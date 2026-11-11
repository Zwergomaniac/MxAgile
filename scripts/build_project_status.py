"""Build a deterministic, read-only MxAgile project-status projection."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from datetime import date, datetime
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import yaml

from project_compatibility import compatibility_report, identity_matches, is_standalone_interaction_artifact, load_yaml, projected_for_validation, schema_errors, safe_file, schema_validation_scope

PHASES = ("discovery", "refinement", "ready", "implementing", "verifying", "done")
TASK_STATUSES = ("pending", "in_progress", "done", "failed", "blocked", "deferred")
REQUIREMENT_STATUSES = ("draft", "accepted", "deferred", "superseded")
DECISION_STATUSES = ("PROPOSED", "CONFIRMED", "REJECTED", "SUPERSEDED")
CONTRACT_STATUSES = ("draft", "active", "stale", "impacted", "superseded")
PROOF_POINT_STATUSES = ("active", "stale", "impacted", "deferred", "not_applicable")
PLAN_STATUSES = ("draft", "active", "superseded")
EVIDENCE_STATUSES = ("PASS", "FAIL", "PARTIAL", "NOT_VERIFIED", "STALE", "LEGACY_EVIDENCE")
PARITY_DIMENSIONS = ("visual", "content", "structure", "state", "interaction", "responsive", "role")
PARITY_EVIDENCE_MATRIX = (
    "contract_parity", "model_parity", "structural_dom_parity",
    "behavioral_parity", "role_parity", "visual_whole_screen_parity",
)
MATRIX_PROOF_GROUPS = {
    "contract_parity": ({"contract_reference"},),
    "model_parity": ({"mxcli_inspect"},),
    "structural_dom_parity": ({"dom_text", "dom_selector", "accessibility_check"},),
    "behavioral_parity": ({"interaction_test"}, {"navigation_flow"}),
    "role_parity": ({"role_test"},),
    "visual_whole_screen_parity": ({"screenshot"},),
}
DIMENSION_PROOF_GROUPS = {
    "visual": ({"screenshot"},),
    "content": ({"dom_text"},),
    "structure": ({"dom_selector"}, {"screenshot"}),
    "state": ({"interaction_test"}, {"screenshot"}),
    "interaction": ({"interaction_test", "navigation_flow"},),
    "responsive": ({"viewport_test"}, {"screenshot"}),
    "role": ({"role_test"}, {"dom_selector"}),
}
BLOCKER_TYPES = (
    "INFRASTRUCTURE_GAP", "LOCATOR_UNSTABLE", "ROLE_SWITCH_BLOCKED",
    "DECISION_REQUIRED", "SCOPE_EXCEEDED", "OTHER",
)
FINDING_TERMINAL_STATUSES = frozenset(("VERIFIED", "SUPERSEDED", "RETIRED"))
DISPOSITION_ACTIONS = {
    "CONFIRMED_IMPLEMENTATION_GAP": "PROPOSE_IMPLEMENTATION",
    "REFERENCE_GAP": "REFERENCE_REFINEMENT",
    "AUTHORITY_CONFLICT": "DECISION_REQUIRED",
    "VERIFICATION_OUTSTANDING": "VERIFY",
    "INFORMATIONAL_COVERAGE_GAP": "NONE",
}
DISPOSITION_PROHIBITIONS = {
    "REFERENCE_GAP": "APP_IMPLEMENTATION",
    "AUTHORITY_CONFLICT": "SEMANTIC_IMPLEMENTATION",
    "VERIFICATION_OUTSTANDING": "APP_IMPLEMENTATION",
    "INFORMATIONAL_COVERAGE_GAP": "APP_IMPLEMENTATION",
}
SHA256_PATTERN = "sha256:"


def _emit_project_stage(stage: str, started: float, **fields: Any) -> None:
    if os.environ.get("MXAGILE_BOARD_PROFILE") != "1":
        return
    payload = {"event": "project_status_stage", "stage": stage,
               "seconds": round(time.perf_counter() - started, 4), **fields}
    sys.stderr.write("BOARD_TIMING " + json.dumps(payload, ensure_ascii=True, sort_keys=True) + "\n")


def _parity_date(value: Any) -> date | None:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        try:
            return date.fromisoformat(value[:10])
        except ValueError:
            return None
    return None


def _parity_evidence_items(report: dict[str, Any], names: tuple[str, ...]) -> list[dict[str, Any]]:
    dimensions = report.get("dimensions")
    if not isinstance(dimensions, dict):
        return []
    items: list[dict[str, Any]] = []
    for name in names:
        dimension = dimensions.get(name)
        if not isinstance(dimension, dict) or not isinstance(dimension.get("evidence"), list):
            continue
        items.extend(item for item in dimension["evidence"] if isinstance(item, dict))
    return items


def _has_proof(items: list[dict[str, Any]], expected_types: set[str] | None = None,
               passed: bool | None = True) -> bool:
    for item in items:
        if expected_types is not None and item.get("type") not in expected_types:
            continue
        if passed is not None and item.get("passed") is not passed:
            continue
        if any(isinstance(item.get(key), str) and item[key].strip()
               for key in ("description", "path", "capture_id", "selector", "expected", "actual")):
            return True
    return False


def _has_proof_groups(items: list[dict[str, Any]], groups: tuple[set[str], ...],
                      passed: bool | None = True) -> bool:
    return all(_has_proof(items, group, passed) for group in groups)


def _whole_screen_comparison_state(
    report: dict[str, Any],
    entry: dict[str, Any],
    validated_capture_sides: dict[str, str] | None,
    expected_result: str,
) -> str:
    review = report.get("whole_screen_review") if isinstance(report.get("whole_screen_review"), dict) else {}
    comparison_result = review.get("comparison_result")
    allowed_results = {"PASS", "FAIL", "PARTIAL", "CONFLICT"}
    if comparison_result in allowed_results and comparison_result != expected_result:
        return "CONFLICT"
    if comparison_result not in allowed_results:
        return "UNKNOWN" if comparison_result is not None else "MISSING"
    if review.get("status") != "complete" or comparison_result != expected_result:
        return "MISSING"
    summary = review.get("comparison_summary")
    if not isinstance(summary, str) or not summary.strip():
        return "MISSING"

    reference_ids = review.get("reference_capture_ids")
    runtime_ids = review.get("runtime_capture_ids")
    reviewed_ids = review.get("visually_reviewed_capture_ids")
    matrix_capture_ids = entry.get("capture_ids")
    evidence = entry.get("evidence") if isinstance(entry.get("evidence"), list) else []
    if not all(isinstance(value, list) and value and all(isinstance(item, str) for item in value)
               for value in (reference_ids, runtime_ids)):
        return "MISSING"
    if not isinstance(reviewed_ids, list) or not all(isinstance(item, str) for item in reviewed_ids):
        return "MISSING"
    if not isinstance(matrix_capture_ids, list) or not all(isinstance(item, str) for item in matrix_capture_ids):
        return "MISSING"

    sides = validated_capture_sides if isinstance(validated_capture_sides, dict) else {}
    expected_capture_ids = set(reference_ids + runtime_ids)
    screenshot_capture_ids = {
        item.get("capture_id") for item in evidence
        if isinstance(item, dict) and item.get("type") == "screenshot"
        and item.get("passed") is True and isinstance(item.get("capture_id"), str)
    }
    if (
        not expected_capture_ids
        or not expected_capture_ids.issubset(set(reviewed_ids))
        or not expected_capture_ids.issubset(set(matrix_capture_ids))
        or not expected_capture_ids.issubset(screenshot_capture_ids)
        or not all(sides.get(capture_id) == "mockup" for capture_id in reference_ids)
        or not all(sides.get(capture_id) == "application" for capture_id in runtime_ids)
    ):
        return "MISSING"
    return "VALID"


def validated_contract_source_hashes(project_root: Path, report: dict[str, Any]) -> dict[str, str]:
    """Hash only explicitly referenced canonical requirements/decisions; never scan collections."""
    root = project_root.resolve()
    matrix = report.get("evidence_matrix") if isinstance(report, dict) else None
    contract = matrix.get("contract_parity") if isinstance(matrix, dict) else None
    sources = contract.get("source_artifacts") if isinstance(contract, dict) else None
    if not isinstance(sources, list):
        return {}
    result: dict[str, str] = {}
    expected_roots = {"requirement": "requirements/", "decision": "planning/decisions/"}
    for source in sources:
        if not isinstance(source, dict):
            continue
        source_type = source.get("source_type")
        relative = source.get("canonical_path")
        artifact_id = source.get("artifact_id")
        expected_hash = source.get("content_hash")
        if source_type not in expected_roots or not isinstance(relative, str) or not relative.startswith(expected_roots[source_type]):
            continue
        path = safe_file(root, relative)
        if path is None or not isinstance(artifact_id, str) or not isinstance(expected_hash, str):
            continue
        try:
            raw = path.read_bytes()
            value = load_yaml(raw.decode("utf-8-sig"))
        except (OSError, UnicodeError, yaml.YAMLError):
            continue
        if not isinstance(value, dict) or value.get("ID") != artifact_id or schema_errors(relative, value):
            continue
        digest = "sha256:" + hashlib.sha256(raw).hexdigest()
        normalized_expected = expected_hash if expected_hash.startswith("sha256:") else "sha256:" + expected_hash
        if digest == normalized_expected:
            result[relative] = digest.removeprefix("sha256:")
    return result


def resolve_parity_status(
    report: dict[str, Any],
    *,
    expected_identity: dict[str, Any] | None = None,
    target_freshness: str = "NOT_OBSERVABLE",
    validated_capture_sides: dict[str, str] | None = None,
    validated_source_hashes: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Resolve one parity record without scanning or mutating the project."""
    blockers: list[dict[str, str]] = []
    dimensions: dict[str, str] = {}
    matrix: dict[str, str] = {}
    validated_contract_sources: list[dict[str, str]] = []
    reported = report.get("overall_result") if isinstance(report, dict) else None
    evidence_class = report.get("evidence_class") if isinstance(report, dict) else None
    identity = report.get("comparison_identity") if isinstance(report, dict) else None
    valid_aggregates = {"PASS", "FAIL", "PARTIAL", "NOT_VERIFIED", "STALE", "FIXTURE_BLOCKED"}
    normalized_evidence_class = evidence_class if evidence_class in {"SMOKE", "REFERENCE_VS_MODEL", "LIVE_PARITY"} else "NOT_OBSERVABLE"

    def finish(state: str, result: str | None, code: str | None = None, reason: str | None = None) -> dict[str, Any]:
        final_blockers = list(blockers)
        if code:
            final_blockers.append({"code": code, "reason": reason or code})
        comparison_identity_status = identity.get("status") if isinstance(identity, dict) else None
        dimension_evidence = {}
        matrix_evidence = {}
        matrix_sources = {}
        matrix_capture_ids = {}
        if isinstance(report, dict):
            raw_dimensions = report.get("dimensions") if isinstance(report.get("dimensions"), dict) else {}
            for name in PARITY_DIMENSIONS:
                dimension = raw_dimensions.get(name) if isinstance(raw_dimensions.get(name), dict) else {}
                items = dimension.get("evidence") if isinstance(dimension.get("evidence"), list) else []
                dimension_evidence[name] = [
                    {key: item[key] for key in ("type", "passed", "capture_id") if key in item}
                    for item in items if isinstance(item, dict)
                ]
            raw_matrix = report.get("evidence_matrix") if isinstance(report.get("evidence_matrix"), dict) else {}
            for name in PARITY_EVIDENCE_MATRIX:
                entry = raw_matrix.get(name) if isinstance(raw_matrix.get(name), dict) else {}
                raw_evidence = entry.get("evidence", []) if isinstance(entry.get("evidence"), list) else []
                matrix_evidence[name] = [
                    {key: item[key] for key in ("type", "passed", "path", "capture_id", "description") if key in item}
                    for item in raw_evidence if isinstance(item, dict)
                ]
                raw_sources = entry.get("source_artifacts", []) if isinstance(entry.get("source_artifacts"), list) else []
                matrix_sources[name] = [
                    {key: source[key] for key in ("source_type", "canonical_path", "artifact_id", "content_hash") if isinstance(source.get(key), str)}
                    for source in raw_sources if isinstance(source, dict)
                ]
                raw_capture_ids = entry.get("capture_ids", []) if isinstance(entry.get("capture_ids"), list) else []
                matrix_capture_ids[name] = [capture_id for capture_id in raw_capture_ids if isinstance(capture_id, str)]
        return {
            "resolver": "build_project_status.resolve_parity_status/v1",
            "status": state,
            "evidence_class": normalized_evidence_class,
            "reported_overall_result": reported if reported in valid_aggregates else None,
            "computed_overall_result": result,
            "claim_matches": reported == result if result is not None and reported in valid_aggregates else False,
            "promotion_allowed": state == "RESOLVED" and result == "PASS",
            "comparison_identity_status": comparison_identity_status if comparison_identity_status in {"BOUND", "REFERENCE_DRIFT", "INCOMPLETE"} else "NOT_OBSERVABLE",
            "target_freshness": target_freshness if target_freshness in {"CURRENT", "STALE"} else "NOT_OBSERVABLE",
            "dimension_results": dimensions,
            "evidence_matrix_results": matrix,
            "evidence_provenance": {
                "dimension_evidence": dimension_evidence,
                "matrix_evidence": matrix_evidence,
                "matrix_source_artifacts": matrix_sources,
                "matrix_capture_ids": matrix_capture_ids,
                "validated_contract_sources": validated_contract_sources,
                "contract_source_validation": "VALIDATED" if validated_contract_sources else "NOT_OBSERVABLE",
            },
            "blockers": final_blockers,
        }

    if not isinstance(report, dict):
        return finish("UNKNOWN", "NOT_VERIFIED", "PARITY_RECORD_INVALID", "Parity record is not an object.")
    if evidence_class not in {"SMOKE", "REFERENCE_VS_MODEL", "LIVE_PARITY"}:
        return finish("NOT_OBSERVABLE", "NOT_VERIFIED", "EVIDENCE_CLASS_NOT_OBSERVED", "A recognized evidence_class is required.")
    if evidence_class != "LIVE_PARITY":
        return finish("BLOCKED", "NOT_VERIFIED", "EVIDENCE_CLASS_NOT_LIVE_PARITY",
                      f"{evidence_class} evidence cannot establish complete live parity.")
    if report.get("evidence_level") != "browser":
        return finish("BLOCKED", "NOT_VERIFIED", "LIVE_BROWSER_EVIDENCE_REQUIRED",
                      "LIVE_PARITY requires browser-level runtime evidence.")

    if not isinstance(identity, dict):
        return finish("NOT_OBSERVABLE", "NOT_VERIFIED", "COMPARISON_IDENTITY_NOT_OBSERVED",
                      "Comparison identity is missing.")
    if identity.get("status") == "REFERENCE_DRIFT":
        return finish("STALE", "STALE", "REFERENCE_DRIFT", "Evidence is bound to a different target identity.")
    if identity.get("status") != "BOUND":
        return finish("BLOCKED", "NOT_VERIFIED", "COMPARISON_IDENTITY_INCOMPLETE",
                      "Comparison identity is not BOUND.")
    if not isinstance(expected_identity, dict):
        return finish("NOT_OBSERVABLE", "NOT_VERIFIED", "CURRENT_IDENTITY_NOT_OBSERVED",
                      "The current active-target identity was not supplied to the resolver.")
    if identity != expected_identity:
        return finish("STALE", "STALE", "COMPARISON_IDENTITY_MISMATCH",
                      "The report identity differs from the current active-target identity.")
    if target_freshness == "STALE":
        return finish("STALE", "STALE", "TARGET_EVIDENCE_STALE", "The active target changed after verification.")
    if target_freshness != "CURRENT":
        return finish("NOT_OBSERVABLE", "NOT_VERIFIED", "TARGET_FRESHNESS_NOT_OBSERVED",
                      "Current-target freshness was not established.")

    verified_at = _parity_date(report.get("verified_at"))
    target_changed_at = _parity_date(report.get("target_changed_at"))
    if verified_at is None:
        return finish("NOT_OBSERVABLE", "NOT_VERIFIED", "VERIFICATION_DATE_NOT_OBSERVED",
                      "A valid verified_at date is required.")
    if target_changed_at and target_changed_at > verified_at:
        return finish("STALE", "STALE", "TARGET_CHANGED_AFTER_VERIFICATION",
                      "The target changed after this verification was recorded.")

    raw_dimensions = report.get("dimensions")
    if not isinstance(raw_dimensions, dict):
        return finish("BLOCKED", "NOT_VERIFIED", "DIMENSIONS_MISSING", "Canonical parity dimensions are missing.")
    effective_results: list[str] = []
    insufficient_evidence = False
    unknown_status = False
    visual_comparison_conflict = False
    for name in PARITY_DIMENSIONS:
        dimension = raw_dimensions.get(name)
        if not isinstance(dimension, dict):
            dimensions[name] = "NOT_VERIFIED"
            effective_results.append("NOT_VERIFIED")
            blockers.append({"code": "DIMENSION_MISSING", "reason": f"Required dimension {name} is missing."})
            insufficient_evidence = True
            continue
        required = dimension.get("required", True)
        if not isinstance(required, bool):
            dimensions[name] = "UNKNOWN"
            unknown_status = True
            blockers.append({"code": "DIMENSION_REQUIRED_UNKNOWN", "reason": f"Requiredness for {name} is not boolean."})
            continue
        status = dimension.get("result")
        allowed = {"PASS", "FAIL", "PARTIAL", "NOT_VERIFIED", "CONFLICT", "NOT_APPLICABLE", "LEGACY_EVIDENCE", "STALE", "FIXTURE_BLOCKED"}
        if status not in allowed:
            status = "UNKNOWN"
            unknown_status = True
            blockers.append({"code": "DIMENSION_STATUS_UNKNOWN", "reason": f"Status for {name} is missing or unrecognized."})
        evidence = dimension.get("evidence") if isinstance(dimension.get("evidence"), list) else []
        if required and status in {"PASS", "FAIL", "PARTIAL", "CONFLICT"}:
            evidence_items = [item for item in evidence if isinstance(item, dict)]
            proof_passed = _has_proof_groups(evidence_items, DIMENSION_PROOF_GROUPS[name])
            proof_failed = _has_proof_groups(evidence_items, DIMENSION_PROOF_GROUPS[name], False)
            if status == "PASS" and not proof_passed:
                status = "NOT_VERIFIED"
                insufficient_evidence = True
                blockers.append({"code": "DIMENSION_EVIDENCE_INSUFFICIENT", "reason": f"Dimension {name} claims PASS without the evidence types required by ui-parity.md."})
            elif status == "FAIL" and not proof_failed and not dimension.get("deviations"):
                status = "NOT_VERIFIED"
                insufficient_evidence = True
                blockers.append({"code": "FAIL_EVIDENCE_INSUFFICIENT", "reason": f"Dimension {name} claims FAIL without a failed evidence item or deviation."})
            elif status == "PARTIAL" and (not proof_passed or (not proof_failed and not dimension.get("deviations"))):
                status = "NOT_VERIFIED"
                insufficient_evidence = True
                blockers.append({"code": "PARTIAL_EVIDENCE_INSUFFICIENT", "reason": f"Dimension {name} PARTIAL requires both passing and failing evidence or a deviation."})
            elif status == "CONFLICT" and not proof_failed and not dimension.get("deviations"):
                status = "NOT_VERIFIED"
                insufficient_evidence = True
                blockers.append({"code": "PARTIAL_EVIDENCE_INSUFFICIENT", "reason": f"Dimension {name} lacks evidence or deviations."})
        if status == "NOT_APPLICABLE" and not (isinstance(dimension.get("not_applicable_rationale"), str) and dimension["not_applicable_rationale"].strip()):
            status = "NOT_VERIFIED"
            insufficient_evidence = True
            blockers.append({"code": "NOT_APPLICABLE_RATIONALE_MISSING", "reason": f"Dimension {name} lacks a NOT_APPLICABLE rationale."})
        if status == "LEGACY_EVIDENCE" and not (isinstance(dimension.get("legacy_provenance"), str) and dimension["legacy_provenance"].strip()):
            status = "NOT_VERIFIED"
            insufficient_evidence = True
            blockers.append({"code": "LEGACY_PROVENANCE_MISSING", "reason": f"Dimension {name} lacks legacy provenance."})
        dimensions[name] = status
        if required:
            effective_results.append(status)

    raw_matrix = report.get("evidence_matrix")
    if not isinstance(raw_matrix, dict):
        for name in PARITY_EVIDENCE_MATRIX:
            matrix[name] = "NOT_VERIFIED"
            effective_results.append("NOT_VERIFIED")
        insufficient_evidence = True
        blockers.append({"code": "EVIDENCE_MATRIX_MISSING", "reason": "The six-dimension evidence matrix is required."})
    else:
        for name in PARITY_EVIDENCE_MATRIX:
            entry = raw_matrix.get(name)
            if not isinstance(entry, dict):
                matrix[name] = "NOT_VERIFIED"
                effective_results.append("NOT_VERIFIED")
                insufficient_evidence = True
                blockers.append({"code": "EVIDENCE_MATRIX_DIMENSION_MISSING", "reason": f"Evidence matrix dimension {name} is missing."})
                continue
            required = entry.get("required", True)
            status = entry.get("status")
            if not isinstance(required, bool) or status not in {"PASS", "FAIL", "PARTIAL", "NOT_VERIFIED", "CONFLICT", "NOT_APPLICABLE"}:
                matrix[name] = "UNKNOWN"
                unknown_status = True
                blockers.append({"code": "EVIDENCE_MATRIX_STATUS_UNKNOWN", "reason": f"Evidence matrix status/requiredness for {name} is invalid."})
                continue
            if status == "NOT_APPLICABLE":
                note = entry.get("note")
                if required or not isinstance(note, str) or not note.strip():
                    matrix[name] = "NOT_VERIFIED"
                    effective_results.append("NOT_VERIFIED")
                    insufficient_evidence = True
                    blockers.append({"code": "EVIDENCE_MATRIX_NA_UNJUSTIFIED", "reason": f"Evidence matrix dimension {name} is required or lacks a not-applicable rationale."})
                else:
                    matrix[name] = "NOT_APPLICABLE"
                continue
            if name == "visual_whole_screen_parity" and required and status in {"PASS", "FAIL", "PARTIAL", "CONFLICT"}:
                comparison_state = _whole_screen_comparison_state(
                    report, entry,
                    validated_capture_sides if isinstance(validated_capture_sides, dict) else {},
                    status,
                )
                if comparison_state == "CONFLICT":
                    status = "CONFLICT"
                    visual_comparison_conflict = True
                    blockers.append({
                        "code": "VISUAL_COMPARISON_RESULT_MISMATCH",
                        "reason": "Whole-screen comparison result conflicts with visual_whole_screen_parity status.",
                    })
                elif comparison_state == "UNKNOWN":
                    status = "UNKNOWN"
                    unknown_status = True
                    blockers.append({
                        "code": "VISUAL_COMPARISON_RESULT_UNKNOWN",
                        "reason": "Whole-screen comparison result is unrecognized.",
                    })
                elif comparison_state != "VALID":
                    status = "NOT_VERIFIED"
                    insufficient_evidence = True
                    blockers.append({
                        "code": "WHOLE_SCREEN_COMPARISON_NOT_OBSERVED",
                        "reason": "Whole-screen status requires a matching comparison result, summary, and validated reviewed captures from both sides.",
                    })
            if name == "contract_parity" and required and status == "PASS":
                source_artifacts = entry.get("source_artifacts")
                source_hashes = validated_source_hashes if isinstance(validated_source_hashes, dict) else {}
                validated_contract_sources = []
                if isinstance(source_artifacts, list):
                    for source in source_artifacts:
                        if not isinstance(source, dict) or source.get("source_type") not in {"requirement", "decision"}:
                            continue
                        path = source.get("canonical_path")
                        artifact_id = source.get("artifact_id")
                        declared_hash = source.get("content_hash")
                        actual_hash = source_hashes.get(path) if isinstance(path, str) else None
                        if not all(isinstance(value, str) and value.strip() for value in (path, artifact_id, declared_hash, actual_hash)):
                            continue
                        normalized_declared = declared_hash if declared_hash.startswith("sha256:") else "sha256:" + declared_hash
                        normalized_actual = actual_hash if actual_hash.startswith("sha256:") else "sha256:" + actual_hash
                        if normalized_declared == normalized_actual and re.fullmatch(r"sha256:[a-f0-9]{64}", normalized_declared):
                            validated_contract_sources.append({
                                "source_type": source["source_type"],
                                "canonical_path": path,
                                "artifact_id": artifact_id,
                                "content_hash": normalized_declared,
                            })
                if not validated_contract_sources:
                    status = "NOT_VERIFIED"
                    insufficient_evidence = True
                    blockers.append({"code": "CONTRACT_SOURCE_EVIDENCE_INSUFFICIENT", "reason": "Contract parity PASS requires at least one requirement/decision reference whose content hash was validated for this resolver run."})
            if required and status == "PASS":
                matrix_evidence = entry.get("evidence") if isinstance(entry.get("evidence"), list) else []
                proof = [item for item in matrix_evidence if isinstance(item, dict)]
                sufficient = _has_proof_groups(proof, MATRIX_PROOF_GROUPS[name], True)
                if not sufficient:
                    status = "NOT_VERIFIED"
                    insufficient_evidence = True
                    blockers.append({"code": "MATRIX_EVIDENCE_INSUFFICIENT", "reason": f"Evidence matrix dimension {name} lacks sufficient linked evidence."})
            matrix[name] = status
            if required:
                effective_results.append(status)

    if "FAIL" in effective_results:
        return finish("RESOLVED", "FAIL")
    if visual_comparison_conflict:
        return finish("AMBIGUOUS", None, "VISUAL_COMPARISON_RESULT_MISMATCH",
                      "Whole-screen comparison evidence and its matrix status disagree.")
    if unknown_status:
        return finish("UNKNOWN", "NOT_VERIFIED")
    if insufficient_evidence:
        return finish("BLOCKED", "NOT_VERIFIED")

    result_set = set(effective_results)
    if "FAIL" in result_set:
        return finish("RESOLVED", "FAIL")
    unresolved = result_set & {"STALE", "FIXTURE_BLOCKED"}
    if unresolved and len(result_set - {"PASS", "NOT_APPLICABLE", "LEGACY_EVIDENCE"}) > 1:
        return finish("AMBIGUOUS", None, "AGGREGATE_PRECEDENCE_UNRESOLVED",
                      "Existing policy does not define precedence for this combination of blockers.")
    if unresolved:
        return finish("RESOLVED", next(iter(unresolved)))
    if "NOT_VERIFIED" in result_set:
        return finish("RESOLVED", "NOT_VERIFIED")
    if result_set & {"PARTIAL", "CONFLICT"}:
        return finish("RESOLVED", "PARTIAL")
    return finish("RESOLVED", "PASS")


