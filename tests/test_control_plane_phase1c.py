"""Phase 1C: shell/git classification, host parity, canonical spawn path and mandatory child acceptance."""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path

from test_control_plane_phase1b import CLOSED, Phase1BFixture, enforcement

ROOT = Path(__file__).resolve().parents[1]
SAVE = ROOT / "scripts" / "Save-MxAgileDelegationResult.ps1"
GET = ROOT / "scripts" / "Get-MxAgileDelegationResult.ps1"
WRITE_EPOCH = ROOT / "scripts" / "Write-MxAgileEpochCheckpoint.ps1"


def _pwsh(*args: str) -> dict:
    output = subprocess.run(["pwsh", "-NoProfile", "-File", *args], capture_output=True, text=True, check=True).stdout
    return json.loads(output.strip().splitlines()[-1])


class ShellClassificationTests(Phase1BFixture):
    def test_shell_and_git_matrix(self):
        cases = {
            "git status": "READ", "git -C . log --oneline": "READ", "git diff HEAD": "READ",
            "git commit -m x": "CONTROLLED_MUTATION", "git checkout main": "CONTEXT_INVALIDATING",
            "git reset --hard HEAD~1": "HIGH_RISK_MUTATION", "git clean -fdx": "HIGH_RISK_MUTATION",
            "git merge feature": "INTEGRATION_MUTATION", "git frobnicate": "HIGH_RISK_MUTATION",
            "echo x > javascriptsource/a.js": "IMPLEMENTATION_WRITE",
            "Set-Content -Path theme/web/main.scss -Value x": "IMPLEMENTATION_WRITE",
            "sed -i 's/a/b/' javascriptsource/a.js": "IMPLEMENTATION_WRITE",
            "echo x > planning/evidence/note.txt": "EVIDENCE_WRITE",
            "python -m pytest tests 2>&1": "VERIFICATION",
            "python -B .mxagile/tools/serve_project_board.py --port 0": "TOOLING_SERVICE",
            "ls -la > /dev/null": "READ", "cat a.txt | grep x": "READ",
            "git status && echo x > javascriptsource/a.js": "IMPLEMENTATION_WRITE",
            "rm": "IMPLEMENTATION_WRITE",
        }
        for command, expected in cases.items():
            with self.subTest(command=command):
                self.assertEqual(enforcement.classify_shell(self.root, command), expected)

    def test_high_risk_git_needs_delivery_authorization_while_reads_stay_open(self):
        self.assertEqual(self.hook("Bash", {"command": "git status"})["decision"], "allow")
        self.assertEqual(self.hook("Bash", {"command": "git reset --hard HEAD~1"})["decision"], "deny")


class HostParityTests(Phase1BFixture):
    def test_claude_and_concord_tool_names_get_the_same_guard_decision(self):
        studio = self.hook("mcp__mendix-studio-pro__create_page", {"name": "Orders"})
        concord = self.hook("mcp__concord-v2-mcp__apply_model_change", {"unit": "Orders"})
        self.assertEqual((studio["decision"], concord["decision"]), ("deny", "deny"))
        self.assertEqual(studio["reason"], concord["reason"])
        self.assertEqual(self.hook("mcp__concord-v2-mcp__concord_discover", {})["operation_class"], "READ")

    def test_spawn_handoff_must_be_at_the_canonical_acceptance_path(self):
        handoff = self.visual_handoff()
        self.write(".concord/elsewhere.json", json.dumps(handoff))
        moved = self.hook("Agent", {"subagent_type": "mxagile-ui-agent", "prompt": "MXAGILE_HANDOFF: .concord/elsewhere.json"})
        self.assertEqual(moved["decision"], "deny")
        self.assertIn("CHILD_HANDOFF_NOT_CANONICAL", moved["reason"])


class MandatoryAcceptanceTests(Phase1BFixture):
    def setUp(self) -> None:
        super().setUp()
        subprocess.run(["pwsh", "-NoProfile", "-File", str(WRITE_EPOCH), "-ProjectRoot", str(self.root), "-MissionId", "MISSION-2026-11-11-cp"],
                       capture_output=True, check=True)

    def save(self, handoff: dict, verdict: dict | None) -> tuple[dict, dict]:
        payload = {
            "schema_version": "1.1", "mission_id": "MISSION-2026-11-11-cp", "delegation_id": handoff["delegation_id"],
            "agent_type": handoff["agent_type"], "scope": handoff["scope"], "references": [], "conclusion": "child finished",
            "findings": [], "provenance": [], "affected_ids": [], "unknowns": [], "conflicts": [], "decision_candidates": [],
            "evidence_references": [], "model_profile": "MID", "model_resolution": handoff["model_resolution"],
        }
        if verdict is not None:
            self.write(".concord/evidence/visual/verdict.json", json.dumps(verdict))
            payload["verdict_reference"] = ".concord/evidence/visual/verdict.json"
        input_path = self.write(".concord/scratch/result-input.json", json.dumps(payload))
        saved = _pwsh(str(SAVE), "-ProjectRoot", str(self.root), "-InputFile", str(input_path))
        read = _pwsh(str(GET), "-ProjectRoot", str(self.root), "-DelegationId", handoff["delegation_id"])
        return saved, read

    def test_accepted_result_is_reusable(self):
        handoff = self.visual_handoff(CLOSED)
        saved, read = self.save(handoff, self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")]))
        self.assertEqual((saved["acceptance"], saved["reusable"]), ("ACCEPTED", True))
        self.assertEqual((read["state"], read["reusable"], read["result"]["acceptance"]["gate_result"]), ("CURRENT", True, "PASS"))

    def test_child_claim_lowers_but_never_raises(self):
        handoff = self.visual_handoff(CLOSED)
        saved, read = self.save(handoff, self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")], claim="needs_human"))
        self.assertEqual((saved["acceptance"], saved["reusable"]), ("NEEDS_HUMAN", False))
        self.assertEqual((read["state"], read["reusable"]), ("NEEDS_HUMAN", False))
        handoff = self.visual_handoff(CLOSED)
        saved, read = self.save(handoff, self.verdict(handoff, [self.evidence("default", "static"), self.evidence("modal_open", "static")], mode="static"))
        self.assertEqual(read["result"]["acceptance"]["gate_result"], "PARTIAL")

    def test_missing_output_or_forbidden_write_is_rejected(self):
        handoff = self.visual_handoff(CLOSED)
        saved, read = self.save(handoff, None)
        self.assertEqual((saved["acceptance"], read["reusable"]), ("REJECTED", False))
        self.assertIn("OUTPUT_MISSING", read["result"]["acceptance"]["finding_codes"])
        handoff = self.visual_handoff(CLOSED)
        self.write("theme/web/main.scss", "body {}\n")
        saved, _ = self.save(handoff, self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")]))
        self.assertEqual(saved["acceptance"], "REJECTED")

    def test_result_without_control_plane_handoff_keeps_legacy_contract(self):
        handoff = self.visual_handoff(CLOSED)
        (self.root / ".concord/delegation-handoffs/DELEGATION-V1.json").unlink()
        saved, read = self.save(handoff, None)
        self.assertEqual((saved["acceptance"], saved["reusable"], read["state"]), ("NOT_REQUIRED", True, "CURRENT"))


if __name__ == "__main__":
    unittest.main()
