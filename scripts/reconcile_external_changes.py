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
from reconciliation_git import (
    GitReconciliationError,
    analyze_commit_range,
    classify_path,
    prepare_change_set,
    working_tree_changes,
)


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
    for name, operation in (
        ("MERGE_HEAD", "MERGE"), ("CHERRY_PICK_HEAD", "CHERRY_PICK"),
        ("REVERT_HEAD", "REVERT"), ("rebase-merge", "REBASE"), ("rebase-apply", "REBASE"),
    ):
        path = Path(_git_text(root, "rev-parse", "--git-path", name))
        if not path.is_absolute():
            path = root / path
        if path.exists():
            operations.append(operation)
    return sorted(set(operations))


def _project_fingerprint(root: Path) -> str:
    return _project_status(root)["source_fingerprint"]


def _project_status(root: Path) -> dict[str, Any]:
    scripts_dir = Path(__file__).resolve().parent
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    try:
        from build_project_status import build_status

        status = build_status(root)
    except Exception as exc:
        raise ReconciliationError(f"PROJECT_FINGERPRINT_UNAVAILABLE:{type(exc).__name__}") from None
    fingerprint = status.get("source_fingerprint")
    if not isinstance(fingerprint, str) or not SHA256_PATTERN.fullmatch(fingerprint):
        raise ReconciliationError("PROJECT_FINGERPRINT_INVALID")
    return status


def _artifact_index_fingerprint(root: Path) -> str | None:
    path = root / ".mxagile/state/artifact-index.json"
    if not path.is_file():
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig")).get("source_fingerprint")
    except (OSError, ValueError, AttributeError):
        return None
    return value if isinstance(value, str) and SHA256_PATTERN.fullmatch(value) else None


def _impact_candidates(root: Path, changed_paths: list[dict[str, Any]]) -> dict[str, Any]:
    index_path = root / ".mxagile/state/artifact-index.json"
    if not index_path.is_file():
        return {"status": "INDEX_MISSING", "candidates": []}
    try:
        index = json.loads(index_path.read_text(encoding="utf-8-sig"))
        stored_fingerprint = index.get("source_fingerprint")
        scripts_dir = Path(__file__).resolve().parent
        if str(scripts_dir) not in sys.path:
            sys.path.insert(0, str(scripts_dir))
        from resolve_impact import _compute_current_fingerprint

        if stored_fingerprint != _compute_current_fingerprint(root):
            return {"status": "INDEX_STALE", "candidates": []}
        nodes = {node.get("id"): node for node in index.get("nodes", []) if isinstance(node, dict) and isinstance(node.get("id"), str)}
        edges = [edge for edge in index.get("edges", []) if isinstance(edge, dict)]
    except Exception:
        return {"status": "INDEX_INVALID", "candidates": []}

    result = []
    for changed in changed_paths:
        canonical_path = changed.get("path")
        if not isinstance(canonical_path, str):
            continue
        direct_ids = sorted(node_id for node_id, node in nodes.items() if node.get("path") == canonical_path)
        related_ids: set[str] = set()
        for edge in edges:
            provenance = edge.get("provenance") if isinstance(edge.get("provenance"), dict) else {}
            if provenance.get("type") != "DECLARED":
                continue
            source = edge.get("from")
            target = edge.get("to")
            if source in direct_ids and target in nodes:
                related_ids.add(target)
            if target in direct_ids and source in nodes:
                related_ids.add(source)
        result.append({
            "path": canonical_path,
            "path_class": classify_path(canonical_path),
            "artifact_ids": direct_ids,
            "related_artifact_ids": sorted(related_ids),
        })
    return {"status": "CURRENT", "candidates": result}


