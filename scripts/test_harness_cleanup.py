"""Read-only test-harness cleanup planner (RF-007).

Ownership of a temporary test-harness artifact is never inferred from a file extension.
A path is removable only when an explicit, worktree-local ownership record names it and the
current content still matches the content recorded at harness injection. Canonical Mendix model
artifacts (`*.mpr`, `mprcontents/**/*.mxunit`) additionally require an explicit model-unit
ownership acknowledgement. The planner never deletes or restores anything; it only reports.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from git_index_integrity import GIT_TIMEOUT_SECONDS, resolve_repository  # noqa: E402

MANIFEST_RELATIVE = ".mxagile/state/test-harness/ownership.json"
SCHEMA = "mxagile-test-harness-ownership/1"


def git(top: Path, *arguments: str) -> bytes:
    result = subprocess.run(["git", "--no-optional-locks", "-C", str(top), *arguments], capture_output=True, timeout=GIT_TIMEOUT_SECONDS)
    if result.returncode:
        raise ValueError("GIT_QUERY_FAILED")
    return result.stdout


def top_level(root: Path) -> Path:
    repository = resolve_repository(root)
    if repository is None:
        raise ValueError("NO_GIT_WORKTREE")
    return Path(repository["top_level"])


def is_model_artifact(top: Path, relative: str) -> bool:
    """Canonical model artifacts: the project .mpr and, in MPRv2 projects, every mprcontents unit."""
    if "/" not in relative and relative.lower().endswith(".mpr"):
        return True
    return relative.startswith("mprcontents/") and relative.lower().endswith(".mxunit") and any(top.glob("*.mpr"))


def safe_relative(top: Path, value: str) -> str | None:
    relative = value.replace("\\", "/").strip()
    if not relative or relative.startswith("/") or ":" in relative or any(part in ("", ".", "..") for part in relative.split("/")):
        return None
    if not (top / relative).resolve(strict=False).is_relative_to(top.resolve()):
        return None
    return relative


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            sha.update(block)
    return sha.hexdigest()


def load_manifest(top: Path) -> tuple[str, dict]:
    path = top / MANIFEST_RELATIVE
    if not path.is_file():
        return "ABSENT", {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("schema") != SCHEMA or not isinstance(data.get("entries"), list):
            return "INVALID", {}
        entries = {}
        for entry in data["entries"]:
            relative = safe_relative(top, str(entry.get("path", "")))
            if relative is None or not isinstance(entry.get("sha256"), str) or not entry.get("harness"):
                return "INVALID", {}
            entries[relative] = entry
        return "PRESENT", entries
    except (OSError, ValueError, AttributeError):
        return "INVALID", {}


def changed_paths(top: Path) -> list[tuple[str, str]]:
    raw = git(top, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames")
    return [(item[:2].decode(), os.fsdecode(item[3:])) for item in raw.split(b"\0") if item]


def plan(root: Path) -> dict:
    top = top_level(root)
    manifest_state, owned = load_manifest(top)
    report = {"read_only": True, "top_level": str(top), "manifest": MANIFEST_RELATIVE, "manifest_state": manifest_state,
              "removable": [], "preserved": []}
    for status, relative in changed_paths(top):
        if relative == MANIFEST_RELATIVE or relative.startswith(".mxagile/state/"):
            continue
        model = is_model_artifact(top, relative)
        entry = owned.get(relative) if manifest_state == "PRESENT" else None
        item = {"path": relative, "git_status": status, "model_artifact": model}
        path = top / relative
        if entry is None:
            reason = "CANONICAL_MODEL_ARTIFACT; no explicit harness ownership" if model else "REQUIRES_CLASSIFICATION; no explicit harness ownership"
            if manifest_state == "INVALID":
                reason = "OWNERSHIP_MANIFEST_INVALID; " + reason
            report["preserved"].append({**item, "reason": reason})
        elif model and entry.get("model_unit") is not True:
            report["preserved"].append({**item, "reason": "MODEL_ARTIFACT_OWNERSHIP_NOT_ACKNOWLEDGED"})
        elif "D" in status or not path.is_file():
            report["preserved"].append({**item, "reason": "OWNED_PATH_MISSING_OR_DELETED; no automatic restore"})
        elif digest(path) != entry["sha256"]:
            report["preserved"].append({**item, "reason": "CONTENT_CHANGED_SINCE_HARNESS_INJECTION; ownership no longer provable"})
        else:
            action = "delete-untracked" if status == "??" else "restore-from-HEAD"
            report["removable"].append({**item, "action": action, "harness": entry["harness"]})
    return report


def record(root: Path, paths: list[str], harness: str, model_unit: bool = False) -> dict:
    """Record explicit harness ownership right after harness injection (writes only the worktree-local manifest)."""
    top = top_level(root)
    state, entries = load_manifest(top)
    if state == "INVALID":
        return {"state": "RECORD_REFUSED", "reason": "OWNERSHIP_MANIFEST_INVALID"}
    changed = {relative for _, relative in changed_paths(top)}
    for value in paths:
        relative = safe_relative(top, value)
        if relative is None:
            return {"state": "RECORD_REFUSED", "reason": "UNSAFE_PATH", "path": value}
        if not (top / relative).is_file() or relative not in changed:
            return {"state": "RECORD_REFUSED", "reason": "PATH_NOT_A_CURRENT_HARNESS_CHANGE", "path": relative}
        if is_model_artifact(top, relative) and not model_unit:
            return {"state": "RECORD_REFUSED", "reason": "MODEL_ARTIFACT_REQUIRES_EXPLICIT_MODEL_UNIT_OWNERSHIP", "path": relative}
        entries[relative] = {"path": relative, "sha256": digest(top / relative), "harness": harness, "model_unit": is_model_artifact(top, relative)}
    manifest = top / MANIFEST_RELATIVE
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps({"schema": SCHEMA, "entries": sorted(entries.values(), key=lambda e: e["path"])}, indent=2) + "\n", encoding="utf-8")
    return {"state": "RECORDED", "manifest": MANIFEST_RELATIVE, "count": len(paths)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--record", nargs="+", metavar="PATH", help="Record explicit harness ownership for these paths.")
    parser.add_argument("--harness", help="Harness name for --record (e.g. MxTest).")
    parser.add_argument("--model-unit", action="store_true", help="Explicitly acknowledge harness ownership of canonical model artifacts.")
    args = parser.parse_args()
    try:
        if args.record:
            if not args.harness:
                parser.error("--record requires --harness")
            report = record(args.project_root.resolve(), args.record, args.harness, args.model_unit)
        else:
            report = plan(args.project_root.resolve())
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        report = {"state": "CLEANUP_PLAN_UNAVAILABLE", "reason": str(error) or type(error).__name__, "removable": []}
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report.get("state") not in ("RECORD_REFUSED", "CLEANUP_PLAN_UNAVAILABLE") else 4


if __name__ == "__main__":
    raise SystemExit(main())
