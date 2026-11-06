"""Deterministic Git range and Change-Set verification for reconciliation."""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Any

from jsonschema import Draft7Validator


CHANGE_SET_SCHEMA = "change-set.schema.json"
CHANGE_SET_DIRECTORY = "planning/reconciliation/change-sets"
CHANGE_SET_ID_PATTERN = re.compile(r"^CS-[A-Za-z0-9._-]+$")
ORIGIN_VALUE = "mxagile"


class GitReconciliationError(ValueError):
    pass


def _run_git(root: Path, *args: str, input_bytes: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", "--no-optional-locks", "-C", str(root), *args],
        input=input_bytes,
        capture_output=True,
        check=False,
    )


def _git(root: Path, *args: str) -> bytes:
    result = _run_git(root, *args)
    if result.returncode:
        raise GitReconciliationError("GIT_QUERY_FAILED")
    return result.stdout


def _git_text(root: Path, *args: str) -> str:
    return os.fsdecode(_git(root, *args)).strip()


def _raw_changes(raw: bytes) -> dict[str, str]:
    parts = raw.split(b"\0")
    changes: dict[str, str] = {}
    index = 0
    while index < len(parts):
        record = parts[index]
        if not record:
            index += 1
            continue
        if b"\t" in record:
            metadata, raw_path = record.split(b"\t", 1)
            index += 1
        else:
            if index + 1 >= len(parts):
                break
            metadata, raw_path = record, parts[index + 1]
            index += 2
        if not metadata or not raw_path:
            continue
        fields = metadata.decode("ascii", errors="strict").split()
        if not fields:
            continue
        status = fields[-1]
        if len(status) != 1:
            raise GitReconciliationError("RENAME_OR_COPY_STATUS_UNEXPECTED")
        changes[os.fsdecode(raw_path)] = status
    return changes


