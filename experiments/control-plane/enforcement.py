"""Mandatory enforcement adapter for host PreToolUse hooks (Claude Code payload shape).

The guard stays the authority; this adapter only classifies a tool call and turns the guard
verdict into allow/deny. Critical classes fail closed when no valid decision is available.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import sys
import uuid
from pathlib import Path
from dataclasses import dataclass
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import guard  # noqa: E402

try:
    import run_events
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
    import run_events  # type: ignore[no-redef]

READ = "READ"
IMPLEMENTATION_WRITE = "IMPLEMENTATION_WRITE"
DELIVERY_WRITE = "DELIVERY_WRITE"
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
PUBLICATION = "PUBLICATION"
VERIFICATION = "VERIFICATION"
TOOLING_SERVICE = "TOOLING_SERVICE"

DELIVERY_CRITICAL = {IMPLEMENTATION_WRITE, HIGH_RISK_MUTATION, INTEGRATION_MUTATION}
# Only structurally read-only calls bypass current-state authorization.
ENFORCED = {IMPLEMENTATION_WRITE, DELIVERY_WRITE, CHILD_SPAWN, HIGH_RISK_MUTATION, INTEGRATION_MUTATION,
            EVIDENCE_WRITE, LIFECYCLE_WRITE, FRAMEWORK_WRITE, DERIVED_PROJECTION_WRITE,
            EXTERNAL_SIDE_EFFECT, CONTROLLED_MUTATION, CONTEXT_INVALIDATING, VERIFICATION, TOOLING_SERVICE}
_SEVERITY = [READ, TOOLING_SERVICE, VERIFICATION, EVIDENCE_WRITE, DERIVED_PROJECTION_WRITE, DELIVERY_WRITE, LIFECYCLE_WRITE,
             CONTROLLED_MUTATION, CONTEXT_INVALIDATING, EXTERNAL_SIDE_EFFECT, FRAMEWORK_WRITE,
             INTEGRATION_MUTATION, HIGH_RISK_MUTATION, PUBLICATION, IMPLEMENTATION_WRITE]
READ_ONLY_AGENT_TYPES = {"Explore", "Plan", "claude-code-guide", "statusline-setup"}
MENDIX_MCP_SERVERS = ("mendix-studio-pro", "concord")
READ_VERB = re.compile(
    r"(?:^|_)(get|list|read|search|find|glob|describe|inspect|query|show|status|probe|check|validate|diff|discover|"
    r"explain|analyze|analyse|lookup|fetch|resolve|summarize|help|docs|knowledge|info|context|refs|callers|callees)(?:_|$)",
    re.I)
MUTATION_VERB = re.compile(r'(?:^|_)(exec|execute|create|alter|drop|apply|write|update|delete|remove|patch|compile|fix|rename)(?:_|$)', re.I)
PATH_CLASSES: tuple[tuple[tuple[str, ...], str], ...] = (
    (("planning/lifecycle/", "planning/mission/", "planning/execution-waves.md", ".concord/context-epoch.yaml"), LIFECYCLE_WRITE),
    (("planning/evidence/", "planning/parity/", "planning/acceptance-campaigns/", "planning/wave-reports/", ".concord/screenshots/", ".concord/evidence/"), EVIDENCE_WRITE),
    ((".mxagile/migration/", ".mxagile/state/core-provenance.json", ".mxagile/state/update-transaction.json"), FRAMEWORK_WRITE),
    ((".mxagile/state/", "graphify-out/", ".concord/routing-decisions/", ".concord/delegated-results/", ".concord/delegation-handoffs/", ".concord/scratch/"), DERIVED_PROJECTION_WRITE),
    ((".mxagile/", ".claude/", ".github/", ".agents/", "AGENTS.md", "CLAUDE.md", "AGENT.md"), FRAMEWORK_WRITE),
    (("requirements/", "specs/", "planning/", "sprints/"), DELIVERY_WRITE),
)
MUTATING_SHELL = re.compile(r"\bmxcli(?:\.exe)?\b[^|;&]*\b(exec|create|alter|drop|apply|write|fix|rename|layout)\b", re.I)
FRAMEWORK_SHELL = re.compile(r"(mxagile-setup|install-core|update-layer|update-mxcli|canonicalize_artifacts)", re.I)
GIT_CLASSES = {
    "status": READ, "log": READ, "diff": READ, "show": READ, "blame": READ, "branch": READ, "rev-parse": READ,
    "ls-files": READ, "fetch": READ, "add": CONTROLLED_MUTATION, "commit": CONTROLLED_MUTATION,
    "checkout": CONTEXT_INVALIDATING, "switch": CONTEXT_INVALIDATING, "stash": CONTEXT_INVALIDATING,
    "reset": HIGH_RISK_MUTATION, "clean": HIGH_RISK_MUTATION, "restore": HIGH_RISK_MUTATION,
    "rm": HIGH_RISK_MUTATION, "push": PUBLICATION, "tag": CONTROLLED_MUTATION,
    "merge": INTEGRATION_MUTATION, "rebase": INTEGRATION_MUTATION, "cherry-pick": INTEGRATION_MUTATION,
    "pull": INTEGRATION_MUTATION, "apply": INTEGRATION_MUTATION, "am": INTEGRATION_MUTATION,
}
VERIFICATION_SHELL = re.compile(r"(\bpytest\b|\bunittest\b|\bnpm\s+(run\s+)?test\b|\bplaywright\b|tests[/\\][\w./\\-]*test|\brun-impact-tests\b|\bproject_compatibility\b)", re.I)
TOOLING_SHELL = re.compile(r"(serve_project_board|build_project_status|graphify|check-studio-pro-status|Get-MxAgileCapabilities)", re.I)
WRITE_VERBS = re.compile(r"^(set-content|add-content|out-file|new-item|remove-item|move-item|copy-item|rename-item|rm|mv|cp|del|rmdir|mkdir|touch|tee|sed|truncate)$", re.I)
NULL_REDIRECT = re.compile(r"\d?\s*>\s*&\s*\d\b|\d?\s*>\s*(\$null|/dev/null|nul)\b", re.I)
REDIRECT_TARGET = re.compile(r"(?<![<\d])>>?\s*(\"[^\"]+\"|'[^']+'|[^\s;|&]+)")
HANDOFF_MARKER = re.compile(r"MXAGILE_HANDOFF:\s*(\S+)")
HANDOFF_DIR = ".concord/delegation-handoffs/"


def new_run_id() -> str:
    return f"RUN-{uuid.uuid4().hex[:12]}"


def _persist_event(root: Path, result: dict[str, Any], payload: dict[str, Any], run_id: str) -> None:
    event_type = result.get("event", {}).get("type")
    if not event_type:
        return
    tool_name = str(payload.get("tool_name") or "")
    host = "concord" if "concord" in tool_name.lower() else (
        "studio_pro" if "mendix-studio-pro" in tool_name.lower() else "claude_code")
    verdict = result.get("verdict") or {}
    codes = [item.get("code") for item in verdict.get("must_findings", []) if item.get("code")]
    if event_type == "child_started":
        handoff = result.get("handoff") or {}
        run_id = handoff.get("run_id") or run_id
        parent_run_id = handoff.get("parent_run_id")
        mission_id = handoff.get("mission_id")
        wave_id = (handoff.get("delivery_context") or {}).get("wave_id")
        capability = handoff.get("capability")
        correlation = {key: value for key, value in {
            "delegation_id": handoff.get("delegation_id"),
            "handoff_reference": result.get("handoff_reference"),
        }.items() if value is not None}
    else:
        parent_run_id = None
        mission_id = verdict.get("mission_id")
        wave_id = verdict.get("wave_id")
        capability = None
        correlation = {}
    try:
        run_events.append_event(
            root, event_type, run_id=run_id, parent_run_id=parent_run_id,
            mission_id=mission_id, wave_id=wave_id, capability=capability,
            actor=tool_name or "claude_code", host=host, correlation=correlation,
            payload={key: value for key, value in {
                "reason_codes": codes, "recovery": result.get("recovery"),
                "operation_class": result.get("operation_class"), "tool_name": tool_name,
                "controlled_recovery": result.get('controlled_recovery'),
            }.items() if value is not None},
        )
    except Exception as exc:
        print(f"MxAgile event audit unavailable: {type(exc).__name__}", file=sys.stderr)


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


@dataclass(frozen=True)
class HostBoundaryEvidence:
    """Trusted in-process host evidence, never reconstructed from agent tool_input.

    A dispatch classifier must verify the discovered inner operation's complete argument
    contract. Child attestation must confirm actual host tool restrictions and run binding.
    The stdin hook has neither source today and therefore supplies no evidence.
    """
    classify_dispatch: Callable[[str, dict[str, Any]], str | None] | None = None
    attest_diagnostic_child: Callable[[dict[str, Any], dict[str, Any]], bool] | None = None


def classify_tool_call(root: Path, payload: dict[str, Any], evidence: HostBoundaryEvidence | None = None) -> tuple[str, str]:
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
        # Dispatchers require inner-operation evidence; a claimed read_only flag is not evidence.
        if operation in {'concord_invoke', 'execute_handler'}:
            if evidence and evidence.classify_dispatch:
                classification = evidence.classify_dispatch(tool, tool_input)
                if classification == READ:
                    return READ, 'DISPATCH_READ_CONTRACT_CONFIRMED'
                if classification in ENFORCED:
                    return classification, 'DISPATCH_OPERATION_CONFIRMED'
            return IMPLEMENTATION_WRITE, 'DISPATCH_OPERATION_NOT_OBSERVABLE'
        return (READ if READ_VERB.search(operation) and not MUTATION_VERB.search(operation) else IMPLEMENTATION_WRITE), tool
    if tool == "Bash":
        command = str(tool_input.get("command") or "")
        return classify_shell(root, command), command
    # Unknown host tools are not assumed harmless.
    return IMPLEMENTATION_WRITE, tool


def _strip(token: str) -> str:
    return token.strip().strip("\"'")


def _shell_tokens(text: str) -> list[str]:
    lexer = shlex.shlex(text, posix=False, punctuation_chars=';&|<>\n')
    lexer.whitespace = ' \t\r'
    lexer.whitespace_split = True
    lexer.commenters = ''
    return list(lexer)


def _sed_read_only(args: list[str]) -> bool:
    scripts = []
    index = 0
    while index < len(args):
        value = args[index]
        if value in {'-n', '-E', '-r', '--quiet', '--silent', '--regexp-extended'}:
            index += 1
            continue
        if value in {'-e', '--expression'}:
            index += 1
            if index >= len(args):
                return False
            scripts.append(args[index])
        elif value.startswith('-'):
            return False
        elif not scripts:
            scripts.append(value)
        index += 1
    # Script files, e/w commands and substitution execution/write flags are not stdout-only.
    return bool(scripts) and all(
        re.fullmatch(r'(?:\d+(?:,\d+)?|\$)?p', script)
        or re.fullmatch(r's(?P<d>[^\\\w\s])(?:\\.|(?!(?P=d)).)*(?P=d)(?:\\.|(?!(?P=d)).)*(?P=d)[gp0-9]*', script)
        for script in scripts
    )


def _classify_segment(root: Path, segment: str) -> str:
    text = NULL_REDIRECT.sub(' ', segment).strip()
    if not text:
        return READ
    raw_tokens = _shell_tokens(text)
    tokens = [_strip(token) for token in raw_tokens]
    head = tokens[0].lower().replace('\\', '/').rsplit('/', 1)[-1].removesuffix('.exe') if tokens else ''
    args = tokens[1:]
    targets = [tokens[index + 1] for index, token in enumerate(raw_tokens[:-1]) if '>' in token and all(char in ';&|<>' for char in token)]
    if targets:
        return max((classify_path(root, target) for target in targets), key=_SEVERITY.index)
    if any('>' in token and all(char in ';&|<>' for char in token) for token in raw_tokens):
        return IMPLEMENTATION_WRITE
    if head == 'sed':
        return READ if _sed_read_only(args) else IMPLEMENTATION_WRITE
    if head == 'mxcli':
        rest = args[:]
        while len(rest) >= 2 and rest[0] in {'-p', '--project'}:
            rest = rest[2:]
        command = rest[0].lower() if rest else ''
        if command in {'help', 'syntax', 'version', '--version', '--help', '-h', 'lint'} and not any(a.split('=', 1)[0] in {'--output', '-o', '--apply', '--fix', '--write', '--execute'} for a in rest):
            return READ
        return IMPLEMENTATION_WRITE
    if head == 'git':
        rest = args[:]
        while rest and rest[0] in {'-C', '-c'}:
            rest = rest[2:]
        subcommand = next((token for token in rest if not token.startswith('-')), '').lower()
        if subcommand == 'branch' and any(a not in {'branch', '--list', '-l', '--show-current', '-a', '-r', '-v', '-vv'} for a in rest):
            return HIGH_RISK_MUTATION
        return GIT_CLASSES.get(subcommand, HIGH_RISK_MUTATION)
    scripts = [a.replace('\\', '/').rsplit('/', 1)[-1] for a in args if a.endswith('.py')]
    if head in {'python', 'python3', 'py'} and 'project_compatibility.py' in scripts:
        script_index = next(i for i, a in enumerate(args) if a.replace('\\', '/').rsplit('/', 1)[-1] == 'project_compatibility.py')
        subcommand = args[script_index + 1:script_index + 2]
        readonly = subcommand in (['doctor'], ['contract-snapshot'], ['resync-preflight']) or (subcommand == ['migrate'] and '--apply-safe' not in args)
        if all(a == '-B' for a in args[:script_index]) and readonly and '--apply' not in args:
            return READ
    if head in {'get-mxagilecapabilities.ps1', 'check-studio-pro-status.ps1'}:
        return READ
    if FRAMEWORK_SHELL.search(text):
        return FRAMEWORK_WRITE
    if MUTATING_SHELL.search(text):
        return IMPLEMENTATION_WRITE
    if VERIFICATION_SHELL.search(text):
        return VERIFICATION
    if TOOLING_SHELL.search(text):
        return TOOLING_SERVICE
    if WRITE_VERBS.match(head):
        operands = [token for token in args if not token.startswith('-')]
        return max((classify_path(root, target) for target in operands), key=_SEVERITY.index, default=IMPLEMENTATION_WRITE)
    if head in {'cat', 'head', 'tail', 'grep', 'rg', 'ls', 'pwd', 'echo', 'printf', 'get-content', 'get-childitem', 'select-object', 'select-string', 'get-location', 'test-path'}:
        return READ
    return IMPLEMENTATION_WRITE


def classify_shell(root: Path, command: str) -> str:
    """Quote-aware chains; unparsed shell execution and redirects fail closed."""
    if '$(' in command or '`' in command or '<(' in command or '>(' in command:
        return IMPLEMENTATION_WRITE
    try:
        segments = []
        current = []
        for token in _shell_tokens(command):
            if token and all(char in ';&|\n' for char in token):
                segments.append(' '.join(current))
                current = []
            else:
                current.append(token)
        segments.append(' '.join(current))
        return max((_classify_segment(root, segment) for segment in segments), key=_SEVERITY.index, default=READ)
    except ValueError:
        return IMPLEMENTATION_WRITE


def _blocking(verdict: dict[str, Any]) -> tuple[str, str | None]:
    codes = [f["code"] for f in verdict["must_findings"]]
    recovery = (verdict.get('recovery_plan') or {}).get('primary_next_action')
    return ", ".join(codes) or verdict["verdict"], recovery


def _spawn_decision(facts: guard.ProjectFacts, payload: dict[str, Any], run_id: str, evidence: HostBoundaryEvidence | None = None) -> dict[str, Any]:
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
    if handoff.get('capability') == 'read_only_diagnostic':
        schema = json.loads((facts.root / '.mxagile' / 'schemas' / 'delegation-handoff.schema.json').read_text(encoding='utf-8'))
        context = handoff.get('delivery_context') or {}
        tools = handoff.get('allowed_tools') or []
        valid = (
            not list(guard.Draft7Validator(schema).iter_errors(handoff))
            and handoff.get('schema_version') == '1.4'
            and handoff.get('parent_run_id') == run_id
            and bool(handoff.get('scope', {}).get('paths'))
            and all(guard._safe_project_file(facts.root, path) is not None for path in handoff['scope']['paths'])
            and Path(context.get('project_root') or '').resolve() == facts.root.resolve()
            and bool(tools) and set(handoff.get('required_tools', [])) <= set(tools)
            and all(tool not in {'Bash', 'Task', 'Agent', 'TodoWrite'} and classify_tool_call(facts.root, {'tool_name': tool, 'tool_input': {}}, evidence)[0] == READ for tool in tools)
            and context.get('authorization') == 'read_only'
            and context.get('commit_expectation') == 'no_commit'
            and not any(context.get(key) for key in ('write_scope', 'output_artifacts', 'evidence_destinations'))
            and not handoff.get('write_classes') and handoff.get('evidence_destination') is None
            and {'ALL_WRITES', 'ACCEPTANCE', 'DELIVERY_AUTHORIZATION'} <= set(handoff.get('forbidden_mutations', []))
            and handoff.get('output_contract') == 'diagnostic-findings/1'
            and not guard._verify_source_fingerprints(facts, handoff.get('source_fingerprints'))
        )
        if not valid:
            return {'decision': 'deny', 'reason': 'DIAGNOSTIC_HANDOFF_INVALID', 'recovery': 'inspect'}
        if not evidence or not evidence.attest_diagnostic_child or not evidence.attest_diagnostic_child(handoff, payload):
            return {'decision': 'deny', 'reason': 'DIAGNOSTIC_TOOL_CONSTRAINT_NOT_OBSERVABLE', 'recovery': 'inspect'}
        return {'decision': 'allow', 'reason': 'READ_ONLY_DIAGNOSTIC_HOST_CONFIRMED', 'handoff': handoff, 'handoff_reference': canonical}
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
        return {"decision": "allow", "reason": "can_delegate pass", "verdict": verdict,
            "handoff": handoff, "handoff_reference": canonical}
    reason, recovery = _blocking(verdict)
    return {"decision": "deny", "reason": reason, "recovery": recovery, "verdict": verdict,
            "handoff": handoff, "handoff_reference": canonical}


def _controlled_recovery(facts: guard.ProjectFacts, payload: dict[str, Any]) -> str | None:
    if payload.get('tool_name') != 'Bash' or facts.update_transaction_present:
        return None
    command = str((payload.get('tool_input') or {}).get('command') or '')
    if any(marker in command for marker in ('$(', '`', '<(', '>(')):
        return None
    raw = _shell_tokens(command)
    if any(token and all(char in ';&|<>\n' for char in token) for token in raw):
        return None
    args = [_strip(token) for token in raw]
    if not args:
        return None
    program = args.pop(0).lower().replace('\\', '/').rsplit('/', 1)[-1].removesuffix('.exe')
    tools = facts.root / '.mxagile' / 'tools'
    action = None
    if program in {'python', 'python3', 'py'}:
        if args[:1] == ['-B']:
            args = args[1:]
        if len(args) != 7 or not Path(args[0]).is_absolute() or Path(args[0]).resolve() != tools / 'project_compatibility.py':
            return None
        if args[1:4] != ['migrate', '--apply-safe', '--project-root'] or args[5:] != ['--format', 'json']:
            return None
        root_arg = args[4]
        action = 'contract_reconciliation'
    elif program in {'pwsh', 'powershell'}:
        if len(args) != 6 or [a.lower() for a in (args[0], args[1], args[3], args[5])] != ['-noprofile', '-file', '-projectroot', '-preserveevidence']:
            return None
        if not Path(args[2]).is_absolute() or Path(args[2]).resolve() != tools / 'Write-MxAgileEpochCheckpoint.ps1':
            return None
        root_arg = args[4]
        action = 'context_resync'
    else:
        return None
    if not Path(root_arg).is_absolute() or Path(root_arg).resolve() != facts.root:
        return None
    expected = facts.core_provenance.get('recovery_tools')
    if not isinstance(expected, dict) or not expected or not tools.is_dir() or tools.is_symlink():
        return None
    actual = {}
    for path in tools.rglob('*.py'):
        if path.is_symlink() or any(parent.is_symlink() for parent in path.parents if parent != facts.root):
            return None
        actual[path.relative_to(tools).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    writer = tools / 'Write-MxAgileEpochCheckpoint.ps1'
    if not writer.is_file() or writer.is_symlink():
        return None
    actual[writer.name] = hashlib.sha256(writer.read_bytes()).hexdigest()
    if actual != expected:
        return None
    from project_compatibility import contract_snapshot, resync_preflight
    if not facts.core_provenance.get('artifact_contract') or contract_snapshot(facts.root) != facts.core_provenance['artifact_contract']:
        return None
    if action == 'context_resync' and resync_preflight(facts.root)['state'] != 'READY_FOR_RESYNC':
        return None
    return action


def decide(project_root: str | Path, payload: dict[str, Any], *, evidence: HostBoundaryEvidence | None = None) -> dict[str, Any]:
    root = Path(project_root).resolve()
    requested_run_id = os.environ.get("MXAGILE_RUN_ID", "")
    run_id = requested_run_id if re.fullmatch(r"RUN-[A-Za-z0-9-]{4,80}", requested_run_id) else new_run_id()
    try:
        op_class, detail = classify_tool_call(root, payload, evidence)
    except Exception:  # an unclassifiable call is treated as critical
        op_class, detail = IMPLEMENTATION_WRITE, "unclassifiable"
    result: dict[str, Any] = {"operation_class": op_class, "detail": detail}
    if op_class == PUBLICATION:
        # Remote publication is never authorized by delivery state; the developer decides in the host.
        result.update({"decision": "ask", "reason": "PUBLICATION_REQUIRES_DEVELOPER_APPROVAL", "recovery": "human_resolution"})
    elif op_class not in ENFORCED:
        result.update({"decision": "allow", "reason": "not an enforced operation class"})
    else:
        try:
            facts = guard.load_project_facts(root)
            recovery = _controlled_recovery(facts, payload)
            if recovery:
                op_class = CONTROLLED_MUTATION
                result.update({'operation_class': op_class, 'decision': 'allow', 'reason': 'INTEGRITY_BOUND_CORE_RECOVERY', 'controlled_recovery': recovery})
            elif op_class == CHILD_SPAWN:
                result.update(_spawn_decision(facts, payload, run_id, evidence))
            else:
                verdict = guard.delivery_authorization(facts, op_class, run_id, require_implementing=op_class in DELIVERY_CRITICAL)
                if verdict["verdict"] == "pass":
                    result.update({"decision": "allow", "reason": "delivery authorized", "verdict": verdict})
                else:
                    reason, recovery = _blocking(verdict)
                    result.update({"decision": "deny", "reason": reason, "recovery": recovery, "verdict": verdict})
        except Exception as exc:  # fail closed: no valid guard decision is never an allow
            result.update({"decision": "deny", "reason": f"GUARD_UNAVAILABLE: {type(exc).__name__}", "recovery": "inspect"})
    result["event"] = {
        "type": ('recovery_required' if result.get('controlled_recovery') else ("child_started" if op_class == CHILD_SPAWN else "delivery_authorized")) if result["decision"] == "allow" and op_class in ENFORCED
        else ("delivery_blocked" if result["decision"] == "deny" else ("publication_requested" if op_class == PUBLICATION else None)),
        "run_id": (result.get("verdict") or {}).get("run_id") or run_id,
        "operation_class": op_class,
    }
    _persist_event(root, result, payload, run_id)
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
