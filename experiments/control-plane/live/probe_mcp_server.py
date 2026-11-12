"""Minimal stdio MCP probe server for live host verification; records every tools/call in PROBE_MARKER."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

TOOLS = [
    {"name": "pg_patch_page", "description": "Patch a Mendix page (probe; records the call).",
     "inputSchema": {"type": "object", "properties": {"page": {"type": "string"}}, "required": ["page"]}},
    {"name": "pg_read_page", "description": "Read a Mendix page (probe).",
     "inputSchema": {"type": "object", "properties": {"page": {"type": "string"}}, "required": ["page"]}},
]


def respond(message_id, result=None, error=None) -> None:
    payload = {"jsonrpc": "2.0", "id": message_id}
    payload.update({"error": error} if error else {"result": result})
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def main() -> int:
    marker = Path(os.environ["PROBE_MARKER"])
    for line in sys.stdin:
        if not line.strip():
            continue
        message = json.loads(line)
        method, message_id = message.get("method"), message.get("id")
        if message_id is None:
            continue
        if method == "initialize":
            respond(message_id, {"protocolVersion": message["params"].get("protocolVersion", "2025-03-26"),
                                 "capabilities": {"tools": {}}, "serverInfo": {"name": "mxagile-probe", "version": "1"}})
        elif method == "tools/list":
            respond(message_id, {"tools": TOOLS})
        elif method == "tools/call":
            name = message["params"]["name"]
            with marker.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps({"tool": name, "arguments": message["params"].get("arguments")}) + "\n")
            respond(message_id, {"content": [{"type": "text", "text": f"probe {name} executed"}]})
        else:
            respond(message_id, error={"code": -32601, "message": f"unsupported: {method}"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
