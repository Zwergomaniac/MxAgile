"""Child transition contract for runtime visual verification.

Routing, handoff construction, deterministic child acceptance and the visual gate evaluator.
Nothing here writes lifecycle state; results are evaluations plus non-persisted event candidates.
"""

from __future__ import annotations

import hashlib
import itertools
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft7Validator

sys.path.insert(0, str(Path(__file__).resolve().parent))
import enforcement  # noqa: E402
import guard  # noqa: E402

VERDICT_SCHEMA = json.loads(Path(__file__).with_name("control-plane-verdict.schema.json").read_text(encoding="utf-8"))
RUNTIME_VISUAL = "runtime_visual_verification"
OUTPUT_CONTRACT = "control-plane-verdict/1.0#visual_verification"
DEFAULT_MAX_ROUNDS = 2
IMPLEMENTATION_FORBIDDEN = ["*.mpr", "mprcontents/", "javascriptsource/", "themesource/", "theme/", "widgets/", "planning/lifecycle/", "planning/mission/"]
STALE_CODES = {
    "mockup_revision": "MOCKUP_REVISION_CHANGED",
    "requirement": "REQUIREMENT_CHANGED",
    "decision": "DECISION_CHANGED",
    "page": "PAGE_IMPLEMENTATION_CHANGED",
    "lifecycle": "WAVE_STATE_CHANGED",
    "roles_states": "ROLE_STATE_SET_CHANGED",
    "implementation_revision": "IMPLEMENTATION_REVISION_CHANGED",
    "contract": "VERIFICATION_CONTRACT_CHANGED",
}
_RANK = {"pass": 0, "partial": 1, "unavailable": 2, "fail": 3, "needs_human": 4}


def route_intent(text: str) -> dict[str, Any]:
    """Deterministic capability routing; a mockup-vs-app request with dynamics is never static analysis."""
    lowered = text.lower()
    mockup = any(word in lowered for word in ("mockup", "design", "entwurf"))
    app = any(word in lowered for word in ("app", "runtime", "anwendung", "page", "seite"))
    dynamic = any(word in lowered for word in ("dynami", "zustand", "state", "visuell", "visual", "blocker", "lücke", "luecke", "gap"))
    if mockup and app and dynamic:
        return {
            "capability": RUNTIME_VISUAL,
            "requires_runtime_evidence": True,
            "required_inputs": ["mockup_revision", "page", "roles", "states", "requirements", "decisions", "evidence_destination"],
            "required_tools": ["browser", "playwright"],
            "write_classes": ["EVIDENCE_WRITE"],
        }
    return {"capability": "static_analysis", "requires_runtime_evidence": False, "required_inputs": [], "required_tools": [], "write_classes": []}


def _sha(root: Path, relative: str) -> str:
    path = guard._safe_project_file(root, relative)
    return hashlib.sha256(path.read_bytes()).hexdigest() if path and path.is_file() else "missing"


