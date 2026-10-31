"""Read-only external-change report and explicit MxAgile baseline adoption."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from git_index_integrity import inspect_index
from jsonschema import Draft7Validator


STATE_SCHEMA = "project-reconciliation-state.schema.json"
STATE_DIRECTORY = Path(".mxagile/state/reconciliation")
SHA256_PATTERN = re.compile(r"^sha256:[a-f0-9]{64}$")


class ReconciliationError(ValueError):
    pass


def _git(root: Path, *args: str, allow_failure: bool = False) -> bytes:
    result = subprocess.run(
        ["git", "--no-optional-locks", "-C", str(root), *args],
        capture_output=True,
        check=False,
    )
    if result.returncode and not allow_failure:
        raise ReconciliationError("GIT_QUERY_FAILED")
    return result.stdout


def _git_text(root: Path, *args: str, allow_failure: bool = False) -> str:
    return os.fsdecode(_git(root, *args, allow_failure=allow_failure)).strip()


def _is_ignored(root: Path, path: Path) -> bool:
    relative = path.relative_to(root).as_posix()
    result = subprocess.run(
        ["git", "--no-optional-locks", "-C", str(root), "check-ignore", "--no-index", "--quiet", "--", relative],
        capture_output=True,
        check=False,
    )
    if result.returncode not in (0, 1):
        raise ReconciliationError("GIT_IGNORE_CHECK_FAILED")
    return result.returncode == 0


def _sha256(value: str) -> str:
    return "sha256:" + hashlib.sha256(os.fsencode(value)).hexdigest()


def _state_schema(root: Path) -> dict[str, Any]:
    path = root / ".mxagile/schemas" / STATE_SCHEMA
    if not path.is_file():
        raise ReconciliationError("STATE_SCHEMA_UNAVAILABLE")
    try:
        schema = json.loads(path.read_text(encoding="utf-8-sig"))
        Draft7Validator.check_schema(schema)
    except (OSError, ValueError, TypeError):
        raise ReconciliationError("STATE_SCHEMA_INVALID") from None
    return schema


def _validate_state(root: Path, state: dict[str, Any]) -> None:
    errors = sorted(Draft7Validator(_state_schema(root)).iter_errors(state), key=lambda error: list(error.path))
    if errors:
        raise ReconciliationError("RECONCILIATION_STATE_INVALID")


def _git_paths(root: Path) -> dict[str, Path]:
    top = Path(_git_text(root, "rev-parse", "--show-toplevel")).resolve()
    if top != root.resolve():
        raise ReconciliationError("PROJECT_ROOT_NOT_GIT_ROOT")
    git_dir = Path(_git_text(root, "rev-parse", "--git-dir"))
    common_dir = Path(_git_text(root, "rev-parse", "--git-common-dir"))
    if not git_dir.is_absolute():
        git_dir = root / git_dir
    if not common_dir.is_absolute():
        common_dir = root / common_dir
    return {"git_dir": git_dir.resolve(), "common_dir": common_dir.resolve()}


def _active_operations(root: Path) -> list[str]:
    operations: list[str] = []
    for name in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD"):
        if Path(_git_text(root, "rev-parse", "--git-path", name)).exists():
            operations.append(name.removesuffix("_HEAD"))
    for name in ("rebase-merge", "rebase-apply"):
        if Path(_git_text(root, "rev-parse", "--git-path", name)).exists():
            operations.append("REBASE")
            break
    return sorted(set(operations))


def _project_fingerprint(root: Path) -> str:
    scripts_dir = Path(__file__).resolve().parent
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    try:
        from build_project_status import build_status

        fingerprint = build_status(root).get("source_fingerprint")
    except Exception as exc:
        raise ReconciliationError(f"PROJECT_FINGERPRINT_UNAVAILABLE:{type(exc).__name__}") from None
    if not isinstance(fingerprint, str) or not SHA256_PATTERN.fullmatch(fingerprint):
        raise ReconciliationError("PROJECT_FINGERPRINT_INVALID")
    return fingerprint


def _artifact_index_fingerprint(root: Path) -> str | None:
    path = root / ".mxagile/state/artifact-index.json"
    if not path.is_file():
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig")).get("source_fingerprint")
    except (OSError, ValueError, AttributeError):
        return None
    return value if isinstance(value, str) and SHA256_PATTERN.fullmatch(value) else None


def _branch_state_path(root: Path, branch_ref: str) -> tuple[Path, str, str]:
    paths = _git_paths(root)
    repository_identity = _sha256(str(paths["common_dir"]))
    worktree_identity = _sha256(str(paths["git_dir"]))
    branch_key = _sha256(branch_ref)
    repository_key = repository_identity.removeprefix("sha256:")
    worktree_key = worktree_identity.removeprefix("sha256:")
    branch_key_path = branch_key.removeprefix("sha256:") + ".json"
    path = root / STATE_DIRECTORY / repository_key / worktree_key / branch_key_path
    return path, repository_identity, worktree_identity


def _snapshot(root: Path) -> dict[str, Any]:
    root = root.resolve()
    integrity = inspect_index(root)
    result: dict[str, Any] = {
        "read_only": True,
        "git_integrity": integrity,
        "operations_in_progress": [],
        "working_tree_clean": None,
        "repository_identity": None,
        "worktree_identity": None,
        "branch_ref": None,
        "head": None,
        "head_tree_oid": None,
        "shallow_repository": None,
        "state_path": None,
        "watermark": None,
    }
    if integrity.get("state") != "GIT_INDEX_PLAUSIBLE":
        result["status"] = "GIT_INTEGRITY_BLOCKED"
        return result
    try:
        paths = _git_paths(root)
        branch_ref = _git_text(root, "symbolic-ref", "--quiet", "HEAD", allow_failure=True)
        head = _git_text(root, "rev-parse", "--verify", "HEAD")
        if not branch_ref:
            result.update(status="DETACHED_HEAD", head=head)
            return result
        if not re.fullmatch(r"refs/heads/.+", branch_ref):
            result.update(status="BRANCH_REF_INVALID", head=head)
            return result
        repository_identity = _sha256(str(paths["common_dir"]))
        worktree_identity = _sha256(str(paths["git_dir"]))
        state_path, _, _ = _branch_state_path(root, branch_ref)
        operations = _active_operations(root)
        status_bytes = _git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all")
        shallow = _git_text(root, "rev-parse", "--is-shallow-repository") == "true"
        result.update({
            "operations_in_progress": operations,
            "working_tree_clean": not bool(status_bytes),
            "repository_identity": repository_identity,
            "worktree_identity": worktree_identity,
            "branch_ref": branch_ref,
            "head": head,
            "head_tree_oid": _git_text(root, "rev-parse", "HEAD^{tree}"),
            "shallow_repository": shallow,
            "state_path": state_path,
        })
        if operations:
            result["status"] = "GIT_OPERATION_IN_PROGRESS"
            return result
        if not status_bytes:
            pass
        else:
            result["status"] = "DIRTY_UNRECONCILED"
        if state_path.is_file():
            try:
                watermark = json.loads(state_path.read_text(encoding="utf-8-sig"))
                _validate_state(root, watermark)
                result["watermark"] = watermark
            except (OSError, ValueError, TypeError):
                result["status"] = "WATERMARK_INVALID"
                return result
        if result.get("status") == "DIRTY_UNRECONCILED":
            return result
        if result["watermark"] is None:
            result["status"] = "BASELINE_REQUIRED"
        elif result["watermark"]["last_reconciled_commit"] == head:
            result["status"] = "NO_COMMITTED_DELTA"
        else:
            result["status"] = "DELTA_DETECTION_PENDING"
        return result
    except ReconciliationError as exc:
        result["status"] = str(exc)
        return result


def build_report(project_root: str | Path) -> dict[str, Any]:
    """Build an observational report without writing project or runtime state."""
    return _snapshot(Path(project_root))


def _atomic_write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            json.dump(value, handle, ensure_ascii=False, sort_keys=True, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def adopt_baseline(project_root: str | Path, *, confirmed: bool = False) -> dict[str, Any]:
    """Explicitly accept the clean current HEAD as a baseline; never scans history."""
    root = Path(project_root).resolve()
    if not confirmed:
        return {"status": "BASELINE_CONFIRMATION_REQUIRED", "read_only": True, "watermark": None}
    report = _snapshot(root)
    if report["status"] == "GIT_INTEGRITY_BLOCKED":
        return {"status": report["status"], "read_only": True, "git_integrity": report["git_integrity"], "watermark": None}
    if report["status"] in ("DETACHED_HEAD", "GIT_OPERATION_IN_PROGRESS"):
        return {"status": report["status"], "read_only": True, "watermark": None}
    if report["status"] == "DIRTY_UNRECONCILED":
        return {"status": "BASELINE_REQUIRES_CLEAN_TREE", "read_only": True, "watermark": None}
    if report["status"] not in ("BASELINE_REQUIRED", "NO_COMMITTED_DELTA", "DELTA_DETECTION_PENDING"):
        return {"status": report["status"], "read_only": True, "watermark": None}
    state_path = report["state_path"]
    if not isinstance(state_path, Path):
        return {"status": "WATERMARK_PATH_UNAVAILABLE", "read_only": True, "watermark": None}
    if not _is_ignored(root, state_path):
        return {"status": "WATERMARK_PATH_NOT_IGNORED", "read_only": True, "watermark": None}
    lock_path = state_path.with_suffix(state_path.suffix + ".adoption-lock")
    lock_fd: int | None = None
    try:
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        lock_fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        if state_path.exists():
            return {"status": "WATERMARK_ALREADY_EXISTS", "read_only": True, "watermark": None}
        latest = _snapshot(root)
        if any(latest.get(key) != report.get(key) for key in (
            "repository_identity", "worktree_identity", "branch_ref", "head", "head_tree_oid", "working_tree_clean"
        )) or latest["status"] != report["status"]:
            return {"status": "REPOSITORY_CHANGED_DURING_ADOPTION", "read_only": True, "watermark": None}
        state = {
            "schema_version": 1,
            "repository_identity": report["repository_identity"],
            "worktree_identity": report["worktree_identity"],
            "branch_ref": report["branch_ref"],
            "branch_key": _sha256(report["branch_ref"]),
            "last_reconciled_commit": report["head"],
            "head_tree_oid": report["head_tree_oid"],
            "project_fingerprint": _project_fingerprint(root),
            "artifact_index_fingerprint": _artifact_index_fingerprint(root),
            "baseline_kind": "EXPLICIT_ADOPTION",
            "last_change_set_ids": [],
            "context_epoch": None,
            "last_report_id": None,
            "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        }
        _validate_state(root, state)
        _atomic_write_json(state_path, state)
        return {
            "status": "BASELINE_ADOPTED",
            "read_only": False,
            "state_path": state_path.relative_to(root).as_posix(),
            "watermark": state,
        }
    except FileExistsError:
        return {"status": "BASELINE_ADOPTION_IN_PROGRESS", "read_only": True, "watermark": None}
    except ReconciliationError as exc:
        return {"status": str(exc), "read_only": True, "watermark": None}
    except OSError:
        return {"status": "BASELINE_WRITE_FAILED", "read_only": True, "watermark": None}
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
            try:
                lock_path.unlink()
            except OSError:
                pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("report", help="Emit a read-only reconciliation status report.")
    adoption = commands.add_parser("adopt-baseline", help="Explicitly accept clean current HEAD as baseline.")
    adoption.add_argument("--confirm-baseline-adoption", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = build_report(args.project_root) if args.command == "report" else adopt_baseline(
            args.project_root, confirmed=args.confirm_baseline_adoption
        )
    except (OSError, ReconciliationError) as exc:
        result = {"status": str(exc) if isinstance(exc, ReconciliationError) else "REPORT_UNAVAILABLE", "read_only": True}
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2, default=str))
    if args.command == "adopt-baseline" and result.get("status") != "BASELINE_ADOPTED":
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())