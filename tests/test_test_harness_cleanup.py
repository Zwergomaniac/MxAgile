"""Fix 5 (RF-007): canonical mprcontents/*.mxunit are productive model artifacts; cleanup ownership is explicit.

Real Git fixtures in temp directories only; the planner itself must never mutate files or the index."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from temp_cleanup import cleanup_temporary_directory

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import test_harness_cleanup as cleanup  # noqa: E402

UNIT = "mprcontents/96/e7/96e7e64a-5961-41e5-a072-b868d0617f6c.mxunit"


class HarnessCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mxagile-harness-")
        self.base = Path(self.temp.name)
        self.main = self.base / "main"
        self.main.mkdir()
        self.git(self.main, "init", "--quiet", "-b", "main")
        self.git(self.main, "config", "core.autocrlf", "false")
        (self.main / ".gitignore").write_text(".mxagile/state/\n", encoding="utf-8")
        (self.main / "App.mpr").write_bytes(b"MPR\n")
        (self.main / UNIT).parent.mkdir(parents=True)
        (self.main / UNIT).write_bytes(b"\x10\x00\x00\x00canonical-unit")
        self.git(self.main, "add", "--all")
        self.git(self.main, "commit", "--quiet", "-m", "base")
        self.worktree = self.base / "wtA"
        self.git(self.main, "worktree", "add", "--quiet", "-b", "A", str(self.worktree))

    def tearDown(self):
        cleanup_temporary_directory(self.temp, expected_prefix="mxagile-harness-")

    def git(self, cwd, *arguments):
        return subprocess.run(["git", "--no-optional-locks", "-C", str(cwd), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", *arguments],
                              capture_output=True, check=True).stdout

    def snapshot(self, checkout):
        files = {str(p.relative_to(checkout)): p.read_bytes() for p in checkout.rglob("*") if p.is_file() and ".git" not in p.parts}
        index = Path(self.git(checkout, "rev-parse", "--path-format=absolute", "--git-path", "index").decode().strip())
        return files, index.read_bytes(), self.git(checkout, "status", "--porcelain=v2", "--untracked-files=all")

    def planned(self, checkout, location=None):
        before = self.snapshot(checkout)
        report = cleanup.plan(location or checkout)
        self.assertEqual(self.snapshot(checkout), before, "planner must never change files or the index")
        return {i["path"]: i for i in report["removable"]}, {i["path"]: i for i in report["preserved"]}, report

    def test_1_canonical_unit_is_left_unchanged(self):
        for checkout in (self.main, self.worktree):
            with self.subTest(checkout=checkout.name):
                (checkout / UNIT).write_bytes(b"\x12\x00\x00\x00serialization-only rewrite")
                removable, preserved, _ = self.planned(checkout)
                self.assertNotIn(UNIT, removable)
                self.assertTrue(preserved[UNIT]["model_artifact"])
                self.assertIn("CANONICAL_MODEL_ARTIFACT", preserved[UNIT]["reason"])

    def test_2_semantically_changed_unit_is_never_discarded(self):
        for checkout in (self.main, self.worktree):
            with self.subTest(checkout=checkout.name):
                (checkout / UNIT).write_bytes(b"harness-touched")
                self.assertEqual(cleanup.record(checkout, [UNIT], "MxTest", model_unit=True)["state"], "RECORDED")
                (checkout / UNIT).write_bytes(b"semantic change by developer after harness run")
                removable, preserved, _ = self.planned(checkout)
                self.assertNotIn(UNIT, removable)
                self.assertIn("CONTENT_CHANGED_SINCE_HARNESS_INJECTION", preserved[UNIT]["reason"])

    def test_3_untracked_materialized_unit_is_not_deleted_by_extension(self):
        new_unit = "mprcontents/ab/cd/abcd0000-0000-0000-0000-000000000000.mxunit"
        loose_unit = "javasource/mxtest/loose.mxunit"
        for checkout in (self.main, self.worktree):
            with self.subTest(checkout=checkout.name):
                for relative in (new_unit, loose_unit):
                    (checkout / relative).parent.mkdir(parents=True, exist_ok=True)
                    (checkout / relative).write_bytes(b"materialized")
                removable, preserved, _ = self.planned(checkout, checkout / "mprcontents")
                self.assertEqual(removable, {})
                self.assertIn("CANONICAL_MODEL_ARTIFACT", preserved[new_unit]["reason"])
                self.assertIn("REQUIRES_CLASSIFICATION", preserved[loose_unit]["reason"])
                self.assertTrue((checkout / new_unit).is_file())

    def test_4_explicitly_owned_harness_artifacts_remain_cleanable(self):
        java = "javasource/mxtest/actions/RunTests.java"
        harness_unit = "mprcontents/ee/ff/eeff0000-0000-0000-0000-000000000000.mxunit"
        for relative in (java, harness_unit):
            (self.main / relative).parent.mkdir(parents=True, exist_ok=True)
            (self.main / relative).write_bytes(b"injected by MxTest")
        refused = cleanup.record(self.main, [harness_unit], "MxTest")
        self.assertEqual(refused["reason"], "MODEL_ARTIFACT_REQUIRES_EXPLICIT_MODEL_UNIT_OWNERSHIP")
        self.assertEqual(cleanup.record(self.main, [java], "MxTest")["state"], "RECORDED")
        self.assertEqual(cleanup.record(self.main, [harness_unit], "MxTest", model_unit=True)["state"], "RECORDED")
        self.assertEqual(cleanup.record(self.main, ["../outside.txt"], "MxTest")["reason"], "UNSAFE_PATH")
        removable, preserved, report = self.planned(self.main)
        self.assertEqual(report["manifest_state"], "PRESENT")
        self.assertEqual(removable[java]["action"], "delete-untracked")
        self.assertEqual(removable[harness_unit]["action"], "delete-untracked")
        self.assertNotIn(cleanup.MANIFEST_RELATIVE, preserved)

    def test_5_main_manifest_never_authorizes_linked_worktree(self):
        java = "javasource/mxtest/Helper.java"
        for checkout in (self.main, self.worktree):
            (checkout / java).parent.mkdir(parents=True, exist_ok=True)
            (checkout / java).write_bytes(b"injected")
        cleanup.record(self.main, [java], "MxTest")
        main_removable, _, _ = self.planned(self.main)
        wt_removable, wt_preserved, wt_report = self.planned(self.worktree)
        self.assertIn(java, main_removable)
        self.assertEqual((wt_report["manifest_state"], wt_removable), ("ABSENT", {}))
        self.assertIn("REQUIRES_CLASSIFICATION", wt_preserved[java]["reason"])
        self.assertEqual(Path(wt_report["top_level"]), self.worktree.resolve())

    def test_invalid_manifest_fails_closed(self):
        java = "javasource/mxtest/X.java"
        (self.main / java).parent.mkdir(parents=True)
        (self.main / java).write_bytes(b"x")
        manifest = self.main / cleanup.MANIFEST_RELATIVE
        manifest.parent.mkdir(parents=True)
        manifest.write_text(json.dumps({"schema": cleanup.SCHEMA, "entries": [{"path": "../x", "sha256": "0", "harness": "MxTest"}]}), encoding="utf-8")
        removable, preserved, report = self.planned(self.main)
        self.assertEqual((report["manifest_state"], removable), ("INVALID", {}))
        self.assertIn("OWNERSHIP_MANIFEST_INVALID", preserved[java]["reason"])

    def test_policy_no_longer_classifies_mxunit_by_extension(self):
        policy = (ROOT / ".mxagile/policies/test-harness-cleanup.md").read_text(encoding="utf-8")
        block = policy.split("### Patterns typically TEMPORARY_TEST_HARNESS_ARTIFACT", 1)[1].split("###", 1)[0]
        self.assertNotIn("*.mxunit", block)
        for marker in ("mprcontents/**/*.mxunit", "test_harness_cleanup.py", "explicit ownership", "never inferred from a file extension"):
            self.assertIn(marker, policy)
        completion = (ROOT / ".mxagile/policies/mission-completion.md").read_text(encoding="utf-8")
        self.assertNotIn("injects *.mxunit", completion)
        installer = (ROOT / "scripts/install-core.ps1").read_text(encoding="utf-8")
        self.assertIn('".mxagile/tools/test_harness_cleanup.py"', installer)


if __name__ == "__main__":
    unittest.main()
