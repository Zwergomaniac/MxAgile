"""Deterministic, sequential impact gates; full regression remains authoritative."""

from __future__ import annotations

import argparse
import ast
import fnmatch
import json
import subprocess
import sys
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES = (
    (("tests/test-reconciliation-board.ps1",), 1,
     ("test_external_change_reconciliation.py", "test_board_performance.py", "test_board_http.py")),
    ((".mxagile/policies/lifecycle-resync.md",), 1,
     ("test-startup-priority.ps1", "test-session-bootstrap.ps1", "test-managed-block.ps1", "test-core-provenance.ps1")),
        (("scripts/reconcile_external_changes.py", "scripts/reconciliation_git.py", "tests/test_external_change_reconciliation.py",
            "scripts/install-core.ps1", "scripts/apply-project-agent-instructions.ps1",
            ".mxagile/schemas/change-set.schema.json", ".mxagile/schemas/project-reconciliation-state.schema.json",
            ".mxagile/policies/external-change-reconciliation.md"),
         3, ("test_external_change_reconciliation.py", "test-core-provenance.ps1", "test-injection-contract.ps1")),
        (("tests/temp_cleanup.py",), 1,
            ("test_external_change_reconciliation.py", "test_git_index_integrity.py", "test_project_status.py", "test_board_performance.py")),
        (("tests/helpers/Remove-TestTempDirectory.ps1",), 1,
            ("test-bootstrap-generic.ps1", "test-core-installer.ps1", "test-injection-contract.ps1")),
    (("mxagile-dev.ps1", "tests/test-mxagile-dev-cli.ps1"), 1, ("test-mxagile-dev-cli.ps1",)),
    (("scripts/canonicalize_artifacts.py",), 2,
     ("test-wp10-artifact-schemas.ps1", "test-migration-fixtures.ps1", "test_git_index_integrity.py")),
    (("tests/test-inventory.json", "tests/run-all-tests.ps1", "tests/run-fast-tests.ps1", "tests/run-impact-tests.py", "tests/test_test_impact.py", "tests/test-impact-tiers.ps1", "CLAUDE.md"), 3, ("test_test_impact.py",)),
    (("scripts/git_index_integrity.py", "tests/test_git_index_integrity.py", "tests/test-git-index-integrity.ps1", "tests/test_git_recovery.py", "tests/test-git-recovery.ps1", ".mxagile/policies/safety-rules.md", ".mxagile/policies/commit-authority.md"),
     1, ("test_git_index_integrity.py", "test_git_recovery.py", "test-commit-authority.ps1")),
    (("scripts/project_compatibility.py", ".mxagile/policies/project-compatibility.md", "tests/test_project_status.py"),
    1, ("test_project_status.py", "test_parity_gallery.py")),
    ((".mxagile/board/*", "scripts/*project_status.py", "scripts/serve_project_board.py", "tests/test_parity_gallery.py", "tests/test-parity-gallery.ps1", "tests/test_board_performance.py", "docs/project-status-inventory.md", ".mxagile/policies/gap-verification-repair.md", ".mxagile/policies/project-compatibility.md"),
     1, ("test_project_status.py", "test_parity_gallery.py", "test_board_performance.py", "test-board-authority.ps1")),
    (("scripts/serve_project_board.py", "tests/test_board_http.py"), 1, ("test_board_http.py",)),
    (("*parity*", "*evidence*"), 2,
     ("test_project_status.py", "test-ui-parity.ps1", "test-verification-lifecycle.ps1")),
    (("scripts/install-core.ps1", "scripts/*setup*", "mxagile-setup*", ".mxagile/policies/update-contract.md"),
    3, ("test-capability-discovery-routing.ps1", "test-core-provenance.ps1", "test-local-updater.ps1")),
    (("scripts/apply-project-agent-instructions.ps1", "scripts/generate-mxagile-platform-skills.ps1", ".mxagile/agents/*", ".mxagile/skills/*"),
        2, ("test-managed-block.ps1", "test-platform-portability.ps1", "test-injection-contract.ps1",
            "test-capability-discovery-routing.ps1")),
    ((".claude/agents/*",), 2,
         ("test-managed-block.ps1", "test-platform-portability.ps1", "test-injection-contract.ps1",
            "test-capability-discovery-routing.ps1")),
    ((".mxagile/adapters/*/agent-delegation*.yaml", ".mxagile/delegation.yaml", ".mxagile/model-profiles.yaml",
     ".mxagile/policies/agent-delegation.md", "tests/fixtures/delegation/*"),
     1, ("test-agent-delegation.ps1",)),
    ((".mxagile/capabilities.yaml", ".mxagile/config.yaml", ".mxagile/version.yaml"), 1,
     ("test-agent-delegation.ps1", "test-capabilities-registry.ps1", "test-capabilities-resolver.ps1",
      "test-capability-discovery-routing.ps1", "test-core-provenance.ps1")),
    ((".mxagile/orchestrator.md",), 1,
     ("test-agent-delegation.ps1", "test-ownership-guard.ps1")),
    ((".mxagile/policies/consistency-check.md",), 1,
     ("test-capabilities-resolver.ps1", "test-capability-discovery-routing.ps1")),
    ((".mxagile/policies/credential-discovery.md",), 1,
     ("test-credential-discovery.ps1",)),
    ((".mxagile/policies/runtime-startup-recovery.md",), 1,
     ("test-runtime-startup-recovery.ps1",)),
    ((".mxagile/policies/test-identity-lifecycle.md",), 2,
     ("test-scope-aware-verification.ps1",)),
    ((".mxagile/policies/test-staleness.md", ".mxagile/policies/test-workflow.md"), 2,
     ("test-verification-lifecycle.ps1",)),
    ((".mxagile/policies/verification-gap-taxonomy.md",), 2,
     ("test-verification-gap-taxonomy.ps1", "test-scope-aware-verification.ps1")),
    ((".mxagile/policies/mission-completion.md",), 2,
     ("test-mission-completion.ps1",)),
    (("tests/fixtures/verification-lifecycle/*", "tests/test-verification-lifecycle.ps1"), 2,
     ("test-verification-lifecycle.ps1",)),
    ((".mxagile/lifecycle.yaml",), 2,
     ("test-session-bootstrap.ps1", "test-mxcli-runtime-resolution.ps1")),
    (("tests/fixtures/scope-aware-verification/fixture-H-runtime-config-discrepancy-diagnosed-before-identity-mutation.yaml",), 2,
     ("test-scope-aware-verification.ps1",)),
    ((".mxagile/schemas/delegation-handoff.schema.json", ".mxagile/schemas/delegation-result.schema.json",
        ".mxagile/schemas/harness-adapter.schema.json", ".mxagile/schemas/routing-decision.schema.json",
        ".mxagile/schemas/context-epoch.schema.json"),
     2, ("test-agent-delegation.ps1", "test-agent-delegation-results.ps1")),
    (("scripts/Get-MxAgileCapabilities.ps1",), 1,
     ("test-agent-delegation.ps1", "test-capabilities-resolver.ps1", "test-capability-discovery-routing.ps1")),
    (("scripts/Normalize-MxcliSessionStart.ps1",), 1,
     ("test-session-bootstrap.ps1",)),
        (('scripts/Resolve-MxAgileMxcli.ps1', 'scripts/mxcli_runtime_recipe.py', 'tests/test_runtime_recipe.py',
             '.mxagile/policies/local-runtime-profile.md', '.mxagile/policies/development-runtime.md'), 1,
            ('test-mxcli-runtime-resolution.ps1',)),
        (('.mxagile/policies/development-runtime.md',), 1,
         ('test-warm-local-loop.ps1',)),
        (('.mxagile/schemas/mxagile-project.schema.json',), 1,
         ('test-mxcli-runtime-resolution.ps1', 'test-local-runtime-profile.ps1')),
        (('.mxagile/policies/runtime-strategy.md',), 1,
         ('test-runtime-strategy.ps1',)),
        (('.mxagile/policies/verification-layers.md', '.mxagile/policies/gap-verification-repair.md'), 2,
         ('test_project_status.py', 'test-ui-parity.ps1', 'test-verification-lifecycle.ps1')),
    (('.mxagile/policies/runtime-dependency-recovery.md',), 1,
     ('test-gradle-stall-diagnosis.ps1',)),
    (('.mxagile/policies/runtime-configuration-reconciliation.md',), 2,
     ('test-local-runtime-profile.ps1', 'test-scope-aware-verification.ps1')),
    (('.claude/agents/mxagile-ui-agent.md', '.claude/agents/mxagile-discovery-agent.md'), 2,
      ('test-managed-block.ps1', 'test-platform-portability.ps1', 'test-injection-contract.ps1')),
     (('scripts/context_telemetry_model.py', 'scripts/context_architecture_telemetry.py',
        'scripts/claude_jsonl_collector.py', 'tests/test_context_architecture_telemetry.py'), 1,
      ('test-context-architecture-telemetry.ps1',)),
     (('.mxagile/policies/operating-mode.md',), 1,
      ('test-operating-mode-detection.ps1', 'test-capabilities-resolver.ps1',
        'test-capability-discovery-routing.ps1')),
        (("scripts/Get-MxAgileDelegationResult.ps1", "scripts/Save-MxAgileDelegationResult.ps1",
            "scripts/Save-MxAgileRoutingDecision.ps1"), 2,
     ("test-agent-delegation-results.ps1", "test-capability-discovery-routing.ps1")),
    (("scripts/Write-MxAgileEpochCheckpoint.ps1",), 2,
     ("test-agent-delegation-results.ps1", "test-context-lifecycle-rollover.ps1")),
    (("tests/helpers/MxAgileBaselineFixture.ps1",), 1,
     ("test-startup-priority.ps1", "test-session-bootstrap.ps1", "test-mxagile-dev-cli.ps1")),
    (("scripts/build_artifact_index.py",), 1,
     ("test-wp10-artifact-schemas.ps1", "test-artifact-trace-index.ps1", "test-graph-capability.ps1", "test-impact-resolver.ps1")),
    ((".mxagile/schemas/*", ".mxagile/templates/generic/ui-inventory/template.yaml", "docs/injection-contract.md"), 2,
     ("test_project_status.py", "test-negative-schema.ps1", "test-injection-contract.ps1")),
    (("tests/run-impact-tests.py", "tests/test_test_impact.py", "tests/test-impact-tiers.ps1", "tests/README.md"), 1, ("test_test_impact.py",)),
    (("docs/*", "CHANGELOG.md", ".mxagile/README.md", ".mxagile/GLOSSARY.yaml"), 1,
     ("test-documentation-consistency.ps1",)),
)


