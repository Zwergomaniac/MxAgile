"""Read-only report and explicit baseline-adoption fixtures."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import reconcile_external_changes as reconciliation


class ReconciliationBaselineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="mxagile-reconcile-")
        self.root = Path(self.temporary.name)
        self.git("init", "--quiet")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        (self.root / ".gitignore").write_text(".mxagile/state/\n", encoding="utf-8")
        (self.root / ".mxagile/schemas").mkdir(parents=True)
        for schema_name in ("project-reconciliation-state.schema.json", "change-set.schema.json"):
            source = ROOT / ".mxagile/schemas" / schema_name
            (self.root / ".mxagile/schemas" / schema_name).write_bytes(source.read_bytes())
        (self.root / "mxagile-project.yaml").write_text("name: Fixture\n", encoding="utf-8")
        (self.root / "planning/requirements").mkdir(parents=True)
        (self.root / "requirements/REQ-001.yml").parent.mkdir(parents=True)
        (self.root / "requirements/REQ-001.yml").write_text(
            "ID: REQ-001\ntitle: Fixture requirement\nstatus: accepted\n", encoding="utf-8"
        )
        (self.root / "source.txt").write_text("baseline\n", encoding="utf-8")
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Fixture baseline")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def git(self, *args: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(self.root), *args],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def test_schemas_are_valid_draft_seven(self) -> None:
        for name in ("project-reconciliation-state.schema.json", "change-set.schema.json"):
            schema = json.loads((ROOT / ".mxagile/schemas" / name).read_text(encoding="utf-8"))
            Draft7Validator.check_schema(schema)

    def test_report_without_baseline_is_read_only(self) -> None:
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["status"], "BASELINE_REQUIRED")
        self.assertTrue(report["read_only"])
        self.assertFalse(Path(report["state_path"]).exists())
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_adoption_requires_explicit_confirmation(self) -> None:
        result = reconciliation.adopt_baseline(self.root)
        self.assertEqual(result["status"], "BASELINE_CONFIRMATION_REQUIRED")
        self.assertFalse((self.root / ".mxagile/state/reconciliation").exists())

    def test_dirty_tree_cannot_be_adopted(self) -> None:
        (self.root / "source.txt").write_text("uncommitted\n", encoding="utf-8")
        result = reconciliation.adopt_baseline(self.root, confirmed=True)
        self.assertEqual(result["status"], "BASELINE_REQUIRES_CLEAN_TREE")
        self.assertFalse((self.root / ".mxagile/state/reconciliation").exists())

    def test_watermark_requires_gitignored_runtime_path(self) -> None:
        self.git("rm", "--quiet", ".gitignore")
        self.git("commit", "--quiet", "-m", "Remove runtime ignore rule")
        result = reconciliation.adopt_baseline(self.root, confirmed=True)
        self.assertEqual(result["status"], "WATERMARK_PATH_NOT_IGNORED")
        self.assertFalse((self.root / ".mxagile/state/reconciliation").exists())

    def test_detached_head_cannot_be_adopted(self) -> None:
        head = self.git("rev-parse", "HEAD")
        self.git("checkout", "--quiet", "--detach", head)
        result = reconciliation.adopt_baseline(self.root, confirmed=True)
        self.assertEqual(result["status"], "DETACHED_HEAD")
        self.assertFalse((self.root / ".mxagile/state/reconciliation").exists())

    def test_explicit_adoption_binds_branch_worktree_head_and_fingerprints(self) -> None:
        expected_head = self.git("rev-parse", "HEAD")
        expected_branch = self.git("symbolic-ref", "--quiet", "HEAD")
        result = reconciliation.adopt_baseline(self.root, confirmed=True)
        self.assertEqual(result["status"], "BASELINE_ADOPTED")
        state = result["watermark"]
        self.assertEqual(state["last_reconciled_commit"], expected_head)
        self.assertEqual(state["branch_ref"], expected_branch)
        self.assertRegex(state["repository_identity"], r"^sha256:[a-f0-9]{64}$")
        self.assertRegex(state["worktree_identity"], r"^sha256:[a-f0-9]{64}$")
        self.assertRegex(state["project_fingerprint"], r"^sha256:[a-f0-9]{64}$")
        self.assertEqual(state["baseline_kind"], "EXPLICIT_ADOPTION")
        self.assertTrue((self.root / result["state_path"]).is_file())
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_existing_watermark_is_never_overwritten_by_adoption(self) -> None:
        adopted = reconciliation.adopt_baseline(self.root, confirmed=True)
        state_path = self.root / adopted["state_path"]
        before = state_path.read_bytes()
        second = reconciliation.adopt_baseline(self.root, confirmed=True)
        self.assertEqual(second["status"], "WATERMARK_ALREADY_EXISTS")
        self.assertEqual(state_path.read_bytes(), before)

    def test_state_schema_rejects_missing_or_extra_fields(self) -> None:
        adopted = reconciliation.adopt_baseline(self.root, confirmed=True)
        state = dict(adopted["watermark"])
        state["unrecognized"] = "not allowed"
        with self.assertRaises(reconciliation.ReconciliationError):
            reconciliation._validate_state(self.root, state)


if __name__ == "__main__":
    unittest.main()