"""Read-only report and explicit baseline-adoption fixtures."""

from __future__ import annotations

import json
from contextlib import redirect_stdout
from io import StringIO
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import reconcile_external_changes as reconciliation
import reconciliation_git as git_reconciliation
import project_compatibility
import resolve_impact


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

    def commit_paths(
        self,
        changes: dict[str, str | None],
        *,
        change_set_id: str | None = None,
        declared_paths: tuple[str, ...] = (),
        trailers: bool = False,
    ) -> str:
        parent = self.git("rev-parse", "HEAD")
        for path, content in changes.items():
            target = self.root / path
            if content is None:
                target.unlink(missing_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content, encoding="utf-8")
        self.git("add", "--all")

        if change_set_id:
            manifest_paths = []
            for path in declared_paths:
                before = subprocess.run(
                    ["git", "-C", str(self.root), "rev-parse", "--verify", f"{parent}:{path}"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                after = subprocess.run(
                    ["git", "-C", str(self.root), "rev-parse", "--verify", f":{path}"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                before_oid = before.stdout.strip() if before.returncode == 0 else None
                after_oid = after.stdout.strip() if after.returncode == 0 else None
                status = "A" if before_oid is None else "D" if after_oid is None else "M"
                manifest_paths.append({
                    "path": path,
                    "status": status,
                    "before_blob": before_oid,
                    "after_blob": after_oid,
                })
            manifest = {
                "schema_version": 1,
                "change_set_id": change_set_id,
                "mission_id": "MISSION-2026-10-31-fixture",
                "context_epoch": None,
                "result_references": [],
                "parent_commits": [parent],
                "paths": manifest_paths,
                "reconciliation": {
                    "status": "COMPLETE",
                    "outcome": "IMPACT_RECONCILED",
                    "project_fingerprint": "sha256:" + "a" * 64,
                    "references": [],
                },
            }
            manifest_path = self.root / "planning/reconciliation/change-sets" / f"{change_set_id}.json"
            manifest_path.parent.mkdir(parents=True, exist_ok=True)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            self.git("add", "--", manifest_path.relative_to(self.root).as_posix())

        message = "Fixture change"
        if trailers:
            mission_id = "MISSION-2026-10-31-fixture"
            message += (
                "\n\nMxAgile-Origin: mxagile"
                f"\nMxAgile-Mission: {mission_id}"
                f"\nMxAgile-Change-Set: {change_set_id or 'CS-MISSING'}"
            )
        self.git("commit", "--quiet", "-m", message)
        return self.git("rev-parse", "HEAD")

    def write_finding(
        self,
        finding_id: str,
        source_path: str,
        *,
        origin: str = "PROJECT",
        lifecycle_status: str = "CLASSIFIED",
        extra: dict[str, Any] | None = None,
    ) -> Path:
        value = {
            "ID": finding_id,
            "title": "Fixture finding",
            "gap_type": "VISUAL_GAP",
            "severity": "MATERIAL",
            "lifecycle_status": lifecycle_status,
            "origin": origin,
            "observation": "Fixture evidence-backed observation.",
            "source_artifacts": [{"source_type": "other", "canonical_path": source_path}],
        }
        value.update(extra or {})
        path = self.root / "planning/findings" / f"{finding_id}.yml"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, sort_keys=True) + "\n", encoding="utf-8")
        return path

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

    def test_no_delta_when_watermark_equals_head(self) -> None:
        reconciliation.adopt_baseline(self.root, confirmed=True)
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["commit_range"]["status"], "NO_COMMITTED_DELTA")
        self.assertEqual(report["commit_range"]["commits"], [])
        self.assertEqual(report["watermark"]["last_reconciled_commit"], report["head"])

    def test_mpr_delta_is_semantic_review_required_without_local_capability(self) -> None:
        (self.root / "Fixture.mpr").write_bytes(b"baseline model")
        (self.root / "mprcontents").mkdir()
        (self.root / "mprcontents/page.mxunit").write_text("page baseline\n", encoding="utf-8")
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Add Mendix model fixture")
        reconciliation.adopt_baseline(self.root, confirmed=True)
        self.commit_paths({"mprcontents/page.mxunit": "page changed\n"})
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["model_semantic_review"]["status"], "SEMANTIC_REVIEW_REQUIRED")
        self.assertEqual(report["model_semantic_review"]["reason"], "PROJECT_LOCAL_MXCLI_NOT_FOUND")

    def test_report_and_interrupt_leave_prior_watermark_and_evidence_unchanged(self) -> None:
        evidence = self.root / "planning/evidence/framework-reality.json"
        evidence.parent.mkdir(parents=True, exist_ok=True)
        evidence.write_text("{\"verified\":true}\n", encoding="utf-8")
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Add promoted evidence")
        adopted = reconciliation.adopt_baseline(self.root, confirmed=True)
        state_path = self.root / adopted["state_path"]
        state_before = state_path.read_bytes()
        evidence_before = evidence.read_bytes()
        self.commit_paths({"app/page.yaml": "external change\n"})
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["commit_range"]["status"], "RECONCILIATION_REQUIRED")
        self.assertEqual(state_path.read_bytes(), state_before)
        self.assertEqual(evidence.read_bytes(), evidence_before)

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

    def test_mixed_commit_attributes_only_change_set_paths(self) -> None:
        watermark = self.git("rev-parse", "HEAD")
        commit = self.commit_paths(
            {"app/page.yaml": "page: changed\n", "external/notes.md": "outside\n"},
            change_set_id="CS-MIXED",
            declared_paths=("app/page.yaml",),
            trailers=True,
        )
        result = git_reconciliation.analyze_commit_range(self.root, watermark, commit)
        self.assertEqual(result["status"], "RECONCILIATION_REQUIRED")
        self.assertEqual(result["commits"][0]["classification"], "MIXED")
        classes = {item["path"]: item["classification"] for item in result["commits"][0]["paths"]}
        self.assertEqual(classes["app/page.yaml"], "MXAGILE_ATTRIBUTED_CHANGE")
        self.assertEqual(classes["external/notes.md"], "EXTERNAL_CHANGE")

    def test_trailer_without_change_set_is_external(self) -> None:
        watermark = self.git("rev-parse", "HEAD")
        commit = self.commit_paths({"external/unmarked.txt": "outside\n"}, trailers=True)
        result = git_reconciliation.analyze_commit_range(self.root, watermark, commit)
        self.assertEqual(result["commits"][0]["classification"], "EXTERNAL_CHANGE")

    def test_change_set_without_trailer_is_ambiguous(self) -> None:
        watermark = self.git("rev-parse", "HEAD")
        commit = self.commit_paths(
            {"app/page.yaml": "changed\n"},
            change_set_id="CS-NO-TRAILER",
            declared_paths=("app/page.yaml",),
        )
        result = git_reconciliation.analyze_commit_range(self.root, watermark, commit)
        self.assertEqual(result["commits"][0]["classification"], "AMBIGUOUS")

    def test_known_external_known_sequence_remains_per_commit(self) -> None:
        watermark = self.git("rev-parse", "HEAD")
        first = self.commit_paths(
            {"app/first.yaml": "known one\n"},
            change_set_id="CS-FIRST",
            declared_paths=("app/first.yaml",),
            trailers=True,
        )
        self.commit_paths({"external/middle.txt": "external\n"})
        last = self.commit_paths(
            {"app/last.yaml": "known two\n"},
            change_set_id="CS-LAST",
            declared_paths=("app/last.yaml",),
            trailers=True,
        )
        result = git_reconciliation.analyze_commit_range(self.root, watermark, last)
        self.assertEqual([item["commit"] for item in result["commits"]], [first, self.git("rev-parse", "HEAD~1"), last])
        self.assertEqual(
            [item["classification"] for item in result["commits"]],
            ["MXAGILE_ATTRIBUTED_CHANGE", "EXTERNAL_CHANGE", "MXAGILE_ATTRIBUTED_CHANGE"],
        )

    def test_attributed_only_range_is_cheap_and_not_external(self) -> None:
        watermark = self.git("rev-parse", "HEAD")
        head = self.commit_paths(
            {"app/page.yaml": "known\n"},
            change_set_id="CS-KNOWN-ONLY",
            declared_paths=("app/page.yaml",),
            trailers=True,
        )
        result = git_reconciliation.analyze_commit_range(self.root, watermark, head)
        self.assertEqual(result["status"], "MXAGILE_ATTRIBUTED_ONLY")
        self.assertEqual(result["commits"][0]["classification"], "MXAGILE_ATTRIBUTED_CHANGE")

    def test_working_tree_classes_are_separate(self) -> None:
        (self.root / "source.txt").write_text("staged\n", encoding="utf-8")
        self.git("add", "--", "source.txt")
        (self.root / "source.txt").write_text("unstaged\n", encoding="utf-8")
        (self.root / "new.txt").write_text("untracked\n", encoding="utf-8")
        changes = git_reconciliation.working_tree_changes(self.root)
        self.assertEqual(changes["staged"], [{"path": "source.txt", "status": "M"}])
        self.assertEqual(changes["unstaged"], [{"path": "source.txt", "status": "M"}])
        self.assertEqual(changes["untracked"], [{"path": "new.txt", "status": "A"}])

    def test_public_report_includes_mixed_commit_and_keeps_watermark(self) -> None:
        adopted = reconciliation.adopt_baseline(self.root, confirmed=True)
        watermark = adopted["watermark"]["last_reconciled_commit"]
        self.commit_paths(
            {"app/page.yaml": "page: changed\n", "external/notes.md": "outside\n"},
            change_set_id="CS-REPORT",
            declared_paths=("app/page.yaml",),
            trailers=True,
        )
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["commit_range"]["status"], "RECONCILIATION_REQUIRED")
        self.assertEqual(report["commit_range"]["commits"][0]["classification"], "MIXED")
        self.assertFalse(report["can_advance_watermark"])
        self.assertEqual(report["watermark"]["last_reconciled_commit"], watermark)

    def test_external_change_unrelated_to_active_finding_does_not_change_finding(self) -> None:
        (self.root / "app/page.yaml").parent.mkdir(parents=True, exist_ok=True)
        (self.root / "app/page.yaml").write_text("page: current\n", encoding="utf-8")
        finding_path = self.write_finding("FIND-PAGE", "app/page.yaml")
        before_finding = finding_path.read_bytes()
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Add active finding")
        reconciliation.adopt_baseline(self.root, confirmed=True)
        self.commit_paths({"external/notes.md": "unrelated\n"})
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["finding_impacts"], [])
        self.assertEqual(finding_path.read_bytes(), before_finding)

    def test_external_change_to_active_finding_requires_reassessment_and_blocks_watermark(self) -> None:
        (self.root / "app/page.yaml").parent.mkdir(parents=True, exist_ok=True)
        (self.root / "app/page.yaml").write_text("page: current\n", encoding="utf-8")
        finding_path = self.write_finding("FIND-PAGE", "app/page.yaml")
        before_finding = finding_path.read_bytes()
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Add active finding")
        baseline = reconciliation.adopt_baseline(self.root, confirmed=True)["watermark"]["last_reconciled_commit"]
        self.commit_paths({"app/page.yaml": "page: externally changed\n"})
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["finding_impacts"][0]["finding_id"], "FIND-PAGE")
        self.assertEqual(report["finding_impacts"][0]["status"], "REASSESS_REQUIRED")
        self.assertIn("FINDING_IMPACT_UNRECONCILED", report["watermark_gate"]["blockers"])
        self.assertFalse(report["watermark_gate"]["can_advance"])
        self.assertEqual(report["watermark"]["last_reconciled_commit"], baseline)
        self.assertEqual(finding_path.read_bytes(), before_finding)

    def test_persisted_finding_assessment_is_bound_to_affected_blob_delta(self) -> None:
        (self.root / "app/page.yaml").parent.mkdir(parents=True, exist_ok=True)
        (self.root / "app/page.yaml").write_text("page: current\n", encoding="utf-8")
        finding_path = self.write_finding("FIND-PAGE", "app/page.yaml")
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Add active finding")
        baseline = reconciliation.adopt_baseline(self.root, confirmed=True)["watermark"]["last_reconciled_commit"]
        self.commit_paths({"app/page.yaml": "page: externally changed\n"})
        first_report = reconciliation.build_report(self.root)
        delta_fingerprint = first_report["finding_impacts"][0]["delta_fingerprint"]
        finding = json.loads(finding_path.read_text(encoding="utf-8"))
        finding["reconciliation"] = {
            "delta_fingerprint": delta_fingerprint,
            "outcome": "STILL_VALID",
            "assessed_at": "2026-11-01T12:00:00Z",
            "evidence_refs": ["planning/reconciliation/reports/FIND-PAGE-review.json"],
        }
        relative = finding_path.relative_to(self.root).as_posix()
        self.commit_paths({relative: json.dumps(finding, sort_keys=True) + "\n"})
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["finding_impacts"][0]["status"], "STILL_VALID")
        self.assertNotIn("FINDING_IMPACT_UNRECONCILED", report["watermark_gate"]["blockers"])
        self.assertIn("EXTERNAL_CHANGE_RECONCILIATION_REQUIRED", report["watermark_gate"]["blockers"])
        self.assertFalse(report["watermark_gate"]["can_advance"])
        self.assertEqual(report["watermark"]["last_reconciled_commit"], baseline)

    def test_watermark_advance_blocks_unreconciled_finding_impact(self) -> None:
        (self.root / "app/page.yaml").parent.mkdir(parents=True, exist_ok=True)
        (self.root / "app/page.yaml").write_text("current\n", encoding="utf-8")
        self.write_finding("FIND-PAGE", "app/page.yaml")
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Add linked Finding")
        baseline = reconciliation.adopt_baseline(self.root, confirmed=True)["watermark"]["last_reconciled_commit"]
        self.commit_paths({
            "app/page.yaml": "external\n",
            "planning/reconciliation/assessment.json": "{\"pending\":true}\n",
        })
        report = reconciliation.build_report(self.root)
        external_paths = sorted({
            item["path"] for entry in report["commit_range"]["commits"] for item in entry["paths"]
            if item["classification"] == "EXTERNAL_CHANGE"
        })
        result = reconciliation.advance_watermark(
            self.root,
            confirmed=True,
            expected_report_id=report["report_id"],
            reconciled_paths=external_paths,
            impact_references=["planning/reconciliation/assessment.json"],
        )
        self.assertEqual(result["status"], "FINDING_IMPACT_UNRECONCILED")
        self.assertEqual(reconciliation.build_report(self.root)["watermark"]["last_reconciled_commit"], baseline)

    def test_framework_followup_verified_requires_doctor_and_commit_evidence(self) -> None:
        self.write_finding(
            "FIND-CORE-FIX",
            "scripts/reconcile_external_changes.py",
            origin="FRAMEWORK_FOLLOWUP",
            lifecycle_status="VERIFIED",
            extra={
                "framework_commit": "a" * 40,
                "resolution_commit": "b" * 40,
                "resolution_references": ["planning/reconciliation/reports/doctor-001.json"],
                "evidence_refs": ["planning/evidence/framework-followup-001.json"],
                "reconciliation": {
                    "delta_fingerprint": "sha256:" + "d" * 64,
                    "outcome": "RESOLVED",
                    "assessed_at": "2026-11-01T12:00:00Z",
                    "evidence_refs": ["planning/reconciliation/reports/doctor-001.json"],
                },
            },
        )
        status = reconciliation._project_status(self.root)
        self.assertEqual(status["findings"]["resolved"], 1)
        self.assertEqual(status["findings"]["framework_followup"], 0)
        self.assertEqual(status["findings"]["items"], [])
        self.assertEqual(status["findings"]["history"][0]["resolution_references"], ["planning/reconciliation/reports/doctor-001.json"])

    def test_framework_change_alone_does_not_resolve_followup(self) -> None:
        (self.root / "scripts").mkdir(exist_ok=True)
        (self.root / "scripts/core.py").write_text("old framework\n", encoding="utf-8")
        self.write_finding("FIND-CORE", "scripts/core.py", origin="FRAMEWORK_FOLLOWUP")
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Add framework followup")
        reconciliation.adopt_baseline(self.root, confirmed=True)
        self.commit_paths({"scripts/core.py": "updated framework\n"})
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["finding_impacts"][0]["status"], "FRAMEWORK_FOLLOWUP_REVIEW_REQUIRED")
        self.assertFalse(report["watermark_gate"]["can_advance"])

    def test_framework_followup_resolves_only_after_doctor_and_reality_evidence(self) -> None:
        (self.root / "scripts").mkdir(exist_ok=True)
        (self.root / "scripts/core.py").write_text("old framework\n", encoding="utf-8")
        finding_path = self.write_finding("FIND-CORE", "scripts/core.py", origin="FRAMEWORK_FOLLOWUP")
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Add framework followup")
        reconciliation.adopt_baseline(self.root, confirmed=True)
        framework_commit = self.commit_paths({"scripts/core.py": "fixed framework\n"})
        pending = reconciliation.build_report(self.root)
        self.assertEqual(pending["finding_impacts"][0]["status"], "FRAMEWORK_FOLLOWUP_REVIEW_REQUIRED")
        finding = json.loads(finding_path.read_text(encoding="utf-8"))
        finding.update({
            "lifecycle_status": "VERIFIED",
            "framework_commit": framework_commit,
            "resolution_commit": framework_commit,
            "evidence_refs": ["planning/evidence/framework-reality.json"],
            "resolution_references": ["planning/reconciliation/doctor-001.json"],
            "reconciliation": {
                "delta_fingerprint": pending["finding_impacts"][0]["delta_fingerprint"],
                "outcome": "RESOLVED",
                "assessed_at": "2026-11-01T12:00:00Z",
                "evidence_refs": ["planning/reconciliation/doctor-001.json", "planning/evidence/framework-reality.json"],
            },
        })
        self.commit_paths({
            "planning/findings/FIND-CORE.yml": json.dumps(finding, sort_keys=True) + "\n",
            "planning/reconciliation/doctor-001.json": "{\"result\":\"PASS\"}\n",
            "planning/evidence/framework-reality.json": "{\"verified\":true}\n",
        })
        resolved = reconciliation.build_report(self.root)
        self.assertEqual(resolved["finding_impacts"][0]["status"], "RESOLVED")
        self.assertNotIn("FINDING_IMPACT_UNRECONCILED", resolved["watermark_gate"]["blockers"])

    def test_external_mockup_is_candidate_not_active_target(self) -> None:
        (self.root / "input-resources/ui-ux").mkdir(parents=True, exist_ok=True)
        (self.root / "planning/target-mockups").mkdir(parents=True, exist_ok=True)
        (self.root / "input-resources/ui-ux/source.html").write_text("<html>source</html>\n", encoding="utf-8")
        (self.root / "planning/target-mockups/accepted.html").write_text("<html>accepted target</html>\n", encoding="utf-8")
        inventory = {
            "page_id": "PAGE-REGION",
            "source_mockup": "input-resources/ui-ux/source.html",
            "target_mockup": "planning/target-mockups/accepted.html",
        }
        page_path = self.root / "planning/ui-inventory/PAGE-REGION.yaml"
        page_path.parent.mkdir(parents=True, exist_ok=True)
        page_path.write_text(json.dumps(inventory) + "\n", encoding="utf-8")
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Adopt current target authority")
        reconciliation.adopt_baseline(self.root, confirmed=True)
        active_before = reconciliation._project_status(self.root)["project"]["active_targets"]["items"]
        self.commit_paths({"input-resources/ui-ux/new-refined.html": "<html>new proposal</html>\n"})
        report = reconciliation.build_report(self.root)
        self.assertIn(
            {"path": "input-resources/ui-ux/new-refined.html", "status": "REFERENCE_RECONCILIATION_REQUIRED"},
            report["external_reference_candidates"],
        )
        self.assertEqual(report["active_references"], active_before)
        self.assertEqual(report["impact_resolution"]["status"], "INDEX_MISSING")

    def test_artifact_impact_candidates_require_current_index_fingerprint(self) -> None:
        index_path = self.root / ".mxagile/state/artifact-index.json"
        index_path.parent.mkdir(parents=True, exist_ok=True)
        index_path.write_text(json.dumps({
            "source_fingerprint": "sha256:" + "a" * 64,
            "nodes": [
                {"id": "PAGE-1", "path": "planning/ui-inventory/PAGE-1.yaml"},
                {"id": "REQ-001", "path": "requirements/REQ-001.yml"},
            ],
            "edges": [{"from": "REQ-001", "to": "PAGE-1", "provenance": {"type": "DECLARED"}}],
        }), encoding="utf-8")
        changed = [{"path": "planning/ui-inventory/PAGE-1.yaml", "classification": "EXTERNAL_CHANGE"}]
        with patch.object(resolve_impact, "_compute_current_fingerprint", return_value="sha256:" + "a" * 64):
            current = reconciliation._impact_candidates(self.root, changed)
        self.assertEqual(current["status"], "CURRENT")
        self.assertEqual(current["candidates"][0]["artifact_ids"], ["PAGE-1"])
        self.assertEqual(current["candidates"][0]["related_artifact_ids"], ["REQ-001"])
        with patch.object(resolve_impact, "_compute_current_fingerprint", return_value="sha256:" + "b" * 64):
            stale = reconciliation._impact_candidates(self.root, changed)
        self.assertEqual(stale, {"status": "INDEX_STALE", "candidates": []})

    def test_model_delta_without_local_mpr_or_mxcli_requires_semantic_review(self) -> None:
        no_project = reconciliation._model_semantic_capability(self.root, ["mprcontents/units/Unit.mxunit"])
        self.assertEqual(no_project["status"], "SEMANTIC_REVIEW_REQUIRED")
        self.assertEqual(no_project["reason"], "PROJECT_MPR_NOT_FOUND")
        (self.root / "Fixture.mpr").write_bytes(b"fixture")
        no_binary = reconciliation._model_semantic_capability(self.root, ["mprcontents/units/Unit.mxunit"])
        self.assertEqual(no_binary["reason"], "PROJECT_LOCAL_MXCLI_NOT_FOUND")

    def test_model_capability_probe_uses_only_project_local_binary(self) -> None:
        (self.root / "Fixture.mpr").write_bytes(b"fixture")
        binary = self.root / ("mxcli.exe" if sys.platform == "win32" else "mxcli")
        binary.write_bytes(b"fixture binary")
        calls = []

        def fake_probe(arguments, **kwargs):
            calls.append(arguments[0])
            if arguments[-1] == "--version":
                return subprocess.CompletedProcess(arguments, 0, stdout="mxcli fixture-version\n", stderr="")
            return subprocess.CompletedProcess(arguments, 0, stdout="commands: inspect\n", stderr="")

        with patch.object(reconciliation.subprocess, "run", side_effect=fake_probe):
            report = reconciliation._model_semantic_capability(self.root, ["mprcontents/units/Unit.mxunit"])
        self.assertEqual(report["status"], "SEMANTIC_REVIEW_REQUIRED")
        self.assertEqual(report["reason"], "SEMANTIC_MODEL_DIFF_NOT_VERIFIED")
        self.assertEqual(report["capabilities"], ["inspect"])
        self.assertEqual(calls, [str(binary), str(binary)])

    def test_watermark_advance_requires_confirmation_and_exact_impact_coverage(self) -> None:
        reconciliation.adopt_baseline(self.root, confirmed=True)
        commit = self.commit_paths({
            "external/page.yaml": "changed\n",
            "planning/reconciliation/assessment.json": "{\"outcome\":\"NO_IMPACT\"}\n",
        })
        report = reconciliation.build_report(self.root)
        required_paths = sorted({
            item["path"]
            for entry in report["commit_range"]["commits"]
            for item in entry["paths"]
            if item["classification"] == "EXTERNAL_CHANGE"
        })
        missing_confirmation = reconciliation.advance_watermark(
            self.root,
            expected_report_id=report["report_id"],
            reconciled_paths=required_paths,
            impact_references=["planning/reconciliation/assessment.json"],
        )
        self.assertEqual(missing_confirmation["status"], "WATERMARK_ADVANCE_CONFIRMATION_REQUIRED")
        wrong_coverage = reconciliation.advance_watermark(
            self.root,
            confirmed=True,
            expected_report_id=report["report_id"],
            reconciled_paths=["external/page.yaml"],
            impact_references=["planning/reconciliation/assessment.json"],
        )
        self.assertEqual(wrong_coverage["status"], "EXTERNAL_PATH_COVERAGE_MISMATCH")
        advanced = reconciliation.advance_watermark(
            self.root,
            confirmed=True,
            expected_report_id=report["report_id"],
            reconciled_paths=required_paths,
            impact_references=["planning/reconciliation/assessment.json"],
        )
        self.assertEqual(advanced["status"], "WATERMARK_ADVANCED")
        self.assertEqual(advanced["watermark"]["last_reconciled_commit"], commit)
        self.assertEqual(advanced["watermark"]["reconciliation_references"], ["planning/reconciliation/assessment.json"])

    def test_watermark_write_rolls_back_if_head_changes(self) -> None:
        adopted = reconciliation.adopt_baseline(self.root, confirmed=True)
        state_path = self.root / adopted["state_path"]
        old_state = state_path.read_bytes()
        self.commit_paths({
            "external/page.yaml": "changed\n",
            "planning/reconciliation/assessment.json": "{\"outcome\":\"NO_IMPACT\"}\n",
        })
        report = reconciliation.build_report(self.root)
        required_paths = sorted({
            item["path"]
            for entry in report["commit_range"]["commits"]
            for item in entry["paths"]
            if item["classification"] == "EXTERNAL_CHANGE"
        })
        original_write = reconciliation._atomic_write_json
        mutated = False

        def race_after_watermark(path: Path, state: dict) -> None:
            nonlocal mutated
            original_write(path, state)
            if state["baseline_kind"] == "RECONCILED" and not mutated:
                mutated = True
                (self.root / "racing.txt").write_text("new head\n", encoding="utf-8")
                self.git("add", "--", "racing.txt")
                self.git("commit", "--quiet", "-m", "Head changed during watermark write")

        with patch.object(reconciliation, "_atomic_write_json", side_effect=race_after_watermark):
            result = reconciliation.advance_watermark(
                self.root,
                confirmed=True,
                expected_report_id=report["report_id"],
                reconciled_paths=required_paths,
                impact_references=["planning/reconciliation/assessment.json"],
            )
        self.assertEqual(result["status"], "REPOSITORY_CHANGED_DURING_WATERMARK_WRITE")
        self.assertEqual(state_path.read_bytes(), old_state)

    def test_superseded_finding_requires_link_and_is_compact_history(self) -> None:
        self.write_finding("FIND-OLD", "app/old-page.yaml", lifecycle_status="SUPERSEDED", extra={"superseded_by": "FIND-NEW"})
        self.write_finding("FIND-NEW", "app/new-page.yaml")
        status = reconciliation._project_status(self.root)
        self.assertEqual([item["id"] for item in status["findings"]["items"]], ["FIND-NEW"])
        self.assertEqual(status["findings"]["superseded"], 1)
        self.assertEqual(status["findings"]["history"][0]["superseded_by"], "FIND-NEW")
        self.assertNotIn("title", status["findings"]["history"][0])
        self.assertNotIn("observation", status["findings"]["history"][0])

    def test_verified_finding_is_removed_from_active_projection_but_retained(self) -> None:
        self.write_finding(
            "FIND-RESOLVED",
            "app/page.yaml",
            lifecycle_status="VERIFIED",
            extra={"evidence_refs": ["EV-001"], "resolution_references": ["planning/evidence/doctor.json"]},
        )
        status = reconciliation._project_status(self.root)
        self.assertEqual(status["findings"]["items"], [])
        self.assertEqual(status["findings"]["resolved"], 1)
        self.assertEqual(status["findings"]["history"][0]["evidence_refs"], ["EV-001"])
        self.assertEqual(status["findings"]["history"][0]["resolution_references"], ["planning/evidence/doctor.json"])

    def test_retired_finding_requires_reason(self) -> None:
        path = self.write_finding("FIND-RETIRED", "app/page.yaml", lifecycle_status="RETIRED")
        errors = project_compatibility.schema_errors(
            "planning/findings/FIND-RETIRED.yml", json.loads(path.read_text(encoding="utf-8"))
        )
        self.assertIn("required", errors)

    def test_change_set_producer_writes_but_never_stages_or_commits(self) -> None:
        (self.root / "app/page.yaml").parent.mkdir(parents=True, exist_ok=True)
        (self.root / "app/page.yaml").write_text("page: staged\n", encoding="utf-8")
        self.git("add", "--", "app/page.yaml")
        prepared = git_reconciliation.prepare_change_set(
            self.root,
            change_set_id="CS-PREPARED",
            mission_id="MISSION-2026-10-31-fixture",
            project_fingerprint="sha256:" + "b" * 64,
            outcome="NO_IMPACT",
        )
        self.assertEqual(prepared["status"], "CHANGE_SET_PREPARED")
        self.assertFalse(prepared["staged"])
        self.assertFalse(prepared["committed"])
        self.assertEqual(prepared["trailers"][-1], "MxAgile-Change-Set: CS-PREPARED")
        staged = self.git("diff", "--cached", "--name-only", "HEAD").splitlines()
        self.assertEqual(staged, ["app/page.yaml"])
        self.assertTrue((self.root / prepared["path"]).is_file())

    def test_change_set_producer_rejects_unstaged_and_untracked_paths(self) -> None:
        (self.root / "app/page.yaml").parent.mkdir(parents=True, exist_ok=True)
        (self.root / "app/page.yaml").write_text("page: staged\n", encoding="utf-8")
        self.git("add", "--", "app/page.yaml")
        (self.root / "outside.txt").write_text("untracked\n", encoding="utf-8")
        with self.assertRaises(git_reconciliation.GitReconciliationError):
            git_reconciliation.prepare_change_set(
                self.root,
                change_set_id="CS-UNSTABLE",
                mission_id="MISSION-2026-10-31-fixture",
                project_fingerprint="sha256:" + "c" * 64,
                outcome="NO_IMPACT",
            )

    def test_change_set_cli_requires_explicit_confirmation(self) -> None:
        output = StringIO()
        with redirect_stdout(output):
            exit_code = reconciliation.main([
                "--project-root", str(self.root), "prepare-change-set",
                "--change-set-id", "CS-NO-CONFIRM",
                "--mission-id", "MISSION-2026-10-31-fixture",
                "--reconciliation-outcome", "NO_IMPACT",
            ])
        self.assertEqual(exit_code, 2)
        self.assertEqual(json.loads(output.getvalue())["status"], "CHANGE_SET_CONFIRMATION_REQUIRED")
        self.assertFalse((self.root / "planning/reconciliation/change-sets/CS-NO-CONFIRM.json").exists())

    def test_public_report_keeps_staged_unstaged_and_untracked_separate(self) -> None:
        (self.root / "source.txt").write_text("staged\n", encoding="utf-8")
        self.git("add", "--", "source.txt")
        (self.root / "source.txt").write_text("unstaged\n", encoding="utf-8")
        (self.root / "new.txt").write_text("untracked\n", encoding="utf-8")
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["status"], "DIRTY_UNRECONCILED")
        self.assertEqual(report["working_changes"]["staged"][0]["path"], "source.txt")
        self.assertEqual(report["working_changes"]["unstaged"][0]["path"], "source.txt")
        self.assertEqual(report["working_changes"]["untracked"][0]["path"], "new.txt")

    def test_branch_switch_requires_branch_specific_baseline(self) -> None:
        reconciliation.adopt_baseline(self.root, confirmed=True)
        self.git("switch", "--quiet", "-c", "feature/other-branch")
        report = reconciliation.build_report(self.root)
        self.assertEqual(report["status"], "BASELINE_REQUIRED")
        self.assertEqual(report["branch_ref"], "refs/heads/feature/other-branch")

    def test_rewritten_history_is_diverged(self) -> None:
        watermark = self.git("rev-parse", "HEAD")
        self.git("checkout", "--quiet", "--orphan", "rewritten")
        self.git("add", "--all")
        self.git("commit", "--quiet", "-m", "Rewritten root")
        head = self.git("rev-parse", "HEAD")
        result = git_reconciliation.analyze_commit_range(self.root, watermark, head)
        self.assertEqual(result["status"], "DIVERGED_HISTORY")

    def test_merge_commit_with_only_inherited_paths_is_not_new_delta(self) -> None:
        watermark = self.git("rev-parse", "HEAD")
        main_branch = self.git("symbolic-ref", "--short", "HEAD")
        self.git("switch", "--quiet", "-c", "feature/side")
        (self.root / "side.txt").write_text("side\n", encoding="utf-8")
        self.git("add", "--", "side.txt")
        self.git("commit", "--quiet", "-m", "Side change")
        self.git("switch", "--quiet", main_branch)
        (self.root / "main.txt").write_text("main\n", encoding="utf-8")
        self.git("add", "--", "main.txt")
        self.git("commit", "--quiet", "-m", "Main change")
        self.git("merge", "--quiet", "--no-ff", "feature/side", "-m", "Merge side")
        head = self.git("rev-parse", "HEAD")
        result = git_reconciliation.analyze_commit_range(self.root, watermark, head)
        self.assertEqual(len(result["commits"][-1]["parents"]), 2)
        self.assertEqual(result["commits"][-1]["classification"], "INHERITED_MERGE")
        self.assertEqual(result["commits"][-1]["paths"], [])

    def test_unattributed_merge_resolution_is_ambiguous(self) -> None:
        watermark = self.git("rev-parse", "HEAD")
        main_branch = self.git("symbolic-ref", "--short", "HEAD")
        self.git("switch", "--quiet", "-c", "feature/conflict")
        (self.root / "source.txt").write_text("side\n", encoding="utf-8")
        self.git("add", "--", "source.txt")
        self.git("commit", "--quiet", "-m", "Side edit")
        self.git("switch", "--quiet", main_branch)
        (self.root / "source.txt").write_text("main\n", encoding="utf-8")
        self.git("add", "--", "source.txt")
        self.git("commit", "--quiet", "-m", "Main edit")
        merge = subprocess.run(
            ["git", "-C", str(self.root), "merge", "--no-ff", "feature/conflict", "-m", "Resolve conflict"],
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(merge.returncode, 0)
        (self.root / "source.txt").write_text("resolved\n", encoding="utf-8")
        self.git("add", "--", "source.txt")
        self.git("commit", "--quiet", "-m", "Resolve conflict")
        head = self.git("rev-parse", "HEAD")
        result = git_reconciliation.analyze_commit_range(self.root, watermark, head)
        self.assertEqual(result["status"], "AMBIGUOUS_HISTORY")
        self.assertEqual(result["commits"][-1]["classification"], "AMBIGUOUS")

    def test_active_operations_are_root_bound_and_block_delta_scan(self) -> None:
        for name, operation in (
            ("MERGE_HEAD", "MERGE"), ("CHERRY_PICK_HEAD", "CHERRY_PICK"),
            ("REVERT_HEAD", "REVERT"), ("rebase-merge", "REBASE"), ("rebase-apply", "REBASE"),
        ):
            with self.subTest(operation=name):
                metadata = self.root / ".git" / name
                if name.startswith("rebase-"):
                    metadata.mkdir()
                else:
                    metadata.write_text(self.git("rev-parse", "HEAD") + "\n", encoding="ascii")
                try:
                    with patch.object(reconciliation, "working_tree_changes", side_effect=AssertionError("Delta scan during Git operation")):
                        report = reconciliation.build_report(self.root)
                    self.assertEqual(report["status"], "GIT_OPERATION_IN_PROGRESS")
                    self.assertEqual(report["operations_in_progress"], [operation])
                    self.assertEqual(report["working_changes"], {"staged": [], "unstaged": [], "untracked": []})
                finally:
                    if metadata.is_dir():
                        metadata.rmdir()
                    else:
                        metadata.unlink()

    def test_integrity_failure_blocks_range_before_delta_scan(self) -> None:
        failure = {"state": "GIT_INDEX_INTEGRITY_FAILURE", "mutations_allowed": False}
        with patch.object(reconciliation, "inspect_index", return_value=failure):
            report = reconciliation.build_report(self.root)
        self.assertEqual(report["status"], "GIT_INTEGRITY_BLOCKED")
        self.assertEqual(report["working_changes"]["staged"], [])

    def test_same_branch_worktrees_get_distinct_local_state(self) -> None:
        reconciliation.adopt_baseline(self.root, confirmed=True)
        branch = self.git("symbolic-ref", "--short", "HEAD")
        second = self.root.parent / f"{self.root.name}-second-worktree"
        subprocess.run(
            ["git", "-C", str(self.root), "worktree", "add", "--force", str(second), branch],
            check=True,
            capture_output=True,
        )
        try:
            first_paths = reconciliation._git_paths(self.root)
            second_paths = reconciliation._git_paths(second)
            self.assertNotEqual(first_paths["git_dir"], second_paths["git_dir"])
            self.assertNotEqual(
                reconciliation._branch_state_path(self.root, f"refs/heads/{branch}")[0],
                reconciliation._branch_state_path(second, f"refs/heads/{branch}")[0],
            )
            self.assertEqual(reconciliation.build_report(second)["status"], "BASELINE_REQUIRED")
        finally:
            subprocess.run(
                ["git", "-C", str(self.root), "worktree", "remove", "--force", str(second)],
                check=True,
                capture_output=True,
            )


if __name__ == "__main__":
    unittest.main()