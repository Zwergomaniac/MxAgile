"""Bounded, opt-in smoke check of the read-only MxAgile project Board (CS-7, contract v1).

The smoke starts the Board of ONE project on a loopback port chosen by the operating system,
checks the v1 route list in a headless browser plus a handful of representative links, and
reports a machine-readable result. It is a smoke check, not an end-to-end suite:

- it never starts a Mendix runtime, never performs visual parity and never crawls entities;
- it never writes into the project (the Board cache is redirected to a private temp directory);
- a missing browser is reported as UNAVAILABLE, never as PASS;
- the whole run is bounded by a hard deadline (default and maximum: 60 seconds) and cleans up
  every process it started.

Exit codes: 0 PASS, 1 FAIL, 2 UNAVAILABLE, 3 TIMEOUT/ERROR.

Test hooks (not part of the public contract): MXAGILE_BOARD_SMOKE_BROWSER=none forces "no browser";
MXAGILE_BOARD_SMOKE_SERVER_SCRIPT replaces the Board server script.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import urlopen

sys.dont_write_bytecode = True

SCHEMA_VERSION = 1
ROUTE_LIST_VERSION = 3
# Versioned v3 route list (v3: CS-6 information architecture NOW / DELIVERY / QUALITY / SYSTEM): (hash route, heading that proves the view rendered).
ROUTES = (
    ("overview", "Delivery at a glance"),
    ("timeline", "Project Timeline"),
    ("waves", "Waves & Workpackages"),
    ("requirements", "Requirements"),
    ("tasks", "Tasks"),
    ("verification", "Verification & Evidence"),
    ("pages", "Pages & Parity"),
    ("findings", "Findings"),
    ("decisions", "Decisions"),
    ("health", "Health & Diagnostics"),
    ("portfolio", "Portfolio"),
)
LOADING_TOKENS = (
    "LOADING PARITY EVIDENCE", "PARITY EVIDENCE NOT LOADED",
    "LOADING PAGE PREVIEW METADATA", "PAGE PREVIEW METADATA NOT LOADED",
    "Pages werden geladen", "Page wird geladen", "Verlauf wird geladen",
)
PROJECTION_LABELS = {"FRESH": "AKTUELL", "STALE": "VERALTET", "BUILDING": "BUILDING", "PROJECTION_ERROR": "PROJECTION_ERROR"}
MAX_TIMEOUT_SECONDS = 60.0
TARGET_SECONDS = 15.0
SERVER_START_SECONDS = 15.0
STATUS_STAGE_SECONDS = 25.0
SERVER_OVERLAY_KEYS = frozenset({"ui_settings", "reconciliation"})
SNAPSHOT_ROOTS = ("planning", "requirements", "specs", ".mxagile/state", ".mxagile/tools", ".mxagile/board", "scripts")
SNAPSHOT_FILES = ("mxagile-project.yaml", ".mxagile/version.yaml")
READY_PATTERN = re.compile(r"MxAgile Board: http://127\.0\.0\.1:(\d+)/")


class SmokeTimeout(Exception):
    def __init__(self, where: str, detail: str = "") -> None:
        super().__init__(where)
        self.where = where
        self.detail = detail


class StageFail(Exception):
    def __init__(self, kind: str, message: str, route: str | None = None) -> None:
        super().__init__(message)
        self.kind = kind
        self.message = message
        self.route = route

    def as_dict(self) -> dict:
        return {"route": self.route, "kind": self.kind, "message": self.message[:600]}


class Deadline:
    def __init__(self, seconds: float) -> None:
        self.end = time.monotonic() + seconds

    def remaining(self) -> float:
        return self.end - time.monotonic()

    def budget(self, cap: float) -> float:
        return max(0.0, min(cap, self.remaining()))

    def check(self, where: str) -> None:
        if self.remaining() <= 0:
            raise SmokeTimeout(where)


def core_schema_dir() -> Path:
    base = Path(__file__).resolve().parents[1]
    return base / "schemas" if base.name == ".mxagile" else base / ".mxagile" / "schemas"


ARTIFACT_ORIGIN_MARKERS = ("/design-preview/", "/design-preview-source/", "/reference/", "/page-artifact/")


def script_error_origin(origin_hint: str | None) -> str:
    """'artifact' when a script error was raised inside an embedded project artifact, else 'board'.

    The hint is the error stack or the console location URL (never the message text): errors from embedded reference project
    HTML must not be reported as Board-core failures.
    """
    hint = origin_hint or ""
    return "artifact" if any(marker in hint for marker in ARTIFACT_ORIGIN_MARKERS) else "board"


def classify_projection(projection: dict | None) -> tuple[str, str | None]:
    """Return (verdict, message): verdict is OK, WARN or FAIL (CS-2 projection_state semantics)."""
    if not isinstance(projection, dict) or "state" not in projection:
        return "WARN", "PROJECTION_STATE_ABSENT: status carries no projection_state"
    state = projection.get("state")
    if state == "FRESH":
        return "OK", None
    if state in ("STALE", "BUILDING"):
        reason = projection.get("reason") or "no reason reported"
        return "WARN", f"PROJECTION_{state}: {reason}"
    if state == "PROJECTION_ERROR":
        return "FAIL", "PROJECTION_ERROR: the Board reports that no usable projection could be built"
    return "FAIL", f"PROJECTION_STATE_UNKNOWN: {state!r}"


def project_snapshot(root: Path) -> dict[str, tuple]:
    """Cheap change witness for the project: Git status hash plus size/mtime of canonical roots."""
    state: dict[str, tuple] = {}
    if (root / ".git").exists():
        try:
            output = subprocess.run(
                ["git", "--no-optional-locks", "-C", str(root), "status", "--porcelain=v1", "-z", "--untracked-files=all"],
                capture_output=True, check=False, timeout=30,
            )
            state["!git-status"] = (hashlib.sha256(output.stdout).hexdigest(),)
        except (OSError, subprocess.SubprocessError):
            state["!git-status"] = ("UNAVAILABLE",)
    for relative in SNAPSHOT_FILES:
        path = root / relative
        if path.is_file():
            stat = path.stat()
            state[relative] = (stat.st_size, stat.st_mtime_ns)
    for relative in SNAPSHOT_ROOTS:
        base = root / relative
        if not base.is_dir():
            continue
        for directory, dirnames, filenames in os.walk(base):
            dirnames[:] = [name for name in dirnames if name != ".git"]
            for name in filenames:
                path = Path(directory) / name
                try:
                    stat = path.stat()
                except OSError:
                    continue
                state[path.relative_to(root).as_posix()] = (stat.st_size, stat.st_mtime_ns)
    return state


def diff_snapshots(before: dict, after: dict) -> list[str]:
    return sorted(key for key in set(before) | set(after) if before.get(key) != after.get(key))


def kill_tree(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(3)
        return
    except subprocess.TimeoutExpired:
        pass
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, check=False)
    else:
        process.kill()
    try:
        process.wait(3)
    except subprocess.TimeoutExpired:
        pass


def port_is_open(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.3):
            return True
    except OSError:
        return False


class BoardSmoke:
    def __init__(self, root: Path, *, timeout: float, include_reconciliation: bool, strict_unchanged: bool = False) -> None:
        self.root = root.resolve()
        self.strict_unchanged = strict_unchanged
        self.timeout = max(3.0, min(float(timeout), MAX_TIMEOUT_SECONDS))
        self.include_reconciliation = include_reconciliation
        self.started = time.monotonic()
        # Reserve part of the budget for cleanup so the HARD limit covers the whole run.
        self.deadline = Deadline(max(1.0, self.timeout - min(5.0, self.timeout * 0.4)))
        self.stages: list[dict] = []
        self.warnings: list[str] = []
        self.notes: list[str] = []
        self.timings: dict[str, float | None] = {
            "startup_seconds": None, "first_status_seconds": None, "first_usable_page_seconds": None,
            "browser_seconds": None, "browser_launch_seconds": None, "context_close_seconds": None, "driver_stop_seconds": None, "total_seconds": None, "cleanup_seconds": None,
            "snapshot_seconds": None,
        }
        self.port: int | None = None
        self.process: subprocess.Popen | None = None
        self.cache_dir: Path | None = None
        self.stderr_path: Path | None = None
        self.stdout_lines: list[str] = []
        self.status: dict | None = None
        self.page_previews: dict | None = None
        self.gallery: dict | None = None
        self.projection: dict | None = None
        self.browser: dict = {"available": False, "engine": None, "source": "none", "reason": None}
        self.screenshots: list[str] = []
        self.screenshot_dir: Path | None = None
        self.routes_checked: list[str] = []
        self.links_checked: list[dict] = []
        self.consistency: list[dict] = []
        self.snapshot_before: dict = {}
        self.project_unchanged: bool | None = None
        self.changed_paths: list[str] = []
        self.cleanup: dict = {"process_terminated": None, "port_closed": None, "cache_removed": None}
        self.project_fingerprint: str | None = None
        self.core_version: str | None = None
        self.result = "ERROR"
        self.error: str | None = None
        self._lock = threading.Lock()
        self._finished = False

    # ------------------------------------------------------------------ helpers
    @property
    def base(self) -> str:
        return f"http://127.0.0.1:{self.port}/"

    def stage(self, stage_id: str, function) -> dict:
        entry = {"id": stage_id, "result": "PASS", "seconds": 0.0, "failures": []}
        self.stages.append(entry)
        started = time.perf_counter()
        try:
            function(entry)
        except StageFail as failure:
            entry["result"] = "FAIL"
            entry["failures"].append(failure.as_dict())
        except SmokeTimeout as timeout:
            entry["result"] = "TIMEOUT"
            entry["failures"].append({"route": None, "kind": "timeout", "message": f"{timeout.where} {timeout.detail}".strip()})
            raise
        finally:
            entry["seconds"] = round(time.perf_counter() - started, 3)
        return entry

    def skip(self, stage_id: str, reason: str, result: str = "SKIPPED") -> None:
        self.stages.append({"id": stage_id, "result": result, "seconds": 0.0, "failures": [], "reason": reason})

    def http(self, path: str, *, per_request: float = 30.0) -> tuple[int, bytes, float]:
        started = time.perf_counter()
        limit = max(0.5, self.deadline.budget(per_request))
        try:
            with urlopen(self.base + path, timeout=limit) as response:
                body, code = response.read(), response.status
        except HTTPError as error:
            body, code = error.read(), error.code
            error.close()
        except (URLError, TimeoutError, socket.timeout, ConnectionError, OSError) as error:
            if self.deadline.remaining() <= 0:
                raise SmokeTimeout(f"GET {path}", "request did not finish before the deadline") from None
            raise StageFail("request_failed", f"GET {path}: {type(error).__name__}", None) from None
        return code, body, round(time.perf_counter() - started, 3)

    def screenshot(self, page, name: str) -> None:
        if len(self.screenshots) >= 3:
            return
        try:
            if self.screenshot_dir is None:
                self.screenshot_dir = Path(tempfile.gettempdir()) / "mxagile-board-smoke" / f"{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
                self.screenshot_dir.mkdir(parents=True, exist_ok=True)
            target = self.screenshot_dir / f"{re.sub(r'[^A-Za-z0-9._-]', '_', name)}.png"
            page.screenshot(path=str(target))
            self.screenshots.append(str(target))
        except Exception:  # evidence capture must never mask the real failure
            pass

    # ------------------------------------------------------------------ stages
    def s0_preflight(self, entry: dict) -> None:
        if not (self.root / ".mxagile" / "board" / "index.html").is_file():
            raise StageFail("board_payload_missing", "Project has no .mxagile/board/index.html payload")
        try:
            import yaml  # noqa: F401
        except ImportError:
            raise StageFail("python_dependency_missing", "PyYAML is not installed (see .mxagile/tools/requirements.txt)") from None
        server = self.server_script()
        if not server.is_file():
            raise StageFail("board_server_missing", f"Board server script not found: {server}")
        self.snapshot_before = project_snapshot(self.root)

    def server_script(self) -> Path:
        override = os.environ.get("MXAGILE_BOARD_SMOKE_SERVER_SCRIPT")
        return Path(override) if override else Path(__file__).resolve().parent / "serve_project_board.py"

    def s1_start_server(self, entry: dict) -> None:
        self.cache_dir = Path(tempfile.mkdtemp(prefix="mxagile-board-smoke-cache-"))
        stderr_handle = tempfile.NamedTemporaryFile(prefix="mxagile-board-smoke-stderr-", suffix=".log", delete=False)
        self.stderr_path = Path(stderr_handle.name)
        environment = {key: value for key, value in os.environ.items()
                       if key not in ("MXAGILE_BOARD_LEGACY_CACHE", "MXAGILE_BOARD_PROFILE")}
        environment.update({
            "MXAGILE_BOARD_CACHE_DIR": str(self.cache_dir),
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONUNBUFFERED": "1",
        })
        command = [sys.executable, "-B", "-u", str(self.server_script()), "--project-root", str(self.root), "--port", "0"]
        options: dict = {"env": environment, "stdout": subprocess.PIPE, "stderr": stderr_handle, "stdin": subprocess.DEVNULL,
                         "text": True, "encoding": "utf-8", "errors": "replace", "bufsize": 1}
        if os.name == "nt":
            options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        else:
            options["start_new_session"] = True
        started = time.perf_counter()
        self.process = subprocess.Popen(command, **options)
        stderr_handle.close()

        def pump() -> None:
            assert self.process is not None and self.process.stdout is not None
            for line in self.process.stdout:
                self.stdout_lines.append(line.rstrip("\n"))

        threading.Thread(target=pump, name="board-smoke-stdout", daemon=True).start()
        limit = self.deadline.budget(SERVER_START_SECONDS)
        waited_until = time.monotonic() + limit
        while time.monotonic() < waited_until:
            for line in list(self.stdout_lines):
                match = READY_PATTERN.search(line)
                if match:
                    self.port = int(match.group(1))
                    self.timings["startup_seconds"] = round(time.perf_counter() - started, 3)
                    return
            if self.process.poll() is not None:
                break
            time.sleep(0.05)
        tail = ""
        if self.stderr_path and self.stderr_path.exists():
            tail = self.stderr_path.read_text(encoding="utf-8", errors="replace")[-400:].strip()
        if self.process.poll() is not None:
            raise StageFail("server_exited", f"Board exited with code {self.process.returncode} before it was ready. {tail}")
        if self.deadline.remaining() <= 0:
            raise SmokeTimeout("server start", "no ready line before the deadline")
        raise StageFail("server_start_timeout", f"Board printed no ready line within {limit:.0f}s. {tail}")

    def s2_api(self, entry: dict) -> None:
        status_deadline = self.deadline.budget(STATUS_STAGE_SECONDS)
        stage_end = time.monotonic() + status_deadline
        first_call = time.perf_counter()
        last_503: str | None = None
        while True:
            self.deadline.check("GET api/status")
            code, body, seconds = self.http("api/status", per_request=max(1.0, stage_end - time.monotonic()))
            if code == 200:
                self.timings["first_status_seconds"] = round(time.perf_counter() - first_call, 3)
                try:
                    self.status = json.loads(body)
                except ValueError:
                    raise StageFail("status_invalid_json", "GET api/status returned invalid JSON") from None
                break
            if code == 503:
                last_503 = body[:200].decode("utf-8", errors="replace")
                if time.monotonic() >= stage_end - 0.6:
                    raise StageFail("status_503_no_projection",
                                    f"GET api/status stayed HTTP 503 for {status_deadline:.0f}s: no usable projection could be built ({last_503})")
                time.sleep(0.5)
                continue
            raise StageFail("status_http_error", f"GET api/status returned HTTP {code}")
        status = self.status or {}
        self.project_fingerprint = status.get("source_fingerprint")
        self.core_version = (status.get("project") or {}).get("core_version")
        self.projection = status.get("projection_state") if isinstance(status.get("projection_state"), dict) else None
        verdict, message = classify_projection(self.projection)
        if verdict == "FAIL":
            raise StageFail("projection_error", message or "projection failed")
        if verdict == "WARN" and message:
            self.warnings.append(message)
        self.validate_status_schema(status)
        code, body, _ = self.http("api/page-previews")
        if code != 200:
            raise StageFail("page_previews_http_error", f"GET api/page-previews returned HTTP {code}")
        self.page_previews = json.loads(body)
        items = (self.page_previews or {}).get("items") or []
        if items:
            page_id = sorted(item["page_id"] for item in items)[0]
            code, body, _ = self.http(f"api/gallery?screen_id={quote(page_id)}")
            if code != 200:
                raise StageFail("gallery_http_error", f"GET api/gallery?screen_id={page_id} returned HTTP {code}")
            self.gallery = json.loads(body)
        if self.include_reconciliation:
            code, _, _ = self.http("api/reconciliation", per_request=30.0)
            if code != 200:
                raise StageFail("reconciliation_http_error", f"GET api/reconciliation returned HTTP {code}")

    def validate_status_schema(self, status: dict) -> None:
        # The schema must come from the same Core as the Board server that produced the status; a project may
        # carry an older installed copy of the schema (same rule as SCHEMA_ROOT in project_compatibility.py).
        schema_path = core_schema_dir() / "project-status.schema.json"
        if not schema_path.is_file():
            self.warnings.append("SCHEMA_UNAVAILABLE: project-status.schema.json not found; status contract not validated")
            return
        # The HTTP payload carries a server overlay (`ui_settings`) that project-status.schema.json
        # does not describe, and a lazily loaded `reconciliation` placeholder with an extra `availability`
        # field (pre-existing, BRD-F-44); the canonical projection itself is validated.
        projection = {key: value for key, value in status.items() if key not in SERVER_OVERLAY_KEYS}
        self.notes.append("canonical projection validated against project-status.schema.json without the server overlay keys "
                          + ", ".join(sorted(SERVER_OVERLAY_KEYS))
                          + "; the complete /api/status response is NOT claimed to be schema-valid (BRD-F-44, deferred)")
        try:
            import jsonschema
            schema = json.loads(schema_path.read_text(encoding="utf-8-sig"))
            errors = sorted(jsonschema.Draft7Validator(schema).iter_errors(projection), key=lambda error: list(error.path))
        except ImportError:
            self.warnings.append("SCHEMA_UNAVAILABLE: jsonschema not installed; status contract not validated")
            return
        except (OSError, ValueError):
            self.warnings.append("SCHEMA_UNAVAILABLE: status schema unreadable; status contract not validated")
            return
        if errors:
            # A deviation between the served projection and its schema is a contract defect of the Core
            # (e.g. an enum that lags behind an emitted value), not a Board malfunction: report it visibly
            # but keep checking the Board. Schema conformance has its own regression tests.
            first = errors[0]
            where = "/".join(map(str, first.path)) or "<root>"
            self.warnings.append(f"STATUS_SCHEMA_DEVIATION: {len(errors)} violation(s) of project-status.schema.json; "
                                 f"first at {where}: {first.message[:200]}")

    def s5_links(self, entry: dict) -> None:
        status = self.status or {}
        candidates: list[tuple[str, str]] = []
        references = [item for item in (status.get("source_references") or {}).get("items", []) if item.get("availability") == "available"]
        by_type = {}
        for item in references:
            by_type.setdefault(item.get("source_type"), item)
        source = by_type.get("requirement") or (references[0] if references else None)
        if source:
            candidates.append(("source", "source/" + "/".join(quote(part) for part in source["canonical_path"].split("/"))))
        targets = [item for item in (status.get("project") or {}).get("active_targets", {}).get("items", []) if item.get("availability") == "available"]
        if targets and targets[0].get("canonical_path"):
            candidates.append(("reference", "reference/" + "/".join(quote(part) for part in targets[0]["canonical_path"].split("/"))))
        for item in (self.page_previews or {}).get("items", []):
            if (item.get("html_source") or {}).get("availability") == "available" and item["html_source"].get("preview_url"):
                candidates.append(("design_preview", item["html_source"]["preview_url"].lstrip("/")))
                break
        parity = by_type.get("parity_report")
        if parity:
            candidates.append(("parity_source", "source/" + "/".join(quote(part) for part in parity["canonical_path"].split("/"))))
        for run in (self.gallery or {}).get("items", []):
            captures = run.get("captures") or []
            if captures:
                candidates.append(("capture", "capture/" + "/".join(quote(part) for part in captures[0]["screenshot_path"].split("/"))))
                break
        failures = []
        for kind, path in candidates[:5]:
            code, body, seconds = self.http(path, per_request=15.0)
            self.links_checked.append({"kind": kind, "path": "/" + path, "status": code, "seconds": seconds})
            if code != 200 or not body:
                failures.append(f"{kind} /{path} -> HTTP {code}")
        for absent in ("source", "reference", "design_preview", "parity_source", "capture"):
            if absent not in {item["kind"] for item in self.links_checked}:
                self.links_checked.append({"kind": absent, "path": None, "status": None, "seconds": None, "reason": "NOT_PROVIDED_BY_PROJECT"})
        if failures:
            raise StageFail("link_unresolved", "; ".join(failures))

    # ------------------------------------------------------------------ browser
    def detect_browser(self):
        if os.environ.get("MXAGILE_BOARD_SMOKE_BROWSER", "").lower() == "none":
            self.browser["reason"] = "FORCED_NONE"
            return None
        try:
            from playwright.sync_api import sync_playwright
        except Exception:
            self.browser["reason"] = "PLAYWRIGHT_NOT_INSTALLED"
            return None
        return sync_playwright

    def run_browser_stages(self, sync_playwright) -> None:
        started = time.perf_counter()
        s3 = {"id": "S3", "result": "PASS", "seconds": 0.0, "failures": []}
        s4 = {"id": "S4", "result": "PASS", "seconds": 0.0, "failures": []}
        s6 = {"id": "S6", "result": "PASS", "seconds": 0.0, "failures": []}
        self.stages.extend([s3, s4, s6])
        try:
            with sync_playwright() as playwright:
                launch_started = time.perf_counter()
                try:
                    browser = playwright.chromium.launch()
                    self.timings["browser_launch_seconds"] = round(time.perf_counter() - launch_started, 3)
                except Exception as error:
                    self.browser.update({"available": False, "reason": f"CHROMIUM_UNAVAILABLE: {str(error).splitlines()[0][:160]}"})
                    for entry in (s3, s4, s6):
                        entry["result"] = "UNAVAILABLE"
                        entry["reason"] = self.browser["reason"]
                    return
                self.browser.update({"available": True, "engine": "chromium", "source": "python-playwright", "reason": None})
                # Leaving the playwright context closes the browser together with the driver; an extra
                # explicit browser.close() only added a second graceful-shutdown wait.
                self.browser_session(browser, s3, s4, s6)
                session_done = time.perf_counter()
            self.timings["driver_stop_seconds"] = round(time.perf_counter() - session_done, 3)
        finally:
            self.timings["browser_seconds"] = round(time.perf_counter() - started, 3)

    def browser_session(self, browser, s3: dict, s4: dict, s6: dict) -> None:
        context = browser.new_context(viewport={"width": 1280, "height": 900})
        page = context.new_page()
        errors: list[dict] = []
        responses: list[tuple[str, int]] = []
        page.on("pageerror", lambda error: errors.append({"kind": "pageerror", "message": str(error)[:300],
                                                          "origin": script_error_origin(str(getattr(error, "stack", "") or ""))}))
        page.on("console", lambda message: errors.append({"kind": "console_error", "message": message.text[:300],
                                                          "origin": script_error_origin((message.location or {}).get("url", ""))})
                if message.type == "error" and "Failed to load resource" not in message.text else None)
        page.on("response", lambda response: responses.append((response.url, response.status)))

        def timeout_for(cap: float) -> float:
            self.deadline.check("browser")
            return max(500.0, self.deadline.budget(cap) * 1000.0)

        page.set_default_timeout(timeout_for(10.0))
        started = time.perf_counter()
        try:
            page.goto(self.base + "#portfolio", wait_until="domcontentloaded", timeout=timeout_for(15.0))
            page.wait_for_selector("#board:not([hidden])", timeout=timeout_for(20.0))
        except SmokeTimeout:
            raise
        except Exception as error:
            visible = ""
            try:
                visible = page.inner_text("#load-state", timeout=500)
            except Exception:
                pass
            self.screenshot(page, "first-load")
            s3["result"] = "FAIL"
            s3["failures"].append({"route": "portfolio", "kind": "board_not_usable", "message": f"{(visible or str(error).splitlines()[0])[:300]}"})
            return
        self.timings["first_usable_page_seconds"] = round(time.perf_counter() - started, 3)
        s3_started = time.perf_counter()

        for route, heading in ROUTES:
            self.deadline.check(f"route {route}")
            try:
                page.evaluate("(route) => { location.hash = route; }", route)
                page.wait_for_selector(f'#view h2:has-text("{heading}")', timeout=timeout_for(8.0))
                self.wait_final_state(page, route)
                if route == "findings" and not (page.locator("#view .plain-item").count() or page.locator("#view .empty").count()):
                    raise StageFail("canonical_state_missing", "Findings shows neither records nor a canonical empty/unavailable state", route)
                self.routes_checked.append(route)
            except SmokeTimeout:
                raise
            except StageFail as failure:
                self.screenshot(page, f"route-{route}")
                s3["result"] = "FAIL"
                s3["failures"].append(failure.as_dict())
            except Exception as error:
                self.screenshot(page, f"route-{route}")
                s3["result"] = "FAIL"
                s3["failures"].append({"route": route, "kind": "route_not_rendered",
                                       "message": f"Heading '{heading}' not rendered: {str(error).splitlines()[0][:200]}"})
        s3["seconds"] = round(time.perf_counter() - s3_started, 3)
        s6_started = time.perf_counter()
        self.consistency_checks(page, s6)
        s6["seconds"] = round(time.perf_counter() - s6_started, 3)
        s4_started = time.perf_counter()
        self.drilldowns(page, s4)
        s4["seconds"] = round(time.perf_counter() - s4_started, 3)
        visibility_started = time.perf_counter()
        self.projection_visibility(page, s6)
        s6["seconds"] = round(s6["seconds"] + time.perf_counter() - visibility_started, 3)
        for item in errors:
            if item.get("origin") == "artifact":
                self.warnings.append(f"ARTIFACT_SCRIPT_ERROR: {item['message'][:160]} (raised inside an embedded project artifact, not Board code)")
                continue
            s3["result"] = "FAIL"
            s3["failures"].append({"route": None, "kind": item["kind"], "message": item["message"]})
        for url, code in responses:
            if code >= 400 and url.startswith(self.base) and not url.endswith("/favicon.ico"):
                s3["result"] = "FAIL"
                s3["failures"].append({"route": None, "kind": "http_error", "message": f"{code} {url[len(self.base) - 1:][:200]}"})
        if s3["result"] == "FAIL" and not self.screenshots:
            self.screenshot(page, "final-state")
        context_started = time.perf_counter()
        context.close()
        self.timings["context_close_seconds"] = round(time.perf_counter() - context_started, 3)

    def wait_final_state(self, page, route: str) -> None:
        end = time.monotonic() + max(0.5, self.deadline.budget(12.0))
        while True:
            text = page.inner_text("#view")
            if not any(token in text for token in LOADING_TOKENS):
                return
            if time.monotonic() >= end:
                raise StageFail("route_still_loading", f"View stayed in a loading state: {next(t for t in LOADING_TOKENS if t in text)}", route)
            time.sleep(0.2)

    def drilldowns(self, page, entry: dict) -> None:
        status = self.status or {}
        waves = (status.get("delivery") or {}).get("waves", {}).get("items", [])
        requirements = (status.get("requirements") or {}).get("items", [])
        pages = (self.page_previews or {}).get("items", [])

        def drill(kind: str, route: str, link_selector: str, check, available: bool) -> None:
            self.deadline.check(f"drilldown {kind}")
            if not available:
                entry.setdefault("notes", []).append(f"{kind}: NOT_APPLICABLE (project has none)")
                return
            try:
                page.evaluate("(route) => { location.hash = route; }", route)
                self.wait_final_state(page, route)
                link = page.locator(link_selector).first
                link.wait_for(state="visible", timeout=max(500.0, self.deadline.budget(8.0) * 1000))
                href = link.get_attribute("href")
                link.click()
                check(href)
            except SmokeTimeout:
                raise
            except Exception as error:
                self.screenshot(page, f"drilldown-{kind}")
                entry["result"] = "FAIL"
                entry["failures"].append({"route": route, "kind": "drilldown_failed", "message": f"{kind}: {str(error).splitlines()[0][:240]}"})

        def check_wave(href: str) -> None:
            wave_id = href.split("/", 1)[1]
            page.wait_for_selector(f'#view h2:has-text("{wave_id}")', timeout=max(500.0, self.deadline.budget(8.0) * 1000))
            page.wait_for_selector('#view .view-title small:has-text("Wave detail")', timeout=2000)
            facts = page.inner_text("#view .detail-fields")
            match = re.search(r"TASKS\s+(\d+|UNKNOWN)\s+(\d+|UNKNOWN) done", facts)
            api = next((item for item in waves if item["wave_id"] == wave_id), None)
            if api and match:
                expected = (str(api["task_progress"]["total"]) if api["task_progress"]["total"] is not None else "UNKNOWN",
                            str(api["task_progress"]["status_counts"].get("done")) if api["task_progress"]["status_counts"].get("done") is not None else "UNKNOWN")
                self.record_consistency("wave_tasks_total_done", f"{match.group(1)}/{match.group(2)}", f"{expected[0]}/{expected[1]}")

        def check_requirement(href: str) -> None:
            requirement_id = href.split("/", 1)[1]
            page.wait_for_selector(f'#view h2:has-text("{requirement_id}")', timeout=max(500.0, self.deadline.budget(8.0) * 1000))

        def check_page(href: str) -> None:
            page_id = href.split("/", 1)[1]
            page.wait_for_selector(f'#view .page-hub .hub-header:has-text("{page_id}")', timeout=max(500.0, self.deadline.budget(10.0) * 1000))
            self.wait_final_state(page, "page")

        drill("wave", "waves", '#view a.internal-link[href^="#wave/"]', check_wave, bool(waves))
        drill("requirement", "requirements", '#view a.internal-link[href^="#requirement/"]', check_requirement, bool(requirements))
        drill("page", "pages", '#view a.page-card-title[href^="#pages/"]', check_page, bool(pages))
        # Legacy hash routes are redirected (FR-084).
        try:
            page.evaluate("(route) => { location.hash = route; }", "gallery")
            page.wait_for_function("location.hash === '#pages?view=parity'", timeout=3000)
        except SmokeTimeout:
            raise
        except Exception as error:
            entry["result"] = "FAIL"
            entry["failures"].append({"route": "gallery", "kind": "legacy_redirect_failed", "message": str(error).splitlines()[0][:200]})

    def record_consistency(self, name: str, ui, api) -> None:
        self.consistency.append({"name": name, "ui": ui, "api": api, "match": str(ui) == str(api)})

    def consistency_checks(self, page, entry: dict) -> None:
        status = self.status or {}
        try:
            page.evaluate("(route) => { location.hash = route; }", "overview")
            page.wait_for_selector('#view h2:has-text("Delivery at a glance")', timeout=3000)
            overview = page.inner_text("#view")
            total = re.search(r"(\d+|UNKNOWN) total", overview)
            api_total = (status.get("requirements") or {}).get("total")
            if total:
                self.record_consistency("requirements_total", total.group(1), api_total if api_total is not None else "UNKNOWN")
            done_badges = page.locator("#view .plain-item .state", has_text=re.compile(r"^done$")).count()
            self.record_consistency("waves_done", done_badges, ((status.get("delivery") or {}).get("waves") or {}).get("phase_counts", {}).get("done") or 0)
            page.evaluate("(route) => { location.hash = route; }", "waves")
            page.wait_for_selector('#view h2:has-text("Waves")', timeout=3000)
            self.record_consistency("waves_listed", page.locator("#view article.plain-section").count(),
                                    len(((status.get("delivery") or {}).get("waves") or {}).get("items", [])))
            page.evaluate("(route) => { location.hash = route; }", "decisions")
            page.wait_for_selector('#view h2:has-text("Decisions")', timeout=3000)
            proposed = re.search(r"(\d+|UNKNOWN) proposed", page.inner_text("#view .view-title"))
            api_proposed = ((status.get("decisions") or {}).get("status_counts") or {}).get("PROPOSED")
            if proposed:
                self.record_consistency("decisions_proposed", proposed.group(1), api_proposed if api_proposed is not None else "UNKNOWN")
            page.evaluate("(route) => { location.hash = route; }", "findings")
            page.wait_for_selector('#view h2:has-text("Findings")', timeout=3000)
            open_findings = re.search(r"(\d+|UNKNOWN) open", page.inner_text("#view .view-title"))
            api_open = (status.get("findings") or {}).get("open")
            if open_findings:
                self.record_consistency("findings_open", open_findings.group(1), api_open if api_open is not None else "UNKNOWN")
            health = status.get("health")
            if isinstance(health, dict):
                chip = page.inner_text("#health-chip", timeout=2000)
                level = re.search(r"HEALTH · (OK|DEGRADED|BLOCKED)", chip)
                self.record_consistency("health_level", level.group(1) if level else chip[:40], health.get("level"))
        except SmokeTimeout:
            raise
        except Exception as error:
            entry["result"] = "FAIL"
            entry["failures"].append({"route": None, "kind": "consistency_unreadable", "message": str(error).splitlines()[0][:240]})
            return
        mismatches = [item for item in self.consistency if not item["match"] and item["name"] != "wave_tasks_total_done"]
        if mismatches:
            entry["result"] = "FAIL"
            entry["failures"].append({"route": None, "kind": "consistency", "message": "; ".join(f"{m['name']}: UI {m['ui']} != API {m['api']}" for m in mismatches)[:500]})

    def projection_visibility(self, page, entry: dict) -> None:
        try:
            label = page.inner_text("#updated-label")
        except Exception as error:
            entry["result"] = "FAIL"
            entry["failures"].append({"route": None, "kind": "projection_not_visible", "message": str(error).splitlines()[0][:200]})
            return
        if "PROJEKTION" not in label.upper():
            # An older installed Board payload predates the projection display. That is a version
            # difference worth reporting, not a mismatch between a shown value and the API.
            self.warnings.append("PROJECTION_NOT_DISPLAYED: the Board UI payload shows no projection state "
                                 "(payload older than Core CS-2); API state is "
                                 f"{(self.projection or {}).get('state')}")
            return
        code, body, _ = self.http("api/status")
        states = {(self.projection or {}).get("state")}
        if code == 200:
            try:
                states.add((json.loads(body).get("projection_state") or {}).get("state"))
            except ValueError:
                pass
        states.discard(None)
        expected = {PROJECTION_LABELS.get(state, state) for state in states}
        self.consistency.append({"name": "projection_state_visible", "ui": label[-80:], "api": sorted(states), "match": bool(expected) and any(item in label for item in expected)})
        if states and not self.consistency[-1]["match"]:
            entry["result"] = "FAIL"
            entry["failures"].append({"route": None, "kind": "projection_label_mismatch", "message": f"Board shows '{label[-80:]}' but the API reports {sorted(states)}"})

    # ------------------------------------------------------------------ orchestration
    def skip_remaining(self, stage_ids: tuple[str, ...], reason: str) -> None:
        for stage_id in stage_ids:
            self.skip(stage_id, reason)

    def execute(self) -> None:
        order = ("S0", "S1", "S2", "S3", "S4", "S5", "S6")
        for stage_id, function in (("S0", self.s0_preflight), ("S1", self.s1_start_server), ("S2", self.s2_api)):
            self.stage(stage_id, function)
            if self.stages[-1]["result"] != "PASS":
                self.skip_remaining(order[order.index(stage_id) + 1:], f"PRECONDITION_FAILED: {stage_id}")
                return
        self.stage("S5", self.s5_links)
        runner = self.detect_browser()
        if runner is None:
            for stage_id in ("S3", "S4", "S6"):
                self.stages.append({"id": stage_id, "result": "UNAVAILABLE", "seconds": 0.0, "failures": [], "reason": self.browser["reason"]})
            return
        self.run_browser_stages(runner)

    def finish_cleanup(self) -> None:
        started = time.perf_counter()
        process = self.process
        if process is not None:
            kill_tree(process)
            self.cleanup["process_terminated"] = process.poll() is not None
        if self.port is not None:
            deadline = time.monotonic() + 3.0
            while port_is_open(self.port) and time.monotonic() < deadline:
                time.sleep(0.1)
            self.cleanup["port_closed"] = not port_is_open(self.port)
        if self.cache_dir is not None:
            shutil.rmtree(self.cache_dir, ignore_errors=True)
            self.cleanup["cache_removed"] = not self.cache_dir.exists()
        if self.stderr_path is not None and self.stderr_path.exists() and self.result in ("PASS", "UNAVAILABLE"):
            try:
                self.stderr_path.unlink()
            except OSError:
                pass
        self.timings["cleanup_seconds"] = round(time.perf_counter() - started, 3)

    def run(self) -> dict:
        watchdog = threading.Timer(self.timeout + 8.0, self.watchdog)
        watchdog.daemon = True
        watchdog.start()
        try:
            self.execute()
            self.result = self.derive_result()
        except SmokeTimeout:
            self.result = "TIMEOUT"
        except Exception as error:  # an unexpected defect in the smoke itself is not a Board verdict
            self.result = "ERROR"
            self.error = f"{type(error).__name__}: {str(error)[:300]}"
        finally:
            self.finish_cleanup()
            watchdog.cancel()
        self.timings["total_seconds"] = round(time.monotonic() - self.started, 3)
        self.result = self.apply_cleanup_and_timing(self.result)
        with self._lock:
            self._finished = True
        return self.build_report()

    def derive_result(self) -> str:
        results = [item["result"] for item in self.stages]
        if "TIMEOUT" in results:
            return "TIMEOUT"
        if "FAIL" in results:
            return "FAIL"
        if "UNAVAILABLE" in results:
            return "UNAVAILABLE"
        return "PASS"

    def apply_cleanup_and_timing(self, result: str) -> str:
        if self.cleanup["process_terminated"] is False or self.cleanup["port_closed"] is False:
            self.stages.append({"id": "CLEANUP", "result": "FAIL", "seconds": self.timings["cleanup_seconds"] or 0.0,
                                "failures": [{"route": None, "kind": "cleanup_failed", "message": f"Board process or port still alive: {self.cleanup}"}]})
            if result in ("PASS", "UNAVAILABLE"):
                result = "FAIL"
        snapshot_started = time.perf_counter()
        after = project_snapshot(self.root) if self.snapshot_before else {}
        self.timings["snapshot_seconds"] = round(time.perf_counter() - snapshot_started, 3)
        self.changed_paths = diff_snapshots(self.snapshot_before, after) if self.snapshot_before else []
        self.project_unchanged = (not self.changed_paths) if self.snapshot_before else None
        if self.changed_paths and self.strict_unchanged:
            # Deterministic environment (fixture/tests): nobody else touches the project, so a change is a defect.
            self.stages.append({"id": "PROJECT_UNCHANGED", "result": "FAIL", "seconds": self.timings["snapshot_seconds"] or 0.0,
                                "failures": [{"route": None, "kind": "project_modified",
                                              "message": "Project changed during the smoke: " + ", ".join(self.changed_paths[:8])}]})
            if result in ("PASS", "UNAVAILABLE"):
                result = "FAIL"
        elif self.changed_paths:
            # Live project: concurrent edits by other processes are expected; causality is not provable here.
            self.warnings.append("PROJECT_CHANGED_DURING_RUN: " + ", ".join(self.changed_paths[:5])
                                 + " (the smoke writes nothing into the project; causality not established, another process may have changed it)")
        total = self.timings["total_seconds"] or 0.0
        if result in ("PASS", "UNAVAILABLE") and total > TARGET_SECONDS:
            self.warnings.append(f"SLOW_RUN: {total:.1f}s exceeds the {TARGET_SECONDS:.0f}s target (hard limit {self.timeout:.0f}s)")
        if total > self.timeout and result in ("PASS", "UNAVAILABLE", "FAIL"):
            result = "TIMEOUT"
        return result

    def watchdog(self) -> None:
        with self._lock:
            if self._finished:
                return
        if self.process is not None:
            kill_tree(self.process)
        report = {"check": "board_smoke", "schema_version": SCHEMA_VERSION, "result": "TIMEOUT",
                  "reason": "WATCHDOG: the smoke did not finish within its hard limit", "duration_seconds": round(time.monotonic() - self.started, 3)}
        print(json.dumps(report, sort_keys=True), flush=True)
        os._exit(3)

    def build_report(self) -> dict:
        stages = sorted(self.stages, key=lambda item: item["id"])
        failures = [dict(failure, stage=stage["id"]) for stage in stages for failure in stage.get("failures", [])]
        report = {
            "check": "board_smoke",
            "schema_version": SCHEMA_VERSION,
            "result": self.result,
            "duration_seconds": self.timings["total_seconds"],
            "core_version": self.core_version,
            "project_fingerprint": self.project_fingerprint,
            "route_list_version": ROUTE_LIST_VERSION,
            "routes_checked": self.routes_checked,
            "browser": self.browser,
            "projection_state": (self.projection or {}).get("state"),
            "timings": self.timings,
            "stages": stages,
            "failures": failures,
            "warnings": self.warnings,
            "notes": self.notes,
            "links_checked": self.links_checked,
            "consistency": self.consistency,
            "environment": {"cache_dir_isolated": True, "legacy_cache_env_removed": True, "port": self.port},
            "cleanup": self.cleanup,
            "artifacts": {"failure_screenshots": self.screenshots},
            "project_unchanged": self.project_unchanged,
        }
        if self.error:
            report["error"] = self.error
        if failures and self.stderr_path is not None and self.stderr_path.exists():
            report["artifacts"]["server_stderr_tail"] = self.stderr_path.read_text(encoding="utf-8", errors="replace")[-600:]
            report["artifacts"]["server_stderr_file"] = str(self.stderr_path)
        return report


EXIT_CODES = {"PASS": 0, "FAIL": 1, "UNAVAILABLE": 2, "TIMEOUT": 3, "ERROR": 3}


def format_text(report: dict) -> str:
    lines = [f"BOARD_SMOKE: {report['result']} ({report.get('duration_seconds')} s)"]
    timings = report.get("timings") or {}
    lines.append("  startup {} s · first status {} s · browser launch {} s · first usable page {} s · cleanup {} s".format(
        timings.get("startup_seconds"), timings.get("first_status_seconds"), timings.get("browser_launch_seconds"),
        timings.get("first_usable_page_seconds"), timings.get("cleanup_seconds")))
    browser = report["browser"]
    state = "available" if browser.get("available") else (browser.get("reason") or "not evaluated")
    lines.append(f"  browser: {browser.get('source')} ({state}) · projection: {report.get('projection_state')}")
    for stage in report.get("stages", []):
        suffix = f" — {stage['reason']}" if stage.get("reason") else ""
        lines.append(f"  {stage['id']}: {stage['result']} ({stage['seconds']} s){suffix}")
    for failure in report.get("failures", []):
        lines.append(f"  FAILURE [{failure.get('stage')}] {failure.get('kind')} {failure.get('route') or ''}: {failure.get('message')}")
    for warning in report.get("warnings", []):
        lines.append(f"  WARNING: {warning}")
    for shot in (report.get("artifacts") or {}).get("failure_screenshots", []):
        lines.append(f"  SCREENSHOT: {shot}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Bounded smoke check of the read-only MxAgile project Board.")
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--format", choices=["json", "text"], default="text")
    parser.add_argument("--include-reconciliation", action="store_true",
                        help="also request /api/reconciliation (can be slow on large histories)")
    parser.add_argument("--strict-project-unchanged", action="store_true",
                        help="treat any project modification during the run as FAIL (deterministic fixtures); default: warning")
    parser.add_argument("--timeout", type=float, default=MAX_TIMEOUT_SECONDS,
                        help=f"hard limit in seconds (maximum {MAX_TIMEOUT_SECONDS:.0f})")
    args = parser.parse_args(argv)
    report = BoardSmoke(args.project_root, timeout=args.timeout, include_reconciliation=args.include_reconciliation,
                        strict_unchanged=args.strict_project_unchanged).run()
    print(json.dumps(report, sort_keys=True, indent=2) if args.format == "json" else format_text(report))
    return EXIT_CODES.get(report["result"], 3)


if __name__ == "__main__":
    raise SystemExit(main())
