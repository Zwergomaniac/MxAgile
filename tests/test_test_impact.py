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
        self.assertEqual(plan["suites"], ["test_control_plane_phase1d.py", "test_control_plane_phase2.py", "test_parity_gallery.py", "test_project_status.py"])
        self.assertEqual(plan["tier"], 1)

    def test_board_includes_consumers(self):
        suites = impact.select([".mxagile/board/board.js"])["suites"]
        self.assertIn("test-board-authority.ps1", suites)
        self.assertIn("test_run_activity_board.py", suites)

    def test_installer_requires_integration(self):
        self.assertEqual(impact.select(["scripts/install-core.ps1"])["tier"], 3)

    def test_control_plane_experiment_selects_guard_and_baseline_upgrade_suites(self):
        plan = impact.select(["experiments/control-plane/guard.py", "experiments/control-plane/control-plane-verdict.schema.json"])
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-control-plane-upgrade-from-baseline.ps1", "test_control_plane_guard.py",
                                          "test_control_plane_phase1b.py", "test_control_plane_phase1c.py",
                                          "test_control_plane_phase1d.py", "test_control_plane_phase2.py"])

    def test_control_plane_hook_registration_selects_registration_and_upgrade_suites(self):
        plan = impact.select(["scripts/Register-MxAgileControlPlaneHook.ps1"])
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-control-plane-hook-registration.ps1", "test-control-plane-upgrade-from-baseline.ps1",
                                          "test_control_plane_phase1d.py"])

    def test_run_event_writer_selects_contract_persistence_board_and_upgrade_suites(self):
        plan = impact.select(["scripts/run_events.py", "scripts/run-event.schema.json"])
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["tier"], 2)
        self.assertEqual(plan["suites"], ["test-control-plane-upgrade-from-baseline.ps1", "test_control_plane_phase2.py",
                                          "test_run_activity_board.py", "test_run_events.py"])

    def test_post_compaction_resync_selects_resume_reconciliation_suites(self):
        plan = impact.select(["scripts/Invoke-MxAgilePostCompactionResync.ps1"])
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-context-transition-coordinator.ps1", "test_run_events.py"])

    def test_company_layer_update_lifecycle_selects_safety_suites_and_release_gate(self):
        plan = impact.select([
            "mxagile-setup-company-layer.ps1",
            "scripts/update-layer.ps1",
            ".mxagile/schemas/update-transaction.schema.json",
        ])
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["tier"], 3)
        self.assertTrue({
            "test-layer-update.ps1",
            "test-core-installer.ps1",
            "test-core-provenance.ps1",
            "test-startup-priority.ps1",
            "test-wp10-artifact-schemas.ps1",
        }.issubset(set(plan["suites"])))

    def test_spec_kit_traceability_paths_are_documentation_not_unknown_paths(self):
        paths = ["specs/001-board-redesign/spec.md", "specs/001-board-redesign/contracts/timeline-event.md",
                 "specs/001-board-redesign/reports/cs-2-bench.json", "specs/002-any-future-feature/tasks.md"]
        plan = impact.select(paths)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["tier"], 1)  # bounded documentation validation, no Full Release Gate
        self.assertEqual(plan["suites"], ["test-documentation-consistency.ps1"])
        mixed = impact.select(paths + ["docs/board-redesign-plan.md"])
        self.assertEqual((mixed["unmapped"], mixed["tier"]), ([], 1))

    def test_spec_kit_mapping_does_not_weaken_the_fail_closed_rule(self):
        for unknown in ("unknown-top-level/file.bin", "specsX/looks-similar.md", "my-specs/spec.md", "Specs/Upper.md"):
            plan = impact.select(["specs/001-board-redesign/spec.md", unknown])
            self.assertEqual(plan["unmapped"], [unknown], unknown)
            self.assertEqual(plan["tier"], 3, unknown)  # a genuinely unknown path still requires the full release gate

    def test_impact_router_changes_require_release_gate(self):
        plan = impact.select(["tests/run-impact-tests.py"])
        self.assertEqual(plan["tier"], 3)
        self.assertEqual(plan["suites"], ["test_test_impact.py"])

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

    def test_ui_and_artifact_lifecycle_policies_have_targeted_suites(self):
        expected = {
            ".mxagile/policies/design-contract-intake.md": {
                "test-design-contract-identity.ps1", "test-ac-faithfulness.ps1", "test-role-access-semantics.ps1",
                "test-wp2-lifecycle-extensions.ps1",
            },
            ".mxagile/policies/impact-resolution.md": {
                "test-revision-lifecycle.ps1", "test-verification-lifecycle.ps1", "test-impact-resolver.ps1",
            },
            ".mxagile/policies/mockup-analysis.md": {
                "test-mockup-materialization.ps1", "test-scope-aware-verification.ps1",
            },
        }
        for path, suites in expected.items():
            with self.subTest(path=path):
                plan = impact.select([path])
                self.assertEqual(plan["unmapped"], [])
                self.assertEqual(plan["tier"], 2)
                self.assertTrue(suites.issubset(set(plan["suites"])))

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

    def test_temp_cleanup_helpers_select_all_direct_consumers(self):
        python_helper = impact.select(["tests/temp_cleanup.py"])
        self.assertEqual(python_helper["tier"], 1)
        self.assertEqual(python_helper["unmapped"], [])
        self.assertEqual(python_helper["suites"], [
            "test_board_performance.py",
            "test_external_change_reconciliation.py",
            "test_git_index_integrity.py",
            "test_project_status.py",
        ])

        powershell_helper = impact.select(["tests/helpers/Remove-TestTempDirectory.ps1"])
        self.assertEqual(powershell_helper["tier"], 1)
        self.assertEqual(powershell_helper["unmapped"], [])
        self.assertEqual(powershell_helper["suites"], [
            "test-bootstrap-generic.ps1",
            "test-core-installer.ps1",
            "test-injection-contract.ps1",
        ])

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
        self.assertEqual(plan["suites"], ["test-mxcli-runtime-resolution.ps1", "test-warm-local-loop.ps1"])

    def test_development_runtime_contract_selects_recipe_and_warm_loop_suites(self):
        plan = impact.select([".mxagile/policies/development-runtime.md"])
        self.assertEqual(plan["unmapped"], [])
        self.assertIn("test-mxcli-runtime-resolution.ps1", plan["suites"])
        self.assertIn("test-warm-local-loop.ps1", plan["suites"])

    def test_project_runtime_schema_selects_c1_and_profile_suites(self):
        plan = impact.select([".mxagile/schemas/mxagile-project.schema.json"])
        self.assertEqual(plan["unmapped"], [])
        self.assertIn("test-mxcli-runtime-resolution.ps1", plan["suites"])
        self.assertIn("test-local-runtime-profile.ps1", plan["suites"])

    def test_parent_completion_policy_selects_mission_guard(self):
        plan = impact.select([".mxagile/policies/mission-completion.md"])
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-mission-completion.ps1"])

    def test_parent_resync_fixture_selects_verification_lifecycle_suite(self):
        plan = impact.select(["tests/fixtures/verification-lifecycle/fixture-L-child-complete-parent-resync.yaml"])
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-verification-lifecycle.ps1"])

    def test_sessionstart_normalizer_selects_its_production_backed_suite(self):
        plan = impact.select(["scripts/Normalize-MxcliSessionStart.ps1"])
        self.assertEqual(plan["tier"], 1)
        self.assertEqual(plan["unmapped"], [])
        self.assertEqual(plan["suites"], ["test-session-bootstrap.ps1"])

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
            "test_run_activity_board.py",
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

    def test_selection_plan_explains_selected_and_not_selected_suites(self):
        plan = impact.select(["scripts/project_compatibility.py"])
        self.assertTrue(plan["exclusions_authoritative"])
        self.assertIn("scripts/project_compatibility.py", [
            item["changed_path"] for item in plan["selected_by"]["test_project_status.py"]
        ])
        omitted = next(item for item in plan["not_selected"] if item["suite"] == "test-reconciliation-board.ps1")
        self.assertIn("No matched impact rule", omitted["reason"])

    def test_unmapped_path_prevents_authoritative_exclusion_claims(self):
        plan = impact.select(["scripts/project_compatibility.py", "scripts/new-authority.py"])
        self.assertFalse(plan["exclusions_authoritative"])
        omitted = next(item for item in plan["not_selected"] if item["suite"] == "test-reconciliation-board.ps1")
        self.assertIn("No justified exclusion", omitted["reason"])

    def test_empty_change_set_makes_no_exclusion_claim(self):
        plan = impact.select([])
        self.assertFalse(plan["exclusions_authoritative"])
        omitted = next(item for item in plan["not_selected"] if item["suite"] == "test-reconciliation-board.ps1")
        self.assertIn("No changed paths", omitted["reason"])

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