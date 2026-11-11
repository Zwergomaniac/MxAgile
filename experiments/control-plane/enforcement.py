"""Mandatory enforcement adapter for host PreToolUse hooks (Claude Code payload shape).

The guard stays the authority; this adapter only classifies a tool call and turns the guard
verdict into allow/deny. Critical classes fail closed when no valid decision is available.
"""

from __future__ import annotations

import json
import re
import sys
import uuid
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import guard  # noqa: E402

READ = "READ"
IMPLEMENTATION_WRITE = "IMPLEMENTATION_WRITE"
EVIDENCE_WRITE = "EVIDENCE_WRITE"
LIFECYCLE_WRITE = "LIFECYCLE_WRITE"
FRAMEWORK_WRITE = "FRAMEWORK_WRITE"
DERIVED_PROJECTION_WRITE = "DERIVED_PROJECTION_WRITE"
CHILD_SPAWN = "CHILD_SPAWN"
EXTERNAL_SIDE_EFFECT = "EXTERNAL_SIDE_EFFECT"

# Classes that require a valid delivery decision; others stay lightweight.
ENFORCED = {IMPLEMENTATION_WRITE, CHILD_SPAWN}
READ_ONLY_AGENT_TYPES = {"Explore", "Plan", "claude-code-guide", "statusline-setup"}
MENDIX_MCP_SERVERS = ("mendix-studio-pro", "concord")
READ_VERB = re.compile(r"(?:^|_)(get|list|read|search|find|describe|inspect|query|show|status|probe|check|validate|diff)(?:_|$)", re.I)
PATH_CLASSES: tuple[tuple[tuple[str, ...], str], ...] = (
    (("planning/lifecycle/", "planning/mission/", "planning/execution-waves.md", ".concord/context-epoch.yaml"), LIFECYCLE_WRITE),
    (("planning/evidence/", "planning/parity/", "planning/acceptance-campaigns/", "planning/wave-reports/", ".concord/screenshots/", ".concord/evidence/"), EVIDENCE_WRITE),
    ((".mxagile/state/", "graphify-out/", ".concord/routing-decisions/", ".concord/delegated-results/", ".concord/delegation-handoffs/", ".concord/scratch/"), DERIVED_PROJECTION_WRITE),
    ((".mxagile/", ".claude/", ".github/", ".agents/", "AGENTS.md", "CLAUDE.md", "AGENT.md"), FRAMEWORK_WRITE),
    (("requirements/", "specs/", "planning/", "sprints/"), DERIVED_PROJECTION_WRITE),
)
MUTATING_SHELL = re.compile(r"\bmxcli(?:\.exe)?\b[^|;&]*\b(exec|create|alter|drop|apply|write)\b", re.I)
FRAMEWORK_SHELL = re.compile(r"(mxagile-setup|install-core|update-layer|update-mxcli|canonicalize_artifacts)", re.I)
GIT_MUTATION = re.compile(r"\bgit\s+(commit|push|reset|rebase|merge|checkout|switch|tag|stash|clean)\b", re.I)
HANDOFF_MARKER = re.compile(r"MXAGILE_HANDOFF:\s*(\S+)")


def new_run_id() -> str:
    return f"RUN-{uuid.uuid4().hex[:12]}"


def classify_path(root: Path, raw: str) -> str:
    path = Path(raw)
    try:
        relative = (path if path.is_absolute() else root / path).resolve().relative_to(root.resolve()).as_posix()
    except (OSError, ValueError):
        return EXTERNAL_SIDE_EFFECT
    for prefixes, op_class in PATH_CLASSES:
        if any(relative == prefix or relative.startswith(prefix) for prefix in prefixes):
            return op_class
    return IMPLEMENTATION_WRITE


def classify_tool_call(root: Path, payload: dict[str, Any]) -> tuple[str, str]:
    tool = str(payload.get("tool_name") or "")
    tool_input = payload.get("tool_input") or {}
    if tool in {"Read", "Glob", "Grep", "LS", "WebFetch", "WebSearch", "TodoWrite"}:
        return READ, tool
    if tool in {"Write", "Edit", "MultiEdit", "NotebookEdit"}:
        target = str(tool_input.get("file_path") or tool_input.get("notebook_path") or "")
        return (classify_path(root, target) if target else IMPLEMENTATION_WRITE), target
    if tool in {"Task", "Agent"}:
        return CHILD_SPAWN, str(tool_input.get("subagent_type") or "")
    if tool.startswith("mcp__"):
        server, _, operation = tool[len("mcp__"):].partition("__")
        if server.startswith(MENDIX_MCP_SERVERS):
            return (READ if READ_VERB.search(operation) else IMPLEMENTATION_WRITE), tool
        return READ, tool
    if tool == "Bash":
        command = str(tool_input.get("command") or "")
        if FRAMEWORK_SHELL.search(command):
            return FRAMEWORK_WRITE, command
        if MUTATING_SHELL.search(command):
            return IMPLEMENTATION_WRITE, command
        if GIT_MUTATION.search(command):
            return EXTERNAL_SIDE_EFFECT, command
        return READ, command
    # Unknown host tools are not assumed harmless.
    return IMPLEMENTATION_WRITE, tool


