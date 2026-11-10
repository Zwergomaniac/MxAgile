"""Isolated real Git fixtures; no recovery or mutation of the framework repository."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from temp_cleanup import cleanup_temporary_directory

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import git_index_integrity
import reconcile_external_changes


class IndexIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mxagile-index-")
        self.root = Path(self.temp.name)
        self.command("init", "--quiet")

    def tearDown(self):
        cleanup_temporary_directory(self.temp, expected_prefix="mxagile-index-")

    def command(self, *arguments):
        return subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", *arguments], capture_output=True, check=True).stdout

    def tracked(self, count):
        for index in range(count):
            (self.root / f"model-{index:04d}.mxunit").write_text("{}\n", encoding="utf-8")
        self.command("add", "--all")
        self.command("commit", "--quiet", "-m", "Fixture")

    def test_reality_6170_retained_files_and_empty_index(self):
        self.tracked(6170)
        head = self.command("rev-parse", "HEAD")
        self.command("read-tree", "--empty")
        index_path = self.root / ".git/index"
        before = index_path.read_bytes()
        report = git_index_integrity.inspect_index(self.root)
        self.assertEqual(report["state"], "GIT_INDEX_INTEGRITY_FAILURE")
        self.assertFalse(report["mutations_allowed"])
        self.assertEqual([report[key] for key in ("head_entry_count", "index_entry_count", "staged_deletion_count", "working_tree_present_count")], [6170, 0, 6170, 6170])
        self.assertEqual(index_path.read_bytes(), before)
        self.assertEqual(self.command("rev-parse", "HEAD"), head)
        self.assertEqual(len(list(self.root.glob("*.mxunit"))), 6170)
        drift = reconcile_external_changes.build_report(self.root)
        self.assertEqual(drift["status"], "GIT_INTEGRITY_BLOCKED")
        self.assertEqual(drift["working_changes"], {"staged": [], "unstaged": [], "untracked": []})
        self.command("restore", "--source=HEAD", "--staged", "--", ":/")
        self.assertEqual(git_index_integrity.inspect_index(self.root)["state"], "GIT_INDEX_PLAUSIBLE")
        self.assertEqual(len(list(self.root.glob("*.mxunit"))), 6170)

    def test_normal_unborn_and_actual_deletion(self):
        self.assertTrue(git_index_integrity.inspect_index(self.root)["mutations_allowed"])
        self.tracked(2)
        self.assertEqual(git_index_integrity.inspect_index(self.root)["state"], "GIT_INDEX_PLAUSIBLE")
        self.command("rm", "model-0000.mxunit", "model-0001.mxunit")
        self.assertTrue(git_index_integrity.inspect_index(self.root)["mutations_allowed"])

    def test_locks_are_classified_and_never_deleted(self):
        self.tracked(1)
        lock = self.root / ".git/index.lock"
        lock.write_text("fixture", encoding="ascii")
        for active, state in ((True, "GIT_OPERATION_IN_PROGRESS"), (False, "GIT_INDEX_LOCK_STALE_CANDIDATE"), (None, "GIT_INDEX_LOCK_UNVERIFIED")):
            with self.subTest(active=active), patch.object(git_index_integrity, "git_activity", return_value=active):
                report = git_index_integrity.inspect_index(self.root)
                self.assertEqual(report["state"], state)
                self.assertFalse(report["mutations_allowed"])
                self.assertEqual(lock.read_text(), "fixture")

    def test_unreadable_index_is_not_pass(self):
        self.tracked(1)
        (self.root / ".git/index").write_bytes(b"not-an-index")
        self.assertEqual(git_index_integrity.inspect_index(self.root)["state"], "GIT_INDEX_NOT_CHECKED")

    def test_installer_and_canonicalizer_stop_before_mutations(self):
        self.tracked(1)
        self.command("read-tree", "--empty")
        root = Path(__file__).resolve().parents[1]
        index_before = (self.root / ".git/index").read_bytes()
        for command in (
            ["pwsh", "-NoProfile", "-File", str(root / "scripts/install-core.ps1"), "-ProjectRoot", str(self.root)],
            [sys.executable, str(root / "scripts/canonicalize_artifacts.py"), "--project-root", str(self.root)],
        ):
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("GIT_INDEX_INTEGRITY_FAILURE", result.stdout, result.stderr)
            self.assertFalse((self.root / ".mxagile").exists())
            self.assertEqual((self.root / ".git/index").read_bytes(), index_before)

    def test_non_repository_stays_not_applicable_and_broken_marker_fails_closed(self):
        with tempfile.TemporaryDirectory(prefix="mxagile-index-") as plain:
            report = git_index_integrity.inspect_index(Path(plain))
            self.assertEqual((report["state"], report["mutations_allowed"]), ("GIT_INDEX_NOT_APPLICABLE", True))
            (Path(plain) / ".git").write_text("gitdir: does-not-exist\n", encoding="utf-8")
            nested = Path(plain) / "a" / "b"
            nested.mkdir(parents=True)
            report = git_index_integrity.inspect_index(nested)
            self.assertEqual((report["state"], report["mutations_allowed"]), ("GIT_INDEX_NOT_CHECKED", False))

    def test_policy_blocks_all_risky_followups_and_distribution_is_explicit(self):
        root = Path(__file__).resolve().parents[1]
        safety = (root / ".mxagile/policies/safety-rules.md").read_text(encoding="utf-8")
        for operation in ("git add", "Commit", "Migration", "Update", "Modellmutation", "Cleanup", "Rebase", "Merge"):
            self.assertIn(operation, safety)
        installer = (root / "scripts/install-core.ps1").read_text(encoding="utf-8")
        self.assertLess(installer.index("$guardOutput ="), installer.index("Running project type detection"))
        self.assertIn('".mxagile/tools/git_index_integrity.py"', installer)
        routing = (root / "scripts/apply-project-agent-instructions.ps1").read_text(encoding="utf-8")
        self.assertRegex(routing, r"Read `\.mxagile/policies/safety-rules\.md` and run the read-only Git\s+index guard before Git-derived drift analysis or mutations")
        self.assertIn("python .mxagile/tools/git_index_integrity.py --project-root .", safety)
        self.assertIn("jeder andere Exit blockiert normale Mutationen", safety)


STUB_PROCESSES = {"state": "OBSERVED", "processes": [], "file_handle_ownership": "UNKNOWN"}


class GuardHardeningMatrixTests(unittest.TestCase):
    """Fix 6: Git-native repository resolution (root, deep subdirectory, linked worktrees),
    byte-identical index across all Git states, bounded process observation."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mxagile-index-")
        self.base = Path(self.temp.name)
        self.main = self.base / "main"
        self.main.mkdir()
        self.git(self.main, "init", "--quiet", "-b", "main")
        self.git(self.main, "config", "core.autocrlf", "false")
        self.deep_rel = Path("mprcontents/aa/bb")
        (self.main / self.deep_rel).mkdir(parents=True)
        for name in ("unitA", "unitB", "unitC"):
            (self.main / self.deep_rel / f"{name}.mxunit").write_bytes(b"base\n")
        (self.main / "App.mpr").write_bytes(b"MPR\n")
        self.git(self.main, "add", "--all")
        self.git(self.main, "commit", "--quiet", "-m", "base")
        self.wt_a, self.wt_b = self.base / "wtA", self.base / "wtB"
        self.git(self.main, "worktree", "add", "--quiet", "-b", "A", str(self.wt_a))
        self.git(self.main, "worktree", "add", "--quiet", "-b", "B", str(self.wt_b))

    def tearDown(self):
        cleanup_temporary_directory(self.temp, expected_prefix="mxagile-index-")

    def git(self, cwd, *arguments, check=True):
        result = subprocess.run(["git", "--no-optional-locks", "-C", str(cwd), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", *arguments], capture_output=True)
        if check and result.returncode:
            self.fail(result.stderr.decode(errors="replace"))
        return result

    def own_index(self, checkout):
        return Path(self.git(checkout, "rev-parse", "--path-format=absolute", "--git-path", "index").stdout.decode().strip()).resolve()

    def fingerprint(self, checkout):
        index = self.own_index(checkout)
        return (index.read_bytes(), index.stat().st_mtime_ns,
                self.git(checkout, "ls-files", "--stage").stdout,
                self.git(checkout, "diff", "--cached", "-M", "--name-status").stdout,
                self.git(checkout, "status", "--porcelain=v2").stdout)

    def assert_guard_read_only(self, checkout, expected_state="GIT_INDEX_PLAUSIBLE"):
        checkouts = (self.main, self.wt_a, self.wt_b)
        before = {c: self.fingerprint(c) for c in checkouts}
        for location in (checkout, checkout / self.deep_rel):
            with self.subTest(location=str(location)):
                report = git_index_integrity.inspect_index(location)
                self.assertEqual(report["state"], expected_state)
                self.assertTrue(report["mutations_allowed"])
                self.assertEqual(Path(report["top_level"]), checkout.resolve())
                self.assertEqual(Path(report["index_path"]), self.own_index(checkout))
        with patch.object(git_index_integrity, "git_activity", return_value=False), patch.object(git_index_integrity, "runtime_processes", return_value=STUB_PROCESSES):
            for operation in ("merge-abort", "index-rebuild", "cherry-pick-abort"):
                result = git_index_integrity.recovery_preflight(checkout / self.deep_rel, operation, user_authorized=True, scope_reviewed=True)
                self.assertNotEqual((operation, result["state"]), ("index-rebuild", "RECOVERY_READY"))
        self.assertEqual({c: self.fingerprint(c) for c in checkouts}, before, "guard must never write any index")

    def unit(self, checkout, name):
        return checkout / self.deep_rel / f"{name}.mxunit"

    def test_matrix_main_and_linked_worktrees(self):
        for checkout in (self.main, self.wt_a, self.wt_b):
            with self.subTest(checkout=checkout.name, case="clean"):
                self.assert_guard_read_only(checkout)
        self.unit(self.wt_a, "unitA").write_bytes(b"A staged\n")
        self.git(self.wt_a, "add", "--all")
        with self.subTest(case="staged in worktree A"):
            self.assert_guard_read_only(self.wt_a)
        self.unit(self.wt_a, "unitA").write_bytes(b"A unstaged on top\n")
        with self.subTest(case="mixed staged/unstaged in worktree A"):
            self.assert_guard_read_only(self.wt_a)
        self.git(self.wt_b, "mv", str(self.deep_rel / "unitB.mxunit"), str(self.deep_rel / "unitB2.mxunit"))
        with self.subTest(case="rename in worktree B"):
            self.assert_guard_read_only(self.wt_b)
        (self.main / self.deep_rel / "new.mxunit").write_bytes(b"untracked\n")
        with self.subTest(case="untracked in main"):
            self.assert_guard_read_only(self.main)
        self.assertNotEqual(self.own_index(self.wt_a), self.own_index(self.wt_b))
        self.assertNotEqual(self.own_index(self.main), self.own_index(self.wt_a))

    def prepare_conflict(self):
        self.git(self.main, "checkout", "--quiet", "-b", "other")
        self.unit(self.main, "unitC").write_bytes(b"theirs\n")
        self.git(self.main, "commit", "--quiet", "-am", "other")
        self.git(self.main, "checkout", "--quiet", "main")
        self.unit(self.main, "unitC").write_bytes(b"ours\n")
        self.git(self.main, "commit", "--quiet", "-am", "main")

    def test_merge_conflict_stages_are_never_reconstructed(self):
        self.prepare_conflict()
        self.assertNotEqual(self.git(self.main, "merge", "other", check=False).returncode, 0)
        stages = {line.split()[2] for line in self.git(self.main, "ls-files", "--stage", "--unmerged").stdout.decode().splitlines()}
        self.assertEqual(stages, {"1", "2", "3"})
        self.assert_guard_read_only(self.main)
        with patch.object(git_index_integrity, "git_activity", return_value=False), patch.object(git_index_integrity, "runtime_processes", return_value=STUB_PROCESSES):
            rebuild = git_index_integrity.recovery_preflight(self.main / self.deep_rel, "index-rebuild", user_authorized=True, scope_reviewed=True)
        self.assertEqual(rebuild["state"], "RECOVERY_BLOCKED")
        self.assertEqual(rebuild["snapshot"]["unmerged_entry_count"], 3)

    def test_cherry_pick_conflict_is_left_untouched(self):
        self.prepare_conflict()
        self.assertNotEqual(self.git(self.main, "cherry-pick", "other", check=False).returncode, 0)
        self.assertTrue(Path(self.git(self.main, "rev-parse", "--path-format=absolute", "--git-path", "CHERRY_PICK_HEAD").stdout.decode().strip()).is_file())
        self.assert_guard_read_only(self.main)

    def test_process_listing_normal_and_timeout(self):
        real_run = subprocess.run
        calls = []

        def fake(rows=None, timeout=False):
            def runner(command, *args, **kwargs):
                if command and command[0] in ("tasklist", "ps"):
                    calls.append(kwargs.get("timeout"))
                    if timeout:
                        raise subprocess.TimeoutExpired(command, kwargs.get("timeout"))
                    return subprocess.CompletedProcess(command, 0, stdout=rows, stderr="")
                return real_run(command, *args, **kwargs)
            return runner

        rows = '"git.exe","4711","Console","1","6.720 K"\n' if os.name == "nt" else "git\n"
        with patch.object(git_index_integrity.subprocess, "run", side_effect=fake(rows)):
            self.assertEqual(git_index_integrity.observed_git_activity(), (True, "OBSERVED"))
        lock = Path(self.git(self.main, "rev-parse", "--path-format=absolute", "--git-path", "index.lock").stdout.decode().strip())
        lock.write_text("fixture", encoding="ascii")
        try:
            with patch.object(git_index_integrity.subprocess, "run", side_effect=fake(timeout=True)):
                self.assertEqual(git_index_integrity.observed_git_activity(), (None, "TIMEOUT"))
                report = git_index_integrity.inspect_index(self.main / self.deep_rel)
                self.assertEqual((report["state"], report["process_observation"], report["mutations_allowed"]), ("GIT_INDEX_LOCK_UNVERIFIED", "TIMEOUT", False))
                self.assertEqual(git_index_integrity.runtime_processes()["state"], "TIMEOUT")
            self.assertEqual(lock.read_text(), "fixture")
        finally:
            lock.unlink()
        with patch.object(git_index_integrity.subprocess, "run", side_effect=fake(timeout=True)):
            preflight = git_index_integrity.recovery_preflight(self.main, "index-rebuild", user_authorized=True, scope_reviewed=True)
        self.assertEqual(preflight["state"], "RECOVERY_BLOCKED")
        self.assertTrue(preflight["reason"].startswith("GIT_PROCESS_OBSERVATION_TIMEOUT"), preflight["reason"])
        self.assertTrue(calls and all(value == git_index_integrity.PROCESS_TIMEOUT_SECONDS for value in calls), calls)