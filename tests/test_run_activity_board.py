"""Run Activity API: validated audit projection, event-driven revision polling, and artifact-safe links."""

from __future__ import annotations

import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "scripts"), str(ROOT / "tests")]
import run_events  # noqa: E402
import serve_project_board  # noqa: E402
from test_board_http import write_board_fixture  # noqa: E402


class RunActivityBoardTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="mxagile-run-board-")
        self.root = Path(self._tmp.name)
        write_board_fixture(self.root)
        ui = self.root / ".mxagile/board"
        ui.mkdir(parents=True, exist_ok=True)
        (ui / "index.html").write_text("<html></html>", encoding="utf-8")
        self.server = serve_project_board.ProjectBoardServer(self.root, ui, 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        self._tmp.cleanup()

    def get_json(self, path: str) -> dict:
        with urlopen(self.url + path) as response:
            return json.loads(response.read())

    def test_api_validates_events_projects_active_runs_and_keeps_canonical_state_separate(self):
        before = self.get_json("/api/status")
        first_revision = self.get_json("/api/revision")["run_event_revision"]
        run_events.append_event(self.root, "child_started", run_id="RUN-child000001", parent_run_id="RUN-aabbccddeeff",
                                mission_id="MISSION-1", wave_id="W03", capability="runtime_visual_verification",
                                actor="mxagile-ui-agent", host="claude_code",
                                correlation={"delegation_id": "DELEGATION-001", "handoff_reference": ".concord/delegation-handoffs/DELEGATION-001.json"})
        opened = self.get_json("/api/run-activity?category=children&limit=20")
        self.assertEqual(opened["active_runs"][0]["status"], "RESULT_UNKNOWN")
        self.assertEqual(opened["active_runs"][0]["parent_run_id"], "RUN-aabbccddeeff")
        run_events.append_event(self.root, "verdict_received", run_id="RUN-child000001", parent_run_id="RUN-aabbccddeeff",
                                mission_id="MISSION-1", wave_id="W03", actor="child_result_acceptor", host="mxagile",
                                payload={"verdict": "pass", "round": 1})
        run_events.append_event(self.root, "child_accepted", run_id="RUN-child000001", parent_run_id="RUN-aabbccddeeff",
                                mission_id="MISSION-1", wave_id="W03", actor="child_result_acceptor", host="mxagile",
                                payload={"acceptance_status": "ACCEPTED"})
        after_revision = self.get_json("/api/revision")["run_event_revision"]
        self.assertNotEqual(first_revision, after_revision)
        activity = self.get_json("/api/run-activity?category=children&limit=20")
        self.assertEqual(activity["order"], "chronological_oldest_to_newest")
        self.assertEqual([item["event_type"] for item in activity["events"]], ["child_started", "child_accepted"])
        self.assertEqual(activity["active_runs"], [])
        after = self.get_json("/api/status")
        self.assertEqual(before["project"]["lifecycle"], after["project"]["lifecycle"])
        self.assertEqual(activity["state_authority"], "canonical_artifacts")

    def test_invalid_event_lines_are_counted_and_unknown_filters_rejected(self):
        run_events.append_event(self.root, "delivery_blocked", run_id="RUN-blocked0001", host="claude_code",
                                payload={"reason_codes": ["HEAD_STALE"], "recovery": "resync"})
        log = next((self.root / run_events.EVENT_DIR).glob("events-*.jsonl"))
        with log.open("ab") as handle:
            handle.write(b'{"schema_version":99}\n')
        result = self.get_json("/api/run-activity?category=warnings")
        self.assertEqual((len(result["events"]), result["invalid_lines"]), (1, 1))
        with self.assertRaises(HTTPError) as raised:
            urlopen(self.url + "/api/run-activity?category=unsafe")
        self.assertEqual(raised.exception.code, 400)
        raised.exception.close()

    def test_run_artifact_route_is_allowlisted_and_resolves_inside_project(self):
        evidence = self.root / ".concord/evidence/visual/screen.png"
        evidence.parent.mkdir(parents=True)
        evidence.write_bytes(b"png-probe")
        with urlopen(self.url + "/run-artifact/.concord/evidence/visual/screen.png") as response:
            self.assertEqual(response.read(), b"png-probe")
        with self.assertRaises(HTTPError) as raised:
            urlopen(self.url + "/run-artifact/.env")
        self.assertEqual(raised.exception.code, 404)
        raised.exception.close()


if __name__ == "__main__":
    unittest.main()