def _contract_digest(contract: dict[str, Any]) -> str:
    return hashlib.sha256(json.dumps(contract, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def input_fingerprint(root: Path, contract: dict[str, Any]) -> dict[str, str]:
    """Semantic inputs of one visual verdict; values are `identity@digest` so reasons stay explainable."""
    mockup = contract["mockup"]
    fingerprint = {f"mockup_revision:{mockup['path']}": f"{mockup['identity']}@{_sha(root, mockup['path'])}"}
    for kind in ("requirement", "decision"):
        for item in contract.get(f"{kind}s", []):
            fingerprint[f"{kind}:{item['id']}"] = f"{item['id']}@{_sha(root, item['path'])}"
    page = contract["page"]
    fingerprint[f"page:{page['identity']}"] = f"{page['identity']}@{_sha(root, page['path'])}" if page.get("path") else page["identity"]
    pairs = sorted(f"{role}/{state}" for role, state in required_pairs(contract))
    fingerprint["roles_states"] = hashlib.sha256("|".join(pairs).encode("utf-8")).hexdigest()
    implementation = contract.get("implementation_paths") or []
    if implementation:
        joined = "|".join(f"{path}={_sha(root, path)}" for path in sorted(implementation))
        fingerprint["implementation_revision"] = hashlib.sha256(joined.encode("utf-8")).hexdigest()
    else:
        fingerprint["implementation_revision"] = guard._git_value(root, "rev-parse", "HEAD") or "unknown"
    fingerprint["contract"] = _contract_digest(contract)
    return fingerprint


def stale_reasons(recorded: dict[str, str], current: dict[str, str]) -> list[dict[str, str]]:
    reasons = []
    for key in sorted(set(recorded) | set(current)):
        if recorded.get(key) == current.get(key):
            continue
        kind = key.split(":", 1)[0]
        before, after = (recorded.get(key) or "absent"), (current.get(key) or "absent")
        reasons.append({"code": STALE_CODES.get(kind, "INPUT_CHANGED"), "input": key,
                        "from": before.split("@", 1)[0], "to": after.split("@", 1)[0]})
    return reasons


def required_pairs(contract: dict[str, Any]) -> list[tuple[str, str]]:
    explicit = contract.get("required_coverage")
    if explicit:
        return [tuple(pair) for pair in explicit]
    return list(itertools.product(contract.get("roles", []), contract.get("states", [])))


def build_visual_handoff(
    facts: guard.ProjectFacts,
    contract: dict[str, Any],
    *,
    agent_type: str,
    delegation_id: str,
    route_decision_reference: str,
    parent_observations: dict[str, Any],
    authorization_reference: str | None = None,
) -> dict[str, Any]:
    root = facts.root
    sources = [{"kind": "mockup_revision", "identity": contract["mockup"]["identity"], "path": contract["mockup"]["path"]}]
    sources += [{"kind": "requirement", "identity": item["id"], "path": item["path"]} for item in contract.get("requirements", [])]
    sources += [{"kind": "decision", "identity": item["id"], "path": item["path"]} for item in contract.get("decisions", [])]
    if contract["page"].get("path"):
        sources.append({"kind": "page", "identity": contract["page"]["identity"], "path": contract["page"]["path"]})
    sources.append({"kind": "lifecycle", "identity": "process-state", "path": "planning/lifecycle/process-state.yaml"})
    for source in sources:
        source["sha256"] = _sha(root, source["path"])
    paths = [source["path"] for source in sources]
    destination = contract["evidence_destination"].rstrip("/") + "/"
    wave_id = facts.mission.get("active_wave")
    return {
        "schema_version": "1.4",
        "mission_id": facts.mission.get("mission_id"),
        "delivery_context": {
            "wave_id": wave_id, "work_package_id": f"VISUAL-{contract['page']['identity']}", "project_root": str(root),
            "branch": facts.branch, "worktree": None, "base_head": facts.head,
            "operating_mode": parent_observations.get("operating_mode", "UNKNOWN"),
            "authorization": "read_only", "write_scope": [destination], "forbidden_scope": IMPLEMENTATION_FORBIDDEN,
            "required_artifacts": paths, "verification_expectations": ["runtime evidence per required role/state"],
            "commit_expectation": "no_commit",
            "resync_conditions": ["base HEAD changed", "input source fingerprint changed", "update or migration state active"],
            "required_skills": ["mxagile-visual-verification"], "loaded_skills": [],
            "required_capabilities": [RUNTIME_VISUAL], "available_capabilities": [],
            "required_evidence_sources": ["browser"], "evidence_destinations": [destination], "output_artifacts": [OUTPUT_CONTRACT],
            "requested_model_profile": "MID", "resolved_model": None, "effective_model": None, "effective_model_status": "not_observable",
        },
        "delegation_id": delegation_id,
        "task": "Runtime visual and dynamic gap verification: mockup vs. app",
        "agent_type": agent_type,
        "scope": {"summary": f"Visual verification of {contract['page']['identity']}", "paths": paths},
        "authority_references": [],
        "artifact_paths": paths,
        "source_fingerprints": [{"path": source["path"], "sha256": source["sha256"]} for source in sources],
        "allowed_tools": ["read", "browser", "write:evidence"],
        "forbidden_mutations": IMPLEMENTATION_FORBIDDEN,
        "expected_result_schema": "delegation-result/1.1",
        "model_profile": "MID",
        "model_resolution": {"model_selection": "unknown", "profile_resolution": "unknown", "resolution": "not_requested",
                             "resolved_model": None, "requested_reasoning_effort": None, "fallback_used": False, "fallback_reason": None},
        "run_id": enforcement.new_run_id(),
        "parent_run_id": None,
        "capability": RUNTIME_VISUAL,
        "route_decision_reference": route_decision_reference,
        "write_classes": ["EVIDENCE_WRITE"],
        "evidence_destination": destination,
        "required_tools": ["browser", "playwright"],
        "input_sources": sources,
        "output_contract": OUTPUT_CONTRACT,
        "parent_observations": parent_observations,
        "authorization_reference": authorization_reference,
        "verification_contract": contract,
    }


def _evidence_problem(root: Path, destination: str, item: dict[str, Any]) -> str | None:
    relative = item["path"].replace("\\", "/")
    if not relative.startswith(destination):
        return f"outside evidence destination: {relative}"
    path = guard._safe_project_file(root, relative)
    if path is None or not path.is_file():
        return f"missing: {relative}"
    if hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
        return f"fingerprint mismatch: {relative}"
    return None


def evaluate_visual_gate(root: str | Path, contract: dict[str, Any], verdict: dict[str, Any]) -> dict[str, Any]:
    """Deterministic visual gate; a child claim can lower but never raise the result."""
    root = Path(root).resolve()
    run_id = verdict.get("run_id") if isinstance(verdict, dict) else None
    result: dict[str, Any] = {"gate_type": "visual_verification", "reasons": [], "stale_reasons": [], "coverage": {}}

    def finish(gate_result: str, consequence: str, event_type: str) -> dict[str, Any]:
        result.update({"gate_result": gate_result, "allowed_consequence": consequence,
                       "event": {"type": event_type, "run_id": run_id, "gate_result": gate_result}})
        return result

    errors = list(Draft7Validator(VERDICT_SCHEMA).iter_errors(verdict)) if isinstance(verdict, dict) else ["not an object"]
    if errors or verdict.get("gate_type") != "visual_verification" or "visual" not in verdict:
        result["reasons"].append("VERDICT_INVALID")
        return finish("FAIL", "none", "gate_evaluated")
    visual = verdict["visual"]
    result["stale_reasons"] = stale_reasons(visual["input_fingerprint"], input_fingerprint(root, contract))
    if result["stale_reasons"]:
        result["reasons"].append("INPUTS_CHANGED")
        return finish("STALE", "re-evaluation required", "gate_invalidated")

    round_number = int(verdict.get("round") or 1)
    max_rounds = int(contract.get("max_rounds") or DEFAULT_MAX_ROUNDS)
    if verdict["must_findings"]:
        result["reasons"] += [finding["code"] for finding in verdict["must_findings"]]
        if round_number >= max_rounds:
            result["reasons"].append("ROUND_LIMIT")
            return finish("NEEDS_HUMAN", "escalate to developer", "recovery_required")
        return finish("FAIL", f"repair round {round_number + 1} of {max_rounds}", "repair_round_started")
    if verdict["verdict"] == "needs_human":
        return finish("NEEDS_HUMAN", "escalate to developer", "recovery_required")

    destination = contract["evidence_destination"].rstrip("/") + "/"
    problems = [problem for item in visual["evidence"] if (problem := _evidence_problem(root, destination, item))]
    if problems:
        result["reasons"] += [f"EVIDENCE_INVALID: {problem}" for problem in problems]
        return finish("FAIL", "none", "gate_evaluated")
    layers: dict[tuple[str, str], set[str]] = {}
    for item in visual["evidence"]:
        layers.setdefault((item["role"], item["state"]), set()).add(item["layer"])
    pairs = required_pairs(contract)
    for role, state in pairs:
        observed = layers.get((role, state), set())
        result["coverage"][f"{role}/{state}"] = "runtime" if "runtime" in observed else ("static" if observed else "missing")
    coverage = set(result["coverage"].values())
    if not pairs or coverage == {"missing"}:
        claim = "unavailable"
    elif coverage == {"runtime"} and visual["verification_mode"] == "runtime":
        claim = "pass"
    else:
        claim = "partial"
        result["reasons"].append("RUNTIME_EVIDENCE_INCOMPLETE")
    effective = max(claim, verdict["verdict"], key=lambda value: _RANK.get(value, 2))
    consequence = "ui_verification may be recorded as passed by the lifecycle owner" if effective == "pass" else "none"
    return finish(effective.upper(), consequence, "gate_evaluated")


def _changed_paths(root: Path, base_head: str) -> list[str]:
    paths: set[str] = set()
    for args in (("diff", "--name-only", base_head), ("ls-files", "--others", "--exclude-standard")):
        result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, check=False)
        paths.update(line.strip() for line in result.stdout.splitlines() if line.strip())
    return sorted(paths)


def accept_child_result(
    root: str | Path,
    handoff: dict[str, Any],
    verdict: dict[str, Any] | None,
    contract: dict[str, Any],
    *,
    changed_paths: list[str] | None = None,
) -> dict[str, Any]:
    """`process exited` is not `delivery accepted`: deterministic acceptance of one child result."""
    root = Path(root).resolve()
    findings: list[dict[str, str]] = []
    status = "ACCEPTED"

    def demote(new_status: str) -> None:
        nonlocal status
        order = ["ACCEPTED", "PARTIAL", "NEEDS_HUMAN", "STALE", "REJECTED"]
        status = max(status, new_status, key=order.index)

    if not isinstance(verdict, dict):
        findings.append({"code": "OUTPUT_MISSING", "summary": "The child produced no verdict."})
        demote("REJECTED")
        verdict = {}
    elif list(Draft7Validator(VERDICT_SCHEMA).iter_errors(verdict)) or verdict.get("gate_type") != "visual_verification" or "visual" not in verdict:
        findings.append({"code": "OUTPUT_CONTRACT_VIOLATED", "summary": f"Verdict does not satisfy {OUTPUT_CONTRACT}."})
        demote("REJECTED")
    elif verdict.get("run_id") != handoff.get("run_id"):
        findings.append({"code": "CORRELATION_MISMATCH", "summary": "Verdict run_id differs from the handoff run_id."})
        demote("REJECTED")
    elif verdict.get("verdict") == "needs_human":
        findings.append({"code": "CHILD_REPORTED_NEEDS_HUMAN", "summary": "The child reported a problem that needs a human decision."})
        demote("NEEDS_HUMAN")

    facts = guard.load_project_facts(root)
    integrity, _ = guard._lifecycle_integrity(facts)
    blocking = [finding for finding in integrity if finding["disposition"] != "advisory"]
    if blocking:
        findings += [{"code": finding["code"], "summary": finding["summary"]} for finding in blocking]
        demote("STALE")
    if facts.head != handoff["delivery_context"]["base_head"]:
        findings.append({"code": "BASE_HEAD_CHANGED", "summary": "HEAD moved after the child was authorized."})
        demote("STALE")
    changed_inputs = set()
    for source in handoff.get("input_sources") or []:
        if _sha(root, source["path"]) != source["sha256"]:
            if source["kind"] != "page":
                changed_inputs.add(source["path"])
            findings.append({"code": STALE_CODES.get(source["kind"], "INPUT_CHANGED"), "summary": f"{source['identity']} changed after authorization."})
            demote("STALE")

    allowed = set(handoff.get("write_classes") or [])
    destination = str(handoff.get("evidence_destination") or "")
    observed = _changed_paths(root, handoff["delivery_context"]["base_head"]) if changed_paths is None else changed_paths
    forbidden = []
    for path in observed:
        # Git cannot attribute a change; input and framework-state changes are already staleness causes.
        if path in changed_inputs or (blocking and path.startswith(".mxagile/state/")):
            continue
        op_class = enforcement.classify_path(root, path)
        if op_class == enforcement.EVIDENCE_WRITE and destination and not path.startswith(destination):
            op_class = "EVIDENCE_WRITE_OUTSIDE_DESTINATION"
        if path.startswith(destination) and destination:
            op_class = enforcement.EVIDENCE_WRITE
        if op_class not in allowed:
            forbidden.append({"path": path, "class": op_class})
    if forbidden:
        findings.append({"code": "FORBIDDEN_CHILD_WRITE", "summary": "; ".join(f"{item['path']} ({item['class']})" for item in forbidden)})
        demote("REJECTED")

    mode = (handoff.get("parent_observations") or {}).get("operating_mode", "UNKNOWN")
    if mode != "CLOSED-AUTONOM":
        # Unsaved Studio Pro edits are invisible to Git; absence of a diff is not proof of no model change.
        findings.append({"code": "MODEL_SCOPE_NOT_OBSERVABLE", "summary": f"Model changes are not observable in {mode}."})
        demote("PARTIAL")

    gate = None
    if status in {"ACCEPTED", "PARTIAL"}:
        gate = evaluate_visual_gate(root, contract, verdict)
        if status == "PARTIAL" and gate["gate_result"] == "PASS":
            gate["gate_result"], gate["allowed_consequence"] = "PARTIAL", "none"
            gate["reasons"].append("ACCEPTANCE_PARTIAL")
        # A delivered-but-incomplete output contract must never be booked as an accepted child result.
        gate_result = gate["gate_result"]
        if gate_result in {"PARTIAL", "UNAVAILABLE"}:
            findings.append({"code": "RUNTIME_EVIDENCE_INCOMPLETE", "summary": f"Visual gate is {gate_result}."})
            demote("PARTIAL")
        elif gate_result in {"STALE", "NEEDS_HUMAN"}:
            findings.append({"code": f"GATE_{gate_result}", "summary": "; ".join(gate["reasons"])})
            demote(gate_result)
        elif gate_result == "FAIL" and any(r == "VERDICT_INVALID" or r.startswith("EVIDENCE_INVALID") for r in gate["reasons"]):
            findings.append({"code": "EVIDENCE_INVALID", "summary": "; ".join(gate["reasons"])})
            demote("REJECTED")
    event_type = {"ACCEPTED": "child_completed", "PARTIAL": "child_completed", "REJECTED": "child_rejected",
                  "STALE": "recovery_required", "NEEDS_HUMAN": "recovery_required"}[status]
    return {"status": status, "findings": findings, "forbidden_changes": forbidden, "gate": gate,
            "event": {"type": event_type, "run_id": handoff.get("run_id"), "parent_run_id": handoff.get("parent_run_id")}}


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Mandatory child result acceptance.")
    parser.add_argument("command", choices=["accept"])
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--handoff", required=True)
    parser.add_argument("--verdict")
    args = parser.parse_args(argv)
    root = Path(args.project_root).resolve()
    try:
        handoff = json.loads((root / args.handoff).read_text(encoding="utf-8"))
        verdict_path = guard._safe_project_file(root, args.verdict) if args.verdict else None
        verdict = json.loads(verdict_path.read_text(encoding="utf-8")) if verdict_path and verdict_path.is_file() else None
        contract = handoff.get("verification_contract")
        if not isinstance(contract, dict):
            raise ValueError("handoff has no verification_contract")
        result = accept_child_result(root, handoff, verdict, contract)
    except Exception as exc:  # acceptance that cannot run is never an acceptance
        result = {"status": "NEEDS_HUMAN", "findings": [{"code": "ACCEPTANCE_UNAVAILABLE", "summary": type(exc).__name__}],
                  "forbidden_changes": [], "gate": None, "event": {"type": "recovery_required", "run_id": None, "parent_run_id": None}}
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
