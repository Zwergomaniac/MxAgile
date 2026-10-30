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


def write_file(root: Path, relative: str, content: str) -> Path:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content).lstrip(), encoding="utf-8")
    return path


def fixture(root: Path) -> None:
    write_file(root, "mxagile-project.yaml", "name: Board Fixture\n")
    write_file(root, ".mxagile/version.yaml", "version: '1.7.0'\n")
    write_file(root, ".env.mendix", "PASSWORD=do-not-export-this-secret\n")
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
        revision_id: REV-002
        mockup_name: Board
        active_target: true
        bundle_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    """)
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
        evidence = status["verification"]["evidence"]
        self.assertEqual(evidence["recorded_counts"]["PASS"], 1)
        self.assertEqual(evidence["current_counts"]["verified"], None)
        self.assertEqual(evidence["current_counts"]["stale"], 2)
        self.assertEqual(evidence["freshness"], "unknown")
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