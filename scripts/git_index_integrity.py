"""Read-only Git index damage containment; never attribute cause or recover automatically."""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
from pathlib import Path


def git(root: Path, *arguments: str) -> bytes:
    result = subprocess.run(["git", "--no-optional-locks", "-C", str(root), *arguments], capture_output=True)
    if result.returncode:
        raise ValueError("GIT_QUERY_FAILED")
    return result.stdout


def git_activity() -> bool | None:
    try:
        if os.name == "nt":
            result = subprocess.run(["tasklist", "/FI", "IMAGENAME eq git.exe", "/FO", "CSV", "/NH"], capture_output=True, text=True, check=True)
            return any(row and row[0].lower() == "git.exe" for row in csv.reader(result.stdout.splitlines()))
        result = subprocess.run(["ps", "-A", "-o", "comm="], capture_output=True, text=True, check=True)
        return any(Path(line.strip()).name == "git" for line in result.stdout.splitlines())
    except (OSError, subprocess.SubprocessError):
        return None


def inspect_index(root: Path) -> dict:
    report = {
        "read_only": True, "state": "GIT_INDEX_NOT_CHECKED", "mutations_allowed": False,
        "head_entry_count": None, "index_entry_count": None, "staged_deletion_count": None,
        "working_tree_present_count": None, "working_tree_files_present": None,
        "index_lock_present": None, "git_process_active": None,
        "reason": None, "recovery_command": None,
    }
    if not (root / ".git").exists():
        report.update(state="GIT_INDEX_NOT_APPLICABLE", mutations_allowed=True, reason="NO_GIT_WORKTREE")
        return report
    try:
        top = Path(os.fsdecode(git(root, "rev-parse", "--show-toplevel")).strip()).resolve()
        lock_path = Path(os.fsdecode(git(top, "rev-parse", "--git-path", "index.lock")).strip())
        if not lock_path.is_absolute():
            lock_path = top / lock_path
        report["index_lock_present"] = lock_path.exists()
        if lock_path.exists():
            activity = git_activity()
            report.update(git_process_active=activity,
                          state="GIT_OPERATION_IN_PROGRESS" if activity else ("GIT_INDEX_LOCK_STALE_CANDIDATE" if activity is False else "GIT_INDEX_LOCK_UNVERIFIED"),
                          reason="LOCK_NOT_REMOVED; process observation does not establish lock ownership")
            return report
        head_check = subprocess.run(["git", "--no-optional-locks", "-C", str(top), "rev-parse", "--verify", "HEAD"], capture_output=True)
        if head_check.returncode:
            reference = os.fsdecode(git(top, "symbolic-ref", "--quiet", "HEAD")).strip()
            refs = git(top, "for-each-ref", "--format=%(refname)").splitlines()
            if reference.encode() in refs:
                raise ValueError("HEAD_UNREADABLE")
            report.update(state="GIT_INDEX_NOT_APPLICABLE", mutations_allowed=True, reason="UNBORN_HEAD")
            return report
        head = [path for path in git(top, "ls-tree", "-r", "--name-only", "-z", "HEAD").split(b"\0") if path]
        index = [entry for entry in git(top, "ls-files", "--stage", "-z").split(b"\0") if entry]
        deleted = [path for path in git(top, "diff", "--cached", "--no-renames", "--name-only", "--diff-filter=D", "-z", "HEAD", "--").split(b"\0") if path]
        present = sum(os.path.lexists(top / os.fsdecode(path)) for path in (deleted or head))
        report.update(head_entry_count=len(head), index_entry_count=len(index), staged_deletion_count=len(deleted),
                      working_tree_present_count=present, working_tree_files_present=bool(present))
        if head and not index and len(deleted) == len(head) and present:
            report.update(state="GIT_INDEX_INTEGRITY_FAILURE", reason="EMPTY_INDEX_WITH_RETAINED_HEAD_FILES; cause unproven",
                          recovery_command="git restore --source=HEAD --staged -- :/")
        else:
            report.update(state="GIT_INDEX_PLAUSIBLE", mutations_allowed=True)
    except (OSError, ValueError):
        report.update(state="GIT_INDEX_NOT_CHECKED", reason="GIT_OR_REPOSITORY_UNAVAILABLE")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    report = inspect_index(args.project_root.resolve())
    print(json.dumps(report, sort_keys=True, indent=2))
    return 0 if report["mutations_allowed"] else 4


if __name__ == "__main__":
    raise SystemExit(main())