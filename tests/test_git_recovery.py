"""Controlled recovery contracts; real Git operations are confined to temp fixtures."""

import unittest
import sys
import subprocess
import tempfile
import os
import json
from unittest.mock import patch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import git_index_integrity


class RecoveryContractTests(unittest.TestCase):
    def test_postconditions_reject_unmerged_index_and_concurrent_git(self):
        baseline = {'repository_identity': 'fixture', 'head': 'unchanged', 'branch': 'main', 'scope': [],
                    'protected_worktree_fingerprint': 'same', 'protected_index_fingerprint': 'same'}
        after = {**baseline, 'preservation_check_complete': True, 'scoped_head_files_present': True,
                 'operations': {}, 'index': {'state': 'GIT_INDEX_PLAUSIBLE'}, 'locks': [],
                 'unmerged_entry_count': 1, 'git_process_active': False}
        before = {'state': 'RECOVERY_READY', 'operation': 'merge-abort', 'snapshot': baseline}
        with patch.object(git_index_integrity, 'recovery_snapshot', return_value=after):
            self.assertEqual(git_index_integrity.verify_recovery(ROOT, before, 0)['state'], 'RECOVERY_PARTIAL')
            after.update(unmerged_entry_count=0, git_process_active=True)
            self.assertEqual(git_index_integrity.verify_recovery(ROOT, before, 0)['state'], 'RECOVERY_PARTIAL')
            after['git_process_active'] = None
            self.assertEqual(git_index_integrity.verify_recovery(ROOT, before, 0)['state'], 'RECOVERY_PARTIAL')
            after.update(git_process_active=False, autostash_present=True)
            self.assertEqual(git_index_integrity.verify_recovery(ROOT, before, 0)['state'], 'RECOVERY_PARTIAL')

    def test_no_current_merge_never_authorizes_abort(self):
        snapshot = {'locks': [], 'git_process_active': False, 'preservation_check_complete': True,
                    'cache_files': [], 'operations': {'merge-abort': False, 'rebase-abort': False, 'cherry-pick-abort': False}}
        with patch.object(git_index_integrity, 'recovery_snapshot', return_value=snapshot):
            result = git_index_integrity.recovery_preflight(ROOT, 'merge-abort', user_authorized=True, scope_reviewed=True)
        self.assertEqual(result['state'], 'RECOVERY_BLOCKED')
        self.assertIsNone(result['command'])

    def test_explicit_recovery_is_not_general_git_authority(self):
        policy = (ROOT / '.mxagile/policies/safety-rules.md').read_text(encoding='utf-8')
        for marker in ('CONTROLLED_RECOVERY', 'MERGE_HEAD', 'git merge --abort',
                       'git restore --source=HEAD --staged -- :/', 'gezielte Nutzereskalation'):
            self.assertIn(marker, policy)
        self.assertIn('Allgemeine\nCommit-/Autonomie-Autoritaet reicht nicht', policy)
        routing = (ROOT / 'scripts/apply-project-agent-instructions.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('CONTROLLED_RECOVERY preflight, bounded operation and post-check', routing)
        self.assertIn('do not reject authorized recovery solely because normal Git writes are restricted', routing)

    def test_lock_failures_and_resume_remain_fail_closed(self):
        policy = (ROOT / '.mxagile/policies/safety-rules.md').read_text(encoding='utf-8')
        for marker in ('recipe-cache.sqlite-shm', 'recipe-cache.sqlite-wal', 'UNKNOWN bleibt UNKNOWN',
                       'RECOVERY_SUCCESS', 'RECOVERY_PARTIAL / RECOVERY_FAILED und STOP',
                       'Re-Sync vor Fortsetzung Pflicht', 'Recovery erfuellt keine Gates'):
            self.assertIn(marker, policy)


class RecoveryFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mxagile-recovery-')
        self.root = Path(self.temp.name)
        self.run_git('init', '--quiet', '-b', 'main')
        for name in ('conflict.txt', 'unrelated.txt'):
            (self.root / name).write_text('base\n', encoding='utf-8')
        self.run_git('add', '--all')
        self.run_git('commit', '--quiet', '-m', 'Base fixture')

    def tearDown(self):
        self.temp.cleanup()

    def run_git(self, *arguments):
        result = subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', *arguments], capture_output=True)
        if result.returncode:
            self.fail(result.stderr.decode(errors='replace'))
        return result.stdout

    def conflict(self):
        self.run_git('checkout', '--quiet', '-b', 'other')
        (self.root / 'conflict.txt').write_text('theirs\n', encoding='utf-8')
        self.run_git('commit', '--quiet', '-am', 'Other fixture')
        self.run_git('checkout', '--quiet', 'main')
        (self.root / 'conflict.txt').write_text('ours\n', encoding='utf-8')
        self.run_git('commit', '--quiet', '-am', 'Main fixture')
        result = subprocess.run(['git', '-C', str(self.root), 'merge', 'other'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / '.git/MERGE_HEAD').exists())

    def preflight(self, operation):
        with patch.object(git_index_integrity, 'git_activity', return_value=False):
            return git_index_integrity.recovery_preflight(self.root, operation, user_authorized=True, scope_reviewed=True)

    def test_r1_r4_r7_merge_abort_preserves_unrelated_changes_and_requires_resync(self):
        self.conflict()
        (self.root / 'unrelated.txt').write_text('preserve local work\n', encoding='utf-8')
        (self.root / 'notes.txt').write_text('preserve untracked\n', encoding='utf-8')
        before = self.preflight('merge-abort')
        self.assertEqual(before['state'], 'RECOVERY_READY', before['reason'])
        self.assertTrue((self.root / '.git/MERGE_HEAD').exists())
        self.run_git(*before['command'][1:])
        after = git_index_integrity.verify_recovery(self.root, before, 0)
        self.assertEqual(after['state'], 'RECOVERY_SUCCESS', after)
        self.assertTrue(after['resync_required'])
        self.assertFalse(after['resume_allowed'])
        self.assertEqual((self.root / 'unrelated.txt').read_text(), 'preserve local work\n')
        self.assertEqual((self.root / 'notes.txt').read_text(), 'preserve untracked\n')

    def test_r2_no_merge_metadata_never_aborts(self):
        self.assertEqual(self.preflight('merge-abort')['state'], 'RECOVERY_BLOCKED')

    def test_cli_without_user_authorization_cannot_start_recovery(self):
        index_bytes = (self.root / '.git/index').read_bytes()
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/git_index_integrity.py'),
                                 '--project-root', str(self.root), '--recovery', 'merge-abort'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 4, result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report['read_only'])
        self.assertIsNone(report['command'])
        self.assertEqual((self.root / '.git/index').read_bytes(), index_bytes)

    def test_r3_authorized_empty_index_rebuild_only(self):
        self.run_git('read-tree', '--empty')
        index_bytes = (self.root / '.git/index').read_bytes()
        before = self.preflight('index-rebuild')
        self.assertEqual(before['state'], 'RECOVERY_READY', before['reason'])
        self.assertEqual((self.root / '.git/index').read_bytes(), index_bytes)
        self.run_git(*before['command'][1:])
        self.assertEqual(git_index_integrity.verify_recovery(self.root, before, 0)['state'], 'RECOVERY_SUCCESS')

    def test_r4_unrelated_staged_changes_block_until_preserved(self):
        self.conflict()
        (self.root / 'unrelated.txt').write_text('do not lose staging\n', encoding='utf-8')
        self.run_git('add', '--', 'unrelated.txt')
        before = self.preflight('merge-abort')
        self.assertEqual(before['reason'], 'UNRELATED_STAGED_CHANGES_REQUIRE_PRESERVATION')
        self.assertIsNone(before['command'])

    def test_r5_sharing_violation_has_no_delete_or_kill_fallback(self):
        self.conflict()
        cache = self.root / '.concord/journal/recipe-cache.sqlite-wal'
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b'cache fixture')
        snapshot = git_index_integrity.recovery_snapshot(self.root, 'merge-abort')
        snapshot['git_process_active'] = False
        snapshot['cache_files'][0].update(tracked=True, in_recovery_scope=True, probe='SHARING_VIOLATION')
        with patch.object(git_index_integrity, 'recovery_snapshot', return_value=snapshot):
            result = self.preflight('merge-abort')
        self.assertIn('CACHE_FILE_LOCK', result['reason'])
        self.assertIsNone(result['command'])
        self.assertEqual(cache.read_bytes(), b'cache fixture')

    def test_r6_hard_reset_always_escalates(self):
        result = self.preflight('reset --hard')
        self.assertEqual(result['state'], 'RECOVERY_ESCALATION_REQUIRED')
        self.assertIsNone(result['command'])

    def test_r5_failed_git_query_retains_precise_lock_observation(self):
        cache = self.root / '.concord/journal/recipe-cache.sqlite-wal'
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b'cache fixture')
        with (
            patch.object(git_index_integrity, 'recovery_snapshot', side_effect=ValueError('GIT_QUERY_FAILED')),
            patch.object(git_index_integrity, 'file_probe', return_value='SHARING_VIOLATION'),
        ):
            result = self.preflight('merge-abort')
        self.assertEqual(result['state'], 'RECOVERY_BLOCKED')
        self.assertEqual(result['cache_files'][0]['probe'], 'SHARING_VIOLATION')
        self.assertEqual(result['cache_files'][0]['owner'], 'UNKNOWN')
        self.assertIsNone(result['command'])

    def test_missing_authority_and_failed_postconditions_are_not_success(self):
        self.conflict()
        denied = git_index_integrity.recovery_preflight(self.root, 'merge-abort')
        self.assertIsNone(denied['command'])
        before = self.preflight('merge-abort')
        self.assertEqual(git_index_integrity.verify_recovery(self.root, before, 1)['state'], 'RECOVERY_PARTIAL')

    def test_secret_source_is_not_read_as_recovery_evidence(self):
        path = self.root / '.env.mendix'
        path.write_text('sensitive-fixture-marker\n', encoding='utf-8')
        with patch.object(git_index_integrity, 'git', wraps=git_index_integrity.git) as queries:
            result = self.preflight('merge-abort')
        self.assertEqual(result['state'], 'RECOVERY_BLOCKED')
        self.assertFalse(any('--binary' in call.args for call in queries.call_args_list))
        self.assertNotIn('sensitive-fixture-marker', str(result))

    @unittest.skipUnless(os.name == 'nt', 'Windows sharing semantics')
    def test_r5_real_windows_sharing_probe_does_not_remove_wal(self):
        import ctypes
        from ctypes import wintypes
        cache = self.root / '.concord/journal/recipe-cache.sqlite-shm'
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b'held cache fixture')
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        kernel.CreateFileW.restype = wintypes.HANDLE
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel.CreateFileW(str(cache), 0x80000000, 1, None, 3, 0, None)
        self.assertNotEqual(handle, wintypes.HANDLE(-1).value)
        try:
            self.assertEqual(git_index_integrity.file_probe(cache), 'SHARING_VIOLATION')
        finally:
            kernel.CloseHandle(handle)
        self.assertEqual(cache.read_bytes(), b'held cache fixture')