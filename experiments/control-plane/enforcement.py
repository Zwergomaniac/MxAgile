"""Mandatory enforcement adapter for host PreToolUse hooks (Claude Code payload shape).

The guard stays the authority; this adapter only classifies a tool call and turns the guard
verdict into allow/deny. Critical classes fail closed when no valid decision is available.
"""

from __future__ import annotations

import json
import os
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
CONTROLLED_MUTATION = "CONTROLLED_MUTATION"
CONTEXT_INVALIDATING = "CONTEXT_INVALIDATING"
HIGH_RISK_MUTATION = "HIGH_RISK_MUTATION"
INTEGRATION_MUTATION = "INTEGRATION_MUTATION"
VERIFICATION = "VERIFICATION"
TOOLING_SERVICE = "TOOLING_SERVICE"

# Classes that require a valid delivery decision; others stay lightweight.
ENFORCED = {IMPLEMENTATION_WRITE, CHILD_SPAWN, HIGH_RISK_MUTATION, INTEGRATION_MUTATION}
_SEVERITY = [READ, TOOLING_SERVICE, VERIFICATION, EVIDENCE_WRITE, DERIVED_PROJECTION_WRITE, LIFECYCLE_WRITE,
             CONTROLLED_MUTATION, CONTEXT_INVALIDATING, EXTERNAL_SIDE_EFFECT, FRAMEWORK_WRITE,
             INTEGRATION_MUTATION, HIGH_RISK_MUTATION, IMPLEMENTATION_WRITE]
READ_ONLY_AGENT_TYPES = {"Explore", "Plan", "claude-code-guide", "statusline-setup"}
MENDIX_MCP_SERVERS = ("mendix-studio-pro", "concord")
READ_VERB = re.compile(
    r"(?:^|_)(get|list|read|search|find|describe|inspect|query|show|status|probe|check|validate|diff|discover|"
    r"explain|analyze|analyse|lookup|fetch|resolve|summarize|help|docs|knowledge|info|context|refs|callers|callees)(?:_|$)",
    re.I)
PATH_CLASSES: tuple[tuple[tuple[str, ...], str], ...] = (
    (("planning/lifecycle/", "planning/mission/", "planning/execution-waves.md", ".concord/context-epoch.yaml"), LIFECYCLE_WRITE),
    (("planning/evidence/", "planning/parity/", "planning/acceptance-campaigns/", "planning/wave-reports/", ".concord/screenshots/", ".concord/evidence/"), EVIDENCE_WRITE),
    ((".mxagile/state/", "graphify-out/", ".concord/routing-decisions/", ".concord/delegated-results/", ".concord/delegation-handoffs/", ".concord/scratch/"), DERIVED_PROJECTION_WRITE),
    ((".mxagile/", ".claude/", ".github/", ".agents/", "AGENTS.md", "CLAUDE.md", "AGENT.md"), FRAMEWORK_WRITE),
    (("requirements/", "specs/", "planning/", "sprints/"), DERIVED_PROJECTION_WRITE),
)
MUTATING_SHELL = re.compile(r"\bmxcli(?:\.exe)?\b[^|;&]*\b(exec|create|alter|drop|apply|write|fix|rename|layout)\b", re.I)
FRAMEWORK_SHELL = re.compile(r"(mxagile-setup|install-core|update-layer|update-mxcli|canonicalize_artifacts)", re.I)
GIT_CLASSES = {
    "status": READ, "log": READ, "diff": READ, "show": READ, "blame": READ, "branch": READ, "rev-parse": READ,
    "ls-files": READ, "fetch": READ, "add": CONTROLLED_MUTATION, "commit": CONTROLLED_MUTATION,
    "checkout": CONTEXT_INVALIDATING, "switch": CONTEXT_INVALIDATING, "stash": CONTEXT_INVALIDATING,
    "reset": HIGH_RISK_MUTATION, "clean": HIGH_RISK_MUTATION, "restore": HIGH_RISK_MUTATION,
    "rm": HIGH_RISK_MUTATION, "push": HIGH_RISK_MUTATION, "tag": CONTROLLED_MUTATION,
    "merge": INTEGRATION_MUTATION, "rebase": INTEGRATION_MUTATION, "cherry-pick": INTEGRATION_MUTATION,
    "pull": INTEGRATION_MUTATION, "apply": INTEGRATION_MUTATION, "am": INTEGRATION_MUTATION,
}
VERIFICATION_SHELL = re.compile(r"(\bpytest\b|\bunittest\b|\bnpm\s+(run\s+)?test\b|\bplaywright\b|tests[/\\][\w./\\-]*test|\brun-impact-tests\b|\bproject_compatibility\b)", re.I)
TOOLING_SHELL = re.compile(r"(serve_project_board|build_project_status|graphify|check-studio-pro-status|Get-MxAgileCapabilities)", re.I)
WRITE_VERBS = re.compile(r"^(set-content|add-content|out-file|new-item|remove-item|move-item|copy-item|rename-item|rm|mv|cp|del|rmdir|mkdir|touch|tee|sed|truncate)$", re.I)
NULL_REDIRECT = re.compile(r"\d?>&\d|\d?>\s*(\$null|/dev/null|nul)\b", re.I)
REDIRECT_TARGET = re.compile(r"(?<![<\d])>>?\s*(\"[^\"]+\"|'[^']+'|[^\s;|&]+)")
HANDOFF_MARKER = re.compile(r"MXAGILE_HANDOFF:\s*(\S+)")
HANDOFF_DIR = ".concord/delegation-handoffs/"


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
        return classify_shell(root, command), command
    # Unknown host tools are not assumed harmless.
    return IMPLEMENTATION_WRITE, tool


