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

    def test_unattested_plan_child_does_not_inherit_parent_or_adapter_model_claims(self) -> None:
        with tempfile.TemporaryDirectory(prefix='mxagile-model-evidence-') as temp_dir:
            project = Path(temp_dir)
            child = project / 'session-1' / 'subagents' / 'agent-plan.jsonl'
            child.parent.mkdir(parents=True)
            child.write_text(json.dumps({'type': 'assistant', 'message': {'role': 'assistant', 'content': []}}), encoding='utf-8')
            child.with_name('agent-plan.meta.json').write_text(json.dumps({'agentType': 'Plan', 'requested_profile': 'MID'}), encoding='utf-8')
            record = claude_collector._transcript_report(child, project, None, 'NOT_OBSERVABLE',
                parent_model_at_spawn='claude-opus-fixture', handoff={'requested_model': None})
            self.assertEqual(record['model']['requested_profile']['value'], 'MID')
            self.assertEqual(record['model']['spawn_request_model']['state'], OBSERVED)
            self.assertIsNone(record['model']['spawn_request_model']['value'])
            for field in ('resolved_profile', 'resolved_model', 'actual_model', 'provider'):
                self.assertEqual(record['model'][field]['state'], NOT_OBSERVABLE)
            self.assertEqual(record['model']['parent_model_at_spawn']['value'], 'claude-opus-fixture')

    def test_child_escalation_metadata_is_audited_without_model_attestation(self) -> None:
        with tempfile.TemporaryDirectory(prefix='mxagile-child-policy-') as temp_dir:
            project = Path(temp_dir)
            child = project / 'session-1' / 'subagents' / 'agent-child.jsonl'
            child.parent.mkdir(parents=True)
            child.write_text(json.dumps({'type': 'assistant', 'message': {'role': 'assistant', 'content': []}}), encoding='utf-8')
            metadata = {'main_profile': 'MID', 'requested_child_profile': 'HIGH', 'resolved_child_profile': 'HIGH',
                        'requested_child_model': 'host-high-model', 'escalation_policy': 'autonomous',
                        'escalation_authority': 'autonomous_policy', 'escalation_reason': 'Conflicting accepted contracts.',
                        'escalation_authority_reference': 'project:model_escalation', 'actual_model': 'unattested-claim'}
            child.with_suffix('.meta.json').write_text(json.dumps(metadata), encoding='utf-8')
            record = claude_collector._transcript_report(child, project, None, 'NOT_OBSERVABLE',
                parent_model_at_spawn='host-main-model', handoff={'requested_model': 'host-high-model'})
            for field in metadata.keys() - {'actual_model'}:
                self.assertEqual(record['model'][field]['value'], metadata[field])
                self.assertEqual(record['model'][field]['state'], DECLARED)
            self.assertEqual(record['model']['main_model']['value'], 'host-main-model')
            self.assertEqual(record['model']['main_model']['state'], OBSERVED)
            self.assertEqual(record['model']['spawn_request_model']['value'], 'host-high-model')
            self.assertEqual(record['model']['actual_model']['state'], NOT_OBSERVABLE)
            self.assertIsNone(record['model']['actual_model']['value'])

    def test_spawn_model_comes_from_agent_call_not_mid_metadata_or_named_agent_default(self) -> None:
        with tempfile.TemporaryDirectory(prefix='mxagile-spawn-boundary-') as temp_dir:
            project = Path(temp_dir)
            child = project / 'session-1' / 'subagents' / 'agent-discovery.jsonl'
            child.parent.mkdir(parents=True)
            child.write_text(json.dumps({'type': 'assistant', 'message': {'role': 'assistant', 'content': []}}), encoding='utf-8')
            child.with_suffix('.meta.json').write_text(json.dumps({
                'requested_profile': 'MID', 'resolved_profile': 'MID', 'resolved_model': 'sonnet',
                'model': 'sonnet', 'actual_model': 'sonnet',
            }), encoding='utf-8')
            for requested in ('sonnet', None, 'opus'):
                with self.subTest(requested=requested):
                    inputs = {'subagent_type': 'mxagile-discovery-agent', 'prompt': 'Analyze one bounded requirement batch.'}
                    if requested is not None:
                        inputs['model'] = requested
                    # Synthetic host-call fixtures prove collector behavior, not live execution.
                    events = [{'type': 'assistant', 'message': {'role': 'assistant', 'model': 'parent-model',
                               'content': [{'type': 'tool_use', 'id': 'call-1', 'name': 'Agent', 'input': inputs}]}}]
                    handoff = claude_collector._direct_tool_calls(events, project)['agent_calls'][0]
                    report = claude_collector._transcript_report(child, project, None, 'NOT_OBSERVABLE', handoff=handoff)
                    self.assertEqual(report['model']['requested_profile']['value'], 'MID')
                    self.assertEqual(report['model']['resolved_profile']['value'], 'MID')
                    self.assertEqual(report['model']['resolved_model']['state'], DECLARED)
                    self.assertEqual(report['model']['spawn_request_model']['value'], requested)
                    self.assertEqual(report['model']['spawn_request_model']['state'], OBSERVED)
                    self.assertEqual(report['model']['actual_model']['state'], NOT_OBSERVABLE)
                    self.assertIsNone(report['model']['actual_model']['value'])

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