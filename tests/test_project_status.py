"""Fixture tests for the deterministic project-status builder."""

from __future__ import annotations

import copy
import hashlib
import json
import shutil
import sys
import subprocess
import tempfile
import textwrap
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch
from jsonschema import Draft7Validator
from temp_cleanup import cleanup_temporary_directory

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts" / "build_project_status.py"
SCHEMA = ROOT / ".mxagile" / "schemas" / "project-status.schema.json"
sys.path.insert(0, str(ROOT / "scripts"))
import build_project_status
import build_artifact_index
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
  source_mockup = f"input-resources/ui-ux/{mockup_name}/index.html"
  write_file(root, source_mockup, f"<html>{page_id}</html>\n")
  content = f"page_id: {page_id}\nsource_mockup: {source_mockup}\nmockup_name: {mockup_name}\ntarget_revision: {revision_id}\n"
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


def make_authority_disposition(
  root: Path,
  classification: str,
  allowed_action: str,
  prohibited_actions: list[str],
  revision: int = 1,
) -> dict:
  def basis_ref(source_type: str, canonical_path: str, artifact_id: str | None = None) -> dict:
    content_hash = "sha256:" + hashlib.sha256((root / canonical_path).read_bytes()).hexdigest()
    reference = {"source_type": source_type, "canonical_path": canonical_path, "content_hash": content_hash}
    if artifact_id:
      reference["artifact_id"] = artifact_id
    return reference

  authoritative_sources = [basis_ref("requirement", "requirements/REQ-001.yml", "REQ-001")]
  evidence_refs = [
    basis_ref("parity_report", "planning/parity/PAGE-1.yaml"),
    basis_ref("evidence_manifest", "planning/evidence/manifests/W01-evidence-manifest.yaml"),
  ]
  basis = sorted(
    [(item["canonical_path"], item["content_hash"].removeprefix("sha256:"))
     for item in authoritative_sources + evidence_refs],
    key=lambda item: item[0],
  )
  fingerprint_material = "\n".join(f"{path}:{digest}" for path, digest in basis)
  unresolved = "Conflicting authoritative sources require a product decision." if classification == "AUTHORITY_CONFLICT" else None
  return {
    "status": "RECONCILED",
    "revision": revision,
    "classification": classification,
    "authoritative_sources": authoritative_sources,
    "evidence_refs": evidence_refs,
    "allowed_action": allowed_action,
    "prohibited_actions": prohibited_actions,
    "unresolved_decision": unresolved,
    "evidence_fingerprint": "sha256:" + hashlib.sha256(fingerprint_material.encode("utf-8")).hexdigest(),
    "reconciled_at": "2026-11-03T12:00:00Z",
  }


