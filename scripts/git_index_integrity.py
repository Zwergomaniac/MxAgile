"""Read-only Git index damage containment; never attribute cause or recover automatically."""

from __future__ import annotations

import argparse
import csv
import hashlib
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
            result = subprocess.run(["tasklist", "/FI", "IMAGENAME eq git.exe", "/FO", "CSV", "/NH"], capture_output=True, text=True, errors='replace', check=True)
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


def git_path(root: Path, name: str) -> Path:
    value = Path(os.fsdecode(git(root, 'rev-parse', '--git-path', name)).strip())
    return value if value.is_absolute() else root / value


def names(raw: bytes) -> list[str]:
    return sorted(os.fsdecode(item) for item in raw.split(b'\0') if item)


def file_probe(path: Path) -> str:
    if not path.exists():
        return 'NOT_PRESENT'
    if os.name != 'nt':
        return 'UNKNOWN'
    import ctypes
    from ctypes import wintypes
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.CreateFileW(str(path), 0x80000000, 0, None, 3, 0, None)
    if handle == wintypes.HANDLE(-1).value:
        return 'SHARING_VIOLATION' if ctypes.get_last_error() == 32 else 'UNKNOWN'
    kernel.CloseHandle(handle)
    return 'NO_SHARING_CONFLICT_OBSERVED'


def protected_fingerprint(root: Path, paths: list[str]) -> tuple[str, bool]:
    fingerprint = hashlib.sha256()
    complete = True
    for relative in paths:
        path = root / relative
        if not path.resolve(strict=False).is_relative_to(root):
            complete = False
            continue
        fingerprint.update(os.fsencode(relative) + b'\0')
        try:
            if any(part.startswith('.env') or part in ('.mcp.json', '.npmrc') or part.endswith(('.pem', '.key')) for part in path.relative_to(root).parts):
                complete = False
            elif path.is_symlink():
                fingerprint.update(os.fsencode(os.readlink(path)))
            elif path.is_file():
                with path.open('rb') as handle:
                    while block := handle.read(1024 * 1024):
                        fingerprint.update(block)
            elif not path.exists():
                fingerprint.update(b'MISSING')
            else:
                complete = False
        except OSError:
            complete = False
    return fingerprint.hexdigest(), complete


def runtime_processes() -> dict:
    try:
        if os.name == 'nt':
            result = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], capture_output=True, text=True, errors='replace', check=True)
            processes = [{'name': row[0], 'pid': row[1]} for row in csv.reader(result.stdout.splitlines())
                         if len(row) >= 2 and any(token in row[0].lower() for token in ('git', 'sqlite', 'studio', 'modeler', 'concord', 'mxcli', 'node', 'python'))]
        else:
            result = subprocess.run(['ps', '-A', '-o', 'pid=,comm='], capture_output=True, text=True, check=True)
            processes = [{'pid': parts[0], 'name': parts[1]} for line in result.stdout.splitlines()
                         if len(parts := line.strip().split(None, 1)) == 2 and any(token in parts[1].lower() for token in ('git', 'sqlite', 'studio', 'modeler', 'concord', 'mxcli', 'node', 'python'))]
        return {'state': 'OBSERVED', 'processes': processes, 'file_handle_ownership': 'UNKNOWN'}
    except (OSError, subprocess.SubprocessError):
        return {'state': 'UNAVAILABLE', 'processes': [], 'file_handle_ownership': 'UNKNOWN'}


def cache_observations(root: Path, tracked: list[str] | None = None, scope: list[str] | None = None) -> list[dict]:
    observations = []
    for name in ('recipe-cache.sqlite-shm', 'recipe-cache.sqlite-wal'):
        relative = '.concord/journal/' + name
        path = root / relative
        try:
            if not path.exists():
                continue
            probe = file_probe(path) if path.resolve().is_relative_to(root.resolve()) else 'UNSAFE_PATH'
        except OSError:
            probe = 'UNKNOWN'
        observations.append({'path': relative, 'tracked': relative in tracked if tracked is not None else 'UNKNOWN',
                             'in_recovery_scope': relative in scope if scope is not None else 'UNKNOWN',
                             'runtime_cache_candidate': True, 'probe': probe, 'owner': 'UNKNOWN'})
    return observations


