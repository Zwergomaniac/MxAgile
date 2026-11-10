"""Read-only Mendix merge preflight, strategy resolver and post-merge integrity gate (MPRv2).

Subcommands (all read-only; nothing here merges, restores, deletes or writes the index):

  preflight         target/source/merge-base(s) -> semantic analysis -> exactly one strategy
  postcheck         integrity gate for a merged model (working tree or revision)
  classify-changes  working tree vs revision: semantic change vs serialization noise

Model comparison is structural on the BSON of every `mprcontents/**/*.mxunit` unit (key order, int32/int64,
list markers and `$ID` churn are normalized; explicit-default noise is reported as a weaker, separate class).
It is never a text diff. Studio Pro remains the Mendix-aware merge engine; Concord is the conflict-resolution
consumer. This tool decides how risky an integration is; it does not perform it.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import sqlite3
import struct
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from git_index_integrity import GIT_TIMEOUT_SECONDS, inspect_index, resolve_repository  # noqa: E402

SCHEMA_PREFLIGHT = "mxagile-mendix-merge-preflight/1"
SCHEMA_POSTCHECK = "mxagile-mendix-merge-postcheck/1"

STUDIO_PRO_MERGE = "STUDIO_PRO_MERGE"
STUDIO_PRO_MERGE_REVIEW = "STUDIO_PRO_MERGE_WITH_TARGETED_CONFLICT_REVIEW"
SEMANTIC_RECONCILIATION = "SEMANTIC_RECONCILIATION"
REPLAY_REQUIRED = "REPLAY_REQUIRED"
BLOCKED = "BLOCKED"
# Names used in earlier contract text; kept as aliases so both vocabularies stay valid.
STRATEGY_ALIAS = {STUDIO_PRO_MERGE: "MERGE_NATIVE", STUDIO_PRO_MERGE_REVIEW: "MERGE_NATIVE_WITH_CONFLICT_REVIEW",
                  SEMANTIC_RECONCILIATION: "SEMANTIC_RECONCILIATION", REPLAY_REQUIRED: "REPLAY_REQUIRED", BLOCKED: "BLOCKED"}

COMPLEX_SHARED_UNITS = 100  # real shared semantic units above this are a complex shared mutation (replay candidate)
REPORT_LIST_CAP = 200
# Effects after a 3-way merge. TARGET_LINE_WINS / SOURCE_LINE_WINS are deterministic for every merge base and harmless;
# BASE_DEPENDENT (criss-cross: the winning line changes with the merge base) is a real conflict.
REAL_DIVERGENCE_EFFECTS = ("DUPLICATE_AFTER_MERGE", "REBUILD_CONFLICT", "BASE_DEPENDENT", "MUTUAL_DELETE")
IGNORED_IDENTITY_TYPES = ("Projects$Folder",)
VAR_PATH = re.compile(r"\$\w+(?:/\w+)+")


class MergeSafetyError(ValueError):
    """Analysis could not be completed; never interpreted as a pass."""


# --------------------------------------------------------------------------- git access (read-only)

def run_git(top: Path, *arguments: str) -> bytes:
    try:
        result = subprocess.run(["git", "--no-optional-locks", "-C", str(top), *arguments], capture_output=True, timeout=GIT_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired as error:
        raise MergeSafetyError("GIT_QUERY_TIMEOUT") from error
    except OSError as error:
        raise MergeSafetyError("GIT_UNAVAILABLE") from error
    if result.returncode:
        raise MergeSafetyError("GIT_QUERY_FAILED: " + os.fsdecode(result.stderr).strip()[:200])
    return result.stdout


def resolve_commit(top: Path, revision: str) -> str:
    return os.fsdecode(run_git(top, "rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}")).strip()


def merge_bases(top: Path, target: str, source: str) -> list[str]:
    result = subprocess.run(["git", "--no-optional-locks", "-C", str(top), "merge-base", "--all", target, source], capture_output=True, timeout=GIT_TIMEOUT_SECONDS)
    if result.returncode not in (0, 1):
        raise MergeSafetyError("GIT_QUERY_FAILED: merge-base")
    return sorted(os.fsdecode(result.stdout).split())


class BlobReader:
    """One persistent `git cat-file --batch` process; strictly read-only."""

    def __init__(self, top: Path):
        self.process = subprocess.Popen(["git", "--no-optional-locks", "-C", str(top), "cat-file", "--batch"],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.cache: dict[str, bytes] = {}

    def read(self, sha: str) -> bytes:
        if sha in self.cache:
            return self.cache[sha]
        assert self.process.stdin and self.process.stdout
        self.process.stdin.write(sha.encode() + b"\n")
        self.process.stdin.flush()
        header = self.process.stdout.readline().split()
        if len(header) < 3 or header[1] != b"blob":
            raise MergeSafetyError("BLOB_UNAVAILABLE " + sha)
        size = int(header[2])
        data = b""
        while len(data) < size:
            chunk = self.process.stdout.read(size - len(data))
            if not chunk:
                raise MergeSafetyError("BLOB_TRUNCATED " + sha)
            data += chunk
        self.process.stdout.read(1)
        self.cache[sha] = data
        return data

    def close(self) -> None:
        try:
            if self.process.stdin:
                self.process.stdin.close()
            self.process.wait(timeout=10)
        except (OSError, subprocess.SubprocessError):
            self.process.kill()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


# --------------------------------------------------------------------------- BSON

def _skip(buffer: bytes, kind: int, i: int) -> int:
    if kind == 0x01 or kind in (0x09, 0x11, 0x12):
        return i + 8
    if kind in (0x02, 0x0D, 0x0E, 0x0F):
        return i + 4 + struct.unpack_from("<i", buffer, i)[0]
    if kind in (0x03, 0x04):
        return i + struct.unpack_from("<i", buffer, i)[0]
    if kind == 0x05:
        return i + 5 + struct.unpack_from("<i", buffer, i)[0]
    if kind == 0x07:
        return i + 12
    if kind == 0x08:
        return i + 1
    if kind in (0x0A, 0xFF, 0x7F):
        return i
    if kind == 0x10:
        return i + 4
    if kind == 0x13:
        return i + 16
    if kind == 0x0B:
        i = buffer.index(0, i) + 1
        return buffer.index(0, i) + 1
    raise ValueError(f"unsupported BSON type {kind:#x}")


def peek(buffer: bytes, wanted: tuple[bytes, ...] = (b"$Type", b"Name")) -> dict[str, str]:
    """Top-level string fields only; nested values are skipped by length."""
    found: dict[str, str] = {}
    try:
        end = struct.unpack_from("<i", buffer, 0)[0] - 1
        i = 4
        while i < end and len(found) < len(wanted):
            kind = buffer[i]
            i += 1
            j = buffer.index(0, i)
            key = buffer[i:j]
            i = j + 1
            if kind == 0x02 and key in wanted:
                n = struct.unpack_from("<i", buffer, i)[0]
                found[key.decode()] = buffer[i + 4:i + 3 + n].decode("utf-8", "replace")
            i = _skip(buffer, kind, i)
    except (ValueError, struct.error, IndexError):
        pass
    return found


def _parse_value(buffer: bytes, kind: int, i: int):
    if kind == 0x01:
        return ("num", struct.unpack_from("<d", buffer, i)[0]), i + 8
    if kind == 0x02:
        n = struct.unpack_from("<i", buffer, i)[0]
        return ("str", buffer[i + 4:i + 3 + n].decode("utf-8", "replace")), i + 4 + n
    if kind in (0x03, 0x04):
        items, end = parse_doc(buffer, i)
        return (("doc", items) if kind == 0x03 else ("arr", [child for _, child in items])), end
    if kind == 0x05:
        n = struct.unpack_from("<i", buffer, i)[0]
        return ("bin", buffer[i + 5:i + 5 + n].hex()), i + 5 + n
    if kind == 0x08:
        return ("bool", buffer[i] == 1), i + 1
    if kind == 0x09:
        return ("date", struct.unpack_from("<q", buffer, i)[0]), i + 8
    if kind == 0x0A:
        return ("null",), i
    if kind == 0x10:
        return ("int", struct.unpack_from("<i", buffer, i)[0]), i + 4
    if kind == 0x12:
        return ("int", struct.unpack_from("<q", buffer, i)[0]), i + 8
    end = _skip(buffer, kind, i)
    return ("raw", kind, buffer[i:end].hex()), end


def parse_doc(buffer: bytes, i: int = 0):
    size = struct.unpack_from("<i", buffer, i)[0]
    end = i + size
    i += 4
    items = []
    while i < end - 1:
        kind = buffer[i]
        i += 1
        j = buffer.index(0, i)
        key = buffer[i:j].decode("utf-8", "replace")
        i = j + 1
        node, i = _parse_value(buffer, kind, i)
        items.append((key, node))
    return items, end


def parse_unit(buffer: bytes):
    return ("doc", parse_doc(buffer)[0])


def _collect_ids(node, out: list[str]) -> None:
    if node[0] == "doc":
        for key, child in sorted(node[1], key=lambda item: item[0]):
            if key == "$ID" and child[0] == "bin":
                out.append(child[1])
            _collect_ids(child, out)
    elif node[0] == "arr":
        for child in node[1]:
            _collect_ids(child, out)


_DEFAULT_VALUES = {("null",), ("bool", False), ("int", 0), ("str", ""), ("arr", ()), ("d", ())}
# Purely geometric properties of graph elements; a change confined to these is presentation, not logic.
PRESENTATION_KEYS = ("Size", "RelativeMiddlePoint", "OriginControlVector", "DestinationControlVector")


def _canon(node, ids: dict[str, int], drop_defaults: bool, strip_presentation: bool = False):
    kind = node[0]
    if kind == "doc":
        items = []
        for key, child in sorted(node[1], key=lambda item: item[0]):
            if key == "$ID" or (strip_presentation and key in PRESENTATION_KEYS):
                continue
            value = _canon(child, ids, drop_defaults, strip_presentation)
            if drop_defaults and value in _DEFAULT_VALUES:
                continue
            items.append((key, value))
        return ("d", tuple(items))
    if kind == "arr":
        items = list(node[1])
        if items and items[0][0] == "int":  # Mendix list-type marker
            items = items[1:]
        return ("arr", tuple(_canon(child, ids, drop_defaults, strip_presentation) for child in items))
    if kind == "bin" and node[1] in ids:
        return ("ref", ids[node[1]])
    return node


# Graph containers whose element order carries no meaning (nodes/edges are connected by id pointers).
# Ordered arrays (widgets, parameters, enumeration values, ...) are intentionally NOT listed.
UNORDERED_GRAPH_KEYS = ("Objects", "Flows")


def _reorder(node, placeholder: dict[str, int], key: str = ""):
    """Sort order-free graph containers by an id-independent shape so equal graphs compare equal."""
    if node[0] == "doc":
        return ("doc", [(child_key, _reorder(child, placeholder, child_key)) for child_key, child in node[1]])
    if node[0] == "arr":
        children = [_reorder(child, placeholder, key) for child in node[1]]
        if key in UNORDERED_GRAPH_KEYS:
            marker = children[:1] if children and children[0][0] == "int" else []
            rest = children[len(marker):]
            rest.sort(key=lambda child: repr(_canon(child, placeholder, True, True)))
            children = marker + rest
        return ("arr", children)
    return node


def _prepare(tree):
    ids: list[str] = []
    _collect_ids(tree, ids)
    first = _reorder(tree, {value: -1 for value in ids})  # pass 1: id-independent shape order
    pass_one: list[str] = []
    _collect_ids(first, pass_one)
    ordered = _reorder(first, {value: index for index, value in enumerate(pass_one)})  # pass 2: ties broken by pointer targets
    final: list[str] = []
    _collect_ids(ordered, final)
    return ordered, {value: index for index, value in enumerate(final)}, set(ids)


def compare_units(a: bytes, b: bytes) -> dict:
    if a == b:
        return {"kind": "BYTE_IDENTICAL", "id_churn": False}
    try:
        tree_a, map_a, ids_a = _prepare(parse_unit(a))
        tree_b, map_b, ids_b = _prepare(parse_unit(b))
    except (ValueError, struct.error, IndexError):
        return {"kind": "UNPARSEABLE", "id_churn": False}
    churn = ids_a != ids_b
    if _canon(tree_a, map_a, False) == _canon(tree_b, map_b, False):
        return {"kind": "SERIALIZATION_ONLY", "id_churn": churn}
    if _canon(tree_a, map_a, True) == _canon(tree_b, map_b, True):
        return {"kind": "DEFAULTS_ONLY", "id_churn": churn}
    if _canon(tree_a, map_a, True, True) == _canon(tree_b, map_b, True, True):
        return {"kind": "PRESENTATION_ONLY", "id_churn": churn}
    return {"kind": "SEMANTIC", "id_churn": churn}


def is_semantic(kind: str) -> bool:
    return kind in ("SEMANTIC", "UNPARSEABLE")


def string_leaves(node, key: str = "", out: set | None = None) -> set:
    out = set() if out is None else out
    if node[0] == "str":
        out.add((key, node[1]))
    elif node[0] == "doc":
        for child_key, child in node[1]:
            string_leaves(child, child_key, out)
    elif node[0] == "arr":
        for child in node[1]:
            string_leaves(child, key, out)
    return out


def guard_findings(a: bytes, b: bytes, markers: tuple[str, ...] = ()) -> dict:
    """Security-relevant competing semantics between two versions of one artifact (target=a, source=b)."""
    findings: list[str] = []
    guards: list[str] = []
    try:
        leaves_a, leaves_b = string_leaves(parse_unit(a)), string_leaves(parse_unit(b))
    except (ValueError, struct.error, IndexError):
        leaves_a, leaves_b = set(), set()
    only_a, only_b = leaves_a - leaves_b, leaves_b - leaves_a
    for literal_side, expression_side in ((only_a, only_b), (only_b, only_a)):
        literal_keys = {key for key, value in literal_side if value.strip().lower() in ("true", "false")}
        for key, value in expression_side:
            if key in literal_keys and VAR_PATH.search(value):
                findings.append("GUARD_COLLAPSE")
                guards.append(value)
    for marker in markers:
        if (marker.encode() in a) != (marker.encode() in b):
            findings.append(f"PROTECTED_MARKER:{marker}")
    kind_a, kind_b = peek(a).get("$Type", ""), peek(b).get("$Type", "")
    if kind_a.startswith("Security$") or kind_b.startswith("Security$"):
        findings.append("SECURITY_TYPE")
    return {"findings": sorted(set(findings)), "guard_expressions": sorted(set(guards)),
            "target_only": sorted(f"{k}={v}"[:160] for k, v in only_a)[:5], "source_only": sorted(f"{k}={v}"[:160] for k, v in only_b)[:5]}


# --------------------------------------------------------------------------- model snapshot

def guid_from_bytes(raw) -> str:
    return str(uuid.UUID(bytes_le=bytes(raw)))


def unit_path(guid: str) -> str:
    return f"mprcontents/{guid[:2]}/{guid[2:4]}/{guid}.mxunit"


def read_mpr(mpr_bytes: bytes) -> dict:
    folder = Path(tempfile.mkdtemp(prefix="mxagile-mpr-"))
    try:
        path = folder / "model.mpr"
        path.write_bytes(mpr_bytes)
        connection = sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True)
        try:
            columns = [row[1] for row in connection.execute("pragma table_info(Unit)")]
            info = {"format": "UNKNOWN", "format_version": None, "product_version": None, "build_version": None, "registry": {}}
            try:
                row = connection.execute("select _FormatVersion,_ProductVersion,_BuildVersion from _MetaData").fetchone()
                if row:
                    info.update(format_version=row[0], product_version=row[1], build_version=row[2])
            except sqlite3.Error:
                pass
            if "ContentsHash" in columns:
                info["format"] = "MPRv2"
                for unit_id, container, containment, digest in connection.execute("select UnitID,ContainerID,ContainmentName,ContentsHash from Unit"):
                    container_guid = guid_from_bytes(container) if isinstance(container, (bytes, bytearray)) and len(container) == 16 else None
                    info["registry"][guid_from_bytes(unit_id)] = {"container": container_guid, "containment": containment, "hash": digest}
            elif "Contents" in columns:
                info["format"] = "MPRv1"
            return info
        finally:
            connection.close()
    except sqlite3.Error as error:
        raise MergeSafetyError(f"MPR_UNREADABLE: {error}") from error
    finally:
        shutil.rmtree(folder, ignore_errors=True)


class Snapshot:
    """Model state of one revision or of the working tree."""

    def __init__(self, label: str, top: Path, reader: BlobReader | None, revision: str | None):
        self.label, self.top, self.reader, self.revision = label, top, reader, revision
        self.mpr_name: str | None = None
        self.mpr_token: str | None = None
        self.info: dict = {"format": "UNKNOWN", "registry": {}}
        self.files: dict[str, object] = {}
        self._meta: dict[str, dict] = {}
        self._identity: dict[str, dict] = {}

    # -- loading
    @classmethod
    def from_git(cls, label: str, top: Path, reader: BlobReader, revision: str) -> "Snapshot":
        snapshot = cls(label, top, reader, revision)
        mprs = []
        for entry in run_git(top, "ls-tree", "-r", "-z", "--full-tree", revision).split(b"\0"):
            if not entry:
                continue
            meta, raw_path = entry.split(b"\t", 1)
            mode, kind, sha = meta.decode().split()
            path = os.fsdecode(raw_path)
            if kind != "blob":
                continue
            if "/" not in path and path.lower().endswith(".mpr"):
                mprs.append((path, sha))
            elif path.startswith("mprcontents/") and path.endswith(".mxunit"):
                name = path.rsplit("/", 1)[1][:-7]
                try:
                    guid = str(uuid.UUID(name))
                except ValueError:
                    guid = name.lower()
                snapshot.files[guid] = sha
        snapshot._finish_mpr(mprs, lambda sha: reader.read(sha))
        return snapshot

    @classmethod
    def from_worktree(cls, label: str, top: Path) -> "Snapshot":
        snapshot = cls(label, top, None, None)
        mprs = [(path.name, path) for path in sorted(top.glob("*.mpr")) if path.is_file()]
        folder = top / "mprcontents"
        if folder.is_dir():
            for path in folder.rglob("*.mxunit"):
                try:
                    guid = str(uuid.UUID(path.stem))
                except ValueError:
                    guid = path.stem.lower()
                snapshot.files[guid] = path
        snapshot._finish_mpr(mprs, lambda path: path.read_bytes())
        return snapshot

    def _finish_mpr(self, mprs: list, reader) -> None:
        if len(mprs) != 1:
            self.info = {"format": "MPR_NOT_UNIQUE" if mprs else "NO_MPR", "registry": {}}
            return
        self.mpr_name, token = mprs[0]
        self.mpr_token = token if isinstance(token, str) else None
        self.info = read_mpr(reader(token))

    # -- accessors
    @property
    def registry(self) -> dict:
        return self.info["registry"]

    @property
    def ids(self) -> set[str]:
        return set(self.registry)

    def token(self, guid: str):
        value = self.files.get(guid)
        return value if isinstance(value, str) else None

    def read(self, guid: str) -> bytes:
        value = self.files[guid]
        return self.reader.read(value) if isinstance(value, str) else Path(value).read_bytes()

    def meta(self, guid: str) -> dict:
        if guid not in self._meta:
            try:
                self._meta[guid] = peek(self.read(guid))
            except (KeyError, OSError, MergeSafetyError):
                self._meta[guid] = {}
        return self._meta[guid]

    def identity(self, guid: str) -> dict:
        if guid not in self._identity:
            meta = self.meta(guid)
            module, current, seen = "", (self.registry.get(guid) or {}).get("container"), set()
            while current and current in self.registry and current not in seen:
                seen.add(current)
                if self.meta(current).get("$Type", "").endswith("ModuleImpl"):
                    module = self.meta(current).get("Name", "")
                    break
                current = self.registry[current]["container"]
            kind, name = meta.get("$Type", ""), meta.get("Name", "")
            display = f"{module}.{name}" if module and name else (name or f"{module}.<{kind.split('$')[-1]}>")
            self._identity[guid] = {"key": f"{kind}|{module}|{name}", "display": display, "type": kind, "unit": guid}
        return self._identity[guid]

    def consistency(self, verify_hashes: bool) -> dict:
        registered, present = set(self.registry), set(self.files)
        missing, orphans = sorted(registered - present), sorted(present - registered)
        mismatches: list[str] = []
        if verify_hashes and self.info["format"] == "MPRv2":
            for guid in sorted(registered & present):
                digest = base64.b64encode(hashlib.sha256(self.read(guid)).digest()).decode()
                if digest != self.registry[guid]["hash"]:
                    mismatches.append(guid)
        return {"consistent": self.info["format"] == "MPRv2" and not (missing or orphans or mismatches),
                "registry_entries": len(registered), "mxunit_files": len(present), "hashes_verified": verify_hashes,
                "missing_units": missing[:REPORT_LIST_CAP], "missing_count": len(missing),
                "orphan_units": orphans[:REPORT_LIST_CAP], "orphan_count": len(orphans),
                "hash_mismatches": mismatches[:REPORT_LIST_CAP], "hash_mismatch_count": len(mismatches)}

    def describe(self) -> dict:
        return {"revision": self.revision, "mpr": self.mpr_name, "mpr_format": self.info["format"], "mpr_format_version": self.info.get("format_version"),
                "product_version": self.info.get("product_version"), "registry_entries": len(self.registry), "mxunit_files": len(self.files)}


class Comparator:
    """Cached unit comparison across snapshots."""

    def __init__(self):
        self.cache: dict[tuple, dict] = {}

    def unit(self, a: Snapshot, b: Snapshot, guid: str) -> dict:
        token_a, token_b = a.token(guid), b.token(guid)
        if token_a and token_b and token_a == token_b:
            return {"kind": "BYTE_IDENTICAL", "id_churn": False}
        key = (token_a, token_b) if token_a and token_b else None
        if key and key in self.cache:
            return self.cache[key]
        result = compare_units(a.read(guid), b.read(guid))
        if key:
            self.cache[key] = result
        return result


def changes_against(side: Snapshot, base: Snapshot, comparator: Comparator) -> dict:
    added = sorted(side.ids - base.ids)
    deleted = sorted(base.ids - side.ids)
    counts = {"SEMANTIC": [], "UNPARSEABLE": [], "SERIALIZATION_ONLY": [], "DEFAULTS_ONLY": [], "PRESENTATION_ONLY": []}
    id_churn = 0
    for guid in sorted(side.ids & base.ids):
        if guid not in side.files or guid not in base.files:
            continue
        verdict = comparator.unit(side, base, guid)
        if verdict["kind"] != "BYTE_IDENTICAL":
            counts[verdict["kind"]].append(guid)
            id_churn += bool(verdict["id_churn"])
    return {"added": added, "deleted": deleted, "semantic": counts["SEMANTIC"] + counts["UNPARSEABLE"], "serialization_only": counts["SERIALIZATION_ONLY"],
            "defaults_only": counts["DEFAULTS_ONLY"], "presentation_only": counts["PRESENTATION_ONLY"], "id_churn_units": id_churn,
            "mpr_changed": side.mpr_token != base.mpr_token if side.mpr_token and base.mpr_token else None}


def summarize_changes(changes: dict) -> dict:
    return {"added": len(changes["added"]), "deleted": len(changes["deleted"]), "semantic": len(changes["semantic"]),
            "serialization_only": len(changes["serialization_only"]), "defaults_only": len(changes["defaults_only"]),
            "presentation_only": len(changes["presentation_only"]),
            "id_churn_units": changes["id_churn_units"], "mpr_changed": changes["mpr_changed"]}


# --------------------------------------------------------------------------- preflight

def version_tuple(value: str | None) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", value or "")[:3])


def entry(snapshot: Snapshot, guid: str) -> dict:
    identity = snapshot.identity(guid)
    return {"unit": guid, "identity": identity["display"], "type": identity["type"]}


def preflight(top: Path, target: str, source: str, base: str | None = None, markers: tuple[str, ...] = (),
              native_reconciliation_failed: bool = False) -> dict:
    target_sha, source_sha = resolve_commit(top, target), resolve_commit(top, source)
    base_shas = [resolve_commit(top, base)] if base else merge_bases(top, target_sha, source_sha)
    report: dict = {"schema": SCHEMA_PREFLIGHT, "read_only": True, "target_rev": target, "source_rev": source, "target": {"sha": target_sha},
                    "source": {"sha": source_sha}, "merge_bases": [{"sha": sha} for sha in base_shas], "criss_cross": len(base_shas) > 1,
                    "protected_markers": list(markers), "blocking_reasons": [], "warnings": [], "reasons": [], "required_actions": []}
    guard = inspect_index(top)
    report["git_index_guard"] = {"state": guard["state"], "mutations_allowed": guard["mutations_allowed"], "index_path": guard.get("index_path")}
    if not guard["mutations_allowed"]:
        report["blocking_reasons"].append(f"GIT_INDEX_GUARD_{guard['state']}")
    if not base_shas:
        report["blocking_reasons"].append("NO_COMMON_ANCESTOR")
        return finish(report, REPLAY_REQUIRED, ["NO_COMMON_ANCESTOR: unrelated histories cannot be merged by Studio Pro"])

    with BlobReader(top) as reader:
        snapshots = {"target": Snapshot.from_git("target", top, reader, target_sha), "source": Snapshot.from_git("source", top, reader, source_sha)}
        bases = [Snapshot.from_git(f"base-{index}", top, reader, sha) for index, sha in enumerate(base_shas)]
        target_snapshot, source_snapshot = snapshots["target"], snapshots["source"]
        report["target"].update(target_snapshot.describe())
        report["source"].update(source_snapshot.describe())
        report["merge_bases"] = [dict(base_snapshot.describe(), sha=sha) for base_snapshot, sha in zip(bases, base_shas)]
        report["registry"] = {"target": target_snapshot.consistency(True), "source": source_snapshot.consistency(True)}
        for label, snapshot in (("target", target_snapshot), ("source", source_snapshot)):
            if not report["registry"][label]["consistent"] and snapshot.info["format"] == "MPRv2":
                report["blocking_reasons"].append(f"REGISTRY_INCONSISTENT_{label.upper()}")
        for index, base_snapshot in enumerate(bases):
            consistency = base_snapshot.consistency(False)
            report["merge_bases"][index]["registry_consistent"] = consistency["consistent"]
            report["merge_bases"][index]["orphan_count"] = consistency["orphan_count"]
            report["merge_bases"][index]["missing_count"] = consistency["missing_count"]
            if base_snapshot.info["format"] == "MPRv2" and not consistency["consistent"]:
                report["warnings"].append(f"HISTORICAL_MERGE_BASE_INCONSISTENT: {base_shas[index][:8]} (orphans={consistency['orphan_count']}, missing={consistency['missing_count']}); inconsistent history is not a blocker for a consistent target/source")

        formats = {snapshot.info["format"] for snapshot in (target_snapshot, source_snapshot, *bases)}
        versions = {snapshot.info.get("product_version") for snapshot in (target_snapshot, source_snapshot)}
        report["model_versions"] = {"target": target_snapshot.info.get("product_version"), "source": source_snapshot.info.get("product_version"),
                                    "bases": [snapshot.info.get("product_version") for snapshot in bases]}
        if formats != {"MPRv2"}:
            report["blocking_reasons"] = [reason for reason in report["blocking_reasons"] if not reason.startswith("REGISTRY_")]
            return finish(report, REPLAY_REQUIRED, [f"MPR_FORMAT_CHANGE: formats seen across target/source/base = {sorted(formats)}; normalize before branching or run a controlled replay"])
        if len({version_tuple(value)[:2] for value in versions}) > 1:
            return finish(report, REPLAY_REQUIRED, [f"MENDIX_VERSION_INCOMPATIBLE: target {sorted(versions)[0]} vs source {sorted(versions)[-1]}"])
        if len(versions) > 1:
            report["warnings"].append(f"MENDIX_PATCH_VERSION_DIFFERS: {sorted(versions, key=str)}")
        if report["blocking_reasons"]:
            return finish(report, BLOCKED, ["Blocking integrity or guard state; fix before any merge"])

        comparator = Comparator()
        target_changes = [changes_against(target_snapshot, base_snapshot, comparator) for base_snapshot in bases]
        source_changes = [changes_against(source_snapshot, base_snapshot, comparator) for base_snapshot in bases]
        report["changes"] = [{"base": sha, "target": summarize_changes(t), "source": summarize_changes(s)} for sha, t, s in zip(base_shas, target_changes, source_changes)]
        report["mpr_changed_on_both_sides"] = all(t["mpr_changed"] and s["mpr_changed"] for t, s in zip(target_changes, source_changes))

        # units that differ between the two heads
        head_noise: list[str] = []
        overlaps: list[dict] = []
        security: list[dict] = []
        for guid in sorted(target_snapshot.ids & source_snapshot.ids):
            if guid not in target_snapshot.files or guid not in source_snapshot.files:
                continue
            between = comparator.unit(target_snapshot, source_snapshot, guid)
            if between["kind"] == "BYTE_IDENTICAL":
                continue
            if not is_semantic(between["kind"]):
                head_noise.append(guid)
                continue
            outcomes = []
            for base_snapshot, t_changes, s_changes in zip(bases, target_changes, source_changes):
                if guid not in base_snapshot.ids:
                    outcomes.append("BOTH")
                    continue
                t_changed, s_changed = guid in t_changes["semantic"], guid in s_changes["semantic"]
                outcomes.append("BOTH" if t_changed and s_changed else "TARGET" if t_changed else "SOURCE" if s_changed else "NOISE")
            base_dependent = len(set(outcomes)) > 1
            if "BOTH" in outcomes or base_dependent:
                item = entry(target_snapshot, guid)
                item.update(outcomes=dict(zip([sha[:8] for sha in base_shas], outcomes)), base_dependent_outcome=base_dependent,
                            conflict="BOTH_SIDES_CHANGED" if "BOTH" in outcomes else "BASE_DEPENDENT_ONE_SIDED")
                overlaps.append(item)
                analysis = guard_findings(target_snapshot.read(guid), source_snapshot.read(guid), markers)
                if analysis["findings"]:
                    security.append({**item, **analysis})
        report["serialization_only_between_heads"] = len(head_noise)

        # delete/modify across heads
        delete_modify: list[dict] = []
        for guid in sorted(target_snapshot.ids - source_snapshot.ids):
            for base_snapshot, t_changes in zip(bases, target_changes):
                if guid in base_snapshot.ids and guid in t_changes["semantic"]:
                    delete_modify.append({**entry(target_snapshot, guid), "modified_on": "target", "deleted_on": "source"})
                    break
        for guid in sorted(source_snapshot.ids - target_snapshot.ids):
            for base_snapshot, s_changes in zip(bases, source_changes):
                if guid in base_snapshot.ids and guid in s_changes["semantic"]:
                    delete_modify.append({**entry(source_snapshot, guid), "modified_on": "source", "deleted_on": "target"})
                    break

        divergences = identity_divergences(target_snapshot, source_snapshot, bases, target_changes, source_changes, markers, security)

        report["shared_semantic_units"] = overlaps[:REPORT_LIST_CAP]
        report["shared_semantic_count"] = len(overlaps)
        report["delete_modify_conflicts"] = delete_modify[:REPORT_LIST_CAP]
        report["identity_divergences"] = divergences
        report["identity_divergence_count"] = len(divergences)
        report["identity_divergence_real_count"] = sum(item["merge_effect"] in REAL_DIVERGENCE_EFFECTS for item in divergences)
        report["security_critical"] = security
        report["protected_marker_locations"] = {marker: sorted({snapshot.identity(guid)["display"] for snapshot in (target_snapshot, source_snapshot)
                                                                  for guid in snapshot.files if marker.encode() in snapshot.read(guid)}) for marker in markers}
        report["concord_scope"] = concord_scope(overlaps, delete_modify, divergences, security, len(head_noise))
        report["expectations_hint"] = "postcheck recomputes expectations from the recorded target/source/base SHAs"
    return resolve(report, overlaps, delete_modify, divergences, security, native_reconciliation_failed)


def identity_divergences(target: Snapshot, source: Snapshot, bases: list[Snapshot], t_changes: list[dict], s_changes: list[dict],
                         markers: tuple[str, ...], security: list[dict]) -> list[dict]:
    only_t, only_s = target.ids - source.ids, source.ids - target.ids
    by_key_t: dict[str, list[str]] = {}
    by_key_s: dict[str, list[str]] = {}
    for snapshot, guids, index in ((target, only_t, by_key_t), (source, only_s, by_key_s)):
        for guid in sorted(guids):
            if guid not in snapshot.files:
                continue
            identity = snapshot.identity(guid)
            if identity["type"] in IGNORED_IDENTITY_TYPES or not identity["type"]:
                continue
            index.setdefault(identity["key"], []).append(guid)
    results = []
    for key in sorted(set(by_key_t) & set(by_key_s)):
        guid_t, guid_s = by_key_t[key][0], by_key_s[key][0]
        effects = []
        for base, tc, sc in zip(bases, t_changes, s_changes):
            in_t, in_s = guid_t in base.ids, guid_s in base.ids
            if not in_t and not in_s:
                effects.append("DUPLICATE_AFTER_MERGE")  # two independent creations: both lines survive
            elif in_s and not in_t:  # source kept the base line, target rebuilt it
                effects.append("REBUILD_CONFLICT" if guid_s in sc["semantic"] else "TARGET_LINE_WINS")
            elif in_t and not in_s:  # target kept the base line, source rebuilt it
                effects.append("REBUILD_CONFLICT" if guid_t in tc["semantic"] else "SOURCE_LINE_WINS")
            else:
                effects.append("MUTUAL_DELETE")  # each side deleted the other's base line
        effect = effects[0] if len(set(effects)) == 1 else "BASE_DEPENDENT"
        content = compare_units(target.read(guid_t), source.read(guid_s))
        item = {"identity": target.identity(guid_t)["display"], "type": target.identity(guid_t)["type"], "target_unit": guid_t, "source_unit": guid_s,
                "merge_effect": effect, "per_base": effects if effect == "BASE_DEPENDENT" else None,
                "content": "IDENTICAL" if content["kind"] in ("BYTE_IDENTICAL", "SERIALIZATION_ONLY", "DEFAULTS_ONLY") else "DIFFERENT",
                "multiplicity": [len(by_key_t[key]), len(by_key_s[key])]}
        if item["content"] == "DIFFERENT" and effect in REAL_DIVERGENCE_EFFECTS:
            analysis = guard_findings(target.read(guid_t), source.read(guid_s), markers)
            if analysis["findings"]:
                item["security_findings"] = analysis["findings"]
                security.append({"unit": guid_t, "source_unit": guid_s, "identity": item["identity"], "type": item["type"], "conflict": "IDENTITY_DIVERGENCE",
                                 "base_dependent_outcome": effect == "BASE_DEPENDENT", **analysis})
        results.append(item)
    return results


def concord_scope(overlaps: list, delete_modify: list, divergences: list, security: list, noise_between_heads: int) -> dict:
    """The targeted conflict scope for Studio Pro conflict resolution / Concord: only genuinely open items, never noise."""
    entries: dict[str, dict] = {}

    def entry_for(kind: str, identity: str, **details) -> dict:
        item = entries.setdefault(f"{kind}|{identity}", {"kind": kind, "identity": identity, "security_findings": [], "decision_required": False})
        item.update(details)
        return item

    for item in overlaps:
        entry_for("SHARED_SEMANTIC", item["identity"], unit=item["unit"], base_dependent=item["base_dependent_outcome"], outcomes=item["outcomes"])
    for item in delete_modify:
        entry_for("DELETE_MODIFY", item["identity"], unit=item["unit"], modified_on=item["modified_on"], deleted_on=item["deleted_on"])
    harmless = 0
    for item in divergences:
        if item["merge_effect"] in REAL_DIVERGENCE_EFFECTS:
            entry_for("IDENTITY_DIVERGENCE", item["identity"], target_unit=item["target_unit"], source_unit=item["source_unit"],
                      merge_effect=item["merge_effect"], content=item["content"], resolution="keep exactly one UUID line, port content, re-point references")
        else:
            harmless += 1
    for item in security:
        kind = "IDENTITY_DIVERGENCE" if item.get("conflict") == "IDENTITY_DIVERGENCE" else "SHARED_SEMANTIC"
        target = entries.get(f"{kind}|{item['identity']}") or entries.get(f"SHARED_SEMANTIC|{item['identity']}") or entry_for("SECURITY_DECISION", item["identity"], unit=item["unit"])
        target["security_findings"] = item["findings"]
        target["decision_required"] = True
        target["guard_expressions"] = item.get("guard_expressions", [])
    items = sorted(entries.values(), key=lambda value: (value["kind"], value["identity"]))
    return {"in_scope": items[:REPORT_LIST_CAP], "in_scope_count": len(items),
            "decisions_required": sum(item["decision_required"] for item in items),
            "out_of_scope": {"serialization_noise_units_between_heads": noise_between_heads, "deterministic_identity_replacements": harmless},
            "note": "Only in_scope items are handed to Studio Pro conflict resolution / Concord. Serialization noise and deterministic replacements are not conflicts."}


def resolve(report: dict, overlaps: list, delete_modify: list, divergences: list, security: list, native_failed: bool) -> dict:
    actions = report["required_actions"]
    reasons: list[str] = []
    if report["criss_cross"]:
        report["warnings"].append(f"CRISS_CROSS_HISTORY: {len(report['merge_bases'])} merge bases; a single merge base must not decide any conflicting unit")
    if security:
        actions.append({"action": "SECURITY_DECISION_REQUIRED", "count": len(security), "policy": "EXPLICIT_DECISION; no merge base or merge order may decide competing security semantics",
                        "units": [{"identity": item["identity"], "findings": item["findings"], "guard_expressions": item["guard_expressions"]} for item in security]})
    real_divergences = [item for item in divergences if item["merge_effect"] in REAL_DIVERGENCE_EFFECTS]
    if divergences:
        actions.append({"action": "IDENTITY_RECONCILIATION", "count": len(divergences), "real_after_merge": len(real_divergences),
                        "identities": [{"identity": item["identity"], "merge_effect": item["merge_effect"], "content": item["content"]} for item in divergences]})
    rebuild = [item for item in divergences if item["merge_effect"] == "REBUILD_CONFLICT"]
    if native_failed:
        reasons.append("NATIVE_RECONCILIATION_EVIDENCED_INSUFFICIENT")
        strategy = REPLAY_REQUIRED
    elif len(overlaps) > COMPLEX_SHARED_UNITS:
        reasons.append(f"COMPLEX_SHARED_MUTATION: {len(overlaps)} real shared semantic units > {COMPLEX_SHARED_UNITS}")
        strategy = REPLAY_REQUIRED
    elif rebuild:
        reasons.append(f"REBUILD_CONFLICT: {len(rebuild)} artifact(s) rebuilt on one side while the base line was semantically modified on the other")
        strategy = SEMANTIC_RECONCILIATION
    elif overlaps or delete_modify or real_divergences or security:
        if overlaps:
            reasons.append(f"SHARED_SEMANTIC_UNITS: {len(overlaps)}")
        if delete_modify:
            reasons.append(f"DELETE_MODIFY_CONFLICTS: {len(delete_modify)}")
        if real_divergences:
            reasons.append(f"IDENTITY_DIVERGENCE: {len(real_divergences)} artifact(s) exist as two UUID lines")
        if security:
            reasons.append(f"SECURITY_CRITICAL_CONFLICTS: {len(security)}")
        strategy = STUDIO_PRO_MERGE_REVIEW
    else:
        if report.get("mpr_changed_on_both_sides"):
            reasons.append("MPR_CHANGED_ON_BOTH_SIDES is registry bookkeeping; no overlapping semantic units")
        strategy = STUDIO_PRO_MERGE
    return finish(report, strategy, reasons)


def finish(report: dict, strategy: str, reasons: list[str]) -> dict:
    report["strategy"] = strategy
    report["strategy_alias"] = STRATEGY_ALIAS[strategy]
    report["reasons"] = reasons
    report["next_step"] = {STUDIO_PRO_MERGE: "Studio Pro: Merge Changes Here, then run postcheck.",
                           STUDIO_PRO_MERGE_REVIEW: "Studio Pro: Merge Changes Here; resolve only the listed conflicts (Concord for analysis/resolution); record security and identity decisions; then run postcheck.",
                           SEMANTIC_RECONCILIATION: "Reconcile the listed artifacts semantically (restore the stable line, port the missing modification) before or during the merge; then run postcheck.",
                           REPLAY_REQUIRED: "Replay is required (fallback): normalize the model baseline or replay the source MDL on the target model; document the evidence.",
                           BLOCKED: "Do not merge. Repair the blocking state first."}[strategy]
    return report


# --------------------------------------------------------------------------- postcheck

def expectations(target: Snapshot, source: Snapshot, bases: list[Snapshot], comparator: Comparator) -> dict:
    present: set[str] = set()
    absent: set[str] = set()
    either: set[str] = set()
    added_target: set[str] = set()
    added_source: set[str] = set()
    for guid in target.ids | source.ids:
        in_t, in_s = guid in target.ids, guid in source.ids
        if in_t and in_s:
            present.add(guid)
            continue
        holder, other = (target, source) if in_t else (source, target)
        verdicts = set()
        for base in bases:
            if guid not in base.ids:
                verdicts.add("ADDED")
            elif guid in holder.files and guid in base.files and is_semantic(comparator.unit(holder, base, guid)["kind"]):
                verdicts.add("DELETE_MODIFY")
            else:
                verdicts.add("CLEAN_DELETE")
        if verdicts == {"ADDED"}:
            present.add(guid)
            (added_target if in_t else added_source).add(guid)
        elif verdicts == {"CLEAN_DELETE"}:
            absent.add(guid)
        else:
            either.add(guid)
    return {"present": present, "absent": absent, "either": either, "added_target": added_target, "added_source": added_source}


POSTCHECK_STAGES = ("studio-pro-merge", "concord-resolution", "final")


def postcheck(top: Path, revision: str | None = None, preflight_report: dict | None = None, markers: tuple[str, ...] = (),
              accepted: tuple[str, ...] = (), stage: str = "final") -> dict:
    """Integrity gate. `studio-pro-merge` tolerates the open Concord scope (reported as OPEN); `concord-resolution` and `final` do not.
    Only `final` can produce `final_integrity_gate: PASS` (the evidence commit-authority.md asks for)."""
    if stage not in POSTCHECK_STAGES:
        raise MergeSafetyError(f"UNKNOWN_STAGE {stage}")
    pending = "OPEN" if stage == "studio-pro-merge" else "FAIL"
    report: dict = {"schema": SCHEMA_POSTCHECK, "read_only": True, "subject": revision or "WORKTREE", "stage": stage, "checks": [],
                    "accepted_security_decisions": list(accepted), "remaining_scope": []}
    checks = report["checks"]

    def add(name: str, status: str, detail=None):
        checks.append({"check": name, "status": status, "detail": detail})

    unmerged = run_git(top, "ls-files", "-u", "-z").strip(b"\0")
    in_progress = Path(os.fsdecode(run_git(top, "rev-parse", "--path-format=absolute", "--git-path", "MERGE_HEAD")).strip()).exists()
    if unmerged and revision is None:
        add("merge_conflicts_resolved", "FAIL", "unmerged index entries exist; the merge is not finished")
    elif in_progress and revision is None:
        add("merge_conflicts_resolved", "PASS", "merge in progress (uncommitted): this is the pre-commit evidence for the merge commit")
    else:
        add("merge_conflicts_resolved", "PASS")

    with BlobReader(top) as reader:
        result = Snapshot.from_git("result", top, reader, resolve_commit(top, revision)) if revision else Snapshot.from_worktree("result", top)
        report["model"] = result.describe()
        consistency = result.consistency(True)
        report["registry"] = consistency
        add("mpr_mxunit_consistent", "PASS" if consistency["consistent"] else "FAIL",
            None if consistency["consistent"] else {k: consistency[k] for k in ("registry_entries", "mxunit_files", "missing_count", "orphan_count", "hash_mismatch_count")})

        groups: dict[str, list[str]] = {}
        for guid in result.ids & set(result.files):
            identity = result.identity(guid)
            if identity["type"] and identity["type"] not in IGNORED_IDENTITY_TYPES:
                groups.setdefault(identity["key"], []).append(guid)
        duplicates = {key: guids for key, guids in groups.items() if len(guids) > 1}
        report["duplicate_identities"] = [{"identity": result.identity(guids[0])["display"], "units": guids} for guids in duplicates.values()][:REPORT_LIST_CAP]
        add("no_duplicate_artifact_names", pending if duplicates else "PASS", len(duplicates) or None)
        report["remaining_scope"] += [{"kind": "IDENTITY_DIVERGENCE", "identity": found["identity"]} for found in report["duplicate_identities"]]

        derived: list[str] = []
        if preflight_report:
            for item in preflight_report.get("security_critical", []):
                derived += item.get("guard_expressions", [])
        protected = sorted(set(markers) | set(derived))
        identity_keys = {guid: result.identity(guid)["key"] for guid in result.files}
        if preflight_report:
            target_sha, source_sha = preflight_report["target"]["sha"], preflight_report["source"]["sha"]
            base_shas = [item["sha"] for item in preflight_report["merge_bases"]]
            target, source = Snapshot.from_git("target", top, reader, target_sha), Snapshot.from_git("source", top, reader, source_sha)
            bases = [Snapshot.from_git(f"base-{i}", top, reader, sha) for i, sha in enumerate(base_shas)]
            expected = expectations(target, source, bases, Comparator())
            result_keys = set(identity_keys.values())

            def survives(guid: str, holder: Snapshot) -> bool:
                return guid in result.ids or (guid in holder.files and holder.identity(guid)["key"] in result_keys)

            lost = [guid for guid in sorted(expected["present"]) if not survives(guid, target if guid in target.files else source)]
            report["lost_units"] = [{**entry(target if guid in target.files else source, guid), "restore_from": (target_sha if guid in target.files else source_sha), "restore_path": unit_path(guid)} for guid in lost][:REPORT_LIST_CAP]
            add("no_lost_units", "FAIL" if lost else "PASS", len(lost) or None)
            features = {"target": [g for g in expected["added_target"] if not survives(g, target)], "source": [g for g in expected["added_source"] if not survives(g, source)]}
            report["expected_features"] = {"target_added": len(expected["added_target"]), "source_added": len(expected["added_source"]),
                                           "target_missing": len(features["target"]), "source_missing": len(features["source"])}
            add("expected_features_of_both_branches_present", "FAIL" if features["target"] or features["source"] else "PASS", report["expected_features"])
            # decisions: competing security semantics must keep the guard unless explicitly accepted
            unresolved = []
            for item in preflight_report.get("security_critical", []):
                if item["identity"] in accepted:
                    continue
                guards = item.get("guard_expressions", [])
                keys = {identity_keys.get(guid) for guid in (item["unit"], item.get("source_unit")) if guid}
                holders = [guid for guid, key in identity_keys.items() if key in keys or guid in (item["unit"], item.get("source_unit"))]
                if guards and not any(any(g.encode() in result.read(guid) for g in guards) for guid in holders):
                    unresolved.append({"identity": item["identity"], "lost_guard": guards})
            add("security_decisions_resolved", pending if unresolved else "PASS", unresolved or None)
            report["remaining_scope"] += [{"kind": "SECURITY_DECISION", "identity": item["identity"]} for item in unresolved]
        else:
            add("no_lost_units", "NOT_CHECKED", "no preflight report: expectations unavailable")
            add("expected_features_of_both_branches_present", "NOT_CHECKED", "no preflight report: expectations unavailable")
            add("security_decisions_resolved", "NOT_CHECKED", "no preflight report: security decisions unavailable")

        if protected:
            lost_markers = []
            holder_keys: dict[str, set[str]] = {}
            subjects = [(preflight_report["target"]["sha"], preflight_report["source"]["sha"])] if preflight_report else []
            if subjects:
                for sha in subjects[0]:
                    snap = Snapshot.from_git("head", top, reader, sha)
                    for guid in snap.files:
                        raw = snap.read(guid)
                        for marker in protected:
                            if marker.encode() in raw:
                                holder_keys.setdefault(marker, set()).add(snap.identity(guid)["key"])
            for marker in protected:
                needed = holder_keys.get(marker, set())
                have = {identity_keys[guid] for guid in result.files if marker.encode() in result.read(guid)}
                for key in sorted(needed - have):
                    display = key.split("|")[1] + "." + key.split("|")[2]
                    if display not in accepted:
                        lost_markers.append({"marker": marker, "identity": display})
                if not needed and not subjects and not any(marker.encode() in result.read(guid) for guid in result.files):
                    lost_markers.append({"marker": marker, "identity": "<any>"})
            add("protected_markers_preserved", pending if lost_markers else "PASS", lost_markers or None)
            report["remaining_scope"] += [{"kind": "PROTECTED_MARKER", "identity": item["identity"], "marker": item["marker"]} for item in lost_markers]
        else:
            add("protected_markers_preserved", "NOT_APPLICABLE", "no protected markers declared or derived")
    statuses = {check["status"] for check in checks}
    report["state"] = "FAIL" if "FAIL" in statuses else "INCOMPLETE" if "NOT_CHECKED" in statuses else "OPEN_ITEMS" if "OPEN" in statuses else "PASS"
    scope = (preflight_report or {}).get("concord_scope")
    if scope is not None:
        open_keys = {(item["kind"], item["identity"]) for item in report["remaining_scope"]}
        diverged = [item for item in scope["in_scope"] if item["kind"] == "IDENTITY_DIVERGENCE"]
        report["scope"] = {"in_scope": scope["in_scope_count"], "decisions_required": scope["decisions_required"],
                           "identity_divergences_open": sum(("IDENTITY_DIVERGENCE", item["identity"]) in open_keys for item in diverged),
                           "identity_divergences_total": len(diverged),
                           "shared_semantic_units": sum(item["kind"] == "SHARED_SEMANTIC" for item in scope["in_scope"]),
                           "shared_semantic_content_machine_verified": False,
                           "note": "Presence, registry consistency, identity and guard retention are machine-verified; the semantic correctness of manually resolved shared units is not."}
    report["ready_for_final"] = report["state"] == "PASS"
    report["final_integrity_gate"] = "PASS" if report["state"] == "PASS" and stage == "final" else "NOT_PASSED"
    return report


# --------------------------------------------------------------------------- classify-changes (noise vs semantic)

def classify_worktree(top: Path, base: str) -> dict:
    with BlobReader(top) as reader:
        base_snapshot = Snapshot.from_git("base", top, reader, resolve_commit(top, base))
        work = Snapshot.from_worktree("worktree", top)
        counts = {"BYTE_IDENTICAL": 0, "SERIALIZATION_ONLY": 0, "DEFAULTS_ONLY": 0, "PRESENTATION_ONLY": 0, "SEMANTIC": 0, "UNPARSEABLE": 0}
        id_churn = 0
        semantic, noise = [], []
        for guid in sorted(set(base_snapshot.files) & set(work.files)):
            verdict = compare_units(base_snapshot.read(guid), work.read(guid))
            counts[verdict["kind"]] += 1
            id_churn += bool(verdict["id_churn"])
            (semantic if is_semantic(verdict["kind"]) else noise if verdict["kind"] != "BYTE_IDENTICAL" else []).append(entry(base_snapshot, guid)["identity"])
        return {"schema": "mxagile-mendix-change-classification/1", "read_only": True, "base": base_snapshot.revision, "units_compared": sum(counts.values()),
                "counts": counts, "id_churn_units": id_churn, "added_units": len(set(work.files) - set(base_snapshot.files)),
                "deleted_units": len(set(base_snapshot.files) - set(work.files)), "semantic_units": semantic[:REPORT_LIST_CAP], "noise_units": noise[:REPORT_LIST_CAP],
                "note": "DEFAULTS_ONLY (explicit default values) and PRESENTATION_ONLY (geometry) are weaker normalizations than SERIALIZATION_ONLY; they are reported separately, never hidden."}


# --------------------------------------------------------------------------- CLI

def render_text(report: dict) -> str:
    lines = [f"STRATEGY: {report.get('strategy')} ({report.get('strategy_alias')})"]
    lines += [f"  reason: {reason}" for reason in report.get("reasons", [])]
    lines += [f"  BLOCKING: {reason}" for reason in report.get("blocking_reasons", [])]
    lines += [f"  warning: {reason}" for reason in report.get("warnings", [])]
    lines.append(f"  criss-cross: {report.get('criss_cross')}  merge bases: {len(report.get('merge_bases', []))}  mpr changed on both sides: {report.get('mpr_changed_on_both_sides')}")
    for change in report.get("changes", []):
        lines.append(f"  vs base {change['base'][:8]}: target {change['target']}  source {change['source']}")
    lines.append(f"  shared semantic units: {report.get('shared_semantic_count')}  identity divergences: {report.get('identity_divergence_real_count')} real / {report.get('identity_divergence_count')} total  security-critical: {len(report.get('security_critical', []))}")
    lines.append(f"  next: {report.get('next_step')}")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, help="Write the full JSON report here (outside the repository index).")
    parser.add_argument("--format", choices=("json", "text"), default="json")
    commands = parser.add_subparsers(dest="command", required=True)
    pre = commands.add_parser("preflight")
    pre.add_argument("--target", default="HEAD")
    pre.add_argument("--source", required=True)
    pre.add_argument("--base")
    pre.add_argument("--protected-marker", action="append", default=[])
    pre.add_argument("--native-reconciliation-failed", action="store_true", help="Evidence that Studio Pro/Concord reconciliation was insufficient.")
    post = commands.add_parser("postcheck")
    post.add_argument("--rev")
    post.add_argument("--preflight", type=Path)
    post.add_argument("--protected-marker", action="append", default=[])
    post.add_argument("--accept-security-decision", action="append", default=[], metavar="IDENTITY")
    post.add_argument("--stage", choices=POSTCHECK_STAGES, default="final", help="studio-pro-merge tolerates the open Concord scope; concord-resolution and final do not.")
    noise = commands.add_parser("classify-changes")
    noise.add_argument("--base", default="HEAD")
    args = parser.parse_args()
    try:
        repository = resolve_repository(args.project_root.resolve())
        if repository is None:
            raise MergeSafetyError("NO_GIT_WORKTREE")
        top = Path(repository["top_level"])
        if args.command == "preflight":
            report = preflight(top, args.target, args.source, args.base, tuple(args.protected_marker), args.native_reconciliation_failed)
            code = 4 if report["strategy"] == BLOCKED else 0
        elif args.command == "postcheck":
            prior = json.loads(args.preflight.read_text(encoding="utf-8")) if args.preflight else None
            report = postcheck(top, args.rev, prior, tuple(args.protected_marker), tuple(args.accept_security_decision), args.stage)
            code = 0 if report["state"] == "PASS" else 5 if report["state"] == "OPEN_ITEMS" else 4
        else:
            report = classify_worktree(top, args.base)
            code = 0
    except (MergeSafetyError, OSError, ValueError, KeyError, sqlite3.Error) as error:
        report = {"read_only": True, "state": "ANALYSIS_UNAVAILABLE", "reason": str(error) or type(error).__name__}
        code = 3
    if args.output:
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(render_text(report) if args.format == "text" and "strategy" in report else json.dumps(report, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