def fixture(root: Path) -> None:
    write_file(root, "mxagile-project.yaml", "name: Board Fixture\n")
    write_file(root, ".mxagile/version.yaml", "version: '1.7.0'\n")
    write_file(root, ".env.mendix", "PASSWORD=do-not-export-this-secret\n")
    write_file(root, "planning/parity/PAGE-1.yaml", """
        page_id: PAGE-1
        verified_at: '2026-10-30'
        evidence_level: static
        overall_result: PASS
        dimensions:
          visual: {result: PASS}
          content: {result: PASS}
          structure: {result: PASS}
          state: {result: PASS}
          interaction: {result: PASS}
          responsive: {result: PASS}
          role: {result: PASS}
    """)
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
      cleanup_temporary_directory(self.temp, expected_prefix="mxagile-status-")

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

    def test_compatibility_reuses_collection_source_bytes(self) -> None:
      target = (self.root / "planning/tasks/TASK-001.yml").resolve()
      original_read_bytes = Path.read_bytes
      reads = 0

      def counted_read_bytes(path: Path) -> bytes:
        nonlocal reads
        if path.resolve() == target:
          reads += 1
        return original_read_bytes(path)

      with patch.object(Path, "read_bytes", counted_read_bytes):
        status = build_project_status.build_status(self.root)
      self.assertEqual(status["delivery"]["tasks"]["items"][0]["id"], "TASK-001")
      self.assertEqual(reads, 1)

    def test_assignment_reuses_one_checklist_read_for_multiple_tasks(self) -> None:
      checklist = write_file(self.root, "planning/checklists/W01-implementation-checklist.yaml", "wave_id: W01\nitems: []\n")
      for task_id in ("TASK-001", "TASK-002"):
        write_file(self.root, f"planning/tasks/{task_id}.yml", f"""
          ID: {task_id}
          spec: SPEC-001
          action: {task_id}
          status: pending
          migrated_from: planning/checklists/W01-implementation-checklist.yaml
        """)
      target = checklist.resolve()
      original_read_bytes = Path.read_bytes
      reads = 0

      def counted_read_bytes(path: Path) -> bytes:
        nonlocal reads
        if path.resolve() == target:
          reads += 1
        return original_read_bytes(path)

      with patch.object(Path, "read_bytes", counted_read_bytes):
        status = build_project_status.build_status(self.root)
      self.assertEqual(status["delivery"]["tasks"]["items"][0]["migrated_from"], "planning/checklists/W01-implementation-checklist.yaml")
      self.assertEqual(reads, 1)

    def test_terminal_findings_are_compact_history_and_board_defaults_collapsed(self) -> None:
      write_finding(self.root, "FIND-ACTIVE", "CLASSIFIED", "MATERIAL")
      write_file(self.root, "planning/findings/FIND-OLD.yml", """
        ID: FIND-OLD
        title: Replaced finding
        gap_type: VISUAL_GAP
        severity: MATERIAL
        lifecycle_status: SUPERSEDED
        observation: Historical narrative that must not enter the compact projection.
        source_artifacts:
          - source_type: active_target
            canonical_path: planning/target-mockups/Board.html
        requirement_ids: [REQ-001]
        decision_ids: [DEC-001]
        evidence_refs: [EVD-OLD]
        resolution_references: [FIND-NEW]
        superseded_by: FIND-NEW
      """)
      write_file(self.root, "planning/findings/FIND-RESOLVED.yml", """
        ID: FIND-RESOLVED
        title: Verified finding
        gap_type: VISUAL_GAP
        severity: COSMETIC
        lifecycle_status: VERIFIED
        observation: Historical narrative.
        source_artifacts: []
        evidence_refs: [EVD-RESOLVED]
        resolution_references: [planning/evidence/doctor.json]
      """)
      status = build_project_status.build_status(self.root)
      self.assertEqual([item["id"] for item in status["findings"]["items"]], ["FIND-ACTIVE"])
      self.assertEqual(status["findings"]["open"], 1)
      self.assertEqual(status["findings"]["resolved"], 1)
      self.assertEqual(status["findings"]["superseded"], 1)
      self.assertEqual(len(status["findings"]["history"]), 2)
      old = next(item for item in status["findings"]["history"] if item["id"] == "FIND-OLD")
      self.assertEqual(old["superseded_by"], "FIND-NEW")
      self.assertEqual(old["source_artifact_paths"], ["planning/target-mockups/Board.html"])
      self.assertNotIn("title", old)
      self.assertNotIn("observation", old)
      board_js = (ROOT / ".mxagile/board/board.js").read_text(encoding="utf-8")
      board_css = (ROOT / ".mxagile/board/styles.css").read_text(encoding="utf-8")
      self.assertIn('node("details", "finding-history")', board_js)
      self.assertIn("Terminal history", board_js)
      self.assertIn(".finding-history summary", board_css)

    def test_persisted_authority_disposition_gates_later_implementation(self) -> None:
      dispositions = (
        ("FIND-REFERENCE", "REFERENCE_GAP", "REFERENCE_REFINEMENT", ["APP_IMPLEMENTATION"]),
        ("FIND-CONFLICT", "AUTHORITY_CONFLICT", "DECISION_REQUIRED", ["SEMANTIC_IMPLEMENTATION"]),
      )
      for finding_id, classification, action, prohibited in dispositions:
        record = {
          "ID": finding_id,
          "title": finding_id,
          "gap_type": "VISUAL_GAP",
          "severity": "MATERIAL",
          "lifecycle_status": "CLASSIFIED",
          "observation": "A previously reconciled visual finding.",
          "source_artifacts": [],
          "authority_disposition": make_authority_disposition(
            self.root, classification, action, prohibited,
          ),
        }
        write_file(self.root, f"planning/findings/{finding_id}.yml", json.dumps(record))

      status = build_project_status.build_status(self.root)
      projected = {item["id"]: item["authority_disposition"] for item in status["findings"]["items"]}
      reference = projected["FIND-REFERENCE"]
      self.assertEqual(reference["status"], "RESOLVED")
      self.assertTrue(reference["consumable"])
      self.assertEqual(reference["classification"], "REFERENCE_GAP")
      self.assertEqual(reference["allowed_action"], "REFERENCE_REFINEMENT")
      self.assertIn("APP_IMPLEMENTATION", reference["prohibited_actions"])
      conflict = projected["FIND-CONFLICT"]
      self.assertEqual(conflict["status"], "RESOLVED")
      self.assertTrue(conflict["consumable"])
      self.assertEqual(conflict["allowed_action"], "DECISION_REQUIRED")
      self.assertIn("SEMANTIC_IMPLEMENTATION", conflict["prohibited_actions"])

      reference_record = json.loads((self.root / "planning/findings/FIND-REFERENCE.yml").read_text(encoding="utf-8"))
      write_file(self.root, "requirements/REQ-001.yml", "ID: REQ-001\ntitle: Changed authority\ndescription: New accepted authority.\nstatus: accepted\n")
      stale_status = build_project_status.build_status(self.root)
      stale = next(item["authority_disposition"] for item in stale_status["findings"]["items"] if item["id"] == "FIND-REFERENCE")
      self.assertEqual(stale["status"], "STALE")
      self.assertFalse(stale["consumable"])
      self.assertEqual(stale["allowed_action"], "RECONCILE")

      reference_record["authority_disposition"] = make_authority_disposition(
        self.root, "CONFIRMED_IMPLEMENTATION_GAP", "PROPOSE_IMPLEMENTATION", [], revision=2,
      )
      write_file(self.root, "planning/findings/FIND-REFERENCE.yml", json.dumps(reference_record))
      reconciled_status = build_project_status.build_status(self.root)
      reconciled = next(item["authority_disposition"] for item in reconciled_status["findings"]["items"] if item["id"] == "FIND-REFERENCE")
      self.assertEqual(reconciled["status"], "RESOLVED")
      self.assertTrue(reconciled["consumable"])
      self.assertEqual(reconciled["revision"], 2)
      self.assertEqual(reconciled["classification"], "CONFIRMED_IMPLEMENTATION_GAP")

    def test_findings_markdown_is_not_lifecycle_authority(self) -> None:
      before = build_project_status.build_status(self.root)
      write_file(self.root, "FINDINGS.md", "ACTIVE FIND-999\nRESOLVED FIND-001\n" + ("historical narrative\n" * 5000))
      after = build_project_status.build_status(self.root)
      self.assertEqual(after["findings"], before["findings"])
      self.assertEqual(after["source_fingerprint"], before["source_fingerprint"])
      self.assertNotIn("FIND-999", json.dumps(after))

    def test_same_reference_path_keeps_distinct_authority_identity(self) -> None:
      shared_path = "planning/target-mockups/Board/_history/REV-002/index.html"
      write_single_file_page(self.root, "PAGE-LEGACY", shared_path, shared_path)
      status = build_project_status.build_status(self.root)
      references = [
        item for item in status["project"]["active_targets"]["items"]
        if item["canonical_path"] == shared_path
      ]
      self.assertEqual(len(references), 2)
      self.assertCountEqual(
        [item["reference_type"] for item in references],
        ["spa_bundle_entrypoint", "single_file_mockup"],
      )
      self.assertEqual(len({item["reference_id"] for item in references}), 2)
      self.assertEqual(
        {item["authority_sources"][0]["source_type"] for item in references},
        {"revision_manifest", "ui_inventory"},
      )
      board_js = (ROOT / ".mxagile/board/board.js").read_text(encoding="utf-8")
      self.assertIn("SPA BUNDLE", board_js)
      self.assertIn("SINGLE-FILE TARGET", board_js)

    def test_board_exposes_read_only_project_drift_and_loading_shell(self) -> None:
      index = (ROOT / ".mxagile/board/index.html").read_text(encoding="utf-8")
      board_js = (ROOT / ".mxagile/board/board.js").read_text(encoding="utf-8")
      self.assertIn('id="drift-state"', index)
      self.assertIn('id="drift-facts"', index)
      self.assertIn("Status wird geladen", index)
      self.assertIn("LAST RECONCILED", board_js)
      self.assertIn("CURRENT HEAD", board_js)
      self.assertIn("UNRECONCILED COMMITS", board_js)
      self.assertIn("WATERMARK GATE", board_js)

    def test_design_contract_mockup_id_is_not_bundle_mockup_name(self) -> None:
      relative = "planning/ui-inventory/PAGE-BUNDLE.yaml"
      legacy = {
        "page_id": "PAGE-BUNDLE",
        "source_mockup": "input-resources/ui-ux/bundle/index.html",
        "mockup_id": "DC-MOCKUP-001",
        "target_revision": "REV-001",
      }
      self.assertIn("required", project_compatibility.schema_errors(relative, legacy))
      canonical = {**legacy, "mockup_name": "bundle"}
      self.assertEqual(project_compatibility.schema_errors(relative, canonical), [])

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

    def test_proof_point_requirement_traceability_is_distinct_and_lossless(self) -> None:
      proof_point = {
        "id": "PP-001", "claim": "Claim", "role": "ROLE-USER", "data_state": "any",
        "required_layers": ["MODEL"],
      }
      contract = {
        "schema_version": 1, "ID": "TC-001", "title": "Contract", "status": "active",
        "requirement_ids": ["REQ-001", "REQ-002"], "proof_points": [proof_point],
      }
      relative = "planning/test-contracts/TC-001.yaml"
      self.assertEqual(project_compatibility.schema_errors(relative, contract), [])

      proof_point["traceability"] = {"requirement_ids": ["REQ-001", "REQ-002"]}
      self.assertEqual(project_compatibility.schema_errors(relative, contract), [])
      self.assertEqual(proof_point["traceability"]["requirement_ids"], ["REQ-001", "REQ-002"])

      for invalid_ids in (["REQ-001", "REQ-001"], ["REQ-1"], ["PAGE-001"]):
        proof_point["traceability"]["requirement_ids"] = invalid_ids
        self.assertIn("uniqueItems" if len(invalid_ids) == 2 and invalid_ids[0] == invalid_ids[1] else "pattern",
                      project_compatibility.schema_errors(relative, contract))

      proof_point["traceability"]["requirement_ids"] = []
      self.assertEqual(project_compatibility.schema_errors(relative, contract), [])
      contract["requirement_ids"] = ["REQ-001", "REQ-001"]
      self.assertIn("uniqueItems", project_compatibility.schema_errors(relative, contract))

    def test_doctor_checks_proof_point_requirement_references(self) -> None:
      relative = "planning/test-contracts/TC-001.yaml"
      content = """
        schema_version: 1
        ID: TC-001
        title: Contract
        status: active
        requirement_ids: [REQ-001]
        proof_points:
          - id: PP-001
            claim: Claim
            role: ROLE-USER
            data_state: any
            required_layers: [MODEL]
            traceability:
              requirement_ids: [REQ-001]
      """
      write_file(self.root, relative, content)
      report = build_project_status.build_status(self.root)["compatibility"]
      pp_reference = [item for item in report["diagnostics"]
                      if item["source_path"] == relative and item["authority"] == "proof_points[].traceability.requirement_ids"]
      self.assertEqual(pp_reference, [])

      write_file(self.root, relative, content.replace(
        "              requirement_ids: [REQ-001]", "              requirement_ids: [REQ-999]", 1))
      report = build_project_status.build_status(self.root)["compatibility"]
      pp_reference = [item for item in report["diagnostics"]
                      if item["source_path"] == relative and item["authority"] == "proof_points[].traceability.requirement_ids"]
      self.assertEqual(len(pp_reference), 1)
      self.assertEqual(pp_reference[0]["category"], "REFERENCE_MISSING")
      self.assertEqual(pp_reference[0]["repairability"], "AGENT_REPAIRABLE")

      write_file(self.root, "requirements/REQ-002.yml", "ID: REQ-002\ntitle: Invalid\ndescription: Invalid\nsource: unclassified\n")
      write_file(self.root, relative, content.replace(
        "              requirement_ids: [REQ-001]", "              requirement_ids: [REQ-002]", 1))
      report = build_project_status.build_status(self.root)["compatibility"]
      pp_reference = [item for item in report["diagnostics"]
                      if item["source_path"] == relative and item["authority"] == "proof_points[].traceability.requirement_ids"]
      self.assertEqual(len(pp_reference), 1)
      self.assertEqual(pp_reference[0]["category"], "REFERENCE_MISSING")

    def test_requirement_legacy_source_and_created_are_projected_read_only(self) -> None:
      relative = "requirements/REQ-001.yml"
      base = {"ID": "REQ-001", "title": "Legacy", "description": "Legacy requirement"}
      self.assertEqual(project_compatibility.schema_errors(relative, base), [])
      for source in ("native", "legacy", "migrated", "stakeholder", "security_review", "design_contract"):
        self.assertEqual(project_compatibility.schema_errors(relative, {**base, "source": source}), [])

      legacy = {"ID": "REQ-001", "title": "Legacy", "description": "Legacy requirement",
                "source": "design_contract_rev17", "created": "2026-10-30"}
      original = copy.deepcopy(legacy)
      projected = project_compatibility.compatibility_projection(relative, legacy)
      self.assertEqual(projected[0]["source"], "design_contract")
      self.assertEqual(projected[0]["source_ref"], "REV-17")
      self.assertEqual(projected[0]["created_at"], "2026-10-30")
      self.assertEqual(projected[1], ["requirement_created_v1", "requirement_design_contract_revision_v1"])
      self.assertEqual(projected[2], [])
      self.assertEqual(project_compatibility.schema_errors(relative, legacy), [])
      self.assertEqual(legacy, original)
      self.assertEqual(project_compatibility.compatibility_projection(relative, projected[0])[1], [])
      yaml_date = {**base, "created": project_compatibility.datetime.date(2026, 10, 30)}
      self.assertEqual(project_compatibility.compatibility_projection(relative, yaml_date)[0]["created_at"], "2026-10-30")
      matching_yaml_dates = {**yaml_date, "created_at": project_compatibility.datetime.date(2026, 10, 30)}
      self.assertEqual(project_compatibility.compatibility_projection(relative, matching_yaml_dates)[2], [])
      current_yaml_date = {**base, "created_at": project_compatibility.datetime.date(2026, 10, 30)}
      current_projection = project_compatibility.compatibility_projection(relative, current_yaml_date)
      self.assertEqual(current_projection[0]["created_at"], "2026-10-30")
      self.assertEqual(current_projection[1], ["requirement_created_at_yaml_date_v1"])

      write_file(self.root, relative, project_compatibility.yaml.safe_dump(legacy))
      _, requirements, _ = build_project_status.read_collection(self.root, "requirements", "*.yml", "ID", {}, [])
      self.assertEqual(requirements[0]["source"], "design_contract")
      self.assertEqual(requirements[0]["source_ref"], "REV-17")
      report = build_project_status.build_status(self.root)["compatibility"]
      self.assertTrue(any(item["source_path"] == relative and item["repairability"] == "SAFE_DETERMINISTIC"
              for item in report["diagnostics"]))

      conflict = {**legacy, "source_ref": "REV-18", "created_at": "2026-10-29"}
      self.assertEqual(set(project_compatibility.compatibility_projection(relative, conflict)[2]),
                       {"created/created_at", "source/source_ref"})
      unknown = {**legacy, "source": "unclassified"}
      self.assertNotEqual(project_compatibility.schema_errors(relative, unknown), [])

    def test_evidence_manifest_projection_preserves_stale_state_and_capture_provenance(self) -> None:
      relative = "planning/evidence/manifests/W01-evidence-manifest.yaml"
      entry = {
        "entry_id": "EVD-1", "scenario_id": "SCN-1", "screen_id": "PAGE-1",
        "role": "ROLE-USER", "data_state": "populated", "parity_result": "STALE",
        "actual_evidence": [{"artifact_id": "EVD-1-SCREEN", "type": "screenshot",
                              "path": "planning/evidence/screenshots/actual.png",
                              "capture_id": "CAP-001", "provenance": "original-capture"}],
      }
      legacy = {"manifest_id": "MFT-W01", "wave_id": "W01", "created": "2026-10-30",
                "scenarios": [entry]}
      projected, rules, conflicts = project_compatibility.compatibility_projection(relative, legacy)
      self.assertEqual(conflicts, [])
      self.assertCountEqual(rules, ["evidence_manifest_created_v1", "evidence_manifest_scenarios_v1"])
      self.assertEqual(project_compatibility.schema_errors(relative, legacy), [])
      self.assertEqual(projected["entries"][0]["parity_result"], "STALE")
      artifact = projected["entries"][0]["actual_evidence"][0]
      self.assertEqual(artifact["capture_id"], "CAP-001")
      self.assertEqual(artifact["provenance"], "original-capture")
      self.assertIn("scenarios", legacy)
      self.assertEqual(project_compatibility.compatibility_projection(relative, projected)[1], [])

      write_file(self.root, relative, project_compatibility.yaml.safe_dump(legacy))
      _, records, _ = build_project_status.read_collection(
        self.root, "planning/evidence/manifests", "*-evidence-manifest.yaml", "", {}, [])
      self.assertEqual(records[0]["entries"][0]["parity_result"], "STALE")

      mixed = {**legacy, "entries": [{"entry_id": "different"}]}
      self.assertEqual(project_compatibility.compatibility_projection(relative, mixed)[2], ["scenarios/entries"])

      missing_wave = {key: value for key, value in legacy.items() if key != "wave_id"}
      self.assertEqual(project_compatibility.projected_for_validation(relative, missing_wave), missing_wave)
      self.assertIn("required", project_compatibility.schema_errors(relative, missing_wave))
      write_file(self.root, relative, project_compatibility.yaml.safe_dump(missing_wave))
      diagnostics = build_project_status.build_status(self.root)["compatibility"]["diagnostics"]
      missing_wave_diagnostics = [item for item in diagnostics if item["source_path"] == relative]
      self.assertTrue(any(item["category"] == "SCHEMA_ERROR" for item in missing_wave_diagnostics))
      self.assertTrue(any(item["category"] == "WAVE_ASSIGNMENT_MISSING"
                          and item["repairability"] == "DECISION_REQUIRED" for item in missing_wave_diagnostics))
      self.assertFalse(any(item["category"] == "LEGACY_VARIANT" for item in missing_wave_diagnostics))

    def test_non_tc_analysis_and_standalone_interactions_are_not_projected_as_artifacts(self) -> None:
      impact_path = "planning/test-contracts/ANL-014-verification-impact.yaml"
      interaction_path = "planning/ui-inventory/interaction-states-rev005.yaml"
      legacy_page_interaction_path = "planning/ui-inventory/PAGE-INTERACTION-STATES-REV5.yaml"
      metadata_interaction_path = "planning/ui-inventory/interaction-metadata-rev9.yaml"
      legacy_page_interaction_path = "planning/ui-inventory/PAGE-INTERACTION-STATES-REV5.yaml"
      metadata_interaction_path = "planning/ui-inventory/interaction-metadata-rev9.yaml"
      write_file(self.root, impact_path, """
        analysis_id: IMPACT-014
        revision_id: REV-014
        affected_requirements: [REQ-001]
      """)
      write_file(self.root, interaction_path, """
        revision_id: REV-005
        states: []
      """)
      write_file(self.root, legacy_page_interaction_path, """
        page_id: PAGE-INTERACTION-STATES-REV5
        source_mockup: input-resources/ui-ux/legacy.html
        mockup_id: legacy
        target_revision: REV-005
        interaction_states:
          - state_id: STATE-001
            data_effect: null
            navigation_effect: null
      """)
      write_file(self.root, metadata_interaction_path, """
        metadata:
          revision: REV-009
        interactions: []
      """)
      write_file(self.root, legacy_page_interaction_path, """
        page_id: PAGE-INTERACTION-STATES-REV5
        source_mockup: input-resources/ui-ux/legacy.html
        mockup_id: legacy
        target_revision: REV-005
        interaction_states:
          - state_id: STATE-001
            data_effect: null
            navigation_effect: null
      """)
      write_file(self.root, metadata_interaction_path, """
        metadata:
          revision: REV-009
        interactions: []
      """)

      status = build_project_status.build_status(self.root)
      tc_paths = {item["canonical_path"] for item in status["verification"]["test_contracts"]["items"]}
      self.assertNotIn(impact_path, tc_paths)
      self.assertFalse(any(item.get("canonical_path") == interaction_path
                           for item in status["project"]["active_targets"]["items"]))
      diagnostics = {item["source_path"]: item for item in status["compatibility"]["diagnostics"]
                     if item["source_path"] in (impact_path, interaction_path)}
      self.assertEqual(diagnostics[impact_path]["category"], "UNSUPPORTED_VARIANT")
      self.assertEqual(diagnostics[interaction_path]["category"], "UNSUPPORTED_VARIANT")
      self.assertEqual(diagnostics[impact_path]["repairability"], "UNSUPPORTED")
      self.assertEqual(diagnostics[interaction_path]["repairability"], "UNSUPPORTED")
      self.assertEqual(diagnostics[impact_path]["artifact_type"], "unknown")
      self.assertEqual(diagnostics[interaction_path]["artifact_type"], "unknown")
      standalone_paths = (legacy_page_interaction_path, metadata_interaction_path)
      for standalone_path in standalone_paths:
        standalone_diagnostics = [item for item in status["compatibility"]["diagnostics"] if item["source_path"] == standalone_path]
        self.assertFalse(any(item["blocking"] for item in standalone_diagnostics), standalone_path)
        self.assertFalse(any(item["category"] in ("ID_MISMATCH", "SCHEMA_ERROR") for item in standalone_diagnostics), standalone_path)
        self.assertFalse(any(item.get("canonical_path") == standalone_path for item in status["project"]["active_targets"]["items"]))
      for standalone_path in (legacy_page_interaction_path, metadata_interaction_path):
        standalone_diagnostics = [item for item in status["compatibility"]["diagnostics"] if item["source_path"] == standalone_path]
        self.assertFalse(any(item["blocking"] for item in standalone_diagnostics), standalone_path)
        self.assertFalse(any(item["category"] in ("ID_MISMATCH", "SCHEMA_ERROR") for item in standalone_diagnostics), standalone_path)
        self.assertFalse(any(item.get("canonical_path") == standalone_path for item in status["project"]["active_targets"]["items"]))
      with redirect_stdout(StringIO()):
        indexed = build_artifact_index.find_artifacts(self.root)
      self.assertNotIn("IMPACT-014", indexed["test_contract"])
      self.assertNotIn("interaction-states-rev005", indexed["page"])

    def test_legacy_story_sources_do_not_duplicate_canonical_requirement_status(self) -> None:
      write_file(self.root, "planning/stories/REQ-001-legacy.md", "# Historical story\n")
      status = build_project_status.build_status(self.root)
      self.assertEqual([item["id"] for item in status["requirements"]["items"]], ["REQ-001"])
      self.assertEqual(status["compatibility"]["coverage"]["requirement"]["recognized"], 1)
      self.assertFalse(any(item["source_path"] == "planning/stories/REQ-001-legacy.md"
                           for item in status["compatibility"]["diagnostics"]))

    def test_process_state_rejects_fields_owned_by_other_authorities(self) -> None:
      relative = "planning/lifecycle/process-state.yaml"
      for field in ("runtime_verification", "feature_scope", "terminal_state"):
        state = {"waves": {}, field: "legacy"}
        self.assertIn("additionalProperties", project_compatibility.schema_errors(relative, state))
        issues = project_compatibility.schema_diagnostics(relative, state)
        self.assertTrue(any(item[1] == "DECISION_REQUIRED" and field in item[0] for item in issues))
      valid = {"waves": {"W01": {"phase": "done", "gates": {
        "gate_to_refinement": {"result": "passed"}, "gate_to_ready": {"result": "passed"}}}}}
      self.assertEqual(project_compatibility.schema_errors(relative, valid), [])
      unknown = {"waves": {}, "unclassified_audit": "preserve"}
      self.assertIn("additionalProperties", project_compatibility.schema_errors(relative, unknown))
      self.assertTrue(any(issue[1] == "AGENT_REPAIRABLE"
                          for issue in project_compatibility.schema_diagnostics(relative, unknown)))

    def test_ui_inventory_producer_fields_and_legacy_identifiers(self) -> None:
      relative = "planning/ui-inventory/PAGE-001.yaml"
      template = project_compatibility.load_yaml(
        (ROOT / ".mxagile" / "templates" / "generic" / "ui-inventory" / "template.yaml").read_text(encoding="utf-8"))
      self.assertEqual(project_compatibility.schema_errors(relative, template), [])
      producer_template = copy.deepcopy(template)
      producer_template.pop("navigation")
      write_file(self.root, producer_template["source_mockup"], "<html>Producer fixture</html>\n")
      write_file(self.root, relative, project_compatibility.yaml.safe_dump(producer_template, sort_keys=False))
      producer_diagnostics = [item for item in build_project_status.build_status(self.root)["compatibility"]["diagnostics"]
                              if item["source_path"] == relative and item["blocking"]]
      self.assertEqual(producer_diagnostics, [])

      legacy = copy.deepcopy(template)
      legacy["sections"][0]["section_id"] = legacy["sections"][0].pop("id")
      legacy["navigation"][0]["target"] = legacy["navigation"][0].pop("leads_to_page")
      projected, rules, conflicts = project_compatibility.compatibility_projection(relative, legacy)
      self.assertEqual(conflicts, [])
      self.assertCountEqual(rules, ["page_section_id_v1", "page_navigation_target_v1"])
      self.assertEqual(project_compatibility.schema_errors(relative, legacy), [])
      self.assertEqual(projected["sections"][0]["id"], "SEC-001")
      self.assertEqual(projected["navigation"][0]["leads_to_page"], "[Page name or PAGE-NNN]")
      self.assertIn("section_id", legacy["sections"][0])
      self.assertEqual(project_compatibility.compatibility_projection(relative, projected)[1], [])

      unbound_navigation = copy.deepcopy(template)
      navigation = unbound_navigation["navigation"][0]
      navigation.pop("action_id", None)
      navigation["target"] = navigation.pop("leads_to_page")
      unprojected, rules, conflicts = project_compatibility.compatibility_projection(relative, unbound_navigation)
      self.assertEqual(conflicts, [])
      self.assertNotIn("page_navigation_target_v1", rules)
      self.assertIn("target", unprojected["navigation"][0])
      self.assertIn("additionalProperties", project_compatibility.schema_errors(relative, unbound_navigation))

      unknown = {**template, "unclassified_property": "preserve-and-diagnose"}
      self.assertIn("additionalProperties", project_compatibility.schema_errors(relative, unknown))
      old_authority = {"page": "PAGE-001", "source": "input-resources/ui-ux/login.html"}
      self.assertTrue(any(issue[1] == "DECISION_REQUIRED"
                          for issue in project_compatibility.schema_diagnostics(relative, old_authority)))

    def test_ui_inventory_navigation_evidence_and_revision_references(self) -> None:
      write_file(self.root, "input-resources/ui-ux/page-one.html", "<html>Page One</html>\n")
      write_file(self.root, "planning/ui-inventory/PAGE-1.yaml", """
        page_id: PAGE-1
        source_mockup: input-resources/ui-ux/page-one.html
        page_name: Page One
        navigation:
          - action_id: ACT-001
            leads_to_page: PAGE-2
          - action_id: ACT-002
            leads_to_page: PAGE-404
      """)
      write_file(self.root, "planning/ui-inventory/PAGE-2.yaml", """
        page_id: PAGE-2
        source_mockup: input-resources/ui-ux/missing-page.html
        page_name: Page Two
        mockup_name: MissingBundle
        target_revision: REV-999
      """)
      manifest_path = self.root / "planning/evidence/manifests/W01-evidence-manifest.yaml"
      manifest = project_compatibility.load_yaml(manifest_path.read_text(encoding="utf-8"))
      manifest["entries"][0]["screen_id"] = "PAGE-404"
      manifest_path.write_text(project_compatibility.yaml.safe_dump(manifest), encoding="utf-8")

      diagnostics = build_project_status.build_status(self.root)["compatibility"]["diagnostics"]
      missing_refs = {(item["authority"], item["category"]) for item in diagnostics
                      if item["category"] == "REFERENCE_MISSING"}
      self.assertIn(("navigation[].leads_to_page", "REFERENCE_MISSING"), missing_refs)
      self.assertIn(("entries[].screen_id", "REFERENCE_MISSING"), missing_refs)
      self.assertIn(("mockup_name/target_revision", "REFERENCE_MISSING"), missing_refs)
      self.assertIn(("source_mockup", "REFERENCE_MISSING"), missing_refs)

    def test_page_logical_identity_is_independent_of_filename(self) -> None:
      write_file(self.root, "input-resources/ui-ux/customer.html", "<html>Customer</html>\n")
      write_file(self.root, "input-resources/ui-ux/overview.html", "<html>Overview</html>\n")
      write_file(self.root, "planning/ui-inventory/Customer_NewEdit.yaml", """
        page_id: PAGE-CUSTOMER-EDIT
        page_name: Customer_NewEdit
        source_mockup: input-resources/ui-ux/customer.html
      """)
      write_file(self.root, "planning/ui-inventory/PAGE-OVERVIEW.yaml", """
        page_id: PAGE-OVERVIEW
        page_name: Customer_Overview
        source_mockup: input-resources/ui-ux/overview.html
        navigation:
          - action_id: ACT-CUSTOMER-OPEN
            leads_to_page: PAGE-CUSTOMER-EDIT
      """)

      status = build_project_status.build_status(self.root)
      diagnostics = status["compatibility"]["diagnostics"]
      self.assertFalse(any(item["category"] == "REFERENCE_MISSING"
                           and item["authority"] == "navigation[].leads_to_page" for item in diagnostics))
      self.assertFalse(any(item["category"] == "DUPLICATE_ID" for item in diagnostics))
      self.assertTrue(any(item["category"] == "LEGACY_VARIANT" and not item["blocking"]
                          and item["source_path"] == "planning/ui-inventory/Customer_NewEdit.yaml"
                          for item in diagnostics))
      target = next(item for item in status["project"]["active_targets"]["items"]
                    if "PAGE-CUSTOMER-EDIT" in item["screen_ids"])
      self.assertEqual(target["page_bindings"], [
          {"page_id": "PAGE-CUSTOMER-EDIT", "mendix_page_name": "Customer_NewEdit"}
      ])
      with redirect_stdout(StringIO()):
        indexed = build_artifact_index.find_artifacts(self.root)
      self.assertEqual(indexed["page"]["PAGE-CUSTOMER-EDIT"]["path"],
                       "planning/ui-inventory/Customer_NewEdit.yaml")
      self.assertEqual(indexed["page"]["PAGE-CUSTOMER-EDIT"]["mendix_page_name"], "Customer_NewEdit")

      requirement_path = self.root / "requirements/REQ-001.yml"
      requirement = project_compatibility.load_yaml(requirement_path.read_bytes())
      requirement["screens"] = ["PAGE-CUSTOMER-EDIT"]
      requirement_path.write_text(project_compatibility.yaml.safe_dump(requirement, sort_keys=False), encoding="utf-8")
      manifest_path = self.root / "planning/evidence/manifests/W01-evidence-manifest.yaml"
      manifest = project_compatibility.load_yaml(manifest_path.read_bytes())
      for entry in manifest["entries"]:
        entry["screen_id"] = "PAGE-CUSTOMER-EDIT"
      manifest_path.write_text(project_compatibility.yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")

      with redirect_stdout(StringIO()):
        before_graph = build_artifact_index.build_graph(build_artifact_index.find_artifacts(self.root))
      requirement_edge = {"from": "REQ-001", "to": "PAGE-CUSTOMER-EDIT", "type": "APPLIES_TO",
                          "provenance": {"type": "DECLARED", "source": "requirement.screens[]"}}
      self.assertIn(requirement_edge, before_graph["edges"])

      page_path = self.root / "planning/ui-inventory/Customer_NewEdit.yaml"
      page = project_compatibility.load_yaml(page_path.read_bytes())
      page["page_name"] = "Customer_Edit"
      page_path.write_text(project_compatibility.yaml.safe_dump(page, sort_keys=False), encoding="utf-8")
      renamed_status = build_project_status.build_status(self.root)
      renamed_diagnostics = renamed_status["compatibility"]["diagnostics"]
      self.assertFalse(any(item["category"] == "REFERENCE_MISSING"
                           and item["authority"] == "entries[].screen_id" for item in renamed_diagnostics))
      renamed_target = next(item for item in renamed_status["project"]["active_targets"]["items"]
                            if "PAGE-CUSTOMER-EDIT" in item["screen_ids"])
      self.assertEqual(renamed_target["page_bindings"], [
          {"page_id": "PAGE-CUSTOMER-EDIT", "mendix_page_name": "Customer_Edit"}
      ])
      with redirect_stdout(StringIO()):
        after_index = build_artifact_index.find_artifacts(self.root)
        after_graph = build_artifact_index.build_graph(after_index)
      self.assertEqual(after_index["page"]["PAGE-CUSTOMER-EDIT"]["id"], "PAGE-CUSTOMER-EDIT")
      self.assertIn(requirement_edge, after_graph["edges"])

    def test_duplicate_page_logical_identity_is_ambiguous(self) -> None:
      write_file(self.root, "input-resources/ui-ux/page-one.html", "<html>Page One</html>\n")
      for filename, page_name in (("Customer_NewEdit", "Customer_NewEdit"), ("Customer_Edit", "Customer_Edit")):
        write_file(self.root, f"planning/ui-inventory/{filename}.yaml", f"""
          page_id: PAGE-CUSTOMER-EDIT
          page_name: {page_name}
          source_mockup: input-resources/ui-ux/page-one.html
        """)

      diagnostics = build_project_status.build_status(self.root)["compatibility"]["diagnostics"]
      conflicts = [item for item in diagnostics if item["category"] == "DUPLICATE_ID"
                   and item["authority"] == "page_id"]
      self.assertEqual(len(conflicts), 2)
      self.assertTrue(all(item["blocking"] for item in conflicts))
      with redirect_stdout(StringIO()):
        with self.assertRaisesRegex(ValueError, "Duplicate Page logical identity"):
          build_artifact_index.find_artifacts(self.root)

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
      relative = "planning/tasks/TASK-001.yml"
      task = {"ID": "TASK-001", "spec": "SPEC-001", "action": "Inspect",
              "inspect": {"entity": "Module.Entity"}}
      self.assertEqual(project_compatibility.schema_errors(relative, task), [])
      write_file(self.root, relative, "ID: TASK-001\nspec: SPEC-001\naction: Inspect\ninspect:\n  entity: Module.Entity\n")
      diagnostics = build_project_status.build_status(self.root)["compatibility"]["diagnostics"]
      self.assertTrue(any(item["category"] == "EXPECTATION_MISSING" and item["repairability"] == "DECISION_REQUIRED"
                          for item in diagnostics))
      self.assertTrue(any(item["proposed_repair_type"] == "TASK_INSPECT_TYPED_TARGET_V1"
                          and item["repairability"] == "SAFE_DETERMINISTIC" for item in diagnostics))
      canonical = {"ID": "TASK-001", "spec": "SPEC-001", "action": "Inspect",
                   "inspect": {"type": "entity", "target": "Module.Entity", "expect": "Entity has an access rule."}}
      self.assertEqual(project_compatibility.schema_errors(relative, canonical), [])
      unsupported = copy.deepcopy(canonical)
      unsupported["inspect"]["unclassified"] = "preserve"
      issues = project_compatibility.schema_diagnostics("planning/tasks/TASK-001.yml", unsupported)
      self.assertTrue(any(item[1] == "DECISION_REQUIRED" for item in issues))

    def test_typed_task_inspect_supports_evidence_types_and_one_target(self) -> None:
      relative = "planning/tasks/TASK-001.yml"
      for target_type in ("entity", "microflow", "association", "rule", "snippet", "page"):
        task = {"ID": "TASK-001", "spec": "SPEC-001", "action": "Inspect",
                "inspect": {"type": target_type, "target": "CAP_Core.PlanYear_Center", "expect": "Exists."}}
        self.assertEqual(project_compatibility.schema_errors(relative, task), [], target_type)

      task["inspect"]["entity"] = "Module.Other"
      self.assertIn("additionalProperties", project_compatibility.schema_errors(relative, task))
      legacy_multiple = {"ID": "TASK-001", "spec": "SPEC-001", "action": "Inspect",
                         "inspect": {"entity": "Module.Entity", "microflow": "Module.Flow", "expect": "Exists."}}
      projected, _, conflicts = project_compatibility.compatibility_projection(relative, legacy_multiple)
      self.assertEqual(projected, legacy_multiple)
      self.assertTrue(conflicts)
      self.assertTrue(project_compatibility.schema_errors(relative, legacy_multiple))

      legacy_empty_strings = {"ID": "TASK-001", "spec": "SPEC-001", "action": "Inspect",
              "inspect": {"microflow": "", "expect": ""}}
      self.assertEqual(project_compatibility.schema_errors(relative, legacy_empty_strings), [])
      projected, rules, conflicts = project_compatibility.compatibility_projection(relative, legacy_empty_strings)
      self.assertEqual(conflicts, [])
      self.assertEqual(rules, ["task_inspect_typed_target_v1"])
      self.assertEqual(projected["inspect"], {"type": "microflow", "target": "", "expect": ""})
      write_file(self.root, relative, "ID: TASK-001\nspec: SPEC-001\naction: Inspect\ninspect:\n  microflow: Module.Flow\n  expect: '   '\n")
      blank_expectation_task = project_compatibility.load_yaml((self.root / relative).read_bytes())
      self.assertEqual(project_compatibility.schema_errors(relative, blank_expectation_task), [])
      diagnostics = build_project_status.build_status(self.root)["compatibility"]["diagnostics"]
      self.assertTrue(any(item["category"] == "EXPECTATION_MISSING" and item["source_path"] == relative
              and item["repairability"] == "DECISION_REQUIRED" for item in diagnostics))

    def test_task_inspect_legacy_migration_preserves_structured_targets_and_bytes(self) -> None:
      target_types = ("entity", "microflow", "association", "rule", "snippet", "page")
      for index, target_type in enumerate(target_types, start=1):
        task_id = f"TASK-{index:03d}"
        target = f"CAP_Core.Target{index}"
        write_file(self.root, f"planning/tasks/{task_id}.yml",
                   f"ID: {task_id}\nspec: SPEC-001\naction: Inspect\nstatus: pending\ninspect:\n  {target_type}: '{target}' # retain target comment\n  expect: \"Exact expectation {index}.\"\n")
      report = build_project_status.build_status(self.root)["compatibility"]
      migrations = [item for item in report["diagnostics"]
                    if item["proposed_repair_type"] == "TASK_INSPECT_TYPED_TARGET_V1"]
      self.assertEqual(len(migrations), len(target_types))
      plan = project_compatibility.repair_plan(self.root, report)
      self.assertEqual(len(plan["repairs"]), len(target_types))
      result = project_compatibility.apply_repair(self.root, plan["plan_hash"])
      self.assertEqual(len(result["applied"]), len(target_types))
      for index, target_type in enumerate(target_types, start=1):
        task_id = f"TASK-{index:03d}"
        path = self.root / f"planning/tasks/{task_id}.yml"
        migrated = project_compatibility.load_yaml(path.read_bytes())
        self.assertEqual(migrated["inspect"], {
          "type": target_type, "target": f"CAP_Core.Target{index}", "expect": f"Exact expectation {index}."
        })
        self.assertIn("# retain target comment", path.read_text(encoding="utf-8"))
        self.assertEqual(project_compatibility.schema_errors(path.relative_to(self.root).as_posix(), migrated), [])

    def test_missing_inspect_expectation_is_not_passed_or_invented(self) -> None:
      write_file(self.root, "planning/tasks/TASK-071.yml", "ID: TASK-071\nspec: SPEC-001\naction: Inspect snippet\ndetail: prose that is not an expectation\ninspect:\n  snippet: CAP_Core.Snippet\n")
      report = build_project_status.build_status(self.root)["compatibility"]
      diagnostic = next(item for item in report["diagnostics"]
                        if item["source_path"] == "planning/tasks/TASK-071.yml" and item["category"] == "EXPECTATION_MISSING")
      self.assertTrue(diagnostic["blocking"])
      self.assertEqual(diagnostic["repairability"], "DECISION_REQUIRED")
      self.assertNotIn("PASS", diagnostic["message"])
      plan = project_compatibility.repair_plan(self.root, report)
      self.assertEqual(len(plan["repairs"]), 1)
      project_compatibility.apply_repair(self.root, plan["plan_hash"])
      migrated = project_compatibility.load_yaml((self.root / "planning/tasks/TASK-071.yml").read_bytes())
      self.assertEqual(migrated["inspect"], {"type": "snippet", "target": "CAP_Core.Snippet"})
      self.assertEqual(migrated["detail"], "prose that is not an expectation")
      after = build_project_status.build_status(self.root)["compatibility"]["diagnostics"]
      self.assertTrue(any(item["category"] == "EXPECTATION_MISSING" and item["source_path"] == "planning/tasks/TASK-071.yml" for item in after))
      self.assertFalse(any(item["category"] == "SCHEMA_ERROR" and item["source_path"] == "planning/tasks/TASK-071.yml" for item in after))
      self.assertEqual(project_compatibility.repair_plan(self.root, build_project_status.build_status(self.root)["compatibility"])["repairs"], [])

    def test_acceptance_and_maintainer_keep_inspect_authority(self) -> None:
      acceptance = (ROOT / ".mxagile/agents/acceptance-agent.md").read_text(encoding="utf-8")
      maintainer = (ROOT / ".mxagile/agents/maintainer.md").read_text(encoding="utf-8")
      for target_type in ("entity", "microflow", "association", "rule", "snippet", "page"):
        self.assertIn(target_type, acceptance)
      self.assertIn("mxcli describe <type> <target>", acceptance)
      self.assertIn("NOT_VERIFIED", acceptance)
      self.assertIn("TASK_INSPECT_TYPED_TARGET_V1", maintainer)
      self.assertIn("EXPECTATION_MISSING", maintainer)
      self.assertIn("generate `expect` from `detail`", maintainer)

    def test_board_summarizes_inspect_migrations_and_keeps_details_collapsed(self) -> None:
      board_js = (ROOT / ".mxagile/board/board.js").read_text(encoding="utf-8")
      self.assertIn("tasks require task-inspect compatibility migration", board_js)
      self.assertIn('item.proposed_repair_type === "TASK_INSPECT_TYPED_TARGET_V1"', board_js)
      self.assertIn("panel.open = false", board_js)
      self.assertIn("for (const item of report.diagnostics)", board_js)

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

    def test_assignment_rejects_non_mapping_checklists(self) -> None:
      relative = "planning/checklists/W01-implementation-checklist.yaml"
      task = {"migrated_from": relative}
      for source in ("[]\n", "null\n", "items: [\n"):
        with self.subTest(source=source):
          write_file(self.root, relative, source)
          self.assertEqual(project_compatibility.assignment(self.root, task, {"W01"}),
                           ("ambiguous", None, relative))

    def test_compatibility_reuses_collected_checklist_bytes(self) -> None:
      from unittest.mock import patch
      original_read = Path.read_text

      def read_without_checklist_repeat(path, *args, **kwargs):
        if path.parent == self.root / "planning/checklists":
          self.fail("Collected checklist was read again during compatibility projection")
        return original_read(path, *args, **kwargs)

      with patch.object(Path, "read_text", read_without_checklist_repeat):
        status = build_project_status.build_status(self.root)
      self.assertEqual(status["schema_version"], 2)

    def test_scoped_repair_can_reach_compatible_without_promoting_mission(self) -> None:
      for directory in ("planning/evidence/manifests", "planning/target-mockups"):
        shutil.rmtree(self.root / directory)
        (self.root / directory).mkdir(parents=True)
      shutil.rmtree(self.root / "planning/parity")
      (self.root / "planning/parity").mkdir(parents=True)
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

    def test_repair_plan_keeps_same_file_reference_diagnostic_deferred(self) -> None:
      write_file(self.root, "planning/checklists/W01-implementation-checklist.yaml", "wave_id: W01\nitems: []\n")
      task_path = "planning/tasks/TASK-001.yml"
      write_file(self.root, task_path, """
        ID: TASK-001
        spec: SPEC-999
        action: Reconciled task
        status: pending
        migrated_from: planning/checklists/W01-implementation-checklist.yaml
      """)
      report = build_project_status.build_status(self.root)["compatibility"]
      wave_diagnostic = next(item for item in report["diagnostics"]
                             if item["source_path"] == task_path and item["category"] == "WAVE_ASSIGNMENT_MISSING")
      reference_diagnostic = next(item for item in report["diagnostics"]
                                  if item["source_path"] == task_path and item["category"] == "REFERENCE_MISSING")
      unsupported_diagnostic = {
        "diagnostic_id": "DX-UNSUPPORTED-COLOCATED",
        "source_path": task_path,
        "category": "UNSUPPORTED_VARIANT",
        "severity": "WARNING",
        "repairability": "UNSUPPORTED",
        "proposed_repair_type": None,
      }
      report["diagnostics"].append(unsupported_diagnostic)
      plan = project_compatibility.repair_plan(self.root, report)
      self.assertEqual(plan["file_scope"], [task_path])
      self.assertIn(wave_diagnostic["diagnostic_id"], plan["repairs"][0]["diagnostic_ids"])
      self.assertIn(reference_diagnostic["diagnostic_id"], plan["deferred_diagnostic_ids"])
      self.assertNotIn(unsupported_diagnostic["diagnostic_id"], plan["repairs"][0]["diagnostic_ids"])
      self.assertIn(unsupported_diagnostic, report["diagnostics"])

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
        write_file(self.root, "input-resources/ui-ux/portal.html", "<html>Portal source</html>\n")
        write_file(self.root, "planning/ui-inventory/PAGE-PORTAL.yaml", """
          page_id: PAGE-PORTAL
          source_mockup: input-resources/ui-ux/portal.html
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
        self.assertTrue(any(item["category"] == "STALE" and item["source_path"] == "planning/ui-inventory/PAGE-PORTAL.yaml"
                for item in status["compatibility"]["diagnostics"]))

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


PROCESS_STATE_SCHEMA = ROOT / ".mxagile" / "schemas" / "process-state.schema.json"
VALID_CHANGE_SET = {
    "schema_version": 1, "change_set_id": "CS-FIXTURE-OK", "mission_id": "MISSION-FIXTURE",
    "parent_commits": ["a" * 40],
    "paths": [{"path": "planning/tasks/TASK-001.yml", "status": "A", "before_blob": None, "after_blob": "b" * 40}],
    "reconciliation": {"status": "COMPLETE", "outcome": "NO_IMPACT", "project_fingerprint": "sha256:" + "0" * 64, "references": []},
}


def wave_block(phase: str, **gates: dict) -> dict:
    block = {"phase": phase, "gates": {"gate_to_refinement": {"result": "passed"}, "gate_to_ready": {"result": "passed"}}}
    block["gates"].update(gates)
    return block


class LifecycleClarityTests(unittest.TestCase):
    """001-board-redesign CS-0 (OD-3): optional gate schema and informative lifecycle diagnostics."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="mxagile-status-")
        self.root = Path(self.temp.name) / "fixture"
        self.root.mkdir()
        fixture(self.root)
        self.validator = Draft7Validator(json.loads(PROCESS_STATE_SCHEMA.read_text(encoding="utf-8-sig")))

    def tearDown(self) -> None:
        cleanup_temporary_directory(self.temp, expected_prefix="mxagile-status-")

    def errors(self, waves: dict) -> list[str]:
        return [error.message for error in self.validator.iter_errors({"waves": waves})]

    def doctor(self) -> dict:
        return build_project_status.build_status(self.root)["compatibility"]

    def diagnostics(self, category: str) -> list[dict]:
        return [item for item in self.doctor()["diagnostics"] if item["category"] == category]

    # ------------------------------------------------------------------ schema (R4)
    def test_existing_process_state_without_new_gates_stays_valid(self) -> None:
        legacy = {"W1a": {"phase": "done", "resume_from": "LEGACY COMPLETE 2026-10-09",
                          "gates": {"gate_to_refinement": {"result": "not_recorded", "note": "Pre-gate-protocol wave"},
                                    "gate_to_ready": {"result": "not_recorded"}}}}
        self.assertEqual(self.errors(legacy), [])
        import yaml
        fixture_state = yaml.safe_load((self.root / "planning/lifecycle/process-state.yaml").read_text(encoding="utf-8"))
        self.assertEqual(self.errors(fixture_state["waves"]), [])

    def test_optional_testability_and_acceptance_gates_are_valid(self) -> None:
        for result in ("not_recorded", "passed", "failed", "pending"):
            with self.subTest(acceptance=result):
                self.assertEqual(self.errors({"W1": wave_block("verifying", acceptance_gate={"result": result})}), [])
        self.assertEqual(self.errors({"W1": wave_block("done",
            testability_gate={"result": "passed", "evaluated": "2026-11-06"},
            acceptance_gate={"result": "passed", "evaluated": "2026-11-06",
                             "evidence": {"wave_report": "planning/wave-reports/W1.md"}})}), [])
        self.assertEqual(self.errors({"W2": wave_block("verifying", acceptance_gate={
            "result": "pending", "pending_decisions": [{"id": "DEC-009", "text": "Business rule open"}]})}), [])

    def test_gate_contract_stays_strict_where_it_was_strict(self) -> None:
        self.assertTrue(self.errors({"W1": wave_block("ready", gate_to_ready={"result": "pending"})}),
                        "pending is only an acceptance-gate result")
        self.assertTrue(self.errors({"W1": wave_block("ready", testability_gate={"result": "pending"})}))
        self.assertTrue(self.errors({"W1": wave_block("verifying", acceptance_gate="passed")}),
                        "the acceptance gate is an object with `result`, not a scalar")
        self.assertTrue(self.errors({"W1": wave_block("verifying", acceptance_gate={"result": "pending",
                        "pending_decisions": [{"id": "DEC-009"}]})}))
        self.assertTrue(self.errors({"W1": wave_block("verifying", surprise_gate={"result": "passed"})}))
        self.assertTrue(self.errors({"W1": {"phase": "ready", "gates": {"gate_to_refinement": {"result": "passed"}}}}),
                        "gate_to_ready stays a required key")

    # ------------------------------------------------------------------ DONE_BASIS_NOT_RECORDED
    def test_done_wave_without_acceptance_gate_is_one_informative_diagnostic(self) -> None:
        found = self.diagnostics("DONE_BASIS_NOT_RECORDED")
        self.assertEqual(len(found), 1)
        item = found[0]
        self.assertEqual((item["severity"], item["blocking"], item["repairability"]), ("INFO", False, "UNSUPPORTED"))
        self.assertIsNone(item["proposed_repair_type"])
        self.assertIn("W02", item["message"])
        self.assertEqual(item["source_path"], "planning/lifecycle/process-state.yaml")

    def test_recorded_acceptance_basis_silences_the_diagnostic_and_not_recorded_does_not(self) -> None:
        write_file(self.root, "planning/lifecycle/process-state.yaml", json.dumps({"waves": {
            "W01": wave_block("verifying"),
            "W02": wave_block("done", acceptance_gate={"result": "passed", "evaluated": "2026-11-06"}),
            "W03": wave_block("done", acceptance_gate={"result": "not_recorded"}),
        }}))
        found = self.diagnostics("DONE_BASIS_NOT_RECORDED")
        self.assertEqual(len(found), 1)
        self.assertIn("W03", found[0]["message"])
        self.assertNotIn("W02", found[0]["message"])
        self.assertNotIn("W01", found[0]["message"], "only done waves are considered")

    def test_many_done_waves_are_aggregated_into_a_single_diagnostic(self) -> None:
        write_file(self.root, "planning/lifecycle/process-state.yaml", json.dumps({"waves": {
            f"W{index:02d}": wave_block("done") for index in range(1, 16)}}))
        found = self.diagnostics("DONE_BASIS_NOT_RECORDED")
        self.assertEqual(len(found), 1)
        self.assertIn("15 done wave(s)", found[0]["message"])
        self.assertIn("(+7 more)", found[0]["message"])

    # ------------------------------------------------------------------ CHANGE_SET_SCHEMA_INVALID
    def test_change_set_diagnostics_cover_invalid_campaign_log_style_and_broken_json(self) -> None:
        directory = "planning/reconciliation/change-sets"
        write_file(self.root, f"{directory}/CS-FIXTURE-OK.json", json.dumps(VALID_CHANGE_SET))
        campaign_log = dict(VALID_CHANGE_SET, change_set_id="CS-FIXTURE-LOG", final_result="PARTIAL_PASS",
                            gap_classification="mixed", updated_at="2026-11-02T10:00:00Z")
        write_file(self.root, f"{directory}/CS-FIXTURE-LOG.json", json.dumps(campaign_log))
        write_file(self.root, f"{directory}/CS-FIXTURE-BROKEN.json", "{ not json")
        found = {item["source_path"]: item for item in self.diagnostics("CHANGE_SET_SCHEMA_INVALID")}
        self.assertEqual(sorted(found), [f"{directory}/CS-FIXTURE-BROKEN.json", f"{directory}/CS-FIXTURE-LOG.json"])
        log = found[f"{directory}/CS-FIXTURE-LOG.json"]
        self.assertEqual((log["severity"], log["blocking"], log["repairability"]), ("WARNING", False, "DECISION_REQUIRED"))
        self.assertIn("not a work container", log["message"])
        self.assertIn("violation(s)", log["message"])
        self.assertIn("not valid JSON", found[f"{directory}/CS-FIXTURE-BROKEN.json"]["message"])

    def test_new_diagnostics_never_make_the_project_blocked_or_change_the_source_fingerprint(self) -> None:
        baseline = self.doctor()
        directory = "planning/reconciliation/change-sets"
        write_file(self.root, f"{directory}/CS-FIXTURE-LOG.json", json.dumps(dict(VALID_CHANGE_SET, final_result="PARTIAL_PASS")))
        write_file(self.root, "planning/revisions/REV-099.yaml", "revision_id: REV-099\nactive_target: true\nartifact_path: input-resources/ui-ux/none.html\n")
        after = self.doctor()
        new = [item for item in after["diagnostics"] if item["category"] in ("CHANGE_SET_SCHEMA_INVALID", "ACTIVE_REVISION_UNBOUND")]
        self.assertEqual(len(new), 2)
        self.assertFalse(any(item["blocking"] for item in new))
        if baseline["compatibility"] != "BLOCKED":
            self.assertNotEqual(after["compatibility"], "BLOCKED")
        self.assertEqual(after["source_fingerprint"], baseline["source_fingerprint"],
                         "informative lifecycle diagnostics must not enter the source fingerprint")

    # ------------------------------------------------------------------ ACTIVE_REVISION_UNBOUND
    def test_active_ledger_revision_without_any_page_binding_is_reported(self) -> None:
        write_file(self.root, "planning/revisions/REV-037.yaml", """
            revision_id: REV-037
            revision: 37
            active_target: true
            artifact_path: input-resources/ui-ux/rev37.html
        """)
        write_file(self.root, "planning/revisions/REV-005.yaml", "revision_id: REV-005\nactive_target: false\nartifact_path: input-resources/ui-ux/rev5.html\n")
        found = self.diagnostics("ACTIVE_REVISION_UNBOUND")
        self.assertEqual([item["source_path"] for item in found], ["planning/revisions/REV-037.yaml"])
        item = found[0]
        self.assertEqual((item["severity"], item["blocking"], item["repairability"]), ("WARNING", False, "DECISION_REQUIRED"))
        self.assertIn("REV-037", item["message"])

    def test_page_bindings_by_target_mockup_source_mockup_or_target_revision_clear_the_diagnostic(self) -> None:
        write_file(self.root, "planning/revisions/REV-037.yaml",
                   "revision_id: REV-037\nrevision: 37\nactive_target: true\nartifact_path: input-resources/ui-ux/rev37.html\n")
        for index, page_fields in enumerate((
            "source_mockup: input-resources/ui-ux/other.html\ntarget_mockup: input-resources/ui-ux/rev37.html",
            "source_mockup: input-resources/ui-ux/rev37.html",
            "source_mockup: input-resources/ui-ux/other.html\ntarget_revision: REV-037",
        )):
            with self.subTest(binding=page_fields):
                path = self.root / f"planning/ui-inventory/PAGE-BIND-{index}.yaml"
                write_file(self.root, f"planning/ui-inventory/PAGE-BIND-{index}.yaml",
                           f"page_id: PAGE-BIND-{index}\n{page_fields}\n")
                self.assertEqual(self.diagnostics("ACTIVE_REVISION_UNBOUND"), [])
                path.unlink()

    def test_standalone_interaction_artifact_does_not_bind_a_revision(self) -> None:
        write_file(self.root, "planning/revisions/REV-037.yaml",
                   "revision_id: REV-037\nactive_target: true\nartifact_path: input-resources/ui-ux/rev37.html\n")
        write_file(self.root, "planning/ui-inventory/PAGE-INTERACTION-STATES-REV37.yaml",
                   "page_id: PAGE-INTERACTION-STATES-REV37\ntarget_mockup: input-resources/ui-ux/rev37.html\n")
        self.assertEqual(len(self.diagnostics("ACTIVE_REVISION_UNBOUND")), 1)

    def test_status_projection_with_all_new_diagnostics_validates_against_the_status_schema(self) -> None:
        write_file(self.root, "planning/reconciliation/change-sets/CS-FIXTURE-LOG.json", json.dumps(dict(VALID_CHANGE_SET, final_result="X")))
        write_file(self.root, "planning/revisions/REV-099.yaml", "revision_id: REV-099\nactive_target: true\nartifact_path: input-resources/ui-ux/none.html\n")
        status = build_project_status.build_status(self.root)
        categories = {item["category"] for item in status["compatibility"]["diagnostics"]}
        self.assertTrue({"DONE_BASIS_NOT_RECORDED", "CHANGE_SET_SCHEMA_INVALID", "ACTIVE_REVISION_UNBOUND"} <= categories)
        schema = json.loads(SCHEMA.read_text(encoding="utf-8-sig"))
        self.assertEqual([error.message for error in Draft7Validator(schema).iter_errors(status)], [])

    # ------------------------------------------------------------------ boundaries
    def test_doctor_stays_read_only_and_never_creates_waves_findings_or_tasks(self) -> None:
        write_file(self.root, "planning/execution-waves.md", "## W99 - Authorized but unregistered wave\n\nREQ-001\n")
        write_file(self.root, "planning/reconciliation/change-sets/CS-FIXTURE-LOG.json", json.dumps(dict(VALID_CHANGE_SET, final_result="X")))
        before = tree_fingerprint(self.root)
        first = self.doctor()
        second = self.doctor()
        self.assertEqual(first, second)
        self.assertEqual(before, tree_fingerprint(self.root), "Doctor must not write, register or migrate anything")
        self.assertFalse((self.root / "planning/findings").exists())
        self.assertNotIn("W99", json.dumps(first), "execution-waves.md is not parsed by the Doctor")
        import yaml
        state = yaml.safe_load((self.root / "planning/lifecycle/process-state.yaml").read_text(encoding="utf-8"))
        self.assertEqual(sorted(state["waves"]), ["W01", "W02"])

    def test_exit_code_contract_is_unchanged_by_the_new_diagnostics(self) -> None:
        write_file(self.root, "planning/reconciliation/change-sets/CS-FIXTURE-LOG.json", json.dumps(dict(VALID_CHANGE_SET, final_result="X")))
        output = StringIO()
        with patch.object(sys, "argv", ["project_compatibility.py", "doctor", "--project-root", str(self.root), "--format", "json"]):
            with redirect_stdout(output):
                exit_code = project_compatibility.main()
        report = json.loads(output.getvalue())
        self.assertEqual(exit_code, {"COMPATIBLE": 0, "PARTIAL": 1, "BLOCKED": 2}[report["compatibility"]])
        self.assertIn(exit_code, (0, 1, 2))


class ParityStatusResolverTests(unittest.TestCase):
  CONTRACT_SOURCE_PATH = "requirements/REQ-001.yml"
  CONTRACT_SOURCE_CONTENT = (
    b"ID: REQ-001\n"
    b"title: Synthetic canonical requirement\n"
    b"description: Requirement source used for parity contract evidence.\n"
    b"status: accepted\n"
  )
  CONTRACT_SOURCE_HASH = "sha256:" + hashlib.sha256(CONTRACT_SOURCE_CONTENT).hexdigest()

  @classmethod
  def validated_source_hashes(cls) -> dict[str, str]:
    return {cls.CONTRACT_SOURCE_PATH: cls.CONTRACT_SOURCE_HASH.removeprefix("sha256:")}

  @staticmethod
  def live_report() -> tuple[dict, dict, dict]:
    identity = {
      "status": "BOUND",
      "active_target": "REV-001",
      "canonical_mockup_path": "planning/target-mockups/mock/REV-001/index.html",
      "revision": "REV-001",
      "fingerprint": "sha256:" + "a" * 64,
      "target_page": "PAGE-001",
      "roles": ["Admin"],
      "states": ["default"],
      "app_revision": "app-build-001",
      "model_revision": "model-revision-001",
    }

    def proof(kind: str, **fields) -> dict:
      return {"type": kind, "description": f"Synthetic {kind} proof", "passed": True, **fields}

    dimensions = {
      "visual": {"result": "PASS", "required": True, "evidence": [proof("screenshot", path="planning/evidence/screenshots/app.png", capture_id="app-capture")]},
      "content": {"result": "PASS", "required": True, "evidence": [proof("dom_text", expected="Regions", actual="Regions")]},
            "structure": {"result": "PASS", "required": True, "evidence": [proof("mxcli_inspect"), proof("dom_selector"), proof("screenshot", path="planning/evidence/screenshots/structure.png")]},
            "state": {"result": "PASS", "required": True, "evidence": [proof("interaction_test"), proof("screenshot", path="planning/evidence/screenshots/state.png")]},
            "interaction": {"result": "PASS", "required": True, "evidence": [proof("interaction_test"), proof("navigation_flow")]},
            "responsive": {"result": "PASS", "required": True, "evidence": [proof("viewport_test"), proof("screenshot", path="planning/evidence/screenshots/responsive.png")]},
            "role": {"result": "PASS", "required": True, "evidence": [proof("role_test"), proof("dom_selector")]},
    }
    matrix = {
      "contract_parity": {
        "status": "PASS",
        "note": "Contract references verified",
        "capture_ids": ["app-capture"],
        "evidence": [proof("contract_reference", path=ParityStatusResolverTests.CONTRACT_SOURCE_PATH, passed=True)],
        "source_artifacts": [{
          "source_type": "requirement",
          "canonical_path": ParityStatusResolverTests.CONTRACT_SOURCE_PATH,
          "artifact_id": "REQ-001",
          "content_hash": ParityStatusResolverTests.CONTRACT_SOURCE_HASH,
        }],
      },
      "model_parity": {"status": "PASS", "note": "Model checked", "capture_ids": ["app-capture"], "evidence": [proof("mxcli_inspect", path="planning/evidence/model-inspection.json")]},
      "structural_dom_parity": {"status": "PASS", "note": "DOM checked", "capture_ids": ["app-capture"], "evidence": [proof("dom_selector", selector="main")]},
      "behavioral_parity": {"status": "PASS", "note": "Behavior checked", "capture_ids": ["app-capture"], "evidence": [proof("interaction_test", description="Transition was exercised"), proof("navigation_flow", description="Navigation was verified")]},
      "role_parity": {"status": "PASS", "note": "Role checked", "capture_ids": ["app-capture"], "evidence": [proof("role_test", description="Admin session verified")]},
      "visual_whole_screen_parity": {"status": "PASS", "capture_ids": ["reference-capture", "app-capture"], "evidence": [
        proof("screenshot", path="planning/evidence/screenshots/reference.png", capture_id="reference-capture"),
        proof("screenshot", path="planning/evidence/screenshots/app.png", capture_id="app-capture"),
      ]},
    }
    report = {
      "page_id": "PAGE-001",
      "schema_version": 3,
      "evidence_class": "LIVE_PARITY",
      "evidence_level": "browser",
      "verified_at": "2026-11-02",
      "comparison_identity": identity,
      "evidence_matrix": matrix,
      "dimensions": dimensions,
      "whole_screen_review": {
        "status": "complete",
        "scope_note": "Synthetic in-scope review",
        "comparison_result": "PASS",
        "comparison_summary": "Reference and runtime captures compared; no in-scope visual gaps found.",
        "reference_capture_ids": ["reference-capture"],
        "runtime_capture_ids": ["app-capture"],
        "visually_reviewed_capture_ids": ["reference-capture", "app-capture"],
      },
      "overall_result": "PASS",
    }
    capture_sides = {"reference-capture": "mockup", "app-capture": "application"}
    return report, identity, capture_sides

  def test_complete_live_parity_resolves_pass_from_structured_evidence(self):
    report, identity, capture_sides = self.live_report()

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "RESOLVED")
    self.assertEqual(result["computed_overall_result"], "PASS")
    self.assertTrue(result["promotion_allowed"])
    self.assertEqual(
      result["evidence_provenance"]["validated_contract_sources"][0]["content_hash"],
      self.CONTRACT_SOURCE_HASH,
    )

  def test_whole_screen_screenshots_without_comparison_result_do_not_verify_visual_parity(self):
    report, identity, capture_sides = self.live_report()
    report["whole_screen_review"].pop("comparison_result", None)

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "BLOCKED")
    self.assertEqual(result["computed_overall_result"], "NOT_VERIFIED")
    self.assertEqual(result["evidence_matrix_results"]["visual_whole_screen_parity"], "NOT_VERIFIED")
    self.assertFalse(result["promotion_allowed"])

  def test_whole_screen_comparison_gap_is_preserved_as_fail_or_partial(self):
    for comparison_result, expected_aggregate in (("FAIL", "FAIL"), ("PARTIAL", "PARTIAL")):
      with self.subTest(comparison_result=comparison_result):
        report, identity, capture_sides = self.live_report()
        report["whole_screen_review"]["comparison_result"] = comparison_result
        report["whole_screen_review"]["comparison_summary"] = "Actual comparison found a visual gap."
        report["evidence_matrix"]["visual_whole_screen_parity"]["status"] = comparison_result

        result = build_project_status.resolve_parity_status(
          report,
          expected_identity=identity,
          target_freshness="CURRENT",
          validated_capture_sides=capture_sides,
          validated_source_hashes=self.validated_source_hashes(),
        )

        self.assertEqual(result["status"], "RESOLVED")
        self.assertEqual(result["computed_overall_result"], expected_aggregate)
        self.assertFalse(result["promotion_allowed"])

  def test_contract_parity_pass_requires_validated_requirement_or_decision_hash(self):
    report, identity, capture_sides = self.live_report()

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes={},
    )

    self.assertEqual(result["status"], "BLOCKED")
    self.assertEqual(result["computed_overall_result"], "NOT_VERIFIED")
    self.assertIn("CONTRACT_SOURCE_EVIDENCE_INSUFFICIENT", [item["code"] for item in result["blockers"]])

  def test_regions_style_smoke_never_promotes_missing_parity_dimensions(self):
    report, identity, capture_sides = self.live_report()
    report["evidence_class"] = "SMOKE"
    report["dimensions"]["interaction"]["result"] = "NOT_VERIFIED"
    report["dimensions"]["role"]["result"] = "NOT_VERIFIED"
    report["dimensions"]["visual"]["result"] = "NOT_VERIFIED"

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "BLOCKED")
    self.assertEqual(result["computed_overall_result"], "NOT_VERIFIED")
    self.assertFalse(result["promotion_allowed"])

  def test_reference_model_analysis_is_not_live_parity(self):
    report, identity, capture_sides = self.live_report()
    report["evidence_class"] = "REFERENCE_VS_MODEL"
    report["evidence_level"] = "model"

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["computed_overall_result"], "NOT_VERIFIED")
    self.assertFalse(result["promotion_allowed"])

  def test_missing_evidence_class_remains_not_observable(self):
    report, identity, capture_sides = self.live_report()
    report.pop("evidence_class")

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "NOT_OBSERVABLE")
    self.assertEqual(result["computed_overall_result"], "NOT_VERIFIED")
    self.assertFalse(result["promotion_allowed"])

  def test_unknown_dimension_status_remains_unknown(self):
    report, identity, capture_sides = self.live_report()
    report["dimensions"]["role"]["result"] = "UNASSESSED_BY_FUTURE_VERSION"

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "UNKNOWN")
    self.assertEqual(result["computed_overall_result"], "NOT_VERIFIED")
    self.assertFalse(result["promotion_allowed"])

  def test_pass_claim_without_dimension_evidence_is_blocked(self):
    report, identity, capture_sides = self.live_report()
    report["dimensions"]["role"]["evidence"] = []

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "BLOCKED")
    self.assertEqual(result["computed_overall_result"], "NOT_VERIFIED")

  def test_evidenced_required_fail_precedes_another_unverified_dimension(self):
    report, identity, capture_sides = self.live_report()
    report["dimensions"]["content"]["result"] = "FAIL"
    report["dimensions"]["content"]["evidence"][0]["passed"] = False
    report["dimensions"]["content"]["deviations"] = [{"concern": "content_mismatch", "description": "Mismatch", "severity": "material"}]
    report["dimensions"]["role"]["result"] = "NOT_VERIFIED"

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "RESOLVED")
    self.assertEqual(result["computed_overall_result"], "FAIL")

  def test_changed_comparison_identity_is_stale(self):
    report, identity, capture_sides = self.live_report()
    expected = copy.deepcopy(identity)
    expected["revision"] = "REV-002"

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=expected,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "STALE")
    self.assertEqual(result["computed_overall_result"], "STALE")
    self.assertFalse(result["promotion_allowed"])

  def test_unresolved_stale_and_not_verified_precedence_is_ambiguous(self):
    report, identity, capture_sides = self.live_report()
    report["dimensions"]["visual"]["result"] = "STALE"
    report["dimensions"]["interaction"]["result"] = "NOT_VERIFIED"

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "AMBIGUOUS")
    self.assertIsNone(result["computed_overall_result"])
    self.assertFalse(result["promotion_allowed"])

  def test_required_matrix_not_applicable_without_note_is_not_pass(self):
    report, identity, capture_sides = self.live_report()
    report["evidence_matrix"]["role_parity"] = {"status": "NOT_APPLICABLE", "required": True}

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "BLOCKED")
    self.assertEqual(result["computed_overall_result"], "NOT_VERIFIED")
    self.assertFalse(result["promotion_allowed"])

  def test_matrix_does_not_borrow_proof_from_a_ui_dimension(self):
    report, identity, capture_sides = self.live_report()
    report["evidence_matrix"]["model_parity"]["evidence"] = []

    result = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )

    self.assertEqual(result["status"], "BLOCKED")
    self.assertEqual(result["computed_overall_result"], "NOT_VERIFIED")
    self.assertFalse(result["promotion_allowed"])

  def test_single_report_cli_resolves_without_project_scan(self):
    report, identity, capture_sides = self.live_report()
    temporary = tempfile.TemporaryDirectory(prefix="mxagile-parity-request-")
    temp_dir = temporary.name
    try:
      source_path = Path(temp_dir) / self.CONTRACT_SOURCE_PATH
      source_path.parent.mkdir(parents=True, exist_ok=True)
      source_path.write_bytes(self.CONTRACT_SOURCE_CONTENT)
      request_path = Path(temp_dir) / "request.json"
      request_path.write_text(json.dumps({
        "report": report,
        "expected_identity": identity,
        "target_freshness": "CURRENT",
        "validated_capture_sides": capture_sides,
        "project_root": temp_dir,
      }), encoding="utf-8")
      result = subprocess.run(
        [sys.executable, str(BUILDER), "--resolve-parity-request", str(request_path)],
        capture_output=True, text=True, check=False,
      )
    finally:
      cleanup_temporary_directory(temporary, expected_prefix="mxagile-parity-request-")

    self.assertEqual(result.returncode, 0, result.stderr)
    resolution = json.loads(result.stdout)
    self.assertEqual(resolution["status"], "RESOLVED")
    self.assertEqual(resolution["computed_overall_result"], "PASS")
    self.assertTrue(resolution["promotion_allowed"])

  def test_parity_schema_rejects_smoke_promotion_and_accepts_resolved_live_pass(self):
    schema = json.loads((ROOT / ".mxagile/schemas/parity-verification.schema.json").read_text(encoding="utf-8"))
    validator = Draft7Validator(schema)
    report, identity, capture_sides = self.live_report()
    resolution = build_project_status.resolve_parity_status(
      report,
      expected_identity=identity,
      target_freshness="CURRENT",
      validated_capture_sides=capture_sides,
      validated_source_hashes=self.validated_source_hashes(),
    )
    report["aggregate_resolution"] = resolution
    self.assertEqual(resolution["computed_overall_result"], "PASS")
    self.assertEqual(list(validator.iter_errors(report)), [])

    for evidence_class in ("SMOKE", "REFERENCE_VS_MODEL"):
      non_live_claim = copy.deepcopy(report)
      non_live_claim["evidence_class"] = evidence_class
      self.assertTrue(list(validator.iter_errors(non_live_claim)), evidence_class)

  def test_gallery_projection_downgrades_unclassified_reported_pass(self):
    report, identity, _ = self.live_report()
    report["schema_version"] = 2
    report.pop("evidence_class")
    report.pop("aggregate_resolution", None)
    reference_path = "planning/target-mockups/mock/REV-001/index.html"
    report["comparison_identity"]["canonical_mockup_path"] = reference_path
    identity["canonical_mockup_path"] = reference_path

    with tempfile.TemporaryDirectory(prefix="mxagile-parity-gallery-resolver-") as temp_dir:
      root = Path(temp_dir)
      write_file(root, reference_path, "<html>target</html>\n")
      screenshot_paths = {
        "reference-capture": "planning/evidence/screenshots/target/reference.png",
        "app-capture": "planning/evidence/screenshots/actual/application.png",
      }
      for relative in screenshot_paths.values():
        image = root / relative
        image.parent.mkdir(parents=True, exist_ok=True)
        image.write_bytes(b"\x89PNG\r\n\x1a\nsynthetic-image")
      group_inputs = (
        ("reference-capture", "mockup", "target"),
        ("app-capture", "application", "actual"),
      )
      capture_groups = []
      for capture_id, side, snapshot_name in group_inputs:
        snapshot_path = f"planning/evidence/snapshots/{snapshot_name}.html"
        write_file(root, snapshot_path, "<html>snapshot</html>\n")
        capture_groups.append({
          "capture_id": capture_id,
          "capture_source": side,
          "captured_at": "2026-11-02T12:00:00Z",
          "comparison_identity": identity,
          "runtime_url": "http://localhost:8080/",
          "role": "Admin",
          "target_screen": "PAGE-001",
          "session_id": f"session-{side}",
          "run_id": "run-001",
          "screenshot_path": screenshot_paths[capture_id],
          "snapshots": [{"path": snapshot_path, "type": "dom"}],
          "cleanliness_state": "clean",
        })
      entry = {
        "entry_id": "EVID-PAGE-001",
        "scenario_id": "SCN-PAGE-001",
        "screen_id": "PAGE-001",
        "role": "Admin",
        "data_state": "default",
        "parity_result": "PASS",
        "target_mockup": reference_path,
        "comparison_identity": identity,
        "parity_report_path": "planning/parity/PAGE-001.yaml",
        "target_evidence": [{
          "artifact_id": "TARGET-SCREENSHOT",
          "type": "screenshot",
          "path": screenshot_paths["reference-capture"],
          "source": "mockup",
          "capture_id": "reference-capture",
          "dimension": "visual",
          "description": "Synthetic reference capture",
          "lifecycle_stage": "promoted",
        }],
        "actual_evidence": [{
          "artifact_id": "APP-SCREENSHOT",
          "type": "screenshot",
          "path": screenshot_paths["app-capture"],
          "source": "application",
          "capture_id": "app-capture",
          "dimension": "visual",
          "description": "Synthetic application capture",
          "lifecycle_stage": "promoted",
        }],
        "capture_groups": capture_groups,
      }
      manifest = {"manifest_id": "MFT-W01", "wave_id": "W01", "entries": [entry]}
      manifest_path = "planning/evidence/manifests/W01-evidence-manifest.yaml"
      parity_path = "planning/parity/PAGE-001.yaml"
      write_file(root, manifest_path, json.dumps(manifest))
      write_file(root, parity_path, json.dumps(report))
      target = {
        "availability": "available",
        "screen_ids": ["PAGE-001"],
        "canonical_path": reference_path,
        "revision_id": "REV-001",
        "bundle_hash": identity["fingerprint"],
        "content_hash": identity["fingerprint"],
      }

      with project_compatibility.schema_validation_scope():
        runs = build_project_status.visual_evidence_projection(
          root,
          [manifest],
          [manifest_path],
          [target],
          {},
          [],
        )
      self.assertEqual(len(runs), 1)
      self.assertEqual(runs[0]["reported_parity_result"], "PASS")
      self.assertEqual(runs[0]["parity_result"], "NOT_VERIFIED")
      self.assertEqual(runs[0]["parity_resolution"]["status"], "NOT_OBSERVABLE")
      self.assertFalse(runs[0]["parity_resolution"]["promotion_allowed"])

      entry.pop("capture_groups")
      write_file(root, manifest_path, json.dumps(manifest))
      no_capture_gaps: list[dict[str, str | None]] = []
      with project_compatibility.schema_validation_scope():
        no_capture_runs = build_project_status.visual_evidence_projection(
          root,
          [manifest],
          [manifest_path],
          [target],
          {},
          no_capture_gaps,
        )

      live_report, live_identity, capture_sides = self.live_report()
      live_identity["canonical_mockup_path"] = reference_path
      live_report["comparison_identity"] = live_identity
      contract_content = self.CONTRACT_SOURCE_CONTENT
      contract_path = self.CONTRACT_SOURCE_PATH
      contract_file = root / contract_path
      contract_file.parent.mkdir(parents=True, exist_ok=True)
      contract_file.write_bytes(contract_content)
      contract_digest = hashlib.sha256(contract_content).hexdigest()
      live_report["evidence_matrix"]["contract_parity"]["source_artifacts"][0]["content_hash"] = "sha256:" + contract_digest
      live_resolution = build_project_status.resolve_parity_status(
        live_report,
        expected_identity=live_identity,
        target_freshness="CURRENT",
        validated_capture_sides=capture_sides,
        validated_source_hashes={contract_path: contract_digest},
      )
      live_report["aggregate_resolution"] = live_resolution
      entry["comparison_identity"] = live_identity
      entry["capture_groups"] = capture_groups
      write_file(root, manifest_path, json.dumps(manifest))
      write_file(root, parity_path, json.dumps(live_report))
      live_gaps: list[dict[str, str | None]] = []
      with project_compatibility.schema_validation_scope():
        live_runs = build_project_status.visual_evidence_projection(
          root,
          [manifest],
          [manifest_path],
          [target],
          {contract_path: contract_digest},
          live_gaps,
        )
      entry["comparison_identity"] = {**live_identity, "status": "INCOMPLETE"}
      write_file(root, manifest_path, json.dumps(manifest))
      identity_gaps: list[dict[str, str | None]] = []
      with project_compatibility.schema_validation_scope():
        identity_runs = build_project_status.visual_evidence_projection(
          root,
          [manifest],
          [manifest_path],
          [target],
          {contract_path: contract_digest},
          identity_gaps,
        )

    self.assertEqual(len(no_capture_runs), 1)
    self.assertEqual(no_capture_runs[0]["run_id"], "UNOBSERVED")
    self.assertEqual(no_capture_runs[0]["parity_result"], "NOT_VERIFIED")
    self.assertIn("PARITY_EVIDENCE_UNOBSERVED", [gap["code"] for gap in no_capture_gaps])
    self.assertEqual(len(live_runs), 1)
    self.assertEqual(live_runs[0]["reported_parity_result"], "PASS")
    self.assertEqual(live_runs[0]["parity_result"], "PASS")
    self.assertEqual(live_runs[0]["parity_resolution"]["status"], "RESOLVED")
    self.assertTrue(live_runs[0]["parity_resolution"]["promotion_allowed"])
    self.assertEqual(len(identity_runs), 1)
    self.assertEqual(identity_runs[0]["run_id"], "UNOBSERVED")
    self.assertEqual(identity_runs[0]["parity_resolution"]["status"], "BLOCKED")
    self.assertFalse(identity_runs[0]["parity_resolution"]["promotion_allowed"])
    self.assertIn("PARITY_IDENTITY_UNBOUND", [gap["code"] for gap in identity_gaps])


if __name__ == "__main__":
    unittest.main()