def working_tree_changes(root: Path) -> dict[str, list[dict[str, str]]]:
    staged = _raw_changes(_git(root, "diff", "--cached", "--raw", "-z", "--no-renames", "--no-abbrev", "HEAD", "--"))
    unstaged = _raw_changes(_git(root, "diff", "--raw", "-z", "--no-renames", "--no-abbrev", "--"))
    untracked = [
        os.fsdecode(path)
        for path in _git(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
        if path
    ]
    return {
        "staged": [{"path": path, "status": status} for path, status in sorted(staged.items())],
        "unstaged": [{"path": path, "status": status} for path, status in sorted(unstaged.items())],
        "untracked": [{"path": path, "status": "A"} for path in sorted(untracked)],
    }


def _commit_parents(root: Path, commit: str) -> list[str]:
    fields = _git_text(root, "rev-list", "--parents", "-n", "1", commit).split()
    if not fields or fields[0] != commit:
        raise GitReconciliationError("COMMIT_PARENT_QUERY_FAILED")
    return fields[1:]


def _tree_entry(root: Path, tree: str, path: str) -> dict[str, str] | None:
    literal_path = f":(literal){path}"
    raw = _git(root, "ls-tree", "-r", "-z", "--full-tree", tree, "--", literal_path)
    for entry in raw.split(b"\0"):
        if not entry:
            continue
        try:
            metadata, entry_path = entry.split(b"\t", 1)
            mode, object_type, object_id = metadata.decode("ascii").split()
        except (ValueError, UnicodeError):
            raise GitReconciliationError("TREE_ENTRY_INVALID") from None
        if os.fsdecode(entry_path) == path:
            return {"mode": mode, "type": object_type, "oid": object_id}
    return None


def _index_entry(root: Path, path: str) -> dict[str, str] | None:
    raw = _git(root, "ls-files", "--stage", "-z", "--", f":(literal){path}")
    entries = [item for item in raw.split(b"\0") if item]
    if not entries:
        return None
    if len(entries) != 1:
        raise GitReconciliationError("INDEX_PATH_HAS_MULTIPLE_STAGES")
    try:
        metadata, entry_path = entries[0].split(b"\t", 1)
        mode, object_id, stage = metadata.decode("ascii").split()
    except (ValueError, UnicodeError):
        raise GitReconciliationError("INDEX_ENTRY_INVALID") from None
    if os.fsdecode(entry_path) != path or stage != "0":
        raise GitReconciliationError("INDEX_PATH_UNMERGED")
    return {"mode": mode, "type": "blob", "oid": object_id}


def _diff_paths(root: Path, parent: str | None, commit: str) -> dict[str, str]:
    if parent is None:
        raw = _git(root, "diff-tree", "--root", "--raw", "-z", "--no-renames", "--no-abbrev", "-r", commit, "--")
    else:
        raw = _git(root, "diff-tree", "--raw", "-z", "--no-renames", "--no-abbrev", "-r", parent, commit, "--")
    return _raw_changes(raw)


def _raw_entries(raw: bytes) -> dict[str, tuple[dict[str, str] | None, dict[str, str] | None]]:
    """Parse `diff-tree --raw -z --no-abbrev` into (before, after) tree entries per path."""
    parts = raw.split(b"\0")
    entries: dict[str, tuple[dict[str, str] | None, dict[str, str] | None]] = {}
    index = 0
    while index < len(parts):
        record = parts[index]
        if not record:
            index += 1
            continue
        if b"\t" in record:
            metadata, raw_path = record.split(b"\t", 1)
            index += 1
        else:
            if index + 1 >= len(parts):
                break
            metadata, raw_path = record, parts[index + 1]
            index += 2
        if not metadata.startswith(b":") or not raw_path:
            continue
        fields = metadata[1:].decode("ascii", errors="strict").split()
        if len(fields) != 5 or len(fields[4]) != 1:
            raise GitReconciliationError("RENAME_OR_COPY_STATUS_UNEXPECTED")
        old_mode, new_mode, old_oid, new_oid, _status = fields

        def entry(mode: str, oid: str) -> dict[str, str] | None:
            if set(mode) == {"0"}:
                return None
            object_type = "commit" if mode == "160000" else "tree" if mode == "040000" else "blob"
            return {"mode": mode, "type": object_type, "oid": oid}

        entries[os.fsdecode(raw_path)] = (entry(old_mode, old_oid), entry(new_mode, new_oid))
    return entries


def _batched_parents(root: Path, commits: list[str]) -> dict[str, list[str]]:
    """Parents for many commits in one git process."""
    if not commits:
        return {}
    raw = _run_git(root, "rev-list", "--no-walk=unsorted", "--parents", "--stdin",
                   input_bytes=("\n".join(commits) + "\n").encode("ascii"))
    if raw.returncode:
        raise GitReconciliationError("COMMIT_PARENT_QUERY_FAILED")
    result: dict[str, list[str]] = {}
    for line in raw.stdout.decode("ascii", errors="strict").splitlines():
        fields = line.split()
        if fields:
            result[fields[0]] = fields[1:]
    if set(result) != set(commits):
        raise GitReconciliationError("COMMIT_PARENT_QUERY_FAILED")
    return result


def _batched_messages(root: Path, commits: list[str]) -> dict[str, bytes]:
    """Raw commit messages for many commits in one git process."""
    if not commits:
        return {}
    raw = _run_git(root, "log", "--no-walk=unsorted", "--stdin", "--format=%H%x00%B%x00%x01",
                   input_bytes=("\n".join(commits) + "\n").encode("ascii"))
    if raw.returncode:
        raise GitReconciliationError("COMMIT_MESSAGE_QUERY_FAILED")
    result: dict[str, bytes] = {}
    for record in raw.stdout.split(b"\x00\x01"):
        record = record.lstrip(b"\n")
        if not record:
            continue
        commit, _, message = record.partition(b"\x00")
        result[commit.decode("ascii").strip()] = message
    if set(result) != set(commits):
        raise GitReconciliationError("COMMIT_MESSAGE_QUERY_FAILED")
    return result


def _semantic_status(before: dict[str, str] | None, after: dict[str, str] | None) -> str | None:
    if before == after:
        return None
    if before is None:
        return "A"
    if after is None:
        return "D"
    return "M"


def _commit_changes(root: Path, commit: str, parents: list[str]) -> dict[str, dict[str, Any]]:
    if len(parents) <= 1:
        # diff-tree already reports the exact before/after tree entries for root and
        # single-parent commits; no per-path ls-tree lookups are required.
        if parents:
            raw = _git(root, "diff-tree", "--raw", "-z", "--no-renames", "--no-abbrev", "-r", parents[0], commit, "--")
        else:
            raw = _git(root, "diff-tree", "--root", "--raw", "-z", "--no-renames", "--no-abbrev", "-r", commit, "--")
        result: dict[str, dict[str, Any]] = {}
        for path, (before, after) in sorted(_raw_entries(raw).items()):
            status = _semantic_status(before, after)
            if status is not None:
                result[path] = {"status": status, "before": before, "after": after}
        return result
    # Merge commit: one diff-tree per parent already reports the exact before/after entries.
    # A path absent from a parent's diff is unchanged relative to that parent, so that parent's
    # entry equals the commit's entry (the "inherited" case, which is skipped as before).
    per_parent = [
        _raw_entries(_git(root, "diff-tree", "--raw", "-z", "--no-renames", "--no-abbrev", "-r", parent, commit, "--"))
        for parent in parents
    ]
    result = {}
    for path in sorted({path for diff in per_parent for path in diff}):
        after = next((diff[path][1] for diff in per_parent if path in diff), None)
        parent_entries = [diff[path][0] if path in diff else after for diff in per_parent]
        if after in parent_entries:
            continue
        before = parent_entries[0]
        status = _semantic_status(before, after)
        if status is not None:
            result[path] = {"status": status, "before": before, "after": after}
    return result


def _commit_changes_by_tree_lookup(root: Path, commit: str, parents: list[str]) -> dict[str, dict[str, Any]]:
    if not parents:
        paths = _diff_paths(root, None, commit)
    elif len(parents) == 1:
        paths = _diff_paths(root, parents[0], commit)
    else:
        paths = {}
        for parent in parents:
            paths.update(_diff_paths(root, parent, commit))

    commit_tree = _git_text(root, "rev-parse", f"{commit}^{{tree}}")
    result: dict[str, dict[str, Any]] = {}
    for path in sorted(paths):
        after = _tree_entry(root, commit_tree, path)
        parent_entries = [
            _tree_entry(root, _git_text(root, "rev-parse", f"{parent}^{{tree}}"), path)
            for parent in parents
        ]
        if len(parents) > 1 and after in parent_entries:
            continue
        before = parent_entries[0] if parent_entries else None
        status = _semantic_status(before, after)
        if status is not None:
            result[path] = {"status": status, "before": before, "after": after}
    return result


def _trailers(root: Path, commit: str, message: bytes | None = None) -> tuple[dict[str, list[str]], bool]:
    if message is None:
        message = _git(root, "show", "-s", "--format=%B", commit)
    if b"mxagile-" not in message.lower():
        # interpret-trailers can only yield mxagile-* keys that appear in the message.
        return {}, False
    parsed = _run_git(root, "interpret-trailers", "--parse", input_bytes=message)
    if parsed.returncode:
        raise GitReconciliationError("COMMIT_TRAILERS_UNREADABLE")
    values: dict[str, list[str]] = defaultdict(list)
    for raw_line in parsed.stdout.splitlines():
        if b":" not in raw_line:
            continue
        raw_key, raw_value = raw_line.split(b":", 1)
        key = raw_key.decode("utf-8", errors="replace").strip().casefold()
        if key.startswith("mxagile-"):
            values[key].append(raw_value.decode("utf-8", errors="replace").strip())
    return dict(values), bool(values)


def _change_set_schema(root: Path) -> dict[str, Any]:
    schema_path = root / ".mxagile/schemas" / CHANGE_SET_SCHEMA
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8-sig"))
        Draft7Validator.check_schema(schema)
    except (OSError, ValueError, TypeError):
        raise GitReconciliationError("CHANGE_SET_SCHEMA_UNAVAILABLE") from None
    return schema


def _load_change_set(root: Path, commit: str, change_set_id: str) -> dict[str, Any]:
    if not CHANGE_SET_ID_PATTERN.fullmatch(change_set_id):
        raise GitReconciliationError("CHANGE_SET_ID_INVALID")
    path = f"{CHANGE_SET_DIRECTORY}/{change_set_id}.json"
    tree = _git_text(root, "rev-parse", f"{commit}^{{tree}}")
    entry = _tree_entry(root, tree, path)
    if entry is None or entry["type"] != "blob":
        raise GitReconciliationError("CHANGE_SET_MISSING_FROM_COMMIT")
    raw = _git(root, "show", f"{commit}:{path}")
    if len(raw) > 1024 * 1024:
        raise GitReconciliationError("CHANGE_SET_TOO_LARGE")
    try:
        value = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeError, ValueError):
        raise GitReconciliationError("CHANGE_SET_INVALID_JSON") from None
    errors = list(Draft7Validator(_change_set_schema(root)).iter_errors(value))
    if errors:
        raise GitReconciliationError("CHANGE_SET_SCHEMA_INVALID")
    return value


