"""Phase 1B: mandatory enforcement, visual gate, child transition contract and reality regressions."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path
from unittest import mock

import unittest

from test_control_plane_guard import AUTHORIZED, MISSION, GuardFixture, _git

GUARD_DIR = Path(__file__).resolve().parents[1] / "experiments" / "control-plane"
sys.path.insert(0, str(GUARD_DIR))
import child_contract  # noqa: E402
import enforcement  # noqa: E402

LIVE = {"operating_mode": "LIVE-SP-CURRENT", "project_identity_confirmed": True, "observed_at": "2026-11-11T10:00:00Z"}
CLOSED = {**LIVE, "operating_mode": "CLOSED-AUTONOM"}


class Phase1BFixture(GuardFixture):
    def setUp(self) -> None:
        super().setUp()
        self.write(".gitignore", ".concord/\n")
        self.write("input-resources/ui-ux/orders/index.html", "<html>orders REV-037</html>\n")
        self.write("docs/fixture/REQ-001.md", "Orders overview shows a filter.\n")
        self.write("docs/fixture/DEC-001.md", "Modal confirms deletion.\n")
        self.write("javascriptsource/orders/overview.js", "export const overview = 1;\n")
        _git(self.root, "add", "-A")
        _git(self.root, "commit", "-qm", "visual inputs")
        self.resync()
        self.contract = {
            "mockup": {"identity": "REV-037", "path": "input-resources/ui-ux/orders/index.html"},
            "requirements": [{"id": "REQ-001", "path": "docs/fixture/REQ-001.md"}],
            "decisions": [{"id": "DEC-001", "path": "docs/fixture/DEC-001.md"}],
            "page": {"identity": "Orders.OrderOverview", "path": "javascriptsource/orders/overview.js"},
            "implementation_paths": ["javascriptsource/orders/overview.js"],
            "roles": ["User"], "states": ["default", "modal_open"],
            "evidence_destination": ".concord/evidence/visual", "max_rounds": 2,
        }

    def hook(self, tool_name: str, tool_input: dict) -> dict:
        return enforcement.decide(self.root, {"tool_name": tool_name, "tool_input": tool_input, "cwd": str(self.root)})

    def visual_handoff(self, observations: dict = CLOSED) -> dict:
        facts = enforcement.guard.load_project_facts(self.root)
        handoff = child_contract.build_visual_handoff(
            facts, self.contract, agent_type="mxagile-ui-agent", delegation_id="DELEGATION-V1",
            route_decision_reference=".concord/routing-decisions/ROUTE-V1.json", parent_observations=observations)
        route = {
            "schema_version": "1.0", "mission_id": MISSION, "decision_id": "ROUTE-V1", "recorded_at": "2026-11-11T10:00:00Z",
            "session_identity": None, "work_package": handoff["delivery_context"]["work_package_id"],
            "requested_agent_type": "mxagile-ui-agent", "work_class": "bounded_semantic", "scope": handoff["scope"],
            "artifact_count": len(handoff["scope"]["paths"]), "semantic": True, "deterministic": False,
            "capability_state": "supported", "requested_profile": "MID", "route": "DELEGATE", "reason": "runtime visual verification",
            "fallback_reason": None, "delegation_attempted": False, "spawn_outcome": "pending", "delegation_id": "DELEGATION-V1",
            "result_reference": None, "main_consumed": False, "compaction_occurred": False, "result_reused": False,
            "stale_result_rejected": False, "batch_restarted": False, "source_fingerprints": handoff["source_fingerprints"],
        }
        self.write(".concord/routing-decisions/ROUTE-V1.json", json.dumps(route))
        self.write(".concord/delegation-handoffs/DELEGATION-V1.json", json.dumps(handoff))
        return handoff

    def evidence(self, state: str, layer: str = "runtime", role: str = "User") -> dict:
        relative = f".concord/evidence/visual/{role}-{state}-{layer}.png"
        path = self.write(relative, f"png {role} {state} {layer}")
        return {"role": role, "state": state, "kind": "screenshot", "layer": layer, "path": relative,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

    def verdict(self, handoff: dict, evidence: list[dict], *, claim: str = "pass", must=(), should=(), round_number: int = 1,
                mode: str = "runtime") -> dict:
        finding = lambda code: {"code": code, "summary": code.replace("_", " "), "disposition": "fail"}
        return {
            "schema_version": "1.0", "gate_id": "GATE-visual-orders", "gate_type": "visual_verification", "verdict": claim,
            "run_id": handoff["run_id"], "mission_id": MISSION, "wave_id": "W01", "producer": "mxagile-ui-agent",
            "input_references": [], "evidence_references": [], "must_findings": [finding(code) for code in must],
            "should_findings": [{**finding(code), "disposition": "advisory"} for code in should],
            "scope": {"summary": "visual", "paths": []}, "checked_roles": ["User"], "checked_states": ["default", "modal_open"],
            "created_at": "2026-11-11T10:00:00Z", "round": round_number,
            "visual": {"mockup_revision": "REV-037", "page": "Orders.OrderOverview", "html_first_source": "javascriptsource/orders/overview.js",
                       "route": "/p/orders", "roles": ["User"], "states": ["default", "modal_open"], "requirements": ["REQ-001"],
                       "decisions": ["DEC-001"], "verification_mode": mode, "evidence": evidence,
                       "input_fingerprint": child_contract.input_fingerprint(self.root, self.contract)},
        }


class EnforcementTests(Phase1BFixture):
    def test_reads_stay_lightweight_and_never_call_the_guard(self):
        with mock.patch.object(enforcement.guard, "load_project_facts", side_effect=AssertionError("guard called")):
            result = self.hook("Read", {"file_path": str(self.root / "README.md")})
            self.assertEqual(result["decision"], "allow")
            self.assertIsNone(enforcement.hook_output(result))
            self.assertEqual(self.hook("mcp__mendix-studio-pro__get_page", {})["operation_class"], "READ")

    def test_implementation_write_needs_an_implementing_wave(self):
        denied = self.hook("Write", {"file_path": "javascriptsource/orders/overview.js"})
        self.assertEqual((denied["decision"], denied["operation_class"]), ("deny", "IMPLEMENTATION_WRITE"))
        self.assertIn("MUTATION_PHASE_BLOCKED", denied["reason"])
        self.assertEqual(enforcement.hook_output(denied)["hookSpecificOutput"]["permissionDecision"], "deny")
        self.set_wave("implementing")
        allowed = self.hook("Write", {"file_path": "javascriptsource/orders/overview.js"})
        self.assertEqual(allowed["decision"], "allow")
        self.assertIn("MODEL_SCOPE_NOT_OBSERVABLE", {f["code"] for f in allowed["verdict"]["should_findings"]})
        self.assertEqual(allowed["event"]["type"], "delivery_authorized")

    def test_tool_classification_covers_host_paths(self):
        cases = {
            ("mcp__mendix-studio-pro__create_page", "{}"): "IMPLEMENTATION_WRITE",
            ("Bash", "./mxcli.exe exec mdlsource/w1.mdl -p Fixture.mpr"): "IMPLEMENTATION_WRITE",
            ("Bash", "pwsh ./mxagile-setup.ps1"): "FRAMEWORK_WRITE",
            ("Bash", "git commit -m x"): "CONTROLLED_MUTATION",
            ("Write", "planning/evidence/x.png"): "EVIDENCE_WRITE",
            ("Write", "planning/lifecycle/process-state.yaml"): "LIFECYCLE_WRITE",
            ("UnknownTool", ""): "IMPLEMENTATION_WRITE",
        }
        for (tool, value), expected in cases.items():
            tool_input = {"command": value} if tool == "Bash" else {"file_path": value}
            with self.subTest(tool=tool, value=value):
                self.assertEqual(enforcement.classify_tool_call(self.root, {"tool_name": tool, "tool_input": tool_input})[0], expected)

    def test_recovery_paths_stay_open_during_partial_update(self):
        self.write(".mxagile/state/update-transaction.json", json.dumps({"state": "PARTIAL_UPDATE"}))
        self.assertEqual(self.hook("Bash", {"command": "pwsh ./mxagile-setup-company-layer.ps1 -ResumeUpdate"})["decision"], "allow")
        self.set_wave("implementing")
        self.assertEqual(self.hook("Write", {"file_path": "javascriptsource/a.js"})["decision"], "deny")

    def test_unavailable_guard_fails_closed(self):
        with mock.patch.object(enforcement.guard, "load_project_facts", side_effect=RuntimeError("boom")):
            result = self.hook("Write", {"file_path": "javascriptsource/a.js"})
        self.assertEqual(result["decision"], "deny")
        self.assertIn("GUARD_UNAVAILABLE", result["reason"])

    def test_child_spawn_requires_a_validated_handoff(self):
        self.assertEqual(self.hook("Agent", {"subagent_type": "Explore", "prompt": "look"})["decision"], "allow")
        denied = self.hook("Agent", {"subagent_type": "mxagile-implementation-agent", "prompt": "build pages"})
        self.assertEqual(denied["decision"], "deny")
        self.assertIn("CHILD_HANDOFF_MISSING", denied["reason"])


class VisualGateTests(Phase1BFixture):
    def test_full_runtime_coverage_passes_with_non_blocking_should_findings(self):
        handoff = self.visual_handoff()
        verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")], should=["MINOR_SPACING"])
        gate = child_contract.evaluate_visual_gate(self.root, self.contract, verdict)
        self.assertEqual(gate["gate_result"], "PASS", gate)
        self.assertNotIn("wave", gate["allowed_consequence"].lower().split(" ")[0])

    def test_without_runtime_evidence_never_pass(self):
        handoff = self.visual_handoff()
        static = self.verdict(handoff, [self.evidence("default", "static"), self.evidence("modal_open", "static")], mode="static")
        self.assertEqual(child_contract.evaluate_visual_gate(self.root, self.contract, static)["gate_result"], "PARTIAL")
        none = self.verdict(handoff, [])
        self.assertEqual(child_contract.evaluate_visual_gate(self.root, self.contract, none)["gate_result"], "UNAVAILABLE")
        missing_state = self.verdict(handoff, [self.evidence("default")])
        self.assertEqual(child_contract.evaluate_visual_gate(self.root, self.contract, missing_state)["gate_result"], "PARTIAL")

    def test_must_findings_block_and_round_limit_escalates(self):
        handoff = self.visual_handoff()
        evidence = [self.evidence("default"), self.evidence("modal_open")]
        first = child_contract.evaluate_visual_gate(self.root, self.contract, self.verdict(handoff, evidence, must=["GAP_001"]))
        self.assertEqual((first["gate_result"], first["event"]["type"]), ("FAIL", "repair_round_started"))
        second = child_contract.evaluate_visual_gate(self.root, self.contract, self.verdict(handoff, evidence, must=["GAP_001"], round_number=2))
        self.assertEqual(second["gate_result"], "NEEDS_HUMAN")
        self.assertIn("ROUND_LIMIT", second["reasons"])

    def test_child_claim_cannot_raise_and_evidence_must_match(self):
        handoff = self.visual_handoff()
        evidence = [self.evidence("default"), self.evidence("modal_open")]
        lowered = self.verdict(handoff, evidence, claim="partial")
        self.assertEqual(child_contract.evaluate_visual_gate(self.root, self.contract, lowered)["gate_result"], "PARTIAL")
        self.write(evidence[0]["path"], "tampered")
        tampered = child_contract.evaluate_visual_gate(self.root, self.contract, self.verdict(handoff, evidence))
        self.assertEqual(tampered["gate_result"], "FAIL")

    def test_mockup_revision_change_makes_pass_stale_with_reason(self):
        handoff = self.visual_handoff()
        verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")])
        self.write("input-resources/ui-ux/orders/index.html", "<html>orders REV-038</html>\n")
        self.contract["mockup"]["identity"] = "REV-038"
        gate = child_contract.evaluate_visual_gate(self.root, self.contract, verdict)
        self.assertEqual(gate["gate_result"], "STALE")
        self.assertIn({"code": "MOCKUP_REVISION_CHANGED", "input": "mockup_revision:input-resources/ui-ux/orders/index.html",
                       "from": "REV-037", "to": "REV-038"}, gate["stale_reasons"])


class RealityRegressionTests(Phase1BFixture):
    def test_a_concord_html_first_build_without_valid_delivery_context(self):
        self.set_wave("implementing")
        self.write("src/unrelated.py", "x = 1\n")
        _git(self.root, "add", "-A")
        _git(self.root, "commit", "-qm", "context drift without re-sync")
        process_state = (self.root / "planning/lifecycle/process-state.yaml").read_bytes()
        intent = "Baue alle verlinkten Pages HTML-first."
        self.assertEqual(child_contract.route_intent(intent)["capability"], "static_analysis")
        decisions = [
            self.hook("Write", {"file_path": "javascriptsource/orders/overview.js"}),
            self.hook("mcp__mendix-studio-pro__create_page", {"name": "Orders"}),
            self.hook("Agent", {"subagent_type": "mxagile-implementation-agent", "prompt": intent}),
        ]
        self.assertEqual({d["decision"] for d in decisions}, {"deny"})
        self.assertIn("HEAD_STALE", decisions[0]["reason"])
        self.assertEqual(decisions[0]["recovery"], "resync")
        self.assertEqual((self.root / "planning/lifecycle/process-state.yaml").read_bytes(), process_state)
        self.write_yaml("planning/mission/mission-state.yaml", {
            "schema_version": 1, "mission_id": MISSION, "created_at": "2026-11-11", "objective": "x",
            "completion_boundary": "WAVE_IMPLEMENTATION_COMPLETE",
            "criteria": {"lifecycle_derived": {"implementation": {"required": True, "status": "pending"}}},
            "progress": {"mission": "active"}})
        self.resync()
        no_wave = self.hook("Write", {"file_path": "javascriptsource/orders/overview.js"})
        self.assertEqual((no_wave["decision"], no_wave["recovery"]), ("deny", "human_resolution"))
        self.assertIn("MISSION_WAVE_REQUIRED", no_wave["reason"])
        self.assertNotIn("W0", (self.root / "planning/lifecycle/process-state.yaml").read_text(encoding="utf-8").replace("W01", ""))

    def test_b_visual_gap_analysis_routes_to_runtime_verification(self):
        route = child_contract.route_intent("Vollständige Lücken-/Blocker-/Dynamik-Analyse Mockup vs. App.")
        self.assertEqual(route["capability"], "runtime_visual_verification")
        self.assertTrue(route["requires_runtime_evidence"])
        handoff = self.visual_handoff()
        spawn = self.hook("Agent", {"subagent_type": "mxagile-ui-agent", "prompt": "MXAGILE_HANDOFF: .concord/delegation-handoffs/DELEGATION-V1.json"})
        self.assertEqual(spawn["decision"], "allow", spawn.get("reason"))
        self.assertEqual(spawn["event"], {"type": "child_started", "run_id": handoff["run_id"], "operation_class": "CHILD_SPAWN"})
        without_runtime = child_contract.accept_child_result(self.root, handoff, self.verdict(handoff, []), self.contract)
        self.assertEqual((without_runtime["status"], without_runtime["gate"]["gate_result"]), ("PARTIAL", "UNAVAILABLE"))
        full = child_contract.accept_child_result(self.root, handoff, self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")]), self.contract)
        self.assertEqual((full["status"], full["gate"]["gate_result"]), ("ACCEPTED", "PASS"))

    def test_b_spawn_with_tampered_scope_or_lifecycle_write_class_is_denied(self):
        handoff = self.visual_handoff()
        handoff["write_classes"] = ["EVIDENCE_WRITE", "LIFECYCLE_WRITE"]
        self.write(".concord/delegation-handoffs/DELEGATION-V1.json", json.dumps(handoff))
        spawn = self.hook("Agent", {"subagent_type": "mxagile-ui-agent", "prompt": "MXAGILE_HANDOFF: .concord/delegation-handoffs/DELEGATION-V1.json"})
        self.assertEqual(spawn["decision"], "deny")
        self.assertIn("LIFECYCLE_AUTHORITY_DELEGATED", spawn["reason"])

    def test_c_forbidden_child_write_is_rejected_after_termination(self):
        handoff = self.visual_handoff()
        verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")])
        self.write("theme/web/main.scss", "body { color: red; }\n")
        self.write("javascriptsource/orders/overview.js", "export const overview = 2;\n")
        result = child_contract.accept_child_result(self.root, handoff, verdict, self.contract)
        self.assertEqual(result["status"], "REJECTED")
        self.assertIsNone(result["gate"])
        self.assertEqual({item["path"] for item in result["forbidden_changes"]}, {"theme/web/main.scss", "javascriptsource/orders/overview.js"})
        self.assertEqual(result["event"]["type"], "child_rejected")

    def test_c_live_studio_pro_model_scope_is_not_observable_and_never_pass(self):
        handoff = self.visual_handoff(LIVE)
        verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")])
        result = child_contract.accept_child_result(self.root, handoff, verdict, self.contract)
        self.assertEqual((result["status"], result["gate"]["gate_result"]), ("PARTIAL", "PARTIAL"))
        self.assertIn("MODEL_SCOPE_NOT_OBSERVABLE", {finding["code"] for finding in result["findings"]})

    def test_d_context_invalidation_after_authorized_start(self):
        changes = {
            "REQUIREMENT_CHANGED": lambda: self.write("docs/fixture/REQ-001.md", "Filter is optional.\n"),
            "WAVE_STATE_CHANGED": lambda: self.set_wave("verifying"),
            "UPDATE_NOT_READY": lambda: self.write(".mxagile/state/update-transaction.json", json.dumps({"state": "UPDATE_IN_PROGRESS"})),
        }
        for code, change in changes.items():
            with self.subTest(code=code):
                handoff = self.visual_handoff()
                verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")])
                change()
                result = child_contract.accept_child_result(self.root, handoff, verdict, self.contract)
                self.assertEqual(result["status"], "STALE")
                self.assertIn(code, {finding["code"] for finding in result["findings"]})
                self.assertIsNone(result["gate"])
                (self.root / ".mxagile/state/update-transaction.json").unlink(missing_ok=True)
                self.write("docs/fixture/REQ-001.md", "Orders overview shows a filter.\n")
                self.set_wave("ready")


if __name__ == "__main__":
    unittest.main()
