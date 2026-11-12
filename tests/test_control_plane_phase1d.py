"""Phase 1D: Doctor control-plane health, observed host tool names, publication gate, child acceptance states."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_control_plane_phase1b import CLOSED, Phase1BFixture, child_contract, enforcement
from test_control_plane_phase1c import AcceptanceFixture

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import project_compatibility  # noqa: E402

REGISTER = ROOT / "scripts" / "Register-MxAgileControlPlaneHook.ps1"
# Tool list returned by a live Studio Pro 11.16 MCP endpoint (tools/list, read-only probe).
STUDIO_PRO_READ_TOOLS = ("glob", "list_modules", "ped_check_errors", "ped_find_document", "ped_get_schema",
                         "ped_list_folder", "ped_read_document", "pg_read_page", "query_handlers", "read_file")
STUDIO_PRO_WRITE_TOOLS = ("compile_java", "execute_handler", "ped_create_document", "ped_create_module",
                          "ped_delete_document", "ped_update_document", "pg_patch_page", "write_file")


class DoctorControlPlaneHealthTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="mxagile-cp-doctor-")
        self.root = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def install(self) -> None:
        target = self.root / ".mxagile/tools/control-plane"
        target.mkdir(parents=True)
        for name in ("guard.py", "enforcement.py", "child_contract.py", "control-plane-verdict.schema.json"):
            shutil.copy2(ROOT / "experiments/control-plane" / name, target / name)
        for name in ("run_events.py", "run-event.schema.json"):
            shutil.copy2(ROOT / "scripts" / name, target / name)
        (self.root / ".mxagile/schemas").mkdir(parents=True)
        shutil.copy2(ROOT / ".mxagile/schemas/delegation-handoff.schema.json", self.root / ".mxagile/schemas")
        subprocess.run(["pwsh", "-NoProfile", "-File", str(REGISTER), "-SettingsPath", str(self.root / ".claude/settings.json")],
                       capture_output=True, check=True)

    def test_project_without_control_plane_is_not_installed_and_never_live_verified(self):
        health = project_compatibility.control_plane_health(self.root)
        self.assertEqual(health["installation_health"], "NOT_INSTALLED")
        self.assertEqual(health["claude_registration"]["state"], "HOST_REGISTRATION_MISSING")
        self.assertEqual(health["live_host_verification"]["claude_code"], "NOT_VERIFIED")

    def test_installed_and_registered_is_healthy_but_still_not_live_verified(self):
        self.install()
        (self.root / ".mcp.json").write_text('{"mcpServers":{"concord-v2-mcp":{}}}', encoding="utf-8")
        health = project_compatibility.control_plane_health(self.root)
        self.assertEqual((health["installation_health"], health["potentially_active"]), ("HEALTHY", True))
        registration = health["claude_registration"]
        self.assertTrue(registration["fail_closed"] and registration["matcher_complete"] and registration["command_target_present"])
        self.assertEqual(health["live_host_verification"],
                         {"claude_code": "NOT_VERIFIED", "concord": "NOT_VERIFIED", "vscode_copilot": "HOST_UNSUPPORTED",
                          "reason": "LIVE_VERIFICATION_NOT_PERFORMED"})

    def test_missing_adapter_and_unknown_ownership_are_classified_not_generic(self):
        self.install()
        (self.root / ".mxagile/tools/control-plane/enforcement.py").unlink()
        health = project_compatibility.control_plane_health(self.root)
        self.assertEqual(health["installation_health"], "DEGRADED")
        self.assertIn("ADAPTER_FILE_MISSING", {item["code"] for item in health["findings"]})
        self.assertFalse(health["claude_registration"]["command_target_present"])
        (self.root / ".claude/settings.json").write_text("{not json", encoding="utf-8")
        self.assertEqual(project_compatibility.control_plane_health(self.root)["claude_registration"]["state"], "CONFIG_UNKNOWN_OWNERSHIP")

    def test_foreign_hooks_are_counted(self):
        self.install()
        settings_path = self.root / ".claude/settings.json"
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        settings["hooks"]["PreToolUse"].append({"matcher": "Bash", "hooks": [{"type": "command", "command": "audit"}]})
        settings_path.write_text(json.dumps(settings), encoding="utf-8")
        self.assertEqual(project_compatibility.control_plane_health(self.root)["claude_registration"]["foreign_pre_tool_groups"], 1)


class ObservedHostToolTests(Phase1BFixture):
    def test_observed_studio_pro_tools_are_classified_without_false_reads(self):
        for server in ("mendix-studio-pro", "concord-v2-mcp"):
            for tool in STUDIO_PRO_READ_TOOLS:
                with self.subTest(tool=tool, server=server):
                    self.assertEqual(self.hook(f"mcp__{server}__{tool}", {})["operation_class"], "READ")
            for tool in STUDIO_PRO_WRITE_TOOLS:
                with self.subTest(tool=tool, server=server):
                    self.assertEqual(self.hook(f"mcp__{server}__{tool}", {})["decision"], "deny")


class PublicationGateTests(Phase1BFixture):
    def test_push_is_never_authorized_by_an_implementing_wave(self):
        self.set_wave("implementing")
        self.assertEqual(self.hook("Write", {"file_path": "javascriptsource/orders/overview.js"})["decision"], "allow")
        for command in ("git push", "git push --force origin main", "git status && git push"):
            with self.subTest(command=command):
                result = self.hook("Bash", {"command": command})
                self.assertEqual((result["operation_class"], result["decision"]), ("PUBLICATION", "ask"))
                self.assertEqual(enforcement.hook_output(result)["hookSpecificOutput"]["permissionDecision"], "ask")
        self.assertEqual(self.hook("Bash", {"command": "git merge feature"})["decision"], "allow")
        event_types = [event["event_type"] for event in enforcement.run_events.read_events(self.root)["events"]]
        self.assertIn("delivery_authorized", event_types)
        self.assertEqual(event_types.count("publication_requested"), 3)


class ChildAcceptanceStateTests(AcceptanceFixture):
    def test_input_change_during_child_run_is_stale(self):
        handoff = self.visual_handoff(CLOSED)
        verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")])
        accepted, _ = self.save(handoff, verdict)
        self.assertEqual(accepted["acceptance"], "ACCEPTED")
        pass_event = next(event for event in enforcement.run_events.read_events(self.root)["events"]
                          if event["event_type"] == "gate_evaluated" and event["payload"].get("gate_result") == "PASS")
        self.write("input-resources/ui-ux/orders/index.html", "<html>orders REV-038</html>\n")
        saved, read = self.save(handoff, verdict)
        self.assertEqual((saved["acceptance"], saved["reusable"]), ("STALE", False))
        self.assertEqual((read["state"], read["reusable"]), ("STALE", False))
        events = enforcement.run_events.read_events(self.root)["events"]
        invalidation = next(event for event in events if event["event_type"] == "gate_invalidated")
        self.assertEqual(invalidation["correlation"]["gate_event_id"], pass_event["event_id"])
        self.assertIn(pass_event, events)

    def test_child_acceptance_events_keep_parent_correlation_and_execution_order(self):
        parent = "RUN-aabbccddeeff"
        handoff = self.visual_handoff(CLOSED, parent_run_id=parent)
        saved, _ = self.save(handoff, self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")]))
        self.assertEqual(saved["acceptance"], "ACCEPTED")
        events = [event for event in enforcement.run_events.read_events(self.root)["events"] if event["run_id"] == handoff["run_id"]]
        self.assertEqual([event["event_type"] for event in events],
                         ["verdict_received", "gate_evaluated", "child_completed", "child_accepted"])
        self.assertTrue(all(event["parent_run_id"] == parent for event in events))
        self.assertEqual([event["sequence"] for event in events], [1, 2, 3, 4])

    def test_successful_child_exit_is_not_delivery_success(self):
        cases = {
            "REJECTED": lambda h: None,
            "PARTIAL": lambda h: self.verdict(h, [self.evidence("default", "static"), self.evidence("modal_open", "static")], mode="static"),
            "NEEDS_HUMAN": lambda h: self.verdict(h, [self.evidence("default"), self.evidence("modal_open")], claim="needs_human"),
        }
        for expected, make_verdict in cases.items():
            with self.subTest(expected=expected):
                handoff = self.visual_handoff(CLOSED)
                saved, read = self.save(handoff, make_verdict(handoff))
                self.assertEqual((saved["state"], saved["acceptance"], saved["reusable"]), ("COMPLETED", expected, False))
                self.assertEqual((read["state"], read["reusable"]), (expected, False))


class VisualRoutingRealityTests(Phase1BFixture):
    PROMPT = ("Analysiere vollständig alle Lücken, Blocker, visuellen Unterschiede und dynamischen Zustände "
              "zwischen Mockup und App.")

    def test_reality_prompt_routes_to_runtime_verification_with_full_input_contract(self):
        route = child_contract.route_intent(self.PROMPT)
        self.assertEqual(route["capability"], "runtime_visual_verification")
        self.assertTrue(route["requires_runtime_evidence"])
        self.assertTrue({"mockup_revision", "page", "roles", "states", "evidence_destination"} <= set(route["required_inputs"]))
        self.assertTrue({"browser", "playwright"} <= set(route["required_tools"]))

    def test_without_runtime_evidence_the_gate_never_passes(self):
        handoff = self.visual_handoff(CLOSED)
        none = child_contract.evaluate_visual_gate(self.root, self.contract, self.verdict(handoff, []))
        static = child_contract.evaluate_visual_gate(self.root, self.contract, self.verdict(
            handoff, [self.evidence("default", "static"), self.evidence("modal_open", "static")], mode="static"))
        self.assertEqual((none["gate_result"], static["gate_result"]), ("UNAVAILABLE", "PARTIAL"))


if __name__ == "__main__":
    unittest.main()
