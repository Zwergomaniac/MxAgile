"""Deterministic tests for the opt-in Board smoke (001-board-redesign CS-7).

Real-Board cases use an embedded fixture project; failure modes that must not depend on real
timing (hanging server, HTTP 503 without projection, STALE/PROJECTION_ERROR, project writes) use a
tiny stub Board. A missing browser is a legitimate environment state: the same tests then assert
UNAVAILABLE instead of PASS, and browser-only cases are skipped explicitly (never reported as PASS).
"""

from __future__ import annotations

import functools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

from temp_cleanup import cleanup_temporary_directory

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
import board_smoke
import build_project_status
import project_compatibility
import serve_project_board
from test_board_http import write_board_fixture

SMOKE = SCRIPTS / "board_smoke.py"
DOCTOR = SCRIPTS / "project_compatibility.py"
SERVER = SCRIPTS / "serve_project_board.py"
CACHE_GLOB = "mxagile-board-smoke-cache-*"

STUB_SOURCE = r'''
import argparse, json, os, socket, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

parser = argparse.ArgumentParser()
parser.add_argument("--project-root")
parser.add_argument("--port", type=int, default=0)
args = parser.parse_args()
mode = os.environ.get("STUB_MODE", "status503")
if os.environ.get("STUB_ENV_OUT"):
    keys = ("MXAGILE_BOARD_LEGACY_CACHE", "MXAGILE_BOARD_CACHE_DIR", "MXAGILE_BOARD_PROFILE")
    with open(os.environ["STUB_ENV_OUT"], "w", encoding="utf-8") as handle:
        json.dump({key: os.environ.get(key) for key in keys}, handle)
if os.environ.get("STUB_TOUCH"):
    with open(os.path.join(args.project_root, "planning", "stub-wrote.txt"), "w", encoding="utf-8") as handle:
        handle.write("written by the stub during the run")
if mode == "crash":
    sys.stderr.write("stub board crashed on purpose\n")
    sys.exit(3)
if mode == "hang":
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(5)
    print("MxAgile Board: http://127.0.0.1:%d/" % listener.getsockname()[1], flush=True)
    time.sleep(3600)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, code, body, content_type="application/json"):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if mode == "status503":
            return self.reply(503, json.dumps({"error": "status_unavailable", "reason": "RuntimeError"}))
        if self.path == "/api/status":
            with open(os.environ["STUB_STATUS_FILE"], encoding="utf-8") as handle:
                status = json.load(handle)
            status["projection_state"] = {
                "state": os.environ["STUB_PROJECTION_STATE"], "age_seconds": 1.0, "validated_age_seconds": 1.0,
                "reason": os.environ.get("STUB_PROJECTION_REASON") or None, "built_at_head": None, "rebuilding": False,
            }
            return self.reply(200, json.dumps(status))
        if self.path.startswith("/api/page-previews"):
            return self.reply(200, json.dumps({"availability": "available", "items": []}))
        self.reply(200, b"stub resource", "text/plain")

server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
print("MxAgile Board: http://127.0.0.1:%d/" % server.server_port, flush=True)
server.serve_forever()
'''


@functools.lru_cache(maxsize=1)
def browser_available() -> bool:
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as playwright:
            playwright.chromium.launch().close()
        return True
    except Exception:
        return False


def make_project(base: Path, name: str = "project", *, board_payload: bool = True, transform_board_js=None) -> Path:
    root = base / name
    root.mkdir(parents=True)
    write_board_fixture(root)
    if board_payload:
        shutil.copytree(ROOT / ".mxagile/board", root / ".mxagile/board")
        if transform_board_js is not None:
            script = root / ".mxagile/board/board.js"
            script.write_text(transform_board_js(script.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
    shutil.copytree(ROOT / ".mxagile/schemas", root / ".mxagile/schemas")
    (root / ".mxagile").mkdir(exist_ok=True)
    for args in (["init", "-q"], ["config", "user.name", "Fixture"], ["config", "user.email", "fixture@example.invalid"],
                 ["add", "--all"], ["commit", "-q", "-m", "fixture"]):
        subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)
    return root


def clean_environment(extra: dict | None = None) -> dict:
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("MXAGILE_BOARD_SMOKE", "STUB_")) and key != "MXAGILE_BOARD_LEGACY_CACHE"}
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    environment.update(extra or {})
    return environment


