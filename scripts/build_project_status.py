"""Build a deterministic, read-only MxAgile project-status projection."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any

import yaml

from project_compatibility import compatibility_report, identity_matches, load_yaml, schema_errors

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
SHA256_PATTERN = "sha256:"


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
        value = load_yaml(raw.decode("utf-8-sig"))
    except yaml.YAMLError as exc:
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
    try:
        content_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return normalized, None, "unknown"
    return normalized, f"sha256:{content_hash}", "available"


def _authority_source(source_type: str, canonical_path: str, hashes: dict[str, str]) -> dict[str, Any]:
    digest = hashes.get(canonical_path)
    return {
        "source_type": source_type,
        "canonical_path": canonical_path,
        "content_hash": f"sha256:{digest}" if digest else None,
    }


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
            root, derived_path, ("planning/target-mockups/",)
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
                "section_ids": [],
            }
            legacy_by_target[reference_key] = reference
        elif reference["availability"] != "available" or path_state != "available":
            reference["availability"] = "unknown"
        page_id = page.get("page_id")
        if isinstance(page_id, str) and page_id not in reference["screen_ids"]:
            reference["screen_ids"].append(page_id)
            target_by_screen[page_id] = reference
        for section in page.get("sections", []) if isinstance(page.get("sections"), list) else []:
            if isinstance(section, dict) and isinstance(section.get("id"), str) and section["id"] not in reference["section_ids"]:
                reference["section_ids"].append(section["id"])
        reference["authority_sources"].append(_authority_source("ui_inventory", page_path, hashes))
        if canonical_path and content_hash:
            hashes[canonical_path] = content_hash.removeprefix(SHA256_PATTERN)

    for reference in legacy_by_target.values():
        reference["screen_ids"].sort()
        reference["section_ids"].sort()
        reference["authority_sources"].sort(key=lambda source: source["canonical_path"])
        targets.append(reference)
        if reference["availability"] != "available":
            add_gap(gaps, "SINGLE_FILE_TARGET_UNAVAILABLE", reference["canonical_path"], "Explicit UI-inventory target path is missing or unavailable.")

    targets.sort(key=lambda item: (item["mockup_name"] or "", item["canonical_path"] or "", item["revision_id"] or ""))
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

    requirement_state, requirements, requirement_paths = read_collection(root, "requirements", "*.yml", "ID", hashes, gaps)
    task_state, tasks, task_paths = read_collection(root, "planning/tasks", "*.yml", "ID", hashes, gaps)
    decision_state, decisions, decision_paths = read_collection(root, "planning/decisions", "*.yml", "ID", hashes, gaps)
    finding_state, finding_records, finding_paths = read_collection(root, "planning/findings", "*.yml", "ID", hashes, gaps)
    contract_state, contracts, contract_paths = read_collection(root, "planning/test-contracts", "*.yaml", "ID", hashes, gaps)
    plan_state, plans, plan_paths = read_collection(root, "planning/verification-plans", "*.yaml", "ID", hashes, gaps)
    page_state, pages, page_paths = read_collection(root, "planning/ui-inventory", "*.yaml", "", hashes, gaps)
    evidence_state, manifests, manifest_paths = read_collection(
        root, "planning/evidence/manifests", "*-evidence-manifest.yaml", "", hashes, gaps
    )
    revision_state, revisions, revision_paths = read_collection(
        root, "planning/target-mockups", "*/_history/REV-*/revision.yaml", "revision_id", hashes, gaps
    )
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
                    hashes[relative] = hashlib.sha256(checklist_path.read_bytes()).hexdigest()
                except OSError:
                    add_gap(gaps, "CHECKLIST_UNREADABLE", relative, "A checklist source could not be fingerprinted.")
                    continue
                checklist_paths.append(relative)
        else:
            add_gap(gaps, "CHECKLIST_PATH_INVALID", "planning/checklists", "Checklist directory is not safely contained in the project root.")

    wave_state, waves, wave_counts = wave_projection(process_doc if process_state == "available" else None)
    waves, checklist_summary, workpackages = delivery_projection(task_state, tasks, waves, checklist_paths, gaps)
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
    findings_unknown: int | None = 0 if available(finding_state) else None
    finding_items: list[dict[str, Any]] = []
    if available(finding_state):
        for finding, path in zip(finding_records, finding_paths):
            lifecycle_status = finding.get("lifecycle_status")
            known_status = lifecycle_status in (
                "DETECTED", "CLASSIFIED", "REPAIR_PROPOSED", "REPAIR_ACCEPTED",
                "REPAIRED", "VERIFIED", "REPAIR_REJECTED", "DECISION_REQUIRED",
            )
            if not known_status:
                findings_unknown = int(findings_unknown or 0) + 1
                add_gap(gaps, "FINDING_STATUS_UNKNOWN", path, "Finding uses an unknown lifecycle status.")
            elif lifecycle_status == "VERIFIED":
                findings_closed = int(findings_closed or 0) + 1
            else:
                findings_open = int(findings_open or 0) + 1
            severity = finding.get("severity")
            blocking = severity == "CRITICAL" or lifecycle_status == "DECISION_REQUIRED"
            if blocking and known_status and lifecycle_status != "VERIFIED":
                findings_blocking = int(findings_blocking or 0) + 1
            finding_items.append({
                "id": finding.get("ID"),
                "title": finding.get("title"),
                "gap_type": finding.get("gap_type") if isinstance(finding.get("gap_type"), str) else None,
                "severity": severity if isinstance(severity, str) else None,
                "lifecycle_status": lifecycle_status if isinstance(lifecycle_status, str) else None,
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
            })

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
        return canonical_reference(root, value, ("planning/checklists/",))[0]

    result = {
        "schema_version": 2,
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
            "unknown": findings_unknown,
            "items": finding_items,
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
    result["compatibility"] = compatibility_report(root, result, hashes)
    result["decisions"]["historical"] = [
        {"id": Path(item["source_path"]).stem, "source_path": item["source_path"]}
        for item in result["compatibility"]["diagnostics"]
        if item["artifact_type"] == "unknown" and item["category"] == "LEGACY_VARIANT"
        and item["affected_board_area"] == "decisions"
    ]
    result["source_fingerprint"] = result["compatibility"]["source_fingerprint"]
    return result


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