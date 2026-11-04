"""Expected client disconnect and visible builder failure HTTP contracts."""

from __future__ import annotations

import json
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.error import HTTPError
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import serve_project_board
import build_project_status


class ProjectUiSettingsTests(unittest.TestCase):
    def resolve(self, ui: dict, page_id: str | None = None) -> dict:
        with patch.object(build_project_status, "_read_project_ui_config", return_value={"ui": ui}):
            return build_project_status.resolve_project_ui_settings(ROOT, page_id)

    def test_legacy_project_defaults_preserve_existing_ui_mode(self) -> None:
        with patch.object(build_project_status, "_read_project_ui_config", return_value={}):
            settings = build_project_status.resolve_project_ui_settings(ROOT)
        self.assertEqual(settings["settings"]["html_first"]["effective"], False)
        self.assertEqual(settings["settings"]["mockup_driven"]["effective"], "guided")
        self.assertEqual(
            settings["settings"]["leave_running_after_visual_verification"]["effective"], True
        )

    def test_html_first_and_mockup_mode_are_orthogonal(self) -> None:
        for html_first in (False, True):
            for mockup_driven in ("off", "full"):
                with self.subTest(html_first=html_first, mockup_driven=mockup_driven):
                    result = self.resolve({
                        "implementation": {"html_first": html_first},
                        "verification": {"mockup_driven": mockup_driven},
                    })["settings"]
                    self.assertEqual(result["html_first"]["effective"], html_first)
                    self.assertEqual(result["mockup_driven"]["effective"], mockup_driven)

    def test_page_overrides_report_requested_effective_source_and_scope(self) -> None:
        result = self.resolve({
            "implementation": {
                "html_first": False,
                "overrides": {"PAGE-001": {"html_first": True}},
            },
            "verification": {
                "mockup_driven": "full",
                "overrides": {"PAGE-001": {"mockup_driven": "off"}},
            },
        }, "PAGE-001")["settings"]
        html = result["html_first"]
        self.assertEqual((html["requested"], html["effective"]), (False, True))
        self.assertEqual(html["source"], "page_override")
        self.assertEqual(html["scope"], "PAGE-001")
        self.assertEqual(html["override"], {"page_id": "PAGE-001", "value": True})
        mockup = result["mockup_driven"]
        self.assertEqual((mockup["requested"], mockup["effective"]), ("full", "off"))
        self.assertEqual(mockup["source"], "page_override")

    def test_page_can_override_project_html_first_back_to_native(self) -> None:
        result = self.resolve({
            "implementation": {
                "html_first": True,
                "overrides": {"PAGE-002": {"html_first": False}},
            },
        }, "PAGE-002")["settings"]["html_first"]
        self.assertEqual((result["requested"], result["effective"]), (True, False))
        self.assertEqual(result["source"], "page_override")

    def test_invalid_page_id_and_setting_fail_closed(self) -> None:
        with self.assertRaises(build_project_status.ProjectUiConfigError):
            self.resolve({}, "Region_Overview")
        with self.assertRaises(build_project_status.ProjectUiConfigError):
            self.resolve({"implementation": {"html_first": "true"}})


