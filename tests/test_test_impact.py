"""Selection tests do not spawn installers or browsers."""

import importlib.util
import unittest
import json
import subprocess
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("impact_runner", Path(__file__).with_name("run-impact-tests.py"))
impact = importlib.util.module_from_spec(spec)
spec.loader.exec_module(impact)


class ImpactTests(unittest.TestCase):
    def test_doctor_is_narrow(self):
        plan = impact.select(["scripts/project_compatibility.py"])
        self.assertEqual(plan["suites"], ["test_parity_gallery.py", "test_project_status.py"])
        self.assertEqual(plan["tier"], 1)

    def test_board_includes_consumers(self):
        self.assertIn("test-board-authority.ps1", impact.select([".mxagile/board/board.js"])["suites"])

    def test_installer_requires_integration(self):
        self.assertEqual(impact.select(["scripts/install-core.ps1"])["tier"], 3)

    def test_delegation_policy_and_adapter_paths_are_targeted(self):
        paths = [
            ".mxagile/adapters/claude/agent-delegation.yaml",
            ".mxagile/delegation.yaml",
            ".mxagile/model-profiles.yaml",
            ".mxagile/policies/agent-delegation.md",
            "tests/fixtures/delegation/semantic-compatibility.json",
        ]
        plan = impact.select(paths)
        self.assertEqual(plan["tier"], 1)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-agent-delegation.ps1"])

    def test_c0_collector_paths_select_only_the_telemetry_fixture(self):
        plan = impact.select([
            "scripts/context_telemetry_model.py",
            "scripts/context_architecture_telemetry.py",
            "scripts/claude_jsonl_collector.py",
            "tests/test_context_architecture_telemetry.py",
        ])
        self.assertEqual(plan["tier"], 1)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-context-architecture-telemetry.ps1"])

    def test_c1_recipe_paths_select_only_the_runtime_resolver_suite(self):
        plan = impact.select([
            "scripts/Resolve-MxAgileMxcli.ps1",
            "scripts/mxcli_runtime_recipe.py",
            "tests/test_runtime_recipe.py",
            ".mxagile/policies/local-runtime-profile.md",
            ".mxagile/policies/development-runtime.md",
        ])
        self.assertEqual(plan["tier"], 1)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-mxcli-runtime-resolution.ps1"])

    def test_dependency_recovery_policy_selects_its_failure_suite(self):
        plan = impact.select([".mxagile/policies/runtime-dependency-recovery.md"])
        self.assertEqual(plan["tier"], 1)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-gradle-stall-diagnosis.ps1"])

    def test_runtime_configuration_policy_selects_its_behavior_suites(self):
        plan = impact.select([".mxagile/policies/runtime-configuration-reconciliation.md"])
        self.assertEqual(plan["tier"], 2)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], [
            "test-local-runtime-profile.ps1",
            "test-scope-aware-verification.ps1",
        ])

    def test_consolidated_policy_consumers_have_behavior_owners(self):
        plan = impact.select([
            ".claude/agents/mxagile-acceptance-agent.md",
            ".claude/agents/mxagile-implementation-agent.md",
            ".mxagile/GLOSSARY.yaml",
            ".mxagile/lifecycle.yaml",
            ".mxagile/policies/consistency-check.md",
            ".mxagile/policies/credential-discovery.md",
            ".mxagile/policies/runtime-startup-recovery.md",
            ".mxagile/policies/test-identity-lifecycle.md",
            ".mxagile/policies/test-staleness.md",
            ".mxagile/policies/test-workflow.md",
            ".mxagile/policies/verification-gap-taxonomy.md",
            "tests/fixtures/scope-aware-verification/fixture-H-runtime-config-discrepancy-diagnosed-before-identity-mutation.yaml",
        ])
        self.assertEqual(plan["tier"], 2)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], [
            "test-capabilities-resolver.ps1",
            "test-capability-discovery-routing.ps1",
            "test-credential-discovery.ps1",
            "test-documentation-consistency.ps1",
            "test-injection-contract.ps1",
            "test-managed-block.ps1",
            "test-mxcli-runtime-resolution.ps1",
            "test-platform-portability.ps1",
            "test-runtime-startup-recovery.ps1",
            "test-scope-aware-verification.ps1",
            "test-session-bootstrap.ps1",
            "test-verification-gap-taxonomy.ps1",
            "test-verification-lifecycle.ps1",
        ])

    def test_canonical_mxagile_readme_selects_documentation_consistency(self):
        plan = impact.select([".mxagile/README.md"])
        self.assertEqual(plan["tier"], 1)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-documentation-consistency.ps1"])

    def test_consolidated_policy_authorities_select_their_behavior_owners(self):
        plan = impact.select([
            ".mxagile/policies/runtime-strategy.md",
            ".mxagile/policies/verification-layers.md",
            ".mxagile/policies/gap-verification-repair.md",
        ])
        self.assertEqual(plan["tier"], 2)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], [
            "test-board-authority.ps1",
            "test-runtime-strategy.ps1",
            "test-ui-parity.ps1",
            "test-verification-lifecycle.ps1",
            "test_board_performance.py",
            "test_parity_gallery.py",
            "test_project_status.py",
        ])

    def test_generated_agent_projection_selects_projection_consumers(self):
        plan = impact.select([
            ".claude/agents/mxagile-ui-agent.md",
            ".claude/agents/mxagile-discovery-agent.md",
        ])
        self.assertEqual(plan["tier"], 2)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], [
            "test-capability-discovery-routing.ps1",
            "test-injection-contract.ps1",
            "test-managed-block.ps1",
            "test-platform-portability.ps1",
        ])

    def test_startup_injector_selects_its_routing_e2e_suite(self):
        plan = impact.select(["scripts/apply-project-agent-instructions.ps1"])
        self.assertEqual(plan["tier"], 3)
        self.assertEqual(plan["unmapped"], [])
        self.assertIn("test-capability-discovery-routing.ps1", plan["suites"])

    def test_operating_mode_policy_maps_to_c2_consumers(self):
        plan = impact.select([
            ".mxagile/policies/operating-mode.md",
            "scripts/Get-MxAgileCapabilities.ps1",
        ])
        self.assertEqual(plan["tier"], 1)
        self.assertEqual(plan["unmapped"], [])
        for suite in (
            "test-operating-mode-detection.ps1",
            "test-capabilities-resolver.ps1",
            "test-capability-discovery-routing.ps1",
        ):
            self.assertIn(suite, plan["suites"])

    def test_capability_catalog_and_orchestrator_have_distinct_consumers(self):
        capabilities = impact.select([".mxagile/capabilities.yaml", ".mxagile/config.yaml", ".mxagile/version.yaml"])
        self.assertEqual(capabilities["unmapped"], [])
        self.assertIn("test-capabilities-resolver.ps1", capabilities["suites"])
        self.assertIn("test-capability-discovery-routing.ps1", capabilities["suites"])
        orchestrator = impact.select([".mxagile/orchestrator.md"])
        self.assertEqual(orchestrator["tier"], 1)
        self.assertIn("test-ownership-guard.ps1", orchestrator["suites"])

    def test_delegated_result_and_handoff_contracts_are_targeted(self):
        plan = impact.select([
            ".mxagile/schemas/delegation-handoff.schema.json",
            ".mxagile/schemas/delegation-result.schema.json",
            ".mxagile/schemas/harness-adapter.schema.json",
            ".mxagile/schemas/routing-decision.schema.json",
            ".mxagile/schemas/context-epoch.schema.json",
            "scripts/Get-MxAgileCapabilities.ps1",
            "scripts/Get-MxAgileDelegationResult.ps1",
            "scripts/Save-MxAgileDelegationResult.ps1",
            "scripts/Save-MxAgileRoutingDecision.ps1",
            "scripts/Write-MxAgileEpochCheckpoint.ps1",
        ])
        self.assertEqual(plan["tier"], 2)
        self.assertEqual(plan["unmapped"], [])
        self.assertIn("test-agent-delegation.ps1", plan["suites"])
        self.assertIn("test-agent-delegation-results.ps1", plan["suites"])
        self.assertIn("test-context-lifecycle-rollover.ps1", plan["suites"])

    def test_delegation_mapping_does_not_downgrade_installer(self):
        self.assertEqual(impact.select(["scripts/install-core.ps1"])["tier"], 3)

    def test_baseline_fixture_helper_and_indexer_have_targeted_consumers(self):
        fixtures = impact.select(["tests/helpers/MxAgileBaselineFixture.ps1"])
        self.assertEqual(fixtures["tier"], 1)
        self.assertEqual(fixtures["unmapped"], [])
        self.assertEqual(fixtures["suites"], ["test-mxagile-dev-cli.ps1", "test-session-bootstrap.ps1", "test-startup-priority.ps1"])
        indexer = impact.select(["scripts/build_artifact_index.py"])
        self.assertEqual(indexer["tier"], 1)
        self.assertEqual(indexer["unmapped"], [])
        self.assertIn("test-wp10-artifact-schemas.ps1", indexer["suites"])

    def test_unknown_fails_closed(self):
        self.assertEqual(impact.select(["scripts/new-authority.py"])["tier"], 3)

    def test_selection_is_stable_and_deduplicated(self):
        paths = ["scripts/project_compatibility.py", "scripts/build_project_status.py"]
        plan = impact.select(paths)
        self.assertEqual(plan, impact.select(list(reversed(paths)) + paths))
        self.assertEqual(plan["suites"].count("test_project_status.py"), 1)

    def test_reconciliation_wrapper_does_not_repeat_python_suites(self):
        plan = impact.select(["tests/test-reconciliation-board.ps1", "scripts/reconcile_external_changes.py",
                              "scripts/serve_project_board.py", "tests/test_board_performance.py"])
        self.assertEqual(plan["unmapped"], [])
        self.assertNotIn("test-reconciliation-board.ps1", plan["suites"])
        for suite in ("test_external_change_reconciliation.py", "test_board_performance.py", "test_board_http.py"):
            self.assertEqual(plan["suites"].count(suite), 1)

    def test_full_runner_uses_supported_host_and_does_not_promote_targeted_runs(self):
        runner = (Path(__file__).parent / "run-all-tests.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("& pwsh -NoProfile -NonInteractive -File $testFile.FullName", runner)
        self.assertNotIn("powershell -NoProfile -File $testFile.FullName", runner)
        self.assertIn("$SelectedTests.Count -gt 0", runner)
        self.assertIn("TARGETED REGRESSION: PASS; FULL REGRESSION: NOT EXECUTED", runner)

    def test_fast_and_impact_runners_use_supported_host(self):
        runner = (Path(__file__).parent / "run-fast-tests.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("& pwsh -NoProfile -File $file.FullName", runner)
        self.assertIn("& pwsh -NoProfile -File $testFile.FullName", runner)
        self.assertNotIn("powershell -NoProfile -File", runner)
        source = (Path(__file__).parent / "run-impact-tests.py").read_text(encoding="utf-8-sig")
        self.assertIn('["pwsh", "-NoProfile", "-File"', source)
        self.assertIn('unittest.TextTestRunner(verbosity=2)', source)

    def test_skipped_scenario_is_incomplete_not_full_pass(self):
        with tempfile.TemporaryDirectory(prefix='mxagile-runner-') as directory:
            root = Path(directory)
            source = (Path(__file__).parent / 'run-all-tests.ps1').read_text(encoding='utf-8-sig')
            (root / 'run-all-tests.ps1').write_text(source, encoding='utf-8')
            (root / 'test-inventory.json').write_text(json.dumps([{'File': 'test-skipped.ps1', 'Tier': 0}]), encoding='utf-8')
            (root / 'test-skipped.ps1').write_text("Write-Host 'SKIP: fixture unavailable'\nexit 0\n", encoding='utf-8')
            result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-File', str(root / 'run-all-tests.ps1')], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn('REGRESSION: INCOMPLETE', result.stdout)
            self.assertNotIn('FULL REGRESSION: PASS', result.stdout)