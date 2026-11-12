"""Validated, append-only runtime audit events; canonical lifecycle state remains authoritative."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
import time
import uuid
from functools import lru_cache
from pathlib import Path
from typing import Any

try:
    import jsonschema
except ImportError:
    jsonschema = None

SCHEMA_VERSION = 1
MAX_EVENT_BYTES = 8192
MAX_STREAM_BYTES = 5 * 1024 * 1024
MAX_EVENT_STORE_BYTES = 100 * 1024 * 1024
MAX_READ_FILES = 1200
MAX_EVENTS = 5000
EVENT_DIR = Path(".mxagile/state/runs")
SCHEMA_PATH = Path(__file__).with_name("run-event.schema.json")
TERMINAL_TYPES = {"child_accepted", "child_partial", "child_rejected", "child_stale", "child_needs_human",
                  "run_completed", "run_abandoned", "lifecycle_resync_completed", "update_completed", "migration_completed"}
START_TYPES = {"child_started", "run_started", "update_started", "migration_started", "lifecycle_resync_started"}
_LOCKS: dict[str, Any] = {}
_LOCKS_GUARD = __import__("threading").Lock()


def project_identity(root: Path) -> str:
    return "LOCAL-" + hashlib.sha256(str(root.resolve()).casefold().encode("utf-8")).hexdigest()[:20]


def _safe_event_dir(root: Path, *, create: bool = False) -> Path:
    root = root.resolve()
    directory = root / EVENT_DIR
    if create:
        directory.mkdir(parents=True, exist_ok=True)
    resolved = directory.resolve(strict=create)
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise ValueError("EVENT_PATH_OUTSIDE_PROJECT") from exc
    if directory.is_symlink():
        raise ValueError("EVENT_DIRECTORY_SYMLINK")
    return resolved


@lru_cache(maxsize=1)
def _schema() -> dict:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    return schema


def validate_event(event: dict[str, Any]) -> list[str]:
    if jsonschema is None:
        return ["JSONSCHEMA_UNAVAILABLE"]
    validator = _validator()
    return [error.message for error in validator.iter_errors(event)]


@lru_cache(maxsize=1)
def _validator():
    return jsonschema.Draft7Validator(_schema(), format_checker=jsonschema.FormatChecker())


class _FileLock:
    def __init__(self, path: Path, timeout: float = 10.0):
        self.path, self.timeout, self.handle = path, timeout, None
        with _LOCKS_GUARD:
            self.thread_lock = _LOCKS.setdefault(str(path.resolve()), __import__("threading").Lock())

    def __enter__(self):
        if not self.thread_lock.acquire(timeout=self.timeout):
            raise TimeoutError("EVENT_LOCK_TIMEOUT")
        try:
            self.handle = self.path.open("a+b")
            if os.name == "nt":
                import msvcrt
                self.handle.seek(0, os.SEEK_END)
                if self.handle.tell() == 0:
                    self.handle.write(b"\0")
                    self.handle.flush()
                self.handle.seek(0)
                deadline = time.monotonic() + self.timeout
                while True:
                    try:
                        msvcrt.locking(self.handle.fileno(), msvcrt.LK_NBLCK, 1)
                        break
                    except OSError:
                        if time.monotonic() >= deadline:
                            raise TimeoutError("EVENT_LOCK_TIMEOUT")
                        time.sleep(0.025)
            else:
                import fcntl
                fcntl.flock(self.handle.fileno(), fcntl.LOCK_EX)
        except Exception:
            if self.handle:
                self.handle.close()
            self.thread_lock.release()
            raise
        return self

    def __exit__(self, *_exc):
        if self.handle is None:
            return
        if os.name == "nt":
            import msvcrt
            self.handle.seek(0)
            msvcrt.locking(self.handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            fcntl.flock(self.handle.fileno(), fcntl.LOCK_UN)
        self.handle.close()
        self.thread_lock.release()


def _event_files(root: Path) -> list[Path]:
    directory = _safe_event_dir(root)
    if not directory.is_dir():
        return []
    files = sorted((path for path in directory.glob("events-*-????-??.jsonl") if path.is_file() and not path.is_symlink()),
                   key=lambda path: path.name)
    return files[-MAX_READ_FILES:]


def _read_log(path: Path) -> tuple[list[dict], int, bool]:
    raw = path.read_bytes()
    complete, has_partial = raw.rsplit(b"\n", 1)[0], bool(raw and not raw.endswith(b"\n"))
    rows: list[dict] = []
    invalid = 0
    if complete:
        for line in complete.splitlines():
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except (UnicodeDecodeError, json.JSONDecodeError):
                invalid += 1
                continue
            if validate_event(event):
                invalid += 1
                continue
            rows.append(event)
    return rows, invalid, has_partial


def read_events(root: str | Path, *, limit: int = 500) -> dict:
    root = Path(root).resolve()
    if limit < 1 or limit > MAX_EVENTS:
        raise ValueError("EVENT_LIMIT_OUT_OF_RANGE")
    events: list[dict] = []
    invalid = 0
    partial = 0
    for path in _event_files(root):
        rows, bad, tail = _read_log(path)
        events.extend(rows)
        invalid += bad
        partial += int(tail)
    events.sort(key=lambda item: (item["occurred_at"], item["run_id"], item["sequence"], item["event_id"]))
    return {"events": events[-limit:], "total_valid": len(events), "invalid_lines": invalid,
            "partial_tail_files": partial, "truncated": len(events) > limit}


def _next_sequence(directory: Path, run_id: str) -> tuple[int, int]:
    sequence = 0
    invalid = 0
    for path in _event_files(directory.parent.parent.parent):
        raw = path.read_bytes()
        if raw and not raw.endswith(b"\n"):
            last_newline = raw.rfind(b"\n")
            raw = raw[:last_newline + 1] if last_newline >= 0 else b""
            with path.open("r+b") as handle:
                handle.truncate(len(raw))
                handle.flush()
                os.fsync(handle.fileno())
        for line in raw.splitlines():
            if not line.strip():
                continue
            try:
                event = json.loads(line)
                if validate_event(event):
                    invalid += 1
                    continue
                if event["run_id"] == run_id:
                    sequence = max(sequence, int(event["sequence"]))
            except (ValueError, KeyError, TypeError, json.JSONDecodeError):
                invalid += 1
    return sequence + 1, invalid


def append_event(
    root: str | Path,
    event_type: str,
    *,
    run_id: str,
    parent_run_id: str | None = None,
    mission_id: str | None = None,
    wave_id: str | None = None,
    capability: str | None = None,
    actor: str = "mxagile",
    host: str = "unknown",
    correlation: dict | None = None,
    payload: dict | None = None,
    event_class: str | None = None,
    occurred_at: dt.datetime | None = None,
) -> dict:
    root = Path(root).resolve()
    directory = _safe_event_dir(root, create=True)
    now = occurred_at or dt.datetime.now(dt.timezone.utc)
    if now.tzinfo is None:
        raise ValueError("EVENT_TIMESTAMP_REQUIRES_TIMEZONE")
    stamp = now.astimezone(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    resolved_class = event_class or event_class_for(event_type)
    month_path = directory / f"events-{resolved_class}-{now.astimezone(dt.timezone.utc):%Y-%m}.jsonl"
    if month_path.is_symlink():
        raise ValueError("EVENT_LOG_SYMLINK")
    month_path.touch(exist_ok=True)
    event = {
        "schema_version": SCHEMA_VERSION,
        "event_id": f"EVT-{uuid.uuid4().hex}",
        "event_type": event_type,
        "event_class": resolved_class,
        "occurred_at": stamp,
        "sequence": 0,
        "run_id": run_id,
        "parent_run_id": parent_run_id,
        "project_identity": project_identity(root),
        "mission_id": mission_id,
        "wave_id": wave_id,
        "actor": actor,
        "capability": capability,
        "host": host,
        "correlation": correlation or {},
        "payload": payload or {},
    }
    lock_path = directory / f"{month_path.stem}.lock"
    with _FileLock(directory / "append.lock"), _FileLock(lock_path):
        _prune_retention(directory, now)
        if month_path.stat().st_size >= MAX_STREAM_BYTES:
            raise ValueError("EVENT_STREAM_SIZE_LIMIT")
        total_size = sum(path.stat().st_size for path in directory.glob("events-*-????-??.jsonl") if path.is_file() and not path.is_symlink())
        if total_size >= MAX_EVENT_STORE_BYTES:
            raise ValueError("EVENT_STORE_SIZE_LIMIT")
        sequence, _invalid = _next_sequence(directory, run_id)
        event["sequence"] = sequence
        errors = validate_event(event)
        if errors:
            raise ValueError("INVALID_EVENT: " + "; ".join(errors))
        encoded = (json.dumps(event, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode("utf-8")
        if len(encoded) > MAX_EVENT_BYTES:
            raise ValueError("EVENT_TOO_LARGE")
        with month_path.open("ab") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
    return event


def event_class_for(event_type: str) -> str:
    if event_type in {"unknown_tool_classification", "adapter_unavailable", "host_registration_missing", "event_write_failed"}:
        return "DIAGNOSTIC"
    if event_type in {"lifecycle_resync_completed", "update_started", "update_partial", "update_completed", "migration_started", "migration_completed"}:
        return "PROJECT_HISTORY"
    return "RUN_AUDIT"


def _prune_retention(directory: Path, now: dt.datetime) -> None:
    cutoffs = {"DIAGNOSTIC": now - dt.timedelta(days=30), "RUN_AUDIT": now - dt.timedelta(days=180)}
    for path in directory.glob("events-*-????-??.jsonl"):
        match = re.fullmatch(r"events-(DIAGNOSTIC|RUN_AUDIT)-(\d{4})-(\d{2})\.jsonl", path.name)
        if not match or path.is_symlink():
            continue
        year, month = int(match.group(2)), int(match.group(3))
        if not 1 <= month <= 12:
            continue
        if dt.datetime(year, month, 1, tzinfo=dt.timezone.utc) < cutoffs[match.group(1)].replace(day=1):
            path.unlink(missing_ok=True)


def revision(root: str | Path) -> str:
    files = _event_files(Path(root).resolve())
    digest = hashlib.sha256()
    for path in files:
        stat = path.stat()
        digest.update(path.name.encode("utf-8"))
        digest.update(str(stat.st_size).encode("ascii"))
        digest.update(str(stat.st_mtime_ns).encode("ascii"))
        if stat.st_size <= 1024 * 1024:
            digest.update(path.read_bytes())
    return digest.hexdigest()


def active_runs(events: list[dict]) -> list[dict]:
    grouped: dict[str, list[dict]] = {}
    for event in events:
        if event["event_type"] in START_TYPES | TERMINAL_TYPES | {"run_interrupted", "run_resumed"}:
            grouped.setdefault(event["run_id"], []).append(event)
    result = []
    for run_id, rows in grouped.items():
        rows.sort(key=lambda item: (item["occurred_at"], item["sequence"], item["event_id"]))
        first = rows[0]
        last = rows[-1]
        terminal = next((item for item in reversed(rows) if item["event_type"] in TERMINAL_TYPES), None)
        if terminal:
            continue
        interrupted = any(item["event_type"] == "run_interrupted" for item in rows) and not any(
            item["event_type"] == "run_resumed" and item["occurred_at"] > max(
                row["occurred_at"] for row in rows if row["event_type"] == "run_interrupted") for item in rows)
        if interrupted:
            status = "INTERRUPTED"
        else:
            status = "RESULT_UNKNOWN"
        result.append({"run_id": run_id, "parent_run_id": first["parent_run_id"], "mission_id": first["mission_id"],
                       "wave_id": first["wave_id"], "capability": first["capability"], "actor": first["actor"],
                       "host": first["host"], "status": status, "started_at": first["occurred_at"],
                       "last_event_at": last["occurred_at"], "event_count": len(rows),
                       "correlation": first["correlation"],
                       "reconciliation_state": "NEEDS_RECONCILIATION" if not terminal else None})
    result.sort(key=lambda item: (item["started_at"], item["run_id"]), reverse=True)
    return result


def resume_context(root: str | Path) -> dict:
    root = Path(root).resolve()
    snapshot = read_events(root, limit=MAX_EVENTS)
    guard_module = None
    try:
        try:
            import guard
        except ImportError:
            candidates = (root / ".mxagile/tools/control-plane", Path(__file__).resolve().parents[1] / "experiments/control-plane")
            for candidate in candidates:
                if (candidate / "guard.py").is_file():
                    sys.path.insert(0, str(candidate))
                    break
            import guard
        guard_module = guard
        facts = guard.load_project_facts(root)
        integrity, _ = guard._lifecycle_integrity(facts)
        mission_id = facts.mission.get("mission_id")
        wave_id = facts.mission.get("active_wave")
        wave = (facts.process_state.get("waves") or {}).get(wave_id) if wave_id else None
        canonical = {"mission_id": mission_id, "wave_id": wave_id,
                 "wave_phase": wave.get("phase") if isinstance(wave, dict) else None,
                     "head": facts.head, "branch": facts.branch,
                     "lifecycle_findings": [item["code"] for item in integrity if item.get("disposition") != "advisory"]}
    except Exception as exc:
        canonical = {"available": False, "reason": type(exc).__name__}
    runs = active_runs(snapshot["events"])
    for run in runs:
        handoff_reference = run["correlation"].get("handoff_reference")
        if not handoff_reference or guard_module is None:
            run["input_state"] = "NOT_OBSERVABLE"
            continue
        handoff_path = guard_module._safe_project_file(root, handoff_reference)
        try:
            handoff = json.loads(handoff_path.read_text(encoding="utf-8")) if handoff_path and handoff_path.is_file() else None
        except (OSError, ValueError):
            handoff = None
        sources = handoff.get("input_sources") if isinstance(handoff, dict) else None
        if not isinstance(sources, list):
            run["input_state"] = "NOT_OBSERVABLE"
            continue
        changed = []
        unavailable = []
        for source in sources:
            if not isinstance(source, dict) or not isinstance(source.get("path"), str):
                unavailable.append("invalid_source_reference")
                continue
            path = guard_module._safe_project_file(root, source["path"])
            if path is None or not path.is_file():
                unavailable.append(source["path"])
                continue
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != source.get("sha256"):
                changed.append(source["path"])
        run["input_state"] = "STALE" if changed else ("NOT_OBSERVABLE" if unavailable else "CURRENT")
        run["changed_inputs"] = changed
        run["unavailable_inputs"] = unavailable
    return {"canonical_state": canonical, "active_runs": runs,
            "unresolved_runs": [run for run in runs if run["reconciliation_state"]],
            "event_log": {key: snapshot[key] for key in ("total_valid", "invalid_lines", "partial_tail_files", "truncated")},
            "resume_rule": "Re-read canonical state; event history is audit only."}


def _cli() -> int:
    parser = argparse.ArgumentParser(description="Inspect validated MxAgile run/audit events and reconcile resume context.")
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("read")
    commands.add_parser("resume")
    args = parser.parse_args()
    try:
        if args.command == "read":
            output = read_events(args.project_root)
        else:
            output = resume_context(args.project_root)
    except Exception as exc:
        output = {"error": type(exc).__name__, "reason": str(exc)}
        print(json.dumps(output, sort_keys=True))
        return 2
    print(json.dumps(output, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(_cli())
