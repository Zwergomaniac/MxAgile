"""Selection tests do not spawn installers or browsers."""

import importlib.util
import unittest
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

    def test_unknown_fails_closed(self):
        self.assertEqual(impact.select(["scripts/new-authority.py"])["tier"], 3)

    def test_selection_is_stable_and_deduplicated(self):
        paths = ["scripts/project_compatibility.py", "scripts/build_project_status.py"]
        plan = impact.select(paths)
        self.assertEqual(plan, impact.select(list(reversed(paths)) + paths))
        self.assertEqual(plan["suites"].count("test_project_status.py"), 1)

    def test_full_runner_uses_supported_host_and_does_not_promote_targeted_runs(self):
        runner = (Path(__file__).parent / "run-all-tests.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("& pwsh -NoProfile -File $testFile.FullName", runner)
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