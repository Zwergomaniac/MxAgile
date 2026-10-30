"""Fixture tests for the deterministic project-status builder."""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
import tempfile
import textwrap
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts" / "build_project_status.py"
SCHEMA = ROOT / ".mxagile" / "schemas" / "project-status.schema.json"
sys.path.insert(0, str(ROOT / "scripts"))
import build_project_status
import canonicalize_artifacts
import serve_project_board
import project_compatibility


def write_file(root: Path, relative: str, content: str) -> Path:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content).lstrip(), encoding="utf-8")
    return path


def write_revision(
  root: Path,
  mockup_name: str,
  revision: int,
  active: bool,
  bundle_hash_digit: str,
  entry_point: str = "index.html",
) -> Path:
  revision_id = f"REV-{revision:03d}"
  lifecycle_status = "REFINED_TARGET" if active else "SUPERSEDED_TARGET"
  trigger = "initial_acceptance" if revision == 1 else "refinement_accepted"
  content = f"""
    revision: {revision}
    revision_id: {revision_id}
    mockup_name: {mockup_name}
    created_at: '2026-10-30'
    lifecycle_status: {lifecycle_status}
    refinement_status: ACCEPTED
    active_target: {str(active).lower()}
    entry_point: {entry_point}
    bundle_hash: sha256:{bundle_hash_digit * 64}
    lifecycle_trigger: {trigger}
    change_classification: material
    impact_scope: full
  """
  path = write_file(root, f"planning/target-mockups/{mockup_name}/_history/{revision_id}/revision.yaml", content)
  write_file(root, f"planning/target-mockups/{mockup_name}/_history/{revision_id}/{entry_point}", f"<html>{mockup_name} {revision_id}</html>\n")
  return path


def write_page(root: Path, page_id: str, mockup_name: str, revision_id: str, section_ids: tuple[str, ...] = ()) -> None:
  sections = "\n".join(f"  - id: {section_id}\n    title: {section_id}" for section_id in section_ids)
  content = f"page_id: {page_id}\nmockup_name: {mockup_name}\ntarget_revision: {revision_id}\n"
  if sections:
    content += f"sections:\n{sections}\n"
  write_file(root, f"planning/ui-inventory/{page_id}.yaml", content)


def write_single_file_page(root: Path, page_id: str, source_path: str, target_path: str, section_ids: tuple[str, ...] = ()) -> None:
  fields = [f"page_id: {page_id}", f"source_mockup: {source_path}", f"target_mockup: {target_path}"]
  if section_ids:
    fields.extend(["sections:", *[f"  - id: {section_id}\n    title: {section_id}" for section_id in section_ids]])
  write_file(root, f"planning/ui-inventory/{page_id}.yaml", "\n".join(fields) + "\n")


def write_task(
  root: Path,
  task_id: str,
  status: str,
  *,
  wave_id: str | None = None,
  workpackage_id: str | None = None,
  requirement_ids: tuple[str, ...] = (),
  migrated_from: str | None = None,
) -> None:
  fields = [f"ID: {task_id}", "spec: SPEC-001", f"action: {task_id}", f"status: {status}"]
  if wave_id:
    fields.append(f"wave_id: {wave_id}")
  if workpackage_id:
    fields.append(f"workpackage_id: {workpackage_id}")
  if requirement_ids:
    fields.append(f"req: [{', '.join(requirement_ids)}]")
  if migrated_from:
    fields.append(f"migrated_from: {migrated_from}")
  write_file(root, f"planning/tasks/{task_id}.yml", "\n".join(fields) + "\n")


def write_finding(
  root: Path,
  finding_id: str,
  lifecycle_status: str,
  severity: str,
  *,
  wave_id: str | None = None,
  workpackage_id: str | None = None,
  requirement_ids: tuple[str, ...] = (),
) -> None:
  fields = [
    f"ID: {finding_id}", f"title: {finding_id}", "gap_type: INTERACTION_GAP",
    f"severity: {severity}", f"lifecycle_status: {lifecycle_status}",
    f"observation: Observed state for {finding_id}.", "source_artifacts: []",
  ]
  if wave_id:
    fields.append(f"wave_id: {wave_id}")
  if workpackage_id:
    fields.append(f"workpackage_id: {workpackage_id}")
  if requirement_ids:
    fields.append(f"requirement_ids: [{', '.join(requirement_ids)}]")
  write_file(root, f"planning/findings/{finding_id}.yml", "\n".join(fields) + "\n")


