"""Isolated real Git fixtures; no recovery or mutation of the framework repository."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import git_index_integrity


class IndexIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mxagile-index-")
        self.root = Path(self.temp.name)
        self.command("init", "--quiet")

    def tearDown(self):
        self.temp.cleanup()

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

    def test_policy_blocks_all_risky_followups_and_distribution_is_explicit(self):
        root = Path(__file__).resolve().parents[1]
        safety = (root / ".mxagile/policies/safety-rules.md").read_text(encoding="utf-8")
        for operation in ("git add", "Commit", "Migration", "Update", "Modellmutation", "Cleanup", "Rebase", "Merge"):
            self.assertIn(operation, safety)
        installer = (root / "scripts/install-core.ps1").read_text(encoding="utf-8")
        self.assertLess(installer.index("$guardOutput ="), installer.index("Running project type detection"))
        self.assertIn('".mxagile/tools/git_index_integrity.py"', installer)
        self.assertIn("git_index_integrity.py", (root / "scripts/apply-project-agent-instructions.ps1").read_text(encoding="utf-8"))