"""Expected client disconnect and visible builder failure HTTP contracts."""

from __future__ import annotations

import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.error import HTTPError
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import serve_project_board


class BoardHttpTests(unittest.TestCase):
    def test_expected_client_disconnect_is_logged_compactly(self) -> None:
        class BrokenWriter:
            def write(self, body: bytes) -> None:
                raise BrokenPipeError("client closed")

        handler = object.__new__(serve_project_board.ProjectBoardHandler)
        handler.wfile = BrokenWriter()
        handler.send_response = Mock()
        handler.send_header = Mock()
        handler.end_headers = Mock()
        handler.log_message = Mock()
        handler._send(200, b"payload", "application/json")
        handler.log_message.assert_called_once_with("CLIENT_DISCONNECT")

    def test_builder_failure_remains_visible_as_503(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-board-http-") as temporary:
            root = Path(temporary)
            ui_root = root / ".mxagile/board"
            ui_root.mkdir(parents=True, exist_ok=True)
            server = serve_project_board.ProjectBoardServer(root, ui_root, 0)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with patch.object(serve_project_board, "build_status", side_effect=RuntimeError("fixture failure")):
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