def _verify_change_set(
    root: Path,
    commit: str,
    parents: list[str],
    changes: dict[str, dict[str, Any]],
    trailers: dict[str, list[str]],
) -> tuple[bool, str | None, set[str]]:
    required_keys = ("mxagile-origin", "mxagile-mission", "mxagile-change-set")
    if any(len(trailers.get(key, [])) != 1 for key in required_keys):
        return False, "TRAILER_MISSING_OR_CONFLICTING", set()
    origin, mission_id, change_set_id = (trailers[key][0] for key in required_keys)
    if origin.casefold() != ORIGIN_VALUE or not CHANGE_SET_ID_PATTERN.fullmatch(change_set_id):
        return False, "TRAILER_VALUE_INVALID", set()
    try:
        change_set = _load_change_set(root, commit, change_set_id)
    except GitReconciliationError as exc:
        return False, str(exc), set()
    if change_set["mission_id"] != mission_id or change_set["change_set_id"] != change_set_id:
        return False, "TRAILER_MANIFEST_ID_MISMATCH", set()
    if change_set["parent_commits"] != parents:
        return False, "PARENT_LIST_MISMATCH", set()
    manifest_path = f"{CHANGE_SET_DIRECTORY}/{change_set_id}.json"
    if manifest_path not in changes:
        return False, "CHANGE_SET_NOT_CREATED_IN_COMMIT", set()
    declared_paths: set[str] = set()
    for item in change_set["paths"]:
        path = item["path"]
        if path in declared_paths or path == manifest_path:
            return False, "CHANGE_SET_PATH_DUPLICATE_OR_RESERVED", set()
        declared_paths.add(path)
        actual = changes.get(path)
        if actual is None:
            return False, "CHANGE_SET_PATH_NOT_CHANGED", set()
        before = actual["before"]
        after = actual["after"]
        if actual["status"] != item["status"]:
            return False, "CHANGE_SET_STATUS_MISMATCH", set()
        if (before or {}).get("oid") != item["before_blob"] or (after or {}).get("oid") != item["after_blob"]:
            return False, "CHANGE_SET_BLOB_MISMATCH", set()
        if item.get("before_mode", (before or {}).get("mode")) != (before or {}).get("mode"):
            return False, "CHANGE_SET_MODE_MISMATCH", set()
        if item.get("after_mode", (after or {}).get("mode")) != (after or {}).get("mode"):
            return False, "CHANGE_SET_MODE_MISMATCH", set()
    return True, None, declared_paths


