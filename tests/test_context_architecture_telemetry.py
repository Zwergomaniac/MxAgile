"""Synthetic, content-safe tests for the harness-neutral telemetry model."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import claude_jsonl_collector as claude_collector
import context_architecture_telemetry as shared_cli
from context_telemetry_model import DECLARED, NOT_OBSERVABLE, OBSERVED, new_session_record


class CanonicalTelemetryModelTests(unittest.TestCase):
    def test_missing_copilot_usage_is_run_scoped_not_a_capability_claim(self) -> None:
        record = new_session_record("vscode_copilot", "session-1", "run-1")

        self.assertEqual(record["harness"]["value"], "vscode_copilot")
        self.assertEqual(record["provider_usage"]["state"], NOT_OBSERVABLE)
        self.assertEqual(record["provider_usage"]["scope"], "this_collector_run")
        self.assertEqual(record["model"]["actual_model"]["state"], NOT_OBSERVABLE)
        self.assertEqual(record["delegation"]["context_relationship"]["state"], NOT_OBSERVABLE)
        self.assertNotIn("capability", record)

    def test_shared_cli_does_not_claim_harness_load_from_file_presence(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-c0-inventory-") as temp_dir:
            project = Path(temp_dir)
            (project / "CLAUDE.md").write_text("synthetic instruction", encoding="utf-8")

            report = shared_cli.build_report(project, "vscode_copilot", "session-1", "run-1")

            self.assertEqual(report["session"]["harness"]["state"], DECLARED)
            claude_file = next(
                item for item in report["source_inventory"]["instruction_files"]
                if item["path"] == "CLAUDE.md"
            )
            self.assertEqual(claude_file["file_presence"]["state"], OBSERVED)
            self.assertEqual(claude_file["file_presence"]["value"], "PRESENT")
            self.assertEqual(claude_file["runtime_load"]["state"], NOT_OBSERVABLE)

    def test_collector_is_not_wired_into_startup_injection_or_hooks(self) -> None:
        wiring_files = [
            ROOT / ".mxagile/orchestrator.md",
            ROOT / "scripts/apply-project-agent-instructions.ps1",
            ROOT / "scripts/install-core.ps1",
        ]
        for root in (ROOT / ".mxagile", ROOT / "scripts"):
            if root.is_dir():
                wiring_files.extend(
                    path
                    for path in root.rglob("*")
                    if path.is_file()
                    and any(token in path.name.lower() for token in ("hook", "pretool", "compaction"))
                    and path.suffix.lower() in {".md", ".ps1", ".py"}
                )

        for path in wiring_files:
            if not path.is_file():
                continue
            content = path.read_text(encoding="utf-8", errors="replace")
            self.assertNotIn("context_architecture_telemetry", content, str(path))
            self.assertNotIn("claude_jsonl_collector", content, str(path))

    def test_claude_jsonl_maps_runtime_evidence_into_shared_fields(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mxagile-c0-") as temp_dir:
            project = Path(temp_dir) / "project"
            child_dir = project / "session-1" / "subagents"
            child_dir.mkdir(parents=True)
            child_path = child_dir / "agent-child.jsonl"
            child_meta = child_path.with_name("agent-child.meta.json")

            child_meta.write_text(
                json.dumps(
                    {
                        "name": "worker",
                        "agentType": "fork",
                        "isFork": True,
                        "model": "inherit",
                        "toolUseId": "call-parent-1",
                        "finished": True,
                    }
                ),
                encoding="utf-8",
            )
            events = [
                {
                    "type": "api-request-blob",
                    "message": {
                        "role": "user",
                        "content": [{"type": "text", "text": "PRIVATE_API_BLOB_SENTINEL"}],
                    },
                },
                {
                    "type": "assistant",
                    "requestId": "request-child-1",
                    "message": {
                        "id": "message-child-1",
                        "model": "claude-sonnet-4-6",
                        "stop_reason": "end_turn",
                        "usage": {
                            "input_tokens": 9,
                            "output_tokens": 4,
                            "cache_read_input_tokens": 0,
                            "cache_creation_input_tokens": 0,
                        },
                        "content": [{"type": "text", "text": "PRIVATE_CHILD_OUTPUT_SENTINEL"}],
                    },
                },
            ]
            child_path.write_text("\n".join(json.dumps(event) for event in events), encoding="utf-8")

            report = claude_collector._transcript_report(
                child_path,
                project,
                None,
                "USER_CONTROLLED",
                parent_model_at_spawn="claude-sonnet-4-6",
                handoff={
                    "handoff_utf8_bytes": 123,
                    "result_utf8_bytes": 45,
                    "parent_model_at_spawn": "claude-sonnet-4-6",
                },
            )

            self.assertEqual(report["harness"]["state"], OBSERVED)
            self.assertEqual(report["agent_identity"]["parent"]["value"], "MAIN")
            self.assertEqual(report["agent_identity"]["child"]["value"]["name"], "worker")
            self.assertEqual(report["delegation"]["context_relationship"]["value"], "fork_inherit")
            self.assertEqual(report["delegation"]["handoff_utf8_bytes"]["value"], 123)
            self.assertEqual(report["delegation"]["result_utf8_bytes"]["value"], 45)
            self.assertEqual(report["model"]["requested_model"]["state"], DECLARED)
            self.assertEqual(report["model"]["requested_model"]["value"], "inherit")
            self.assertEqual(report["model"]["actual_model"]["value"], ["claude-sonnet-4-6"])
            self.assertEqual(report["model"]["provenance"]["state"], OBSERVED)
            self.assertEqual(report["model"]["parent_model_at_spawn"]["value"], "claude-sonnet-4-6")
            self.assertEqual(report["provider_usage"]["value"]["unique_api_requests"], 1)

            serialized = json.dumps(report, ensure_ascii=False)
            self.assertNotIn("PRIVATE_API_BLOB_SENTINEL", serialized)
            self.assertNotIn("PRIVATE_CHILD_OUTPUT_SENTINEL", serialized)


if __name__ == "__main__":
    unittest.main()