def _reference_candidates(committed_paths: list[dict[str, Any]], working_changes: dict[str, list[dict[str, str]]]) -> list[dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    allowed_extensions = {".html", ".htm", ".css", ".js", ".mjs", ".json", ".png", ".jpg", ".jpeg", ".svg", ".webp"}
    for item in committed_paths:
        path = item.get("path")
        if not isinstance(path, str) or classify_path(path) != "REFERENCE" or Path(path).suffix.lower() not in allowed_extensions:
            continue
        if item.get("classification") not in ("EXTERNAL_CHANGE", "AMBIGUOUS"):
            continue
        result[path] = {"path": path, "status": "REFERENCE_RECONCILIATION_REQUIRED"}
    for group in ("staged", "unstaged", "untracked"):
        for item in working_changes.get(group, []):
            path = item.get("path")
            if isinstance(path, str) and classify_path(path) == "REFERENCE" and Path(path).suffix.lower() in allowed_extensions:
                result[path] = {"path": path, "status": "DIRTY_REFERENCE_UNRECONCILED"}
    return [result[path] for path in sorted(result)]


def _model_semantic_capability(root: Path, changed_paths: list[str]) -> dict[str, Any]:
    model_paths = sorted({
        path for path in changed_paths
        if path.lower().endswith(".mpr") or path.lower().startswith("mprcontents/")
    })
    if not model_paths:
        return {"status": "NOT_APPLICABLE", "model_paths": [], "capabilities": []}
    if not list(root.glob("*.mpr")):
        return {"status": "SEMANTIC_REVIEW_REQUIRED", "reason": "PROJECT_MPR_NOT_FOUND", "model_paths": model_paths, "capabilities": []}
    binary_name = "mxcli.exe" if os.name == "nt" else "mxcli"
    binary = root / binary_name
    if not binary.is_file() or binary.is_symlink() or not binary.resolve().is_relative_to(root.resolve()):
        return {"status": "SEMANTIC_REVIEW_REQUIRED", "reason": "PROJECT_LOCAL_MXCLI_NOT_FOUND", "model_paths": model_paths, "capabilities": []}
    try:
        version_result = subprocess.run([str(binary), "--version"], cwd=root, capture_output=True, text=True, timeout=10, check=False)
        help_result = subprocess.run([str(binary), "--help"], cwd=root, capture_output=True, text=True, timeout=10, check=False)
    except (OSError, subprocess.SubprocessError):
        return {"status": "SEMANTIC_REVIEW_REQUIRED", "reason": "PROJECT_LOCAL_MXCLI_PROBE_FAILED", "model_paths": model_paths, "capabilities": []}
    if version_result.returncode or help_result.returncode:
        return {"status": "SEMANTIC_REVIEW_REQUIRED", "reason": "PROJECT_LOCAL_MXCLI_PROBE_FAILED", "model_paths": model_paths, "capabilities": []}
    help_text = (help_result.stdout + "\n" + help_result.stderr).casefold()
    capabilities = [name for name in ("inspect", "diff", "compare") if re.search(rf"\b{name}\b", help_text)]
    version = next((line.strip()[:120] for line in version_result.stdout.splitlines() if line.strip()), "UNKNOWN")
    reason = "SEMANTIC_MODEL_DIFF_NOT_VERIFIED" if not any(name in capabilities for name in ("diff", "compare")) else "MODEL_DIFF_COMMAND_SEMANTICS_UNVERIFIED"
    return {
        "status": "SEMANTIC_REVIEW_REQUIRED",
        "reason": reason,
        "model_paths": model_paths,
        "capabilities": capabilities,
        "project_mxcli_version": version,
    }


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
        "working_changes": {"staged": [], "unstaged": [], "untracked": []},
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
        if operations:
            result.update(
                status="GIT_OPERATION_IN_PROGRESS", operations_in_progress=operations,
                repository_identity=repository_identity, worktree_identity=worktree_identity,
                branch_ref=branch_ref, head=head, state_path=state_path,
            )
            return result
        status_bytes = _git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all")
        changes = working_tree_changes(root)
        shallow = _git_text(root, "rev-parse", "--is-shallow-repository") == "true"
        result.update({
            "operations_in_progress": operations,
            "working_tree_clean": not bool(status_bytes),
            "working_changes": changes,
            "repository_identity": repository_identity,
            "worktree_identity": worktree_identity,
            "branch_ref": branch_ref,
            "head": head,
            "head_tree_oid": _git_text(root, "rev-parse", "HEAD^{tree}"),
            "shallow_repository": shallow,
            "state_path": state_path,
        })
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
        if result["watermark"] is not None and (
            result["watermark"]["repository_identity"] != repository_identity
            or result["watermark"]["worktree_identity"] != worktree_identity
            or result["watermark"]["branch_ref"] != branch_ref
            or result["watermark"]["branch_key"] != _sha256(branch_ref)
        ):
            result["status"] = "WATERMARK_SCOPE_MISMATCH"
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


def build_report(project_root: str | Path, *, project_status: dict[str, Any] | None = None) -> dict[str, Any]:
    """Build an observational report without writing project or runtime state."""
    report = _snapshot(Path(project_root))
    watermark = report.get("watermark")
    finding_impacts: list[dict[str, Any]] = []
    report["impact_resolution"] = {"status": "BASELINE_REQUIRED", "candidates": []}
    report["external_reference_candidates"] = _reference_candidates([], report.get("working_changes", {}))
    if isinstance(watermark, dict) and report.get("head"):
        try:
            commit_range = analyze_commit_range(
                Path(project_root).resolve(),
                watermark["last_reconciled_commit"],
                report["head"],
                shallow=bool(report.get("shallow_repository")),
            )
        except GitReconciliationError as exc:
            commit_range = {"status": str(exc), "commits": [], "spans": []}
        report["commit_range"] = {
            "from_commit": watermark["last_reconciled_commit"],
            "to_commit": report["head"],
            **commit_range,
        }
        changed_paths = [
            path
            for commit in commit_range.get("commits", [])
            for path in commit.get("paths", [])
            if path.get("classification") != "PROVENANCE_METADATA"
        ]
        changed_external_paths = sorted({
            path["path"] for path in changed_paths
            if path.get("classification") in ("EXTERNAL_CHANGE", "AMBIGUOUS")
        })
        report["impact_resolution"] = _impact_candidates(
            Path(project_root).resolve(),
            [path for path in changed_paths if path.get("classification") in ("EXTERNAL_CHANGE", "AMBIGUOUS")],
        )
        report["external_reference_candidates"] = _reference_candidates(changed_paths, report.get("working_changes", {}))
        try:
            project_status = project_status or _project_status(Path(project_root).resolve())
            report["active_references"] = project_status.get("project", {}).get("active_targets", {}).get("items", [])
            findings = project_status.get("findings", {})
            for collection, terminal in (("items", False), ("history", True)):
                for finding in findings.get(collection, []):
                    source_paths = set(finding.get("source_artifact_paths", []))
                    source_ids = {
                        *finding.get("requirement_ids", []),
                        *finding.get("decision_ids", []),
                        *[source.get("artifact_id") for source in finding.get("source_artifacts", []) if source.get("artifact_id")],
                    }
                    framework_followup = finding.get("origin") == "FRAMEWORK_FOLLOWUP"
                    matched = []
                    for changed in changed_paths:
                        path = changed["path"]
                        is_external = changed.get("classification") in ("EXTERNAL_CHANGE", "AMBIGUOUS")
                        is_framework = path.startswith((".mxagile/", "scripts/", "docs/"))
                        if (
                            (is_external or (framework_followup and is_framework))
                            and (path in source_paths or Path(path).stem.upper() in source_ids)
                        ):
                            matched.append(changed)
                    if not matched:
                        continue
                    matched.sort(key=lambda item: item["path"])
                    finding_delta_fingerprint = _sha256(json.dumps([
                        {"path": item["path"], "before_blob": item.get("before_blob"), "after_blob": item.get("after_blob")}
                        for item in matched
                    ], sort_keys=True, separators=(",", ":")))
                    outcome = finding.get("reconciliation_outcome")
                    framework_evidence_valid = (
                        not framework_followup
                        or (
                            finding.get("lifecycle_status") == "VERIFIED"
                            and isinstance(finding.get("framework_commit"), str)
                            and isinstance(finding.get("resolution_commit"), str)
                            and any("doctor" in reference.casefold() for reference in finding.get("resolution_references", []))
                            and bool(finding.get("evidence_refs"))
                        )
                    )
                    assessed = (
                        finding.get("reconciliation_delta_fingerprint") == finding_delta_fingerprint
                        and outcome in ("STILL_VALID", "RECLASSIFIED", "RESOLVED", "SUPERSEDED", "RETIRED")
                        and bool(finding.get("reconciliation_evidence_refs"))
                        and framework_evidence_valid
                    )
                    if not assessed and framework_followup:
                        impact_status = "FRAMEWORK_FOLLOWUP_REVIEW_REQUIRED"
                    elif not assessed and terminal:
                        impact_status = "TERMINAL_FINDING_REVIEW_REQUIRED"
                    elif not assessed:
                        impact_status = "REASSESS_REQUIRED"
                    else:
                        impact_status = outcome
                    finding_impacts.append({
                        "finding_id": finding.get("id"),
                        "terminal": terminal,
                        "status": impact_status,
                        "changed_paths": [item["path"] for item in matched],
                        "delta_fingerprint": finding_delta_fingerprint,
                        "evidence_references": finding.get("reconciliation_evidence_refs", []) if assessed else [],
                    })
        except ReconciliationError as exc:
            report["finding_assessment_status"] = str(exc)
            report["active_references"] = []
        else:
            report["finding_assessment_status"] = "COMPLETE"
    else:
        report["commit_range"] = {"status": "BASELINE_REQUIRED", "commits": [], "spans": []}
        report["finding_assessment_status"] = "BASELINE_REQUIRED"
        report["active_references"] = []
    report["finding_impacts"] = finding_impacts
    model_paths = [
        path["path"]
        for commit in report["commit_range"].get("commits", [])
        for path in commit.get("paths", [])
        if path.get("path_class") == "MENDIX_MODEL"
    ] + [
        item["path"]
        for group in ("staged", "unstaged", "untracked")
        for item in report.get("working_changes", {}).get(group, [])
        if classify_path(item["path"]) == "MENDIX_MODEL"
    ]
    report["model_semantic_review"] = _model_semantic_capability(Path(project_root).resolve(), model_paths)
    report["watermark_gate"] = {
        "can_advance": False,
        "blockers": sorted({
            "FINDING_IMPACT_UNRECONCILED"
            for impact in finding_impacts
            if impact["status"] in ("REASSESS_REQUIRED", "TERMINAL_FINDING_REVIEW_REQUIRED", "FRAMEWORK_FOLLOWUP_REVIEW_REQUIRED")
        } | ({"AMBIGUOUS_HISTORY"} if report["commit_range"]["status"] == "AMBIGUOUS_HISTORY" else set())
          | ({"EXTERNAL_CHANGE_RECONCILIATION_REQUIRED"} if report["commit_range"]["status"] == "RECONCILIATION_REQUIRED" else set())),
    }
    report["can_advance_watermark"] = report["watermark_gate"]["can_advance"]
    stable_report = json.dumps(report, ensure_ascii=False, sort_keys=True, default=str)
    report["report_id"] = _sha256(stable_report)
    return report


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
            "reconciliation_references": [],
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


def advance_watermark(
    project_root: str | Path,
    *,
    confirmed: bool = False,
    expected_report_id: str | None = None,
    reconciled_paths: list[str] | None = None,
    impact_references: list[str] | None = None,
) -> dict[str, Any]:
    """Explicitly persist a fully classified, path-covered reconciliation watermark."""
    root = Path(project_root).resolve()
    if not confirmed:
        return {"status": "WATERMARK_ADVANCE_CONFIRMATION_REQUIRED", "read_only": True}
    if not isinstance(expected_report_id, str) or not SHA256_PATTERN.fullmatch(expected_report_id):
        return {"status": "EXPECTED_REPORT_ID_REQUIRED", "read_only": True}
    initial = _snapshot(root)
    watermark = initial.get("watermark")
    if not isinstance(watermark, dict):
        return {"status": initial.get("status", "BASELINE_REQUIRED"), "read_only": True}
    if initial.get("status") == "GIT_OPERATION_IN_PROGRESS" or not initial.get("working_tree_clean"):
        return {"status": "WATERMARK_ADVANCE_REQUIRES_CLEAN_TREE", "read_only": True}
    if initial.get("git_integrity", {}).get("state") != "GIT_INDEX_PLAUSIBLE":
        return {"status": "GIT_INTEGRITY_BLOCKED", "read_only": True}

    report = build_report(root)
    if report.get("report_id") != expected_report_id:
        return {"status": "RECONCILIATION_REPORT_CHANGED", "read_only": True, "report_id": report.get("report_id")}
    range_status = report.get("commit_range", {}).get("status")
    if range_status == "AMBIGUOUS_HISTORY":
        return {"status": "AMBIGUOUS_HISTORY", "read_only": True}
    if range_status not in ("NO_COMMITTED_DELTA", "MXAGILE_ATTRIBUTED_ONLY", "RECONCILIATION_REQUIRED"):
        return {"status": "HISTORY_NOT_RECONCILED", "read_only": True, "range_status": range_status}
    if report.get("finding_assessment_status") != "COMPLETE":
        return {"status": "FINDING_ASSESSMENT_UNAVAILABLE", "read_only": True}
    unresolved_findings = [
        impact for impact in report.get("finding_impacts", [])
        if impact.get("status") in ("REASSESS_REQUIRED", "TERMINAL_FINDING_REVIEW_REQUIRED", "FRAMEWORK_FOLLOWUP_REVIEW_REQUIRED")
    ]
    if unresolved_findings:
        return {"status": "FINDING_IMPACT_UNRECONCILED", "read_only": True, "finding_ids": sorted(item["finding_id"] for item in unresolved_findings)}
    model_review = report.get("model_semantic_review", {})
    if model_review.get("status") == "SEMANTIC_REVIEW_REQUIRED":
        return {"status": "SEMANTIC_REVIEW_REQUIRED", "read_only": True, "model_paths": model_review.get("model_paths", [])}

    external_paths = sorted({
        path["path"]
        for commit in report["commit_range"].get("commits", [])
        for path in commit.get("paths", [])
        if path.get("classification") == "EXTERNAL_CHANGE"
    })
    supplied_paths = sorted(set(reconciled_paths or []))
    if supplied_paths != external_paths:
        return {"status": "EXTERNAL_PATH_COVERAGE_MISMATCH", "read_only": True, "required_paths": external_paths}
    references = sorted(set(impact_references or []))
    if external_paths and not references:
        return {"status": "IMPACT_REFERENCES_REQUIRED", "read_only": True}
    for reference in references:
        if (
            not isinstance(reference, str)
            or reference.startswith("/")
            or "\\" in reference
            or any(part in ("", ".", "..") for part in reference.split("/"))
            or not reference.startswith(("planning/reconciliation/", "planning/decisions/", "planning/findings/", "planning/evidence/"))
        ):
            return {"status": "IMPACT_REFERENCE_INVALID", "read_only": True}
        path = root / reference
        tracked = subprocess.run(
            ["git", "--no-optional-locks", "-C", str(root), "ls-files", "--error-unmatch", "--", reference],
            capture_output=True,
            check=False,
        )
        if path.is_symlink() or not path.is_file() or tracked.returncode:
            return {"status": "IMPACT_REFERENCE_NOT_TRACKED", "read_only": True, "reference": reference}

    latest = _snapshot(root)
    stable_keys = ("repository_identity", "worktree_identity", "branch_ref", "head", "head_tree_oid", "working_tree_clean")
    if any(latest.get(key) != initial.get(key) for key in stable_keys) or not latest.get("working_tree_clean"):
        return {"status": "REPOSITORY_CHANGED_BEFORE_WATERMARK_WRITE", "read_only": True}
    if latest.get("git_integrity", {}).get("state") != "GIT_INDEX_PLAUSIBLE":
        return {"status": "GIT_INTEGRITY_BLOCKED", "read_only": True}

    current_report = build_report(root)
    if current_report.get("report_id") != expected_report_id:
        return {"status": "RECONCILIATION_REPORT_CHANGED", "read_only": True, "report_id": current_report.get("report_id")}
    state_path = initial.get("state_path")
    if not isinstance(state_path, Path) or not _is_ignored(root, state_path):
        return {"status": "WATERMARK_PATH_NOT_IGNORED", "read_only": True}
    state = {
        "schema_version": 1,
        "repository_identity": initial["repository_identity"],
        "worktree_identity": initial["worktree_identity"],
        "branch_ref": initial["branch_ref"],
        "branch_key": _sha256(initial["branch_ref"]),
        "last_reconciled_commit": initial["head"],
        "head_tree_oid": initial["head_tree_oid"],
        "project_fingerprint": _project_fingerprint(root),
        "artifact_index_fingerprint": _artifact_index_fingerprint(root),
        "baseline_kind": "RECONCILED",
        "last_change_set_ids": sorted({
            commit["change_set_id"] for commit in current_report["commit_range"].get("commits", [])
            if isinstance(commit.get("change_set_id"), str)
        }),
        "reconciliation_references": references,
        "context_epoch": None,
        "last_report_id": expected_report_id,
        "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    }
    try:
        _validate_state(root, state)
        _atomic_write_json(state_path, state)
        after = _snapshot(root)
        if any(after.get(key) != initial.get(key) for key in stable_keys) or after.get("git_integrity", {}).get("state") != "GIT_INDEX_PLAUSIBLE":
            _atomic_write_json(state_path, watermark)
            return {"status": "REPOSITORY_CHANGED_DURING_WATERMARK_WRITE", "read_only": True}
        return {
            "status": "WATERMARK_ADVANCED",
            "read_only": False,
            "state_path": state_path.relative_to(root).as_posix(),
            "watermark": state,
        }
    except (OSError, ReconciliationError):
        return {"status": "WATERMARK_WRITE_FAILED", "read_only": True}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("report", help="Emit a read-only reconciliation status report.")
    adoption = commands.add_parser("adopt-baseline", help="Explicitly accept clean current HEAD as baseline.")
    adoption.add_argument("--confirm-baseline-adoption", action="store_true")
    advance = commands.add_parser("advance-watermark", help="Advance only after explicit, fully evidenced reconciliation.")
    advance.add_argument("--confirm-advance", action="store_true")
    advance.add_argument("--expected-report-id", required=True)
    advance.add_argument("--reconciled-path", action="append", default=[])
    advance.add_argument("--impact-reference", action="append", default=[])
    producer = commands.add_parser("prepare-change-set", help="Prepare Change-Set provenance for reviewed staged paths.")
    producer.add_argument("--confirm-preparation", action="store_true")
    producer.add_argument("--change-set-id", required=True)
    producer.add_argument("--mission-id", required=True)
    producer.add_argument("--context-epoch")
    producer.add_argument(
        "--reconciliation-outcome",
        required=True,
        choices=("NO_IMPACT", "IMPACT_RECONCILED", "DECISION_REQUIRED_PERSISTED"),
    )
    producer.add_argument("--result-reference", action="append", default=[])
    producer.add_argument("--reconciliation-reference", action="append", default=[])
    args = parser.parse_args(argv)
    try:
        if args.command == "report":
            result = build_report(args.project_root)
        elif args.command == "adopt-baseline":
            result = adopt_baseline(args.project_root, confirmed=args.confirm_baseline_adoption)
        elif args.command == "advance-watermark":
            result = advance_watermark(
                args.project_root,
                confirmed=args.confirm_advance,
                expected_report_id=args.expected_report_id,
                reconciled_paths=args.reconciled_path,
                impact_references=args.impact_reference,
            )
        elif not args.confirm_preparation:
            result = {"status": "CHANGE_SET_CONFIRMATION_REQUIRED", "read_only": True}
        else:
            root = args.project_root.resolve()
            integrity = inspect_index(root)
            if integrity.get("state") != "GIT_INDEX_PLAUSIBLE":
                result = {"status": "GIT_INTEGRITY_BLOCKED", "git_integrity": integrity, "read_only": True}
            else:
                result = prepare_change_set(
                    root,
                    change_set_id=args.change_set_id,
                    mission_id=args.mission_id,
                    context_epoch=args.context_epoch,
                    project_fingerprint=_project_fingerprint(root),
                    outcome=args.reconciliation_outcome,
                    result_references=args.result_reference,
                    reconciliation_references=args.reconciliation_reference,
                )
    except (OSError, ReconciliationError, GitReconciliationError) as exc:
        result = {
            "status": str(exc) if isinstance(exc, (ReconciliationError, GitReconciliationError)) else "REPORT_UNAVAILABLE",
            "read_only": True,
        }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2, default=str))
    if args.command == "adopt-baseline" and result.get("status") != "BASELINE_ADOPTED":
        return 2
    if args.command == "advance-watermark" and result.get("status") != "WATERMARK_ADVANCED":
        return 2
    if args.command == "prepare-change-set" and result.get("status") != "CHANGE_SET_PREPARED":
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())