def classify_path(path: str) -> str:
    normalized = path.replace("\\", "/").lower()
    if normalized.endswith(".mpr") or normalized.startswith("mprcontents/"):
        return "MENDIX_MODEL"
    if normalized.startswith(("input-resources/ui-ux/", "planning/target-mockups/")):
        return "REFERENCE"
    if normalized.startswith(("requirements/", "input-resources/requirements/")):
        return "REQUIREMENT"
    if normalized.startswith("planning/decisions/"):
        return "DECISION"
    if normalized.startswith(("planning/tasks/", "planning/checklists/", "planning/waves/")):
        return "TASK_OR_WAVE"
    if normalized.startswith(("planning/evidence/", "planning/parity/", "planning/verification-plans/", "planning/test-contracts/")):
        return "VERIFICATION_OR_EVIDENCE"
    if normalized.startswith("planning/ui-inventory/"):
        return "UI_INVENTORY"
    if normalized.startswith("planning/findings/"):
        return "FINDING"
    if normalized.startswith((".mxagile/", "mxagile-project.yaml")):
        return "FRAMEWORK_OR_CONFIGURATION"
    if normalized.startswith(("docs/", "documentation/")) or normalized.endswith((".md", ".rst")):
        return "DOCUMENTATION"
    if normalized.startswith("scripts/"):
        return "PROJECT_CODE"
    return "UNKNOWN"


