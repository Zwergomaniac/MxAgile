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
    (("scripts/canonicalize_artifacts.py",), 2,
     ("test-wp10-artifact-schemas.ps1", "test-migration-fixtures.ps1", "test_git_index_integrity.py")),
    (("tests/test-inventory.json", "tests/run-all-tests.ps1"), 3, ("test_test_impact.py",)),
    (("scripts/git_index_integrity.py", "tests/test_git_index_integrity.py", "tests/test-git-index-integrity.ps1", "tests/test_git_recovery.py", "tests/test-git-recovery.ps1", ".mxagile/policies/safety-rules.md", ".mxagile/policies/commit-authority.md"),
     1, ("test_git_index_integrity.py", "test_git_recovery.py", "test-commit-authority.ps1")),
    (("scripts/project_compatibility.py", ".mxagile/policies/project-compatibility.md", "tests/test_project_status.py"),
    1, ("test_project_status.py", "test_parity_gallery.py")),
    ((".mxagile/board/*", "scripts/*project_status.py", "scripts/serve_project_board.py", "tests/test_parity_gallery.py", "tests/test-parity-gallery.ps1"),
     1, ("test_project_status.py", "test_parity_gallery.py", "test-board-authority.ps1")),
    (("*parity*", "*evidence*"), 2,
     ("test_project_status.py", "test-ui-parity.ps1", "test-verification-lifecycle.ps1")),
    (("scripts/install-core.ps1", "scripts/*setup*", "mxagile-setup*", ".mxagile/policies/update-contract.md"),
    3, ("test-capability-discovery-routing.ps1", "test-core-provenance.ps1", "test-local-updater.ps1")),
    (("scripts/apply-project-agent-instructions.ps1", "scripts/generate-mxagile-platform-skills.ps1", ".mxagile/agents/*", ".mxagile/skills/*"),
     2, ("test-managed-block.ps1", "test-platform-portability.ps1", "test-injection-contract.ps1")),
    ((".mxagile/schemas/*", "docs/injection-contract.md"), 2,
     ("test_project_status.py", "test-negative-schema.ps1", "test-injection-contract.ps1")),
    (("tests/run-impact-tests.py", "tests/test_test_impact.py", "tests/test-impact-tiers.ps1", "tests/README.md"), 1, ("test_test_impact.py",)),
    (("docs/*", "CHANGELOG.md"), 1, ("test-documentation-consistency.ps1",)),
)


def select(paths: list[str]) -> dict:
    suites = set()
    unknown = []
    tier = 0
    for path in sorted(set(paths)):
        matches = [rule for rule in RULES if any(fnmatch.fnmatchcase(path, pattern) for pattern in rule[0])]
        if not matches and path.startswith("tests/test-") and path.endswith(".ps1"):
            matches = [((), 1, (Path(path).name,))]
        if not matches:
            unknown.append(path)
        for _, depth, tests in matches:
            tier = max(tier, depth)
            suites.update(tests)
    return {"tier": max(tier, 3 if unknown else 0), "suites": sorted(suites), "unmapped": unknown}


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
    if python_suite.countTestCases() and not unittest.TextTestRunner(verbosity=1).run(python_suite).wasSuccessful():
        return 1
    for name in plan["suites"]:
        if name.endswith(".ps1"):
            tick = time.perf_counter()
            result = subprocess.run(["powershell", "-NoProfile", "-File", str(ROOT / "tests" / name)], cwd=ROOT)
            print(f"{name}: {time.perf_counter() - tick:.2f}s; exit={result.returncode}", flush=True)
            if result.returncode:
                return result.returncode
    print(f"Impact Regression: PASS ({time.perf_counter() - started:.2f}s)")
    print("Integration: covered by selected suites" if plan["tier"] >= 2 else "Integration: NOT REQUIRED")
    print("Full Regression: REQUIRED (central installer contract)" if plan["tier"] >= 3 else "Full Regression: NOT REQUIRED for this change; REQUIRED before release / cross-contract acceptance")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())