def select(paths: list[str]) -> dict:
    suites = set()
    selected_by: dict[str, set[tuple[str, tuple[str, ...]]]] = {}
    unknown = []
    tier = 0
    for path in sorted(set(paths)):
        matches = []
        for rule in RULES:
            patterns, depth, tests = rule
            matched_patterns = tuple(pattern for pattern in patterns if fnmatch.fnmatchcase(path, pattern))
            if matched_patterns:
                matches.append((depth, tests, matched_patterns))
        if not matches and path.startswith("tests/test-") and path.endswith(".ps1"):
            matches = [(1, (Path(path).name,), (path,))]
        if not matches:
            unknown.append(path)
        for depth, tests, matched_patterns in matches:
            tier = max(tier, depth)
            suites.update(tests)
            for test in tests:
                selected_by.setdefault(test, set()).add((path, matched_patterns))

    inventory = json.loads((ROOT / "tests/test-inventory.json").read_text(encoding="utf-8-sig"))
    full_suites = {entry["File"]: entry for entry in inventory}
    full_suites.update({path.name: full_suites.get(path.name, {}) for path in (ROOT / "tests").glob("test-*.ps1")})
    smoke = ROOT / "tests/smoke-test.ps1"
    if smoke.exists():
        full_suites.setdefault(smoke.name, {})

    exclusions_authoritative = bool(paths) and not unknown
    if exclusions_authoritative:
        no_selection_reason = "No matched impact rule selects this suite for the supplied changed paths."
    elif unknown:
        no_selection_reason = "No justified exclusion: an unmapped changed path requires the full release gate."
    else:
        no_selection_reason = "No changed paths were supplied; no impact exclusion decision was made."
    selected_evidence = {
        suite: [
            {"changed_path": path, "matched_patterns": list(patterns)}
            for path, patterns in sorted(evidence)
        ]
        for suite, evidence in sorted(selected_by.items())
    }
    not_selected = [
        {
            "suite": suite,
            "tier": metadata.get("Tier", "unknown"),
            "reason": no_selection_reason,
        }
        for suite, metadata in sorted(full_suites.items())
        if suite not in suites
    ]
    return {
        "tier": max(tier, 3 if unknown else 0),
        "suites": sorted(suites),
        "unmapped": unknown,
        "exclusions_authoritative": exclusions_authoritative,
        "selected_by": selected_evidence,
        "not_selected": not_selected,
    }