def _classify_commit(
    root: Path,
    commit: str,
    *,
    parents: list[str] | None = None,
    message: bytes | None = None,
) -> dict[str, Any]:
    if parents is None:
        parents = _commit_parents(root, commit)
    changes = _commit_changes(root, commit, parents)
    trailers, has_mxagile_trailers = _trailers(root, commit, message)
    change_set_files = [path for path in changes if path.startswith(CHANGE_SET_DIRECTORY + "/") and path.endswith(".json")]
    path_classes: dict[str, str] = {}
    attribution = "EXTERNAL_CHANGE"
    reason: str | None = None
    verified_change_set_id: str | None = None
    if len(parents) > 1 and not changes:
        attribution, reason = "INHERITED_MERGE", "NO_MERGE_RESOLUTION_DELTA"
    elif len(parents) > 1 and changes and not has_mxagile_trailers:
        attribution, reason = "AMBIGUOUS", "MERGE_RESOLUTION_UNATTRIBUTED"
    elif not has_mxagile_trailers:
        if change_set_files:
            attribution, reason = "AMBIGUOUS", "CHANGE_SET_WITHOUT_TRAILER"
    else:
        verified, reason, declared_paths = _verify_change_set(root, commit, parents, changes, trailers)
        if verified:
            verified_change_set_id = trailers["mxagile-change-set"][0]
            for path in changes:
                if path == f"{CHANGE_SET_DIRECTORY}/{verified_change_set_id}.json":
                    continue
                path_classes[path] = "MXAGILE_ATTRIBUTED_CHANGE" if path in declared_paths else "EXTERNAL_CHANGE"
            classes = set(path_classes.values())
            if classes == {"MXAGILE_ATTRIBUTED_CHANGE"}:
                attribution = "MXAGILE_ATTRIBUTED_CHANGE"
            elif classes == {"EXTERNAL_CHANGE"}:
                attribution = "EXTERNAL_CHANGE"
            elif classes:
                attribution = "MIXED"
            else:
                attribution = "INHERITED_MERGE" if len(parents) > 1 else "AMBIGUOUS"
                reason = "NO_ATTRIBUTABLE_PROJECT_PATHS"
        elif change_set_files:
            attribution = "AMBIGUOUS"
        else:
            attribution, reason = "EXTERNAL_CHANGE", "VERIFIED_CHANGE_SET_MISSING"
    if attribution == "AMBIGUOUS":
        path_classes = {path: "AMBIGUOUS" for path in changes if path not in change_set_files}
    elif attribution == "EXTERNAL_CHANGE":
        path_classes = {path: "EXTERNAL_CHANGE" for path in changes if path not in change_set_files}
    paths = [
        {
            "path": path,
            "status": changes[path]["status"],
            "classification": path_classes.get(path, "PROVENANCE_METADATA"),
            "path_class": classify_path(path),
            "before_blob": (changes[path]["before"] or {}).get("oid"),
            "after_blob": (changes[path]["after"] or {}).get("oid"),
        }
        for path in sorted(changes)
    ]
    return {
        "commit": commit,
        "parents": parents,
        "change_set_id": verified_change_set_id,
        "classification": attribution,
        "reason": reason,
        "paths": paths,
    }