def recovery_snapshot(root: Path, operation: str, scope: list[str] | None = None) -> dict:
    root = Path(os.fsdecode(git(root, 'rev-parse', '--show-toplevel')).strip()).resolve()
    head = os.fsdecode(git(root, 'rev-parse', '--verify', 'HEAD')).strip()
    operations = {
        'merge-abort': git_path(root, 'MERGE_HEAD').is_file(),
        'rebase-abort': git_path(root, 'rebase-merge').is_dir() or git_path(root, 'rebase-apply/rebasing').is_file(),
        'cherry-pick-abort': git_path(root, 'CHERRY_PICK_HEAD').is_file(),
    }
    staged = names(git(root, 'diff', '--cached', '--no-renames', '--name-only', '-z', 'HEAD', '--'))
    unstaged = names(git(root, 'diff', '--no-renames', '--name-only', '-z', '--'))
    untracked = names(git(root, 'ls-files', '--others', '--exclude-standard', '-z'))
    if scope is None:
        scope = []
        if operation == 'merge-abort' and operations[operation]:
            other = os.fsdecode(git(root, 'rev-parse', '--verify', 'MERGE_HEAD^{commit}')).strip()
            scope = names(git(root, 'diff', '--no-renames', '--name-only', '-z', 'HEAD', other, '--'))
            scope = sorted(set(scope + names(git(root, 'diff', '--name-only', '--diff-filter=U', '-z', '--'))))
    tracked = names(git(root, 'ls-files', '-z'))
    head_paths = names(git(root, 'ls-tree', '-r', '--name-only', '-z', 'HEAD'))
    protected = sorted(set(tracked + head_paths + untracked) - set(scope))
    worktree_hash, complete = protected_fingerprint(root, protected)
    sensitive = any(part.startswith('.env') or part in ('.mcp.json', '.npmrc') or part.endswith(('.pem', '.key'))
                    for relative in set(tracked + head_paths + untracked) for part in Path(relative).parts)
    complete = complete and not sensitive
    index_entries = git(root, 'ls-files', '--stage', '-z').split(b'\0')
    protected_index = b'\0'.join(entry for entry in index_entries if entry and os.fsdecode(entry.split(b'\t', 1)[1]) not in scope)
    locks = [name for name in ('index.lock', 'HEAD.lock', 'packed-refs.lock') if git_path(root, name).exists()]
    caches = cache_observations(root, tracked, scope)
    status = git(root, 'status', '--porcelain=v1', '-z', '--untracked-files=all')
    diff = git(root, 'diff', '--no-ext-diff', '--no-textconv', '--binary', '--') if complete else b'UNAVAILABLE'
    cached = git(root, 'diff', '--cached', '--no-ext-diff', '--no-textconv', '--binary', 'HEAD', '--') if complete else b'UNAVAILABLE'
    return {
        'repository_identity': hashlib.sha256(os.fsencode(root)).hexdigest(),
        'head': head, 'branch': os.fsdecode(git(root, 'rev-parse', '--abbrev-ref', 'HEAD')).strip(),
        'operations': operations, 'scope': scope, 'index': inspect_index(root), 'locks': locks,
        'autostash_present': git_path(root, 'MERGE_AUTOSTASH').exists(),
        'git_process_active': git_activity(), 'runtime_processes': runtime_processes(), 'tool_handle_owner': 'UNKNOWN', 'cache_files': caches,
        'staged_count': len(staged), 'unstaged_count': len(unstaged), 'untracked_count': len(untracked),
        'unmerged_entry_count': sum(bool(entry) and entry.split(b'\t', 1)[0].split()[-1] != b'0' for entry in index_entries),
        'unrelated_staged_count': len(set(staged) - set(scope)),
        'protected_worktree_fingerprint': worktree_hash, 'protected_index_fingerprint': hashlib.sha256(protected_index).hexdigest(),
        'preservation_check_complete': complete,
        'content_diff_check_available': complete,
        'status_fingerprint': hashlib.sha256(status).hexdigest(),
        'diff_fingerprint': hashlib.sha256(diff).hexdigest(), 'cached_diff_fingerprint': hashlib.sha256(cached).hexdigest(),
        'scoped_head_files_present': all(os.path.lexists(root / path) for path in set(scope).intersection(head_paths)),
    }


