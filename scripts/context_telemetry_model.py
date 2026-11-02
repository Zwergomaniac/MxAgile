"""Harness-neutral records for opt-in context-architecture measurements."""

from __future__ import annotations

from typing import Any


OBSERVED = "OBSERVED"
DECLARED = "DECLARED"
NOT_OBSERVABLE = "NOT_OBSERVABLE"


def observation(
    state: str = NOT_OBSERVABLE,
    value: Any = None,
    provenance: str | None = None,
    reason: str | None = None,
) -> dict[str, Any]:
    if state not in {OBSERVED, DECLARED, NOT_OBSERVABLE}:
        raise ValueError(f"Unsupported telemetry observation state: {state}")
    return {
        "state": state,
        "value": value,
        "provenance": provenance,
        "reason": reason,
        "scope": "this_collector_run",
    }


def not_observable(reason: str) -> dict[str, Any]:
    return observation(reason=reason)


def new_session_record(harness: str, session_id: str, run_id: str) -> dict[str, Any]:
    """Return the canonical record shape shared by all harness collectors."""
    return {
        "telemetry_version": 1,
        "collector_id": observation(NOT_OBSERVABLE, reason="Collector identity was not supplied."),
        "harness": observation(DECLARED, harness, "caller-selected collector scope"),
        "session_identity": observation(DECLARED, session_id, "collector-supplied identifier"),
        "run_identity": observation(DECLARED, run_id, "collector-supplied identifier"),
        "collection_scope": observation(DECLARED, "this_collector_run", "canonical record scope"),
        "agent_identity": {
            "parent": not_observable("No parent-agent identity was supplied by this collector."),
            "child": not_observable("No child-agent identity was supplied by this collector."),
        },
        "delegation": {
            "type": not_observable("This collector did not observe delegation type."),
            "context_relationship": not_observable("This collector did not observe fresh/fork inheritance."),
            "handoff_utf8_bytes": not_observable("No handoff-size event was observed."),
            "result_utf8_bytes": not_observable("No delegation-result size was observed."),
        },
        "model": {
            "requested_profile": not_observable("No requested MxAgile model profile was observed."),
            "requested_model": not_observable("No requested provider model was observed."),
            "actual_model": not_observable("No actual provider model was observed."),
            "provenance": not_observable("No model-selection provenance was observed."),
            "parent_model_at_spawn": not_observable("No parent model at child spawn was observed."),
        },
        "loads": {
            "instruction_or_projection_paths": not_observable("No runtime load manifest was supplied."),
            "file_reads": not_observable("No file-read events were supplied."),
            "policy_reads": not_observable("No policy-read events were supplied."),
            "skill_reads": not_observable("No skill-read events were supplied."),
        },
        "compaction_resume": not_observable("No compaction/resume events were supplied."),
        "context_sizes": {
            "request_message_utf8_bytes": not_observable("No request-message size was supplied."),
            "tool_result_utf8_bytes": not_observable("No tool-result size was supplied."),
        },
        "tool_invocations": not_observable("No tool-invocation events were supplied."),
        "provider_usage": not_observable("No per-request provider usage was supplied."),
        "provider_cost": not_observable("No provider cost attribution was supplied."),
        "collector_extensions": {},
    }