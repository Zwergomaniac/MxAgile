"""Experimental control-plane guard: pass, refusal, legacy, migration and re-sync contracts."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

import yaml
from jsonschema import Draft7Validator
from temp_cleanup import cleanup_temporary_directory

ROOT = Path(__file__).resolve().parents[1]
GUARD_DIR = ROOT / "experiments" / "control-plane"
_spec = importlib.util.spec_from_file_location("control_plane_guard", GUARD_DIR / "guard.py")
guard = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = guard
_spec.loader.exec_module(guard)
VERDICT_SCHEMA = json.loads((GUARD_DIR / "control-plane-verdict.schema.json").read_text(encoding="utf-8"))

MISSION = "MISSION-2026-11-11-cp"
AUTHORIZED = {"status": "confirmed", "reference": "user-message:2026-11-11T10:00"}


def _git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid", *args],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout.strip()


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class GuardFixture(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="mxagile-cp-")
        self.root = Path(self.temporary.name)
        shutil.copytree(ROOT / ".mxagile" / "schemas", self.root / ".mxagile" / "schemas")
        shutil.copy2(ROOT / ".mxagile" / "lifecycle.yaml", self.root / ".mxagile" / "lifecycle.yaml")
        self.write_yaml("planning/mission/mission-state.yaml", {
            "schema_version": 1, "mission_id": MISSION, "created_at": "2026-11-11",
            "objective": "Control plane fixture", "completion_boundary": "WAVE_IMPLEMENTATION_COMPLETE",
            "criteria": {"lifecycle_derived": {"implementation": {"required": True, "status": "pending"}}},
            "active_wave": "W01", "progress": {"mission": "active"},
        })
        self.set_wave("ready")
        self.write("planning/execution-waves.md", "# Execution Waves\n\n## Wave W01 - Fixture\n")
        _git(self.root, "init", "-q")
        _git(self.root, "add", "-A")
        _git(self.root, "commit", "-qm", "fixture")
        self.resync()

    def tearDown(self) -> None:
        cleanup_temporary_directory(self.temporary, expected_prefix="mxagile-cp-")

    def write(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def write_yaml(self, relative: str, value: dict) -> Path:
        return self.write(relative, yaml.safe_dump(value, sort_keys=False))

    def set_wave(self, phase: str, *, testability: bool = True, **extra) -> None:
        gates = {"gate_to_refinement": {"result": "passed"}, "gate_to_ready": {"result": "passed"}}
        if testability:
            gates["testability_gate"] = {"result": "passed"}
        self.write_yaml("planning/lifecycle/process-state.yaml", {"waves": {"W01": {"phase": phase, "gates": gates, **extra}}})

    def resync(self, when: datetime | None = None) -> None:
        moment = (when or datetime.now(timezone.utc)).isoformat(timespec="seconds")
        self.write_yaml(".concord/context-epoch.yaml", {
            "schema_version": "1.0",
            "mission": {"id": MISSION, "objective": "fixture", "status": "active"},
            "scope": {"project": str(self.root)},
            "lifecycle": {"current_phase": "ready", "active_context_epoch": "EPOCH-001"},
            "repository": {"branch": _git(self.root, "rev-parse", "--abbrev-ref", "HEAD"),
                           "commit": _git(self.root, "rev-parse", "--short", "HEAD"), "checkpoint_time": moment},
            "context": {"epoch_id": "EPOCH-001"},
        })

    def evaluate(self, request: dict) -> dict:
        result = guard.evaluate(self.root, {"mission_id": MISSION, "wave_id": "W01", **request})
        self.assertEqual(list(Draft7Validator(VERDICT_SCHEMA).iter_errors(result)), [])
        return result

    @staticmethod
    def codes(result: dict) -> set[str]:
        return {finding["code"] for finding in result["must_findings"]}

    def delivery_context(self, authorization: str, write_scope: list[str]) -> dict:
        return {
            "wave_id": "W01", "work_package_id": "WP-1", "project_root": str(self.root),
            "branch": _git(self.root, "rev-parse", "--abbrev-ref", "HEAD"), "worktree": None,
            "base_head": _git(self.root, "rev-parse", "HEAD"), "operating_mode": "CLOSED-AUTONOM",
            "authorization": authorization, "write_scope": write_scope, "forbidden_scope": [],
            "required_artifacts": [], "verification_expectations": [], "commit_expectation": "no_commit",
            "resync_conditions": [], "required_skills": [], "loaded_skills": [], "required_capabilities": [],
            "available_capabilities": [], "required_evidence_sources": [], "evidence_destinations": [],
            "output_artifacts": [], "requested_model_profile": "MID", "resolved_model": None,
            "effective_model": None, "effective_model_status": "not_observable",
        }


class TransitionTests(GuardFixture):
    def test_declared_transition_with_gates_and_authorization_passes(self):
        result = self.evaluate({"gate_type": "transition", "target_phase": "implementing", "authorization": AUTHORIZED})
        self.assertEqual(result["verdict"], "pass", result["must_findings"])

    def test_missing_user_authorization_needs_human(self):
        result = self.evaluate({"gate_type": "transition", "target_phase": "implementing"})
        self.assertEqual(result["verdict"], "needs_human")
        self.assertIn("USER_AUTHORIZATION_NOT_OBSERVED", self.codes(result))

    def test_undeclared_transition_fails(self):
        self.set_wave("discovery")
        result = self.evaluate({"gate_type": "transition", "target_phase": "implementing", "authorization": AUTHORIZED})
        self.assertEqual(result["verdict"], "fail")
        self.assertIn("TRANSITION_NOT_ALLOWED", self.codes(result))

    def test_legacy_wave_without_optional_testability_gate_is_tolerated(self):
        self.set_wave("ready", testability=False)
        result = self.evaluate({"gate_type": "transition", "target_phase": "implementing", "authorization": AUTHORIZED})
        self.assertEqual(result["verdict"], "pass", result["must_findings"])
        self.assertIn("LEGACY_GATE_NOT_RECORDED", {f["code"] for f in result["should_findings"]})

    def test_return_transition_needs_reason_and_scope(self):
        self.set_wave("implementing")
        result = self.evaluate({"gate_type": "transition", "target_phase": "refinement", "authorization": AUTHORIZED})
        self.assertEqual(result["verdict"], "needs_human")
        self.assertIn("RETURN_SCOPE_REQUIRED", self.codes(result))


class LifecycleIntegrityTests(GuardFixture):
    request = {"gate_type": "transition", "target_phase": "implementing", "authorization": AUTHORIZED}

    def test_partial_update_blocks_delivery_with_resume_recovery(self):
        self.write(".mxagile/state/update-transaction.json", json.dumps({"state": "PARTIAL_UPDATE"}))
        result = self.evaluate(self.request)
        self.assertEqual(result["verdict"], "fail")
        finding = next(f for f in result["must_findings"] if f["code"] == "UPDATE_NOT_READY")
        self.assertEqual(finding["recovery"], "resume")

    def test_migration_in_progress_and_partial_canonicalization_block_delivery(self):
        self.write_yaml(".mxagile/migration/state.yaml", {"status": "in_progress"})
        self.assertIn("MIGRATION_IN_PROGRESS", self.codes(self.evaluate(self.request)))
        self.write_yaml(".mxagile/migration/state.yaml", {"status": "complete", "artifact_canonicalization": "in_progress"})
        result = self.evaluate(self.request)
        self.assertEqual(result["verdict"], "fail")
        self.assertIn("MIGRATION_PARTIAL", self.codes(result))

    def test_hybrid_mode_after_completed_migration_is_valid(self):
        self.write_yaml(".mxagile/migration/state.yaml", {"status": "complete", "artifact_canonicalization": "pending"})
        result = self.evaluate(self.request)
        self.assertEqual(result["verdict"], "pass", result["must_findings"])
        self.assertIn("HYBRID_ARTIFACTS", {f["code"] for f in result["should_findings"]})

    def test_update_invalidates_context_until_resync(self):
        later = datetime.now(timezone.utc) + timedelta(minutes=5)
        self.write(".mxagile/state/last-update-result.json", json.dumps({"installed_at": later.isoformat()}))
        stale = self.evaluate(self.request)
        self.assertEqual(stale["verdict"], "unavailable")
        self.assertEqual(next(f for f in stale["must_findings"] if f["code"] == "CONTEXT_STALE_AFTER_UPDATE")["recovery"], "resync")
        self.resync(later + timedelta(seconds=1))
        self.assertEqual(self.evaluate(self.request)["verdict"], "pass")

    def test_project_without_mission_state_names_a_recovery_instead_of_schema_error(self):
        (self.root / "planning/mission/mission-state.yaml").unlink()
        result = self.evaluate(self.request)
        finding = next(f for f in result["must_findings"] if f["code"] == "CANONICAL_SOURCE_MISSING")
        self.assertEqual((result["verdict"], finding["recovery"]), ("needs_human", "human_resolution"))

    def test_stale_head_blocks(self):
        self.write("src/later.py", "x = 1\n")
        _git(self.root, "add", "-A")
        _git(self.root, "commit", "-qm", "later")
        self.assertIn("HEAD_STALE", self.codes(self.evaluate(self.request)))


class MutationTests(GuardFixture):
    def mutation(self, paths: list[str], **overrides) -> dict:
        request = {
            "gate_type": "mutation", "operation": "file_write", "authorization": AUTHORIZED,
            "scope": {"summary": "fixture", "paths": paths},
            "delivery_context": self.delivery_context("authorized_write", ["src/"]),
            "observations": {"operating_mode": "CLOSED-AUTONOM", "project_identity_confirmed": True},
        }
        request.update(overrides)
        return self.evaluate(request)

    def setUp(self) -> None:
        super().setUp()
        self.set_wave("implementing")

    def test_bounded_write_passes(self):
        self.assertEqual(self.mutation(["src/a.py"])["verdict"], "pass")

    def test_scope_escape_fails(self):
        result = self.mutation(["planning/lifecycle/process-state.yaml"])
        self.assertEqual(result["verdict"], "fail")
        self.assertIn("SCOPE_ESCAPE", self.codes(result))

    def test_wrong_phase_and_read_only_context_fail(self):
        self.set_wave("ready")
        result = self.mutation(["src/a.py"], delivery_context=self.delivery_context("read_only", ["src/"]))
        self.assertTrue({"MUTATION_PHASE_BLOCKED", "WRITE_AUTHORIZATION_MISSING"} <= self.codes(result))

    def test_model_write_requires_mode_compatible_route(self):
        result = self.mutation(["Module.Entity"], operation="model_write",
                               delivery_context=self.delivery_context("authorized_write", ["Module.*"]),
                               observations={"operating_mode": "CLOSED-AUTONOM", "project_identity_confirmed": True,
                                             "tool_route": {"id": "studio_pro_mcp", "state": "supported", "same_project": True}})
        self.assertIn("MODEL_TOOL_ROUTE_UNAVAILABLE", self.codes(result))


class DelegationTests(GuardFixture):
    def route_and_handoff(self, authorization: str, write_scope: list[str]) -> tuple[str, dict]:
        source = self.root / "planning/execution-waves.md"
        fingerprints = [{"path": "planning/execution-waves.md", "sha256": _sha(source)}]
        scope = {"summary": "analyze wave plan", "paths": ["planning/execution-waves.md"]}
        resolution = {"model_selection": "unknown", "profile_resolution": "unknown", "resolution": "not_requested",
                      "resolved_model": None, "requested_reasoning_effort": None, "fallback_used": False, "fallback_reason": None}
        route = {
            "schema_version": "1.0", "mission_id": MISSION, "decision_id": "ROUTE-1",
            "recorded_at": "2026-11-11T10:00:00Z", "session_identity": None, "work_package": "WP-1",
            "requested_agent_type": "analyst", "work_class": "bounded_semantic", "scope": scope, "artifact_count": 1,
            "semantic": True, "deterministic": False, "capability_state": "supported", "requested_profile": "MID",
            "route": "DELEGATE", "reason": "bounded analysis", "fallback_reason": None, "delegation_attempted": False,
            "spawn_outcome": "pending", "delegation_id": "DELEGATION-1", "result_reference": None,
            "main_consumed": False, "compaction_occurred": False, "result_reused": False,
            "stale_result_rejected": False, "batch_restarted": False, "source_fingerprints": fingerprints,
        }
        self.write(".concord/routing-decisions/ROUTE-1.json", json.dumps(route))
        handoff = {
            "schema_version": "1.3", "mission_id": MISSION,
            "delivery_context": self.delivery_context(authorization, write_scope),
            "delegation_id": "DELEGATION-1", "task": "Analyze", "agent_type": "analyst", "scope": scope,
            "authority_references": [], "artifact_paths": ["planning/execution-waves.md"],
            "source_fingerprints": fingerprints, "allowed_tools": ["read"], "forbidden_mutations": ["*"],
            "expected_result_schema": "delegation-result/1.1", "model_profile": "MID", "model_resolution": resolution,
        }
        return ".concord/routing-decisions/ROUTE-1.json", handoff

    def delegation(self, authorization: str, write_scope: list[str], visible: bool = True) -> dict:
        route, handoff = self.route_and_handoff(authorization, write_scope)
        return self.evaluate({"gate_type": "delegation", "route_decision_reference": route, "handoff": handoff,
                              "authorization": AUTHORIZED,
                              "observations": {"operating_mode": "CLOSED-AUTONOM", "spawn_tool_visible": visible,
                                               "project_identity_confirmed": True}})

    def test_bounded_read_only_delegation_passes(self):
        result = self.delegation("read_only", [])
        self.assertEqual(result["verdict"], "pass", result["must_findings"])

    def test_unobserved_spawn_tool_is_not_a_pass(self):
        self.assertEqual(self.delegation("read_only", [], visible=False)["verdict"], "fail")

    def test_child_cannot_receive_lifecycle_authority(self):
        self.set_wave("implementing")
        result = self.delegation("authorized_write", ["planning/lifecycle/process-state.yaml"])
        self.assertEqual(result["verdict"], "fail")
        self.assertIn("LIFECYCLE_AUTHORITY_DELEGATED", self.codes(result))

    def test_source_change_after_routing_invalidates_delegation(self):
        route, handoff = self.route_and_handoff("read_only", [])
        self.write("planning/execution-waves.md", "# Execution Waves\n\n## Wave W01 - Changed\n")
        result = self.evaluate({"gate_type": "delegation", "route_decision_reference": route, "handoff": handoff,
                                "observations": {"operating_mode": "CLOSED-AUTONOM", "spawn_tool_visible": True}})
        self.assertIn("SOURCE_FINGERPRINT_STALE", self.codes(result))


if __name__ == "__main__":
    unittest.main()