def _group_spans(commits: list[dict[str, Any]]) -> list[dict[str, Any]]:
    spans: list[dict[str, Any]] = []
    for commit in commits:
        classification = commit["classification"]
        if spans and spans[-1]["classification"] == classification:
            spans[-1]["last_commit"] = commit["commit"]
            spans[-1]["commit_count"] += 1
            spans[-1]["paths"] = sorted(set(spans[-1]["paths"]) | {
                path["path"] for path in commit["paths"] if path["classification"] != "PROVENANCE_METADATA"
            })
            continue
        spans.append({
            "classification": classification,
            "first_commit": commit["commit"],
            "last_commit": commit["commit"],
            "commit_count": 1,
            "paths": sorted(path["path"] for path in commit["paths"] if path["classification"] != "PROVENANCE_METADATA"),
        })
    return spans


def prepare_change_set(
    root: Path,
    *,
    change_set_id: str,
    mission_id: str,
    project_fingerprint: str,
    outcome: str,
    result_references: list[str] | None = None,
    reconciliation_references: list[str] | None = None,
    context_epoch: str | None = None,
) -> dict[str, Any]:
    """Write a Change-Set manifest for staged paths; never stages or commits."""
    root = root.resolve()
    if not CHANGE_SET_ID_PATTERN.fullmatch(change_set_id):
        raise GitReconciliationError("CHANGE_SET_ID_INVALID")
    branch_ref = _git_text(root, "symbolic-ref", "--quiet", "HEAD")
    if not re.fullmatch(r"refs/heads/.+", branch_ref):
        raise GitReconciliationError("DETACHED_HEAD")
    operations = ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"]
    for operation in operations:
        operation_path = Path(_git_text(root, "rev-parse", "--git-path", operation))
        if not operation_path.is_absolute():
            operation_path = root / operation_path
        if operation_path.exists():
            raise GitReconciliationError("GIT_OPERATION_IN_PROGRESS")
    head = _git_text(root, "rev-parse", "--verify", "HEAD")
    tree_changes = working_tree_changes(root)
    if tree_changes["unstaged"] or tree_changes["untracked"]:
        raise GitReconciliationError("CHANGE_SET_REQUIRES_NO_UNSTAGED_OR_UNTRACKED_PATHS")
    staged = tree_changes["staged"]
    if not staged:
        raise GitReconciliationError("NO_STAGED_PATHS")
    manifest_path = f"{CHANGE_SET_DIRECTORY}/{change_set_id}.json"
    if any(item["path"] == manifest_path for item in staged):
        raise GitReconciliationError("CHANGE_SET_PATH_ALREADY_STAGED")
    target = root / manifest_path
    if target.exists() or _run_git(root, "ls-files", "--error-unmatch", "--", manifest_path).returncode == 0:
        raise GitReconciliationError("CHANGE_SET_ALREADY_EXISTS")
    ignored = _run_git(root, "check-ignore", "--no-index", "--quiet", "--", manifest_path)
    if ignored.returncode == 0:
        raise GitReconciliationError("CHANGE_SET_PATH_IGNORED")
    if ignored.returncode != 1:
        raise GitReconciliationError("GIT_IGNORE_CHECK_FAILED")

    parent_tree = _git_text(root, "rev-parse", f"{head}^{{tree}}")
    paths = []
    for item in staged:
        path = item["path"]
        if path.startswith(CHANGE_SET_DIRECTORY + "/"):
            raise GitReconciliationError("CHANGE_SET_METADATA_CANNOT_BE_ATTRIBUTED")
        before = _tree_entry(root, parent_tree, path)
        after = _index_entry(root, path)
        status = _semantic_status(before, after)
        if status is None:
            raise GitReconciliationError("STAGED_PATH_HAS_NO_TREE_DELTA")
        paths.append({
            "path": path,
            "status": status,
            "before_mode": (before or {}).get("mode"),
            "after_mode": (after or {}).get("mode"),
            "before_blob": (before or {}).get("oid"),
            "after_blob": (after or {}).get("oid"),
        })

    change_set = {
        "schema_version": 1,
        "change_set_id": change_set_id,
        "mission_id": mission_id,
        "context_epoch": context_epoch,
        "result_references": sorted(set(result_references or [])),
        "parent_commits": [head],
        "paths": paths,
        "reconciliation": {
            "status": "COMPLETE",
            "outcome": outcome,
            "project_fingerprint": project_fingerprint,
            "references": sorted(set(reconciliation_references or [])),
        },
    }
    schema_path = root / ".mxagile/schemas" / CHANGE_SET_SCHEMA
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8-sig"))
        errors = list(Draft7Validator(schema).iter_errors(change_set))
    except (OSError, ValueError, TypeError):
        raise GitReconciliationError("CHANGE_SET_SCHEMA_UNAVAILABLE") from None
    if errors:
        raise GitReconciliationError("CHANGE_SET_SCHEMA_INVALID")

    target.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=target.parent,
            prefix=f".{target.name}.", suffix=".tmp", delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            json.dump(change_set, handle, ensure_ascii=False, sort_keys=True, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, target)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()
    return {
        "status": "CHANGE_SET_PREPARED",
        "staged": False,
        "committed": False,
        "path": target.relative_to(root).as_posix(),
        "trailers": [
            f"MxAgile-Origin: {ORIGIN_VALUE}",
            f"MxAgile-Mission: {mission_id}",
            f"MxAgile-Change-Set: {change_set_id}",
        ],
        "change_set": change_set,
    }


