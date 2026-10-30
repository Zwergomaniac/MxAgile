"""Build a deterministic, read-only MxAgile project-status projection."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import yaml

PHASES = ("discovery", "refinement", "ready", "implementing", "verifying", "done")
TASK_STATUSES = ("pending", "in_progress", "done", "failed", "blocked", "deferred")
REQUIREMENT_STATUSES = ("draft", "accepted", "deferred", "superseded")
DECISION_STATUSES = ("PROPOSED", "CONFIRMED", "REJECTED", "SUPERSEDED")
CONTRACT_STATUSES = ("draft", "active", "stale", "impacted", "superseded")
PROOF_POINT_STATUSES = ("active", "stale", "impacted", "deferred", "not_applicable")
PLAN_STATUSES = ("draft", "active", "superseded")
EVIDENCE_STATUSES = ("PASS", "FAIL", "PARTIAL", "NOT_VERIFIED", "STALE", "LEGACY_EVIDENCE")
BLOCKER_TYPES = (
    "INFRASTRUCTURE_GAP", "LOCATOR_UNSTABLE", "ROLE_SWITCH_BLOCKED",
    "DECISION_REQUIRED", "SCOPE_EXCEEDED", "OTHER",
)


def add_gap(gaps: list[dict[str, str | None]], code: str, source: str | None, description: str) -> None:
    gap = {"code": code, "source": source, "description": description}
    if gap not in gaps:
        gaps.append(gap)


def safe_path(root: Path, path: Path) -> bool:
    if path.is_symlink():
        return False
    try:
        path.resolve().relative_to(root)
    except (OSError, ValueError):
        return False
    return True


def read_yaml_file(
    root: Path,
    relative_path: str,
    hashes: dict[str, str],
    gaps: list[dict[str, str | None]],
) -> tuple[Any, str]:
    path = root / relative_path
    if not path.exists():
        hashes[f"!missing:{relative_path}"] = "missing"
        return None, "missing"
    if not safe_path(root, path) or not path.is_file():
        hashes[f"!invalid:{relative_path}"] = "invalid"
        add_gap(gaps, "SOURCE_PATH_INVALID", relative_path, "Canonical source is not a regular file inside the project root.")
        return None, "invalid"
    try:
        raw = path.read_bytes()
        hashes[relative_path] = hashlib.sha256(raw).hexdigest()
        value = yaml.safe_load(raw.decode("utf-8-sig"))
    except (OSError, UnicodeError, yaml.YAMLError):
        add_gap(gaps, "SOURCE_PARSE_FAILED", relative_path, "Canonical source could not be read as UTF-8 YAML.")
        return None, "invalid"
    if not isinstance(value, dict):
        add_gap(gaps, "SOURCE_SHAPE_INVALID", relative_path, "Canonical source must contain a YAML object.")
        return None, "invalid"
    return value, "available"


def read_collection(
    root: Path,
    directory: str,
    pattern: str,
    id_field: str,
    hashes: dict[str, str],
    gaps: list[dict[str, str | None]],
) -> tuple[str, list[dict[str, Any]], list[str]]:
    base = root / directory
    if not base.exists():
        hashes[f"!missing-directory:{directory}"] = "missing"
        return "unavailable", [], []
    if not safe_path(root, base) or not base.is_dir():
        hashes[f"!invalid-directory:{directory}"] = "invalid"
        add_gap(gaps, "SOURCE_PATH_INVALID", directory, "Canonical source directory is not inside the project root.")
        return "unavailable", [], []

    paths = sorted(base.glob(pattern), key=lambda item: item.as_posix())
    if not paths:
        hashes[f"!empty-directory:{directory}:{pattern}"] = "empty"
        return "available", [], []

    records: list[dict[str, Any]] = []
    relative_paths: list[str] = []
    invalid = 0
    for path in paths:
        relative = path.relative_to(root).as_posix()
        value, state = read_yaml_file(root, relative, hashes, gaps)
        if state != "available" or not isinstance(value, dict):
            invalid += 1
            continue
        if id_field:
            expected_id = path.parent.name if path.name == "revision.yaml" else path.stem
            if value.get(id_field) != expected_id:
                add_gap(gaps, "ARTIFACT_ID_MISMATCH", relative, f"{id_field} does not match the canonical filename or revision directory.")
                invalid += 1
                continue
        records.append(value)
        relative_paths.append(relative)

    if invalid and records:
        return "partial", records, relative_paths
    if invalid:
        return "unavailable", [], []
    return "available", records, relative_paths


def status_counts(
    records: list[dict[str, Any]], field: str, statuses: tuple[str, ...], available: bool
) -> dict[str, int | None]:
    result: dict[str, int | None] = {status: 0 if available else None for status in statuses}
    result["unknown"] = 0 if available else None
    if not available:
        return result
    for record in records:
        value = record.get(field)
        if value in statuses:
            result[value] = int(result[value] or 0) + 1
        else:
            result["unknown"] = int(result["unknown"] or 0) + 1
    return result


def wave_projection(process_state: dict[str, Any] | None) -> tuple[str, list[dict[str, Any]], dict[str, int | None]]:
    waves_data = process_state.get("waves") if isinstance(process_state, dict) else None
    if not isinstance(waves_data, dict):
        counts = {phase: None for phase in PHASES}
        counts["unknown"] = None
        return "unavailable", [], counts

    items: list[dict[str, Any]] = []
    counts = {phase: 0 for phase in PHASES}
    counts["unknown"] = 0
    partial = False
    for wave_id, state in sorted(waves_data.items(), key=lambda item: str(item[0])):
        if not isinstance(state, dict):
            phase = None
            gates_data = {}
            partial = True
        else:
            phase = state.get("phase") if state.get("phase") in PHASES else None
            gates_data = state.get("gates") if isinstance(state.get("gates"), dict) else {}
            if phase is None:
                partial = True
        counts[phase or "unknown"] += 1
        gates: dict[str, str | None] = {}
        for gate in ("gate_to_refinement", "gate_to_ready"):
            gate_data = gates_data.get(gate)
            result = gate_data.get("result") if isinstance(gate_data, dict) else None
            gates[gate] = result if result in ("not_recorded", "passed", "failed") else None
            if gates[gate] is None:
                partial = True
        items.append({"wave_id": str(wave_id), "phase": phase, "gates": gates})
    return ("partial" if partial else "available"), items, counts


def mission_projection(
    mission_doc: dict[str, Any] | None, source_state: str
) -> tuple[dict[str, Any], str | None]:
    empty_types: dict[str, int | None] = {kind: None for kind in BLOCKER_TYPES}
    if mission_doc is None:
        return {
            "availability": "unavailable", "id": None, "status": None,
            "blocker_count": None, "blocker_types": empty_types,
        }, None

    progress = mission_doc.get("progress") if isinstance(mission_doc.get("progress"), dict) else {}
    status = progress.get("mission")
    if status not in ("active", "complete", "blocked", "archived"):
        status = None
    blockers = mission_doc.get("blockers")
    availability = "available" if source_state == "available" and status else "partial"
    blocker_count: int | None = None
    if isinstance(blockers, list):
        blocker_count = len(blockers)
        blocker_types = {kind: 0 for kind in BLOCKER_TYPES}
        for blocker in blockers:
            kind = blocker.get("type") if isinstance(blocker, dict) else None
            blocker_types[kind if kind in blocker_types else "OTHER"] += 1
    else:
        blocker_types = empty_types
        availability = "partial"
    mission_id = mission_doc.get("mission_id") if isinstance(mission_doc.get("mission_id"), str) else None
    active_wave = mission_doc.get("active_wave") if isinstance(mission_doc.get("active_wave"), str) else None
    return {
        "availability": availability, "id": mission_id, "status": status,
        "blocker_count": blocker_count, "blocker_types": blocker_types,
    }, active_wave


def build_status(project_root: Path) -> dict[str, Any]:
    root = project_root.resolve()
    hashes: dict[str, str] = {}
    gaps: list[dict[str, str | None]] = []

    project_config, _ = read_yaml_file(root, "mxagile-project.yaml", hashes, gaps)
    version_doc, version_state = read_yaml_file(root, ".mxagile/version.yaml", hashes, gaps)
    process_doc, process_state = read_yaml_file(root, "planning/lifecycle/process-state.yaml", hashes, gaps)
    mission_doc, mission_state = read_yaml_file(root, "planning/mission/mission-state.yaml", hashes, gaps)
    context_doc, context_state = read_yaml_file(root, "planning/lifecycle/context-epoch.yaml", hashes, gaps)

    requirement_state, requirements, _ = read_collection(root, "requirements", "*.yml", "ID", hashes, gaps)
    task_state, tasks, _ = read_collection(root, "planning/tasks", "*.yml", "ID", hashes, gaps)
    decision_state, decisions, _ = read_collection(root, "planning/decisions", "*.yml", "ID", hashes, gaps)
    contract_state, contracts, _ = read_collection(root, "planning/test-contracts", "*.yaml", "ID", hashes, gaps)
    plan_state, plans, _ = read_collection(root, "planning/verification-plans", "*.yaml", "ID", hashes, gaps)
    evidence_state, manifests, _ = read_collection(
        root, "planning/evidence/manifests", "*-evidence-manifest.yaml", "", hashes, gaps
    )
    revision_state, revisions, revision_paths = read_collection(
        root, "planning/target-mockups", "*/_history/REV-*/revision.yaml", "revision_id", hashes, gaps
    )

    active_revisions = [
        (path, revision)
        for path, revision in zip(revision_paths, revisions)
        if revision.get("active_target") is True
    ]
    active_targets: dict[str, dict[str, Any]] = {}
    if revision_state == "partial" or len(active_revisions) > 1:
        target_availability = "ambiguous"
        target = {"availability": target_availability, "mockup": None, "revision_id": None, "bundle_hash": None, "source_path": None}
        add_gap(gaps, "ACTIVE_TARGET_AMBIGUOUS", "planning/target-mockups", "A unique active target cannot be proven from all revision sources.")
    elif len(active_revisions) == 1:
        path, revision = active_revisions[0]
        target = {
            "availability": "available",
            "mockup": revision.get("mockup_name") if isinstance(revision.get("mockup_name"), str) else None,
            "revision_id": revision.get("revision_id") if isinstance(revision.get("revision_id"), str) else None,
            "bundle_hash": revision.get("bundle_hash") if isinstance(revision.get("bundle_hash"), str) else None,
            "source_path": path,
        }
        if target["mockup"]:
            active_targets[target["mockup"]] = target
    else:
        target = {"availability": "unavailable", "mockup": None, "revision_id": None, "bundle_hash": None, "source_path": None}
        add_gap(gaps, "ACTIVE_TARGET_UNAVAILABLE", "planning/target-mockups", "No unique revision declares active_target: true.")

    wave_state, waves, wave_counts = wave_projection(process_doc if process_state == "available" else None)
    mission, active_wave_id = mission_projection(mission_doc, mission_state)
    wave_by_id = {wave["wave_id"]: wave for wave in waves}
    if active_wave_id and active_wave_id in wave_by_id:
        lifecycle_phase = wave_by_id[active_wave_id]["phase"]
        lifecycle_availability = "available" if lifecycle_phase else "partial"
    elif active_wave_id:
        lifecycle_phase = None
        lifecycle_availability = "partial"
        add_gap(gaps, "ACTIVE_WAVE_NOT_FOUND", "planning/mission/mission-state.yaml", "Mission active_wave does not match a recorded process-state wave.")
    elif waves and all(wave["phase"] == "done" for wave in waves):
        lifecycle_phase = "done"
        lifecycle_availability = "available"
    else:
        lifecycle_phase = None
        lifecycle_availability = "unavailable"

    project_name = project_config.get("name") if isinstance(project_config, dict) else None
    if not isinstance(project_name, str) or not project_name.strip():
        mpr_files = sorted(root.glob("*.mpr"), key=lambda item: item.name.lower())
        project_name = mpr_files[0].stem if len(mpr_files) == 1 else root.name
    core_version = version_doc.get("version") if isinstance(version_doc, dict) else None
    project_availability = "available" if version_state == "available" else "partial"
    add_gap(gaps, "PROJECT_ID_UNAVAILABLE", "mxagile-project.yaml", "No stable project identifier exists; display name is not an identity.")

    def available(state: str) -> bool:
        return state == "available"

    def normalized(state: str) -> str:
        return state if state in ("available", "partial", "unavailable", "ambiguous") else "unavailable"

    req_counts = status_counts(requirements, "status", REQUIREMENT_STATUSES, available(requirement_state))
    task_counts = status_counts(tasks, "status", TASK_STATUSES, available(task_state))
    decision_counts = status_counts(decisions, "status", DECISION_STATUSES, available(decision_state))
    contract_counts = status_counts(contracts, "status", CONTRACT_STATUSES, available(contract_state))
    plan_counts = status_counts(plans, "status", PLAN_STATUSES, available(plan_state))

    proof_counts: dict[str, int | None] = {state: 0 if available(contract_state) else None for state in PROOF_POINT_STATUSES}
    proof_counts["unknown"] = 0 if available(contract_state) else None
    if available(contract_state):
        for contract in contracts:
            points = contract.get("proof_points")
            if not isinstance(points, list):
                proof_counts["unknown"] = int(proof_counts["unknown"] or 0) + 1
                continue
            for point in points:
                if not isinstance(point, dict):
                    proof_counts["unknown"] = int(proof_counts["unknown"] or 0) + 1
                    continue
                state = point.get("status", contract.get("status"))
                if state in PROOF_POINT_STATUSES:
                    proof_counts[state] = int(proof_counts[state] or 0) + 1
                else:
                    proof_counts["unknown"] = int(proof_counts["unknown"] or 0) + 1

    pending_affected_requirements = sorted({
        requirement_id
        for decision in decisions
        if decision.get("status") == "PROPOSED"
        for requirement_id in decision.get("affected_requirements", [])
        if isinstance(requirement_id, str)
    }) if available(decision_state) else []

    evidence_recorded = {state: 0 if available(evidence_state) else None for state in EVIDENCE_STATUSES}
    evidence_recorded["unknown"] = 0 if available(evidence_state) else None
    evidence_stale = 0 if available(evidence_state) else None
    evidence_failed = 0 if available(evidence_state) else None
    evidence_unverified = 0 if available(evidence_state) else None
    if available(evidence_state):
        for manifest in manifests:
            entries = manifest.get("entries")
            if not isinstance(entries, list):
                evidence_recorded["unknown"] = int(evidence_recorded["unknown"] or 0) + 1
                continue
            for entry in entries:
                if not isinstance(entry, dict):
                    evidence_recorded["unknown"] = int(evidence_recorded["unknown"] or 0) + 1
                    continue
                result = entry.get("parity_result")
                if result in EVIDENCE_STATUSES:
                    evidence_recorded[result] = int(evidence_recorded[result] or 0) + 1
                else:
                    evidence_recorded["unknown"] = int(evidence_recorded["unknown"] or 0) + 1
                target_for_entry = active_targets.get(entry.get("mockup_name"))
                target_mismatch = bool(target_for_entry and (
                    (entry.get("target_revision") and entry.get("target_revision") != target_for_entry.get("revision_id"))
                    or (entry.get("bundle_hash") and target_for_entry.get("bundle_hash") and entry.get("bundle_hash") != target_for_entry.get("bundle_hash"))
                ))
                if result == "STALE" or target_mismatch:
                    evidence_stale = int(evidence_stale or 0) + 1
                elif result == "FAIL":
                    evidence_failed = int(evidence_failed or 0) + 1
                elif result == "NOT_VERIFIED":
                    evidence_unverified = int(evidence_unverified or 0) + 1

    if process_state != "available":
        add_gap(gaps, "LIFECYCLE_STATE_UNAVAILABLE", "planning/lifecycle/process-state.yaml", "Canonical tracked process state is missing or invalid; local scratch state is not read.")
    if mission_state != "available":
        add_gap(gaps, "MISSION_STATE_UNAVAILABLE", "planning/mission/mission-state.yaml", "Canonical mission state is missing or invalid.")
    if task_state != "available":
        add_gap(gaps, "TASKS_UNAVAILABLE", "planning/tasks", "Canonical task collection is missing or incomplete.")
    add_gap(gaps, "CHECKLIST_SCHEMA_UNAVAILABLE", "planning/checklists", "Legacy checklist formats have no canonical schema and are not interpreted.")
    add_gap(gaps, "WORKPACKAGE_MAPPING_UNAVAILABLE", "planning/tasks", "Canonical task schema has no wave or workpackage relationship.")
    add_gap(gaps, "FINDING_SCHEMA_UNAVAILABLE", None, "Core has no general finding identity and lifecycle contract.")
    add_gap(gaps, "MODEL_FRESHNESS_UNAVAILABLE", "planning/acceptance-campaigns", "Verification artifacts do not record a current Mendix model fingerprint.")
    add_gap(gaps, "OPERATING_MODE_UNAVAILABLE", "machine/session observation", "Current Studio Pro operating mode is not a canonical project artifact.")
    add_gap(gaps, "CAPABILITY_SESSION_STATE_UNAVAILABLE", ".mxagile/capabilities.yaml", "Current capability activity requires session-attested environment evidence.")
    add_gap(gaps, "CONTEXT_SESSION_STATE_UNAVAILABLE", "Context Mode session", "Current context mode and pressure are not durable project status.")
    add_gap(gaps, "MULTI_SOURCE_UNAVAILABLE", None, "Core has no canonical source or agent-session registry.")

    context_status = {"availability": "unavailable", "epoch_id": None, "phase": None, "mode": None, "pressure": None}
    if context_state == "available":
        context_meta = context_doc.get("context") if isinstance(context_doc, dict) else None
        lifecycle_meta = context_doc.get("lifecycle") if isinstance(context_doc, dict) else None
        if isinstance(context_meta, dict):
            epoch_id = context_meta.get("epoch_id")
            pressure = context_meta.get("pressure_state")
            phase = lifecycle_meta.get("current_phase") if isinstance(lifecycle_meta, dict) else None
            context_status.update({
                "availability": "partial" if isinstance(epoch_id, str) else "unavailable",
                "epoch_id": epoch_id if isinstance(epoch_id, str) else None,
                "phase": phase if phase in ("discovery", "refinement", "ready", "implementing", "verifying", "done") else None,
                "pressure": pressure if pressure in ("UNKNOWN", "NORMAL", "PRESSURE", "ROLLOVER_RECOMMENDED", "ROLLOVER_REQUIRED") else None,
            })
    else:
        add_gap(gaps, "CONTEXT_EPOCH_UNAVAILABLE", "planning/lifecycle/context-epoch.yaml", "No canonical context handoff is available in this project snapshot.")

    hashes_payload = "\n".join(f"{path}:{digest}" for path, digest in sorted(hashes.items()))
    source_fingerprint = "sha256:" + hashlib.sha256(hashes_payload.encode("utf-8")).hexdigest()

    runtime = {
        "runtime_config": None, "runtime_mode": None, "database": None,
        "mock_data": None, "test_identities": None,
        "runtime_pipeline_stage": None, "dependency_sync_state": None,
    }
    runtime_availability = "unavailable"
    waves_data = process_doc.get("waves") if isinstance(process_doc, dict) else None
    wave_data = waves_data.get(active_wave_id) if isinstance(waves_data, dict) and active_wave_id else None
    prerequisites = wave_data.get("prerequisite_state") if isinstance(wave_data, dict) else None
    if isinstance(prerequisites, dict):
        for field in runtime:
            value = prerequisites.get(field)
            runtime[field] = value if isinstance(value, str) else None
        runtime_availability = "partial"

    return {
        "schema_version": 1,
        "projection": True,
        "authority": "mxagile_canonical_artifacts",
        "source_fingerprint": source_fingerprint,
        "project": {
            "availability": project_availability,
            "id": None,
            "name": project_name,
            "core_version": core_version if isinstance(core_version, str) else None,
            "active_target": target,
            "lifecycle": {"availability": lifecycle_availability, "active_wave_id": active_wave_id, "phase": lifecycle_phase},
        },
        "mission": mission,
        "delivery": {
            "waves": {"availability": wave_state, "items": waves, "phase_counts": wave_counts},
            "task_progress": {
                "availability": normalized(task_state),
                "total": len(tasks) if available(task_state) else None,
                "status_counts": task_counts,
            },
            "checklist_progress": {"availability": "unavailable", "total": None, "done": None, "source": None},
            "workpackages": {"availability": "unavailable", "items": []},
        },
        "requirements": {
            "availability": normalized(requirement_state),
            "total": len(requirements) if available(requirement_state) else None,
            "status_counts": req_counts,
        },
        "decisions": {
            "availability": normalized(decision_state),
            "total": len(decisions) if available(decision_state) else None,
            "status_counts": decision_counts,
            "pending_affected_requirements": pending_affected_requirements,
            "blocked_by_decision": {"availability": "unavailable", "count": None},
        },
        "verification": {
            "test_contracts": {"availability": normalized(contract_state), "status_counts": contract_counts},
            "proof_points": {"availability": normalized(contract_state), "status_counts": proof_counts},
            "plans": {"availability": normalized(plan_state), "status_counts": plan_counts},
            "evidence": {
                "availability": normalized(evidence_state),
                "freshness": "unknown",
                "recorded_counts": evidence_recorded,
                "current_counts": {
                    "verified": None, "unverified": evidence_unverified,
                    "stale": evidence_stale, "failed": evidence_failed, "pending": None,
                },
            },
        },
        "findings": {"availability": "unavailable", "open": None, "blocking": None, "closed": None},
        "runtime": {
            "readiness_availability": runtime_availability,
            "recorded_readiness": runtime,
            "operating_mode_availability": "unavailable",
            "operating_mode": None,
        },
        "capabilities": {"availability": "unavailable", "active_count": None},
        "context": context_status,
        "sources": {"availability": "unavailable", "items": []},
        "gaps": sorted(gaps, key=lambda gap: (gap["code"], gap["source"] or "", gap["description"])),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Emit deterministic MxAgile project-status JSON.")
    parser.add_argument("--project-root", type=Path, default=Path.cwd(), help="Project root (default: current directory).")
    args = parser.parse_args()
    try:
        status = build_status(args.project_root)
    except (OSError, ValueError) as exc:
        print(f"project status unavailable: {type(exc).__name__}", file=sys.stderr)
        return 2
    print(json.dumps(status, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())