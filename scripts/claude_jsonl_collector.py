"""Opt-in context-architecture measurements. No prompts or tool contents are emitted."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from context_telemetry_model import DECLARED, NOT_OBSERVABLE, OBSERVED, new_session_record, not_observable, observation


POLICY_REFERENCE = re.compile(
    r"(?:\.mxagile[\\/]policies[\\/]|policies[\\/])([A-Za-z0-9._-]+\.md)",
    re.IGNORECASE,
)
READ_COMMAND = re.compile(r"\b(Get-Content|cat|head|tail|sed|less)\b", re.IGNORECASE)
SEARCH_COMMAND = re.compile(r"\b(rg|grep|Select-String)\b", re.IGNORECASE)


def _utc(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed.astimezone(timezone.utc)


def _bytes(value: Any) -> int:
    if isinstance(value, str):
        return len(value.encode("utf-8"))
    if isinstance(value, list):
        return sum(_bytes(block.get("text", "")) for block in value if isinstance(block, dict))
    if isinstance(value, dict):
        return _bytes(value.get("text", ""))
    return 0


def _safe_path(value: str, project_root: Path) -> str:
    path = Path(value)
    try:
        return path.resolve().relative_to(project_root.resolve()).as_posix()
    except (OSError, ValueError):
        return f"external:{path.name}"


def _file_entry(path: Path, project_root: Path, source_class: str) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
    except OSError:
        return {
            "path": _safe_path(str(path), project_root),
            "source_class": source_class,
            "file_presence": not_observable("File metadata could not be read in this collector run."),
            "runtime_load": not_observable("File presence/loading could not be attested by this collector run."),
        }
    text = raw.decode("utf-8", errors="replace")
    return {
        "path": _safe_path(str(path), project_root),
        "source_class": source_class,
        "file_presence": observation(OBSERVED, "PRESENT", "local filesystem metadata"),
        "runtime_load": not_observable("File presence is not evidence that the harness loaded this file."),
        "utf8_bytes": len(raw),
        "characters": len(text),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def source_inventory(project_root: Path) -> dict[str, Any]:
    instruction_paths = [
        project_root / "CLAUDE.md",
        project_root / "AGENT.md",
        project_root / "AGENTS.md",
        project_root / ".github/copilot-instructions.md",
    ]
    instructions = [
        _file_entry(path, project_root, "instruction_source")
        for path in instruction_paths
        if path.is_file()
    ]
    projection_roots = {
        "claude_agents": project_root / ".claude/agents",
        "claude_skills": project_root / ".claude/skills",
        "copilot_skills": project_root / ".github/skills",
        "codex_skills": project_root / ".agents/skills",
        "grok_skills": project_root / ".grok/skills",
        "opencode_skills": project_root / ".opencode/skills",
        "hermes_skills": project_root / ".hermes/skills",
    }
    projections: dict[str, Any] = {}
    for name, root in projection_roots.items():
        files = [path for path in root.rglob("*") if path.is_file()] if root.is_dir() else []
        projections[name] = {
            "source_class": "GENERATED_PROJECTION",
            "file_presence": observation(OBSERVED, len(files), "local filesystem inventory"),
            "runtime_load": not_observable("Harness load was not attested in this collector run; file presence is not runtime-load evidence."),
            "files": len(files),
            "utf8_bytes": sum(path.stat().st_size for path in files),
        }
    return {
        "instruction_files": instructions,
        "generated_projections": projections,
        "note": "On-disk bytes do not prove harness loading. Supply a loaded-instruction manifest to attest actual injected paths.",
    }


def _read_events(path: Path, cutoff: datetime | None) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as source:
        for line in source:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            event_time = _utc(event.get("timestamp"))
            if cutoff and event_time and event_time > cutoff:
                continue
            yield event


def _direct_tool_calls(events: list[dict[str, Any]], project_root: Path) -> dict[str, Any]:
    calls: dict[str, tuple[str, dict[str, Any]]] = {}
    unique_tools: set[str] = set()
    tool_counts: Counter[str] = Counter()
    read_paths: Counter[str] = Counter()
    read_result_bytes: Counter[str] = Counter()
    context_mode_counts: Counter[str] = Counter()
    context_mode_result_bytes: Counter[str] = Counter()
    agent_calls: dict[str, dict[str, Any]] = {}

    for event in events:
        message = event.get("message")
        if event.get("type") != "assistant" or not isinstance(message, dict):
            continue
        for block in message.get("content", []) or []:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            tool_id = block.get("id")
            if tool_id and tool_id in unique_tools:
                continue
            if tool_id:
                unique_tools.add(tool_id)
            name = str(block.get("name", "UNKNOWN"))
            tool_counts[name] += 1
            inputs = block.get("input") if isinstance(block.get("input"), dict) else {}
            if tool_id:
                calls[tool_id] = (name, inputs)
            if name == "Read":
                value = inputs.get("file_path") or inputs.get("path")
                if isinstance(value, str):
                    read_paths[_safe_path(value, project_root)] += 1
            if name == "Bash":
                command = str(inputs.get("command", ""))
                category = "read" if READ_COMMAND.search(command) else "search" if SEARCH_COMMAND.search(command) else "other"
                for policy in set(POLICY_REFERENCE.findall(command)):
                    key = f"{category}:{policy}"
                    read_paths[key] += 1
            if name.startswith("mcp__plugin_context-mode_context-mode__ctx_"):
                context_mode_counts[name.rsplit("__", 1)[-1]] += 1
                if name.endswith("__ctx_execute_file"):
                    value = inputs.get("path") or inputs.get("file_path")
                    if isinstance(value, str):
                        read_paths[f"context_mode:{_safe_path(value, project_root)}"] += 1
            if name == "Agent":
                agent_calls[str(tool_id)] = {
                    "tool_call_id": tool_id,
                    "name": inputs.get("name"),
                    "agent_type": inputs.get("subagent_type"),
                    "requested_model": inputs.get("model"),
                    "handoff_utf8_bytes": len(json.dumps(inputs, ensure_ascii=False).encode("utf-8")),
                    "parent_model_at_spawn": message.get("model"),
                }

    result_bytes = Counter()
    result_counts = Counter()
    for event in events:
        message = event.get("message")
        if event.get("type") != "user" or not isinstance(message, dict):
            continue
        for block in message.get("content", []) or []:
            if not isinstance(block, dict) or block.get("type") != "tool_result":
                continue
            use_id = block.get("tool_use_id")
            name = calls.get(use_id, ("UNKNOWN", {}))[0]
            size = _bytes(block.get("content", ""))
            result_counts[name] += 1
            result_bytes[name] += size
            if name == "Read":
                inputs = calls.get(use_id, (name, {}))[1]
                value = inputs.get("file_path") or inputs.get("path")
                if isinstance(value, str):
                    read_result_bytes[_safe_path(value, project_root)] += size
            if name.startswith("mcp__plugin_context-mode_context-mode__ctx_"):
                context_mode_result_bytes[name.rsplit("__", 1)[-1]] += size

    return {
        "unique_tool_calls": dict(tool_counts),
        "tool_result_utf8_bytes": dict(result_bytes),
        "tool_result_counts": dict(result_counts),
        "direct_read_calls_by_path": dict(read_paths),
        "direct_read_result_utf8_bytes_by_path": dict(read_result_bytes),
        "context_mode_calls": dict(context_mode_counts),
        "context_mode_result_utf8_bytes": dict(context_mode_result_bytes),
        "agent_calls": list(agent_calls.values()),
    }


def _transcript_report(
    path: Path,
    project_root: Path,
    cutoff: datetime | None,
    main_model_provenance: str,
    parent_model_at_spawn: str | None = None,
    handoff: dict[str, Any] | None = None,
    loaded_instruction_paths: list[str] | None = None,
) -> dict[str, Any]:
    metadata_path = path.with_name(path.name.replace(".jsonl", ".meta.json"))
    metadata: dict[str, Any] = {}
    if metadata_path.is_file():
        try:
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            metadata = {}

    events = list(_read_events(path, cutoff))
    usage_by_request: dict[str, tuple[str, dict[str, Any]]] = {}
    conflicting_usage_requests = 0
    usage_signatures: dict[str, set[str]] = defaultdict(set)
    all_api_events = 0
    model_messages: Counter[str] = Counter()
    compactions: list[dict[str, Any]] = []
    text_output_bytes = 0
    request_message_events = 0
    final_text_bytes = 0
    end_turn_events = 0
    first_time: str | None = None
    last_time: str | None = None

    for event in events:
        stamp = event.get("timestamp")
        if stamp:
            parsed = _utc(stamp)
            if parsed:
                first_time = first_time or stamp
                last_time = stamp
        if event.get("type") == "system" and "compact" in str(event.get("subtype", "")).lower():
            compact_meta = event.get("compactMetadata") if isinstance(event.get("compactMetadata"), dict) else {}
            compactions.append({"timestamp": stamp, "pre_tokens": compact_meta.get("preTokens")})

        message = event.get("message")
        if event.get("type") == "api-request-blob" and isinstance(message, dict):
            text_output_bytes += _bytes(message.get("content", []))
            request_message_events += 1
        if event.get("type") != "assistant" or not isinstance(message, dict):
            continue
        if message.get("stop_reason") == "end_turn":
            final_text_bytes = _bytes(message.get("content", []))
            end_turn_events += 1
        usage = message.get("usage")
        request_id = event.get("requestId")
        if not isinstance(usage, dict) or not request_id:
            continue
        all_api_events += 1
        model = str(message.get("model") or "NOT_OBSERVABLE")
        signature = json.dumps(usage, sort_keys=True, ensure_ascii=False)
        usage_signatures[str(request_id)].add(signature)
        usage_by_request[str(request_id)] = (model, usage)
        model_messages[model] += 1

    conflicting_usage_requests = sum(1 for signatures in usage_signatures.values() if len(signatures) > 1)
    model_usage: dict[str, dict[str, int]] = {}
    for model, usage in usage_by_request.values():
        target = model_usage.setdefault(model, {"requests": 0, "input_tokens": 0, "output_tokens": 0, "cache_read_tokens": 0, "cache_write_tokens": 0})
        target["requests"] += 1
        target["input_tokens"] += int(usage.get("input_tokens") or 0)
        target["output_tokens"] += int(usage.get("output_tokens") or 0)
        target["cache_read_tokens"] += int(usage.get("cache_read_input_tokens") or 0)
        target["cache_write_tokens"] += int(usage.get("cache_creation_input_tokens") or 0)

    is_main = path.parent.name != "subagents"
    agent_name = "MAIN" if is_main else metadata.get("name")
    transcript_id = path.stem
    session_id = path.stem if is_main else path.parent.parent.name
    record = new_session_record("claude_code", session_id, transcript_id)
    record["collector_id"] = observation(OBSERVED, "claude_jsonl", "collector_adapter")
    record["harness"] = (
        observation(OBSERVED, "claude_code", "Claude transcript JSONL event schema")
        if events
        else not_observable("No parseable Claude transcript events were present in this collector run.")
    )
    record["session_identity"] = observation(OBSERVED, session_id, "Claude transcript directory/filename")
    record["run_identity"] = observation(OBSERVED, transcript_id, "Claude transcript filename")
    record["collection_scope"] = observation(DECLARED, "this_collector_run", "Claude JSONL adapter report scope")
    record["agent_identity"]["parent"] = (
        not_observable("Main session has no parent agent.")
        if is_main
        else observation(OBSERVED, "MAIN", "Claude subagent metadata/session layout")
    )
    record["agent_identity"]["child"] = (
        observation(OBSERVED, {"name": agent_name, "run_id": transcript_id}, "Claude subagent metadata")
        if not is_main
        else not_observable("Main session is not a child agent.")
    )
    record["delegation"]["type"] = (
        observation(OBSERVED, metadata.get("agentType", "unknown"), "Claude subagent metadata")
        if not is_main
        else observation(OBSERVED, "main", "Claude main transcript")
    )
    fork = metadata.get("isFork") if not is_main else False
    record["delegation"]["context_relationship"] = (
        observation(OBSERVED, "fork_inherit" if fork else "fresh_context", "Claude subagent metadata isFork")
        if not is_main and isinstance(fork, bool)
        else not_observable("Fork/fresh context relationship was not recorded.")
        if not is_main
        else observation(OBSERVED, "main_context", "Claude main transcript")
    )
    if handoff:
        record["delegation"]["handoff_utf8_bytes"] = observation(
            OBSERVED, handoff.get("handoff_utf8_bytes"), "parent Agent tool input JSON bytes"
        )
        record["delegation"]["result_utf8_bytes"] = observation(
            OBSERVED if handoff.get("result_utf8_bytes") is not None else NOT_OBSERVABLE,
            handoff.get("result_utf8_bytes"),
            "parent Agent tool result bytes" if handoff.get("result_utf8_bytes") is not None else None,
            None if handoff.get("result_utf8_bytes") is not None else "Parent result event was not recorded.",
        )
    else:
        record["delegation"]["handoff_utf8_bytes"] = not_observable("No parent handoff was available to this transcript collector.")
        record["delegation"]["result_utf8_bytes"] = not_observable("No parent result was available to this transcript collector.")

    requested_model = metadata.get("model") if not is_main else None
    record["model"]["requested_profile"] = not_observable("No MxAgile model profile was present in the transcript metadata.")
    record["model"]["requested_model"] = (
        observation(DECLARED, requested_model, "Claude subagent metadata")
        if requested_model
        else not_observable("No requested model field was present in the transcript metadata.")
    )
    actual_models = sorted(model_usage)
    record["model"]["actual_model"] = (
        observation(OBSERVED, actual_models, "Claude message.model on unique requestId records")
        if actual_models
        else not_observable("No actual provider model was recorded in the transcript.")
    )
    record["model"]["provenance"] = (
        observation(DECLARED, main_model_provenance, "explicit caller-provided session provenance")
        if is_main and main_model_provenance != "NOT_OBSERVABLE"
        else observation(OBSERVED, "requested_model_inherited", "Claude subagent model metadata")
        if not is_main and requested_model == "inherit"
        else not_observable("Model selection provenance was not recorded for this collector run.")
    )
    record["model"]["parent_model_at_spawn"] = (
        observation(OBSERVED, parent_model_at_spawn, "parent Agent call message.model")
        if parent_model_at_spawn
        else not_observable("Parent model at spawn was not available.")
    )

    tooling = _direct_tool_calls(events, project_root)
    record["loads"]["instruction_or_projection_paths"] = (
        observation(OBSERVED, loaded_instruction_paths, "explicit loaded-instruction manifest")
        if loaded_instruction_paths is not None
        else not_observable("The collector cannot infer harness instruction loads from files on disk.")
    )
    record["loads"]["file_reads"] = observation(
        OBSERVED,
        {"calls_by_path": tooling["direct_read_calls_by_path"], "result_utf8_bytes_by_path": tooling["direct_read_result_utf8_bytes_by_path"]},
        "Claude Read tool events",
    )
    record["loads"]["policy_reads"] = observation(
        OBSERVED,
        {key: value for key, value in tooling["direct_read_calls_by_path"].items() if "policy" in key.lower() or key.endswith(".md")},
        "Claude Read/Bash/Context Mode event paths; excerpts are not full-policy loads",
    )
    record["loads"]["skill_reads"] = observation(
        OBSERVED,
        {"invocations": tooling["unique_tool_calls"].get("Skill", 0)},
        "Claude Skill tool events",
    )
    tool_result_bytes = sum(tooling["tool_result_utf8_bytes"].values())
    record["context_sizes"]["request_message_utf8_bytes"] = (
        observation(OBSERVED, text_output_bytes, "Claude api-request-blob.message proxy; not complete prompt context")
        if request_message_events
        else not_observable("No api-request-blob message was recorded in this collector run.")
    )
    record["context_sizes"]["tool_result_utf8_bytes"] = observation(
        OBSERVED, tool_result_bytes, "Claude tool_result content bytes"
    )
    record["context_sizes"]["tool_result_utf8_bytes_by_tool"] = observation(
        OBSERVED, tooling["tool_result_utf8_bytes"], "Claude tool_result content bytes"
    )
    record["tool_invocations"] = observation(
        OBSERVED, tooling["unique_tool_calls"], "Claude tool_use events"
    )
    record["provider_usage"] = (
        observation(
            OBSERVED,
            {
                "by_actual_model": model_usage,
                "unique_api_requests": len(usage_by_request),
                "stream_events": all_api_events,
                "requests_with_conflicting_usage_records": conflicting_usage_requests,
            },
            "Claude message.usage deduplicated by requestId",
        )
        if usage_by_request
        else not_observable("No provider usage event was recorded in this collector run.")
    )
    record["provider_cost"] = not_observable("Claude local transcript does not contain billable session cost.")
    record["compaction_resume"] = {
        "compaction_events": observation(OBSERVED, compactions, "Claude system compact markers"),
        "resume_events": not_observable("This collector does not distinguish session resume from continuation."),
    }
    record["collector_extensions"]["claude_jsonl"] = {
        "api_events": all_api_events,
        "unique_api_requests": len(usage_by_request),
        "requests_with_conflicting_usage_records": conflicting_usage_requests,
        "tool_events": tooling,
        "transcript_time": {"start": first_time, "end": last_time},
        "last_end_turn_text_bytes": (
            observation(OBSERVED, final_text_bytes, "Claude transcript end_turn text blocks")
            if end_turn_events
            else not_observable("No end_turn text event was recorded in this collector run.")
        ),
        "child_completion": (
            observation(OBSERVED, metadata.get("finished"), "Claude child metadata finished field")
            if not is_main and isinstance(metadata.get("finished"), bool)
            else not_observable("Child completion metadata is absent in this collector run.")
            if not is_main
            else not_observable("Not applicable to a main transcript.")
        ),
    }
    return record


def build_report(
    project_root: Path,
    session_file: Path | None,
    cutoff_text: str | None,
    main_model_provenance: str,
    loaded_manifest: Path | None,
) -> dict[str, Any]:
    cutoff = _utc(cutoff_text)
    loaded: list[str] | None = None
    if loaded_manifest:
        try:
            loaded = [line.strip() for line in loaded_manifest.read_text(encoding="utf-8").splitlines() if line.strip()]
        except OSError:
            loaded = None

    report: dict[str, Any] = {
        "telemetry_version": 1,
        "collector_id": "claude_jsonl" if session_file else "source_inventory",
        "collector_scope": "NOT_OBSERVABLE applies to this collector run and is not a harness capability claim.",
        "measured_at": datetime.now(timezone.utc).isoformat(),
        "project_root_label": project_root.name,
        "cutoff_utc": cutoff.isoformat() if cutoff else None,
        "main_model_provenance": observation(
            DECLARED, main_model_provenance, "explicit caller-supplied provenance"
        ) if main_model_provenance != "NOT_OBSERVABLE" else not_observable(
            "No main-model provenance was supplied for this collector run."
        ),
        "source_inventory": source_inventory(project_root),
        "loaded_instruction_manifest": observation(
            DECLARED, loaded, "caller-supplied manifest; harness evidence was not independently verified"
        ) if loaded is not None else not_observable(
            "No harness-loaded instruction manifest was supplied; disk presence is not runtime-load evidence."
        ),
        "transcript_availability": observation(OBSERVED, "AVAILABLE", "Claude JSONL input") if session_file and session_file.is_file() else not_observable("No transcript was supplied."),
        "transcripts": [],
        "limitations": [
            "No message, prompt, command, tool result, secret, or full transcript content is emitted.",
            "Source/projection file bytes do not prove the harness loaded that file.",
            "API request message bytes exclude system prompt, tool schemas, provider framing, and cache accounting.",
            "Provider billing totals must be supplied separately; local transcript usage is not a billable-dollar ledger.",
        ],
    }
    if not session_file or not session_file.is_file():
        return report

    session_file = session_file.resolve()
    main_id = session_file.stem
    session_dir = session_file.parent / main_id
    children_dir = session_dir / "subagents"
    child_paths = sorted(children_dir.glob("*.jsonl")) if children_dir.is_dir() else []

    main_events = list(_read_events(session_file, cutoff))
    parent_calls: dict[str, dict[str, Any]] = {}
    main_records: dict[str, dict[str, Any]] = {}
    for event in main_events:
        message = event.get("message")
        if event.get("type") != "assistant" or not isinstance(message, dict):
            continue
        for block in message.get("content", []) or []:
            if not isinstance(block, dict) or block.get("type") != "tool_use" or block.get("name") != "Agent":
                continue
            tool_id = str(block.get("id") or "")
            inputs = block.get("input") if isinstance(block.get("input"), dict) else {}
            parent_calls[tool_id] = {
                "name": inputs.get("name"),
                "agent_type": inputs.get("subagent_type"),
                "parent_model_at_spawn": message.get("model"),
                "handoff_utf8_bytes": len(json.dumps(inputs, ensure_ascii=False).encode("utf-8")),
                "result_utf8_bytes": None,
            }
    for event in main_events:
        message = event.get("message")
        if event.get("type") != "user" or not isinstance(message, dict):
            continue
        for block in message.get("content", []) or []:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                tool_id = str(block.get("tool_use_id") or "")
                if tool_id in parent_calls:
                    parent_calls[tool_id]["result_utf8_bytes"] = _bytes(block.get("content", ""))

    report["session_id"] = main_id
    report["transcripts"].append(_transcript_report(session_file, project_root, cutoff, main_model_provenance, loaded_instruction_paths=loaded))
    for child in child_paths:
        metadata_path = child.with_name(child.name.replace(".jsonl", ".meta.json"))
        metadata = {}
        if metadata_path.is_file():
            try:
                metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                metadata = {}
        handoff = parent_calls.get(str(metadata.get("toolUseId") or ""))
        report["transcripts"].append(
            _transcript_report(
                child,
                project_root,
                cutoff,
                main_model_provenance,
                handoff.get("parent_model_at_spawn") if handoff else None,
                handoff,
                loaded,
            )
        )
    report["agent_counts"] = {
        "main": 1,
        "child_transcripts": len(child_paths),
        "main_agent_calls": len(parent_calls),
        "child_transcripts_with_parent_call": sum(
            1
            for child in report["transcripts"][1:]
            if child.get("parent_tool_use_id") in parent_calls
        ),
    }
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--session-file", type=Path, help="Optional Claude Code main transcript JSONL.")
    parser.add_argument("--cutoff-utc", help="Optional ISO UTC cutoff; later events are excluded.")
    parser.add_argument(
        "--main-model-provenance",
        choices=("NOT_OBSERVABLE", "USER_CONTROLLED", "CONFIGURED", "RUNTIME_ATTESTED"),
        default="NOT_OBSERVABLE",
        help="Explicit provenance supplied by the session owner; never inferred from model mix.",
    )
    parser.add_argument("--loaded-instruction-manifest", type=Path, help="Optional newline-delimited harness-attested instruction paths.")
    parser.add_argument("--output", type=Path, help="Optional report JSON path. Default is stdout; no automatic store is written.")
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    session_file = args.session_file.resolve() if args.session_file else None
    loaded_manifest = args.loaded_instruction_manifest.resolve() if args.loaded_instruction_manifest else None
    try:
        report = build_report(project_root, session_file, args.cutoff_utc, args.main_model_provenance, loaded_manifest)
        serialized = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(serialized, encoding="utf-8")
        else:
            sys.stdout.write(serialized)
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"context telemetry unavailable: {type(exc).__name__}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())