def analyze_commit_range(root: Path, watermark: str, head: str, *, shallow: bool = False) -> dict[str, Any]:
    if shallow:
        return {"status": "HISTORY_UNAVAILABLE_SHALLOW", "commits": [], "spans": []}
    exists = _run_git(root, "cat-file", "-e", f"{watermark}^{{commit}}")
    if exists.returncode:
        return {"status": "WATERMARK_COMMIT_NOT_FOUND", "commits": [], "spans": []}
    ancestor = _run_git(root, "merge-base", "--is-ancestor", watermark, head)
    if ancestor.returncode == 1:
        return {"status": "DIVERGED_HISTORY", "commits": [], "spans": []}
    if ancestor.returncode:
        return {"status": "HISTORY_ANCESTRY_UNAVAILABLE", "commits": [], "spans": []}
    if watermark == head:
        return {"status": "NO_COMMITTED_DELTA", "commits": [], "spans": []}
    raw = _git(root, "rev-list", "--topo-order", "--reverse", f"{watermark}..{head}")
    commit_ids = [os.fsdecode(line) for line in raw.splitlines() if line]
    parents = _batched_parents(root, commit_ids)
    messages = _batched_messages(root, commit_ids)
    commits = [
        _classify_commit(root, commit, parents=parents[commit], message=messages[commit])
        for commit in commit_ids
    ]
    spans = _group_spans(commits)
    classes = {commit["classification"] for commit in commits}
    if "AMBIGUOUS" in classes:
        status = "AMBIGUOUS_HISTORY"
    elif classes and classes <= {"MXAGILE_ATTRIBUTED_CHANGE", "INHERITED_MERGE"}:
        status = "MXAGILE_ATTRIBUTED_ONLY"
    else:
        status = "RECONCILIATION_REQUIRED"
    return {"status": status, "commits": commits, "spans": spans}