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

    def test_timeline_endpoint_validates_parameters_and_never_scans_per_request(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-timeline-api-") as temporary:
            root = Path(temporary)
            server, thread = self.start_server(root)
            try:
                base = f"http://127.0.0.1:{server.server_port}"
                server.timeline._thread.join(timeout=30)
                with urlopen(f"{base}/api/timeline?limit=5&group=decision") as response:
                    self.assertEqual(response.headers["Cache-Control"], "no-store")
                    payload = json.loads(response.read())
                self.assertEqual((payload["events"], payload["total"]), ([], 0))
                self.assertEqual(payload["index"]["state"], "NOT_OBSERVABLE")  # no Git history: nothing is guessed
                for bad in ("bogus=1", "limit=abc", "from=yesterday", "authority=X", "wave=W1&wave=W2", "cursor=1"):
                    with self.assertRaises(HTTPError) as response:
                        urlopen(f"{base}/api/timeline?{bad}")
                    self.assertEqual(response.exception.code, 400, bad)
                    response.exception.close()
            finally:
                self.stop_server(server, thread)

    def hub_project(self, root: Path) -> None:
        def write(relative: str, content: str | bytes) -> None:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content if isinstance(content, bytes) else content.encode("utf-8"))

        write("planning/ui-inventory/PAGE-ONE.yaml", "page_id: PAGE-ONE\npage_name: Page_One\ntitle: Seite Eins\nsource_mockup: input-resources/ui-ux/one.html\ntarget_mockup: input-resources/ui-ux/one.html\n")
        write("planning/ui-inventory/PAGE-TWO.yaml", "page_id: PAGE-TWO\npage_name: Page_Two\n")
        write("input-resources/ui-ux/one.html", "<html><body>mockup one</body></html>")
        write("planning/evidence/screenshots/set1/shot-a.png", b"\x89PNG\r\n\x1a\n" + b"0" * 32)
        write("planning/evidence/screenshots/set1/notes.txt", "not an image")
        write("planning/evidence/screenshots/other/secret.png", b"\x89PNG\r\n\x1a\n" + b"1" * 32)
        write("planning/evidence/analysis/set1.md", "# analysis")
        write("planning/parity/SCN-ONE.yaml",
              "# Evidence: planning/evidence/screenshots/set1/ ; analysis: planning/evidence/analysis/set1.md\n"
              "page_id: PAGE-ONE\nscenario_id: SCN-ONE\nverified_at: '2026-11-05'\nevidence_level: browser\n"
              "target_mockup: input-resources/ui-ux/one.html\napp_url: http://localhost:8080/p/one\n"
              "dimensions:\n  visual: {required: true, result: PARTIAL, note: delta}\n  content: {required: true, result: PASS}\noverall_result: PARTIAL\n")
        write("planning/decisions/DEC-001.yml", "ID: DEC-001\ntitle: Choice\nstatus: CONFIRMED\ndecision_type: business\ntopic: x\ndecision_text: y\nowner: PO\n"
              "affected_requirements: [REQ-001]\naffected_screens: [PAGE-ONE]\n")
        write("requirements/REQ-001.yml", "ID: REQ-001\ntitle: A requirement\ndescription: d\nstatus: accepted\n")
        write("planning/tasks/TASK-001.yml", "ID: TASK-001\nspec: SPEC-1\naction: Do it\nstatus: done\nreq: [REQ-001]\n")

    def test_page_hub_serves_only_the_selected_page_and_never_binds_mentioned_captures(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-hub-api-") as temporary:
            root = Path(temporary)
            self.hub_project(root)
            server, thread = self.start_server(root)
            try:
                base = f"http://127.0.0.1:{server.server_port}"
                with urlopen(f"{base}/api/page/PAGE-ONE") as response:
                    hub = json.loads(response.read())
                self.assertEqual((hub["page_id"], hub["title"]), ("PAGE-ONE", "Seite Eins"))
                self.assertNotIn("PAGE-TWO", json.dumps(hub))  # FR-083: nothing of other pages is loaded
                report = hub["parity"]["reports"][0]
                self.assertEqual((report["reported_result"], report["state"]), ("PARTIAL", "REPORTED_UNBOUND"))
                self.assertEqual([item["dimension"] for item in report["dimensions"]], ["visual", "content"])
                self.assertEqual(hub["parity"]["evidence_binding"]["state"], "NOT_RECORDED")
                self.assertEqual(hub["parity"]["model_commit_fingerprint"]["observation_state"], "NOT_RECORDED")
                self.assertIn("PARITY_NOT_BOUND", [item["code"] for item in hub["attention"]])
                groups = hub["visuals"]["captures"]["reported"]
                self.assertEqual([(group["label"], group["total"], group["bound"]) for group in groups], [("set1", 1, False)])
                self.assertEqual(groups[0]["source"], "parity_report_comment")
                self.assertEqual([doc["name"] for doc in hub["visuals"]["captures"]["documents"]], ["set1.md"])
                self.assertEqual([item["id"] for item in hub["context"]["decisions"]], ["DEC-001"])
                self.assertEqual(hub["context"]["requirements"][0]["via"], ["DEC-001"])
                self.assertEqual(hub["context"]["tasks"]["observation_state"], "NOT_OBSERVABLE")
                self.assertEqual(hub["visuals"]["reference"]["availability"], "available")

                # Screenshots are served only when this page's own report mentions them.
                with urlopen(f"{base}{groups[0]['items'][0]['url']}") as response:
                    self.assertEqual(response.headers["Content-Type"], "image/png")
                for forbidden in ("/page-artifact/PAGE-ONE/planning/evidence/screenshots/other/secret.png",
                                  "/page-artifact/PAGE-ONE/planning/evidence/screenshots/set1/notes.txt",
                                  "/page-artifact/PAGE-ONE/planning/parity/SCN-ONE.yaml",
                                  "/page-artifact/PAGE-TWO/planning/evidence/screenshots/set1/shot-a.png",
                                  "/page-artifact/PAGE-ONE/planning/evidence/screenshots/set1/../other/secret.png"):
                    with self.assertRaises(HTTPError) as response:
                        urlopen(f"{base}{forbidden}")
                    self.assertEqual(response.exception.code, 404, forbidden)
                    response.exception.close()

                with urlopen(f"{base}/api/page/PAGE-TWO") as response:
                    second = json.loads(response.read())
                self.assertEqual((second["parity"]["reports"], second["visuals"]["captures"]["reported"]), ([], []))
                self.assertIn("NO_PARITY_REPORT", [item["code"] for item in second["attention"]])
            finally:
                self.stop_server(server, thread)

    def test_page_and_requirement_endpoints_return_404_for_unknown_ids_and_a_requirement_slice(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-slice-api-") as temporary:
            root = Path(temporary)
            self.hub_project(root)
            server, thread = self.start_server(root)
            try:
                base = f"http://127.0.0.1:{server.server_port}"
                for unknown in ("/api/page/PAGE-NOPE", "/api/page/not-a-page", "/api/requirement/REQ-404", "/api/requirement/bad id"):
                    with self.assertRaises(HTTPError) as response:
                        urlopen(f"{base}{unknown.replace(' ', '%20')}")
                    self.assertEqual(response.exception.code, 404, unknown)
                    response.exception.close()
                with urlopen(f"{base}/api/requirement/REQ-001") as response:
                    result = json.loads(response.read())
                self.assertEqual(result["requirement"]["id"], "REQ-001")
                self.assertEqual(result["assessment"]["rule_version"], "delivery-assessment/v1")
                self.assertTrue(result["assessment"]["derived"])
                self.assertEqual([task["id"] for task in result["traceability"]["tasks"]], ["TASK-001"])
                self.assertEqual(result["traceability"]["pages_via_decisions"], ["PAGE-ONE"])
                self.assertEqual([item["id"] for item in result["traceability"]["decisions"]], ["DEC-001"])
            finally:
                self.stop_server(server, thread)

    def test_reference_csp_allows_only_the_board_itself_to_frame(self) -> None:
        """Security decision BRD-F-68: frame-ancestors 'self' for references/previews, 'none' elsewhere, never wider."""
        with tempfile.TemporaryDirectory(prefix="mxagile-board-csp-") as temporary:
            root = Path(temporary)
            self.hub_project(root)
            (root / "planning/ui-inventory/PAGE-THREE.yaml").write_text(
                "page_id: PAGE-THREE\npage_name: Page_Three\nhtml_source: themesource/mod/public/feat/Page.html\n", encoding="utf-8")
            (root / "themesource/mod/public/feat").mkdir(parents=True)
            (root / "themesource/mod/public/feat/Page.html").write_text("<div>fragment</div>", encoding="utf-8")
            (root / ".mxagile/board").mkdir(parents=True, exist_ok=True)
            (root / ".mxagile/board/index.html").write_text("<!doctype html><title>board</title>", encoding="utf-8")
            server, thread = self.start_server(root)
            try:
                base = f"http://127.0.0.1:{server.server_port}"

                def directives(path: str) -> dict[str, list[str]]:
                    with urlopen(f"{base}{path}") as response:
                        policy = response.headers["Content-Security-Policy"]
                    return {part.split()[0]: part.split()[1:] for part in (item.strip() for item in policy.split(";")) if part}

                with urlopen(f"{base}/api/page/PAGE-ONE") as response:
                    reference_url = json.loads(response.read())["visuals"]["reference"]["url"]
                framed = {"reference": directives(reference_url), "design preview": directives("/design-preview/PAGE-THREE/")}
                for name, policy in framed.items():
                    self.assertEqual(policy["frame-ancestors"], ["'self'"], name)
                    joined = " ".join(policy["frame-ancestors"])
                    for broadening in ("*", "http", "data:", "blob:", "127.0.0.1", "localhost"):
                        self.assertNotIn(broadening, joined, f"{name}: frame-ancestors must stay 'self'")
                    self.assertEqual(policy["object-src"], ["'none'"], name)
                    self.assertEqual(policy["base-uri"], ["'none'"], name)
                for path in ("/", "/api/status"):
                    self.assertEqual(directives(path)["frame-ancestors"], ["'none'"], path)
            finally:
                self.stop_server(server, thread)

    def test_health_endpoint_separates_groups_and_serves_older_snapshots(self) -> None:
        diagnostic = {"diagnostic_id": "DX-0000000000000001", "category": "DONE_BASIS_NOT_RECORDED", "severity": "INFO",
                      "blocking": False, "diagnostic_group": "framework_compat", "source_path": None}
        v3 = {"schema_version": 3, "source_fingerprint": "sha256:test",
              "health": {"observation_states": {"findings": "NOT_RECORDED", "capabilities": "NOT_OBSERVABLE"}},
              "compatibility": {"compatibility": "PARTIAL", "repair_status": "NONE", "diagnostics": [diagnostic]}}
        v2 = {"schema_version": 2, "source_fingerprint": "sha256:test"}
        with tempfile.TemporaryDirectory(prefix="mxagile-board-health-api-") as temporary:
            root = Path(temporary)
            server, thread = self.start_server(root)
            try:
                server.status_cache.get_summary = Mock(return_value=v3)
                base = f"http://127.0.0.1:{server.server_port}"
                with urlopen(f"{base}/api/health") as response:
                    self.assertEqual(response.headers["Cache-Control"], "no-store")
                    payload = json.loads(response.read())
                self.assertEqual(payload["observation_states"]["findings"], "NOT_RECORDED")
                self.assertEqual(payload["counts"]["framework_compat"], {"total": 1, "blocking": 0})
                self.assertEqual(payload["counts"]["project_attention"], {"total": 0, "blocking": 0})
                self.assertEqual([item["category"] for item in payload["diagnostics_by_group"]["framework_compat"]], ["DONE_BASIS_NOT_RECORDED"])
                self.assertEqual(payload["level"], "OK")  # NOT_RECORDED / NOT_OBSERVABLE / non-blocking framework items are not data defects
                self.assertEqual(payload["blocking_diagnostics"], 0)
                self.assertIn("projection", payload)

                # An older cached snapshot without health still answers; it never invents states.
                server.status_cache.get_summary = Mock(return_value=v2)
                with urlopen(f"{base}/api/health") as response:
                    legacy = json.loads(response.read())
                self.assertEqual(legacy["observation_states"], {})
                self.assertEqual(legacy["blocking_diagnostics"], 0)

                with self.assertRaises(HTTPError) as response:
                    urlopen(f"{base}/api/health?x=1")
                self.assertEqual(response.exception.code, 400)
                response.exception.close()
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


BOARD_FIXTURE_FILES = {
    # Embedded CS-1 fixture (001-board-redesign T005). Kept inside this mapped test module so the
    # fixture does not introduce unmapped impact paths.
    "mxagile-project.yaml": "name: Board Redesign Fixture\n",
    ".mxagile/version.yaml": 'version: "1.10.0"\n',
    "planning/lifecycle/process-state.yaml": (
        "waves:\n"
        "  W1:\n    phase: done\n    gates:\n"
        "      gate_to_refinement: {result: passed, evaluated: '2026-10-01'}\n"
        "      gate_to_ready: {result: passed, evaluated: '2026-10-02'}\n"
        "  W2:\n    phase: implementing\n    gates:\n"
        "      gate_to_refinement: {result: passed, evaluated: '2026-10-20'}\n"
        "      gate_to_ready: {result: passed, evaluated: '2026-10-21'}\n"
    ),
    "requirements/REQ-001.yml": "ID: REQ-001\ntitle: Fixture requirement 1\ndescription: Fixture.\nstatus: accepted\n",
    "requirements/REQ-002.yml": "ID: REQ-002\ntitle: Fixture requirement 2\ndescription: Fixture.\nstatus: accepted\n",
    "specs/SPEC-001.yml": "ID: SPEC-001\ntitle: Fixture spec\ndescription: Fixture.\nrequirements: [REQ-001, REQ-002]\n",
    "planning/tasks/TASK-001.yml": "ID: TASK-001\nspec: SPEC-001\nreq: [REQ-001]\nwave_id: W1\naction: Done work\nstatus: done\n",
    "planning/tasks/TASK-002.yml": "ID: TASK-002\nspec: SPEC-001\nreq: [REQ-001]\nwave_id: W1\naction: Legacy open item\nstatus: pending\n",
    "planning/findings/FIND-001.yml": (
        "ID: FIND-001\ntitle: Fixture verified finding\ngap_type: CONTENT_GAP\nseverity: COSMETIC\n"
        "lifecycle_status: VERIFIED\nobservation: Label differed.\nwave_id: W1\nrequirement_ids: [REQ-001]\n"
        "source_artifacts:\n  - {source_type: requirement, canonical_path: requirements/REQ-001.yml, artifact_id: REQ-001}\n"
    ),
    "planning/ui-inventory/PAGE-001.yaml": "page_id: PAGE-001\npage_name: Fixture Main\nsource_mockup: input-resources/ui-ux/main.html\n",
    "planning/ui-inventory/PAGE-002.yaml": (
        "page_id: PAGE-002\npage_name: Fixture Page2\nsource_mockup: input-resources/ui-ux/main.html\n"
        "html_source: themesource/fixture/public/page2/Page2.html\n"
    ),
    # Mirrors reference project PAGE-INTERACTION-STATES-REV5: has a page_id but is not a Page (BRD-F-05).
    "planning/ui-inventory/PAGE-INTERACTION-STATES-REV1.yaml": (
        "page_id: PAGE-INTERACTION-STATES-REV1\nsource_mockup: input-resources/ui-ux/main.html\n"
        "interaction_states:\n  - {id: STATE-001, description: Standalone legacy interaction record}\n"
    ),
    # Parity report without comparison identity and without manifest binding (BRD-F-07).
    "planning/parity/SCN-FIXTURE-PAGE2.yaml": (
        "page_id: PAGE-002\nscenario_id: SCN-FIXTURE-PAGE2\nverified_at: '2026-10-25'\nevidence_level: legacy\n"
        "overall_result: PARTIAL\ndimensions:\n"
        "  visual: {result: LEGACY_EVIDENCE}\n  content: {result: LEGACY_EVIDENCE}\n  structure: {result: LEGACY_EVIDENCE}\n"
        "  state: {result: NOT_VERIFIED}\n  interaction: {result: NOT_VERIFIED}\n"
        "  responsive: {result: NOT_VERIFIED}\n  role: {result: NOT_VERIFIED}\n"
    ),
    "input-resources/ui-ux/main.html": "<!doctype html><title>Fixture Main Mockup</title>\n",
    "themesource/fixture/public/page2/Page2.html": "<!doctype html><title>Fixture Page2</title>\n",
}


def write_board_fixture(root: Path) -> None:
    for relative, content in BOARD_FIXTURE_FILES.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")


def git_fixture(root: Path, *args: str) -> str:
    import subprocess
    return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, text=True).stdout.strip()


class BoardCorrectnessCs1Tests(unittest.TestCase):
    """001-board-redesign CS-1: the Board must not display false or misleading values."""

    start_server = BoardHttpTests.start_server
    stop_server = BoardHttpTests.stop_server

    def test_reconciliation_placeholder_carries_observed_head_and_branch(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-cs1-head-", ignore_cleanup_errors=True) as temporary:
            root = Path(temporary)
            write_board_fixture(root)
            git_fixture(root, "init", "--quiet")
            git_fixture(root, "config", "user.name", "Fixture")
            git_fixture(root, "config", "user.email", "fixture@example.invalid")
            git_fixture(root, "symbolic-ref", "HEAD", "refs/heads/main")
            git_fixture(root, "add", "--all")
            git_fixture(root, "commit", "--quiet", "-m", "Fixture baseline")
            head = git_fixture(root, "rev-parse", "HEAD")
            server, thread = self.start_server(root)
            try:
                with urlopen(f"http://127.0.0.1:{server.server_port}/api/status") as response:
                    payload = json.loads(response.read())
            finally:
                self.stop_server(server, thread)
        reconciliation = payload["reconciliation"]
        self.assertEqual(reconciliation["availability"], "not_loaded")
        self.assertEqual(reconciliation["commit_range"]["status"], "NOT_LOADED")
        self.assertEqual(reconciliation["commit_range"]["to_commit"], head)
        self.assertEqual(reconciliation["commit_range"]["branch_ref"], "refs/heads/main")

    def test_placeholder_without_git_reports_no_head_instead_of_failing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-cs1-nogit-") as temporary:
            root = Path(temporary)
            with patch.object(serve_project_board, "git_head_and_branch", return_value=(None, None)) as probe:
                server, thread = self.start_server(root)
                server.status_cache.get_summary = Mock(return_value={"verification": {}})
                try:
                    with urlopen(f"http://127.0.0.1:{server.server_port}/api/status") as response:
                        payload = json.loads(response.read())
                    with self.assertRaises(HTTPError) as missing:
                        urlopen(f"http://127.0.0.1:{server.server_port}/source/planning/unknown.yml")
                    missing.exception.close()
                finally:
                    self.stop_server(server, thread)
            # The cheap HEAD probe belongs to /api/status only, never to asset requests.
            self.assertEqual(probe.call_count, 1)
        self.assertIsNone(payload["reconciliation"]["commit_range"]["to_commit"])
        self.assertIsNone(payload["reconciliation"]["commit_range"]["branch_ref"])

    def test_page_previews_exclude_standalone_interaction_artifacts(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-cs1-pages-") as temporary:
            root = Path(temporary)
            write_board_fixture(root)
            status = build_project_status.build_status_summary(root)
            previews = serve_project_board.build_page_previews(root, status)
        page_ids = [item["page_id"] for item in previews["items"]]
        self.assertEqual(page_ids, ["PAGE-001", "PAGE-002"])
        self.assertNotIn("PAGE-INTERACTION-STATES-REV1", page_ids)

    def test_parity_report_without_manifest_binding_is_a_linkable_source(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-cs1-parity-source-") as temporary:
            root = Path(temporary)
            write_board_fixture(root)
            server, thread = self.start_server(root)
            try:
                with urlopen(f"http://127.0.0.1:{server.server_port}/api/status") as response:
                    payload = json.loads(response.read())
                with urlopen(
                    f"http://127.0.0.1:{server.server_port}/source/planning/parity/SCN-FIXTURE-PAGE2.yaml"
                ) as response:
                    body = response.read().decode("utf-8")
            finally:
                self.stop_server(server, thread)
        references = [item for item in payload["source_references"]["items"] if item["source_type"] == "parity_report"]
        self.assertEqual([(item["canonical_path"], item["artifact_id"]) for item in references],
                         [("planning/parity/SCN-FIXTURE-PAGE2.yaml", "SCN-FIXTURE-PAGE2")])
        self.assertIn("scenario_id: SCN-FIXTURE-PAGE2", body)

    def test_latest_run_rule_is_single_and_server_side(self) -> None:
        def run(entry: str, run_id: str, captured_at: str, *, historical: bool = False) -> dict:
            return {
                "screen_id": "PAGE-001", "entry_id": entry, "run_id": run_id, "manifest_path": "m.yaml",
                "reference_path": "input-resources/ui-ux/main.html", "revision": "REV-001",
                "historical": historical, "parity_result": "PASS" if not historical else "FAIL",
                "captures": [{"captured_at": captured_at}],
            }
        old_current = run("E1", "R1", "2026-11-01T10:00:00Z")
        new_current = run("E2", "R2", "2026-11-03T10:00:00Z")
        newest_historical = run("E3", "R3", "2026-11-04T10:00:00Z", historical=True)
        self.assertIs(serve_project_board.select_latest_run([old_current, newest_historical, new_current]), new_current)
        self.assertIs(serve_project_board.select_latest_run([newest_historical]), newest_historical)
        self.assertIsNone(serve_project_board.select_latest_run([]))

        cache = serve_project_board.ProjectStatusCache(ROOT)
        with patch.object(cache, "get_summary", return_value={}), \
                patch.object(serve_project_board, "source_metadata_signature", return_value=None), \
                patch.object(serve_project_board, "build_status", return_value={
                    "source_fingerprint": "sha256:test",
                    "verification": {"gallery_state": "available", "gallery": [old_current, newest_historical, new_current]},
                }):
            gallery = cache.get_gallery()
        self.assertEqual(gallery["latest_runs"]["PAGE-001"],
                         {"entry_id": "E2", "run_id": "R2", "manifest_path": "m.yaml", "stale": False})

        status = {
            "project": {"active_targets": {"items": []}},
            "verification": {"gallery_state": "available", "gallery": [old_current, newest_historical, new_current]},
            "findings": {"availability": "available", "items": []},
            "runtime": {"recorded_readiness": None},
        }
        with tempfile.TemporaryDirectory(prefix="mxagile-board-cs1-latest-") as temporary:
            root = Path(temporary)
            write_board_fixture(root)
            previews = serve_project_board.build_page_previews(root, status)
        page = next(item for item in previews["items"] if item["page_id"] == "PAGE-001")
        self.assertEqual((page["last_verification_evidence"]["entry_id"], page["parity_status"]), ("E2", "PASS"))

    def test_board_client_contract_for_cs1_corrections(self) -> None:
        source = (ROOT / ".mxagile/board/board.js").read_text(encoding="utf-8")
        drift = source[source.index("function renderProjectDrift"):source.index("function renderAttention")]
        # BRD-F-01: not-loaded is handled before any watermark/BASELINE mapping.
        self.assertLess(drift.index('availability === "not_loaded"'), drift.index("BASELINE REQUIRED"))
        self.assertNotIn('range.to_commit || "UNKNOWN"', drift)
        # BRD-F-03: terminal findings resolve from history.
        self.assertIn("(status.findings.history || []).find((item) => item.id === id)", source)
        # BRD-F-04: no fabricated zero for mission blockers.
        self.assertNotIn('status.mission.status === "blocked" ? status.mission.blocker_count : 0', source)
        # BRD-F-08: the client uses the server latest-run decision instead of re-deriving it.
        self.assertIn("result.latest_runs", source)
        self.assertNotIn("relevantRuns.at(-1)", source)


if __name__ == "__main__":
    unittest.main()