def fixture(root: Path) -> None:
    write_file(root, "mxagile-project.yaml", "name: Board Fixture\n")
    write_file(root, ".mxagile/version.yaml", "version: '1.7.0'\n")
    write_file(root, ".env.mendix", "PASSWORD=do-not-export-this-secret\n")
    write_file(root, "planning/parity/PAGE-1.yaml", "page_id: PAGE-1\noverall_result: PASS\n")
    write_file(root, "planning/evidence/screenshots/SCN-1/actual.svg", "<svg xmlns='http://www.w3.org/2000/svg'></svg>\n")
    write_file(root, "planning/lifecycle/context-epoch.yaml", """
      schema_version: '1.0'
      mission: {id: MISSION-2026-10-30-board, objective: Test context projection, status: active}
      scope: {project: fixture}
      lifecycle: {current_phase: implementing, active_context_epoch: EPOCH-007}
      repository: {branch: feature/test, commit: abc1234}
      context: {epoch_id: EPOCH-007, pressure_state: UNKNOWN}
    """)
    write_file(root, "planning/lifecycle/process-state.yaml", """
        waves:
          W01:
            phase: verifying
            gates:
              gate_to_refinement: {result: passed}
              gate_to_ready: {result: passed}
            prerequisite_state:
              runtime_mode: autonomous
              database: reachable
          W02:
            phase: done
            gates:
              gate_to_refinement: {result: passed}
              gate_to_ready: {result: passed}
    """)
    write_file(root, "planning/mission/mission-state.yaml", """
        schema_version: 1
        mission_id: MISSION-2026-10-30-board
        created_at: '2026-10-30'
        objective: Exercise deterministic status.
        completion_boundary: USER_MISSION_COMPLETE
        criteria:
          lifecycle_derived: {}
        active_wave: W01
        progress:
          mission: blocked
        blockers:
          - type: DECISION_REQUIRED
            description: Waits on a business decision.
            blast_radius: REQUIREMENT
    """)
    write_file(root, "requirements/REQ-001.yml", """
        ID: REQ-001
        title: A requirement
        description: A test requirement.
        status: accepted
    """)
    write_file(root, "planning/tasks/TASK-001.yml", """
        ID: TASK-001
        spec: SPEC-001
        action: An open task
        status: pending
    """)
    write_file(root, "planning/tasks/TASK-002.yml", """
        ID: TASK-002
        spec: SPEC-001
        action: A completed task
        status: done
    """)
    write_file(root, "planning/decisions/DEC-001.yml", """
        ID: DEC-001
        title: Pending choice
        status: PROPOSED
        decision_type: business
        topic: A pending choice
        decision_text: Wait for an explicit choice.
        owner: ProductOwner
        affected_requirements: [REQ-001]
    """)
    write_file(root, "planning/test-contracts/TC-001.yaml", """
        schema_version: 1
        ID: TC-001
        title: Contract
        status: active
        requirement_ids: [REQ-001]
        proof_points:
          - id: PP-001
            claim: The requirement works.
            role: ROLE-USER
            data_state: populated
            required_layers: [MODEL]
    """)
    write_file(root, "planning/verification-plans/VPL-001.yaml", """
        schema_version: 1
        ID: VPL-001
        test_contract_id: TC-001
        wave_id: W01
        status: active
        layer_assignments:
          - proof_point_id: PP-001
            layer_decisions:
              - layer: MODEL
                included: true
                rationale: Model evidence is required.
    """)
    write_file(root, "planning/target-mockups/Board/_history/REV-002/revision.yaml", """
        revision: 2
        revision_id: REV-002
        mockup_name: Board
        created_at: '2026-10-30'
        lifecycle_status: REFINED_TARGET
        refinement_status: ACCEPTED
        active_target: true
        entry_point: index.html
        bundle_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        lifecycle_trigger: initial_acceptance
        change_classification: material
        impact_scope: full
    """)
    write_file(root, "planning/target-mockups/Board/_history/REV-002/index.html", "<html><body>Accepted target</body></html>\n")
    write_file(root, "planning/evidence/manifests/W01-evidence-manifest.yaml", """
        manifest_id: MFT-W01
        wave_id: W01
        entries:
          - entry_id: EVD-1
            scenario_id: SCN-1
            screen_id: PAGE-1
            role: ROLE-USER
            data_state: populated
            parity_result: PASS
            mockup_name: Board
            target_revision: REV-001
            parity_report_path: planning/parity/PAGE-1.yaml
            actual_evidence:
              - artifact_id: EVD-1-SCREEN
                type: screenshot
                path: planning/evidence/screenshots/SCN-1/actual.svg
          - entry_id: EVD-2
            scenario_id: SCN-2
            screen_id: PAGE-2
            role: ROLE-USER
            data_state: populated
            parity_result: STALE
            mockup_name: Board
            target_revision: REV-002
    """)
def run_builder(project: Path) -> tuple[str, dict]:
  status = build_project_status.build_status(project)
  output = json.dumps(status, ensure_ascii=False, indent=2, sort_keys=True)
  return output, json.loads(output)


def tree_fingerprint(root: Path) -> str:
    entries = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        entries.append(f"{path.relative_to(root).as_posix()}:{hashlib.sha256(path.read_bytes()).hexdigest()}")
    return "\n".join(entries)


class ProjectStatusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="mxagile-status-")
        self.root = Path(self.temp.name) / "fixture"
        self.root.mkdir()
        fixture(self.root)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_parser_diagnostic_preserves_location_without_source_content(self) -> None:
      write_file(self.root, "planning/lifecycle/process-state.yaml", "waves: invalid: secret-scalar-value\n")
      _, status = run_builder(self.root)
      diagnostic = next(gap for gap in status["gaps"] if gap["code"] == "SOURCE_PARSE_FAILED")
      self.assertEqual(diagnostic["line"], 1)
      self.assertGreater(diagnostic["column"], 0)
      self.assertNotIn("secret-scalar-value", json.dumps(status))
      self.assertEqual(len(status["delivery"]["tasks"]["items"]), 2)

    def test_doctor_is_read_only_deterministic_and_sanitized(self) -> None:
      write_file(self.root, "planning/lifecycle/process-state.yaml", "waves: invalid: SECRET-SYNTAX\n")
      before = tree_fingerprint(self.root)
      first = build_project_status.build_status(self.root)["compatibility"]
      second = build_project_status.build_status(self.root)["compatibility"]
      self.assertEqual(first, second)
      self.assertEqual(before, tree_fingerprint(self.root))
      diagnostic = next(item for item in first["diagnostics"] if item["category"] == "SYNTAX_ERROR")
      self.assertEqual(diagnostic["line"], 1)
      self.assertEqual(diagnostic["affected_board_area"], "waves")
      self.assertEqual(first["coverage"]["task"]["parsed"], 2)
      self.assertNotIn("SECRET-SYNTAX", json.dumps(first))
      self.assertNotIn("do-not-export", json.dumps(first))

    def test_legacy_contract_suffix_requires_schema_and_unique_identity(self) -> None:
      original = self.root / "planning/test-contracts/TC-001.yaml"
      suffix = original.with_name("TC-001-descriptive-name.yaml")
      original.rename(suffix)
      status = build_project_status.build_status(self.root)
      self.assertEqual(len(status["verification"]["test_contracts"]["items"]), 1)
      self.assertTrue(any(item["category"] == "LEGACY_VARIANT" for item in status["compatibility"]["diagnostics"]))
      shutil.copyfile(suffix, original)
      status = build_project_status.build_status(self.root)
      self.assertEqual(status["verification"]["test_contracts"]["items"], [])
      self.assertTrue(any(item["category"] == "DUPLICATE_ID" for item in status["compatibility"]["diagnostics"]))
      original.unlink()
      suffix.write_text(suffix.read_text().replace("ID: TC-001", "ID: TC-999"))
      self.assertEqual(build_project_status.build_status(self.root)["verification"]["test_contracts"]["items"], [])

    def test_partial_verification_retains_valid_plan(self) -> None:
      write_file(self.root, "planning/verification-plans/VPL-002.yaml", "ID: invalid: scalar\n")
      status = build_project_status.build_status(self.root)
      self.assertEqual(status["verification"]["plans"]["availability"], "partial")
      self.assertEqual(status["verification"]["plans"]["status_counts"]["active"], 1)

    def test_schema_diagnostics_do_not_invent_semantic_content(self) -> None:
      relative = "requirements/REQ-001.yml"
      value = {"ID": "REQ-001", "title": "Fixture", "description": "Fixture",
               "status": "confirmed", "legacy_metadata": "SECRET", "acceptance_criteria": [{}]}
      issues = project_compatibility.schema_diagnostics(relative, value)
      required = [item for item in issues if "Required canonical" in item[0]]
      self.assertEqual(len(required), 4)
      self.assertTrue(all(item[1] == "DECISION_REQUIRED" for item in required))
      self.assertTrue(any(item[1] == "AGENT_REPAIRABLE" for item in issues))
      self.assertNotIn("SECRET", str(issues))
      issues = project_compatibility.schema_diagnostics("planning/test-contracts/TC-001.yaml", {})
      self.assertTrue(any("proof_points" in item[0] and item[1] == "DECISION_REQUIRED" for item in issues))

    def test_evidence_schema_refs_resolve_locally_without_network(self) -> None:
      manifest = {"manifest_id": "MFT-W01", "wave_id": "W01", "entries": [{"entry_id": "E1", "scenario_id": "SCN-1", "screen_id": "PAGE-1", "role": "CEKO", "data_state": "populated", "parity_result": "NOT_VERIFIED", "comparison_identity": {"status": "BOUND"}, "capture_groups": []}]}
      errors = project_compatibility.schema_errors("planning/evidence/manifests/W01-evidence-manifest.yaml", manifest)
      self.assertIn("required", errors)

    def test_duplicate_mapping_keys_are_not_silently_accepted(self) -> None:
      for wave in ("W3", "W4A", "W1C"):
        write_file(self.root, f"planning/checklists/{wave}-implementation-checklist.yaml", f"wave_id: {wave}\nitems: []\n")
        self.assertEqual(project_compatibility.assignment(self.root, {"migrated_from": f"planning/checklists/{wave}-implementation-checklist.yaml"}, {wave})[:2], ("derived", wave))
      write_file(self.root, "planning/tasks/TASK-001.yml", "ID: TASK-001\nID: TASK-999\n")
      write_task(self.root, "TASK-002", "done", wave_id="W01", workpackage_id="WP-01")
      status = build_project_status.build_status(self.root)
      self.assertEqual(len(status["delivery"]["tasks"]["items"]), 1)
      self.assertEqual(status["delivery"]["task_progress"]["total"], 1)
      self.assertEqual(status["delivery"]["waves"]["items"][0]["task_progress"]["total"], 1)
      self.assertEqual(status["delivery"]["workpackages"]["items"][0]["task_ids"], ["TASK-002"])
      self.assertTrue(any(item["category"] == "SYNTAX_ERROR" for item in status["compatibility"]["diagnostics"]))

    def test_reality_117_exact_waves_and_six_missing_provenances(self) -> None:
      waves = {wave: {"phase": "ready", "gates": {"gate_to_refinement": {"result": "passed"}, "gate_to_ready": {"result": "passed"}}}
               for wave in ("W3", "W4A", "W1C")}
      write_file(self.root, "planning/lifecycle/process-state.yaml", project_compatibility.yaml.safe_dump({"waves": waves}))
      for wave in waves:
        write_file(self.root, f"planning/checklists/{wave}-implementation-checklist.yaml", f"wave_id: {wave}\nitems: []\n")
      for index in range(117):
        wave = list(waves)[index % 3]
        write_task(self.root, f"TASK-{index + 100:03d}", "pending", migrated_from=f"planning/checklists/{wave}-implementation-checklist.yaml")
      for index in range(6):
        write_task(self.root, f"TASK-{index + 300:03d}", "pending", migrated_from=f".concord/scratch/W{index}-implementation-checklist.yaml")
      before = tree_fingerprint(self.root)
      report = build_project_status.build_status(self.root)["compatibility"]
      plan = project_compatibility.repair_plan(self.root, report)
      self.assertEqual(len(plan["repairs"]), 117)
      self.assertEqual({item["preview"]["after"] for item in plan["repairs"]}, set(waves))
      scratch = [item for item in report["diagnostics"] if item["category"] == "WAVE_ASSIGNMENT_MISSING" and item["source_path"].startswith("planning/tasks/TASK-3")]
      self.assertEqual(len(scratch), 6)
      self.assertTrue(all(item["repairability"] == "DECISION_REQUIRED" for item in scratch))
      self.assertEqual(before, tree_fingerprint(self.root))

    def test_missing_provenance_needs_unique_canonical_review_authority(self) -> None:
      task = {"spec": "SPEC-001", "req": ["REQ-001"]}
      manifest = {"manifest_id": "MFT-W01", "wave_id": "W01", "entries": [{"entry_id": "E1", "scenario_id": "SCN-1", "screen_id": "PAGE-1", "role": "CEKO", "data_state": "populated", "parity_result": "NOT_VERIFIED", "traceability": {"requirements": ["REQ-001"]}}]}
      documents = {"planning/evidence/manifests/W01-evidence-manifest.yaml": manifest}
      self.assertEqual(project_compatibility.wave_review_authority(task, documents, {"W01", "W02"}), next(iter(documents)))
      documents["planning/evidence/manifests/W02-evidence-manifest.yaml"] = {**manifest, "wave_id": "W02"}
      self.assertIsNone(project_compatibility.wave_review_authority(task, documents, {"W01", "W02"}))

    def test_legacy_decisions_remain_historical_without_status_promotion(self) -> None:
      write_file(self.root, "planning/decisions/DEC-099.md", "# Historical\nSECRET-LEGACY-CONTENT\n")
      before = tree_fingerprint(self.root)
      status = build_project_status.build_status(self.root)
      self.assertEqual(status["decisions"]["historical"], [{"id": "DEC-099", "source_path": "planning/decisions/DEC-099.md"}])
      self.assertNotIn("SECRET-LEGACY-CONTENT", json.dumps(status))
      self.assertEqual(before, tree_fingerprint(self.root))

    def test_unknown_legacy_ui_and_inspect_are_not_guessed(self) -> None:
      issues = project_compatibility.schema_diagnostics("planning/ui-inventory/PAGE-1.yaml", {"page": "PAGE-1", "source": "design.html"})
      self.assertTrue(issues)
      self.assertFalse(any(item[1] == "SAFE_DETERMINISTIC" for item in issues))
      issues = project_compatibility.schema_diagnostics("planning/tasks/TASK-001.yml", {"ID": "TASK-001", "spec": "SPEC-001", "action": "Inspect", "inspect": {"entity": "Module.Entity"}})
      self.assertTrue(any(item[1] == "DECISION_REQUIRED" for item in issues))

    def test_legacy_ui_conflicts_are_explicit_and_never_automapped(self) -> None:
      write_file(self.root, "planning/ui-inventory/PAGE-1.yaml", "page_id: PAGE-1\npage: PAGE-9\nsource_mockup: input-resources/ui-ux/new.html\nsource: input-resources/ui-ux/old.html\n")
      report = build_project_status.build_status(self.root)["compatibility"]
      conflicts = [item for item in report["diagnostics"] if item["category"] == "AUTHORITY_CONFLICT" and item["source_path"] == "planning/ui-inventory/PAGE-1.yaml"]
      self.assertEqual(len(conflicts), 2)
      self.assertTrue(all(item["repairability"] == "DECISION_REQUIRED" for item in conflicts))

    def test_wave_repair_is_scoped_dry_run_and_idempotent(self) -> None:
      write_file(self.root, "planning/checklists/W01-implementation-checklist.yaml", "wave_id: W01\nitems: []\n")
      write_task(self.root, "TASK-001", "done", migrated_from="planning/checklists/W01-implementation-checklist.yaml")
      before = tree_fingerprint(self.root)
      report = build_project_status.build_status(self.root)["compatibility"]
      plan = project_compatibility.repair_plan(self.root, report)
      self.assertEqual(plan["file_scope"], ["planning/tasks/TASK-001.yml"])
      self.assertEqual(before, tree_fingerprint(self.root))
      result = project_compatibility.apply_repair(self.root, plan["plan_hash"])
      value = project_compatibility.load_yaml((self.root / plan["file_scope"][0]).read_bytes())
      self.assertEqual(value["wave_id"], "W01")
      self.assertEqual(value["status"], "done")
      self.assertEqual(value["assignment_provenance"]["rule"], "migrated_from_checklist_v1")
      self.assertEqual(result["applied"], plan["file_scope"])
      after = build_project_status.build_status(self.root)
      self.assertEqual(project_compatibility.repair_plan(self.root, after["compatibility"])["repairs"], [])

    def test_ambiguous_and_conflicting_assignments_need_decision(self) -> None:
      write_file(self.root, "planning/checklists/W01-implementation-checklist.yaml", "wave_id: W02\n")
      write_task(self.root, "TASK-001", "pending", wave_id="W02", migrated_from="planning/checklists/W01-implementation-checklist.yaml")
      report = build_project_status.build_status(self.root)["compatibility"]
      self.assertTrue(any(item["category"] == "AUTHORITY_CONFLICT" and item["repairability"] == "DECISION_REQUIRED" for item in report["diagnostics"]))
      self.assertEqual(project_compatibility.repair_plan(self.root, report)["repairs"], [])

    def test_yaml_quote_repair_preserves_text_comments_and_phase(self) -> None:
      path = self.root / "planning/lifecycle/process-state.yaml"
      original = path.read_text().replace("phase: verifying", "phase: verifying\n    resume_from: stage: continue # marker")
      path.write_text(original, encoding="utf-8")
      self.assertIsNone(project_compatibility.quoted_yaml_candidate("planning/lifecycle/process-state.yaml", path.read_bytes()))
      path.write_text(original.replace(" # marker", ""), encoding="utf-8")
      raw = path.read_bytes()
      replacement = project_compatibility.quoted_yaml_candidate("planning/lifecycle/process-state.yaml", raw)
      self.assertIsNotNone(replacement)
      value = project_compatibility.load_yaml(replacement)
      self.assertEqual(value["waves"]["W01"]["resume_from"], "stage: continue")
      self.assertEqual(value["waves"]["W01"]["phase"], "verifying")
      report = build_project_status.build_status(self.root)["compatibility"]
      plan = project_compatibility.repair_plan(self.root, report)
      self.assertNotIn("stage: continue", json.dumps(plan))
      project_compatibility.apply_repair(self.root, plan["plan_hash"])
      self.assertEqual(path.read_bytes(), replacement)

    def test_stale_repair_plan_cannot_write(self) -> None:
      write_file(self.root, "planning/checklists/W01-implementation-checklist.yaml", "wave_id: W01\n")
      write_task(self.root, "TASK-001", "pending", migrated_from="planning/checklists/W01-implementation-checklist.yaml")
      plan = project_compatibility.repair_plan(self.root, build_project_status.build_status(self.root)["compatibility"])
      write_file(self.root, "planning/checklists/W01-implementation-checklist.yaml", "wave_id: W02\n")
      before = tree_fingerprint(self.root)
      with self.assertRaises(ValueError):
        project_compatibility.apply_repair(self.root, plan["plan_hash"])
      self.assertEqual(tree_fingerprint(self.root), before)

    def test_failed_write_rolls_back_only_written_files(self) -> None:
      write_file(self.root, "planning/checklists/W01-implementation-checklist.yaml", "wave_id: W01\n")
      for task_id in ("TASK-001", "TASK-002"):
        write_task(self.root, task_id, "pending", migrated_from="planning/checklists/W01-implementation-checklist.yaml")
      plan = project_compatibility.repair_plan(self.root, build_project_status.build_status(self.root)["compatibility"])
      before = tree_fingerprint(self.root)
      actual = project_compatibility.atomic_replace
      calls = []
      def fail_second(path, raw):
        calls.append(path)
        if len(calls) == 2:
          raise OSError("fixture failure")
        actual(path, raw)
      with patch.object(project_compatibility, "atomic_replace", side_effect=fail_second):
        with self.assertRaises(ValueError):
          project_compatibility.apply_repair(self.root, plan["plan_hash"])
      self.assertEqual(tree_fingerprint(self.root), before)

    def test_agent_candidates_cannot_promote_lifecycle_status(self) -> None:
      task = self.root / "planning/tasks/TASK-001.yml"
      task.write_text(task.read_text() + "unsupported_field: fixture\n")
      staged = Path(self.temp.name) / "candidate"
      write_file(staged, "planning/tasks/TASK-001.yml", "ID: TASK-001\nspec: SPEC-001\naction: Test\nstatus: done\n")
      report = build_project_status.build_status(self.root)["compatibility"]
      self.assertEqual(project_compatibility.repair_plan(self.root, report, staged)["repairs"], [])

    def test_invalid_legacy_json_and_missing_validator_never_pass(self) -> None:
      write_file(self.root, "planning/tasks/TASK-LEGACY.json", '{"ID": "secret-marker", invalid}\n')
      report = build_project_status.build_status(self.root)["compatibility"]
      self.assertTrue(any(item["category"] == "SYNTAX_ERROR" and item["line"] == 1 for item in report["diagnostics"]))
      self.assertNotIn("secret-marker", json.dumps(report))
      with patch.object(project_compatibility, "jsonschema", None):
        self.assertEqual(build_project_status.build_status(self.root)["compatibility"]["compatibility"], "BLOCKED")

    def test_doctor_and_repair_cli_are_read_only_by_default(self) -> None:
      write_file(self.root, "planning/checklists/W01-implementation-checklist.yaml", "wave_id: W01\n")
      write_task(self.root, "TASK-001", "pending", migrated_from="planning/checklists/W01-implementation-checklist.yaml")
      before = tree_fingerprint(self.root)
      for command in ("doctor", "repair"):
        output = StringIO()
        with patch.object(sys, "argv", ["project_compatibility.py", command, "--project-root", str(self.root), "--format", "json"]):
          with redirect_stdout(output):
            exit_code = project_compatibility.main()
        self.assertIn(exit_code, (0, 1, 2))
        self.assertIsInstance(json.loads(output.getvalue()), dict)
        self.assertEqual(before, tree_fingerprint(self.root))

    def test_invalid_yaml_indentation_and_lifecycle_scalar_are_not_autorepaired(self) -> None:
      for content in (b'waves:\n W01:\n  phase: done: promoted\n', b'waves:\n  W01:\n    phase: ready\n   gates: {}\n'):
        self.assertIsNone(project_compatibility.quoted_yaml_candidate("planning/lifecycle/process-state.yaml", content))

    def test_scoped_repair_can_reach_compatible_without_promoting_mission(self) -> None:
      for directory in ("planning/evidence/manifests", "planning/target-mockups"):
        shutil.rmtree(self.root / directory)
        (self.root / directory).mkdir(parents=True)
      (self.root / "planning/findings").mkdir()
      write_file(self.root, "specs/SPEC-001.yml", "ID: SPEC-001\ntitle: Fixture\ndescription: Fixture spec\nrequirements: [REQ-001]\n")
      write_file(self.root, "planning/checklists/W01-implementation-checklist.yaml", "wave_id: W01\n")
      for task_id in ("TASK-001", "TASK-002"):
        write_task(self.root, task_id, "pending", migrated_from="planning/checklists/W01-implementation-checklist.yaml")
      report = build_project_status.build_status(self.root)["compatibility"]
      plan = project_compatibility.repair_plan(self.root, report)
      after = project_compatibility.apply_repair(self.root, plan["plan_hash"])
      self.assertEqual(after["compatibility"]["compatibility"], "COMPATIBLE")
      self.assertEqual(build_project_status.build_status(self.root)["mission"]["status"], "blocked")

    def test_reviewed_agent_candidate_and_reference_failure_rollback(self) -> None:
      write_file(self.root, "specs/SPEC-001.yml", "ID: SPEC-001\ntitle: Fixture\ndescription: Fixture spec\nrequirements: [REQ-001]\n")
      task = self.root / "planning/tasks/TASK-001.yml"
      original = task.read_bytes()
      task.write_bytes(original + b'unsupported_field: fixture\n')
      staged = Path(self.temp.name) / "candidate"
      candidate = write_file(staged, "planning/tasks/TASK-001.yml", original.decode() + "req: [REQ-999]\n")
      report = build_project_status.build_status(self.root)["compatibility"]
      plan = project_compatibility.repair_plan(self.root, report, staged)
      self.assertEqual(plan["file_scope"], ["planning/tasks/TASK-001.yml"])
      before = tree_fingerprint(self.root)
      with self.assertRaises(ValueError):
        project_compatibility.apply_repair(self.root, plan["plan_hash"], staged)
      self.assertEqual(tree_fingerprint(self.root), before)
      candidate.write_bytes(original)
      plan = project_compatibility.repair_plan(self.root, report, staged)
      project_compatibility.apply_repair(self.root, plan["plan_hash"], staged)
      self.assertEqual(task.read_bytes(), original)

    def test_verification_proof_point_reference_is_checked(self) -> None:
      path = self.root / "planning/verification-plans/VPL-001.yaml"
      path.write_text(path.read_text().replace("PP-001", "PP-999"))
      report = build_project_status.build_status(self.root)["compatibility"]
      self.assertTrue(any(item["category"] == "REFERENCE_MISSING" and item["authority"] == "test_contract_id/proof_points" for item in report["diagnostics"]))

    def test_evidence_wave_is_not_inferred_from_timeline(self) -> None:
      path = self.root / "planning/evidence/manifests/W99-evidence-manifest.yaml"
      write_file(self.root, path.relative_to(self.root).as_posix(), "manifest_id: MFT-W99\nwave_id: W99\nentries: []\n")
      report = build_project_status.build_status(self.root)["compatibility"]
      diagnostic = next(item for item in report["diagnostics"] if item["source_path"] == path.relative_to(self.root).as_posix() and item["category"] == "WAVE_ASSIGNMENT_MISSING")
      self.assertEqual(diagnostic["repairability"], "DECISION_REQUIRED")
      self.assertIsNone(diagnostic["proposed_repair_type"])

    def test_diagnostic_source_endpoint_never_serves_raw_invalid_source(self) -> None:
      import threading
      import urllib.request
      import urllib.error
      write_file(self.root, "planning/lifecycle/process-state.yaml", "waves: invalid: SECRET-HTTP-VALUE\n")
      server = serve_project_board.ProjectBoardServer(self.root, self.root / ".mxagile/board", 0)
      worker = threading.Thread(target=server.serve_forever, daemon=True)
      worker.start()
      try:
        base = f"http://127.0.0.1:{server.server_port}"
        response = urllib.request.urlopen(base + "/diagnostic-source/planning/lifecycle/process-state.yaml")
        payload = response.read().decode()
        self.assertIn("SYNTAX_ERROR", payload)
        self.assertNotIn("SECRET-HTTP-VALUE", payload)
        self.assertEqual(json.loads(payload)["diagnostics"][0]["line"], 1)
        for path in ("/diagnostic-source/.env.mendix", "/diagnostic-source/../.env.mendix"):
          with self.assertRaises(urllib.error.HTTPError) as failure:
            urllib.request.urlopen(base + path)
          self.assertEqual(failure.exception.code, 404)
      finally:
        server.shutdown()
        server.server_close()
        worker.join()

    def test_projection_is_deterministic_read_only_and_secret_free(self) -> None:
        before = tree_fingerprint(self.root)
        first, status = run_builder(self.root)
        second, _ = run_builder(self.root)
        self.assertEqual(first, second)
        self.assertEqual(before, tree_fingerprint(self.root))
        self.assertNotIn("do-not-export-this-secret", first)
        self.assertNotIn(str(self.root), first)
        self.assertEqual(status["projection"], True)
        self.assertEqual(status["authority"], "mxagile_canonical_artifacts")
        self.assertEqual(status["schema_version"], 2)
        self.assertRegex(status["source_fingerprint"], r"^sha256:[0-9a-f]{64}$")

    def test_cli_emits_the_same_json_projection(self) -> None:
        expected, _ = run_builder(self.root)
        output = StringIO()
        with patch.object(sys, "argv", [str(BUILDER), "--project-root", str(self.root)]):
            with redirect_stdout(output):
                exit_code = build_project_status.main()
        self.assertEqual(exit_code, 0)
        self.assertEqual(output.getvalue().strip(), expected)

    def test_lifecycle_delivery_decisions_and_evidence_are_explicit(self) -> None:
        _, status = run_builder(self.root)
        self.assertEqual(status["project"]["lifecycle"]["active_wave_id"], "W01")
        self.assertEqual(status["project"]["lifecycle"]["phase"], "verifying")
        self.assertEqual(status["delivery"]["waves"]["phase_counts"]["done"], 1)
        self.assertEqual(status["delivery"]["waves"]["phase_counts"]["verifying"], 1)
        self.assertEqual(status["mission"]["status"], "blocked")
        self.assertEqual(status["mission"]["blocker_count"], 1)
        self.assertEqual(status["delivery"]["task_progress"]["status_counts"]["pending"], 1)
        self.assertEqual(status["delivery"]["task_progress"]["status_counts"]["done"], 1)
        self.assertEqual(status["decisions"]["status_counts"]["PROPOSED"], 1)
        self.assertEqual(status["decisions"]["pending_affected_requirements"], ["REQ-001"])
        self.assertEqual(status["decisions"]["blocked_by_decision"]["count"], 1)
        evidence = status["verification"]["evidence"]
        self.assertEqual(evidence["recorded_counts"]["PASS"], 1)
        self.assertEqual(evidence["current_counts"]["verified"], None)
        self.assertEqual(evidence["current_counts"]["stale"], 2)
        self.assertEqual(evidence["freshness"], "partial")
        self.assertEqual(evidence["target_freshness"], "determinable")
        self.assertEqual(evidence["model_freshness"], "unknown")
        self.assertEqual(status["delivery"]["checklist_progress"]["availability"], "unavailable")
        self.assertEqual(status["findings"]["availability"], "unavailable")
        self.assertEqual(status["sources"]["availability"], "unavailable")
        self.assertEqual(status["context"]["availability"], "partial")
        self.assertEqual(status["context"]["epoch_id"], "EPOCH-007")
        self.assertEqual(status["context"]["phase"], "implementing")
        self.assertEqual(status["context"]["pressure"], "UNKNOWN")
        self.assertIsNone(status["context"]["mode"])

    def test_missing_sources_are_unavailable_not_zero(self) -> None:
        empty = Path(self.temp.name) / "empty"
        empty.mkdir()
        _, status = run_builder(empty)
        self.assertEqual(status["mission"]["availability"], "unavailable")
        self.assertEqual(status["project"]["lifecycle"]["availability"], "unavailable")
        self.assertIsNone(status["requirements"]["total"])
        self.assertIsNone(status["delivery"]["task_progress"]["total"])

    def test_terminal_lifecycle_is_done(self) -> None:
        terminal = Path(self.temp.name) / "terminal"
        write_file(terminal, "planning/lifecycle/process-state.yaml", """
            waves:
              W01:
                phase: done
                gates:
                  gate_to_refinement: {result: passed}
                  gate_to_ready: {result: passed}
        """)
        _, status = run_builder(terminal)
        self.assertEqual(status["project"]["lifecycle"]["phase"], "done")

    def test_multiple_bundle_targets_and_source_references_are_explicit(self) -> None:
        write_revision(self.root, "Portal", 9, False, "b")
        write_revision(self.root, "Portal", 10, True, "c", "app/index.html")
        write_page(self.root, "PAGE-BOARD", "Board", "REV-002", ("SEC-OVERVIEW",))
        write_page(self.root, "PAGE-PORTAL", "Portal", "REV-010", ("SEC-PORTAL",))
        write_file(self.root, "planning/checklists/W01-implementation-checklist.yaml", "items: []\n")

        _, status = run_builder(self.root)
        targets = status["project"]["active_targets"]
        self.assertEqual(targets["availability"], "available")
        self.assertEqual({target["mockup_name"] for target in targets["items"]}, {"Board", "Portal"})
        portal = next(target for target in targets["items"] if target["mockup_name"] == "Portal")
        self.assertEqual(portal["revision_id"], "REV-010")
        self.assertEqual(portal["canonical_path"], "planning/target-mockups/Portal/_history/REV-010/app/index.html")
        self.assertEqual(portal["authoritative_state"], "ACTIVE_TARGET")
        self.assertEqual(portal["source_fingerprint"], portal["bundle_hash"])
        self.assertEqual(portal["screen_ids"], ["PAGE-PORTAL"])
        self.assertEqual(portal["section_ids"], ["SEC-PORTAL"])
        self.assertTrue(portal["authority_sources"][0]["content_hash"].startswith("sha256:"))
        references = status["source_references"]["items"]
        self.assertTrue(any(ref["source_type"] == "requirement" and ref["artifact_id"] == "REQ-001" for ref in references))
        self.assertTrue(any(ref["source_type"] == "wave_state" and ref["anchor"] == "waves.W01" for ref in references))
        self.assertTrue(any(ref["source_type"] == "checklist" and ref["canonical_path"].endswith("W01-implementation-checklist.yaml") for ref in references))
        self.assertTrue(any(ref["source_type"] == "decision" and ref["artifact_id"] == "DEC-001" for ref in references))
        self.assertTrue(any(ref["source_type"] == "test_contract" and ref["artifact_id"] == "TC-001" for ref in references))
        self.assertTrue(any(ref["source_type"] == "verification_plan" and ref["artifact_id"] == "VPL-001" for ref in references))
        self.assertTrue(any(ref["source_type"] == "evidence_manifest" for ref in references))
        self.assertTrue(any(ref["source_type"] == "evidence_artifact" and ref["artifact_id"] == "EVD-1-SCREEN" for ref in references))
        self.assertTrue(any(ref["source_type"] == "parity_report" for ref in references))
        self.assertTrue(all("://" not in ref["canonical_path"] for ref in references))
        fingerprint_before = status["source_fingerprint"]
        entry_point = self.root / portal["canonical_path"]
        entry_point.write_text("<html>Changed active target</html>\n", encoding="utf-8")
        _, changed_status = run_builder(self.root)
        self.assertNotEqual(changed_status["source_fingerprint"], fingerprint_before)

    def test_single_file_uses_explicit_inventory_target_not_newest_candidate(self) -> None:
        write_file(self.root, "input-resources/ui-ux/legacy.html", "<html>Source</html>\n")
        write_file(self.root, "planning/target-mockups/Legacy.html", "<html>Accepted target</html>\n")
        write_file(self.root, "planning/target-mockups/Legacy-REV-999.html", "<html>Unselected candidate</html>\n")
        write_single_file_page(
            self.root,
            "PAGE-LEGACY",
            "input-resources/ui-ux/legacy.html",
            "planning/target-mockups/Legacy.html",
            ("SEC-LEGACY",),
        )
        _, status = run_builder(self.root)
        target = next(item for item in status["project"]["active_targets"]["items"] if item["reference_type"] == "single_file_mockup")
        self.assertEqual(target["canonical_path"], "planning/target-mockups/Legacy.html")
        self.assertEqual(target["authoritative_state"], "ACTIVE_TARGET")
        self.assertEqual(target["screen_ids"], ["PAGE-LEGACY"])
        self.assertEqual(target["section_ids"], ["SEC-LEGACY"])
        self.assertNotEqual(target["canonical_path"], "planning/target-mockups/Legacy-REV-999.html")
        self.assertEqual(serve_project_board.resolve_reference_file(self.root, status, target["canonical_path"]), self.root / target["canonical_path"])

    def test_inventory_revision_drift_is_visible_against_canonical_active_target(self) -> None:
        write_revision(self.root, "Portal", 9, False, "b")
        write_revision(self.root, "Portal", 17, True, "c")
        write_file(self.root, "planning/ui-inventory/PAGE-PORTAL.yaml", """
          page_id: PAGE-PORTAL
          mockup_name: Portal
          target_revision: REV-009
          bundle_hash: sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
        """)
        _, status = run_builder(self.root)
        target = next(item for item in status["project"]["active_targets"]["items"] if item["mockup_name"] == "Portal")
        self.assertEqual(target["revision_id"], "REV-017")
        self.assertIn("REV-017", target["canonical_path"])
        self.assertEqual(target["authoritative_state"], "ACTIVE_TARGET")
        self.assertEqual(target["inventory_drift"]["state"], "mismatch")
        self.assertEqual(target["inventory_drift"]["mismatched_screen_ids"], ["PAGE-PORTAL"])

        write_file(self.root, "planning/ui-inventory/PAGE-PORTAL.yaml", """
          page_id: PAGE-PORTAL
          mockup_name: Portal
        """)
        _, missing_identity_status = run_builder(self.root)
        target = next(item for item in missing_identity_status["project"]["active_targets"]["items"] if item["mockup_name"] == "Portal")
        self.assertEqual(target["inventory_drift"]["state"], "unknown")
        self.assertEqual(target["inventory_drift"]["unknown_screen_ids"], ["PAGE-PORTAL"])

    def test_revision_conflict_or_path_traversal_never_selects_a_file(self) -> None:
        conflict_path = write_revision(self.root, "Board", 3, True, "d")
        _, conflict_status = run_builder(self.root)
        board_target = next(item for item in conflict_status["project"]["active_targets"]["items"] if item["mockup_name"] == "Board")
        self.assertEqual(board_target["availability"], "ambiguous")
        self.assertIsNone(board_target["canonical_path"])
        self.assertEqual(board_target["authoritative_state"], "UNKNOWN")

        revision_path = self.root / "planning/target-mockups/Board/_history/REV-002/revision.yaml"
        conflict_revision = conflict_path.read_text(encoding="utf-8")
        conflict_path.write_text(conflict_revision.replace("active_target: true", "active_target: false"), encoding="utf-8")
        revision = revision_path.read_text(encoding="utf-8")
        revision_path.write_text(revision.replace("entry_point: index.html", "entry_point: ../../../../outside.html"), encoding="utf-8")
        _, traversal_status = run_builder(self.root)
        board_target = next(item for item in traversal_status["project"]["active_targets"]["items"] if item["mockup_name"] == "Board")
        self.assertEqual(board_target["availability"], "unknown")
        self.assertIsNone(board_target["canonical_path"])

        write_file(self.root, "planning/target-mockups/Board/_history/REV-004/revision.yaml", "revision_id: [invalid yaml\n")
        _, incomplete_status = run_builder(self.root)
        board_target = next(item for item in incomplete_status["project"]["active_targets"]["items"] if item["mockup_name"] == "Board")
        self.assertEqual(board_target["availability"], "ambiguous")
        self.assertIsNone(board_target["canonical_path"])

    def test_no_active_revision_does_not_choose_latest(self) -> None:
        revision_path = self.root / "planning/target-mockups/Board/_history/REV-002/revision.yaml"
        revision = revision_path.read_text(encoding="utf-8")
        revision_path.write_text(revision.replace("active_target: true", "active_target: false"), encoding="utf-8")
        _, status = run_builder(self.root)
        target = next(item for item in status["project"]["active_targets"]["items"] if item["mockup_name"] == "Board")
        self.assertEqual(target["availability"], "unknown")
        self.assertIsNone(target["canonical_path"])
        self.assertIsNone(target["revision_id"])

    def test_explicit_wave_workpackage_and_checklist_mapping(self) -> None:
        checklist = "planning/checklists/W01-implementation-checklist.yaml"
        write_file(self.root, checklist, "items: []\n")
        windows_checklist = checklist.replace("/", "\\")
        write_task(self.root, "TASK-010", "done", wave_id="W01", workpackage_id="WP-SEARCH", requirement_ids=("REQ-001",), migrated_from=windows_checklist)
        write_task(self.root, "TASK-011", "pending", wave_id="W01", workpackage_id="WP-SEARCH", migrated_from=windows_checklist)

        _, status = run_builder(self.root)
        wave = next(item for item in status["delivery"]["waves"]["items"] if item["wave_id"] == "W01")
        self.assertEqual(wave["task_progress"]["total"], 2)
        self.assertEqual(wave["task_progress"]["status_counts"]["done"], 1)
        self.assertEqual(wave["checklist_progress"]["availability"], "available")
        self.assertEqual(wave["checklist_progress"]["total"], 2)
        self.assertEqual(wave["checklist_progress"]["done"], 1)
        self.assertEqual(wave["requirement_ids"], ["REQ-001"])
        self.assertTrue(all(task["migrated_from"] == checklist for task in status["delivery"]["tasks"]["items"] if task["id"] in {"TASK-010", "TASK-011"}))
        package = next(item for item in status["delivery"]["workpackages"]["items"] if item["workpackage_id"] == "WP-SEARCH")
        self.assertEqual(package["wave_id"], "W01")
        self.assertEqual(package["task_progress"]["total"], 2)
        self.assertEqual(package["requirement_ids"], ["REQ-001"])
        self.assertEqual(status["delivery"]["workpackages"]["unmapped_task_count"], 2)

    def test_canonical_gap_finding_lifecycle_and_blocking_counts(self) -> None:
        write_finding(self.root, "FIND-BOARD-CRITICAL", "DETECTED", "CRITICAL", wave_id="W01", workpackage_id="WP-SEARCH", requirement_ids=("REQ-001",))
        write_finding(self.root, "FIND-BOARD-DECISION", "DECISION_REQUIRED", "MATERIAL", requirement_ids=("REQ-001",))
        write_finding(self.root, "FIND-BOARD-VERIFIED", "VERIFIED", "MATERIAL")

        _, status = run_builder(self.root)
        findings = status["findings"]
        self.assertEqual(findings["availability"], "available")
        self.assertEqual(findings["open"], 2)
        self.assertEqual(findings["blocking"], 2)
        self.assertEqual(findings["closed"], 1)
        self.assertEqual(findings["unknown"], 0)
        critical = next(item for item in findings["items"] if item["id"] == "FIND-BOARD-CRITICAL")
        self.assertEqual(critical["wave_id"], "W01")
        self.assertEqual(critical["workpackage_id"], "WP-SEARCH")
        self.assertTrue(any(ref["source_type"] == "finding" and ref["artifact_id"] == "FIND-BOARD-CRITICAL" for ref in status["source_references"]["items"]))

    def test_checklist_canonicalization_preserves_explicit_wave_and_workpackage(self) -> None:
        checklist = write_file(self.root, "planning/checklists/W07-implementation-checklist.yaml", """
            tasks:
              - action: Implement search filter
                spec: SPEC-001
                status: done
                workpackage_id: WP-SEARCH
        """)
        converted = canonicalize_artifacts.convert_checklist_yaml_to_tasks(checklist, self.root, 20)
        self.assertEqual(len(converted), 1)
        self.assertEqual(converted[0]["wave_id"], "W07")
        self.assertEqual(converted[0]["workpackage_id"], "WP-SEARCH")
        self.assertEqual(converted[0]["status"], "done")

    def test_local_server_serves_only_contract_authorized_files_on_loopback(self) -> None:
        _, status = run_builder(self.root)
        target = next(item for item in status["project"]["active_targets"]["items"] if item["mockup_name"] == "Board")
        asset_relative = f"{target['reference_root']}/assets/icon.svg"
        write_file(self.root, asset_relative, "<svg xmlns='http://www.w3.org/2000/svg'></svg>\n")
        self.assertEqual(serve_project_board.resolve_reference_file(self.root, status, target["canonical_path"]), self.root / target["canonical_path"])
        self.assertEqual(serve_project_board.resolve_reference_file(self.root, status, asset_relative), self.root / asset_relative)
        self.assertIsNone(serve_project_board.resolve_reference_file(self.root, status, f"{target['reference_root']}/revision.yaml"))
        self.assertIsNone(serve_project_board.resolve_reference_file(self.root, status, "requirements/REQ-001.yml"))
        self.assertIsNone(serve_project_board.resolve_reference_file(self.root, status, "../outside.html"))
        self.assertEqual(serve_project_board.resolve_source_file(self.root, status, "requirements/REQ-001.yml"), self.root / "requirements/REQ-001.yml")
        self.assertIsNone(serve_project_board.resolve_source_file(self.root, status, "planning/mission/mission-state.yaml/../secrets.txt"))

        server = serve_project_board.ProjectBoardServer(self.root, self.root / ".mxagile/board", 0)
        try:
            self.assertEqual(server.server_address[0], "127.0.0.1")
        finally:
            server.server_close()

    def test_projection_validates_against_schema(self) -> None:
        executable = shutil.which("pwsh") or shutil.which("powershell")
        if not executable:
            self.skipTest("PowerShell Test-Json is unavailable")
        raw, _ = run_builder(self.root)
        output_path = Path(self.temp.name) / "status.json"
        output_path.write_text(raw, encoding="utf-8")
        command = (
            f"if (-not (Test-Json -LiteralPath '{output_path}' -SchemaFile '{SCHEMA}')) "
            "{ exit 1 }"
        )
        import subprocess

        subprocess.run([executable, "-NoProfile", "-Command", command], check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()