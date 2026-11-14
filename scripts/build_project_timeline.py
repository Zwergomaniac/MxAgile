#!/usr/bin/env python3
"""Evidence-based project timeline (CS-5).

A derived, disposable projection of what happened in a project: reconstructed from canonical artifacts
and the Git history, never written into the project and never used as lifecycle authority.

Attribution rules (contracts/timeline-event.md, K.6):
- An event is attributed to a MxAgile entity only through explicit evidence: the touched canonical artifact,
  a canonical field link (e.g. task.wave_id), a verified commit trailer + Change-Set, or an artifact field.
- A mention of an entity in a commit message is labelled GIT_MENTION and never attributes the event.
- Temporal proximity, branch names, file-name similarity or free-text mission ids never attribute anything.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any

import yaml
from wave_ids import CHECKLIST_PATH_PATTERN, WAVE_MENTION_PATTERN, wave_sort_key

sys.dont_write_bytecode = True

INDEX_FORMAT = 3
RULE_VERSION = "project-timeline/v2"
AUTHORITY_CLASSES = ("CANONICAL_RECORD", "GIT_DERIVED", "COMMIT_TRAILER", "GIT_MENTION")
BLOB_LIMIT = 256 * 1024
MAX_COMMITS = 20000
DERIVATIONS = (
    "artifact_field", "touched_artifact", "commit_trailer", "change_set_paths", "canonical_field_link",
    "canonical_artifact_name", "message_mention",
)

_YAML_LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

# --------------------------------------------------------------------------- path classes
PROCESS_STATE = "planning/lifecycle/process-state.yaml"
CONTEXT_EPOCH = "planning/lifecycle/context-epoch.yaml"
MISSION_STATE = "planning/mission/mission-state.yaml"
FRAMEWORK_VERSION = ".mxagile/version.yaml"
CHANGE_SET_DIRECTORY = "planning/reconciliation/change-sets"
_ARTIFACTS = (
    ("task", re.compile(r"^planning/tasks/(TASK-[A-Za-z0-9_-]+)\.ya?ml$")),
    ("decision", re.compile(r"^planning/decisions/(DEC-[A-Za-z0-9_-]+)\.ya?ml$")),
    ("requirement", re.compile(r"^requirements/(REQ-[A-Za-z0-9_-]+)\.ya?ml$")),
    ("finding", re.compile(r"^planning/findings/([A-Za-z0-9_.-]+)\.ya?ml$")),
    ("revision", re.compile(r"^planning/revisions/(REV-[A-Za-z0-9_-]+)\.ya?ml$")),
    ("page", re.compile(r"^planning/ui-inventory/(PAGE-[A-Za-z0-9_-]+)\.ya?ml$")),
    ("parity", re.compile(r"^planning/parity/([A-Za-z0-9_.-]+)\.ya?ml$")),
    ("manifest", re.compile(r"^planning/evidence/manifests/([A-Za-z0-9_.-]+?)(?:-evidence-manifest)?\.ya?ml$")),
    ("contract", re.compile(r"^planning/test-contracts/(TC-[A-Za-z0-9_-]+?)(?:-[a-z0-9-]+)?\.ya?ml$")),
    ("checklist", CHECKLIST_PATH_PATTERN),
)
_MENTION_PATTERNS = (
    ("wave", WAVE_MENTION_PATTERN),
    ("task", re.compile(r"\b(TASK-[0-9]+)\b")),
    ("requirement", re.compile(r"\b(REQ-[0-9]+)\b")),
    ("decision", re.compile(r"\b(DEC-[0-9]+)\b")),
    ("revision", re.compile(r"\b(REV-[0-9]+)\b")),
    ("page", re.compile(r"\b(PAGE-[A-Z0-9_-]+)\b")),
)
_ZERO_OID = re.compile(r"^0+$")
_TYPE_GROUPS = {
    "wave": ("wave.", "mission.", "epoch."),
    "requirement": ("requirement.",),
    "decision": ("decision.",),
    "finding": ("finding.",),
    "verification": ("parity.", "evidence.", "verification."),
    "authority": ("authority.",),
    "page": ("page.",),
    "task": ("task.",),
    "provenance": ("changeset.", "delegation.", "reconciliation.", "framework."),
    "code": ("model.", "project.", "reference.", "document.", "commit."),
}


def _group_of(event_type: str) -> str:
    for group, prefixes in _TYPE_GROUPS.items():
        if event_type.startswith(prefixes):
            return group
    return "other"


# --------------------------------------------------------------------------- git
def _run_git(root: Path, *args: str, input_bytes: bytes | None = None, timeout: float = 180.0) -> subprocess.CompletedProcess | None:
    try:
        return subprocess.run(
            ["git", "--no-optional-locks", "-c", "core.quotepath=false", "-C", str(root), *args],
            input=input_bytes, capture_output=True, timeout=timeout, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None


def _git_text(root: Path, *args: str) -> str | None:
    done = _run_git(root, *args)
    if done is None or done.returncode:
        return None
    return done.stdout.decode("utf-8", "replace").strip()


def repository_state(root: Path) -> dict[str, Any] | None:
    info = _git_text(root, "rev-parse", "--show-toplevel", "--show-prefix", "HEAD", "--is-shallow-repository", "--symbolic-full-name", "HEAD")
    if not info:
        return None
    lines = info.split("\n")
    # --show-prefix prints an empty line at the repository root, so the line count varies.
    if len(lines) == 4:
        lines.insert(1, "")
    if len(lines) < 5 or not re.fullmatch(r"[0-9a-f]{40}", lines[2].strip()):
        return None
    branch = lines[4].strip()
    return {"toplevel": lines[0].strip(), "prefix": lines[1].strip(), "head": lines[2].strip(),
            "shallow": lines[3].strip() == "true", "branch": branch if branch and branch != "HEAD" else "DETACHED"}


def _cache_file(root: Path, repo: dict[str, Any]) -> Path | None:
    override = os.environ.get("MXAGILE_BOARD_CACHE_DIR")
    if override:
        base = Path(override)
    elif os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData/Local")) / "mxagile" / "board-cache"
    else:
        base = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "mxagile" / "board-cache"
    resolved = root.resolve()
    try:
        base.resolve().relative_to(resolved)
        return None  # never inside the project (read-only contract)
    except (OSError, ValueError):
        pass
    identity = str(resolved).casefold() if os.name == "nt" else str(resolved)
    project_key = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:32]
    branch_key = hashlib.sha256(repo["branch"].encode("utf-8")).hexdigest()[:16]
    return base / project_key / branch_key / "timeline-index.json"


# --------------------------------------------------------------------------- helpers
def _event_id(event_type: str, path: str | None, commit: str | None, field: str | None, value: Any) -> str:
    raw = "|".join(str(part) for part in (event_type, path or "", commit or "", field or "", value if value is not None else ""))
    return "EV-" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _load_blob(raw: bytes | None) -> Any:
    if not raw:
        return None
    try:
        value = yaml.load(raw.decode("utf-8-sig"), Loader=_YAML_LOADER)
    except (yaml.YAMLError, UnicodeError, ValueError, RecursionError):
        return None
    return value if isinstance(value, dict) else None


def _text(value: Any, limit: int = 140) -> str | None:
    return str(value).strip().replace("\n", " ")[:limit] if value is not None and str(value).strip() else None


def _str_list(value: Any, limit: int = 12) -> list[str]:
    return [str(item) for item in value if isinstance(item, (str, int))][:limit] if isinstance(value, list) else []


def _iso(epoch: int) -> str:
    return datetime.fromtimestamp(epoch, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def _entity(kind: str, identifier: str, derivation: str) -> dict[str, str]:
    return {"type": kind, "id": identifier, "derivation": derivation}


def _read_blobs(root: Path, oids: set[str]) -> dict[str, bytes]:
    """Every needed blob through one `git cat-file --batch` process."""
    if not oids:
        return {}
    ordered = sorted(oids)
    done = _run_git(root, "cat-file", "--batch", input_bytes=("\n".join(ordered) + "\n").encode("ascii"))
    if done is None or done.returncode:
        return {}
    data, position, blobs = done.stdout, 0, {}
    for oid in ordered:
        end = data.find(b"\n", position)
        if end < 0:
            break
        header = data[position:end].split()
        if len(header) == 3 and header[1] == b"blob" and header[2].isdigit():
            size = int(header[2])
            if size <= BLOB_LIMIT:
                blobs[oid] = data[end + 1:end + 1 + size]
            position = end + 1 + size + 1
        else:
            position = end + 1
    return blobs


def _scan(root: Path, range_spec: str | None) -> list[dict[str, Any]]:
    fmt = "%x01%H%x1f%P%x1f%ct%x1f%cI%x1f%an%x1f%s%x1f%b%x02"
    args = ["log", "--first-parent", "-m", "--raw", "--no-renames", "--no-abbrev", f"--format={fmt}", f"-n{MAX_COMMITS}"]
    args.append(range_spec or "HEAD")
    done = _run_git(root, *args)
    if done is None or done.returncode:
        return []
    commits: list[dict[str, Any]] = []
    for chunk in done.stdout.decode("utf-8", "replace").split("\x01"):
        if "\x02" not in chunk:
            continue
        header, _, raw_part = chunk.partition("\x02")
        fields = header.split("\x1f")
        if len(fields) < 7:
            continue
        commit, parents, stamp, iso, author, subject, body = fields[:7]
        changes = []
        for line in raw_part.splitlines():
            if not line.startswith(":") or "\t" not in line:
                continue
            meta, _, path = line.partition("\t")
            parts = meta[1:].split()
            if len(parts) >= 5:
                changes.append({"status": parts[4][:1], "old": parts[2], "new": parts[3], "old_mode": parts[0], "new_mode": parts[1], "path": path})
        commits.append({"hash": commit.strip(), "parents": parents.split(), "epoch": int(stamp), "iso": iso,
                        "author": author, "subject": subject, "body": body, "changes": changes})
    return commits


# --------------------------------------------------------------------------- event derivation
def _commit_ref(commit: dict[str, Any]) -> dict[str, Any]:
    return {"hash": commit["hash"], "short": commit["hash"][:7], "first_parent": commit["parents"][0] if commit["parents"] else None,
            "author": commit["author"], "subject": commit["subject"][:200]}


class _Builder:
    def __init__(self, commit: dict[str, Any], mentions: list[dict[str, str]]):
        self.commit = commit
        self.mentions = mentions
        self.events: list[dict[str, Any]] = []

    def add(self, event_type: str, title: str, entities: list[dict[str, str]], *, path: str | None = None, field: str | None = None,
            before: Any = None, after: Any = None, significance: int = 1, detail: str | None = None) -> None:
        seen, unique = set(), []
        for entity in entities:
            key = (entity["type"], entity["id"])
            if key not in seen:
                seen.add(key)
                unique.append(entity)
        self.events.append({
            "event_id": _event_id(event_type, path, self.commit["hash"], field, after if after is not None else title),
            "type": event_type, "authority_class": "GIT_DERIVED", "lane": "attributed",
            "occurred_at": self.commit["iso"], "occurred_epoch": self.commit["epoch"], "time_basis": "commit_time",
            "title": title, "detail": detail, "significance": significance, "entities": unique,
            "commit": _commit_ref(self.commit),
            "source": {"path": path, "field": field, "before": _text(before, 80), "after": _text(after, 80)} if path else None,
            "change_set_id": None, "mission_label": None, "mission_id": None, "health": [],
        })


def _wave_links(value: dict[str, Any], derivation: str = "canonical_field_link") -> list[dict[str, str]]:
    wave = value.get("wave_id")
    return [_entity("wave", str(wave), derivation)] if isinstance(wave, (str, int)) and str(wave).strip() else []


def _status_word(status: Any) -> str:
    return {"done": "abgeschlossen", "pending": "offen", "in_progress": "in Arbeit", "blocked": "blockiert", "deferred": "zurückgestellt",
            "failed": "fehlgeschlagen", "accepted": "angenommen", "draft": "Entwurf", "superseded": "ersetzt", "CONFIRMED": "bestätigt",
            "PROPOSED": "vorgeschlagen", "REJECTED": "abgelehnt", "SUPERSEDED": "ersetzt"}.get(str(status), str(status))


def _derive_artifact_events(builder: _Builder, kind: str, identifier: str, change: dict[str, str], before: dict | None, after: dict | None) -> bool:
    path, status = change["path"], change["status"]
    created = status == "A" or before is None
    if after is None:
        return False
    own = _entity(kind if kind not in ("manifest", "contract", "checklist", "parity") else kind, identifier, "touched_artifact")
    if kind == "task":
        was, now = (before or {}).get("status"), after.get("status")
        entities = [_entity("task", identifier, "touched_artifact"), *_wave_links(after, "canonical_field_link")] + \
                   [_entity("requirement", r, "canonical_field_link") for r in _str_list(after.get("req"))]
        action = _text(after.get("action"), 90)
        if created:
            builder.add("task.created", f"Task {identifier} angelegt" + (f": {action}" if action else ""), entities, path=path, field="status", after=now)
            return True
        if was != now:
            builder.add("task.status_changed", f"Task {identifier}: {_status_word(now)}" + (f" – {action}" if action else ""), entities,
                        path=path, field="status", before=was, after=now, significance=2 if now == "done" else 1)
            return True
        return False
    if kind == "decision":
        entities = [_entity("decision", identifier, "touched_artifact")] + \
                   [_entity("requirement", r, "canonical_field_link") for r in _str_list(after.get("affected_requirements"))] + \
                   [_entity("page", p, "canonical_field_link") for p in _str_list(after.get("affected_screens"))] + \
                   [_entity("revision", r, "canonical_field_link") for r in _str_list(after.get("affected_mockup_revisions"))]
        was, now = (before or {}).get("status"), after.get("status")
        title = _text(after.get("title"), 90)
        if created:
            verb = "vorgeschlagen" if now == "PROPOSED" else f"erfasst ({_status_word(now)})"
            builder.add("decision.proposed" if now == "PROPOSED" else "decision.recorded", f"Decision {identifier} {verb}" + (f": {title}" if title else ""),
                        entities, path=path, field="status", after=now, significance=3)
            return True
        if was != now:
            etype = {"CONFIRMED": "decision.confirmed", "SUPERSEDED": "decision.superseded"}.get(str(now), "decision.status_changed")
            builder.add(etype, f"Decision {identifier} {_status_word(now)}" + (f": {title}" if title else ""), entities,
                        path=path, field="status", before=was, after=now, significance=3)
            return True
        return False
    if kind == "requirement":
        entities = [_entity("requirement", identifier, "touched_artifact")]
        was, now = (before or {}).get("status"), after.get("status")
        title = _text(after.get("title"), 90)
        if created:
            builder.add("requirement.created", f"Requirement {identifier} angelegt ({_status_word(now)})" + (f": {title}" if title else ""),
                        entities, path=path, field="status", after=now, significance=2)
        elif was != now:
            builder.add("requirement.status_changed", f"Requirement {identifier}: {_status_word(was)} → {_status_word(now)}" + (f" – {title}" if title else ""),
                        entities, path=path, field="status", before=was, after=now, significance=2)
        else:
            builder.add("requirement.changed", f"Requirement {identifier} aktualisiert" + (f": {title}" if title else ""), entities,
                        path=path, field="content", after=change["new"], significance=1)
        return True
    if kind == "finding":
        entities = [_entity("finding", identifier, "touched_artifact"), *_wave_links(after)] + \
                   [_entity("requirement", r, "canonical_field_link") for r in _str_list(after.get("requirement_ids"))]
        was, now = (before or {}).get("lifecycle_status"), after.get("lifecycle_status")
        title = _text(after.get("title"), 90)
        if created:
            builder.add("finding.created", f"Finding {identifier} erfasst ({now})" + (f": {title}" if title else ""), entities,
                        path=path, field="lifecycle_status", after=now, significance=3)
            return True
        if was != now:
            builder.add("finding.transitioned", f"Finding {identifier}: {was} → {now}" + (f" – {title}" if title else ""), entities,
                        path=path, field="lifecycle_status", before=was, after=now, significance=3)
            return True
        return False
    if kind == "revision":
        entities = [_entity("revision", identifier, "touched_artifact")] + [_entity("page", p, "canonical_field_link") for p in _str_list(after.get("screens"))]
        was = bool((before or {}).get("active_target"))
        now = bool(after.get("active_target"))
        if now and (created or not was):
            builder.add("authority.active_target_changed", f"{identifier} ist jetzt aktive Design-Authority", entities,
                        path=path, field="active_target", before=was, after=now, significance=3)
        elif was and not now:
            builder.add("authority.active_target_changed", f"{identifier} ist nicht mehr aktive Design-Authority", entities,
                        path=path, field="active_target", before=was, after=now, significance=3)
        elif created:
            builder.add("authority.revision_recorded", f"Revision {identifier} erfasst", entities, path=path, field="revision", after=identifier, significance=2)
        else:
            return False
        return True
    if kind == "page":
        name = _text(after.get("page_name") or after.get("title") or after.get("mockup_name") or identifier, 80)
        entities = [_entity("page", identifier, "touched_artifact")]
        was_target = (before or {}).get("target_mockup")
        now_target = after.get("target_mockup")
        detail = f"Zielmockup: {_text(was_target, 60)} → {_text(now_target, 60)}" if was_target != now_target and not created and now_target else None
        builder.add("page.changed", f"Page {name} {'angelegt' if created else 'geändert'}", entities, path=path, field="content",
                    after=change["new"], significance=2, detail=detail)
        return True
    if kind == "parity":
        page = after.get("page_id")
        entities = ([_entity("page", str(page), "canonical_field_link")] if isinstance(page, str) else []) + [_entity("parity_report", identifier, "touched_artifact")]
        result = after.get("overall_result")
        builder.add("parity.recorded", f"Parity-Ergebnis {result or 'ohne Ergebnis'}" + (f" · {page}" if page else "") +
                    " (berichtet; Bindung an Evidenz separat)", entities, path=path, field="overall_result", after=result,
                    significance=2, detail=f"verified_at: {_text(after.get('verified_at'), 30)}")
        return True
    if kind == "manifest":
        wave = after.get("wave_id")
        entities = [_entity("evidence_manifest", identifier, "touched_artifact")] + _wave_links(after)
        entries = after.get("entries") if isinstance(after.get("entries"), list) else []
        for entry in entries[:30]:
            trace = entry.get("traceability") if isinstance(entry, dict) and isinstance(entry.get("traceability"), dict) else {}
            entities.extend(_entity("requirement", r, "canonical_field_link") for r in _str_list(trace.get("requirements"), 6))
        builder.add("evidence.recorded", f"Evidenz-Manifest {identifier} {'erfasst' if created else 'aktualisiert'}" + (f" · {wave}" if wave else ""),
                    entities, path=path, field="manifest", after=change["new"], significance=2)
        return True
    if kind == "contract":
        entities = [_entity("test_contract", identifier, "touched_artifact")] + \
                   [_entity("requirement", r, "canonical_field_link") for r in _str_list(after.get("requirement_ids"))]
        if created:
            builder.add("verification.contract_recorded", f"Test Contract {identifier} angelegt", entities, path=path, field="contract", after=change["new"], significance=2)
            return True
        return False
    if kind == "checklist":
        builder.add("wave.checklist_changed", f"Checkliste von Wave {identifier} {'angelegt' if created else 'geändert'}",
                    [_entity("wave", identifier, "canonical_artifact_name")], path=path, field="checklist", after=change["new"], significance=1)
        return True
    return False


def _derive_process_state(builder: _Builder, change: dict[str, str], before: dict | None, after: dict | None) -> bool:
    waves_after = after.get("waves") if isinstance(after, dict) and isinstance(after.get("waves"), dict) else {}
    waves_before = before.get("waves") if isinstance(before, dict) and isinstance(before.get("waves"), dict) else {}
    produced = False
    for wave_id in sorted(waves_after, key=wave_sort_key):
        now = waves_after[wave_id] if isinstance(waves_after[wave_id], dict) else {}
        was = waves_before.get(wave_id) if isinstance(waves_before.get(wave_id), dict) else None
        entity = [_entity("wave", str(wave_id), "artifact_field")]
        if was is None:
            builder.add("wave.registered", f"Wave {wave_id} registriert (Phase {now.get('phase')})", entity, path=change["path"],
                        field=f"waves.{wave_id}", after=now.get("phase"), significance=2)
            produced = True
        elif was.get("phase") != now.get("phase"):
            phase = now.get("phase")
            title = f"Wave {wave_id} abgeschlossen (DONE)" if phase == "done" else f"Wave {wave_id}: Phase {was.get('phase')} → {phase}"
            builder.add("wave.phase_changed", title, entity, path=change["path"], field=f"waves.{wave_id}.phase",
                        before=was.get("phase"), after=phase, significance=3)
            produced = True
        for gate in ("gate_to_refinement", "gate_to_ready", "testability_gate", "acceptance_gate"):
            gate_now = (now.get("gates") or {}).get(gate) if isinstance(now.get("gates"), dict) else None
            gate_was = (was.get("gates") or {}).get(gate) if isinstance(was, dict) and isinstance(was.get("gates"), dict) else None
            result_now = gate_now.get("result") if isinstance(gate_now, dict) else None
            result_was = gate_was.get("result") if isinstance(gate_was, dict) else None
            if result_now and result_now != result_was and result_now != "not_recorded" and not (isinstance(gate_now, dict) and gate_now.get("evaluated")):
                label = {"gate_to_refinement": "Refinement-Gate", "gate_to_ready": "Ready-Gate", "testability_gate": "Testability-Gate", "acceptance_gate": "Acceptance-Gate"}[gate]
                builder.add("wave.gate_evaluated", f"Wave {wave_id} · {label}: {result_now}", entity, path=change["path"],
                            field=f"waves.{wave_id}.gates.{gate}.result", before=result_was, after=result_now, significance=2)
                produced = True
    return produced


def _derive_single_documents(builder: _Builder, change: dict[str, str], before: dict | None, after: dict | None) -> bool:
    path = change["path"]
    if path == MISSION_STATE and after is not None:
        was = ((before or {}).get("progress") or {}).get("mission") if isinstance((before or {}).get("progress"), dict) else None
        now = (after.get("progress") or {}).get("mission") if isinstance(after.get("progress"), dict) else None
        mission_id = _text(after.get("mission_id"), 80) or "Mission"
        entity = [_entity("mission", mission_id, "artifact_field")]
        if before is None:
            builder.add("mission.started", f"Mission {mission_id} gestartet" + (f": {_text(after.get('objective'), 90)}" if after.get("objective") else ""),
                        entity, path=path, field="progress.mission", after=now, significance=3)
            return True
        if was != now:
            builder.add("mission.status_changed", f"Mission {mission_id}: {was} → {now}", entity, path=path, field="progress.mission",
                        before=was, after=now, significance=3)
            return True
        return False
    if path == CONTEXT_EPOCH and after is not None:
        was = ((before or {}).get("context") or {}).get("epoch_id") if isinstance((before or {}).get("context"), dict) else None
        now = (after.get("context") or {}).get("epoch_id") if isinstance(after.get("context"), dict) else None
        if now and was != now and before is not None:
            builder.add("epoch.rollover", "Kontext-Epoche gewechselt", [_entity("context_epoch", str(now), "artifact_field")], path=path,
                        field="context.epoch_id", before=was, after=now, significance=1)
            return True
        return False
    if path == FRAMEWORK_VERSION and after is not None:
        was, now = (before or {}).get("version"), after.get("version")
        if now and was != now:
            builder.add("framework.updated", f"MxAgile Core auf v{now} aktualisiert" + (f" (zuvor v{was})" if was else ""),
                        [_entity("framework", "MxAgile Core", "touched_artifact")], path=path, field="version", before=was, after=now, significance=2)
            return True
    return False


def _classify(path: str) -> tuple[str, str] | None:
    for kind, pattern in _ARTIFACTS:
        match = pattern.match(path)
        if match:
            return kind, match.group(1)
    return None


def _project_class(path: str) -> str | None:
    """Model, reference or project-code paths; planning/documentation/tooling are handled elsewhere."""
    lowered = path.lower()
    if lowered.endswith(".mpr") or lowered.startswith("mprcontents/"):
        return "model"
    if lowered.startswith(("input-resources/ui-ux/", "planning/target-mockups/")):
        return "reference"
    if lowered.startswith(("planning/", ".mxagile/", ".claude/", ".github/", ".codex/", ".agents/", ".concord/", "requirements/")) or path.startswith("."):
        return None
    if lowered.endswith((".md", ".rst", ".txt")) or lowered.startswith(("docs/", "documentation/")):
        return "document"
    return "project"


def _mentions(commit: dict[str, Any]) -> list[dict[str, str]]:
    text = commit["subject"] + "\n" + commit["body"]
    found, seen = [], set()
    for kind, pattern in _MENTION_PATTERNS:
        for match in pattern.findall(text):
            if (kind, match) not in seen and len(seen) < 12:
                seen.add((kind, match))
                found.append(_entity(kind, match, "message_mention"))
    return found


def _commit_events(commit: dict[str, Any], blobs: dict[str, bytes], trailer: dict[str, Any] | None) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    builder = _Builder(commit, _mentions(commit))
    linked_waves: set[str] = set()
    class_counts: dict[str, int] = {}
    delivery = False
    for change in commit["changes"]:
        path = change["path"]
        if change["status"] == "D" or path.startswith(CHANGE_SET_DIRECTORY + "/"):
            continue
        before = _load_blob(blobs.get(change["old"])) if not _ZERO_OID.match(change["old"]) else None
        after = _load_blob(blobs.get(change["new"])) if not _ZERO_OID.match(change["new"]) else None
        if path == PROCESS_STATE:
            _derive_process_state(builder, change, before, after)
            continue
        if path in (MISSION_STATE, CONTEXT_EPOCH, FRAMEWORK_VERSION):
            _derive_single_documents(builder, change, before, after)
            continue
        artifact = _classify(path)
        if artifact:
            before_count = len(builder.events)
            _derive_artifact_events(builder, artifact[0], artifact[1], change, before, after)
            for event in builder.events[before_count:]:
                for entity in event["entities"]:
                    if entity["type"] == "wave":
                        linked_waves.add(entity["id"])
            if artifact[0] == "task" and after is not None and isinstance(after.get("wave_id"), (str, int)):
                linked_waves.add(str(after["wave_id"]))
            continue
        kind = _project_class(path)
        if kind:
            class_counts[kind] = class_counts.get(kind, 0) + 1
            delivery = delivery or kind in ("model", "reference", "project")
    labels = {
        "model": ("model.changed", "Mendix-Modell geändert", 2), "reference": ("reference.changed", "Referenz-Mockup geändert", 2),
        "project": ("project.changed", "Projektdateien geändert", 2), "document": ("document.changed", "Dokumentation geändert", 1),
    }
    for kind in ("reference", "model", "project", "document"):
        count = class_counts.get(kind)
        if count:
            event_type, label, significance = labels[kind]
            builder.add(event_type, f"{label} · {count} Datei{'en' if count != 1 else ''}", [], path=None, field=kind,
                        after=f"{count}", significance=significance, detail=None)
            builder.events[-1]["event_id"] = _event_id(event_type, None, commit["hash"], kind, count)
    if not builder.events:
        builder.add("commit.recorded", f"Commit {commit['hash'][:7]}: {commit['subject'][:100]}", [], path=None, field="commit", after=commit["hash"], significance=1)
        builder.events[-1]["event_id"] = _event_id("commit.recorded", None, commit["hash"], "commit", commit["hash"])
    _attribute(builder.events, builder.mentions, trailer)
    summary = {"hash": commit["hash"][:12], "epoch": commit["epoch"], "delivery": delivery, "waves": sorted(linked_waves, key=wave_sort_key)}
    return builder.events, summary


def _attribute(events: list[dict[str, Any]], mentions: list[dict[str, str]], trailer: dict[str, Any] | None) -> None:
    """Apply the authority rules after the evidence-backed entities exist."""
    for event in events:
        evidence = [entity for entity in event["entities"] if entity["derivation"] != "message_mention"]
        event["lane"] = "attributed" if evidence else "unattributed"
        if trailer and trailer.get("change_set_id"):
            event["change_set_id"] = trailer["change_set_id"]
            event["entities"].append(_entity("change_set", trailer["change_set_id"],
                                             "change_set_paths" if event["source"] and event["source"]["path"] in trailer.get("paths", ()) else "commit_trailer"))
            event["lane"] = "attributed"
            if not evidence:
                event["authority_class"] = "COMMIT_TRAILER"
        elif trailer and trailer.get("invalid"):
            event["health"] = [trailer["invalid"]]
        if event["lane"] == "unattributed" and mentions:
            event["authority_class"] = "GIT_MENTION"
            event["entities"] = [*event["entities"], *mentions]
        elif event["lane"] == "unattributed":
            event["authority_class"] = "GIT_DERIVED"


# --------------------------------------------------------------------------- snapshot (canonical record) events
def _schema_root() -> Path:
    here = Path(__file__).resolve().parent
    for candidate in (here.parent / ".mxagile" / "schemas", here.parent / "schemas"):
        if candidate.is_dir():
            return candidate
    return here.parent / "schemas"


def _canonical_events(root: Path, repo: dict[str, Any] | None, changeset_commits: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    mission_id = None
    try:
        mission = yaml.load((root / MISSION_STATE).read_text(encoding="utf-8-sig"), Loader=_YAML_LOADER)
    except (OSError, yaml.YAMLError, UnicodeError):
        mission = None
    if isinstance(mission, dict):
        mission_id = mission.get("mission_id") if isinstance(mission.get("mission_id"), str) else None
    directory = root / CHANGE_SET_DIRECTORY
    if directory.is_dir():
        try:
            from jsonschema import Draft7Validator
            schema = json.loads((_schema_root() / "change-set.schema.json").read_text(encoding="utf-8-sig"))
            validator = Draft7Validator(schema)
        except (OSError, ValueError, ImportError):
            validator = None
        for path in sorted(directory.glob("*.json"))[:200]:
            relative = f"{CHANGE_SET_DIRECTORY}/{path.name}"
            try:
                if path.stat().st_size > 1024 * 1024:
                    raise ValueError("TOO_LARGE")
                value = json.loads(path.read_text(encoding="utf-8-sig"))
            except (OSError, ValueError, UnicodeError):
                value = None
            valid = bool(validator and isinstance(value, dict) and not list(validator.iter_errors(value)))
            created = value.get("created_at") if isinstance(value, dict) and isinstance(value.get("created_at"), str) else None
            when = None
            if created:
                try:
                    when = datetime.fromisoformat(created.replace("Z", "+00:00"))
                except ValueError:
                    when = None
            commit_ref, epoch = None, 0
            known = changeset_commits.get(relative)
            if known:
                commit_ref = {"hash": known["hash"], "short": known["hash"][:7], "first_parent": None, "author": known["author"], "subject": known["subject"]}
                if when is None:
                    when = datetime.fromisoformat(known["iso"])
            if when is None:
                continue
            if when.tzinfo is None:
                when = when.replace(tzinfo=timezone.utc)
            epoch = int(when.timestamp())
            change_set_id = value.get("change_set_id") if valid else None
            if valid:
                label = _text(value.get("mission_id"), 80)
                title = f"Change-Set {change_set_id} erfasst · {len(value.get('paths', []))} Pfade" + (f" · Ergebnis {value['final_result']}" if value.get("final_result") else "")
                events.append({
                    "event_id": _event_id("changeset.recorded", relative, None, "created_at", created),
                    "type": "changeset.recorded", "authority_class": "CANONICAL_RECORD", "lane": "attributed",
                    "occurred_at": when.isoformat(), "occurred_epoch": epoch, "time_basis": "artifact_field", "title": title, "detail": None,
                    "significance": 2, "entities": [_entity("change_set", change_set_id, "artifact_field")], "commit": commit_ref,
                    "source": {"path": relative, "field": "created_at", "before": None, "after": _text(created, 40)},
                    "change_set_id": change_set_id, "mission_label": label,
                    "mission_id": label if label and label == mission_id else None, "health": [],
                })
            else:
                events.append({
                    "event_id": _event_id("changeset.invalid", relative, None, "schema", path.name),
                    "type": "changeset.invalid", "authority_class": "GIT_DERIVED", "lane": "unattributed",
                    "occurred_at": when.isoformat(), "occurred_epoch": epoch, "time_basis": "commit_time" if commit_ref else "artifact_field",
                    "title": f"Change-Set-Datei {path.stem} ist nicht schema-konform (ohne Zuordnungswirkung)", "detail": None,
                    "significance": 1, "entities": [], "commit": commit_ref,
                    "source": {"path": relative, "field": "schema", "before": None, "after": None},
                    "change_set_id": None, "mission_label": None, "mission_id": None, "health": ["CHANGE_SET_SCHEMA_INVALID"],
                })
    results = root / ".concord" / "delegated-results"
    if results.is_dir():
        for path in sorted(results.glob("*.json"))[:100]:
            try:
                value = json.loads(path.read_text(encoding="utf-8-sig"))
                completed = datetime.fromisoformat(str(value["completed_at"]).replace("Z", "+00:00"))
            except (OSError, ValueError, KeyError, UnicodeError):
                continue
            if completed.tzinfo is None:
                completed = completed.replace(tzinfo=timezone.utc)
            relative = f".concord/delegated-results/{path.name}"
            entities = [_entity("delegation", path.stem, "artifact_field")]
            if isinstance(value.get("wave_id"), str):
                entities.append(_entity("wave", value["wave_id"], "canonical_field_link"))
            events.append({
                "event_id": _event_id("delegation.completed", relative, None, "completed_at", value["completed_at"]),
                "type": "delegation.completed", "authority_class": "CANONICAL_RECORD", "lane": "attributed",
                "occurred_at": completed.isoformat(), "occurred_epoch": int(completed.timestamp()), "time_basis": "artifact_field",
                "title": f"Delegation {path.stem} abgeschlossen" + (f": {_text(value.get('scope'), 80)}" if value.get("scope") else ""),
                "detail": _text(value.get("conclusion"), 160), "significance": 1, "entities": entities, "commit": None,
                "source": {"path": relative, "field": "completed_at", "before": None, "after": _text(value["completed_at"], 40)},
                "change_set_id": None, "mission_label": None, "mission_id": None, "health": [],
            })
    return events


# --------------------------------------------------------------------------- index
_MEMORY: dict[tuple[str, str], dict[str, Any]] = {}
_LOCK = threading.Lock()


_TRAILER_LINE = re.compile(r"(?im)^mxagile-(origin|mission|change-set):[ \t]*(\S.*?)\s*$")
_CHANGE_SET_ID = re.compile(r"^CS-[A-Za-z0-9._-]+$")


def _trailer_values(commit: dict[str, Any]) -> dict[str, list[str]]:
    values: dict[str, list[str]] = {}
    for match in _TRAILER_LINE.finditer(commit["body"]):
        values.setdefault(match.group(1).lower(), []).append(match.group(2))
    return values


def _entry(mode: str, oid: str) -> dict[str, str] | None:
    return None if set(mode) == {"0"} else {"mode": mode, "oid": oid}


def _verify_inline(commit: dict[str, Any], blobs: dict[str, bytes], validator: Any) -> dict[str, Any]:
    """Equivalent of reconciliation_git._verify_change_set for single-parent commits, using data already in hand."""
    trailers = _trailer_values(commit)
    if any(len(trailers.get(key, [])) != 1 for key in ("origin", "mission", "change-set")):
        return {"invalid": "COMMIT_TRAILER_UNVERIFIED"}
    origin, mission_id, change_set_id = trailers["origin"][0], trailers["mission"][0], trailers["change-set"][0]
    if origin.casefold() != "mxagile" or not _CHANGE_SET_ID.fullmatch(change_set_id):
        return {"invalid": "COMMIT_TRAILER_UNVERIFIED"}
    changes = {change["path"]: change for change in commit["changes"]}
    manifest_path = f"{CHANGE_SET_DIRECTORY}/{change_set_id}.json"
    manifest = changes.get(manifest_path)
    if manifest is None or manifest["status"] != "A":
        return {"invalid": "COMMIT_TRAILER_UNVERIFIED"}
    raw = blobs.get(manifest["new"])
    try:
        document = json.loads(raw.decode("utf-8-sig")) if raw else None
    except (UnicodeError, ValueError):
        document = None
    if not isinstance(document, dict) or validator is None or list(validator.iter_errors(document)):
        return {"invalid": "CHANGE_SET_SCHEMA_INVALID"}
    if document.get("mission_id") != mission_id or document.get("change_set_id") != change_set_id or document.get("parent_commits") != commit["parents"]:
        return {"invalid": "COMMIT_TRAILER_UNVERIFIED"}
    declared: set[str] = set()
    for item in document.get("paths", []):
        path = item["path"]
        actual = changes.get(path)
        if path in declared or path == manifest_path or actual is None or actual["status"] != item["status"]:
            return {"invalid": "COMMIT_TRAILER_UNVERIFIED"}
        before, after = _entry(actual["old_mode"], actual["old"]), _entry(actual["new_mode"], actual["new"])
        if (before or {}).get("oid") != item["before_blob"] or (after or {}).get("oid") != item["after_blob"] \
                or item.get("before_mode", (before or {}).get("mode")) != (before or {}).get("mode") \
                or item.get("after_mode", (after or {}).get("mode")) != (after or {}).get("mode"):
            return {"invalid": "COMMIT_TRAILER_UNVERIFIED"}
        declared.add(path)
    return {"change_set_id": change_set_id, "paths": declared}


def _trailer_info(root: Path, commit: dict[str, Any], blobs: dict[str, bytes], validator: Any) -> dict[str, Any] | None:
    keys = set(_trailer_values(commit))
    if not keys:
        return None
    if keys != {"origin", "mission", "change-set"}:
        return {"invalid": "COMMIT_TRAILER_UNVERIFIED"}  # incomplete trailers never attribute
    if len(commit["parents"]) <= 1:
        return _verify_inline(commit, blobs, validator)
    try:
        import reconciliation_git as rg
        result = rg._classify_commit(root, commit["hash"], parents=commit["parents"], message=(commit["subject"] + "\n\n" + commit["body"]).encode("utf-8"))
    except Exception:
        return {"invalid": "COMMIT_TRAILER_UNVERIFIABLE"}
    if result.get("change_set_id"):
        declared = {item["path"] for item in result.get("paths", []) if item.get("classification") == "MXAGILE_ATTRIBUTED_CHANGE"}
        return {"change_set_id": result["change_set_id"], "paths": declared}
    reason = str(result.get("reason") or "")
    return {"invalid": "CHANGE_SET_SCHEMA_INVALID" if "SCHEMA" in reason or "INVALID" in reason else "COMMIT_TRAILER_UNVERIFIED"}


def _change_set_validator() -> Any:
    try:
        from jsonschema import Draft7Validator
        return Draft7Validator(json.loads((_schema_root() / "change-set.schema.json").read_text(encoding="utf-8-sig")))
    except (OSError, ValueError, ImportError):
        return None


def _git_index(root: Path, repo: dict[str, Any], previous: dict[str, Any] | None) -> dict[str, Any]:
    last = None
    if previous and previous.get("format") == INDEX_FORMAT and previous.get("repo", {}).get("toplevel") == repo["toplevel"] \
            and previous.get("repo", {}).get("prefix") == repo["prefix"]:
        known = previous.get("head")
        if known == repo["head"]:
            return previous
        ancestor = _run_git(root, "merge-base", "--is-ancestor", known, repo["head"]) if known else None
        if ancestor is not None and ancestor.returncode == 0:
            last = known
    commits = _scan(root, f"{last}..{repo['head']}" if last else None)
    prefix = repo["prefix"]
    for commit in commits:
        kept = []
        for change in commit["changes"]:
            path = change["path"]
            if prefix:
                if not path.startswith(prefix):
                    continue
                path = path[len(prefix):]
            kept.append({**change, "path": path})
        commit["changes"] = kept
    needed: set[str] = set()
    for commit in commits:
        complete = set(_trailer_values(commit)) == {"origin", "mission", "change-set"}
        for change in commit["changes"]:
            path = change["path"]
            wanted = path == PROCESS_STATE or path in (MISSION_STATE, CONTEXT_EPOCH, FRAMEWORK_VERSION) or _classify(path) \
                or (complete and path.startswith(CHANGE_SET_DIRECTORY + "/"))
            if wanted:
                for oid in (change["old"], change["new"]):
                    if not _ZERO_OID.match(oid):
                        needed.add(oid)
    blobs = _read_blobs(root, needed)
    validator = _change_set_validator()
    events: list[dict[str, Any]] = []
    summaries: list[dict[str, Any]] = []
    changeset_commits: dict[str, dict[str, Any]] = dict(previous.get("changeset_commits", {})) if last and previous else {}
    for commit in reversed(commits):  # oldest first so that `seq` is chronological
        trailer = _trailer_info(root, commit, blobs, validator)
        commit_events, summary = _commit_events(commit, blobs, trailer)
        events.extend(commit_events)
        summaries.append(summary)
        for change in commit["changes"]:
            if change["path"].startswith(CHANGE_SET_DIRECTORY + "/") and change["status"] in ("A", "M"):
                changeset_commits[change["path"]] = {"hash": commit["hash"], "epoch": commit["epoch"], "iso": commit["iso"],
                                                     "author": commit["author"], "subject": commit["subject"][:200]}
    if last and previous:
        events = previous["events"] + events
        summaries = previous["commits"] + summaries
    for seq, summary in enumerate(summaries):
        summary["seq"] = seq
    return {"format": INDEX_FORMAT, "rule": RULE_VERSION, "repo": {"toplevel": repo["toplevel"], "prefix": repo["prefix"]},
            "head": repo["head"], "shallow": repo["shallow"], "events": events, "commits": summaries,
            "changeset_commits": changeset_commits, "incremental": bool(last), "scanned_commits": len(commits)}


def _write_atomic(path: Path, payload: dict[str, Any]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        handle, temp = tempfile.mkstemp(prefix="timeline-", suffix=".tmp", dir=str(path.parent))
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, ensure_ascii=False, separators=(",", ":"))
        os.replace(temp, path)
    except OSError:
        pass


_REPO_CHECK: dict[str, tuple[float, dict[str, Any] | None]] = {}


def get_index(root: Path, *, rebuild: bool = False, ttl: float = 0.0) -> dict[str, Any]:
    """Timeline index for the current HEAD: memory -> disk (incremental) -> full build. Never writes into the project.

    `ttl` > 0 lets interactive callers reuse a recent HEAD observation instead of spawning git per request.
    """
    root = Path(root).resolve()
    started = time.perf_counter()
    seen = _REPO_CHECK.get(str(root))
    if ttl > 0 and seen is not None and time.monotonic() - seen[0] < ttl and not rebuild:
        repo = seen[1]
    else:
        repo = repository_state(root)
        _REPO_CHECK[str(root)] = (time.monotonic(), repo)
    if repo is None:
        return {"state": "NOT_OBSERVABLE", "reason": "NO_GIT_HISTORY", "events": [], "commits": [], "meta": {"state": "NOT_OBSERVABLE", "reason": "NO_GIT_HISTORY"}}
    key = (str(root), repo["head"])
    with _LOCK:
        cached = _MEMORY.get(key)
        if cached is not None and not rebuild:
            return cached
        cache_file = _cache_file(root, repo)
        previous = None
        if cache_file is not None and cache_file.is_file() and not rebuild:
            try:
                previous = json.loads(cache_file.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                previous = None
        git_part = _git_index(root, repo, previous)
        if cache_file is not None and git_part is not previous:
            _write_atomic(cache_file, git_part)
        events = list(git_part["events"]) + _canonical_events(root, repo, git_part.get("changeset_commits", {}))
        merged: dict[str, dict[str, Any]] = {}
        for event in events:
            merged.setdefault(event["event_id"], event)
        ordered = sorted(merged.values(), key=lambda item: (-item["occurred_epoch"], item["event_id"]))
        index = {
            "state": "READY", "reason": None, "events": ordered, "commits": git_part["commits"],
            "meta": {"state": "READY", "reason": None, "head": repo["head"][:12], "branch": repo["branch"], "shallow": repo["shallow"],
                     "incremental": git_part.get("incremental", False), "scanned_commits": git_part.get("scanned_commits", 0),
                     "build_seconds": round(time.perf_counter() - started, 3), "event_count": len(ordered), "rule_version": RULE_VERSION},
        }
        if len(_MEMORY) > 8:
            _MEMORY.clear()
        _MEMORY[key] = index
        return index


# --------------------------------------------------------------------------- queries
FILTER_KEYS = ("from", "to", "type", "group", "wave", "requirement", "page", "decision", "entity", "mission", "change_set",
               "authority", "lane", "min_significance", "include_mentions", "cursor", "limit")


def _matches(event: dict[str, Any], filters: dict[str, str]) -> bool:
    if filters.get("type") and not event["type"].startswith(filters["type"]):
        return False
    if filters.get("group") and _group_of(event["type"]) != filters["group"]:
        return False
    if filters.get("authority") and event["authority_class"] != filters["authority"]:
        return False
    if filters.get("lane") and event["lane"] != filters["lane"]:
        return False
    if filters.get("min_significance") and event["significance"] < int(filters["min_significance"]):
        return False
    if filters.get("from") and event["occurred_at"][:10] < filters["from"]:
        return False
    if filters.get("to") and event["occurred_at"][:10] > filters["to"]:
        return False
    if filters.get("mission") and filters["mission"] not in (event.get("mission_id"), event.get("mission_label")):
        return False
    if filters.get("change_set") and event.get("change_set_id") != filters["change_set"]:
        return False
    weak = filters.get("include_mentions") == "1" or filters.get("authority") == "GIT_MENTION"
    wanted = [("wave", filters.get("wave")), ("requirement", filters.get("requirement")), ("page", filters.get("page")), ("decision", filters.get("decision"))]
    if filters.get("entity") and ":" in filters["entity"]:
        wanted.append(tuple(filters["entity"].split(":", 1)))  # type: ignore[arg-type]
    for kind, identifier in wanted:
        if identifier and not any(e["type"] == kind and e["id"] == identifier and (weak or e["derivation"] != "message_mention") for e in event["entities"]):
            return False
    return True


def query(index: dict[str, Any], filters: dict[str, str]) -> dict[str, Any]:
    limit = max(1, min(int(filters.get("limit") or 50), 200))
    events = [event for event in index["events"] if _matches(event, filters)]
    start = 0
    cursor = filters.get("cursor")
    if cursor:
        for position, event in enumerate(events):
            if f"{event['occurred_epoch']}:{event['event_id']}" == cursor:
                start = position + 1
                break
    page = events[start:start + limit]
    next_cursor = f"{page[-1]['occurred_epoch']}:{page[-1]['event_id']}" if page and start + limit < len(events) else None
    return {"events": page, "next_cursor": next_cursor, "total": len(events), "index": index["meta"]}


def wave_history(root: Path) -> dict[str, Any]:
    """Per-Wave DONE reconstruction from the process-state history (BRD-F-56). Never reopens a Wave."""
    index = get_index(root)
    if index["state"] != "READY":
        return {"observation_state": "NOT_OBSERVABLE", "reason": index.get("reason"), "waves": {}}
    done: dict[str, dict[str, Any]] = {}
    for event in index["events"]:
        if event["type"] != "wave.phase_changed" or (event["source"] or {}).get("after") != "done" or not event["commit"]:
            continue
        wave = next((e["id"] for e in event["entities"] if e["type"] == "wave"), None)
        if wave and (wave not in done or event["occurred_epoch"] > done[wave]["epoch"]):
            done[wave] = {"commit": event["commit"]["hash"][:12], "epoch": event["occurred_epoch"], "event_id": event["event_id"]}
    seq_of = {summary["hash"]: summary["seq"] for summary in index["commits"]}
    result: dict[str, Any] = {}
    for wave, info in done.items():
        seq = seq_of.get(info["commit"])
        later = [s for s in index["commits"] if seq is not None and s["seq"] > seq]
        linked = [s for s in later if wave in s["waves"]]
        result[wave] = {
            "commit": info["commit"], "committed_at": info["epoch"], "event_id": info["event_id"],
            "linked_artifact_commits": len(linked), "linked_commit_hashes": [s["hash"][:7] for s in linked[-5:]],
            "project_activity_commits": sum(1 for s in later if s["delivery"]),
        }
    return {"observation_state": "AVAILABLE", "reason": None, "waves": result}


# --------------------------------------------------------------------------- CLI
def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only evidence-based project timeline (derived, never written into the project)")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--rebuild", action="store_true", help="ignore the disposable index and rebuild from Git")
    parser.add_argument("--limit", type=int, default=20)
    for key in FILTER_KEYS:
        if key not in ("limit",):
            parser.add_argument(f"--{key.replace('_', '-')}")
    args = parser.parse_args()
    filters = {key: str(getattr(args, key)) for key in FILTER_KEYS if key != "limit" and getattr(args, key, None) is not None}
    filters["limit"] = str(args.limit)
    index = get_index(Path(args.project_root), rebuild=args.rebuild)
    print(json.dumps(query(index, filters) if index["state"] == "READY" else {"events": [], "index": index["meta"]}, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