def run_smoke(root: Path, *extra: str, env: dict | None = None, strict: bool = True, timeout: float = 150.0):
    command = [sys.executable, "-B", str(SMOKE), "--project-root", str(root), "--format", "json", *extra]
    if strict:
        command.append("--strict-project-unchanged")
    started = time.perf_counter()
    completed = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace",
                               env=clean_environment(env), timeout=timeout, check=False)
    return completed.returncode, json.loads(completed.stdout), time.perf_counter() - started


def stage_results(report: dict) -> dict:
    return {stage["id"]: stage["result"] for stage in report["stages"]}


def remove_screenshots(report: dict) -> None:
    for shot in report["artifacts"]["failure_screenshots"]:
        path = Path(shot)
        path.unlink(missing_ok=True)
        try:
            path.parent.rmdir()
        except OSError:
            pass


class BoardSmokeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mxagile-board-smoke-test-")
        cls.base = Path(cls.temporary.name)
        cls.project = make_project(cls.base, "shared")
        cls.stub = cls.base / "stub_board.py"
        cls.stub.write_text(STUB_SOURCE, encoding="utf-8")
        status = build_project_status.build_status_summary(cls.project)
        cls.status_file = cls.base / "stub_status.json"
        cls.status_file.write_text(json.dumps(status), encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cleanup_temporary_directory(cls.temporary, expected_prefix="mxagile-board-smoke-test-")

    def stub_env(self, mode: str, **extra: str) -> dict:
        env = {"MXAGILE_BOARD_SMOKE_SERVER_SCRIPT": str(self.stub), "STUB_MODE": mode,
               "STUB_STATUS_FILE": str(self.status_file), "MXAGILE_BOARD_SMOKE_BROWSER": "none"}
        env.update(extra)
        return env

    # ------------------------------------------------------------------ real Board on the fixture
    def test_real_board_passes_or_is_unavailable_never_passes_without_browser(self) -> None:
        cache_dirs_before = set(Path(tempfile.gettempdir()).glob(CACHE_GLOB))
        shots_root = Path(tempfile.gettempdir()) / "mxagile-board-smoke"
        shots_before = set(shots_root.glob("*")) if shots_root.exists() else set()
        code, report, wall = run_smoke(self.project)
        self.assertEqual(report["check"], "board_smoke")
        self.assertEqual(report["route_list_version"], 3)
        if report["browser"]["available"]:
            self.assertEqual((report["result"], code), ("PASS", 0), report["failures"])
            self.assertEqual(report["routes_checked"], [route for route, _ in board_smoke.ROUTES])
            self.assertEqual(stage_results(report), {f"S{n}": "PASS" for n in range(7)})
        else:
            self.assertEqual((report["result"], code), ("UNAVAILABLE", 2))
            self.assertNotEqual(report["result"], "PASS")
        self.assertEqual(report["projection_state"], "FRESH")
        self.assertFalse([w for w in report["warnings"] if w.startswith("STATUS_SCHEMA_DEVIATION")],
                         "the fixture projection must conform to project-status.schema.json")
        self.assertIs(report["project_unchanged"], True)
        self.assertEqual(report["artifacts"]["failure_screenshots"], [])
        self.assertEqual(report["cleanup"], {"process_terminated": True, "port_closed": True, "cache_removed": True})
        self.assertFalse(board_smoke.port_is_open(report["environment"]["port"]))
        self.assertTrue(report["environment"]["cache_dir_isolated"] and report["environment"]["legacy_cache_env_removed"])
        self.assertEqual(set(Path(tempfile.gettempdir()).glob(CACHE_GLOB)), cache_dirs_before, "isolated cache must be removed")
        shots_after = set(shots_root.glob("*")) if shots_root.exists() else set()
        self.assertEqual(shots_after, shots_before, "routine runs must not create screenshots")
        # timing semantics: SLOW_RUN is visible above the preferred target and never fails an otherwise correct run
        slow = any(warning.startswith("SLOW_RUN") for warning in report["warnings"])
        self.assertEqual(slow, report["duration_seconds"] > board_smoke.TARGET_SECONDS)
        self.assertLess(report["duration_seconds"], 60.0)
        for key in ("startup_seconds", "first_status_seconds", "total_seconds", "cleanup_seconds"):
            self.assertIsNotNone(report["timings"][key], key)
        if report["browser"]["available"]:
            self.assertIsNotNone(report["timings"]["first_usable_page_seconds"])
            kinds = {item["kind"]: item["status"] for item in report["links_checked"] if item.get("status") is not None}
            self.assertEqual(kinds, {"source": 200, "reference": 200, "design_preview": 200, "parity_source": 200})
            self.assertTrue(all(item["match"] for item in report["consistency"]), report["consistency"])
            self.assertTrue(any("NOT claimed to be schema-valid" in note for note in report["notes"]))

    def test_script_errors_from_embedded_artifacts_are_not_board_failures(self) -> None:
        for hint in ("ReferenceError: x\n    at http://127.0.0.1:8851/design-preview-source/PAGE-X/:1:1",
                     "at http://127.0.0.1:8851/reference/input-resources/ui-ux/a.html:9:3",
                     "http://127.0.0.1:8851/page-artifact/PAGE-X/planning/evidence/a.md",
                     "http://127.0.0.1:8851/design-preview/PAGE-X/"):
            self.assertEqual(board_smoke.script_error_origin(hint), "artifact", hint)
        for hint in ("TypeError: y\n    at http://127.0.0.1:8851/board.js:10:5", "", None):
            self.assertEqual(board_smoke.script_error_origin(hint), "board", hint)

    def test_forced_missing_browser_is_unavailable_and_other_stages_still_run(self) -> None:
        code, report, _ = run_smoke(self.project, env={"MXAGILE_BOARD_SMOKE_BROWSER": "none"})
        self.assertEqual((report["result"], code), ("UNAVAILABLE", 2))
        results = stage_results(report)
        self.assertEqual([results[stage] for stage in ("S0", "S1", "S2", "S5")], ["PASS"] * 4)
        self.assertEqual([results[stage] for stage in ("S3", "S4", "S6")], ["UNAVAILABLE"] * 3)
        self.assertEqual(report["browser"]["reason"], "FORCED_NONE")
        self.assertFalse(report["browser"]["available"])
        self.assertEqual(report["failures"], [])

    @unittest.skipUnless(browser_available(), "no Playwright/Chromium: browser-only case skipped, not passed")
    def test_injected_javascript_error_fails_with_screenshot_and_diagnostics(self) -> None:
        project = make_project(self.base, "js-error", transform_board_js=lambda text: text + (
            "\nsetTimeout(function () { throw new Error('injected smoke failure'); }, 100);\n"))
        code, report, _ = run_smoke(project)
        try:
            self.assertEqual((report["result"], code), ("FAIL", 1))
            failure = next(item for item in report["failures"] if item["kind"] == "pageerror")
            self.assertIn("injected smoke failure", failure["message"])
            self.assertEqual(failure["stage"], "S3")
            shots = report["artifacts"]["failure_screenshots"]
            self.assertTrue(shots and all(Path(shot).is_file() for shot in shots))
            self.assertTrue(all(Path(shot).resolve().is_relative_to(Path(tempfile.gettempdir()).resolve()) for shot in shots))
            self.assertFalse(any(Path(shot).resolve().is_relative_to(project.resolve()) for shot in shots))
            self.assertIs(report["project_unchanged"], True)
            self.assertEqual(report["cleanup"]["port_closed"], True)
        finally:
            remove_screenshots(report)

    @unittest.skipUnless(browser_available(), "no Playwright/Chromium: browser-only case skipped, not passed")
    def test_required_v1_route_that_does_not_render_fails(self) -> None:
        project = make_project(self.base, "route-broken", transform_board_js=lambda text: text.replace(
            'sectionTitle("Waves & Workpackages"', 'sectionTitle("Wellen"'))
        code, report, _ = run_smoke(project)
        try:
            self.assertEqual((report["result"], code), ("FAIL", 1))
            self.assertIn("waves", {failure["route"] for failure in report["failures"] if failure["kind"] == "route_not_rendered"})
            self.assertNotIn("waves", report["routes_checked"])
            self.assertIn("decisions", report["routes_checked"], "other routes are still evaluated")
        finally:
            remove_screenshots(report)

    @unittest.skipUnless(browser_available(), "no Playwright/Chromium: browser-only case skipped, not passed")
    def test_page_hub_actions_fit_tiles_at_narrow_desktop_viewport(self) -> None:
        project = make_project(self.base, "page-hub-responsive")
        server = serve_project_board.ProjectBoardServer(project, project / ".mxagile/board", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            from playwright.sync_api import sync_playwright
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch()
                page = browser.new_page(viewport={"width": 1101, "height": 860})
                page.goto(f"http://127.0.0.1:{server.server_port}/#pages/PAGE-002", wait_until="networkidle")
                page.locator(".hub-tiles").wait_for()
                for width in (1101, 1200, 1440):
                    with self.subTest(viewport=width):
                        page.set_viewport_size({"width": width, "height": 860})
                        measurements = page.locator(".hub-tile .target-open").evaluate_all(
                            "elements => elements.map(element => {"
                            "const button = element.getBoundingClientRect();"
                            "const tile = element.closest('.hub-tile').getBoundingClientRect();"
                            "return {buttonLeft: button.left, buttonRight: button.right, tileLeft: tile.left, tileRight: tile.right};"
                            "})"
                        )
                        self.assertTrue(measurements)
                        self.assertTrue(all(item["buttonLeft"] >= item["tileLeft"] - 1 and item["buttonRight"] <= item["tileRight"] + 1 for item in measurements), measurements)
                        self.assertLessEqual(page.locator("html").evaluate("element => element.scrollWidth"), width + 1)
                browser.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    @unittest.skipUnless(browser_available(), "no Playwright/Chromium: browser-only case skipped, not passed")
    def test_older_board_payload_without_projection_display_warns_instead_of_failing(self) -> None:
        project = make_project(self.base, "old-payload", transform_board_js=lambda text: text.replace(
            "renderProjectionState();", "// projection display not present in this payload"))
        code, report, _ = run_smoke(project)
        self.assertEqual((report["result"], code), ("PASS", 0), report["failures"])
        self.assertTrue(any(warning.startswith("PROJECTION_NOT_DISPLAYED") for warning in report["warnings"]))
        self.assertFalse(any(item["name"] == "projection_state_visible" for item in report["consistency"]))

    def test_status_is_validated_against_the_core_schema_not_an_older_project_copy(self) -> None:
        self.assertTrue((board_smoke.core_schema_dir() / "project-status.schema.json").is_file())
        project = make_project(self.base, "old-schema")
        schema_path = project / ".mxagile/schemas/project-status.schema.json"
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        del schema["properties"]["projection_state"]  # what a project with a pre-CS-2 Core copy contains
        schema_path.write_text(json.dumps(schema), encoding="utf-8")
        subprocess.run(["git", "-C", str(project), "commit", "-aqm", "older schema copy"], check=True, capture_output=True)
        code, report, _ = run_smoke(project, env={"MXAGILE_BOARD_SMOKE_BROWSER": "none"})
        self.assertEqual(stage_results(report)["S2"], "PASS", report["failures"])
        self.assertEqual((report["result"], code), ("UNAVAILABLE", 2))

    # ------------------------------------------------------------------ start failures and bounded behaviour
    def test_project_without_board_payload_fails_before_any_server_is_started(self) -> None:
        project = make_project(self.base, "no-payload", board_payload=False)
        code, report, _ = run_smoke(project)
        self.assertEqual((report["result"], code), ("FAIL", 1))
        self.assertEqual(report["failures"][0]["kind"], "board_payload_missing")
        results = stage_results(report)
        self.assertEqual(results["S0"], "FAIL")
        self.assertTrue(all(results[stage] == "SKIPPED" for stage in ("S1", "S2", "S3", "S4", "S5", "S6")))
        self.assertIsNone(report["environment"]["port"])

    def test_board_that_cannot_start_fails_with_server_diagnostics(self) -> None:
        code, report, _ = run_smoke(self.project, env=self.stub_env("crash"))
        self.assertEqual((report["result"], code), ("FAIL", 1))
        failure = report["failures"][0]
        self.assertEqual((failure["stage"], failure["kind"]), ("S1", "server_exited"))
        self.assertIn("stub board crashed on purpose", failure["message"] + report["artifacts"].get("server_stderr_tail", ""))
        self.assertEqual(report["cleanup"]["process_terminated"], True)
        Path(report["artifacts"].get("server_stderr_file", "")).unlink(missing_ok=True)

    def test_status_503_without_projection_is_a_precise_failure_not_a_pass(self) -> None:
        legacy_proof = self.base / "stub-env.json"
        code, report, wall = run_smoke(
            self.project, "--timeout", "9",
            env=self.stub_env("status503", STUB_ENV_OUT=str(legacy_proof), MXAGILE_BOARD_LEGACY_CACHE="1"))
        self.assertEqual((report["result"], code), ("FAIL", 1))
        failure = next(item for item in report["failures"] if item["stage"] == "S2")
        self.assertEqual(failure["kind"], "status_503_no_projection")
        self.assertLess(wall, 20.0)
        seen = json.loads(legacy_proof.read_text(encoding="utf-8"))
        self.assertIsNone(seen["MXAGILE_BOARD_LEGACY_CACHE"], "the smoke must never enable the legacy cache fallback")
        self.assertIsNone(seen["MXAGILE_BOARD_PROFILE"])
        cache_dir = Path(seen["MXAGILE_BOARD_CACHE_DIR"]).resolve()
        self.assertTrue(cache_dir.is_relative_to(Path(tempfile.gettempdir()).resolve()))
        self.assertFalse(cache_dir.is_relative_to(self.project.resolve()))
        self.assertFalse(cache_dir.exists(), "isolated cache directory must be removed")
        self.assertEqual(report["cleanup"], {"process_terminated": True, "port_closed": True, "cache_removed": True})

    def test_hung_board_times_out_within_the_limit_and_leaves_nothing_behind(self) -> None:
        code, report, wall = run_smoke(self.project, "--timeout", "6", env=self.stub_env("hang"))
        self.assertEqual((report["result"], code), ("TIMEOUT", 3))
        self.assertLess(wall, 16.0, "the hard limit must also cover cleanup")
        self.assertLessEqual(report["duration_seconds"], 8.0)
        self.assertEqual(report["cleanup"]["process_terminated"], True)
        self.assertFalse(board_smoke.port_is_open(report["environment"]["port"]))
        self.assertTrue(any(failure["kind"] == "timeout" for failure in report["failures"]))

    # ------------------------------------------------------------------ projection_state semantics (CS-2)
    def test_projection_state_classification(self) -> None:
        classify = board_smoke.classify_projection
        self.assertEqual(classify({"state": "FRESH"}), ("OK", None))
        for state in ("STALE", "BUILDING"):
            verdict, message = classify({"state": state, "reason": "SOURCES_CHURNING"})
            self.assertEqual(verdict, "WARN")
            self.assertIn(state, message)
        self.assertEqual(classify({"state": "PROJECTION_ERROR"})[0], "FAIL")
        self.assertEqual(classify({"state": "SOMETHING_ELSE"})[0], "FAIL")
        self.assertEqual(classify(None)[0], "WARN")

    def test_stale_projection_is_reported_as_warning_but_does_not_fail(self) -> None:
        code, report, _ = run_smoke(self.project, env=self.stub_env(
            "status_ok", STUB_PROJECTION_STATE="STALE", STUB_PROJECTION_REASON="STARTUP_LAST_GOOD"))
        self.assertEqual(report["projection_state"], "STALE")
        self.assertEqual(stage_results(report)["S2"], "PASS")
        self.assertTrue(any(warning.startswith("PROJECTION_STALE") for warning in report["warnings"]))
        self.assertNotEqual(report["result"], "FAIL", report["failures"])
        self.assertEqual((report["result"], code), ("UNAVAILABLE", 2), "no browser was requested in this stub scenario")

    def test_schema_deviation_of_the_projection_is_a_visible_warning_not_a_failure(self) -> None:
        status = json.loads(self.status_file.read_text(encoding="utf-8"))
        status["deviating_root_key"] = True  # violates additionalProperties: false of the status schema
        deviating = self.base / "stub_status_deviating.json"
        deviating.write_text(json.dumps(status), encoding="utf-8")
        code, report, _ = run_smoke(self.project, env=self.stub_env(
            "status_ok", STUB_PROJECTION_STATE="FRESH", STUB_STATUS_FILE=str(deviating)))
        self.assertEqual(stage_results(report)["S2"], "PASS", report["failures"])
        warning = next(w for w in report["warnings"] if w.startswith("STATUS_SCHEMA_DEVIATION"))
        self.assertIn("deviating_root_key", warning)
        self.assertNotEqual(report["result"], "FAIL")

    def test_projection_error_state_fails(self) -> None:
        code, report, _ = run_smoke(self.project, env=self.stub_env("status_ok", STUB_PROJECTION_STATE="PROJECTION_ERROR"))
        self.assertEqual((report["result"], code), ("FAIL", 1))
        self.assertEqual(report["failures"][0]["kind"], "projection_error")

    # ------------------------------------------------------------------ project-unchanged semantics
    def test_project_modification_is_fail_in_strict_mode_and_warning_in_live_mode(self) -> None:
        project = make_project(self.base, "touched")
        env = self.stub_env("status_ok", STUB_PROJECTION_STATE="FRESH", STUB_TOUCH="1")
        code, strict, _ = run_smoke(project, env=env, strict=True)
        self.assertEqual((strict["result"], code), ("FAIL", 1))
        self.assertIs(strict["project_unchanged"], False)
        self.assertTrue(any(f["kind"] == "project_modified" and "planning/stub-wrote.txt" in f["message"] for f in strict["failures"]))
        (project / "planning" / "stub-wrote.txt").unlink()
        code, live, _ = run_smoke(project, env=env, strict=False)
        self.assertNotEqual(live["result"], "FAIL", live["failures"])
        self.assertIs(live["project_unchanged"], False)
        self.assertTrue(any(w.startswith("PROJECT_CHANGED_DURING_RUN") and "causality not established" in w for w in live["warnings"]))

    # ------------------------------------------------------------------ --port 0
    def test_port_zero_assigns_distinct_ports_and_the_ready_line_is_flushed(self) -> None:
        environment = clean_environment({"MXAGILE_BOARD_CACHE_DIR": str(self.base / "port-zero-cache")})
        environment.pop("PYTHONUNBUFFERED", None)  # no -u: the ready line must be flushed by the server itself
        processes = []
        try:
            for _ in range(2):
                processes.append(subprocess.Popen(
                    [sys.executable, "-B", str(SERVER), "--project-root", str(self.project), "--port", "0"],
                    env=environment, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                    text=True, encoding="utf-8"))
            ports = []
            for process in processes:
                line = process.stdout.readline()
                match = re.fullmatch(r"MxAgile Board: http://127\.0\.0\.1:(\d+)/\s*", line)
                self.assertIsNotNone(match, f"unexpected ready line: {line!r}")
                ports.append(int(match.group(1)))
            self.assertEqual(len(set(ports)), 2)
            self.assertTrue(all(port > 0 for port in ports))
            from urllib.request import urlopen
            for port in ports:
                with urlopen(f"http://127.0.0.1:{port}/index.html", timeout=20) as response:
                    self.assertEqual(response.status, 200)
        finally:
            for process in processes:
                board_smoke.kill_tree(process)
                if process.stdout is not None:
                    process.stdout.close()
        for port in ports:
            self.assertFalse(board_smoke.port_is_open(port))

    # ------------------------------------------------------------------ Doctor integration
    def doctor(self, project: Path, *extra: str, env: dict | None = None):
        completed = subprocess.run(
            [sys.executable, "-B", str(DOCTOR), "doctor", "--project-root", str(project), "--format", "json", *extra],
            capture_output=True, text=True, encoding="utf-8", errors="replace", env=clean_environment(env), timeout=150, check=False)
        return completed.returncode, json.loads(completed.stdout)

    def test_doctor_without_flag_never_runs_or_mentions_the_smoke(self) -> None:
        code, report = self.doctor(self.project)
        self.assertIn(code, (0, 1, 2))
        self.assertNotIn("board_smoke", report)
        self.assertEqual(report["stage"], "PROJECT_COMPATIBILITY_CHECKED")

    def test_doctor_exit_codes_with_explicit_smoke(self) -> None:
        baseline, _ = self.doctor(self.project)
        none = {"MXAGILE_BOARD_SMOKE_BROWSER": "none"}
        code, report = self.doctor(self.project, "--board-smoke", env=none)
        self.assertEqual(report["board_smoke"]["result"], "UNAVAILABLE")
        self.assertEqual(code, baseline, "UNAVAILABLE must not change the Doctor exit code unless the smoke is required")
        self.assertEqual(report["stage"], "PROJECT_COMPATIBILITY_CHECKED")
        code, report = self.doctor(self.project, "--require-board-smoke", env=none)
        self.assertEqual((report["board_smoke"]["result"], code), ("UNAVAILABLE", 4))
        broken = make_project(self.base, "doctor-broken", board_payload=False)
        broken_baseline, _ = self.doctor(broken)
        code, report = self.doctor(broken, "--board-smoke", env=none)
        self.assertEqual((report["board_smoke"]["result"], code), ("FAIL", 4))
        self.assertIn(broken_baseline, (0, 1, 2))

    def test_doctor_exit_code_mapping_table(self) -> None:
        mapping = project_compatibility.board_smoke_exit_code
        for doctor_code in (0, 1, 2):
            self.assertEqual(mapping(doctor_code, None, required=False), doctor_code)
            self.assertEqual(mapping(doctor_code, {"result": "PASS"}, required=True), doctor_code)
            self.assertEqual(mapping(doctor_code, {"result": "UNAVAILABLE"}, required=False), doctor_code)
            self.assertEqual(mapping(doctor_code, {"result": "UNAVAILABLE"}, required=True), 4)
            for failing in ("FAIL", "TIMEOUT", "ERROR"):
                self.assertEqual(mapping(doctor_code, {"result": failing}, required=False), 4)

    def test_doctor_repair_rejects_board_smoke_options(self) -> None:
        completed = subprocess.run(
            [sys.executable, "-B", str(DOCTOR), "repair", "--project-root", str(self.project), "--board-smoke"],
            capture_output=True, text=True, env=clean_environment(), timeout=60, check=False)
        self.assertEqual(completed.returncode, 2)
        self.assertIn("cannot be combined with repair", completed.stderr)


if __name__ == "__main__":
    unittest.main()
