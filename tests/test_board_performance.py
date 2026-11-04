"""Synthetic read-only board performance, cache, and HTTP robustness fixtures."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import urlopen
from jsonschema import Draft7Validator
from temp_cleanup import cleanup_temporary_directory

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import build_project_status
import project_compatibility
import serve_project_board
from test_project_status import fixture, write_file


def build_performance_fixture(root: Path) -> None:
    fixture(root)
    waves = {
        f"W{index:02d}": {
            "phase": "implementing",
            "gates": {
                "gate_to_refinement": {"result": "passed"},
                "gate_to_ready": {"result": "passed"},
            },
        }
        for index in range(1, 9)
    }
    write_file(root, "planning/lifecycle/process-state.yaml", json.dumps({"waves": waves}, indent=2))
    for index in range(2, 41):
        req_id = f"REQ-{index:03d}"
        write_file(root, f"requirements/{req_id}.yml", f"""
            ID: {req_id}
            title: Requirement {index}
            description: Synthetic board performance requirement.
            status: accepted
            legacy_metadata: deterministic diagnostic candidate
        """)
    for index in range(1, 25):
        decision_id = f"DEC-{index:03d}"
        write_file(root, f"planning/decisions/{decision_id}.yml", f"""
            ID: {decision_id}
            title: Decision {index}
            status: PROPOSED
            decision_type: business
            topic: Synthetic decision {index}
            decision_text: Explicit fixture decision.
            owner: ProductOwner
            affected_requirements: [REQ-{index + 1:03d}]
        """)
    for wave_number in range(1, 9):
        wave_id = f"W{wave_number:02d}"
        checklist = f"planning/checklists/{wave_id}-implementation-checklist.yaml"
        write_file(root, checklist, f"wave_id: {wave_id}\nitems: []\n")
        for task_number in range(12):
            task_index = (wave_number - 1) * 12 + task_number + 3
            task_id = f"TASK-{task_index:03d}"
            requirement_id = f"REQ-{(task_index % 39) + 1:03d}"
            write_file(root, f"planning/tasks/{task_id}.yml", f"""
                ID: {task_id}
                spec: SPEC-001
                action: Synthetic task {task_index}
                status: pending
                wave_id: {wave_id}
                workpackage_id: WP-{wave_id}-01
                req: [{requirement_id}]
                migrated_from: {checklist}
            """)
    write_file(root, "specs/SPEC-001.yml", "ID: SPEC-001\ntitle: Synthetic spec\nrequirements: [REQ-001]\n")
    for index in range(1, 13):
        page_id = f"PAGE-PERF-{index:03d}"
        source = f"input-resources/ui-ux/Reference-{index:03d}.html"
        target = f"planning/target-mockups/Reference-{index:03d}.html"
        write_file(root, source, f"<html><body>Source {index}</body></html>\n")
        write_file(root, target, f"<html><body>Accepted target {index}</body></html>\n")
        write_file(root, f"planning/ui-inventory/{page_id}.yaml", f"""
            page_id: {page_id}
            page_name: Reference {index}
            source_mockup: {source}
            target_mockup: {target}
        """)


class BoardPerformanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="mxagile-board-perf-")
        self.root = Path(self.temporary.name) / "project"
        self.root.mkdir()
        build_performance_fixture(self.root)

    def tearDown(self) -> None:
        cleanup_temporary_directory(self.temporary, expected_prefix="mxagile-board-perf-")

    def _stub_status(self) -> dict:
        return {
            "schema_version": 2,
            "project": {"active_targets": {"items": [{
                "availability": "available",
                "canonical_path": "planning/target-mockups/Board/index.html",
                "reference_root": "planning/target-mockups/Board",
                "reference_type": "single_file_mockup",
            }]}}
        }

    def _stub_reconciliation(self, project_root: Path, *, project_status: dict) -> dict:
        return {
            "status": "NO_COMMITTED_DELTA",
            "commit_range": {"status": "NO_COMMITTED_DELTA", "commits": [], "spans": []},
            "watermark_gate": {"can_advance": False, "blockers": []},
            "finding_impacts": [],
            "external_reference_candidates": [],
            "impact_resolution": {"status": "BASELINE_REQUIRED", "candidates": []},
        }

    def test_p1_cold_build_returns_populated_status(self) -> None:
        status = build_project_status.build_status(self.root)
        self.assertEqual(status["schema_version"], 2)
        self.assertGreaterEqual(status["requirements"]["total"], 40)
        self.assertGreaterEqual(status["delivery"]["tasks"]["items"].__len__(), 98)
        self.assertGreaterEqual(status["decisions"]["total"], 24)
        self.assertGreaterEqual(len(status["project"]["active_targets"]["items"]), 12)
        self.assertGreaterEqual(len(status["compatibility"]["diagnostics"]), 30)

    def test_p2_unchanged_warm_request_reuses_projection(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        with patch.object(serve_project_board, "build_status_summary", side_effect=lambda root: self._stub_status()), \
             patch.object(serve_project_board, "build_report", side_effect=self._stub_reconciliation):
            first = cache.get()
            second = cache.get()
        self.assertEqual(cache.build_count, 1)
        self.assertIs(first, second)

    def test_p3_requirement_change_invalidates_projection(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        with patch.object(serve_project_board, "build_status_summary", side_effect=lambda root: self._stub_status()), \
             patch.object(serve_project_board, "build_report", side_effect=self._stub_reconciliation):
            cache.get()
            path = self.root / "requirements/REQ-002.yml"
            path.write_text(path.read_text(encoding="utf-8").replace("Requirement 2", "Changed requirement 2"), encoding="utf-8")
            cache.get()
        self.assertEqual(cache.build_count, 2)

    def test_p3b_same_mtime_content_edit_invalidates_by_metadata_signature(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        with patch.object(serve_project_board, "build_status_summary", side_effect=lambda root: self._stub_status()), \
             patch.object(serve_project_board, "build_report", side_effect=self._stub_reconciliation):
            cache.get()
            path = self.root / "requirements/REQ-002.yml"
            before = path.stat()
            original = path.read_text(encoding="utf-8")
            changed = original.replace("Requirement 2", "Requirement X")
            self.assertEqual(len(original), len(changed))
            path.write_text(changed, encoding="utf-8")
            os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
            cache.get()
        self.assertEqual(cache.build_count, 2)

    def test_p4_checklist_change_invalidates_projection(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        with patch.object(serve_project_board, "build_status_summary", side_effect=lambda root: self._stub_status()), \
             patch.object(serve_project_board, "build_report", side_effect=self._stub_reconciliation):
            cache.get()
            path = self.root / "planning/checklists/W01-implementation-checklist.yaml"
            path.write_text("wave_id: W01\nitems: [changed]\n", encoding="utf-8")
            cache.get()
        self.assertEqual(cache.build_count, 2)

    def test_p5_framework_schema_change_invalidates_projection(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        with patch.object(serve_project_board, "build_status_summary", side_effect=lambda root: self._stub_status()), \
             patch.object(serve_project_board, "build_report", side_effect=self._stub_reconciliation):
            cache.get()
            path = self.root / ".mxagile/schemas"
            path.mkdir(parents=True, exist_ok=True)
            (path / "finding.schema.json").write_text('{"version":1}\n', encoding="utf-8")
            cache.get()
        self.assertEqual(cache.build_count, 2)

    def test_p5c_python_bytecode_does_not_invalidate_status_projection(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        bytecode = self.root / "scripts/__pycache__/generated.cpython-314.pyc"
        bytecode.parent.mkdir(parents=True, exist_ok=True)
        bytecode.write_bytes(b"initial generated bytecode")
        with patch.object(serve_project_board, "build_status_summary", side_effect=lambda root: self._stub_status()):
            cache.get_summary()
            bytecode.write_bytes(b"generated bytecode")
            cache.get_summary()
        self.assertEqual(cache.build_count, 1)

    def test_p5d_theme_source_change_does_not_rescan_project_status(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        source = self.root / "themesource/Module/public/overview/Overview.html"
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text("<html>first</html>\n", encoding="utf-8")
        with patch.object(serve_project_board, "build_status_summary", side_effect=lambda root: self._stub_status()):
            cache.get_summary()
            source.write_text("<html>second</html>\n", encoding="utf-8")
            cache.get_summary()
        self.assertEqual(cache.build_count, 1)

    def test_p5b_schema_validator_rebuilds_after_schema_change(self) -> None:
        schema_root = self.root / "schema-contracts"
        schema_root.mkdir()
        schema_path = schema_root / "sample.schema.json"
        schema_path.write_text(json.dumps({"$schema": "http://json-schema.org/draft-07/schema#", "type": "object", "properties": {"kind": {"enum": ["a"]}}}), encoding="utf-8")
        with patch.object(project_compatibility, "SCHEMA_ROOT", schema_root):
            with project_compatibility.schema_validation_scope():
                self.assertTrue(project_compatibility.schema_validator(schema_path).is_valid({"kind": "a"}))
            schema_path.write_text(json.dumps({"$schema": "http://json-schema.org/draft-07/schema#", "type": "object", "properties": {"kind": {"enum": ["b"]}}}), encoding="utf-8")
            with project_compatibility.schema_validation_scope():
                self.assertTrue(project_compatibility.schema_validator(schema_path).is_valid({"kind": "b"}))

    def test_contract_lookup_is_bounded_cached_and_semantics_identical(self) -> None:
        project_compatibility.contract_for.cache_clear()
        try:
            results = [project_compatibility.contract_for("planning/tasks/TASK-001.yml") for _ in range(500)]
            self.assertTrue(all(result == ("task", "tasks") for result in results))
            stats = project_compatibility.contract_for.cache_info()
            self.assertEqual(stats.misses, 1)
            self.assertEqual(stats.hits, 499)
        finally:
            project_compatibility.contract_for.cache_clear()

    def test_yaml_parse_cache_is_exact_content_keyed_and_bounded(self) -> None:
        project_compatibility._parse_yaml.cache_clear()
        original_load = project_compatibility.yaml.load
        try:
            with patch.object(project_compatibility.yaml, "load", wraps=original_load) as parse:
                first = project_compatibility.load_yaml(b"kind: first\n")
                second = project_compatibility.load_yaml(b"kind: first\n")
                changed = project_compatibility.load_yaml(b"kind: second\n")
            self.assertEqual(first, second)
            self.assertEqual(changed, {"kind": "second"})
            self.assertEqual(parse.call_count, 2)
        finally:
            project_compatibility._parse_yaml.cache_clear()

    def test_p6_reference_authority_change_invalidates_projection(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        with patch.object(serve_project_board, "build_status_summary", side_effect=lambda root: self._stub_status()), \
             patch.object(serve_project_board, "build_report", side_effect=self._stub_reconciliation):
            cache.get()
            path = self.root / "planning/ui-inventory/PAGE-PERF-001.yaml"
            path.write_text(path.read_text(encoding="utf-8").replace("Reference-001.html", "Reference-002.html"), encoding="utf-8")
            cache.get()
        self.assertEqual(cache.build_count, 2)

    def test_p6b_mpr_model_change_invalidates_even_when_mtime_is_restored(self) -> None:
        mpr = self.root / "Fixture.mpr"
        mpr.write_bytes(b"model-a")
        cache = serve_project_board.ProjectStatusCache(self.root)
        with patch.object(serve_project_board, "build_status_summary", side_effect=lambda root: self._stub_status()), \
             patch.object(serve_project_board, "build_report", side_effect=self._stub_reconciliation):
            cache.get()
            before = mpr.stat()
            mpr.write_bytes(b"model-b")
            os.utime(mpr, ns=(before.st_atime_ns, before.st_mtime_ns))
            cache.get()
        self.assertEqual(cache.build_count, 2)

    def test_p7_asset_request_reuses_status_snapshot(self) -> None:
        ui_root = self.root / ".mxagile/board"
        ui_root.mkdir(parents=True, exist_ok=True)
        target = self.root / "planning/target-mockups/Board/index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("<html>target</html>\n", encoding="utf-8")
        new_candidate = self.root / "input-resources/ui-ux/new.html"
        new_candidate.parent.mkdir(parents=True, exist_ok=True)
        new_candidate.write_text("<html>new proposal</html>\n", encoding="utf-8")
        server = serve_project_board.ProjectBoardServer(self.root, ui_root, 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with patch.object(serve_project_board, "build_status_summary", side_effect=lambda root: self._stub_status()), \
                 patch.object(serve_project_board, "build_report", return_value={
                     **self._stub_reconciliation(self.root, project_status=self._stub_status()),
                     "external_reference_candidates": [{"path": "input-resources/ui-ux/new.html", "status": "REFERENCE_RECONCILIATION_REQUIRED"}],
                 }) as build_report:
                with urlopen(f"http://127.0.0.1:{server.server_port}/api/status") as response:
                    self.assertEqual(response.status, 200)
                    status = json.loads(response.read())
                    self.assertEqual(status["reconciliation"]["status"], "NOT_LOADED")
                    self.assertNotIn("page_previews", status)
                build_report.assert_not_called()
                with urlopen(f"http://127.0.0.1:{server.server_port}/api/reconciliation") as response:
                    reconciliation = json.loads(response.read())
                    self.assertEqual(reconciliation["reconciliation"]["external_reference_candidates"][0]["path"], "input-resources/ui-ux/new.html")
                build_report.assert_called_once()
                with urlopen(f"http://127.0.0.1:{server.server_port}/reference/planning/target-mockups/Board/index.html") as response:
                    self.assertIn(b"target", response.read())
                with self.assertRaises(HTTPError) as candidate_response:
                    urlopen(f"http://127.0.0.1:{server.server_port}/reference/input-resources/ui-ux/new.html")
                self.assertEqual(candidate_response.exception.code, 404)
                candidate_response.exception.close()
                self.assertEqual(server.status_cache.build_count, 1)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_p7b_page_gallery_is_cached_per_screen_for_unchanged_sources(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        summary = {
            "schema_version": 2,
            "source_fingerprint": "sha256:summary",
            "verification": {"gallery": [], "gallery_state": "not_loaded"},
        }
        full_status = {
            "source_fingerprint": "sha256:full",
            "verification": {
                "gallery_state": "available",
                "gallery": [
                    {"screen_id": "PAGE-PERF-001", "parity_result": "PASS"},
                    {"screen_id": "PAGE-PERF-002", "parity_result": "FAIL"},
                ],
            },
        }
        def build_screen_status(root: Path, *, include_gallery: bool, gallery_screen_id: str | None) -> dict:
            self.assertTrue(include_gallery)
            return {
                **full_status,
                "verification": {
                    "gallery_state": "available",
                    "gallery": [
                        item for item in full_status["verification"]["gallery"]
                        if gallery_screen_id is None or item["screen_id"] == gallery_screen_id
                    ],
                },
            }
        with patch.object(serve_project_board, "build_status_summary", return_value=summary), \
             patch.object(serve_project_board, "build_status", side_effect=build_screen_status) as full_builder:
            first = cache.get_gallery("PAGE-PERF-001")
            second = cache.get_gallery("PAGE-PERF-001")
        self.assertEqual(first["gallery_state"], "available")
        self.assertEqual([item["screen_id"] for item in first["items"]], ["PAGE-PERF-001"])
        self.assertEqual(second, first)
        full_builder.assert_called_once_with(
            self.root, include_gallery=True, gallery_screen_id="PAGE-PERF-001"
        )

    def test_p7c_page_gallery_invalidates_after_relevant_source_change(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        summary = {
            "schema_version": 2,
            "source_fingerprint": "sha256:summary",
            "verification": {"gallery": [], "gallery_state": "not_loaded"},
        }
        calls = 0

        def build_screen_status(root: Path, *, include_gallery: bool, gallery_screen_id: str | None) -> dict:
            nonlocal calls
            calls += 1
            self.assertTrue(include_gallery)
            return {
                "source_fingerprint": f"sha256:gallery-{calls}",
                "verification": {"gallery_state": "available", "gallery": [{"screen_id": gallery_screen_id}]},
            }

        with patch.object(serve_project_board, "build_status_summary", return_value=summary), \
             patch.object(serve_project_board, "build_status", side_effect=build_screen_status):
            cache.get_gallery("PAGE-PERF-001")
            source = self.root / "requirements/REQ-002.yml"
            source.write_text(source.read_text(encoding="utf-8").replace("Requirement 2", "Changed requirement 2"), encoding="utf-8")
            second = cache.get_gallery("PAGE-PERF-001")
        self.assertEqual(calls, 2)
        self.assertEqual(cache.build_count, 2)
        self.assertEqual(second["source_fingerprint"], "sha256:gallery-2")

    def test_p8_concurrent_requests_are_single_flight(self) -> None:
        ui_root = self.root / ".mxagile/board"
        ui_root.mkdir(parents=True, exist_ok=True)
        server = serve_project_board.ProjectBoardServer(self.root, ui_root, 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        started = threading.Event()
        release = threading.Event()
        calls = 0

        def builder(root: Path) -> dict:
            nonlocal calls
            calls += 1
            started.set()
            if not release.wait(timeout=5):
                raise TimeoutError("test release was not signalled")
            return self._stub_status()

        try:
            with patch.object(serve_project_board, "build_status_summary", side_effect=builder), \
                 patch.object(serve_project_board, "build_report", side_effect=self._stub_reconciliation):
                def request_status() -> dict:
                    with urlopen(f"http://127.0.0.1:{server.server_port}/api/status") as response:
                        return json.loads(response.read())

                with ThreadPoolExecutor(max_workers=5) as executor:
                    futures = [executor.submit(request_status) for _ in range(5)]
                    self.assertTrue(started.wait(timeout=5))
                    release.set()
                    statuses = [future.result(timeout=10) for future in futures]
            self.assertEqual(calls, 1)
            self.assertEqual(server.status_cache.build_count, 1)
            self.assertTrue(all(status is statuses[0] or status == statuses[0] for status in statuses))
        finally:
            release.set()
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_p8b_concurrent_builder_failure_fans_out_without_failure_cache(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        started = threading.Event()
        waiters_ready = threading.Event()
        release = threading.Event()
        calls = 0
        wait_count = 0
        count_lock = threading.Lock()
        original_wait = cache._condition.wait

        def track_wait(timeout: float | None = None) -> bool:
            nonlocal wait_count
            with count_lock:
                wait_count += 1
                if wait_count >= 4:
                    waiters_ready.set()
            return original_wait(timeout)

        cache._condition.wait = track_wait

        def failing_builder(root: Path) -> dict:
            nonlocal calls
            calls += 1
            started.set()
            if not release.wait(timeout=5):
                raise TimeoutError("test release was not signalled")
            raise RuntimeError("synthetic builder failure")

        with patch.object(serve_project_board, "build_status_summary", side_effect=failing_builder), \
             patch.object(serve_project_board, "build_report", side_effect=self._stub_reconciliation):
            with ThreadPoolExecutor(max_workers=5) as executor:
                futures = [executor.submit(cache.get) for _ in range(5)]
                self.assertTrue(started.wait(timeout=5))
                self.assertTrue(waiters_ready.wait(timeout=5))
                release.set()
                for future in futures:
                    with self.assertRaises(RuntimeError):
                        future.result(timeout=10)
            self.assertEqual(calls, 1)
            self.assertEqual(cache.build_count, 1)
            with self.assertRaisesRegex(RuntimeError, "synthetic builder failure"):
                cache.get()
        self.assertEqual(calls, 2)

    def test_p10_builder_failure_is_not_cached_or_classified_as_disconnect(self) -> None:
        cache = serve_project_board.ProjectStatusCache(self.root)
        failure = RuntimeError("fixture builder failure")
        with patch.object(serve_project_board, "build_status_summary", side_effect=failure), \
             patch.object(serve_project_board, "build_report", side_effect=self._stub_reconciliation):
            with self.assertRaisesRegex(RuntimeError, "fixture builder failure"):
                cache.get()
        self.assertEqual(cache.build_count, 1)
        self.assertIsNone(cache._status)

    def test_combined_server_snapshot_matches_status_schema(self) -> None:
        status = serve_project_board.ProjectStatusCache(self.root).get()
        schema = json.loads((ROOT / ".mxagile/schemas/project-status.schema.json").read_text(encoding="utf-8"))
        errors = list(Draft7Validator(schema).iter_errors(status))
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()