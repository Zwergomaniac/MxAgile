"""Phase 2 reality fixture: one parent run with correlated visual-verifier children and a repair round."""

from __future__ import annotations

import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "scripts"), str(ROOT / "tests")]
from test_control_plane_phase1b import CLOSED
from test_control_plane_phase1c import AcceptanceFixture, WRITE_EPOCH, enforcement
import run_events


class ParentChildRunRealityTests(AcceptanceFixture):
    def test_delivery_children_repair_and_resume_history_do_not_drive_lifecycle_state(self):
        parent_run_id = "RUN-aabbccddeeff"
        mission_path = self.root / "planning/mission/mission-state.yaml"
        mission_state = yaml.safe_load(mission_path.read_text(encoding="utf-8"))
        mission_state["mission_id"] = "MISSION-2026-11-11-cp"
        self.write_yaml("planning/mission/mission-state.yaml", mission_state)
        self.set_wave("implementing")
        subprocess.run(["git", "-C", str(self.root), "add", "-A"], capture_output=True, check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
                "commit", "-qm", "developer approves implementation"], capture_output=True, check=True)
        subprocess.run(["pwsh", "-NoProfile", "-File", str(WRITE_EPOCH), "-ProjectRoot", str(self.root),
                "-MissionId", "MISSION-2026-11-11-cp"], capture_output=True, check=True)
        process_state = self.root / "planning/lifecycle/process-state.yaml"
        canonical_before_delivery = process_state.read_bytes()
        run_events.append_event(self.root, "run_started", run_id=parent_run_id, mission_id="MISSION-2026-11-11-control-plane",
                                wave_id="W01", actor="parent_delivery", host="claude_code")

        with patch.dict(os.environ, {"MXAGILE_RUN_ID": parent_run_id}):
            authorized = self.hook("Write", {"file_path": "javascriptsource/orders/overview.js"})
        self.assertEqual(authorized["decision"], "allow")
        self.assertEqual(process_state.read_bytes(), canonical_before_delivery)

        first = self.visual_handoff(CLOSED, parent_run_id=parent_run_id, delegation_id="DELEGATION-BUILDER-1")
        spawn = self.hook("Agent", {"subagent_type": first["agent_type"],
                                    "prompt": "MXAGILE_HANDOFF: .concord/delegation-handoffs/DELEGATION-BUILDER-1.json"})
        self.assertEqual(spawn["decision"], "allow", spawn.get("reason"))
        first_result, _ = self.save(first, self.verdict(first, [self.evidence("default"), self.evidence("modal_open")],
                                                       must=("VISUAL_CHANGES_REQUESTED",)))
        self.assertEqual(first_result["acceptance"], "ACCEPTED")

        repair = self.visual_handoff(CLOSED, parent_run_id=parent_run_id, delegation_id="DELEGATION-BUILDER-2")
        repair_spawn = self.hook("Agent", {"subagent_type": repair["agent_type"],
                                           "prompt": "MXAGILE_HANDOFF: .concord/delegation-handoffs/DELEGATION-BUILDER-2.json"})
        self.assertEqual(repair_spawn["decision"], "allow", repair_spawn.get("reason"))
        repair_result, _ = self.save(repair, self.verdict(repair, [self.evidence("default"), self.evidence("modal_open")]))
        self.assertEqual(repair_result["acceptance"], "ACCEPTED")

        facts = enforcement.guard.load_project_facts(self.root)
        transition = enforcement.guard.can_transition(facts, {
            "gate_type": "transition", "mission_id": "MISSION-2026-11-11-cp", "wave_id": "W01",
            "target_phase": "verifying", "implementation_completion": {"state": "all_terminal", "evidence_references": []},
        })
        self.assertEqual(transition["verdict"], "pass", transition["must_findings"])
        self.set_wave("verifying")
        subprocess.run(["git", "-C", str(self.root), "add", "-A"], capture_output=True, check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
                        "commit", "-qm", "lifecycle owner records verifying"], capture_output=True, check=True)
        subprocess.run(["pwsh", "-NoProfile", "-File", str(WRITE_EPOCH), "-ProjectRoot", str(self.root),
                        "-MissionId", "MISSION-2026-11-11-cp"], capture_output=True, check=True)
        self.assertIn("phase: verifying", process_state.read_text(encoding="utf-8"))
        run_events.append_event(self.root, "run_completed", run_id=parent_run_id,
                                mission_id="MISSION-2026-11-11-cp", wave_id="W01",
                                actor="parent_delivery", host="claude_code")

        snapshot = run_events.read_events(self.root, limit=500)
        parent = [event for event in snapshot["events"] if event["run_id"] == parent_run_id]
        children = [event for event in snapshot["events"] if event["parent_run_id"] == parent_run_id]
        self.assertEqual([event["event_type"] for event in parent], ["run_started", "delivery_authorized", "run_completed"])
        self.assertEqual({event["run_id"] for event in children}, {first["run_id"], repair["run_id"]})
        self.assertIn("repair_round_started", [event["event_type"] for event in snapshot["events"]])
        self.assertTrue(all(event["sequence"] == index for index, event in enumerate(parent, 1)))
        self.assertNotEqual(process_state.read_bytes(), canonical_before_delivery)
        self.assertEqual(run_events.resume_context(self.root)["canonical_state"]["wave_phase"], "verifying")
        self.assertEqual(run_events.active_runs(snapshot["events"]), [])


if __name__ == "__main__":
    unittest.main()