def add_gap(gaps: list[dict[str, str | None]], code: str, source: str | None, description: str) -> None:
    gap = {"code": code, "source": source, "description": description}
    if gap not in gaps:
        gaps.append(gap)


def safe_path(root: Path, path: Path) -> bool:
    try:
        current = root
        for part in path.relative_to(root).parts:
            current = current / part
            if current.is_symlink():
                return False
        path.resolve().relative_to(root)
    except (OSError, ValueError):
        return False
    return True


def read_yaml_file(
    root: Path,
    relative_path: str,
    hashes: dict[str, str],
    gaps: list[dict[str, str | None]],
    parsed_documents: dict[str, dict[str, Any]] | None = None,
) -> tuple[Any, str]:
    path = root / relative_path
    if not path.exists():
        hashes[f"!missing:{relative_path}"] = "missing"
        if parsed_documents is not None:
            parsed_documents[relative_path] = {"state": "missing", "raw": None, "value": None}
        return None, "missing"
    if not safe_path(root, path) or not path.is_file():
        hashes[f"!invalid:{relative_path}"] = "invalid"
        if parsed_documents is not None:
            parsed_documents[relative_path] = {"state": "invalid", "raw": None, "value": None}
        add_gap(gaps, "SOURCE_PATH_INVALID", relative_path, "Canonical source is not a regular file inside the project root.")
        return None, "invalid"
    try:
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        hashes[relative_path] = digest
        value = load_yaml(raw.decode("utf-8-sig"))
    except yaml.YAMLError as exc:
        if parsed_documents is not None:
            parsed_documents[relative_path] = {"state": "invalid", "raw": raw, "value": None, "digest": digest}
        add_gap(gaps, "SOURCE_PARSE_FAILED", relative_path, "Canonical source could not be read as UTF-8 YAML.")
        causes = {
            "mapping values are not allowed here": "MAPPING_VALUE_NOT_ALLOWED",
            "duplicate mapping key": "DUPLICATE_MAPPING_KEY",
            "expected <block end>, but found '<block mapping start>'": "INVALID_BLOCK_INDENTATION",
            "could not find expected ':'": "MISSING_MAPPING_SEPARATOR",
        }
        gaps[-1]["parser_cause"] = causes.get(getattr(exc, "problem", ""), type(exc).__name__)
        mark = getattr(exc, "problem_mark", None)
        if mark is not None:
            gaps[-1].update({"line": mark.line + 1, "column": mark.column + 1})
        return None, "invalid"
    except (OSError, UnicodeError):
        if parsed_documents is not None:
            parsed_documents[relative_path] = {"state": "invalid", "raw": None, "value": None}
        add_gap(gaps, "SOURCE_PARSE_FAILED", relative_path, "Canonical source could not be read as UTF-8 YAML.")
        return None, "invalid"
    if not isinstance(value, dict):
        if parsed_documents is not None:
            parsed_documents[relative_path] = {"state": "invalid", "raw": raw, "value": None, "digest": digest}
        add_gap(gaps, "SOURCE_SHAPE_INVALID", relative_path, "Canonical source must contain a YAML object.")
        return None, "invalid"
    if parsed_documents is not None:
        parsed_documents[relative_path] = {"state": "available", "raw": raw, "value": value, "digest": digest}
    return value, "available"