def _strip(token: str) -> str:
    return token.strip().strip("\"'")


def _classify_segment(root: Path, segment: str) -> str:
    text = NULL_REDIRECT.sub(" ", segment).strip()
    if not text:
        return READ
    if FRAMEWORK_SHELL.search(text):
        return FRAMEWORK_WRITE
    if MUTATING_SHELL.search(text):
        return IMPLEMENTATION_WRITE
    targets = [_strip(match) for match in REDIRECT_TARGET.findall(text)]
    tokens = [_strip(token) for token in re.split(r"\s+", text) if token]
    head = tokens[0].lower() if tokens else ""
    if head == "git":
        rest = tokens[1:]
        while rest and rest[0] in {"-C", "-c"}:
            rest = rest[2:]
        subcommand = next((token for token in rest if not token.startswith("-")), "")
        return GIT_CLASSES.get(subcommand.lower(), HIGH_RISK_MUTATION)
    if VERIFICATION_SHELL.search(text):
        return VERIFICATION
    if TOOLING_SHELL.search(text):
        return TOOLING_SERVICE
    if WRITE_VERBS.match(head):
        operands = [token for token in tokens[1:] if not token.startswith("-") and not re.match(r"^s?/.*/.*/\w*$", token)]
        if not operands:
            return IMPLEMENTATION_WRITE
        targets.extend(operands if head.lower() in {"rm", "del", "remove-item", "rmdir", "mkdir", "touch", "new-item"} else operands[-1:])
    if not targets:
        return READ
    return max((classify_path(root, target) for target in targets), key=_SEVERITY.index)


def classify_shell(root: Path, command: str) -> str:
    """Most restrictive class across chained segments; unknown write targets fail closed."""
    segments = [part for part in re.split(r"&&|\|\||;|\r?\n|\|", command) if part.strip()]
    return max((_classify_segment(root, segment) for segment in segments), key=_SEVERITY.index, default=READ)


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
    canonical = f"{HANDOFF_DIR}{handoff.get('delegation_id')}.json"
    if marker.group(1).replace("\\", "/") != canonical:
        # Save-MxAgileDelegationResult reads this exact path, which makes acceptance mandatory.
        return {"decision": "deny", "reason": f"CHILD_HANDOFF_NOT_CANONICAL: expected {canonical}", "recovery": "inspect"}
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
        # Claude sets CLAUDE_PROJECT_DIR for hooks; the tool-call cwd may be a subdirectory.
        root = Path(os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or ".")
        output = hook_output(decide(root, payload))
    except Exception as exc:
        output = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                         "permissionDecisionReason": f"MxAgile control plane: GUARD_UNAVAILABLE: {type(exc).__name__}"}}
    if output:
        print(json.dumps(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