def recovery_preflight(root: Path, operation: str, *, user_authorized: bool = False, scope_reviewed: bool = False) -> dict:
    result = {'mode': 'CONTROLLED_RECOVERY', 'read_only': True, 'state': 'RECOVERY_BLOCKED',
              'operation': operation, 'command': None, 'reason': None, 'snapshot': None}
    commands = {'merge-abort': ['git', 'merge', '--abort'], 'index-rebuild': ['git', 'restore', '--source=HEAD', '--staged', '--', ':/']}
    if operation not in commands:
        result.update(state='RECOVERY_ESCALATION_REQUIRED', reason='NO_AUTOMATIC_DESTRUCTIVE_OR_UNBOUNDED_FALLBACK')
        return result
    try:
        snapshot = recovery_snapshot(root, operation)
        result['snapshot'] = snapshot
        if not user_authorized or not scope_reviewed:
            result['reason'] = 'EXPLICIT_USER_AUTHORIZATION_AND_SCOPE_REVIEW_REQUIRED'
        elif snapshot['locks'] or snapshot['git_process_active'] is not False:
            result['reason'] = 'LOCK_OR_CONCURRENT_GIT_STATE_NOT_CLEARED'
        elif snapshot.get('autostash_present'):
            result['reason'] = 'AUTOSTASH_REQUIRES_SEPARATE_PRESERVATION_REVIEW'
        elif any(item['in_recovery_scope'] and item['probe'] not in ('NOT_PRESENT', 'NO_SHARING_CONFLICT_OBSERVED') for item in snapshot['cache_files']):
            result['reason'] = 'CACHE_FILE_LOCK_OR_OWNER_UNVERIFIED; no deletion or process termination'
        elif not snapshot['preservation_check_complete']:
            result['reason'] = 'PRESERVATION_UNVERIFIED; secure affected changes before recovery'
        elif operation == 'merge-abort' and (not snapshot['operations'][operation] or sum(snapshot['operations'].values()) != 1):
            result['reason'] = 'NO_UNIQUE_CURRENT_MERGE_STATE'
        elif operation == 'merge-abort' and snapshot['unrelated_staged_count']:
            result['reason'] = 'UNRELATED_STAGED_CHANGES_REQUIRE_PRESERVATION'
        elif operation == 'index-rebuild' and (any(snapshot['operations'].values()) or snapshot['index']['state'] != 'GIT_INDEX_INTEGRITY_FAILURE'
                or snapshot['index']['working_tree_present_count'] != snapshot['index']['head_entry_count']):
            result['reason'] = 'INDEX_ONLY_RECOVERY_NOT_ESTABLISHED'
        else:
            result.update(state='RECOVERY_READY', command=commands[operation])
    except (OSError, ValueError):
        result['reason'] = 'RECOVERY_PREFLIGHT_UNAVAILABLE'
        result['cache_files'] = cache_observations(root)
        result['runtime_processes'] = runtime_processes()
    return result


def verify_recovery(root: Path, before: dict, command_exit: int | None = None) -> dict:
    result = {'read_only': True, 'state': 'RECOVERY_FAILED', 'resync_required': False, 'resume_allowed': False}
    if before.get('state') != 'RECOVERY_READY' or not isinstance(before.get('snapshot'), dict):
        result['reason'] = 'NO_VALID_READY_BASELINE'
        return result
    try:
        baseline = before['snapshot']
        after = recovery_snapshot(root, before['operation'], baseline['scope'])
        result['after'] = after
        stable = all(after[key] == baseline[key] for key in ('repository_identity', 'head', 'branch', 'protected_worktree_fingerprint'))
        index_preserved = before['operation'] == 'index-rebuild' or after['protected_index_fingerprint'] == baseline['protected_index_fingerprint']
        valid = (stable and index_preserved and after['preservation_check_complete'] and after['scoped_head_files_present']
             and not any(after['operations'].values()) and after['index']['state'] == 'GIT_INDEX_PLAUSIBLE'
                 and not after['locks'] and not after.get('autostash_present', False)
                 and after['unmerged_entry_count'] == 0 and after['git_process_active'] is False)
        if valid and command_exit == 0:
            result.update(state='RECOVERY_SUCCESS', resync_required=True)
        else:
            result.update(state='RECOVERY_PARTIAL', reason='POSTCONDITIONS_OR_COMMAND_EXIT_NOT_VERIFIED; STOP')
    except (OSError, ValueError, KeyError, TypeError):
        result['reason'] = 'RECOVERY_VERIFICATION_UNAVAILABLE; STOP'
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--recovery', help='Read-only bounded recovery preflight; never executes the proposed command.')
    mode.add_argument('--verify-before', type=Path, help='External JSON preflight baseline for read-only post-check.')
    parser.add_argument('--user-authorized', action='store_true')
    parser.add_argument('--scope-reviewed', action='store_true')
    parser.add_argument('--command-exit', type=int)
    args = parser.parse_args()
    if args.recovery:
        report = recovery_preflight(args.project_root.resolve(), args.recovery, user_authorized=args.user_authorized, scope_reviewed=args.scope_reviewed)
        print(json.dumps(report, sort_keys=True, indent=2))
        return 0 if report['state'] == 'RECOVERY_READY' else 4
    if args.verify_before:
        try:
            before = json.loads(args.verify_before.read_text(encoding='utf-8-sig'))
            report = verify_recovery(args.project_root.resolve(), before, args.command_exit)
        except (OSError, ValueError, TypeError, AttributeError):
            report = {'state': 'RECOVERY_FAILED', 'reason': 'BASELINE_UNAVAILABLE', 'resume_allowed': False}
        print(json.dumps(report, sort_keys=True, indent=2))
        return 0 if report['state'] == 'RECOVERY_SUCCESS' else 4
    report = inspect_index(args.project_root.resolve())
    print(json.dumps(report, sort_keys=True, indent=2))
    return 0 if report["mutations_allowed"] else 4


if __name__ == "__main__":
    raise SystemExit(main())