def read_collection(
    root: Path,
    directory: str,
    pattern: str,
    id_field: str,
    hashes: dict[str, str],
    gaps: list[dict[str, str | None]],
    parsed_documents: dict[str, dict[str, Any]] | None = None,
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
        value, state = read_yaml_file(root, relative, hashes, gaps, parsed_documents)
        if state != "available" or not isinstance(value, dict):
            invalid += 1
            continue
        if id_field == "page_id" and is_standalone_interaction_artifact(relative):
            continue
        value = projected_for_validation(relative, value)
        if id_field:
            expected_id = path.parent.name if path.name == "revision.yaml" else path.stem
            if relative.startswith("planning/ui-inventory/"):
                if not isinstance(value.get(id_field), str) or not re.fullmatch(r"PAGE-[A-Z0-9_-]+", value[id_field]):
                    add_gap(gaps, "ARTIFACT_ID_MISMATCH", relative, "Page must declare its stable page_id.")
                    invalid += 1
                    continue
                if value[id_field] != expected_id:
                    add_gap(gaps, "LEGACY_FILENAME", relative, "Descriptive Page filename is accepted; page_id remains authoritative.")
            else:
                if not identity_matches(relative, value.get(id_field), expected_id):
                    add_gap(gaps, "ARTIFACT_ID_MISMATCH", relative, f"{id_field} does not match the canonical filename or revision directory.")
                    invalid += 1
                    continue
                if value.get(id_field) != expected_id:
                    if schema_errors(relative, value):
                        add_gap(gaps, "SOURCE_SHAPE_INVALID", relative, "Legacy-named artifact must satisfy its canonical schema.")
                        invalid += 1
                        continue
                    add_gap(gaps, "LEGACY_FILENAME", relative, "Documented descriptive Test Contract filename accepted.")
        records.append(value)
        relative_paths.append(relative)

    if id_field:
        duplicate_ids = {record[id_field] for record in records if sum(other[id_field] == record[id_field] for other in records) > 1}
        if duplicate_ids:
            retained = []
            for record, relative in zip(records, relative_paths):
                if record[id_field] in duplicate_ids:
                    add_gap(gaps, "DUPLICATE_ID", relative, "Canonical artifact identity is duplicated.")
                    invalid += 1
                else:
                    retained.append((record, relative))
            records = [record for record, _ in retained]
            relative_paths = [relative for _, relative in retained]

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


def progress_projection(records: list[dict[str, Any]], state: str) -> dict[str, Any]:
    is_available = state in ("available", "partial")
    return {
        "availability": state if state in ("available", "partial", "ambiguous") else "unavailable",
        "total": len(records) if is_available else None,
        "status_counts": status_counts(records, "status", TASK_STATUSES, is_available),
    }


def delivery_projection(
    task_state: str,
    tasks: list[dict[str, Any]],
    waves: list[dict[str, Any]],
    checklist_paths: list[str],
    gaps: list[dict[str, str | None]],
) -> tuple[list[dict[str, Any]], dict[str, Any], dict[str, Any]]:
    wave_ids = {wave["wave_id"] for wave in waves}
    wave_tasks: dict[str, list[dict[str, Any]]] = {wave_id: [] for wave_id in wave_ids}
    workpackage_tasks: dict[tuple[str | None, str], list[dict[str, Any]]] = {}
    readable = task_state in ("available", "partial")
    unmapped_workpackage = 0 if readable else None
    unmapped_wave = 0 if readable else None

    if readable:
        for task in tasks:
            wave_id = task.get("wave_id")
            if isinstance(wave_id, str) and wave_id in wave_tasks:
                wave_tasks[wave_id].append(task)
            else:
                unmapped_wave = int(unmapped_wave or 0) + 1
            workpackage_id = task.get("workpackage_id")
            if isinstance(workpackage_id, str) and workpackage_id.strip():
                package_key = (wave_id if isinstance(wave_id, str) and wave_id in wave_ids else None, workpackage_id)
                workpackage_tasks.setdefault(package_key, []).append(task)
            else:
                unmapped_workpackage = int(unmapped_workpackage or 0) + 1

    if unmapped_wave:
        add_gap(gaps, "TASK_WAVE_MAPPING_PARTIAL", "planning/tasks", f"{unmapped_wave} canonical task(s) have no explicit valid wave_id.")
    if unmapped_workpackage:
        add_gap(gaps, "WORKPACKAGE_MAPPING_PARTIAL", "planning/tasks", f"{unmapped_workpackage} canonical task(s) have no explicit workpackage_id.")

    updated_waves: list[dict[str, Any]] = []
    checklist_total = 0 if readable else None
    checklist_done = 0 if readable else None
    checklist_source: str | None = None
    checklists_by_wave = {
        Path(path).name.split("-", 1)[0]: path
        for path in checklist_paths
    }
    for wave in waves:
        wave_id = wave["wave_id"]
        assigned = wave_tasks.get(wave_id, [])
        checklist_path = checklists_by_wave.get(wave_id)
        checklist_tasks = [
            task for task in assigned
            if isinstance(task.get("migrated_from"), str)
            and task["migrated_from"].replace("\\", "/") == checklist_path
        ] if checklist_path else []
        if checklist_path and readable and checklist_tasks:
            checklist_state = task_state
            checklist_count: int | None = len(checklist_tasks)
            checklist_done_count: int | None = sum(1 for task in checklist_tasks if task.get("status") == "done")
            checklist_source = checklist_path
            checklist_total = int(checklist_total or 0) + checklist_count
            checklist_done = int(checklist_done or 0) + checklist_done_count
        else:
            checklist_state = "unknown" if checklist_path else "unavailable"
            checklist_count = None
            checklist_done_count = None
        requirement_ids = sorted({
            requirement_id
            for task in assigned
            for requirement_id in (task.get("req") if isinstance(task.get("req"), list) else [])
            if isinstance(requirement_id, str)
        })
        updated_waves.append({
            **wave,
            "task_progress": progress_projection(assigned, task_state),
            "checklist_progress": {
                "availability": checklist_state,
                "total": checklist_count,
                "done": checklist_done_count,
                "source": checklist_path if checklist_state in ("available", "partial") else None,
            },
            "requirement_ids": requirement_ids,
            "task_ids": sorted(task["ID"] for task in assigned if isinstance(task.get("ID"), str)),
        })

    packages = []
    for (wave_id, workpackage_id), package_tasks in sorted(workpackage_tasks.items(), key=lambda item: (item[0][0] or "", item[0][1])):
        packages.append({
            "workpackage_id": workpackage_id,
            "wave_id": wave_id,
            "task_progress": progress_projection(package_tasks, task_state),
            "requirement_ids": sorted({
                requirement_id
                for task in package_tasks
                for requirement_id in (task.get("req") if isinstance(task.get("req"), list) else [])
                if isinstance(requirement_id, str)
            }),
            "task_ids": sorted(task["ID"] for task in package_tasks if isinstance(task.get("ID"), str)),
        })
    package_availability = task_state if readable else "unavailable"
    if readable and (unmapped_workpackage or unmapped_wave):
        package_availability = "partial" if packages else "unknown"
    if readable and not packages:
        package_availability = "unavailable"

    if not readable:
        checklist_status = "unavailable"
    elif checklist_total:
        checklist_status = task_state
    elif checklist_paths:
        checklist_status = "unknown"
    else:
        checklist_status = "unavailable"
    checklist_summary = {
        "availability": checklist_status,
        "total": checklist_total if checklist_status in ("available", "partial") else None,
        "done": checklist_done if checklist_status in ("available", "partial") else None,
        "source": checklist_source if checklist_status in ("available", "partial") else None,
    }
    return updated_waves, checklist_summary, {
        "availability": package_availability,
        "items": packages,
        "unmapped_task_count": unmapped_workpackage,
    }


def canonical_reference(
    root: Path,
    supplied_path: Any,
    allowed_roots: tuple[str, ...],
    hashes: dict[str, str] | None = None,
) -> tuple[str | None, str | None, str]:
    """Validate a canonical repo-relative path and hash its file if present."""
    if not isinstance(supplied_path, str) or not supplied_path.strip():
        return None, None, "unknown"
    normalized = supplied_path.replace("\\", "/")
    candidate = PurePosixPath(normalized)
    if (
        candidate.is_absolute()
        or not candidate.parts
        or any(part in ("", ".", "..") for part in normalized.split("/"))
        or ":" in candidate.parts[0]
        or "%" in normalized
        or candidate.as_posix() != normalized
    ):
        return None, None, "unknown"
    if not any(normalized.lower().startswith(prefix.lower()) for prefix in allowed_roots):
        return None, None, "unknown"
    path = root.joinpath(*candidate.parts)
    if not safe_path(root, path):
        return None, None, "unknown"
    if not path.exists() or not path.is_file():
        return normalized, None, "unknown"
    if hashes is not None and hashes.get(normalized):
        return normalized, f"sha256:{hashes[normalized]}", "available"
    try:
        content_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return normalized, None, "unknown"
    return normalized, f"sha256:{content_hash}", "available"


def _finding_authority_disposition(
    root: Path,
    disposition: Any,
    hashes: dict[str, str],
    parsed_documents: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    """Project a persisted disposition; never infer or replace its classification."""
    projected: dict[str, Any] = {
        "status": "NOT_OBSERVABLE",
        "consumable": False,
        "revision": None,
        "classification": None,
        "allowed_action": "RECONCILE",
        "prohibited_actions": [],
        "unresolved_decision": None,
        "evidence_fingerprint": None,
        "reconciled_at": None,
        "authoritative_sources": [],
        "evidence_refs": [],
    }
    if not isinstance(disposition, dict):
        return projected

    classification = disposition.get("classification")
    action = disposition.get("allowed_action")
    prohibited = disposition.get("prohibited_actions")
    sources = disposition.get("authoritative_sources")
    evidence_refs = disposition.get("evidence_refs")
    unresolved = disposition.get("unresolved_decision")
    projected.update({
        "revision": disposition.get("revision") if isinstance(disposition.get("revision"), int) else None,
        "classification": classification if classification in DISPOSITION_ACTIONS else None,
        "unresolved_decision": unresolved if isinstance(unresolved, str) else None,
        "evidence_fingerprint": disposition.get("evidence_fingerprint") if isinstance(disposition.get("evidence_fingerprint"), str) else None,
        "reconciled_at": disposition.get("reconciled_at") if isinstance(disposition.get("reconciled_at"), str) else None,
    })

    if (
        disposition.get("status") != "RECONCILED"
        or classification not in DISPOSITION_ACTIONS
        or action != DISPOSITION_ACTIONS.get(classification)
        or not isinstance(prohibited, list)
        or (classification in DISPOSITION_PROHIBITIONS and DISPOSITION_PROHIBITIONS[classification] not in prohibited)
        or (classification == "AUTHORITY_CONFLICT" and not (isinstance(unresolved, str) and unresolved.strip()))
        or not isinstance(sources, list) or not sources
        or not isinstance(evidence_refs, list) or not evidence_refs
    ):
        projected["status"] = "AMBIGUOUS"
        return projected

    roots_by_type = {
        "requirement": ("requirements/",),
        "decision": ("planning/decisions/",),
        "active_target": ("planning/target-mockups/",),
        "parity_report": ("planning/parity/",),
        "evidence_manifest": ("planning/evidence/manifests/",),
    }
    basis: dict[str, str] = {}
    projected_sources: list[dict[str, str]] = []
    projected_evidence: list[dict[str, str]] = []

    def validate_basis(items: list[Any], *, authoritative: bool) -> str:
        for item in items:
            if not isinstance(item, dict):
                return "AMBIGUOUS"
            source_type = item.get("source_type")
            supplied_path = item.get("canonical_path")
            if source_type not in roots_by_type or not isinstance(supplied_path, str):
                return "AMBIGUOUS"
            canonical_path_value, current_hash, path_state = canonical_reference(
                root, supplied_path, roots_by_type[source_type], hashes,
            )
            if path_state != "available" or canonical_path_value is None or current_hash is None:
                return "NOT_OBSERVABLE"
            declared_hash = item.get("content_hash")
            if not isinstance(declared_hash, str) or not re.fullmatch(r"sha256:[a-f0-9]{64}", declared_hash):
                return "AMBIGUOUS"
            if declared_hash != current_hash:
                return "STALE"
            if authoritative:
                artifact_id = item.get("artifact_id")
                document = parsed_documents.get(canonical_path_value)
                document_value = document.get("value") if isinstance(document, dict) else None
                id_field = "revision_id" if source_type == "active_target" else "ID"
                if (
                    not isinstance(artifact_id, str)
                    or not isinstance(document_value, dict)
                    or document_value.get(id_field) != artifact_id
                ):
                    return "STALE"
                projected_sources.append({
                    "source_type": source_type,
                    "canonical_path": canonical_path_value,
                    "artifact_id": artifact_id,
                    "content_hash": declared_hash,
                })
            else:
                projected_evidence.append({
                    "source_type": source_type,
                    "canonical_path": canonical_path_value,
                    "content_hash": declared_hash,
                })
            digest = current_hash.removeprefix(SHA256_PATTERN)
            prior_digest = basis.get(canonical_path_value)
            if prior_digest is not None and prior_digest != digest:
                return "AMBIGUOUS"
            basis[canonical_path_value] = digest
        return "RESOLVED"

    state = validate_basis(sources, authoritative=True)
    if state == "RESOLVED":
        state = validate_basis(evidence_refs, authoritative=False)
    projected["authoritative_sources"] = projected_sources
    projected["evidence_refs"] = projected_evidence
    if state != "RESOLVED":
        projected["status"] = state
        return projected

    manifest = "\n".join(f"{path}:{digest}" for path, digest in sorted(basis.items()))
    current_fingerprint = SHA256_PATTERN + hashlib.sha256(manifest.encode("utf-8")).hexdigest()
    if current_fingerprint != disposition.get("evidence_fingerprint"):
        projected["status"] = "AMBIGUOUS"
        return projected

    projected.update({
        "status": "RESOLVED",
        "consumable": True,
        "allowed_action": action,
        "prohibited_actions": sorted(set(prohibited)),
    })
    return projected


def _authority_source(source_type: str, canonical_path: str, hashes: dict[str, str]) -> dict[str, Any]:
    digest = hashes.get(canonical_path)
    return {
        "source_type": source_type,
        "canonical_path": canonical_path,
        "content_hash": f"sha256:{digest}" if digest else None,
    }


def _reference_identity(reference: dict[str, Any]) -> str:
    authority_sources = sorted({
        (source.get("source_type"), source.get("canonical_path"))
        for source in reference.get("authority_sources", [])
        if isinstance(source, dict)
    })
    identity = {
        "reference_type": reference.get("reference_type"),
        "mockup_name": reference.get("mockup_name"),
        "target_id": reference.get("target_id"),
        "revision_id": reference.get("revision_id"),
        "canonical_path": reference.get("canonical_path"),
        "bundle_hash": reference.get("bundle_hash"),
        "authority_sources": authority_sources,
    }
    encoded = json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return "REF-" + hashlib.sha256(encoded).hexdigest()[:20]


def build_active_targets(
    root: Path,
    revision_state: str,
    revisions: list[dict[str, Any]],
    revision_paths: list[str],
    page_state: str,
    pages: list[dict[str, Any]],
    page_paths: list[str],
    hashes: dict[str, str],
    gaps: list[dict[str, str | None]],
) -> tuple[str, list[dict[str, Any]], dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    """Resolve only explicit active revisions and UI-inventory target paths."""
    targets: list[dict[str, Any]] = []
    spa_by_name: dict[str, dict[str, Any]] = {}
    target_by_screen: dict[str, dict[str, Any]] = {}
    pages_by_bundle: dict[str, list[tuple[dict[str, Any], str]]] = {}
    for page, page_path in zip(pages, page_paths):
        bundle_name = page.get("mockup_name")
        if isinstance(bundle_name, str) and bundle_name:
            pages_by_bundle.setdefault(bundle_name, []).append((page, page_path))

    revisions_by_bundle: dict[str, list[tuple[dict[str, Any], str]]] = {}
    invalid_revision = revision_state == "partial"
    for revision, revision_path in zip(revisions, revision_paths):
        mockup_name = revision.get("mockup_name")
        if not isinstance(mockup_name, str) or not mockup_name:
            invalid_revision = True
            add_gap(gaps, "ACTIVE_TARGET_IDENTITY_INVALID", revision_path, "Revision is missing its canonical mockup_name.")
            continue
        revisions_by_bundle.setdefault(mockup_name, []).append((revision, revision_path))

    for mockup_name, bundle_revisions in sorted(revisions_by_bundle.items()):
        active = [(revision, path) for revision, path in bundle_revisions if revision.get("active_target") is True]
        authority_sources = [
            _authority_source("revision_manifest", path, hashes)
            for _, path in active
        ]
        if revision_state == "partial" or len(active) != 1:
            state = "ambiguous" if revision_state == "partial" or len(active) > 1 else "unknown"
            targets.append({
                "availability": state,
                "reference_type": "spa_bundle_entrypoint",
                "mockup_name": mockup_name,
                "target_id": None,
                "revision_id": None,
                "authoritative_state": "UNKNOWN",
                "canonical_path": None,
                "reference_root": None,
                "authority_sources": authority_sources,
                "source_fingerprint": None,
                "content_hash": None,
                "bundle_hash": None,
                "inventory_drift": {"state": "unknown", "mismatched_screen_ids": [], "unknown_screen_ids": []},
                "screen_ids": [],
                "section_ids": [],
            })
            code = "ACTIVE_TARGET_AMBIGUOUS" if state == "ambiguous" else "ACTIVE_TARGET_UNAVAILABLE"
            add_gap(gaps, code, "planning/target-mockups", f"Mockup bundle '{mockup_name}' does not have exactly one active revision.")
            continue

        revision, revision_path = active[0]
        revision_id = revision.get("revision_id")
        lifecycle_status = revision.get("lifecycle_status")
        refinement_status = revision.get("refinement_status")
        authority_valid = (
            isinstance(revision_id, str)
            and revision_id == PurePosixPath(revision_path).parent.name
            and lifecycle_status in ("SOURCE", "REFINED_TARGET")
            and refinement_status == "ACCEPTED"
        )
        entry_point = revision.get("entry_point", "index.html")
        if not isinstance(entry_point, str) or not entry_point:
            entry_point = ""
        normalized_entry = entry_point.replace("\\", "/")
        entry = PurePosixPath(normalized_entry)
        entry_valid = (
            bool(normalized_entry)
            and not entry.is_absolute()
            and ":" not in entry.parts[0]
            and all(part not in ("", ".", "..") for part in normalized_entry.split("/"))
            and entry.as_posix() == normalized_entry
            and "%" not in normalized_entry
        )
        derived_path = (PurePosixPath(revision_path).parent / entry).as_posix() if entry_valid else None
        canonical_path, content_hash, path_state = canonical_reference(
            root, derived_path, ("planning/target-mockups/",), hashes
        )
        reference_root = PurePosixPath(revision_path).parent.as_posix()
        reference_root_path = root.joinpath(*PurePosixPath(reference_root).parts)
        if not safe_path(root, reference_root_path) or not reference_root_path.is_dir():
            reference_root = None
        bundle_hash = revision.get("bundle_hash")
        if not isinstance(bundle_hash, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", bundle_hash):
            bundle_hash = None
        target_availability = "available" if authority_valid and path_state == "available" and reference_root and bundle_hash else "unknown"
        if not authority_valid:
            add_gap(gaps, "ACTIVE_TARGET_AUTHORITY_INVALID", revision_path, "Active revision status is inconsistent or lacks accepted authority.")
        if path_state != "available":
            add_gap(gaps, "ACTIVE_TARGET_REFERENCE_UNAVAILABLE", revision_path, "The canonical revision entry point is missing or unsafe to expose.")
        matched_pages = [
            page for page, _ in pages_by_bundle.get(mockup_name, [])
            if isinstance(page.get("page_id"), str) and page.get("target_revision") == revision_id
        ]
        screen_ids = sorted({page["page_id"] for page in matched_pages})
        page_bindings = sorted({
            (page["page_id"], page.get("page_name") if isinstance(page.get("page_name"), str) else None)
            for page in matched_pages
        }, key=lambda binding: binding[0])
        bundle_pages = pages_by_bundle.get(mockup_name, [])
        mismatched_screen_ids: list[str] = []
        unknown_screen_ids: list[str] = []
        for page, page_path in bundle_pages:
            page_id = page.get("page_id")
            page_revision = page.get("target_revision")
            page_bundle_hash = page.get("bundle_hash")
            if not isinstance(page_revision, str) or not page_revision:
                if isinstance(page_id, str):
                    unknown_screen_ids.append(page_id)
            elif page_revision != revision_id or (page_bundle_hash and page_bundle_hash != bundle_hash):
                if isinstance(page_id, str):
                    mismatched_screen_ids.append(page_id)
                add_gap(gaps, "ACTIVE_TARGET_INVENTORY_DRIFT", page_path, "UI inventory target revision or bundle hash differs from the canonical active revision.")
            elif not isinstance(page_bundle_hash, str) or not page_bundle_hash:
                if isinstance(page_id, str):
                    unknown_screen_ids.append(page_id)
        inventory_drift_state = (
            "mismatch" if mismatched_screen_ids else
            "unknown" if unknown_screen_ids or not bundle_pages or page_state != "available" else
            "consistent"
        )
        section_ids = sorted({
            section["id"]
            for page in matched_pages
            for section in page.get("sections", []) if isinstance(page.get("sections"), list)
            if isinstance(section, dict) and isinstance(section.get("id"), str)
        })
        reference = {
            "availability": target_availability,
            "reference_type": "spa_bundle_entrypoint",
            "mockup_name": mockup_name,
            "target_id": revision_id if isinstance(revision_id, str) else None,
            "revision_id": revision_id if isinstance(revision_id, str) else None,
            "authoritative_state": "ACTIVE_TARGET" if authority_valid else "UNKNOWN",
            "canonical_path": canonical_path,
            "reference_root": reference_root,
            "authority_sources": [_authority_source("revision_manifest", revision_path, hashes)],
            "source_fingerprint": bundle_hash,
            "content_hash": content_hash,
            "bundle_hash": bundle_hash,
            "inventory_drift": {
                "state": inventory_drift_state,
                "mismatched_screen_ids": sorted(set(mismatched_screen_ids)),
                "unknown_screen_ids": sorted(set(unknown_screen_ids)),
            },
            "screen_ids": screen_ids,
            "page_bindings": [
                {"page_id": page_id, "mendix_page_name": mendix_page_name}
                for page_id, mendix_page_name in page_bindings
            ],
            "section_ids": section_ids,
        }
        targets.append(reference)
        spa_by_name[mockup_name] = reference
        if bundle_hash:
            hashes[f"reference-bundle:{mockup_name}:{revision_id}"] = bundle_hash.removeprefix(SHA256_PATTERN)
        if canonical_path and content_hash:
            hashes[canonical_path] = content_hash.removeprefix(SHA256_PATTERN)
        for screen_id in screen_ids:
            target_by_screen[screen_id] = reference

    legacy_by_target: dict[str, dict[str, Any]] = {}
    for page, page_path in zip(pages, page_paths):
        if isinstance(page.get("mockup_name"), str) and page.get("mockup_name"):
            continue
        target_path = page.get("target_mockup") or page.get("source_mockup")
        if not isinstance(target_path, str) or not target_path:
            continue
        canonical_path, content_hash, path_state = canonical_reference(
            root,
            target_path,
            ("planning/target-mockups/", "input-resources/ui-ux/"),
            hashes,
        )
        if canonical_path is None:
            add_gap(gaps, "SINGLE_FILE_TARGET_PATH_INVALID", page_path, "UI inventory target is not a safe canonical project-relative mockup path.")
            reference_key = f"!unknown:{page_path}"
        else:
            reference_key = canonical_path
        reference = legacy_by_target.get(reference_key)
        if reference is None:
            reference = {
                "availability": path_state,
                "reference_type": "single_file_mockup" if canonical_path else "unknown",
                "mockup_name": None,
                "target_id": None,
                "revision_id": None,
                "authoritative_state": "ACTIVE_TARGET" if canonical_path else "UNKNOWN",
                "canonical_path": canonical_path,
                "reference_root": canonical_path,
                "authority_sources": [],
                "source_fingerprint": content_hash,
                "content_hash": content_hash,
                "bundle_hash": None,
                "inventory_drift": {"state": "consistent", "mismatched_screen_ids": [], "unknown_screen_ids": []},
                "screen_ids": [],
                "page_bindings": [],
                "section_ids": [],
            }
            legacy_by_target[reference_key] = reference
        elif reference["availability"] != "available" or path_state != "available":
            reference["availability"] = "unknown"
        page_id = page.get("page_id")
        if isinstance(page_id, str) and page_id not in reference["screen_ids"]:
            reference["screen_ids"].append(page_id)
            target_by_screen[page_id] = reference
        if isinstance(page_id, str):
            binding = {
                "page_id": page_id,
                "mendix_page_name": page.get("page_name") if isinstance(page.get("page_name"), str) else None,
            }
            if binding not in reference["page_bindings"]:
                reference["page_bindings"].append(binding)
        for section in page.get("sections", []) if isinstance(page.get("sections"), list) else []:
            if isinstance(section, dict) and isinstance(section.get("id"), str) and section["id"] not in reference["section_ids"]:
                reference["section_ids"].append(section["id"])
        reference["authority_sources"].append(_authority_source("ui_inventory", page_path, hashes))
        if canonical_path and content_hash:
            hashes[canonical_path] = content_hash.removeprefix(SHA256_PATTERN)

    for reference in legacy_by_target.values():
        reference["screen_ids"].sort()
        reference["page_bindings"].sort(key=lambda binding: binding["page_id"])
        reference["section_ids"].sort()
        reference["authority_sources"].sort(key=lambda source: source["canonical_path"])
        targets.append(reference)
        if reference["availability"] != "available":
            add_gap(gaps, "SINGLE_FILE_TARGET_UNAVAILABLE", reference["canonical_path"], "Explicit UI-inventory target path is missing or unavailable.")

    deduplicated: dict[str, dict[str, Any]] = {}
    for reference in targets:
        reference_id = _reference_identity(reference)
        reference["reference_id"] = reference_id
        existing = deduplicated.get(reference_id)
        if existing is None:
            deduplicated[reference_id] = reference
            continue
        if existing["availability"] != reference["availability"]:
            existing["availability"] = "ambiguous"
        existing["screen_ids"] = sorted(set(existing["screen_ids"]) | set(reference["screen_ids"]))
        bindings = {
            (item["page_id"], item["mendix_page_name"])
            for item in existing["page_bindings"] + reference["page_bindings"]
        }
        existing["page_bindings"] = [
            {"page_id": page_id, "mendix_page_name": mendix_page_name}
            for page_id, mendix_page_name in sorted(bindings, key=lambda binding: (binding[0], binding[1] or ""))
        ]
        existing["section_ids"] = sorted(set(existing["section_ids"]) | set(reference["section_ids"]))
    targets = list(deduplicated.values())
    targets.sort(key=lambda item: (item["mockup_name"] or "", item["canonical_path"] or "", item["revision_id"] or "", item["reference_id"]))
    if not targets:
        availability = "unknown"
    elif any(item["availability"] == "ambiguous" for item in targets):
        availability = "ambiguous"
    elif all(item["availability"] == "available" for item in targets) and page_state != "partial" and not invalid_revision:
        availability = "available"
    elif any(item["availability"] == "available" for item in targets):
        availability = "partial"
    else:
        availability = "unknown"
    return availability, targets, spa_by_name, target_by_screen


def build_source_references(
    root: Path,
    process_doc: dict[str, Any] | None,
    process_state: str,
    waves: list[dict[str, Any]],
    collections: list[tuple[str, list[dict[str, Any]], list[str]]],
    manifests: list[dict[str, Any]],
    manifest_paths: list[str],
    hashes: dict[str, str],
    gaps: list[dict[str, str | None]],
) -> tuple[str, list[dict[str, Any]]]:
    references: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str | None, str | None]] = set()

    def add(source_type: str, path_value: str, artifact_id: str | None = None, anchor: str | None = None) -> None:
        canonical_path, content_hash, availability = canonical_reference(
            root,
            path_value,
            ("planning/", "requirements/"),
            hashes,
        )
        if canonical_path is None:
            add_gap(gaps, "SOURCE_REFERENCE_PATH_INVALID", None, "A declared source reference is not a canonical project-relative path.")
            return
        key = (source_type, canonical_path, artifact_id, anchor)
        if key in seen:
            return
        seen.add(key)
        references.append({
            "source_type": source_type,
            "canonical_path": canonical_path,
            "artifact_id": artifact_id,
            "anchor": anchor,
            "availability": availability,
            "content_hash": content_hash,
        })
        if content_hash:
            hashes[canonical_path] = content_hash.removeprefix("sha256:")

    if process_state == "available" and isinstance(process_doc, dict):
        for wave in waves:
            add("wave_state", "planning/lifecycle/process-state.yaml", wave["wave_id"], f"waves.{wave['wave_id']}")

    for source_type, records, paths in collections:
        for record, path in zip(records, paths):
            artifact_id = record.get("ID")
            if artifact_id is None and source_type == "evidence_manifest":
                artifact_id = record.get("manifest_id")
            if artifact_id is None and source_type == "parity_report":
                artifact_id = record.get("scenario_id")
            add(source_type, path, artifact_id if isinstance(artifact_id, str) else None)

    checklists = root / "planning/checklists"
    if checklists.exists() and safe_path(root, checklists) and checklists.is_dir():
        for path in sorted(checklists.glob("W*-implementation-checklist.yaml"), key=lambda item: item.as_posix()):
            relative = path.relative_to(root).as_posix()
            wave_id = path.name.split("-", 1)[0]
            add("checklist", relative, wave_id, None)

    for manifest, manifest_path in zip(manifests, manifest_paths):
        for entry in manifest.get("entries", []) if isinstance(manifest.get("entries"), list) else []:
            if not isinstance(entry, dict):
                continue
            artifact_id = entry.get("entry_id")
            for group_name in ("target_evidence", "actual_evidence", "artifacts"):
                for artifact in entry.get(group_name, []) if isinstance(entry.get(group_name), list) else []:
                    if isinstance(artifact, dict) and isinstance(artifact.get("path"), str):
                        add("evidence_artifact", artifact["path"], artifact.get("artifact_id"), None)
            report_path = entry.get("parity_report_path")
            if isinstance(report_path, str):
                add("parity_report", report_path, artifact_id if isinstance(artifact_id, str) else None)

    references.sort(key=lambda item: (item["source_type"], item["canonical_path"], item["artifact_id"] or "", item["anchor"] or ""))
    if not references:
        return "unknown", []
    if all(reference["availability"] == "available" for reference in references):
        return "available", references
    return "partial", references


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

    def wave_order(item: tuple[Any, Any]) -> tuple[Any, ...]:
        identifier = str(item[0])
        match = re.fullmatch(r"(.*?)(\d+)", identifier)
        if match:
            return (0, match.group(1).casefold(), int(match.group(2)), identifier.casefold())
        return (1, identifier.casefold(), identifier)

    for wave_id, state in sorted(waves_data.items(), key=wave_order):
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
            "objective": None, "progress": None, "blockers": [], "checkpoint_commits": [], "terminal_guard_result": None,
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
    def text(value: Any, limit: int = 240) -> str | None:
        return value.strip()[:limit] if isinstance(value, str) and value.strip() else None

    blocker_details = [
        {"type": text(item.get("type"), 60), "description": text(item.get("description")),
         "blast_radius": text(item.get("blast_radius")), "work_that_can_continue": text(item.get("work_that_can_continue"))}
        for item in (blockers if isinstance(blockers, list) else []) if isinstance(item, dict)
    ][:10]
    checkpoints = mission_doc.get("checkpoint_commits")
    return {
        "availability": availability, "id": mission_id, "status": status,
        "blocker_count": blocker_count, "blocker_types": blocker_types,
        "objective": text(mission_doc.get("objective"), 400),
        "progress": {key: value for key, value in progress.items() if isinstance(value, str)} or None,
        "blockers": blocker_details,
        "checkpoint_commits": [str(item)[:64] for item in checkpoints][:10] if isinstance(checkpoints, list) else [],
        "terminal_guard_result": text(mission_doc.get("terminal_guard_result"), 120),
    }, active_wave


def visual_evidence_projection(root: Path, manifests: list[dict], manifest_paths: list[str],
                               targets: list[dict], hashes: dict, gaps: list,
                               screen_id_filter: str | None = None) -> list[dict]:
    runs = []
    valid = [(manifest, source) for manifest, source in zip(manifests, manifest_paths) if not schema_errors(source, manifest)]
    bindings: dict[str, set[str]] = {}
    for manifest, source in valid:
        for entry in manifest['entries']:
            for group in entry.get('capture_groups', []):
                bindings.setdefault(group['capture_id'], set()).add(json.dumps(group, sort_keys=True))
    for manifest, source in valid:
        for entry in manifest['entries']:
            identity = entry.get('comparison_identity', {})
            screen_id = entry.get('screen_id') if isinstance(entry.get('screen_id'), str) else "UNKNOWN"
            if screen_id_filter is not None and screen_id != screen_id_filter:
                continue
            report_path = entry.get('parity_report_path')
            if not isinstance(report_path, str) or not report_path.startswith('planning/parity/'):
                continue
            parity, state = read_yaml_file(root, report_path, hashes, gaps)
            parity_errors = schema_errors(report_path, parity) if state == 'available' and isinstance(parity, dict) else ["report unavailable"]
            if state != 'available' or not isinstance(parity, dict) or parity_errors:
                add_gap(gaps, 'PARITY_REPORT_INVALID', report_path, 'Linked parity report is unavailable or fails its canonical schema.')
                continue
            identity_is_bound = isinstance(identity, dict) and identity.get('status') == 'BOUND'
            identity_page_matches = identity_is_bound and identity.get('target_page') == screen_id
            if not identity_page_matches or parity.get('comparison_identity') != identity:
                resolver_report = dict(parity)
                resolver_identity = identity if isinstance(identity, dict) else {"status": "INCOMPLETE"}
                if identity_is_bound and not identity_page_matches:
                    resolver_identity = {**identity, "status": "INCOMPLETE"}
                if not identity_is_bound or not identity_page_matches:
                    resolver_report["comparison_identity"] = resolver_identity
                    expected_identity = None
                else:
                    expected_identity = identity
                resolution = resolve_parity_status(
                    resolver_report,
                    expected_identity=expected_identity,
                    target_freshness="NOT_OBSERVABLE",
                    validated_source_hashes=hashes,
                )
                add_gap(gaps, 'PARITY_IDENTITY_UNBOUND', report_path, 'Parity report has missing, conflicting, or unbound comparison identity; promotion is blocked.')
                runs.append({
                    'entry_id': entry.get('entry_id', 'UNKNOWN'), 'run_id': 'UNOBSERVED', 'screen_id': screen_id,
                    'manifest_path': source, 'reference_path': 'NOT_OBSERVABLE',
                    'reference_fingerprint': 'NOT_OBSERVABLE', 'revision': 'NOT_OBSERVABLE', 'historical': True,
                    'parity_result': resolution['computed_overall_result'] or 'NOT_VERIFIED',
                    'reported_parity_result': parity.get('overall_result'), 'parity_resolution': resolution,
                    'dimensions': {name: value.get('status', 'UNKNOWN') for name, value in parity.get('evidence_matrix', {}).items() if isinstance(value, dict)},
                    'captures': [],
                })
                continue
            reference = identity.get('canonical_mockup_path')
            if not isinstance(reference, str) or not reference.startswith(('planning/target-mockups/', 'input-resources/ui-ux/')) or Path(reference).suffix.lower() not in ('.html', '.htm') or not safe_file(root, reference):
                continue
            target = next((item for item in targets if entry['screen_id'] in item['screen_ids']), None)
            current = bool(target and target['availability'] == 'available' and reference == target['canonical_path']
                           and identity['revision'] == (target['revision_id'] or identity['revision'])
                           and identity['fingerprint'] == (target['bundle_hash'] or target['content_hash']))
            if not current:
                reference_file = safe_file(root, reference)
                bound = identity['fingerprint'] == 'sha256:' + hashlib.sha256(reference_file.read_bytes()).hexdigest()
                if '/_history/' in reference:
                    revision_root = reference.split('/_history/', 1)[0] + '/_history/' + identity['revision']
                    revision, revision_state = read_yaml_file(root, revision_root + '/revision.yaml', hashes, gaps)
                    bound = bool(reference.startswith(revision_root + '/') and revision_state == 'available'
                                 and not schema_errors(revision_root + '/revision.yaml', revision)
                                 and revision.get('revision_id') == identity['revision'] and revision.get('bundle_hash') == identity['fingerprint'])
                if not bound:
                    continue
            artifacts = [(side, artifact) for side, field in (('mockup', 'target_evidence'), ('application', 'actual_evidence'))
                         for artifact in entry.get(field, [])]
            captures = []
            seen = set()
            for group in entry.get('capture_groups', []):
                capture_id = group['capture_id']
                if len(bindings[capture_id]) != 1 or sum(item['capture_id'] == capture_id for item in entry['capture_groups']) != 1:
                    add_gap(gaps, 'CAPTURE_ID_CONFLICT', source, 'Capture ID has conflicting or duplicate canonical bindings.')
                    continue
                if capture_id in seen or group['comparison_identity'] != identity or group['target_screen'] != entry['screen_id'] or group['role'] not in identity['roles']:
                    continue
                seen.add(capture_id)
                matches = [artifact for side, artifact in artifacts if side == group['capture_source']
                           and artifact.get('source') == side and artifact.get('capture_id') == capture_id
                           and artifact['path'] == group['screenshot_path'] and artifact['type'] in ('screenshot', 'viewport_screenshot')]
                if len(matches) != 1:
                    continue
                artifact = matches[0]
                image_path = artifact['path']
                if not image_path.startswith('planning/evidence/screenshots/') or Path(image_path).suffix.lower() not in ('.png', '.jpg', '.jpeg', '.webp'):
                    continue
                image = safe_file(root, image_path)
                if image is None or image.stat().st_size > 32 * 1024 * 1024:
                    continue
                raw = image.read_bytes()
                if not (raw.startswith(b'\x89PNG\r\n\x1a\n') or raw.startswith(b'\xff\xd8\xff') or (raw.startswith(b'RIFF') and raw[8:12] == b'WEBP')):
                    continue
                if any(not snapshot['path'].startswith('planning/evidence/') or not safe_file(root, snapshot['path']) for snapshot in group['snapshots']):
                    continue
                hashes[image_path] = hashlib.sha256(raw).hexdigest()
                runtime_url = None
                try:
                    parsed = urlsplit(group['runtime_url'])
                    if parsed.scheme in ('http', 'https') and parsed.hostname:
                        host = f'[{parsed.hostname}]' if ':' in parsed.hostname else parsed.hostname
                        runtime_url = urlunsplit((parsed.scheme, host + (f':{parsed.port}' if parsed.port else ''), parsed.path, '', ''))
                except ValueError:
                    pass
                captures.append({
                    'capture_id': capture_id, 'side': group['capture_source'], 'role': group['role'],
                    'run_id': group['run_id'], 'captured_at': group['captured_at'], 'screenshot_path': image_path,
                    'runtime_url': runtime_url, 'cleanliness_state': group['cleanliness_state'],
                    'freshness': 'CURRENT_TARGET' if current else 'HISTORICAL_TARGET',
                    'evidence_status': artifact.get('lifecycle_stage', 'promoted'),
                })
            freshness = "NOT_OBSERVABLE" if target is None or target.get("availability") != "available" else ("CURRENT" if current else "STALE")
            capture_sides = {
                item["capture_id"]: item["side"]
                for item in captures
                if item["evidence_status"] == "promoted"
            }
            parity_resolution = resolve_parity_status(
                parity,
                expected_identity=identity,
                target_freshness=freshness,
                validated_capture_sides=capture_sides,
                validated_source_hashes=hashes,
            )
            run_ids = sorted({item['run_id'] for item in captures}) or ["UNOBSERVED"]
            if not captures:
                add_gap(gaps, "PARITY_EVIDENCE_UNOBSERVED", report_path,
                        "A linked parity report has no validated capture groups; aggregate remains NOT_VERIFIED.")
            for run_id in run_ids:
                run_captures = [item for item in captures if item['run_id'] == run_id]
                historical = not current or not run_captures or any(item['evidence_status'] != 'promoted' for item in run_captures)
                runs.append({
                    'entry_id': entry['entry_id'], 'run_id': run_id, 'screen_id': entry['screen_id'], 'manifest_path': source,
                    'reference_path': reference, 'reference_fingerprint': identity['fingerprint'],
                    'revision': identity['revision'], 'historical': historical,
                    'parity_result': parity_resolution['computed_overall_result'] or 'NOT_VERIFIED',
                    'reported_parity_result': parity.get('overall_result'),
                    'parity_resolution': parity_resolution,
                    'dimensions': {name: value['status'] for name, value in parity.get('evidence_matrix', {}).items()},
                    'captures': sorted(run_captures, key=lambda item: (0 if item['side'] == 'mockup' else 1, item['role'], item['capture_id'])),
                })
    return sorted(runs, key=lambda item: (item['historical'], item['screen_id'], item['entry_id'], item['run_id'], item['manifest_path']))


OBSERVATION_STATES = (
    "AVAILABLE", "EMPTY", "NOT_RECORDED", "NOT_LOADED", "LOADING", "STALE", "INVALID",
    "UNSUPPORTED", "NOT_OBSERVABLE", "NOT_APPLICABLE", "AMBIGUOUS", "PROJECTION_ERROR",
)
DIAGNOSTIC_GROUP_ORDER = ("project_attention", "projection_health", "framework_compat", "optional_metadata")


def _observed(availability: Any, *, missing: bool = False, count: int | None = None) -> str:
    """Map a v2 availability value plus source evidence to exactly one CS-3 observation state.

    Missing information is never reported as success: a missing source is NOT_RECORDED, an existing
    but unusable one INVALID, and only a readable zero-record collection is EMPTY.
    """
    if missing:
        return "NOT_RECORDED"
    if availability == "unavailable":
        return "INVALID"
    if availability == "ambiguous":
        return "AMBIGUOUS"
    if availability in ("available", "partial"):
        return "EMPTY" if availability == "available" and count == 0 else "AVAILABLE"
    return "NOT_OBSERVABLE"


def attach_observation_states(result: dict[str, Any], hashes: dict[str, str]) -> dict[str, str]:
    """Attach `observation_state` to each projected area (additive; v2 `availability` is kept)."""
    def directory_missing(directory: str) -> bool:
        return f"!missing-directory:{directory}" in hashes

    def file_missing(path: str) -> bool:
        return f"!missing:{path}" in hashes

    def size(area: dict[str, Any], key: str = "items") -> int | None:
        value = area.get(key)
        return len(value) if isinstance(value, list) else None

    project, delivery, verification = result["project"], result["delivery"], result["verification"]
    plans_total = sum(v for v in verification["plans"]["status_counts"].values() if isinstance(v, int))
    areas: list[tuple[str, dict[str, Any], str]] = [
        ("mission", result["mission"], _observed(result["mission"]["availability"], missing=file_missing("planning/mission/mission-state.yaml"))),
        ("project.active_targets", project["active_targets"], _observed(project["active_targets"]["availability"], missing=directory_missing("planning/target-mockups"), count=size(project["active_targets"]))),
        ("delivery.waves", delivery["waves"], _observed(delivery["waves"]["availability"], missing=file_missing("planning/lifecycle/process-state.yaml"), count=size(delivery["waves"]))),
        ("delivery.tasks", delivery["tasks"], _observed(delivery["tasks"]["availability"], missing=directory_missing("planning/tasks"), count=size(delivery["tasks"]))),
        ("requirements", result["requirements"], _observed(result["requirements"]["availability"], missing=directory_missing("requirements"), count=result["requirements"]["total"])),
        ("decisions", result["decisions"], _observed(result["decisions"]["availability"], missing=directory_missing("planning/decisions"), count=result["decisions"]["total"])),
        ("findings", result["findings"], _observed(result["findings"]["availability"], missing=directory_missing("planning/findings"), count=size(result["findings"]))),
        ("verification.test_contracts", verification["test_contracts"], _observed(verification["test_contracts"]["availability"], missing=directory_missing("planning/test-contracts"), count=size(verification["test_contracts"]))),
        ("verification.proof_points", verification["proof_points"], _observed(verification["proof_points"]["availability"], missing=directory_missing("planning/test-contracts"))),
        ("verification.plans", verification["plans"], _observed(verification["plans"]["availability"], missing=directory_missing("planning/verification-plans"), count=plans_total)),
        ("verification.evidence", verification["evidence"], _observed(verification["evidence"]["availability"], missing=directory_missing("planning/evidence/manifests"), count=size(verification["evidence"], "entries"))),
        ("context", result["context"], _observed(result["context"]["availability"], missing=file_missing("planning/lifecycle/context-epoch.yaml"))),
        ("source_references", result["source_references"], _observed(result["source_references"]["availability"], count=size(result["source_references"]))),
        # Structurally unconditional gaps: the framework cannot observe these today (not a project defect).
        ("capabilities", result["capabilities"], "NOT_OBSERVABLE"),
        ("sources", result["sources"], "NOT_OBSERVABLE"),
    ]
    runtime = result["runtime"]
    states: dict[str, str] = {}
    for name, area, state in areas:
        area["observation_state"] = state
        states[name] = state
    # Lifecycle: a readable process-state without an identifiable active Wave is "not recorded", not invalid.
    lifecycle = project["lifecycle"]
    waves_state = states["delivery.waves"]
    lifecycle["observation_state"] = (
        "NOT_RECORDED" if lifecycle["availability"] == "unavailable" and waves_state in ("AVAILABLE", "EMPTY")
        else _observed(lifecycle["availability"], missing=waves_state == "NOT_RECORDED")
    )
    states["project.lifecycle"] = lifecycle["observation_state"]
    runtime["observation_state"] = "NOT_RECORDED" if runtime["readiness_availability"] == "unavailable" else "AVAILABLE"
    runtime["operating_mode_observation_state"] = "NOT_OBSERVABLE"
    verification["evidence"]["model_freshness_observation_state"] = (
        "NOT_OBSERVABLE" if verification["evidence"]["model_freshness"] == "unknown" else "AVAILABLE"
    )
    states["runtime"] = runtime["observation_state"]
    for name, holder, key in (("project.revision_ledger", project, "revision_ledger"), ("delivery.noncanonical_checklists", delivery, "noncanonical_checklists")):
        if isinstance(holder.get(key), dict) and holder[key].get("observation_state"):
            states[name] = holder[key]["observation_state"]
    states["runtime.operating_mode"] = "NOT_OBSERVABLE"
    states["verification.model_freshness"] = verification["evidence"]["model_freshness_observation_state"]
    return states


def build_health(status: dict[str, Any], *, include_diagnostics: bool = False) -> dict[str, Any]:
    """Projection/Data health, derived only from the projection itself (never project authority).

    Attention vs. health vs. framework diagnostics: the group counts keep non-blocking framework or
    metadata diagnostics from reading as project defects; any blocking diagnostic stays visible.
    """
    compatibility = status.get("compatibility") or {}
    diagnostics = compatibility.get("diagnostics") or []
    groups: dict[str, dict[str, int]] = {name: {"total": 0, "blocking": 0} for name in DIAGNOSTIC_GROUP_ORDER}
    listed: dict[str, list[dict[str, Any]]] = {name: [] for name in DIAGNOSTIC_GROUP_ORDER}
    for item in diagnostics:
        group = item.get("diagnostic_group") if item.get("diagnostic_group") in groups else "projection_health"
        groups[group]["total"] += 1
        groups[group]["blocking"] += 1 if item.get("blocking") else 0
        listed[group].append(item)
    blocking = sum(entry["blocking"] for entry in groups.values())
    states = status.get("health", {}).get("observation_states") or {}
    degraded = any(state in ("INVALID", "STALE", "AMBIGUOUS", "PROJECTION_ERROR") for state in states.values())
    level = "BLOCKED" if blocking else "DEGRADED" if degraded or groups["projection_health"]["total"] else "OK"
    health: dict[str, Any] = {
        "level": level,
        "observation_states": states,
        "diagnostics_by_group": groups,
        "blocking_diagnostics": blocking,
        "framework": {
            "compatibility": compatibility.get("compatibility"),
            "repair_status": compatibility.get("repair_status"),
        },
    }
    if include_diagnostics:
        health["diagnostics"] = listed
    return health


DELIVERY_ASSESSMENT_RULE = "delivery-assessment/v1"
WAVE_PHASE_ORDER = ("discovery", "refinement", "ready", "implementing", "verifying", "done")
_NEXT_GATE = {"discovery": "gate_to_refinement", "refinement": "gate_to_ready", "ready": None,
              "implementing": None, "verifying": "acceptance_gate"}
_ACTIVITY_PATH_CLASSES = {"MENDIX_MODEL", "REFERENCE", "PROJECT_CODE"}
_DELIVERY_ACTIVITY_CACHE: dict[tuple[str, str], dict[str, Any]] = {}
_DONE_ADDED = re.compile(r"^\+\s+phase:\s*['\"]?done\b", re.MULTILINE)


def _git_text(root: Path, *args: str, timeout: float = 20.0) -> str | None:
    import subprocess
    try:
        done = subprocess.run(
            ["git", "--no-optional-locks", "-c", "core.quotepath=false", "-C", str(root), *args],
            capture_output=True, timeout=timeout, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout.decode("utf-8", "replace") if done.returncode == 0 else None


def _is_delivery_path(path: str) -> bool:
    from reconciliation_git import classify_path
    kind = classify_path(path)
    if kind in _ACTIVITY_PATH_CLASSES:
        return True
    # Unclassified project paths (application source, theme, ...) count; dot-files and tooling do not.
    return kind == "UNKNOWN" and not path.startswith(".") and "/." not in path


def _newly_done_waves(root: Path, commit: str, path: str) -> set[str]:
    """Waves whose phase is done at `commit` but was not done at its parent (one git process)."""
    import subprocess
    try:
        done = subprocess.run(
            ["git", "--no-optional-locks", "-C", str(root), "cat-file", "--batch"],
            input=f"{commit}:{path}\n{commit}^:{path}\n".encode("utf-8"), capture_output=True, timeout=20, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return set()
    data, blobs, position = done.stdout, [], 0
    for _ in range(2):
        end = data.find(b"\n", position)
        if end < 0:
            blobs.append(None)
            break
        header = data[position:end].split()
        if len(header) == 3 and header[1] == b"blob" and header[2].isdigit():
            size = int(header[2])
            blobs.append(data[end + 1:end + 1 + size])
            position = end + 1 + size + 1
        else:
            blobs.append(None)
            position = end + 1

    def waves_done(blob: bytes | None) -> set[str]:
        try:
            document = yaml.safe_load(blob.decode("utf-8-sig")) if blob else None
        except (yaml.YAMLError, UnicodeError):
            return set()
        waves = document.get("waves") if isinstance(document, dict) else None
        if not isinstance(waves, dict):
            return set()
        return {str(key) for key, value in waves.items() if isinstance(value, dict) and value.get("phase") == "done"}

    while len(blobs) < 2:
        blobs.append(None)
    return waves_done(blobs[0]) - waves_done(blobs[1])


def observe_delivery_activity(root: Path) -> dict[str, Any]:
    """Existence-only Git observation (R-10): never assigns commits to a Wave, Mission or Task."""
    unavailable = {"observation_state": "NOT_OBSERVABLE", "head": None, "latest_commit": None,
                   "last_done_transition": None, "commits_after_done": None, "observed": None, "reason": "NO_GIT_HISTORY"}
    info = _git_text(root, "log", "-1", "--format=%H%x00%ct%x00%s")
    if not info or info.count("\x00") < 2:
        return unavailable
    head, stamp, subject = info.rstrip("\n").split("\x00", 2)
    cache_key = (str(root), head)
    cached = _DELIVERY_ACTIVITY_CACHE.get(cache_key)
    if cached is not None:
        return cached
    latest = {"commit": head[:12], "committed_at": int(stamp) if stamp.isdigit() else None, "subject": subject[:120]}
    result: dict[str, Any] = {**unavailable, "head": head[:12], "latest_commit": latest, "reason": "NO_DONE_TRANSITION_IN_WINDOW"}
    history = _git_text(root, "log", "-n", "200", "-p", "--unified=0", "--format=%x01%H%x00%ct", "--", "planning/lifecycle/process-state.yaml")
    done_commit = None
    for chunk in (history or "").split("\x01"):
        if not chunk.strip():
            continue
        header, _, patch = chunk.partition("\n")
        if _DONE_ADDED.search(patch):
            sha, _, stamp = header.partition("\x00")
            done_commit = {"commit": sha[:12], "full": sha, "committed_at": int(stamp) if stamp.strip().isdigit() else None}
            break
    if done_commit is not None:
        listing = None if done_commit["full"] == head else _git_text(root, "log", "-n", "500", "--name-only", "--format=%x01%H", f"{done_commit['full']}..HEAD")
        count = 0
        for chunk in (listing or "").split("\x01"):
            names = [line for line in chunk.split("\n")[1:] if line.strip()]
            if any(_is_delivery_path(name) for name in names):
                count += 1
        path = "planning/lifecycle/process-state.yaml"
        newly_done = sorted(_newly_done_waves(root, done_commit["full"], path))
        result.update({
            "observation_state": "AVAILABLE", "reason": None,
            "last_done_transition": {"commit": done_commit["commit"], "committed_at": done_commit["committed_at"], "waves": newly_done[:6]},
            "commits_after_done": count, "observed": count > 0,
        })
    if len(_DELIVERY_ACTIVITY_CACHE) > 16:
        _DELIVERY_ACTIVITY_CACHE.clear()
    _DELIVERY_ACTIVITY_CACHE[cache_key] = result
    return result


def derive_current_work(
    mission: dict[str, Any], active_wave_id: str | None, waves: list[dict[str, Any]],
    tasks: list[dict[str, Any]], activity: dict[str, Any], next_action: dict[str, Any] | None,
    active_targets: list[dict[str, Any]],
) -> dict[str, Any]:
    """Derived, never stored: Mission -> registered active/blocked Wave -> next registered Wave -> none (FR-060)."""
    wave_by_id = {wave["wave_id"]: wave for wave in waves}

    def wave_view(wave: dict[str, Any]) -> dict[str, Any]:
        return {"wave_id": wave["wave_id"], "phase": wave["phase"], "gates": wave["gates"]}

    def tasks_in_progress(wave_id: str) -> list[str]:
        return sorted(task["id"] for task in tasks if task.get("wave_id") == wave_id and task.get("status") == "in_progress")[:12]

    def requirements_of(wave_id: str) -> list[str]:
        wave = wave_by_id.get(wave_id) or {}
        return list(wave.get("requirement_ids") or [])[:20]

    def next_step(phase: str | None) -> dict[str, Any]:
        if phase in WAVE_PHASE_ORDER and phase != "done":
            target = WAVE_PHASE_ORDER[WAVE_PHASE_ORDER.index(phase) + 1]
            return {"kind": "LIFECYCLE_TRANSITION", "from_phase": phase, "to_phase": target, "requires": _NEXT_GATE.get(phase)}
        return {"kind": "UNKNOWN"}

    work: dict[str, Any] = {
        "derived": True, "state": "NONE", "source": "none", "reason": "NO_REGISTERED_ACTIVE_OR_PLANNED_WAVE",
        "mission": None, "wave": None, "requirement_ids": [], "tasks_in_progress": [], "blockers": [],
        "next_action": next_action, "next_step": {"kind": "REGISTER_WAVE"},
        "latest_activity": activity.get("latest_commit"),
        "design_authority": [
            {"reference_id": item.get("reference_id"), "mockup_name": item.get("mockup_name"), "revision_id": item.get("revision_id")}
            for item in active_targets[:3]
        ],
        "unattributed_activity": {"observed": None, "since_commit": None, "commit_count": None, "observation_state": "NOT_APPLICABLE"},
        "last_completed": None,
        "waves_registered": len(waves), "waves_done": sum(1 for wave in waves if wave["phase"] == "done"),
    }
    mission_open = mission.get("availability") != "unavailable" and mission.get("status") in ("active", "blocked")
    non_done = [wave for wave in waves if wave["phase"] != "done"]
    if mission_open:
        work["source"] = "mission_state"
        work["mission"] = {"id": mission.get("id"), "objective": mission.get("objective"), "status": mission.get("status"),
                           "progress": mission.get("progress")}
        work["blockers"] = list(mission.get("blockers") or [])
        blocked = mission.get("status") == "blocked" or bool(work["blockers"])
        work["state"], work["reason"] = ("BLOCKED" if blocked else "ACTIVE"), "MISSION_STATE"
        if active_wave_id:
            wave = wave_by_id.get(active_wave_id)
            if wave is None:
                work["state"], work["reason"] = "CONFLICT", "ACTIVE_WAVE_NOT_REGISTERED"
                work["conflict"] = {"active_wave": active_wave_id}
            elif wave["phase"] == "done":
                work["state"], work["reason"] = "CONFLICT", "ACTIVE_WAVE_IS_DONE"
                work["conflict"] = {"active_wave": active_wave_id}
            else:
                work["wave"] = wave_view(wave)
                work["requirement_ids"] = requirements_of(active_wave_id)
                work["tasks_in_progress"] = tasks_in_progress(active_wave_id)
                work["next_step"] = next_step(wave["phase"])
        else:
            work["next_step"] = {"kind": "UNKNOWN"}
        return work
    running = [wave for wave in non_done if wave["phase"] in ("implementing", "verifying")]
    if len(running) > 1:
        work.update({"state": "CONFLICT", "source": "process_state", "reason": "MULTIPLE_ACTIVE_WAVES",
                     "conflict": {"waves": [wave["wave_id"] for wave in running]}})
        return work
    if running:
        wave = running[0]
        blocked = any(task.get("wave_id") == wave["wave_id"] and task.get("status") == "blocked" for task in tasks)
        work.update({"state": "BLOCKED" if blocked else "ACTIVE", "source": "process_state", "reason": "REGISTERED_WAVE",
                     "wave": wave_view(wave), "requirement_ids": requirements_of(wave["wave_id"]),
                     "tasks_in_progress": tasks_in_progress(wave["wave_id"]), "next_step": next_step(wave["phase"])})
        return work
    if non_done:
        wave = non_done[0]
        work.update({"state": "NOT_STARTED", "source": "process_state", "reason": "NEXT_REGISTERED_WAVE",
                     "wave": wave_view(wave), "requirement_ids": requirements_of(wave["wave_id"]),
                     "next_step": next_step(wave["phase"])})
        return work
    # No active canonical work: report observed activity exists, but never attribute it.
    done_transition = activity.get("last_done_transition") or {}
    if done_transition.get("waves"):
        completed_ids = [wave_id for wave_id in done_transition["waves"] if wave_id in wave_by_id]
        wave_tasks = [task for task in tasks if task.get("wave_id") in completed_ids]
        work["last_completed"] = {
            "commit": done_transition.get("commit"), "committed_at": done_transition.get("committed_at"),
            "wave_ids": completed_ids,
            "task_count": len(wave_tasks), "tasks_done": sum(1 for task in wave_tasks if task.get("status") == "done"),
            "requirement_ids": sorted({req for wave_id in completed_ids for req in (wave_by_id[wave_id].get("requirement_ids") or [])})[:20],
        }
    work["unattributed_activity"] = {
        "observed": activity.get("observed"), "since_commit": done_transition.get("commit"),
        "commit_count": activity.get("commits_after_done"), "observation_state": activity.get("observation_state", "NOT_OBSERVABLE"),
    }
    return work


def _terminal_status(task: dict[str, Any]) -> str | None:
    return task.get("status")


def build_delivery_assessments(
    requirements: list[dict[str, Any]], tasks: list[dict[str, Any]], contracts: list[dict[str, Any]],
    evidence_entries: list[dict[str, Any]], findings: list[dict[str, Any]], decisions: list[dict[str, Any]],
    *, findings_observation: str, target_freshness: str, model_freshness: str,
) -> None:
    """Attach `delivery_assessment` (delivery-assessment/v1) to each requirement item; derived, never written back."""
    tasks_by_req: dict[str, list[dict[str, Any]]] = {}
    for task in tasks:
        for req_id in task.get("requirement_ids") or []:
            tasks_by_req.setdefault(req_id, []).append(task)
    contracts_by_req: dict[str, list[dict[str, Any]]] = {}
    for contract in contracts:
        for req_id in contract.get("requirement_ids") or []:
            contracts_by_req.setdefault(req_id, []).append(contract)
    evidence_by_req: dict[str, list[dict[str, Any]]] = {}
    for entry in evidence_entries:
        for req_id in entry.get("requirement_ids") or []:
            evidence_by_req.setdefault(req_id, []).append(entry)
    blocking_by_req: dict[str, list[str]] = {}
    for finding in findings:
        if finding.get("blocking"):
            for req_id in finding.get("requirement_ids") or []:
                blocking_by_req.setdefault(req_id, []).append(finding["id"])
    proposed_by_req: dict[str, list[str]] = {}
    for decision in decisions:
        if decision.get("status") == "PROPOSED":
            for req_id in decision.get("affected_requirements") or []:
                proposed_by_req.setdefault(req_id, []).append(decision["id"])

    def level(name: str, state: str, refs: list[dict[str, str]], reasons: list[tuple[str, str]]) -> dict[str, Any]:
        return {"level": name, "state": state, "evidence_refs": refs[:8],
                "reasons": [{"code": code, "text": text} for code, text in reasons][:6]}

    for item in requirements:
        req_id = item["id"]
        linked = tasks_by_req.get(req_id, [])
        done = [task for task in linked if task.get("status") == "done"]
        refs = [{"type": "task", "id": task["id"]} for task in linked]
        if not linked:
            implementation = level("implementation", "NOT_MET", [], [("NO_TASK_LINKED", "No Task references this Requirement.")])
        elif len(done) == len(linked):
            implementation = level("implementation", "MET", [{"type": "task", "id": task["id"]} for task in done], [])
        else:
            open_tasks = [task for task in linked if task.get("status") != "done"]
            reasons = [("OPEN_TASKS", f"{len(open_tasks)} of {len(linked)} Tasks are not done: " + ", ".join(task["id"] for task in open_tasks[:4]))]
            if any(task.get("status") in ("blocked", "deferred") for task in open_tasks):
                reasons.append(("TASK_BLOCKED_OR_DEFERRED", "At least one open Task is blocked or deferred."))
            implementation = level("implementation", "PARTIAL" if done else "NOT_MET", refs, reasons)

        linked_contracts = contracts_by_req.get(req_id, [])
        entries = evidence_by_req.get(req_id, [])
        passing = [entry for entry in entries if entry.get("parity_result") == "PASS"]
        failing = [entry for entry in entries if entry.get("parity_result") in ("FAIL", "STALE")]
        evidence_refs = [{"type": "evidence", "id": entry["entry_id"]} for entry in entries]
        if not linked_contracts:
            verification = level("verification", "NOT_OBSERVABLE", [], [("NO_TEST_CONTRACT", "No Test Contract is linked, so no verification target is defined.")])
        elif passing and not failing and len(passing) == len(entries):
            verification = level("verification", "MET", evidence_refs, [])
        elif passing:
            verification = level("verification", "PARTIAL", evidence_refs, [("EVIDENCE_NOT_ALL_PASS", f"{len(passing)} of {len(entries)} evidence entries passed.")])
        else:
            verification = level("verification", "NOT_MET", [{"type": "test_contract", "id": contract["id"]} for contract in linked_contracts],
                                 [("NO_PASSING_EVIDENCE", "Test Contract exists but no bound, passing evidence is recorded. Reported parity results do not count (REPORTED_UNBOUND).")])

        if model_freshness == "unknown":
            freshness = level("freshness", "NOT_OBSERVABLE", [], [("MODEL_FRESHNESS_NOT_OBSERVABLE", "The current Mendix model state is not observable, so evidence currency cannot be confirmed.")])
        else:
            freshness = level("freshness", "PARTIAL", [], [("FRESHNESS_PARTIAL", f"Target freshness: {target_freshness}.")])
        if failing:
            freshness = level("freshness", "NOT_MET", evidence_refs, [("EVIDENCE_STALE_OR_FAILED", "At least one evidence entry is stale or failed.")])

        blockers = blocking_by_req.get(req_id, []) + proposed_by_req.get(req_id, [])
        if blockers:
            blocker = level("blocker", "NOT_MET", [{"type": "finding" if ref.startswith("FIND") else "decision", "id": ref} for ref in blockers],
                            [("OPEN_BLOCKER", "Blocking Finding or proposed Decision affects this Requirement: " + ", ".join(blockers[:4]))])
        elif findings_observation not in ("AVAILABLE", "EMPTY"):
            blocker = level("blocker", "NOT_OBSERVABLE", [], [("FINDINGS_NOT_OBSERVABLE", f"Findings are {findings_observation.replace('_', ' ').lower()}, so absence of blockers cannot be asserted.")])
        else:
            blocker = level("blocker", "MET", [], [])

        levels = [implementation, verification, freshness, blocker]
        if blocker["state"] == "NOT_MET":
            label = "BLOCKED"
        elif implementation["state"] == "MET" and verification["state"] == "MET" and freshness["state"] != "NOT_MET":
            label = "VERIFIED"
        elif implementation["state"] == "MET":
            label = "IMPLEMENTED"
        elif implementation["state"] == "PARTIAL" or any(task.get("status") == "in_progress" for task in linked):
            label = "IN_PROGRESS"
        else:
            label = "NOT_STARTED"
        for entry_level in levels:
            if not entry_level["evidence_refs"] and not entry_level["reasons"]:
                entry_level["reasons"] = [{"code": "CONDITION_MET_NO_RECORD", "text": "Condition satisfied; no record needs to be cited."}]
        item["delivery_assessment"] = {
            "requirement_id": req_id, "rule_version": DELIVERY_ASSESSMENT_RULE, "label": label,
            "levels": levels, "derived": True,
        }


def _timeline_wave_history(root: Path) -> dict[str, Any]:
    """Per-Wave DONE reconstruction from the process-state history (CS-5); unavailable without Git or the module."""
    try:
        import build_project_timeline
        return build_project_timeline.wave_history(root)
    except Exception:
        return {"observation_state": "NOT_OBSERVABLE", "reason": "TIMELINE_UNAVAILABLE", "waves": {}}


def _changes_after_done(phase: str | None, wave_id: str, history: dict[str, Any] | None) -> dict[str, Any]:
    """Later activity never reopens or invalidates DONE; it is reported next to it (BRD-F-56)."""
    empty = {"commit_count": None, "project_activity_commits": None, "done_transition": None, "linked_commits": []}
    if phase != "done":
        return {"observation_state": "NOT_APPLICABLE", **empty}
    if not history or history.get("observation_state") != "AVAILABLE":
        return {"observation_state": "NOT_OBSERVABLE", **empty}
    entry = history["waves"].get(wave_id)
    if entry is None:
        # The transition is not in the observed history; it is never inferred from timestamps (BRD-F-28).
        return {"observation_state": "NOT_RECORDED", **empty}
    return {
        "observation_state": "AVAILABLE", "commit_count": entry["linked_artifact_commits"],
        "project_activity_commits": entry["project_activity_commits"],
        "done_transition": {"commit": entry["commit"], "committed_at": entry["committed_at"]},
        "linked_commits": list(entry["linked_commit_hashes"]),
    }


def build_waves_trust(
    waves: list[dict[str, Any]], process_doc: dict[str, Any] | None, tasks: list[dict[str, Any]],
    requirements: list[dict[str, Any]], findings: list[dict[str, Any]], activity: dict[str, Any],
    history: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """'Trust in DONE' per Wave (K.5): historical DONE stays DONE; present confidence is reported separately."""
    waves_doc = process_doc.get("waves") if isinstance(process_doc, dict) and isinstance(process_doc.get("waves"), dict) else {}
    assessment_by_req = {item["id"]: item.get("delivery_assessment") for item in requirements}
    trust: list[dict[str, Any]] = []
    for wave in waves:
        wave_id = wave["wave_id"]
        raw = waves_doc.get(wave_id) if isinstance(waves_doc.get(wave_id), dict) else {}
        gates = raw.get("gates") if isinstance(raw.get("gates"), dict) else {}
        acceptance = gates.get("acceptance_gate") if isinstance(gates.get("acceptance_gate"), dict) else None
        legacy_text = " ".join(str(value) for value in (raw.get("resume_from"), (gates.get("gate_to_refinement") or {}).get("note") if isinstance(gates.get("gate_to_refinement"), dict) else None) if value)
        is_legacy = "legacy" in legacy_text.lower() or "completion_override" in raw
        result = acceptance.get("result") if acceptance else None
        if acceptance and result in ("passed", "failed", "pending"):
            basis_state = "RECORDED"
        elif is_legacy:
            basis_state = "LEGACY"
        else:
            basis_state = "NOT_RECORDED"
        evidence = acceptance.get("evidence") if acceptance and isinstance(acceptance.get("evidence"), list) else []
        wave_tasks = [task for task in tasks if task.get("wave_id") == wave_id]
        open_tasks = sorted(task["id"] for task in wave_tasks if task.get("status") not in ("done", "deferred"))
        done_wave = wave["phase"] == "done"
        explained = basis_state in ("RECORDED", "LEGACY")
        wave_findings = sorted(finding["id"] for finding in findings if finding.get("wave_id") == wave_id)
        labels: dict[str, int] = {}
        for req_id in wave.get("requirement_ids") or []:
            assessment = assessment_by_req.get(req_id)
            if assessment:
                labels[assessment["label"]] = labels.get(assessment["label"], 0) + 1
        verified = labels.get("VERIFIED", 0)
        if verified:
            confidence, reasons = "EVIDENCED", ["Requirements of this Wave have bound, passing evidence."]
        elif labels:
            confidence, reasons = "NOT_EVIDENCED", ["None of this Wave's Requirements has bound, passing verification evidence."]
        else:
            confidence, reasons = "NOT_OBSERVABLE", ["No Requirement is linked to this Wave through Tasks."]
        reasons.append("Evidence currency against the current model is not observable.")
        trust.append({
            "wave_id": wave_id, "phase": wave["phase"], "historical_state": "DONE" if done_wave else (wave["phase"] or "UNKNOWN").upper(),
            "done_basis": {"state": basis_state, "gate_result": result, "evidence": [str(item) for item in evidence][:6]},
            "open_tasks_superseded": open_tasks if done_wave and explained else [],
            "open_tasks_unexplained": open_tasks if done_wave and not explained else [],
            "later_findings": wave_findings[:12],
            "changes_after_done": _changes_after_done(wave["phase"], wave_id, history),
            "present_confidence": {"level": confidence, "requirement_labels": labels, "freshness": "NOT_OBSERVABLE", "reasons": reasons},
        })
    return trust


def build_revision_ledger(root: Path, hashes: dict[str, str], gaps: list, parsed_documents: dict | None) -> dict[str, Any]:
    """Revision ledger (planning/revisions/REV-*.yaml) as design-authority source (FR-065)."""
    if not (root / "planning/revisions").is_dir():
        return {"observation_state": "NOT_RECORDED", "items": []}
    state, records, paths = read_collection(root, "planning/revisions", "REV-*.yaml", "", hashes, gaps, parsed_documents)
    items = []
    for record, path in zip(records, paths):
        screens = record.get("screens") if isinstance(record.get("screens"), list) else []
        decisions = record.get("acceptance_decisions") if isinstance(record.get("acceptance_decisions"), list) else []
        items.append({
            "revision_id": record.get("revision_id") if isinstance(record.get("revision_id"), str) else Path(path).stem,
            "active_target": record.get("active_target") is True,
            "status": record.get("status") if isinstance(record.get("status"), str) else None,
            "artifact_path": record.get("artifact_path") if isinstance(record.get("artifact_path"), str) else None,
            "screens": [str(screen) for screen in screens][:20],
            "acceptance_decisions": [str(decision) for decision in decisions][:10],
            "authority_source": "revision_ledger", "canonical_path": path,
        })
    observation = _observed(state, count=len(items))
    return {"observation_state": observation, "items": items}


def build_parity_report_states(parity_records: list[dict[str, Any]], parity_paths: list[str]) -> list[dict[str, Any]]:
    """Parity reports without bound evidence are 'reported, not proven' (FR-066)."""
    reports = []
    for record, path in list(zip(parity_records, parity_paths))[:200]:
        if not isinstance(record, dict):
            continue
        resolution = resolve_parity_status(record)
        reported = record.get("overall_result") if isinstance(record.get("overall_result"), str) else None
        status = resolution.get("status")
        if status == "RESOLVED":
            state = "COMPUTED"
        elif status == "STALE":
            state = "STALE"
        elif reported in (None, "NOT_VERIFIED"):
            state = "NOT_VERIFIED"
        else:
            state = "REPORTED_UNBOUND"
        reports.append({
            "report_path": path, "page_id": record.get("page_id") if isinstance(record.get("page_id"), str) else None,
            "scenario_id": record.get("scenario_id") if isinstance(record.get("scenario_id"), str) else None,
            "reported_result": reported, "computed_result": resolution.get("computed_overall_result"),
            "state": state, "verified_at": str(record.get("verified_at")) if record.get("verified_at") is not None else None,
            "reasons": [blocker.get("code") for blocker in (resolution.get("blockers") or []) if isinstance(blocker, dict) and blocker.get("code")][:4],
        })
    return reports


def attach_cs4_projections(
    result: dict[str, Any], *, root: Path, process_doc: dict[str, Any] | None, tasks: list[dict[str, Any]],
    parity_records: list[dict[str, Any]], parity_paths: list[str], checklist_paths: list[str],
    task_records: list[dict[str, Any]], hashes: dict[str, str], gaps: list, parsed_documents: dict | None,
    active_wave_id: str | None, next_action: dict[str, Any] | None,
) -> None:
    findings_observation = _observed(result["findings"]["availability"], missing="!missing-directory:planning/findings" in hashes,
                                     count=len(result["findings"]["items"]))
    evidence = result["verification"]["evidence"]
    build_delivery_assessments(
        result["requirements"]["items"], result["delivery"]["tasks"]["items"], result["verification"]["test_contracts"]["items"],
        evidence["entries"], result["findings"]["items"], result["decisions"]["items"],
        findings_observation=findings_observation, target_freshness=evidence["target_freshness"], model_freshness=evidence["model_freshness"],
    )
    activity = observe_delivery_activity(root)
    result["current_work"] = derive_current_work(
        result["mission"], active_wave_id, result["delivery"]["waves"]["items"], result["delivery"]["tasks"]["items"],
        activity, next_action, result["project"]["active_targets"]["items"],
    )
    result["waves_trust"] = build_waves_trust(
        result["delivery"]["waves"]["items"], process_doc, result["delivery"]["tasks"]["items"],
        result["requirements"]["items"], result["findings"]["items"], activity, _timeline_wave_history(root),
    )
    result["project"]["revision_ledger"] = build_revision_ledger(root, hashes, gaps, parsed_documents)
    result["verification"]["parity_reports"] = build_parity_report_states(parity_records, parity_paths)
    migrated = {task.get("migrated_from") for task in task_records}
    result["delivery"]["noncanonical_checklists"] = {
        "observation_state": "AVAILABLE" if checklist_paths else "EMPTY",
        "items": [path for path in checklist_paths if path not in migrated][:40],
    }


def _build_status(
    project_root: Path,
    *,
    include_gallery: bool = True,
    gallery_screen_id: str | None = None,
) -> dict[str, Any]:
    root = project_root.resolve()
    hashes: dict[str, str] = {}
    gaps: list[dict[str, str | None]] = []
    parsed_documents: dict[str, dict[str, Any]] = {}

    stage_started = time.perf_counter()
    project_config, _ = read_yaml_file(root, "mxagile-project.yaml", hashes, gaps, parsed_documents)
    version_doc, version_state = read_yaml_file(root, ".mxagile/version.yaml", hashes, gaps, parsed_documents)
    process_doc, process_state = read_yaml_file(root, "planning/lifecycle/process-state.yaml", hashes, gaps, parsed_documents)
    mission_doc, mission_state = read_yaml_file(root, "planning/mission/mission-state.yaml", hashes, gaps, parsed_documents)
    context_doc, context_state = read_yaml_file(root, "planning/lifecycle/context-epoch.yaml", hashes, gaps, parsed_documents)
    _emit_project_stage("project_config_and_lifecycle_inputs", stage_started, hashed_sources=len(hashes))

    stage_started = time.perf_counter()
    requirement_state, requirements, requirement_paths = read_collection(root, "requirements", "*.yml", "ID", hashes, gaps, parsed_documents)
    read_collection(root, "specs", "*.yml", "ID", hashes, gaps, parsed_documents)
    task_state, tasks, task_paths = read_collection(root, "planning/tasks", "*.yml", "ID", hashes, gaps, parsed_documents)
    _emit_project_stage("requirements_specs_tasks_scan", stage_started,
                        requirements=len(requirements), tasks=len(tasks), hashed_sources=len(hashes))

    stage_started = time.perf_counter()
    decision_state, decisions, decision_paths = read_collection(root, "planning/decisions", "*.yml", "ID", hashes, gaps, parsed_documents)
    finding_state, finding_records, finding_paths = read_collection(root, "planning/findings", "*.yml", "ID", hashes, gaps, parsed_documents)
    _emit_project_stage("findings_and_decisions_scan", stage_started,
                        findings=len(finding_records), decisions=len(decisions), hashed_sources=len(hashes))

    stage_started = time.perf_counter()
    contract_state, contracts, contract_paths = read_collection(root, "planning/test-contracts", "TC-*.yaml", "ID", hashes, gaps, parsed_documents)
    plan_state, plans, plan_paths = read_collection(root, "planning/verification-plans", "*.yaml", "ID", hashes, gaps, parsed_documents)
    page_state, pages, page_paths = read_collection(root, "planning/ui-inventory", "*.yaml", "page_id", hashes, gaps, parsed_documents)
    page_records = [(page, path) for page, path in zip(pages, page_paths)
                    if not is_standalone_interaction_artifact(path)]
    pages = [page for page, _ in page_records]
    page_paths = [path for _, path in page_records]
    _emit_project_stage("contracts_plans_and_page_inventory", stage_started,
                        contracts=len(contracts), plans=len(plans), pages=len(pages), hashed_sources=len(hashes))

    stage_started = time.perf_counter()
    evidence_state, manifests, manifest_paths = read_collection(
        root, "planning/evidence/manifests", "*-evidence-manifest.yaml", "", hashes, gaps, parsed_documents
    )
    _emit_project_stage("evidence_manifest_scan", stage_started,
                        manifests=len(manifests), hashed_sources=len(hashes))

    stage_started = time.perf_counter()
    _parity_state, parity_records, parity_paths = read_collection(root, "planning/parity", "*.yaml", "", hashes, gaps, parsed_documents)
    revision_state, revisions, revision_paths = read_collection(
        root, "planning/target-mockups", "*/_history/REV-*/revision.yaml", "revision_id", hashes, gaps, parsed_documents
    )
    _emit_project_stage("parity_and_mockup_revision_scan", stage_started,
                        revisions=len(revisions), hashed_sources=len(hashes))

    stage_started = time.perf_counter()
    checklist_directory = root / "planning/checklists"
    checklist_paths: list[str] = []
    if checklist_directory.exists():
        if safe_path(root, checklist_directory) and checklist_directory.is_dir():
            for checklist_path in sorted(checklist_directory.glob("W*-implementation-checklist.yaml"), key=lambda path: path.as_posix()):
                if not safe_path(root, checklist_path) or not checklist_path.is_file():
                    add_gap(gaps, "CHECKLIST_PATH_INVALID", "planning/checklists", "A checklist path is not a regular file inside the project root.")
                    continue
                relative = checklist_path.relative_to(root).as_posix()
                try:
                    raw = checklist_path.read_bytes()
                    hashes[relative] = hashlib.sha256(raw).hexdigest()
                    parsed_documents[relative] = {"state": "raw_only", "raw": raw, "value": None, "digest": hashes[relative]}
                except OSError:
                    add_gap(gaps, "CHECKLIST_UNREADABLE", relative, "A checklist source could not be fingerprinted.")
                    continue
                checklist_paths.append(relative)
        else:
            add_gap(gaps, "CHECKLIST_PATH_INVALID", "planning/checklists", "Checklist directory is not safely contained in the project root.")
    _emit_project_stage("checklist_hashing", stage_started, checklists=len(checklist_paths), hashed_sources=len(hashes))

    stage_started = time.perf_counter()
    wave_state, waves, wave_counts = wave_projection(process_doc if process_state == "available" else None)
    waves, checklist_summary, workpackages = delivery_projection(task_state, tasks, waves, checklist_paths, gaps)
    _emit_project_stage("lifecycle_and_workstream_projection", stage_started, waves=len(waves), workpackages=len(workpackages))

    stage_started = time.perf_counter()
    target_availability, active_targets, spa_targets, target_by_screen = build_active_targets(
        root, revision_state, revisions, revision_paths, page_state, pages, page_paths, hashes, gaps
    )
    mission, active_wave_id = mission_projection(mission_doc, mission_state)
    blocked_by_decision_count = mission["blocker_types"].get("DECISION_REQUIRED")
    blocked_by_decision_availability = (
        mission["availability"]
        if isinstance(blocked_by_decision_count, int)
        else "unavailable"
    )
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
    _emit_project_stage("active_mockup_target_projection", stage_started,
                        pages=len(pages), targets=len(active_targets), status=lifecycle_availability)

    project_name = project_config.get("name") if isinstance(project_config, dict) else None
    if not isinstance(project_name, str) or not project_name.strip():
        mpr_files = sorted(root.glob("*.mpr"), key=lambda item: item.name.lower())
        project_name = mpr_files[0].stem if len(mpr_files) == 1 else root.name
    core_version = version_doc.get("version") if isinstance(version_doc, dict) else None
    project_availability = "available" if version_state == "available" else "partial"
    add_gap(gaps, "PROJECT_ID_UNAVAILABLE", "mxagile-project.yaml", "No stable project identifier exists; display name is not an identity.")

    def available(state: str) -> bool:
        return state in ("available", "partial")

    def normalized(state: str) -> str:
        return state if state in ("available", "partial", "unavailable", "ambiguous") else "unavailable"

    req_counts = status_counts(requirements, "status", REQUIREMENT_STATUSES, available(requirement_state))
    task_counts = status_counts(tasks, "status", TASK_STATUSES, available(task_state))
    decision_counts = status_counts(decisions, "status", DECISION_STATUSES, available(decision_state))
    contract_counts = status_counts(contracts, "status", CONTRACT_STATUSES, available(contract_state))
    plan_counts = status_counts(plans, "status", PLAN_STATUSES, available(plan_state))
    requirement_items = [
        {
            "id": record["ID"],
            "title": record.get("title") if isinstance(record.get("title"), str) else None,
            "status": record.get("status") if record.get("status") in REQUIREMENT_STATUSES else None,
            "superseded_by": record.get("superseded_by") if isinstance(record.get("superseded_by"), str) else None,
            "canonical_path": path,
            "content_hash": f"sha256:{hashes[path]}" if hashes.get(path) else None,
        }
        for record, path in zip(requirements, requirement_paths)
        if isinstance(record.get("ID"), str)
    ]
    decision_items = [
        {
            "id": record["ID"],
            "title": record.get("title") if isinstance(record.get("title"), str) else None,
            "status": record.get("status") if record.get("status") in DECISION_STATUSES else None,
            "affected_requirements": sorted({
                req_id for req_id in record.get("affected_requirements", []) if isinstance(req_id, str)
            }) if isinstance(record.get("affected_requirements", []), list) else [],
            "created_at": str(record["created_at"]) if record.get("created_at") is not None else None,
            "confirmed_at": str(record["confirmed_at"]) if record.get("confirmed_at") is not None else None,
            "rationale_excerpt": record["rationale"].strip()[:240] if isinstance(record.get("rationale"), str) and record["rationale"].strip() else None,
            "affected_screens": sorted({
                item for item in record.get("affected_screens", []) if isinstance(item, str)
            })[:20] if isinstance(record.get("affected_screens", []), list) else [],
            "affected_mockup_revisions": sorted({
                item for item in record.get("affected_mockup_revisions", []) if isinstance(item, str)
            })[:20] if isinstance(record.get("affected_mockup_revisions", []), list) else [],
            "canonical_path": path,
            "content_hash": f"sha256:{hashes[path]}" if hashes.get(path) else None,
        }
        for record, path in zip(decisions, decision_paths)
        if isinstance(record.get("ID"), str)
    ]
    contract_items = [
        {
            "id": record["ID"],
            "title": record.get("title") if isinstance(record.get("title"), str) else None,
            "status": record.get("status") if record.get("status") in CONTRACT_STATUSES else None,
            "requirement_ids": sorted({req_id for req_id in record.get("requirement_ids", []) if isinstance(req_id, str)})
            if isinstance(record.get("requirement_ids", []), list) else [],
            "proof_point_ids": sorted({
                point.get("id") for point in record.get("proof_points", [])
                if isinstance(point, dict) and isinstance(point.get("id"), str)
            }) if isinstance(record.get("proof_points", []), list) else [],
            "canonical_path": path,
            "content_hash": f"sha256:{hashes[path]}" if hashes.get(path) else None,
        }
        for record, path in zip(contracts, contract_paths)
        if isinstance(record.get("ID"), str)
    ]

    findings_open: int | None = 0 if available(finding_state) else None
    findings_blocking: int | None = 0 if available(finding_state) else None
    findings_closed: int | None = 0 if available(finding_state) else None
    findings_superseded: int | None = 0 if available(finding_state) else None
    findings_retired: int | None = 0 if available(finding_state) else None
    findings_decision_required: int | None = 0 if available(finding_state) else None
    findings_framework_followup: int | None = 0 if available(finding_state) else None
    findings_unknown: int | None = 0 if available(finding_state) else None
    finding_items: list[dict[str, Any]] = []
    finding_history: list[dict[str, Any]] = []
    if available(finding_state):
        for finding, path in zip(finding_records, finding_paths):
            lifecycle_status = finding.get("lifecycle_status")
            known_status = lifecycle_status in (
                "DETECTED", "CLASSIFIED", "REPAIR_PROPOSED", "REPAIR_ACCEPTED",
                "REPAIRED", "VERIFIED", "REPAIR_REJECTED", "DECISION_REQUIRED", "SUPERSEDED", "RETIRED",
            )
            if not known_status:
                findings_unknown = int(findings_unknown or 0) + 1
                add_gap(gaps, "FINDING_STATUS_UNKNOWN", path, "Finding uses an unknown lifecycle status.")
            elif lifecycle_status in FINDING_TERMINAL_STATUSES:
                findings_closed = int(findings_closed or 0) + 1
                if lifecycle_status == "SUPERSEDED":
                    findings_superseded = int(findings_superseded or 0) + 1
                elif lifecycle_status == "RETIRED":
                    findings_retired = int(findings_retired or 0) + 1
            else:
                findings_open = int(findings_open or 0) + 1
            origin = finding.get("origin") if finding.get("origin") in ("PROJECT", "FRAMEWORK_FOLLOWUP") else "PROJECT"
            if known_status and origin == "FRAMEWORK_FOLLOWUP" and lifecycle_status not in FINDING_TERMINAL_STATUSES:
                findings_framework_followup = int(findings_framework_followup or 0) + 1
            if known_status and lifecycle_status == "DECISION_REQUIRED":
                findings_decision_required = int(findings_decision_required or 0) + 1
            severity = finding.get("severity")
            blocking = severity == "CRITICAL" or lifecycle_status == "DECISION_REQUIRED"
            if blocking and known_status and lifecycle_status not in FINDING_TERMINAL_STATUSES:
                findings_blocking = int(findings_blocking or 0) + 1
            item = {
                "id": finding.get("ID"),
                "title": finding.get("title"),
                "gap_type": finding.get("gap_type") if isinstance(finding.get("gap_type"), str) else None,
                "severity": severity if isinstance(severity, str) else None,
                "lifecycle_status": lifecycle_status if isinstance(lifecycle_status, str) else None,
                "origin": origin,
                "wave_id": finding.get("wave_id") if isinstance(finding.get("wave_id"), str) else None,
                "workpackage_id": finding.get("workpackage_id") if isinstance(finding.get("workpackage_id"), str) else None,
                "requirement_ids": sorted({
                    req_id for req_id in finding.get("requirement_ids", []) if isinstance(req_id, str)
                }) if isinstance(finding.get("requirement_ids", []), list) else [],
                "decision_ids": sorted({
                    decision_id for decision_id in finding.get("decision_ids", []) if isinstance(decision_id, str)
                }) if isinstance(finding.get("decision_ids", []), list) else [],
                "evidence_refs": sorted({
                    evidence_ref for evidence_ref in finding.get("evidence_refs", []) if isinstance(evidence_ref, str)
                }) if isinstance(finding.get("evidence_refs", []), list) else [],
                "blocking": bool(blocking and lifecycle_status != "VERIFIED"),
                "canonical_path": path,
                "authority_disposition": _finding_authority_disposition(
                    root, finding.get("authority_disposition"), hashes, parsed_documents,
                ),
            }
            reconciliation = finding.get("reconciliation") if isinstance(finding.get("reconciliation"), dict) else {}
            item.update({
                "source_artifact_paths": sorted({
                    source["canonical_path"] for source in finding.get("source_artifacts", [])
                    if isinstance(source, dict) and isinstance(source.get("canonical_path"), str)
                }) if isinstance(finding.get("source_artifacts", []), list) else [],
                "source_artifacts": [
                    {
                        "source_type": source.get("source_type") if isinstance(source.get("source_type"), str) else "other",
                        "canonical_path": source.get("canonical_path"),
                        "artifact_id": source.get("artifact_id") if isinstance(source.get("artifact_id"), str) else None,
                    }
                    for source in finding.get("source_artifacts", [])
                    if isinstance(source, dict) and isinstance(source.get("canonical_path"), str)
                ] if isinstance(finding.get("source_artifacts", []), list) else [],
                "reconciliation_delta_fingerprint": reconciliation.get("delta_fingerprint") if isinstance(reconciliation.get("delta_fingerprint"), str) else None,
                "reconciliation_outcome": reconciliation.get("outcome") if isinstance(reconciliation.get("outcome"), str) else None,
                "reconciliation_evidence_refs": sorted({
                    reference for reference in reconciliation.get("evidence_refs", []) if isinstance(reference, str)
                }) if isinstance(reconciliation.get("evidence_refs", []), list) else [],
                "resolution_references": sorted({
                    reference for reference in finding.get("resolution_references", []) if isinstance(reference, str)
                }) if isinstance(finding.get("resolution_references", []), list) else [],
                "superseded_by": finding.get("superseded_by") if isinstance(finding.get("superseded_by"), str) else None,
                "retirement_reason": finding.get("retirement_reason") if isinstance(finding.get("retirement_reason"), str) else None,
                "framework_commit": finding.get("framework_commit") if isinstance(finding.get("framework_commit"), str) else None,
                "resolution_commit": finding.get("resolution_commit") if isinstance(finding.get("resolution_commit"), str) else None,
            })
            if lifecycle_status in FINDING_TERMINAL_STATUSES:
                finding_history.append({
                    key: item[key] for key in (
                        "id", "lifecycle_status", "origin", "gap_type", "severity", "wave_id",
                        "workpackage_id", "requirement_ids", "decision_ids", "evidence_refs",
                        "resolution_references", "reconciliation_delta_fingerprint", "reconciliation_outcome",
                        "reconciliation_evidence_refs", "superseded_by", "retirement_reason",
                        "framework_commit", "resolution_commit", "source_artifact_paths", "source_artifacts", "canonical_path",
                        "authority_disposition",
                    )
                })
            else:
                finding_items.append(item)

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
        for requirement_id in (decision.get("affected_requirements") if isinstance(decision.get("affected_requirements"), list) else [])
        if isinstance(requirement_id, str)
    }) if available(decision_state) else []

    evidence_recorded = {state: 0 if available(evidence_state) else None for state in EVIDENCE_STATUSES}
    evidence_recorded["unknown"] = 0 if available(evidence_state) else None
    evidence_stale = 0 if available(evidence_state) else None
    evidence_failed = 0 if available(evidence_state) else None
    evidence_unverified = 0 if available(evidence_state) else None
    evidence_entries: list[dict[str, Any]] = []
    if available(evidence_state):
        for manifest, manifest_path in zip(manifests, manifest_paths):
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
                target_for_entry = spa_targets.get(entry.get("mockup_name"))
                if target_for_entry is None:
                    screen_id = entry.get("screen_id")
                    target_for_entry = target_by_screen.get(screen_id) if isinstance(screen_id, str) else None
                target_mismatch = bool(target_for_entry and (
                    target_for_entry.get("availability") == "available"
                    and (
                        (entry.get("target_revision") and entry.get("target_revision") != target_for_entry.get("revision_id"))
                        or (entry.get("bundle_hash") and target_for_entry.get("bundle_hash") and entry.get("bundle_hash") != target_for_entry.get("bundle_hash"))
                        or (entry.get("target_mockup") and target_for_entry.get("canonical_path") and entry.get("target_mockup") != target_for_entry.get("canonical_path"))
                    )
                ))
                if result == "STALE" or target_mismatch:
                    evidence_stale = int(evidence_stale or 0) + 1
                elif result == "FAIL":
                    evidence_failed = int(evidence_failed or 0) + 1
                elif result == "NOT_VERIFIED":
                    evidence_unverified = int(evidence_unverified or 0) + 1
                traceability = entry.get("traceability") if isinstance(entry.get("traceability"), dict) else {}
                requirements_for_entry = traceability.get("requirements", [])
                evidence_entries.append({
                    "entry_id": entry.get("entry_id") if isinstance(entry.get("entry_id"), str) else "UNKNOWN",
                    "scenario_id": entry.get("scenario_id") if isinstance(entry.get("scenario_id"), str) else "UNKNOWN",
                    "screen_id": entry.get("screen_id") if isinstance(entry.get("screen_id"), str) else "UNKNOWN",
                    "parity_result": result if result in EVIDENCE_STATUSES else None,
                    "requirement_ids": sorted({req_id for req_id in requirements_for_entry if isinstance(req_id, str)}) if isinstance(requirements_for_entry, list) else [],
                    "wave_id": manifest.get("wave_id") if isinstance(manifest.get("wave_id"), str) else None,
                    "mockup_name": entry.get("mockup_name") if isinstance(entry.get("mockup_name"), str) else None,
                    "target_revision": entry.get("target_revision") if isinstance(entry.get("target_revision"), str) else None,
                    "canonical_path": manifest_path,
                })

    if process_state != "available":
        add_gap(gaps, "LIFECYCLE_STATE_UNAVAILABLE", "planning/lifecycle/process-state.yaml", "Canonical tracked process state is missing or invalid; local scratch state is not read.")
    if mission_state != "available":
        add_gap(gaps, "MISSION_STATE_UNAVAILABLE", "planning/mission/mission-state.yaml", "Canonical mission state is missing or invalid.")
    if task_state != "available":
        add_gap(gaps, "TASKS_UNAVAILABLE", "planning/tasks", "Canonical task collection is missing or incomplete.")
    if checklist_paths and not any(task.get("migrated_from") in checklist_paths for task in tasks):
        add_gap(gaps, "CHECKLIST_CANONICALIZATION_REQUIRED", "planning/checklists", "Legacy checklists are available as source links but require canonicalized tasks for deterministic progress.")
    if finding_state != "available":
        add_gap(gaps, "FINDING_STATE_UNAVAILABLE", "planning/findings", "No canonical finding records are available in this project snapshot.")
    add_gap(gaps, "MODEL_FRESHNESS_UNAVAILABLE", "planning/acceptance-campaigns", "Verification artifacts do not record a current Mendix model fingerprint.")
    add_gap(gaps, "OPERATING_MODE_UNAVAILABLE", "machine/session observation", "Current Studio Pro operating mode is not a canonical project artifact.")
    add_gap(gaps, "CAPABILITY_SESSION_STATE_UNAVAILABLE", ".mxagile/capabilities.yaml", "Current capability activity requires session-attested environment evidence.")
    add_gap(gaps, "CONTEXT_SESSION_STATE_UNAVAILABLE", "Context Mode session", "Current context mode and pressure are not durable project status.")
    add_gap(gaps, "MULTI_SOURCE_UNAVAILABLE", None, "Core has no canonical source or agent-session registry.")

    context_status = {"availability": "unavailable", "epoch_id": None, "phase": None, "mode": None, "pressure": None, "next_action": None}
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
            action = context_doc.get("next_action") if isinstance(context_doc, dict) else None
            if isinstance(action, dict) and isinstance(action.get("description"), str):
                prerequisites = action.get("prerequisites")
                context_status["next_action"] = {
                    "description": action["description"].strip()[:300],
                    "safe_to_run": action.get("safe_to_run") if isinstance(action.get("safe_to_run"), bool) else None,
                    "prerequisites": [str(item)[:160] for item in prerequisites][:6] if isinstance(prerequisites, list) else [],
                }
    else:
        add_gap(gaps, "CONTEXT_EPOCH_UNAVAILABLE", "planning/lifecycle/context-epoch.yaml", "No canonical context handoff is available in this project snapshot.")

    source_reference_state, source_references = build_source_references(
        root,
        process_doc,
        process_state,
        waves,
        [
            ("requirement", requirements, requirement_paths),
            ("task", tasks, task_paths),
            ("decision", decisions, decision_paths),
            ("finding", finding_records, finding_paths),
            ("test_contract", contracts, contract_paths),
            ("verification_plan", plans, plan_paths),
            ("evidence_manifest", manifests, manifest_paths),
            # Parity reports are evidence sources in their own right, even without a manifest binding (BRD-F-07).
            ("parity_report", parity_records, parity_paths),
        ],
        manifests,
        manifest_paths,
        hashes,
        gaps,
    )

    hashes_payload = "\n".join(f"{path}:{digest}" for path, digest in sorted(hashes.items()))
    source_fingerprint = "sha256:" + hashlib.sha256(hashes_payload.encode("utf-8")).hexdigest()
    target_freshness = (
        "determinable"
        if available(evidence_state) and target_availability in ("available", "partial")
        else "unknown"
    )
    model_freshness = "unknown"
    evidence_freshness = "partial" if target_freshness == "determinable" else "unknown"

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

    def canonical_checklist_source(task: dict[str, Any]) -> str | None:
        value = task.get("migrated_from")
        if not isinstance(value, str):
            return None
        return canonical_reference(root, value, ("planning/checklists/",), hashes)[0]

    result = {
        "schema_version": 3,
        "projection": True,
        "authority": "mxagile_canonical_artifacts",
        "source_fingerprint": source_fingerprint,
        "project": {
            "availability": project_availability,
            "id": None,
            "name": project_name,
            "core_version": core_version if isinstance(core_version, str) else None,
            "active_targets": {"availability": target_availability, "items": active_targets},
            "lifecycle": {"availability": lifecycle_availability, "active_wave_id": active_wave_id, "phase": lifecycle_phase},
        },
        "mission": mission,
        "delivery": {
            "waves": {"availability": wave_state, "items": waves, "phase_counts": wave_counts},
            "tasks": {
                "availability": normalized(task_state),
                "items": [
                    {
                        "id": record["ID"],
                        "action": record.get("action") if isinstance(record.get("action"), str) else None,
                        "status": record.get("status") if record.get("status") in TASK_STATUSES else None,
                        "wave_id": record.get("wave_id") if isinstance(record.get("wave_id"), str) else None,
                        "workpackage_id": record.get("workpackage_id") if isinstance(record.get("workpackage_id"), str) else None,
                        "requirement_ids": sorted({req_id for req_id in record.get("req", []) if isinstance(req_id, str)})
                        if isinstance(record.get("req", []), list) else [],
                        "migrated_from": canonical_checklist_source(record),
                        "canonical_path": path,
                        "content_hash": f"sha256:{hashes[path]}" if hashes.get(path) else None,
                    }
                    for record, path in zip(tasks, task_paths)
                    if isinstance(record.get("ID"), str)
                ],
            },
            "task_progress": progress_projection(tasks, task_state),
            "checklist_progress": checklist_summary,
            "workpackages": workpackages,
        },
        "requirements": {
            "availability": normalized(requirement_state),
            "total": len(requirements) if available(requirement_state) else None,
            "status_counts": req_counts,
            "items": requirement_items,
        },
        "decisions": {
            "availability": normalized(decision_state),
            "total": len(decisions) if available(decision_state) else None,
            "status_counts": decision_counts,
            "pending_affected_requirements": pending_affected_requirements,
            "items": decision_items,
            "blocked_by_decision": {
                "availability": blocked_by_decision_availability,
                "count": blocked_by_decision_count,
            },
        },
        "verification": {
            "test_contracts": {"availability": normalized(contract_state), "status_counts": contract_counts, "items": contract_items},
            "proof_points": {"availability": normalized(contract_state), "status_counts": proof_counts},
            "plans": {"availability": normalized(plan_state), "status_counts": plan_counts},
            "evidence": {
                "availability": normalized(evidence_state),
                "freshness": evidence_freshness,
                "target_freshness": target_freshness,
                "model_freshness": model_freshness,
                "recorded_counts": evidence_recorded,
                "current_counts": {
                    "verified": None, "unverified": evidence_unverified,
                    "stale": evidence_stale, "failed": evidence_failed, "pending": None,
                },
                "entries": evidence_entries,
            },
        },
        "findings": {
            "availability": normalized(finding_state),
            "open": findings_open,
            "blocking": findings_blocking,
            "closed": findings_closed,
            "resolved": findings_closed - findings_superseded - findings_retired if findings_closed is not None else None,
            "superseded": findings_superseded,
            "retired": findings_retired,
            "decision_required": findings_decision_required,
            "framework_followup": findings_framework_followup,
            "unknown": findings_unknown,
            "items": finding_items,
            "history": finding_history,
        },
        "runtime": {
            "readiness_availability": runtime_availability,
            "recorded_readiness": runtime,
            "operating_mode_availability": "unavailable",
            "operating_mode": None,
        },
        "capabilities": {"availability": "unavailable", "active_count": None},
        "context": context_status,
        "sources": {"availability": "unavailable", "items": []},
        "source_references": {"availability": source_reference_state, "items": source_references},
        "gaps": sorted(gaps, key=lambda gap: (gap["code"], gap["source"] or "", gap["description"])),
    }
    stage_started = time.perf_counter()
    if include_gallery:
        result["verification"]["gallery"] = visual_evidence_projection(
            root, manifests, manifest_paths, active_targets, hashes, gaps, gallery_screen_id
        )
        result["verification"]["gallery_state"] = "available"
        _emit_project_stage("parity_gallery_and_capture_validation", stage_started,
                            runs=len(result["verification"]["gallery"]), hashed_sources=len(hashes),
                            screen_id=gallery_screen_id)
    else:
        result["verification"]["gallery"] = []
        result["verification"]["gallery_state"] = "not_loaded"
        _emit_project_stage("parity_gallery_and_capture_validation", stage_started,
                            runs=0, hashed_sources=len(hashes), state="not_loaded")
    result["gaps"] = sorted(gaps, key=lambda gap: (gap["code"], gap["source"] or "", gap["description"]))
    stage_started = time.perf_counter()
    result["compatibility"] = compatibility_report(root, result, hashes, parsed_documents=parsed_documents)
    result["decisions"]["historical"] = [
        {"id": Path(item["source_path"]).stem, "source_path": item["source_path"]}
        for item in result["compatibility"]["diagnostics"]
        if item["artifact_type"] == "unknown" and item["category"] == "LEGACY_VARIANT"
        and item["affected_board_area"] == "decisions"
    ]
    result["source_fingerprint"] = result["compatibility"]["source_fingerprint"]
    attach_cs4_projections(
        result, root=root, process_doc=process_doc if process_state == "available" else None,
        tasks=result["delivery"]["tasks"]["items"], parity_records=parity_records, parity_paths=parity_paths,
        checklist_paths=checklist_paths, task_records=tasks, hashes=hashes, gaps=gaps,
        parsed_documents=parsed_documents, active_wave_id=active_wave_id, next_action=context_status.get("next_action"),
    )
    result["health"] = {"observation_states": attach_observation_states(result, hashes)}
    result["health"] = build_health(result)
    _emit_project_stage("compatibility_and_fingerprint", stage_started,
                        diagnostics=len(result["compatibility"].get("diagnostics", [])), hashed_sources=len(hashes))
    return result


def build_status(
    project_root: Path,
    *,
    include_gallery: bool = True,
    gallery_screen_id: str | None = None,
) -> dict[str, Any]:
    with schema_validation_scope():
        return _build_status(
            project_root,
            include_gallery=include_gallery,
            gallery_screen_id=gallery_screen_id,
        )


def build_status_summary(project_root: Path) -> dict[str, Any]:
    """Build the complete project status except the lazy screenshot/gallery projection."""
    return build_status(project_root, include_gallery=False)


UI_SETTING_DEFAULTS = {
    "html_first": (False, ("implementation", "html_first"), True),
    "mockup_driven": ("guided", ("verification", "mockup_driven"), True),
    "leave_running_after_visual_verification": (
        True, ("runtime", "leave_running_after_visual_verification"), False,
    ),
}
PAGE_ID_PATTERN = re.compile(r"PAGE-[A-Z0-9][A-Z0-9_-]*\Z")


class ProjectUiConfigError(ValueError):
    """The project UI configuration is malformed or has an invalid value."""


def _ui_mapping(value: Any, label: str) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ProjectUiConfigError(f"{label} must be a mapping")
    return value


def _read_project_ui_config(project_root: Path) -> dict[str, Any]:
    config_path = project_root / "mxagile-project.yaml"
    if not config_path.exists():
        return {}
    try:
        raw = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise ProjectUiConfigError(f"Cannot read {config_path}: {type(exc).__name__}") from exc
    return _ui_mapping(raw, "project configuration")


def _ui_get(mapping: dict[str, Any], key: str, label: str) -> dict[str, Any]:
    return _ui_mapping(mapping.get(key), label)


def _validate_ui_setting(setting: str, value: Any, label: str) -> None:
    if setting in ("html_first", "leave_running_after_visual_verification"):
        if type(value) is not bool:
            raise ProjectUiConfigError(f"{label} must be a boolean")
    elif setting == "mockup_driven" and value not in ("off", "guided", "full"):
        raise ProjectUiConfigError(f"{label} must be off, guided, or full")


def _resolve_ui_setting(setting: str, ui: dict[str, Any], page_id: str | None) -> dict[str, Any]:
    default, path, supports_override = UI_SETTING_DEFAULTS[setting]
    current = ui
    labels = ["ui"]
    for part in path[:-1]:
        labels.append(part)
        current = _ui_get(current, part, ".".join(labels))

    config_key = path[-1]
    config_label = ".".join((*labels, config_key))
    requested = current.get(config_key, default)
    _validate_ui_setting(setting, requested, config_label)
    requested_source = "project_config" if config_key in current else "schema_default"

    override_value = None
    if page_id and supports_override:
        overrides = _ui_get(current, "overrides", ".".join((*labels, "overrides")))
        page_overrides = _ui_mapping(overrides.get(page_id), f"{'.'.join((*labels, 'overrides'))}.{page_id}")
        if config_key in page_overrides:
            override_value = page_overrides[config_key]
            _validate_ui_setting(setting, override_value, f"page override {page_id}.{config_key}")

    has_override = override_value is not None
    return {
        "requested": requested,
        "effective": override_value if has_override else requested,
        "source": "page_override" if has_override else requested_source,
        "requested_source": requested_source,
        "scope": page_id if has_override else "project",
        "override": {"page_id": page_id, "value": override_value} if has_override else None,
    }


def resolve_project_ui_settings(project_root: Path, page_id: str | None = None) -> dict[str, Any]:
    """Resolve canonical UI settings for agent routing and Board projection."""
    if page_id is not None and not PAGE_ID_PATTERN.fullmatch(page_id):
        raise ProjectUiConfigError(f"Invalid canonical page_id: {page_id}")
    config = _read_project_ui_config(project_root)
    ui = _ui_get(config, "ui", "ui")
    return {
        "page_id": page_id,
        "settings": {setting: _resolve_ui_setting(setting, ui, page_id) for setting in UI_SETTING_DEFAULTS},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Emit deterministic MxAgile project-status JSON.")
    parser.add_argument("--project-root", type=Path, default=Path.cwd(), help="Project root (default: current directory).")
    parser.add_argument("--resolve-parity-request", type=Path,
                        help="Resolve one parity record from a JSON request; does not scan the project.")
    parser.add_argument("--resolve-ui-settings", action="store_true",
                        help="Resolve canonical project UI settings without scanning project status.")
    parser.add_argument("--page-id", help="Optional canonical UI inventory page ID for page-scoped overrides.")
    args = parser.parse_args()
    if args.resolve_ui_settings:
        try:
            settings = resolve_project_ui_settings(args.project_root.resolve(), args.page_id)
        except (OSError, ProjectUiConfigError) as exc:
            print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
            return 2
        print(json.dumps(settings, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    if args.resolve_parity_request:
        try:
            request = json.loads(args.resolve_parity_request.read_text(encoding="utf-8-sig"))
            if not isinstance(request, dict):
                raise ValueError("request root must be an object")
            report = request.get("report")
            project_root = Path(request.get("project_root", args.project_root)).resolve()
            resolution = resolve_parity_status(
                report,
                expected_identity=request.get("expected_identity"),
                target_freshness=request.get("target_freshness", "NOT_OBSERVABLE"),
                validated_capture_sides=request.get("validated_capture_sides"),
                validated_source_hashes=validated_contract_source_hashes(project_root, report) if isinstance(report, dict) else {},
            )
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            resolution = {
                "resolver": "build_project_status.resolve_parity_status/v1",
                "status": "UNKNOWN",
                "evidence_class": "NOT_OBSERVABLE",
                "reported_overall_result": None,
                "computed_overall_result": "NOT_VERIFIED",
                "claim_matches": False,
                "promotion_allowed": False,
                "comparison_identity_status": "NOT_OBSERVABLE",
                "target_freshness": "NOT_OBSERVABLE",
                "dimension_results": {},
                "evidence_matrix_results": {},
                "blockers": [{"code": "PARITY_REQUEST_INVALID", "reason": type(exc).__name__}],
            }
        print(json.dumps(resolution, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    try:
        status = build_status(args.project_root)
    except (OSError, ValueError) as exc:
        print(f"project status unavailable: {type(exc).__name__}", file=sys.stderr)
        return 2
    print(json.dumps(status, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())