class BoardHttpTests(unittest.TestCase):
    def test_builder_kit_board_discovery_is_fast_and_does_not_infer_session_delegation(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-builder-kit-") as temporary:
            root = Path(temporary)
            manifest_dir = root / ".mendix-page-designer-html-mode"
            manifest_dir.mkdir()
            (manifest_dir / "manifest.json").write_text(json.dumps({
                "kit": "mendix-ui-builder-kit",
                "agent": "mendix-page-designer-html-mode",
                "version": "9.8.7",
            }), encoding="utf-8")
            agent = root / ".github/agents/mendix-page-designer-html-mode.agent.md"
            agent.parent.mkdir(parents=True)
            agent.write_text("name: mendix-page-designer-html-mode\n", encoding="utf-8")
            started = time.perf_counter()
            result = serve_project_board.resolve_builder_kit_status(root)
            elapsed = time.perf_counter() - started
        self.assertLess(elapsed, 0.1)
        self.assertTrue(result["installed"])
        self.assertEqual(result["version"], "9.8.7")
        self.assertTrue(result["agent_files_available"]["vscode_copilot"])
        self.assertIsNone(result["agent_available_for_harness"])
        self.assertIsNone(result["agent_delegable"])

    def start_server(self, root: Path):
        ui_root = root / ".mxagile/board"
        ui_root.mkdir(parents=True, exist_ok=True)
        server = serve_project_board.ProjectBoardServer(root, ui_root, 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        return server, thread

    def stop_server(self, server, thread) -> None:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    def test_status_uses_shared_resolver_for_project_and_page_values(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-ui-settings-") as temporary:
            root = Path(temporary)
            inventory = root / "planning/ui-inventory/Region_Overview.yaml"
            inventory.parent.mkdir(parents=True)
            inventory.write_text(
                "page_id: PAGE-001\npage_name: Overview\n"
                "source_mockup: input-resources/ui-ux/Overview.html\n"
                "html_source: themesource/Module/public/overview/Overview.html\n",
                encoding="utf-8",
            )
            source = root / "themesource/Module/public/overview/Overview.html"
            source.parent.mkdir(parents=True)
            source.write_text("<!doctype html><title>Overview</title>", encoding="utf-8")
            reference = root / "input-resources/ui-ux/Overview.html"
            reference.parent.mkdir(parents=True)
            reference.write_text("<!doctype html><title>Reference</title>", encoding="utf-8")
            (root / "mxagile-project.yaml").write_text(
                "ui:\n"
                "  implementation:\n"
                "    html_first: false\n"
                "    overrides:\n"
                "      PAGE-001:\n"
                "        html_first: true\n"
                "  verification:\n"
                "    mockup_driven: guided\n"
                "    overrides:\n"
                "      PAGE-001:\n"
                "        mockup_driven: full\n",
                encoding="utf-8",
            )
            base_status = {
                "project": {"active_targets": {"items": []}},
                "verification": {"gallery_state": "not_loaded", "gallery": []},
                "findings": {"availability": "available", "items": []},
                "runtime": {"recorded_readiness": {"status": "APPLICATION_REACHABLE"}},
            }
            gallery_result = {
                "source_fingerprint": "sha256:test",
                "gallery_state": "available",
                "screen_id": "PAGE-001",
                "items": [{
                    "screen_id": "PAGE-001", "historical": False,
                    "entry_id": "PAR-001", "run_id": "RUN-001", "parity_result": "PASS",
                    "reference_path": "input-resources/ui-ux/Overview.html",
                    "captures": [{"captured_at": "2026-11-04T10:00:00Z", "runtime_url": "http://localhost:8080"}],
                }],
            }
            preview_status = dict(base_status)
            preview_status["page_previews"] = serve_project_board.build_page_previews(root, preview_status)
            self.assertEqual(preview_status["page_previews"]["availability"], "available")
            server, thread = self.start_server(root)
            server.status_cache.get_summary = Mock(return_value=base_status)
            server.status_cache.get = Mock(return_value={
                **base_status,
                "reconciliation": {"status": "NO_COMMITTED_DELTA", "read_only": True},
            })
            server.status_cache.get_gallery = Mock(return_value=gallery_result)
            try:
                try:
                    with urlopen(f"http://127.0.0.1:{server.server_port}/api/status") as response:
                        payload = json.loads(response.read())
                except HTTPError as error:
                    body = error.read()
                    error.close()
                    self.fail(f"Board status request failed: {body!r}")
                self.assertFalse(payload["ui_settings"]["settings"]["html_first"]["effective"])
                self.assertEqual(payload["reconciliation"]["status"], "NOT_LOADED")
                self.assertNotIn("page_previews", payload)

                with patch.object(serve_project_board, "resolve_builder_kit_status", return_value={
                    "availability": "available",
                    "installed": True,
                    "version": "9.8.7",
                    "agent_available_for_harness": True,
                    "agent_delegable": None,
                }):
                    with urlopen(f"http://127.0.0.1:{server.server_port}/api/page-previews") as response:
                        page_payload = json.loads(response.read())
                self.assertEqual(page_payload["project_settings"]["settings"]["html_first"]["effective"], False)
                self.assertTrue(page_payload["builder_kit"]["installed"])
                self.assertEqual(page_payload["builder_kit"]["version"], "9.8.7")
                self.assertTrue(page_payload["builder_kit"]["agent_available_for_harness"])
                self.assertIsNone(page_payload["builder_kit"]["agent_delegable"])
                page = page_payload["items"][0]
                self.assertEqual(page_payload["availability"], "available")
                self.assertEqual(page["page_id"], "PAGE-001")
                self.assertEqual(page["implementation_mode"], "HTML_FIRST")
                self.assertEqual(page["html_first"]["source"], "page_override")
                self.assertEqual(page["mockup_driven"]["effective"], "full")
                self.assertEqual(page["parity_status"], "NOT_LOADED")
                self.assertEqual(page["authority_conflicts"]["availability"], "not_observable")
                self.assertEqual(page["runtime_status"]["state"], "APPLICATION_REACHABLE")
                self.assertEqual(page["last_verification_evidence"]["status"], "NOT_LOADED")
                self.assertEqual(page["html_source"]["preview_class"], "DESIGN PREVIEW")
                self.assertIsNotNone(page["html_source"]["preview_url"])

                with urlopen(f"http://127.0.0.1:{server.server_port}/api/gallery?screen_id=PAGE-001") as response:
                    gallery = json.loads(response.read())
                self.assertEqual(gallery["items"][0]["parity_result"], "PASS")
                self.assertEqual(gallery["items"][0]["captures"][0]["runtime_url"], "http://localhost:8080")
                server.status_cache.get_gallery.assert_called_once_with("PAGE-001")

                with urlopen(f"http://127.0.0.1:{server.server_port}/api/reconciliation") as response:
                    reconciliation = json.loads(response.read())
                self.assertEqual(reconciliation["reconciliation"]["status"], "NO_COMMITTED_DELTA")
                self.assertEqual(server.status_cache.get_summary.call_count, 2)
                server.status_cache.get.assert_called_once()
            finally:
                self.stop_server(server, thread)

    def test_design_preview_is_labeled_and_confined_to_declared_feature_folder(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-html-preview-") as temporary:
            root = Path(temporary)
            inventory = root / "planning/ui-inventory/PAGE-001.yaml"
            inventory.parent.mkdir(parents=True)
            inventory.write_text(
                "page_id: PAGE-001\nhtml_source: themesource/Module/public/overview/Overview.html\n",
                encoding="utf-8",
            )
            feature = root / "themesource/Module/public/overview"
            feature.mkdir(parents=True)
            (feature / "Overview.html").write_text("<!doctype html><title>Feature</title>", encoding="utf-8")
            (feature / "styles.css").write_text("body { color: green; }", encoding="utf-8")
            (feature.parent / "outside.css").write_text("body { color: red; }", encoding="utf-8")
            self.assertIsNone(serve_project_board.resolve_design_preview_file(root, "PAGE-001", "../outside.css"))

            server, thread = self.start_server(root)
            try:
                base_url = f"http://127.0.0.1:{server.server_port}"
                with urlopen(f"{base_url}/design-preview/PAGE-001/") as response:
                    shell = response.read().decode("utf-8")
                    self.assertEqual(response.headers["X-MxAgile-Evidence-Class"], "DESIGN_PREVIEW")
                self.assertIn("DESIGN PREVIEW", shell)
                self.assertIn("NOT MENDIX RUNTIME EVIDENCE", shell)
                with urlopen(f"{base_url}/design-preview-source/PAGE-001/") as response:
                    self.assertIn("<title>Feature</title>", response.read().decode("utf-8"))
                    self.assertEqual(response.headers["X-MxAgile-Evidence-Class"], "DESIGN_PREVIEW")
                with urlopen(f"{base_url}/design-preview-source/PAGE-001/styles.css") as response:
                    self.assertIn("color: green", response.read().decode("utf-8"))
            finally:
                self.stop_server(server, thread)

    def test_gallery_endpoint_accepts_only_canonical_page_scope(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-gallery-api-") as temporary:
            root = Path(temporary)
            server, thread = self.start_server(root)
            server.status_cache.get_gallery = Mock(return_value={
                "source_fingerprint": "sha256:test",
                "gallery_state": "available",
                "screen_id": "PAGE-001",
                "items": [{"screen_id": "PAGE-001", "parity_result": "PASS"}],
            })
            try:
                with urlopen(f"http://127.0.0.1:{server.server_port}/api/gallery?screen_id=PAGE-001") as response:
                    payload = json.loads(response.read())
                self.assertEqual(payload["screen_id"], "PAGE-001")
                self.assertEqual(payload["items"][0]["parity_result"], "PASS")
                server.status_cache.get_gallery.assert_called_once_with("PAGE-001")
                with self.assertRaises(HTTPError) as response:
                    urlopen(f"http://127.0.0.1:{server.server_port}/api/gallery?screen_id=Region_Overview")
                self.assertEqual(response.exception.code, 400)
                response.exception.close()
            finally:
                self.stop_server(server, thread)

    def test_capture_route_loads_lazy_gallery_before_allowlisted_file(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-capture-") as temporary:
            root = Path(temporary)
            capture_path = "planning/evidence/screenshots/PAGE-001.png"
            capture_file = root / capture_path
            capture_file.parent.mkdir(parents=True)
            capture_file.write_bytes(b"validated capture")
            server, thread = self.start_server(root)
            server.status_cache.get_summary = Mock(return_value={
                "verification": {"gallery": [], "gallery_state": "not_loaded"},
            })
            server.status_cache.get_gallery = Mock(return_value={
                "gallery_state": "available",
                "items": [{"captures": [{"screenshot_path": capture_path}]}],
            })
            try:
                with urlopen(f"http://127.0.0.1:{server.server_port}/capture/{capture_path}") as response:
                    self.assertEqual(response.read(), b"validated capture")
                server.status_cache.get_gallery.assert_called_once_with()
            finally:
                self.stop_server(server, thread)

    def test_expected_client_disconnect_is_logged_compactly(self) -> None:
        for error_type in (ConnectionAbortedError, ConnectionResetError, BrokenPipeError):
            with self.subTest(error=error_type.__name__):
                handler = object.__new__(serve_project_board.ProjectBoardHandler)
                handler.wfile = Mock()
                handler.wfile.write.side_effect = error_type("client closed")
                handler.send_response = Mock()
                handler.send_header = Mock()
                handler.end_headers = Mock()
                handler.log_message = Mock()
                handler._send(200, b"payload", "application/json")
                handler.log_message.assert_called_once_with("CLIENT_DISCONNECT")

    def test_unexpected_response_write_error_is_not_swallowed(self) -> None:
        handler = object.__new__(serve_project_board.ProjectBoardHandler)
        handler.wfile = Mock()
        handler.wfile.write.side_effect = OSError("unexpected write failure")
        handler.send_response = Mock()
        handler.send_header = Mock()
        handler.end_headers = Mock()
        handler.log_message = Mock()
        with self.assertRaisesRegex(OSError, "unexpected write failure"):
            handler._send(200, b"payload", "application/json")
        handler.log_message.assert_not_called()

    def test_builder_failure_remains_visible_as_503(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-http-") as temporary:
            root = Path(temporary)
            ui_root = root / ".mxagile/board"
            ui_root.mkdir(parents=True, exist_ok=True)
            server = serve_project_board.ProjectBoardServer(root, ui_root, 0)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with patch.object(serve_project_board, "build_status_summary", side_effect=RuntimeError("fixture failure")):
                    with self.assertRaises(HTTPError) as response:
                        urlopen(f"http://127.0.0.1:{server.server_port}/api/status")
                self.assertEqual(response.exception.code, 503)
                payload = json.loads(response.exception.read())
                self.assertEqual(payload["error"], "status_unavailable")
                self.assertEqual(payload["reason"], "RuntimeError")
                response.exception.close()
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()