def changed_paths(base: str) -> list[str]:
    changed = subprocess.check_output(["git", "diff", "--name-only", base], cwd=ROOT, text=True).splitlines()
    untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard"], cwd=ROOT, text=True).splitlines()
    return sorted(set(changed + untracked))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--paths", nargs="+")
    parser.add_argument("--base", default="HEAD")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--tier", choices=("fast", "impact", "integration", "release"), default="impact")
    args = parser.parse_args()
    paths = args.paths if args.paths is not None else changed_paths(args.base)
    plan = select(paths)
    print(json.dumps({"paths": paths, **plan}, indent=2), flush=True)
    if args.list:
        return 0
    started = time.perf_counter()
    subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)
    for relative in paths:
        path = ROOT / relative
        if path.is_file() and path.suffix == ".py":
            ast.parse(path.read_text(encoding="utf-8-sig"), filename=relative)
        if path.is_file() and path.suffix == ".json":
            value = json.loads(path.read_text(encoding="utf-8-sig"))
            if path.name.endswith('.schema.json'):
                from jsonschema import Draft7Validator
                Draft7Validator.check_schema(value)
    powershell_paths = [path for path in paths if path.endswith(".ps1") and (ROOT / path).is_file()]
    if powershell_paths:
        command = "$failed = $false; foreach ($path in @(" + ",".join("'" + str(ROOT / path).replace("'", "''") + "'" for path in powershell_paths) + ")) { $tokens=$null; $errors=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors); if ($errors.Count) { $errors; $failed=$true } }; if ($failed) { exit 1 }"
        subprocess.run(["pwsh", "-NoProfile", "-Command", command], cwd=ROOT, check=True)
    print(f"Fast Gate: PASS ({time.perf_counter() - started:.2f}s)", flush=True)
    if args.tier == "fast":
        print("Impact Regression: NOT RUN; required tier:", plan["tier"])
        return 0
    if args.tier == "release":
        return subprocess.call(["pwsh", "-NoProfile", "-File", str(ROOT / "tests/run-all-tests.ps1")], cwd=ROOT)
    if plan["unmapped"]:
        print("Full Regression: REQUIRED (unmapped paths); use --tier release")
        return 2
    sys.path.insert(0, str(ROOT / "tests"))
    python_suite = unittest.TestSuite()
    for name in plan["suites"]:
        if name.endswith(".py"):
            python_suite.addTests(unittest.defaultTestLoader.discover(str(ROOT / "tests"), pattern=name))
    started = time.perf_counter()
    if python_suite.countTestCases() and not unittest.TextTestRunner(verbosity=2).run(python_suite).wasSuccessful():
        return 1
    for name in plan["suites"]:
        if name.endswith(".ps1"):
            tick = time.perf_counter()
            result = subprocess.run(["pwsh", "-NoProfile", "-File", str(ROOT / "tests" / name)], cwd=ROOT)
            print(f"{name}: {time.perf_counter() - tick:.2f}s; exit={result.returncode}", flush=True)
            if result.returncode:
                return result.returncode
    print(f"Impact Regression: PASS ({time.perf_counter() - started:.2f}s)")
    print("Integration: covered by selected suites" if plan["tier"] >= 2 else "Integration: NOT REQUIRED")
    print("Full Regression: REQUIRED (central installer contract)" if plan["tier"] >= 3 else "Full Regression: NOT REQUIRED for this change; REQUIRED before release / cross-contract acceptance")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())