def _blocking(verdict: dict[str, Any]) -> tuple[str, str | None]:
    codes = [f["code"] for f in verdict["must_findings"]]
    recovery = next((f.get("recovery") for f in verdict["must_findings"] if f.get("recovery")), None)
    return ", ".join(codes) or verdict["verdict"], recovery


def _spawn_decision(facts: guard.ProjectFacts, payload: dict[str, Any], run_id: str) -> dict[str, Any]:
    tool_input = payload.get("tool_input") or {}
    agent_type = str(tool_input.get("subagent_type") or "")
    if agent_type in READ_ONLY_AGENT_TYPES:
        return {"decision": "allow", "reason": f"read-only agent type {agent_type}"}
    marker = HANDOFF_MARKER.search(str(tool_input.get("prompt") or ""))
    if not marker:
        return {"decision": "deny", "reason": "CHILD_HANDOFF_MISSING: write/verification children need MXAGILE_HANDOFF:<path>", "recovery": "inspect"}
    handoff_path = guard._safe_project_file(facts.root, marker.group(1))
    if handoff_path is None or not handoff_path.is_file():
        return {"decision": "deny", "reason": "CHILD_HANDOFF_UNAVAILABLE", "recovery": "inspect"}
    handoff = json.loads(handoff_path.read_text(encoding="utf-8"))
    if handoff.get("agent_type") != agent_type:
        return {"decision": "deny", "reason": "CHILD_AGENT_TYPE_MISMATCH", "recovery": "inspect"}
    request = {
        "request_id": handoff.get("run_id") or run_id,
        "run_id": handoff.get("run_id") or run_id,
        "gate_type": "delegation",
        "mission_id": handoff.get("mission_id"),
        "wave_id": (handoff.get("delivery_context") or {}).get("wave_id"),
        "route_decision_reference": handoff.get("route_decision_reference"),
        "handoff": handoff,
        "authorization": {"status": "confirmed", "reference": handoff["authorization_reference"]} if handoff.get("authorization_reference") else {},
        "observations": {**(handoff.get("parent_observations") or {}), "spawn_tool_visible": True},
    }
    verdict = guard.can_delegate(facts, request)
    if verdict["verdict"] == "pass":
        return {"decision": "allow", "reason": "can_delegate pass", "verdict": verdict}
    reason, recovery = _blocking(verdict)
    return {"decision": "deny", "reason": reason, "recovery": recovery, "verdict": verdict}


def decide(project_root: str | Path, payload: dict[str, Any]) -> dict[str, Any]:
    root = Path(project_root).resolve()
    run_id = new_run_id()
    try:
        op_class, detail = classify_tool_call(root, payload)
    except Exception:  # an unclassifiable call is treated as critical
        op_class, detail = IMPLEMENTATION_WRITE, "unclassifiable"
    result: dict[str, Any] = {"operation_class": op_class, "detail": detail}
    if op_class not in ENFORCED:
        result.update({"decision": "allow", "reason": "not an enforced operation class"})
    else:
        try:
            facts = guard.load_project_facts(root)
            if op_class == CHILD_SPAWN:
                result.update(_spawn_decision(facts, payload, run_id))
            else:
                verdict = guard.delivery_authorization(facts, op_class, run_id)
                if verdict["verdict"] == "pass":
                    result.update({"decision": "allow", "reason": "delivery authorized", "verdict": verdict})
                else:
                    reason, recovery = _blocking(verdict)
                    result.update({"decision": "deny", "reason": reason, "recovery": recovery, "verdict": verdict})
        except Exception as exc:  # fail closed: no valid guard decision is never an allow
            result.update({"decision": "deny", "reason": f"GUARD_UNAVAILABLE: {type(exc).__name__}", "recovery": "inspect"})
    result["event"] = {
        "type": ("child_started" if op_class == CHILD_SPAWN else "delivery_authorized") if result["decision"] == "allow" and op_class in ENFORCED
        else ("delivery_blocked" if result["decision"] == "deny" else None),
        "run_id": (result.get("verdict") or {}).get("run_id") or run_id,
        "operation_class": op_class,
    }
    return result


def hook_output(result: dict[str, Any]) -> dict[str, Any] | None:
    if result["decision"] == "allow" and result["operation_class"] not in ENFORCED:
        return None
    reason = result["reason"] + (f" | recovery: {result['recovery']}" if result.get("recovery") else "")
    return {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": result["decision"],
        "permissionDecisionReason": f"MxAgile control plane: {reason}",
    }}


def main() -> int:
    raw = sys.stdin.read(1_000_000)
    try:
        payload = json.loads(raw or "{}")
        root = Path(payload.get("cwd") or ".")
        output = hook_output(decide(root, payload))
    except Exception as exc:
        output = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                         "permissionDecisionReason": f"MxAgile control plane: GUARD_UNAVAILABLE: {type(exc).__name__}"}}
    if output:
        print(json.dumps(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
