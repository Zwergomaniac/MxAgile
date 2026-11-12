"""Run/event contract and persistence tests. Events are audit-only and never mutate canonical state."""

from __future__ import annotations

import concurrent.futures
import datetime as dt
import json
import sys
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import run_events  # noqa: E402


class RunEventTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="mxagile-run-events-")
        self.root = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def emit(self, event_type: str, run_id: str = "RUN-0123456789ab", **kwargs) -> dict:
        return run_events.append_event(self.root, event_type, run_id=run_id, host="claude_code", **kwargs)

    def test_event_envelope_is_versioned_validated_and_additive(self):
        event = self.emit("delivery_blocked", payload={"reason_codes": ["HEAD_STALE"], "new_additive_field": True})
        self.assertEqual(run_events.validate_event(event), [])
        self.assertEqual(event["schema_version"], 1)
        self.assertRegex(event["event_id"], r"^EVT-[0-9a-f]{32}$")
        invalid = {**event, "schema_version": 2}
        self.assertTrue(run_events.validate_event(invalid))
        invalid = {**event, "event_type": "agent_says_success"}
        self.assertTrue(run_events.validate_event(invalid))

    def test_legacy_consumer_without_event_history_is_valid_and_empty(self):
        snapshot = run_events.read_events(self.root)
        self.assertEqual((snapshot["events"], snapshot["total_valid"], snapshot["invalid_lines"]), ([], 0, 0))
        self.assertEqual(run_events.active_runs(snapshot["events"]), [])

    def test_sequence_is_per_run_not_a_false_global_order(self):
        first = self.emit("child_started", "RUN-0123456789ab")
        parallel = self.emit("child_started", "RUN-fedcba987654")
        next_child_event = self.emit("child_accepted", "RUN-0123456789ab")
        cross_class = self.emit("lifecycle_resync_completed", "RUN-0123456789ab")
        self.assertEqual((first["sequence"], parallel["sequence"], next_child_event["sequence"], cross_class["sequence"]), (1, 1, 2, 3))
        self.assertNotEqual(first["event_id"], parallel["event_id"])

    def test_concurrent_append_is_valid_unique_and_per_run_ordered(self):
        def write(index: int) -> dict:
            return self.emit("delivery_blocked", payload={"reason_codes": [f"R{index}"], "round": index + 1})
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            events = list(pool.map(write, range(40)))
        self.assertEqual(sorted(event["sequence"] for event in events), list(range(1, 41)))
        snapshot = run_events.read_events(self.root, limit=100)
        self.assertEqual((snapshot["total_valid"], snapshot["invalid_lines"]), (40, 0))

    def test_corrupt_complete_line_is_skipped_and_partial_tail_is_recovered(self):
        self.emit("delivery_blocked")
        log = next((self.root / run_events.EVENT_DIR).glob("events-*.jsonl"))
        with log.open("ab") as handle:
            handle.write(b'{"invalid":true}\n{"partial":')
        snapshot = run_events.read_events(self.root)
        self.assertEqual((snapshot["total_valid"], snapshot["invalid_lines"], snapshot["partial_tail_files"]), (1, 1, 1))
        recovered = self.emit("delivery_authorized")
        snapshot = run_events.read_events(self.root)
        self.assertEqual((recovered["sequence"], snapshot["invalid_lines"], snapshot["partial_tail_files"]), (2, 1, 0))

    def test_retention_removes_old_run_audit_and_diagnostics_but_keeps_project_history(self):
        old = dt.datetime(2025, 1, 15, tzinfo=dt.timezone.utc)
        self.emit("delivery_blocked", "RUN-OLD12345678", occurred_at=old)
        self.emit("adapter_unavailable", "RUN-OLD87654321", occurred_at=old)
        self.emit("lifecycle_resync_completed", "RUN-OLDabcdefgh", occurred_at=old)
        self.emit("delivery_authorized", "RUN-NEW12345678")
        snapshot = run_events.read_events(self.root, limit=100)
        self.assertEqual([event["event_type"] for event in snapshot["events"]], ["lifecycle_resync_completed", "delivery_authorized"])

    def test_orphaned_child_is_unknown_not_failed_and_parent_link_survives(self):
        parent = "RUN-parent000001"
        child = "RUN-child000001"
        self.emit("child_started", child, parent_run_id=parent, mission_id="MISSION-1", wave_id="W02", actor="builder")
        run = run_events.active_runs(run_events.read_events(self.root)["events"])[0]
        self.assertEqual((run["parent_run_id"], run["status"], run["reconciliation_state"]), (parent, "RESULT_UNKNOWN", "NEEDS_RECONCILIATION"))
        self.assertNotEqual(run["status"], "FAILED")
        self.emit("child_accepted", child, parent_run_id=parent, payload={"acceptance_status": "ACCEPTED"})
        self.assertEqual(run_events.active_runs(run_events.read_events(self.root)["events"]), [])

    def test_resume_reconciliation_reads_canonical_state_and_does_not_change_it(self):
        sys.path.insert(0, str(ROOT / "tests"))
        from test_control_plane_phase1b import MISSION, Phase1BFixture
        from test_control_plane_phase1c import WRITE_EPOCH

        class ResumeFixture(Phase1BFixture):
            def runTest(inner_self):
                inner_self.set_wave("ready")
                inner_self.resync()
                subprocess.run(["pwsh", "-NoProfile", "-File", str(WRITE_EPOCH), "-ProjectRoot", str(inner_self.root),
                                "-MissionId", MISSION], capture_output=True, check=True)
                path = inner_self.root / "planning/lifecycle/process-state.yaml"
                before = path.read_bytes()
                self.root = inner_self.root
                resync_events = [event for event in run_events.read_events(inner_self.root)["events"]
                                 if event["event_type"].startswith("lifecycle_resync_")]
                self.assertEqual([event["event_type"] for event in resync_events],
                                 ["lifecycle_resync_started", "lifecycle_resync_completed"])
                self.assertEqual(resync_events[0]["run_id"], resync_events[1]["run_id"])
                from test_control_plane_phase1b import CLOSED
                handoff = inner_self.visual_handoff(CLOSED, parent_run_id="RUN-aabbccddeeff")
                self.emit("child_started", handoff["run_id"], parent_run_id="RUN-aabbccddeeff",
                          mission_id=handoff["mission_id"], wave_id="W01", actor="builder",
                          correlation={"delegation_id": handoff["delegation_id"],
                                       "handoff_reference": f".concord/delegation-handoffs/{handoff['delegation_id']}.json"})
                self.emit("gate_evaluated", "RUN-historical0001", payload={"gate_result": "PASS"})
                inner_self.write("input-resources/ui-ux/orders/index.html", "<html>revised after child start</html>\n")
                context = run_events.resume_context(inner_self.root)
                self.assertEqual(context["canonical_state"]["wave_phase"], "ready")
                self.assertEqual(context["unresolved_runs"][0]["reconciliation_state"], "NEEDS_RECONCILIATION")
                self.assertEqual(context["unresolved_runs"][0]["input_state"], "STALE")
                self.assertIn("input-resources/ui-ux/orders/index.html", context["unresolved_runs"][0]["changed_inputs"])
                self.assertEqual(path.read_bytes(), before)
                self.assertIn("canonical state", context["resume_rule"])
        suite = unittest.TestSuite([ResumeFixture()])
        result = unittest.TestResult()
        suite.run(result)
        self.assertEqual(result.errors, [])
        self.assertEqual(result.failures, [])


if __name__ == "__main__":
    unittest.main()
