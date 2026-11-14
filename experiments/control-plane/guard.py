"""Experimental, read-only MxAgile control-plane evaluator.

This module derives decisions from existing Mission/Wave/update artifacts. It does not
persist lifecycle state or execute the operation being evaluated.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft7Validator

_HERE = Path(__file__).resolve().parent
# Installed: .mxagile/tools/control-plane/ next to .mxagile/tools/build_project_status.py; repo: scripts/.
SCRIPTS_DIR = next(
    (candidate for candidate in (_HERE.parent, _HERE.parents[1] / "scripts") if (candidate / "build_project_status.py").is_file()),
    _HERE.parents[1] / "scripts",
)

PRODUCER = "mxagile-control-plane-experiment/0.1"
RECOVERY_BY_SOURCE = {
    ".mxagile/lifecycle.yaml": ("unavailable", "doctor"),
    "planning/mission/mission-state.yaml": ("needs_human", "human_resolution"),
    "planning/lifecycle/process-state.yaml": ("needs_human", "human_resolution"),
    "planning/execution-waves.md": ("needs_human", "human_resolution"),
    "context-epoch": ("unavailable", "resync"),
}
# Update states that leave a persisted transaction; READY is session-derived and never stored.
UPDATE_STATE_RULES = {
    "UPDATE_IN_PROGRESS": ("fail", "resume"),
    "PARTIAL_UPDATE": ("fail", "resume"),
    "UPDATE_FAILED_ROLLED_BACK": ("needs_human", "inspect"),
    "BLOCKED_BEFORE_MUTATION": ("needs_human", "inspect"),
    "UPDATE_INSTALLED_RESTART_REQUIRED": ("unavailable", "resync"),
    "COMPATIBILITY_NOT_VERIFIED": ("unavailable", "doctor"),
}
VERDICTS = {"pass", "fail", "needs_human", "partial", "unavailable"}
OPERATING_MODES = {
    "LIVE-SP-CURRENT",
    "CLOSED-AUTONOM",
    "LIVE-SP-OTHER",
    "AMBIGUOUS-SP-STATE",
    "UNKNOWN",
}
PHASES = {"discovery", "refinement", "ready", "implementing", "verifying", "done"}
PROTECTED_LIFECYCLE_PATHS = (
    ".mxagile/lifecycle.yaml",
    "planning/execution-waves.md",
    "planning/lifecycle/process-state.yaml",
    "planning/mission/mission-state.yaml",
)


@dataclass
class ProjectFacts:
    root: Path
    lifecycle: dict[str, Any] = field(default_factory=dict)
    mission: dict[str, Any] = field(default_factory=dict)
    process_state: dict[str, Any] = field(default_factory=dict)
    context_epoch: dict[str, Any] = field(default_factory=dict)
    update_transaction: dict[str, Any] | None = None
    update_transaction_present: bool = False
    branch: str | None = None
    head: str | None = None
    planned_waves: set[str] = field(default_factory=set)
    migration_state: dict[str, Any] = field(default_factory=dict)
    last_update: dict[str, Any] = field(default_factory=dict)
    core_provenance: dict[str, Any] = field(default_factory=dict)
    projection_status: dict[str, Any] = field(default_factory=dict)
    auxiliary_interruption: dict[str, Any] = field(default_factory=dict)
    doctor_compatibility: str | None = None
    doctor_blocking: list[str] = field(default_factory=list)
    doctor_diagnostics: list[dict[str, Any]] = field(default_factory=list)
    source_fingerprints: list[dict[str, str]] = field(default_factory=list)
    load_issues: list[str] = field(default_factory=list)


def _fingerprint(path: Path, relative: str) -> dict[str, str]:
    return {
        "kind": "canonical_source",
        "reference": relative,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def _load_yaml(
    root: Path,
    relative: str,
    schema_name: str | None,
    issues: list[str],
    fingerprints: list[dict[str, str]],
) -> dict[str, Any]:
    path = root / relative
    if not path.is_file():
        issues.append(f"SOURCE_MISSING:{relative}")
        return {}
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        issues.append(f"SOURCE_UNREADABLE:{relative}:{type(exc).__name__}")
        return {}
    if not isinstance(value, dict):
        issues.append(f"SOURCE_NOT_OBJECT:{relative}")
        return {}
    fingerprints.append(_fingerprint(path, relative))
    if schema_name:
        _validate_schema(root, relative, value, schema_name, issues)
    return value


def _validate_schema(
    root: Path,
    source: str,
    value: dict[str, Any],
    schema_name: str,
    issues: list[str],
) -> None:
    schema_path = root / ".mxagile" / "schemas" / schema_name
    if not schema_path.is_file():
        issues.append(f"SCHEMA_MISSING:{schema_name}")
        return
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        Draft7Validator.check_schema(schema)
        errors = sorted(Draft7Validator(schema).iter_errors(value), key=lambda error: list(error.path))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        issues.append(f"SCHEMA_UNREADABLE:{schema_name}:{type(exc).__name__}")
        return
    for error in errors[:5]:
        location = "/".join(str(part) for part in error.path) or "$"
        issues.append(f"SCHEMA_INVALID:{source}:{location}")


def _git_value(root: Path, *args: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *args],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    value = result.stdout.strip()
    return value if result.returncode == 0 and value else None


def load_project_facts(project_root: str | Path) -> ProjectFacts:
    """Read canonical state and current Git identity; never writes to the project."""
    root = Path(project_root).resolve()
    facts = ProjectFacts(root=root)
    if os.path.lexists(root / '.mxagile/state/runs/auxiliary-interruption.json'):
        try:
            sys.path.insert(0, str(SCRIPTS_DIR))
            from project_compatibility import auxiliary_interruption
            facts.auxiliary_interruption = auxiliary_interruption(root) or {}
        except (OSError, ValueError, ImportError):
            facts.load_issues.append('SOURCE_UNREADABLE:.mxagile/state/runs/auxiliary-interruption.json')
    facts.lifecycle = _load_yaml(root, ".mxagile/lifecycle.yaml", None, facts.load_issues, facts.source_fingerprints)
    # Schema conformance of canonical artifacts is judged by the existing Doctor (with its legacy projection).
    facts.mission = _load_yaml(
        root, "planning/mission/mission-state.yaml", None, facts.load_issues, facts.source_fingerprints
    )
    facts.process_state = _load_yaml(
        root, "planning/lifecycle/process-state.yaml", None, facts.load_issues, facts.source_fingerprints
    )
    migration_path = root / ".mxagile" / "migration" / "state.yaml"
    if migration_path.is_file():
        facts.migration_state = _load_yaml(
            root, ".mxagile/migration/state.yaml", None, facts.load_issues, facts.source_fingerprints
        )
    provenance_path = root / '.mxagile' / 'state' / 'core-provenance.json'
    if provenance_path.is_file():
        try:
            loaded = json.loads(provenance_path.read_text(encoding='utf-8-sig'))
            if not isinstance(loaded, dict) or _parse_time(loaded.get('installed_at')) is None:
                raise ValueError('invalid installation timestamp')
            commit = loaded.get('commit')
            if commit is not None and (not isinstance(commit, str) or not re.fullmatch(r'[a-f0-9]{40}', commit)):
                raise ValueError('invalid installed commit')
            facts.core_provenance = loaded
            facts.source_fingerprints.append(_fingerprint(provenance_path, '.mxagile/state/core-provenance.json'))
        except (OSError, ValueError):
            facts.load_issues.append('SOURCE_UNREADABLE:.mxagile/state/core-provenance.json')
    if str(SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPTS_DIR))
    try:
        from project_compatibility import projection_integrity
        facts.projection_status = projection_integrity(root, facts.core_provenance)
    except (ImportError, OSError, ValueError) as exc:
        facts.projection_status = {'required': bool(facts.core_provenance), 'ready': False, 'reason': f'Projection proof unavailable: {type(exc).__name__}'}
    projection_path = root / '.mxagile' / 'state' / 'projections-manifest.json'
    if projection_path.is_file():
        facts.source_fingerprints.append(_fingerprint(projection_path, '.mxagile/state/projections-manifest.json'))
    handoff_path = root / ".mxagile" / "state" / "last-update-result.json"
    if handoff_path.is_file():
        try:
            loaded = json.loads(handoff_path.read_text(encoding="utf-8-sig"))
            facts.last_update = loaded if isinstance(loaded, dict) else {}
            facts.source_fingerprints.append(_fingerprint(handoff_path, ".mxagile/state/last-update-result.json"))
        except (OSError, ValueError):
            facts.load_issues.append("SOURCE_UNREADABLE:.mxagile/state/last-update-result.json")

    epoch_candidates = (
        ".concord/context-epoch.yaml",
        "planning/lifecycle/context-epoch.yaml",
    )
    epoch_path = next((relative for relative in epoch_candidates if (root / relative).is_file()), None)
    if epoch_path is None:
        facts.load_issues.append("SOURCE_MISSING:context-epoch")
    else:
        facts.context_epoch = _load_yaml(root, epoch_path, None, facts.load_issues, facts.source_fingerprints)

    plan_path = root / "planning" / "execution-waves.md"
    if not plan_path.is_file():
        facts.load_issues.append("SOURCE_MISSING:planning/execution-waves.md")
    else:
        try:
            plan_text = plan_path.read_text(encoding="utf-8")
            facts.planned_waves = {
                match.group(1)
                for match in re.finditer(r"(?im)^\s{0,3}#{1,6}\s+(?:Wave\s+)?(W[0-9]+)\b", plan_text)
            }
            facts.source_fingerprints.append(_fingerprint(plan_path, "planning/execution-waves.md"))
        except OSError:
            facts.load_issues.append("SOURCE_UNREADABLE:planning/execution-waves.md")

    transaction_path = root / ".mxagile" / "state" / "update-transaction.json"
    facts.update_transaction_present = transaction_path.exists()
    if facts.update_transaction_present:
        try:
            transaction = json.loads(transaction_path.read_text(encoding="utf-8"))
            if not isinstance(transaction, dict):
                raise ValueError("not an object")
            _validate_schema(
                root,
                ".mxagile/state/update-transaction.json",
                transaction,
                "update-transaction.schema.json",
                facts.load_issues,
            )
            facts.update_transaction = transaction
            facts.source_fingerprints.append(
                _fingerprint(transaction_path, ".mxagile/state/update-transaction.json")
            )
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            facts.load_issues.append(f"SOURCE_UNREADABLE:update-transaction:{type(exc).__name__}")

    facts.branch = _git_value(root, "rev-parse", "--abbrev-ref", "HEAD")
    facts.head = _git_value(root, "rev-parse", "HEAD")
    if facts.branch is None or facts.head is None:
        facts.load_issues.append("GIT_IDENTITY_UNAVAILABLE")
    _run_doctor(facts)
    return facts


def _run_doctor(facts: ProjectFacts) -> None:
    if str(SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPTS_DIR))
    try:
        from build_project_status import build_status

        report = build_status(facts.root)["compatibility"]
    except Exception as exc:  # the Doctor is advisory input; its failure must not crash the evaluator
        facts.load_issues.append(f"DOCTOR_UNAVAILABLE:{type(exc).__name__}")
        return
    facts.doctor_compatibility = report.get("compatibility")
    facts.doctor_diagnostics = [item for item in report.get('diagnostics', []) if item.get('blocking')]
    facts.doctor_blocking = sorted(
        {str(item.get("category")) for item in report.get("diagnostics", []) if item.get("blocking")}
    )


def _finding(
    code: str,
    summary: str,
    disposition: str,
    reference: str | None = None,
    recovery: str | None = None,
) -> dict[str, str]:
    finding = {"code": code, "summary": summary, "disposition": disposition}
    if reference:
        finding["reference"] = reference
    if recovery:
        finding["recovery"] = recovery
    return finding


def _issue_finding(issue: str) -> dict[str, str]:
    kind, _, source = issue.partition(":")
    source = source.split(":")[0]
    if kind == "SOURCE_MISSING" and source in RECOVERY_BY_SOURCE:
        disposition, recovery = RECOVERY_BY_SOURCE[source]
        return _finding("CANONICAL_SOURCE_MISSING", f"Canonical source is absent: {source}", disposition, source, recovery)
    if kind == "DOCTOR_UNAVAILABLE":
        return _finding("DOCTOR_UNAVAILABLE", "The compatibility Doctor could not run.", "unavailable", recovery="doctor")
    if kind == "GIT_IDENTITY_UNAVAILABLE":
        return _finding("GIT_IDENTITY_UNAVAILABLE", "Current branch/HEAD could not be read.", "unavailable", recovery="inspect")
    return _finding("PROJECT_FACTS_UNAVAILABLE", issue, "fail", recovery="inspect")


def _parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.astimezone()


def _lifecycle_integrity(facts: ProjectFacts) -> tuple[list[dict[str, str]], list[str]]:
    """Migration, update, re-sync and Doctor gates shared by every operation."""
    findings: list[dict[str, str]] = []
    migration = facts.migration_state
    migration_status = migration.get("status", "none") if migration else "none"
    canonicalization = migration.get("artifact_canonicalization", "none") if migration else "none"
    if migration_status not in ('none', 'complete'):
        disposition, recovery = ("fail", "resume") if migration_status == "in_progress" else ("needs_human", "inspect")
        findings.append(_finding("MIGRATION_IN_PROGRESS", f"Framework migration status is {migration_status}.", disposition, ".mxagile/migration/state.yaml", recovery))
    if canonicalization == "in_progress":
        findings.append(_finding("MIGRATION_PARTIAL", "Artifact canonicalization was started and not completed.", "fail", ".mxagile/migration/state.yaml", "resume"))
    elif canonicalization == "pending":
        findings.append(_finding("HYBRID_ARTIFACTS", "Legacy artifacts are not yet canonicalized; hybrid mode is valid.", "advisory", ".mxagile/migration/state.yaml"))

    if facts.projection_status.get('required') and not facts.projection_status.get('ready'):
        findings.append(_finding('PROJECTION_RECOVERY_REQUIRED', facts.projection_status.get('reason') or 'Mandatory projections are incomplete.', 'fail', '.mxagile/state/projections-manifest.json', 'resume_projection'))

    if 'artifact_contract' in facts.core_provenance:
        from project_compatibility import contract_migration_validator, contract_snapshot
        target = facts.core_provenance.get('artifact_contract')
        record = migration.get('contract_migration') or {}
        try:
            schema = json.loads((facts.root / '.mxagile' / 'schemas' / 'contract-migration.schema.json').read_text(encoding='utf-8-sig'))
            valid_record = isinstance(record, dict) and not list(contract_migration_validator(schema).iter_errors(record))
            actual = contract_snapshot(facts.root)
        except (OSError, ValueError):
            valid_record, actual = False, None
        if not target or actual != target:
            findings.append(_finding('CONTRACT_IDENTITY_NOT_OBSERVABLE', 'Current schema identity does not match installed Core provenance.', 'unavailable', recovery='inspect'))
        elif not valid_record or record.get('target') != target:
            findings.append(_finding('CONTRACT_MIGRATION_REQUIRED', 'Historical migration completion is not bound to the installed contract.', 'fail', '.mxagile/migration/state.yaml', 'resume'))
        elif any(item.get('result') == 'PENDING' for item in record.get('resolution_receipts', [])):
            findings.append(_finding('HUMAN_RESOLUTION_RECOVERY_REQUIRED', 'A bound source resolution needs audit finalization.', 'fail', '.mxagile/migration/state.yaml', 'human_resolution'))
        elif record.get('status') != 'COMPLETE':
            human = record.get('status') == 'NEEDS_HUMAN'
            findings.append(_finding('CONTRACT_MIGRATION_NEEDS_HUMAN' if human else 'CONTRACT_MIGRATION_PENDING', f"Current contract reconciliation is {record.get('status')}.", 'needs_human' if human else 'fail', '.mxagile/migration/state.yaml', 'human_resolution' if human else 'resume'))

    transaction_state = "none"
    if facts.update_transaction_present:
        transaction_state = str((facts.update_transaction or {}).get("state", "UNKNOWN"))
        disposition, recovery = UPDATE_STATE_RULES.get(transaction_state, ("needs_human", "inspect"))
        findings.append(_finding("UPDATE_NOT_READY", f"Persisted update transaction is {transaction_state}.", disposition, ".mxagile/state/update-transaction.json", recovery))

    installed_at = _parse_time(facts.core_provenance.get("installed_at"))
    if facts.last_update and not facts.core_provenance:
        findings.append(_finding('UPDATE_IDENTITY_NOT_OBSERVABLE', 'Historical update evidence cannot establish the current installation identity.', 'unavailable', '.mxagile/state/core-provenance.json', 'doctor'))
    if installed_at:
        installed_at = installed_at.replace(microsecond=0)
    checkpoint_at = _parse_time((facts.context_epoch.get("repository") or {}).get("checkpoint_time"))
    interrupted_at = _parse_time(facts.auxiliary_interruption.get('interrupted_at'))
    if interrupted_at and (checkpoint_at is None or checkpoint_at < interrupted_at):
        findings.append(_finding('AUXILIARY_INTERRUPTION_REQUIRES_RESYNC', 'Independent user work interrupted the Delivery context; canonical re-sync is required before resume.', 'unavailable', '.mxagile/state/runs/auxiliary-interruption.json', 'resync'))
    if installed_at and (checkpoint_at is None or checkpoint_at < installed_at):
        findings.append(_finding("CONTEXT_STALE_AFTER_UPDATE", "The framework was updated after the last Context Epoch re-sync.", "unavailable", ".mxagile/state/core-provenance.json", "resync"))

    for receipt in (migration.get('contract_migration') or {}).get('resolution_receipts', []):
        applied_at = _parse_time(receipt.get('applied_at'))
        if receipt.get('result') == 'APPLIED' and applied_at and (checkpoint_at is None or checkpoint_at < applied_at):
            findings.append(_finding('CONTEXT_STALE_AFTER_HUMAN_RESOLUTION', 'Canonical Requirement changed after Context Epoch re-sync.', 'unavailable', receipt['source_path'], 'resync'))
            break

    if facts.doctor_compatibility == "BLOCKED":
        categories = ", ".join(facts.doctor_blocking[:5]) or "unspecified"
        findings.append(_finding("DOCTOR_BLOCKED", f"Current Doctor reports blocking diagnostics: {categories}.", "fail", recovery="doctor"))
    elif facts.doctor_compatibility == "PARTIAL":
        findings.append(_finding("DOCTOR_PARTIAL", "Current Doctor reports non-blocking diagnostics.", "advisory"))
    checked = [
        f"migration:{migration_status}",
        f"canonicalization:{canonicalization}",
        f"update_transaction:{transaction_state}",
        f"doctor:{facts.doctor_compatibility or 'unknown'}",
        f"core_provenance:{'available' if facts.core_provenance else 'not_observable'}",
    ]
    return findings, checked


def _base_checks(
    facts: ProjectFacts, request: dict[str, Any]
) -> tuple[list[dict[str, str]], list[str], dict[str, Any] | None]:
    findings, checked = _lifecycle_integrity(facts)
    findings.extend(_issue_finding(issue) for issue in facts.load_issues)
    if facts.load_issues:
        return findings, checked, None

    mission_id = request.get("mission_id")
    wave_id = request.get("wave_id")
    if not isinstance(mission_id, str) or not isinstance(wave_id, str):
        findings.append(_finding("MISSION_WAVE_REQUIRED", "No canonical Mission/active Wave; no Wave is inferred.", "needs_human", recovery="human_resolution"))
        return findings, checked, None

    if facts.mission.get("mission_id") != mission_id:
        findings.append(_finding("MISSION_MISMATCH", "Request mission does not match canonical Mission state.", "fail"))
    mission_progress = facts.mission.get("progress") or {}
    if mission_progress.get("mission") != "active":
        findings.append(_finding("MISSION_NOT_ACTIVE", "Canonical Mission is not explicitly active.", "fail"))
    if facts.mission.get("active_wave") != wave_id:
        findings.append(_finding("ACTIVE_WAVE_MISMATCH", "Requested Wave is not the canonical active Wave.", "fail"))

    wave = (facts.process_state.get("waves") or {}).get(wave_id)
    if not isinstance(wave, dict):
        findings.append(_finding("WAVE_NOT_REGISTERED", "Wave has no canonical process-state block.", "fail"))
        return findings, checked, None
    if wave_id not in facts.planned_waves:
        findings.append(_finding("WAVE_PLAN_MISSING", "Wave is not registered in execution-waves.md.", "fail"))

    epoch_mission = (facts.context_epoch.get("mission") or {}).get("id")
    if epoch_mission != mission_id:
        findings.append(_finding("EPOCH_MISSION_MISMATCH", "Context Epoch belongs to a different Mission.", "fail", recovery="resync"))
    repository = facts.context_epoch.get("repository") or {}
    if repository.get("branch") != facts.branch:
        findings.append(_finding("BRANCH_STALE", "Current branch differs from the Context Epoch.", "fail", recovery="resync"))
    checkpoint_head = str(repository.get("commit") or "")
    if not checkpoint_head or not (facts.head or "").startswith(checkpoint_head):
        findings.append(_finding("HEAD_STALE", "Current HEAD differs from the Context Epoch.", "fail", recovery="resync"))

    for blocker in facts.mission.get("blockers") or []:
        radius = blocker.get("blast_radius")
        if radius in {"MISSION", "WAVE"}:
            findings.append(
                _finding("MISSION_OR_WAVE_BLOCKER", "A canonical Mission/Wave blocker is open.", "fail")
            )
        elif radius == "REQUIREMENT":
            findings.append(
                _finding(
                    "REQUIREMENT_BLOCKER_SCOPE_UNKNOWN",
                    "A Requirement blocker cannot be mapped to the requested scope deterministically.",
                    "needs_human",
                )
            )

    phase = wave.get("phase")
    if phase not in PHASES:
        findings.append(_finding("WAVE_PHASE_UNKNOWN", "Canonical Wave phase is missing or unknown.", "unavailable"))
    checked.extend([
        f"mission:{mission_progress.get('mission', 'unknown')}",
        f"wave:{phase or 'unknown'}",
        f"context_branch:{repository.get('branch', 'unknown')}",
    ])
    return findings, checked, wave


def _scope_matches(path: str, grants: list[str]) -> bool:
    for grant in grants:
        normalized = grant.replace("\\", "/")
        if normalized.endswith("/") and path.startswith(normalized):
            return True
        if any(character in normalized for character in "*?[") and fnmatch.fnmatchcase(path, normalized):
            return True
        if path == normalized:
            return True
    return False


def _scope_findings(request: dict[str, Any], delivery_context: dict[str, Any]) -> list[dict[str, str]]:
    scope = request.get("scope") or {}
    paths = scope.get("paths") if isinstance(scope, dict) else None
    grants = delivery_context.get("write_scope") or []
    forbidden = delivery_context.get("forbidden_scope") or []
    findings: list[dict[str, str]] = []
    if not isinstance(paths, list) or not paths:
        return [_finding("SCOPE_EMPTY", "Mutation scope must name at least one bounded path or model unit.", "needs_human")]
    for path in paths:
        if not isinstance(path, str) or not path:
            findings.append(_finding("SCOPE_INVALID", "Mutation scope contains an invalid entry.", "fail"))
        elif _scope_matches(path, forbidden):
            findings.append(_finding("SCOPE_FORBIDDEN", f"Requested item is in forbidden scope: {path}", "fail"))
        elif not _scope_matches(path, grants):
            findings.append(_finding("SCOPE_ESCAPE", f"Requested item is outside the authorized write scope: {path}", "fail"))
    return findings


def _authorization_findings(request: dict[str, Any]) -> list[dict[str, str]]:
    authorization = request.get("authorization") or {}
    if authorization.get("status") != "confirmed" or not authorization.get("reference"):
        return [
            _finding(
                "USER_AUTHORIZATION_NOT_OBSERVED",
                "No explicit current-session user authorization reference was supplied.",
                "needs_human",
            )
        ]
    return []


def _gate_result(wave: dict[str, Any], gate_name: str, optional: bool = False) -> list[dict[str, str]]:
    gates = wave.get("gates") or {}
    if optional and gate_name not in gates:
        # Older waves predate the optional gate key; gate_to_ready covered it.
        return [_finding("LEGACY_GATE_NOT_RECORDED", f"{gate_name} is not recorded (older Wave); gate_to_ready is authoritative.", "advisory")]
    gate = gates.get(gate_name) or {}
    if gate.get("result") == "passed":
        return []
    if gate.get("result") == "failed":
        return [_finding("GATE_FAILED", f"Required gate {gate_name} failed.", "fail", f"process-state.yaml#waves.{gate_name}")]
    return [_finding("GATE_NOT_VERIFIED", f"Required gate {gate_name} is not recorded as passed.", "unavailable")]


def _evidence_findings(facts: ProjectFacts, references: Any) -> list[dict[str, str]]:
    if not isinstance(references, list):
        return [_finding("EVIDENCE_UNAVAILABLE", "Evidence references must be an array.", "unavailable")]
    findings: list[dict[str, str]] = []
    for item in references:
        if not isinstance(item, dict) or not isinstance(item.get("path"), str):
            findings.append(_finding("EVIDENCE_REFERENCE_INVALID", "Evidence reference is malformed.", "fail"))
            continue
        relative = item["path"].replace("\\", "/")
        if relative.startswith("/") or re.match(r"^[A-Za-z]:", relative) or ".." in relative.split("/"):
            findings.append(_finding("EVIDENCE_PATH_INVALID", "Evidence path escapes the project root.", "fail"))
            continue
        path = (facts.root / relative).resolve()
        try:
            path.relative_to(facts.root)
        except ValueError:
            findings.append(_finding("EVIDENCE_PATH_INVALID", "Evidence path resolves outside the project root.", "fail"))
            continue
        if not path.is_file():
            findings.append(_finding("EVIDENCE_MISSING", f"Evidence file is missing: {relative}", "unavailable"))
            continue
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != item.get("sha256"):
            findings.append(_finding("EVIDENCE_STALE", f"Evidence fingerprint changed: {relative}", "fail"))
    return findings


def _recovery_plan(facts: ProjectFacts, findings: list[dict[str, str]]) -> dict[str, Any]:
    """Ordered projection of existing findings, never permission to perform a recovery write."""
    by_code = {f['code']: f for f in findings}
    primary = None
    blocker = None
    for code in ('PROJECTION_RECOVERY_REQUIRED', 'UPDATE_NOT_READY', 'MIGRATION_IN_PROGRESS', 'MIGRATION_PARTIAL', 'CONTRACT_IDENTITY_NOT_OBSERVABLE', 'CONTRACT_MIGRATION_REQUIRED', 'HUMAN_RESOLUTION_RECOVERY_REQUIRED', 'CONTRACT_MIGRATION_NEEDS_HUMAN', 'CONTRACT_MIGRATION_PENDING', 'DOCTOR_BLOCKED', 'UPDATE_IDENTITY_NOT_OBSERVABLE'):
        if code in by_code:
            blocker = code
            primary = by_code[code].get('recovery') or 'inspect'
            break
    decisions = [item for item in facts.doctor_diagnostics if item.get('repairability') == 'DECISION_REQUIRED']
    if blocker == 'DOCTOR_BLOCKED' and decisions:
        primary = 'human_resolution'
    if primary is None:
        prerequisite = next((f for f in findings if f['code'] != 'MUTATION_PHASE_BLOCKED' and f.get('recovery') != 'resync'), None)
        if prerequisite:
            primary = prerequisite.get('recovery') or 'inspect'
    if primary is None and any(f.get('recovery') == 'resync' for f in findings):
        primary = 'resync'
    if primary is None:
        primary = next((f.get('recovery') for f in findings if f.get('recovery')), None)
    allowed = ['inspect', 'doctor']
    if primary and primary not in allowed:
        allowed.append(primary)
    return {
        'primary_next_action': primary,
        'allowed_recovery_actions': allowed,
        'blocked_recovery_actions': ['resync'] if findings and primary != 'resync' else [],
        'reason_codes': [f['code'] for f in findings],
        'decision_references': [
            {key: item[key] for key in ('diagnostic_id', 'source_path', 'authority', 'category') if isinstance(item.get(key), str)}
            for item in decisions
        ],
    }


def _finish(
    facts: ProjectFacts,
    request: dict[str, Any],
    gate_type: str,
    findings: list[dict[str, str]],
    checked_states: list[str],
    checked_roles: list[str] | None = None,
    evidence_references: list[dict[str, Any]] | None = None,
    should_findings: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    unique: dict[tuple[str, str], dict[str, str]] = {}
    for finding in findings:
        unique.setdefault((finding["code"], finding["summary"]), finding)
    findings = list(unique.values())
    advisories = [finding for finding in findings if finding.get("disposition") == "advisory"]
    findings = [finding for finding in findings if finding.get("disposition") != "advisory"]
    should_findings = [*(should_findings or []), *advisories]
    dispositions = {finding.get("disposition") for finding in findings}
    if not dispositions:
        verdict = "pass"
    elif "fail" in dispositions:
        verdict = "fail"
    elif "needs_human" in dispositions:
        verdict = "needs_human"
    else:
        verdict = "unavailable"

    request_bytes = json.dumps(request, sort_keys=True, separators=(",", ":")).encode("utf-8")
    input_references = [*facts.source_fingerprints, {
        "kind": "decision_request",
        "reference": str(request.get("request_id") or "inline"),
        "sha256": hashlib.sha256(request_bytes).hexdigest(),
    }]
    scope = request.get("scope") if isinstance(request.get("scope"), dict) else {}
    result = {
        "schema_version": "1.0",
        "gate_id": str(request.get("gate_id") or f"GATE-{gate_type}-{request.get('wave_id', 'unknown')}"),
        "gate_type": gate_type,
        "verdict": verdict,
        "run_id": request.get("run_id"),
        "mission_id": request.get("mission_id"),
        "wave_id": request.get("wave_id"),
        "producer": PRODUCER,
        "input_references": input_references,
        "evidence_references": evidence_references or [],
        "must_findings": findings,
        "recovery_plan": _recovery_plan(facts, findings),
        "should_findings": should_findings or [],
        "scope": {"summary": str(scope.get("summary") or "unspecified"), "paths": list(scope.get("paths") or [])},
        "checked_roles": checked_roles or [],
        "checked_states": sorted(set(checked_states)),
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    }
    schema_path = Path(__file__).with_name("control-plane-verdict.schema.json")
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    errors = list(Draft7Validator(schema).iter_errors(result))
    if errors:
        raise ValueError(f"Generated verdict violates schema: {errors[0].message}")
    return result


def can_transition(facts: ProjectFacts, request: dict[str, Any]) -> dict[str, Any]:
    findings, checked, wave = _base_checks(facts, request)
    if wave is None:
        return _finish(facts, request, "transition", findings, checked)
    target = request.get("target_phase")
    current = (wave or {}).get("phase")
    phase_rule = ((facts.lifecycle.get("lifecycle") or {}).get("phases") or {}).get(current, {})
    forward = set(phase_rule.get("next") or [])
    returns = set(phase_rule.get("returns_to") or [])
    if not isinstance(target, str) or target not in PHASES:
        findings.append(_finding("TARGET_PHASE_INVALID", "Requested lifecycle phase is invalid or absent.", "fail"))
    elif target not in forward | returns:
        findings.append(_finding("TRANSITION_NOT_ALLOWED", f"{current} -> {target} is not declared by lifecycle.yaml.", "fail"))
    elif target in returns and target not in forward:
        findings.extend(_authorization_findings(request))
        if not request.get("reason") or not (request.get("scope") or {}).get("paths"):
            findings.append(_finding("RETURN_SCOPE_REQUIRED", "A return transition needs a reason and bounded affected scope.", "needs_human"))
    elif target == "refinement":
        findings.extend(_gate_result(wave or {}, "gate_to_refinement"))
    elif target == "ready":
        findings.extend(_gate_result(wave or {}, "gate_to_ready"))
        findings.extend(_gate_result(wave or {}, "testability_gate", optional=True))
    elif target == "implementing":
        findings.extend(_gate_result(wave or {}, "gate_to_ready"))
        findings.extend(_gate_result(wave or {}, "testability_gate", optional=True))
        findings.extend(_authorization_findings(request))
    elif target == "verifying":
        completion = request.get("implementation_completion") or {}
        if completion.get("state") != "all_terminal":
            findings.append(_finding("IMPLEMENTATION_NOT_COMPLETE", "Checklist completion is not evidenced as all terminal.", "unavailable"))
        findings.extend(_evidence_findings(facts, completion.get("evidence_references", [])))
    elif target == "done":
        gates = request.get("gate_results") or {}
        for required_gate in ("quality_gate", "ui_verification", "acceptance_gate"):
            if (gates.get(required_gate) or {}).get("result") != "passed":
                findings.append(_finding("EXIT_GATE_NOT_PASSED", f"Exit gate {required_gate} is not evidenced as passed.", "unavailable"))
        refs = [ref for result in gates.values() if isinstance(result, dict) for ref in result.get("evidence_references", [])]
        findings.extend(_evidence_findings(facts, refs))
    checked.append(f"transition:{current or 'unknown'}->{target or 'unknown'}")
    return _finish(facts, request, "transition", findings, checked, evidence_references=request.get("evidence_references", []))


def _validate_delivery_context(
    facts: ProjectFacts, request: dict[str, Any], delivery_context: dict[str, Any]
) -> list[dict[str, str]]:
    schema_path = facts.root / ".mxagile" / "schemas" / "delegation-handoff.schema.json"
    if not schema_path.is_file():
        return [_finding("HANDOFF_SCHEMA_UNAVAILABLE", "Delegation handoff schema is unavailable.", "unavailable")]
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        context_schema = schema["properties"]["delivery_context"]
        errors = list(Draft7Validator(context_schema).iter_errors(delivery_context))
    except (OSError, ValueError, KeyError, json.JSONDecodeError):
        return [_finding("HANDOFF_SCHEMA_INVALID", "Delegation handoff schema could not be loaded.", "unavailable")]
    findings = [_finding("DELIVERY_CONTEXT_INVALID", "Delivery Context does not satisfy its schema.", "fail") for _ in errors[:3]]
    if findings:
        return findings
    if Path(delivery_context["project_root"]).resolve() != facts.root:
        findings.append(_finding("PROJECT_ROOT_MISMATCH", "Delivery Context project root is not the evaluated root.", "fail"))
    if delivery_context.get("mission_id", request.get("mission_id")) != request.get("mission_id"):
        findings.append(_finding("MISSION_MISMATCH", "Delivery Context mission differs from canonical state.", "fail"))
    if delivery_context.get("wave_id") != request.get("wave_id"):
        findings.append(_finding("DELIVERY_WAVE_MISMATCH", "Delivery Context Wave differs from the request.", "fail"))
    if delivery_context.get("branch") != facts.branch:
        findings.append(_finding("DELIVERY_BRANCH_STALE", "Delivery Context branch is stale.", "fail"))
    base_head = str(delivery_context.get("base_head") or "")
    if not facts.head or not facts.head.startswith(base_head):
        findings.append(_finding("DELIVERY_HEAD_STALE", "Delivery Context base HEAD is stale.", "fail"))
    observed_mode = (request.get("observations") or {}).get("operating_mode")
    if observed_mode not in OPERATING_MODES or observed_mode == "UNKNOWN":
        findings.append(_finding("OPERATING_MODE_UNKNOWN", "Current operating mode is not observable.", "unavailable"))
    elif delivery_context.get("operating_mode") != observed_mode:
        findings.append(_finding("OPERATING_MODE_STALE", "Delivery Context operating mode differs from current observation.", "fail"))
    return findings


def can_mutate(facts: ProjectFacts, request: dict[str, Any]) -> dict[str, Any]:
    findings, checked, wave = _base_checks(facts, request)
    if wave is None:
        return _finish(facts, request, "mutation", findings, checked)
    if wave and wave.get("phase") != "implementing":
        findings.append(_finding("MUTATION_PHASE_BLOCKED", "Mutations require the active Wave to be implementing.", "fail"))
    delivery_context = request.get("delivery_context")
    if not isinstance(delivery_context, dict):
        findings.append(_finding("DELIVERY_CONTEXT_MISSING", "A Delivery Context is required for mutation.", "unavailable"))
        delivery_context = {}
    else:
        findings.extend(_validate_delivery_context(facts, request, delivery_context))
    if delivery_context.get("authorization") != "authorized_write":
        findings.append(_finding("WRITE_AUTHORIZATION_MISSING", "Delivery Context does not grant an authorized-write scope.", "fail"))
    findings.extend(_authorization_findings(request))
    if wave:
        eligibility = ((wave.get("prerequisite_state") or {}).get("mutation_eligibility"))
        if request.get("operation") == "model_write" and eligibility in {"blocked", "violation_detected"}:
            findings.append(_finding("MODEL_MUTATION_NOT_ELIGIBLE", f"Model mutation eligibility is {eligibility}.", "fail", recovery="human_resolution"))

    findings.extend(_scope_findings(request, delivery_context))
    observations = request.get("observations") or {}
    if observations.get("project_identity_confirmed") is not True:
        findings.append(_finding("PROJECT_IDENTITY_UNCONFIRMED", "The current operation is not bound to the intended project identity.", "needs_human"))
    operation = request.get("operation")
    mode = observations.get("operating_mode")
    if mode not in OPERATING_MODES or mode in {"UNKNOWN", "AMBIGUOUS-SP-STATE"}:
        findings.append(_finding("OPERATING_MODE_UNUSABLE", "Mutation route cannot be selected from the current operating-mode evidence.", "needs_human"))
    elif operation == "model_write":
        route = observations.get("tool_route") or {}
        route_name = route.get("id")
        allowed_route = {
            "LIVE-SP-CURRENT": {"studio_pro_mcp", "concord_mcp"},
            "CLOSED-AUTONOM": {"mxcli"},
            "LIVE-SP-OTHER": {"mxcli"},
        }[mode]
        if route_name not in allowed_route or route.get("state") != "supported":
            findings.append(_finding("MODEL_TOOL_ROUTE_UNAVAILABLE", "No supported model-write route matches the operating mode.", "fail"))
        elif route.get("same_project") is not True:
            findings.append(_finding("MODEL_PROJECT_IDENTITY_UNCONFIRMED", "The model-write route is not confirmed for this project.", "needs_human"))
        elif route_name == "concord_mcp" and (mode != "LIVE-SP-CURRENT" or route.get("read_only_probe_succeeded") is not True):
            findings.append(_finding("CONCORD_FALLBACK_UNVERIFIED", "Concord fallback lacks the required same-project read-only probe.", "fail"))
    elif operation == "runtime_write":
        findings.append(_finding("RUNTIME_WRITE_NOT_IMPLEMENTED", "Runtime ownership/lease enforcement is outside this Phase 1 prototype.", "unavailable"))
    elif operation != "file_write":
        findings.append(_finding("OPERATION_UNSUPPORTED", "Operation type is not supported by this prototype.", "unavailable"))

    checked.append(f"mutation:{operation or 'unknown'}")
    return _finish(facts, request, "mutation", findings, checked, evidence_references=request.get("evidence_references", []))


def _safe_project_file(root: Path, relative: str) -> Path | None:
    if not relative or Path(relative).is_absolute() or re.match(r"^[A-Za-z]:", relative):
        return None
    if ".." in relative.replace("\\", "/").split("/"):
        return None
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        return None
    return candidate


def _verify_source_fingerprints(facts: ProjectFacts, references: Any) -> list[dict[str, str]]:
    if not isinstance(references, list):
        return [_finding("SOURCE_FINGERPRINTS_MISSING", "Source fingerprints are not an array.", "unavailable")]
    findings: list[dict[str, str]] = []
    for reference in references:
        path_value = reference.get("path") if isinstance(reference, dict) else None
        expected = reference.get("sha256") if isinstance(reference, dict) else None
        path = _safe_project_file(facts.root, str(path_value or ""))
        if path is None or not path.is_file():
            findings.append(_finding("SOURCE_REFERENCE_UNAVAILABLE", "A fingerprinted source path is unavailable or unsafe.", "unavailable"))
            continue
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            findings.append(_finding("SOURCE_FINGERPRINT_STALE", f"Source changed since routing: {path_value}", "fail"))
    return findings


def _protected_child_scope(paths: list[str]) -> bool:
    return any(_scope_matches(protected, paths) for protected in PROTECTED_LIFECYCLE_PATHS)


def delivery_authorization(facts: ProjectFacts, operation_class: str, request_id: str = "host-pretool", *, require_implementing: bool = True) -> dict[str, Any]:
    """Delivery authorization derived only from canonical state; used by host enforcement adapters."""
    request = {
        "request_id": request_id,
        "gate_id": f"GATE-mutation-{operation_class}",
        "mission_id": facts.mission.get("mission_id"),
        "wave_id": facts.mission.get("active_wave"),
    }
    findings, checked, wave = _base_checks(facts, request)
    if require_implementing and wave is not None and wave.get("phase") != "implementing":
        # An implementing phase is the canonical record of the developer's explicit approval.
        findings.append(_finding("MUTATION_PHASE_BLOCKED", f"Active Wave is {wave.get('phase')}; implementation writes require implementing.", "fail", recovery="human_resolution"))
    findings.append(_finding("MODEL_SCOPE_NOT_OBSERVABLE", "Per-unit Mendix model scope is not observable at the host tool boundary.", "advisory"))
    findings.append(_finding("PROJECT_IDENTITY_NOT_OBSERVED", "Tool-route project identity is not verified by the host adapter.", "advisory"))
    checked.append(f"operation_class:{operation_class}")
    return _finish(facts, request, "mutation", findings, checked)


def can_delegate(facts: ProjectFacts, request: dict[str, Any]) -> dict[str, Any]:
    findings, checked, wave = _base_checks(facts, request)
    if wave is None:
        return _finish(facts, request, "delegation", findings, checked)
    route_reference = request.get("route_decision_reference")
    route_path = _safe_project_file(facts.root, str(route_reference or ""))
    route_decision: dict[str, Any] = {}
    if route_path is None or not route_path.is_file():
        findings.append(_finding("ROUTE_DECISION_UNAVAILABLE", "Persisted routing decision is missing or unsafe.", "unavailable"))
    else:
        try:
            route_decision = json.loads(route_path.read_text(encoding="utf-8"))
            route_schema_path = facts.root / ".mxagile" / "schemas" / "routing-decision.schema.json"
            route_schema = json.loads(route_schema_path.read_text(encoding="utf-8"))
            errors = list(Draft7Validator(route_schema).iter_errors(route_decision))
            if errors:
                findings.append(_finding("ROUTE_DECISION_INVALID", "Persisted routing decision does not satisfy its schema.", "fail"))
            else:
                findings.extend(_verify_source_fingerprints(facts, route_decision.get("source_fingerprints")))
                facts.source_fingerprints.append(_fingerprint(route_path, str(route_reference).replace("\\", "/")))
        except (OSError, ValueError, json.JSONDecodeError):
            findings.append(_finding("ROUTE_DECISION_INVALID", "Persisted routing decision could not be parsed.", "unavailable"))

    handoff = request.get("handoff")
    if not isinstance(handoff, dict):
        findings.append(_finding("HANDOFF_MISSING", "A bounded delegation handoff is required.", "unavailable"))
        handoff = {}
    else:
        handoff_schema_path = facts.root / ".mxagile" / "schemas" / "delegation-handoff.schema.json"
        try:
            handoff_schema = json.loads(handoff_schema_path.read_text(encoding="utf-8"))
            errors = list(Draft7Validator(handoff_schema).iter_errors(handoff))
            if errors:
                findings.append(_finding("HANDOFF_INVALID", "Handoff does not satisfy the canonical schema.", "fail"))
        except (OSError, ValueError, json.JSONDecodeError):
            findings.append(_finding("HANDOFF_SCHEMA_UNAVAILABLE", "Delegation handoff schema could not be loaded.", "unavailable"))
        findings.extend(_verify_source_fingerprints(facts, handoff.get("source_fingerprints")))
        facts.source_fingerprints.append({
            "kind": "handoff_payload",
            "reference": str(handoff.get("delegation_id") or "inline"),
            "sha256": hashlib.sha256(json.dumps(handoff, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest(),
        })

    if route_decision.get("route") != "DELEGATE" or route_decision.get("mission_id") != request.get("mission_id"):
        findings.append(_finding("ROUTE_NOT_AUTHORIZED", "Persisted route does not authorize delegation for this Mission.", "fail"))
    if route_decision.get("capability_state") != "supported" or route_decision.get("spawn_outcome") != "pending":
        findings.append(_finding("SPAWN_NOT_VERIFIED", "Route is not pending with supported spawn capability.", "unavailable"))
    if handoff.get("mission_id") != request.get("mission_id") or handoff.get("agent_type") != route_decision.get("requested_agent_type"):
        findings.append(_finding("HANDOFF_ROUTE_MISMATCH", "Handoff Mission or agent type differs from the persisted route.", "fail"))
    if (handoff.get("scope") or {}) != (route_decision.get("scope") or {}):
        findings.append(_finding("HANDOFF_SCOPE_MISMATCH", "Handoff scope differs from the persisted routing decision.", "fail"))
    if wave:
        context = handoff.get("delivery_context") or {}
        findings.extend(_validate_delivery_context(facts, request, context))
        write_classes = set(handoff.get("write_classes") or [])
        if "LIFECYCLE_WRITE" in write_classes:
            findings.append(_finding("LIFECYCLE_AUTHORITY_DELEGATED", "Lifecycle writes cannot be delegated to a child.", "fail"))
        if context.get("authorization") == "authorized_write":
            mutation_request = {
                **request,
                "scope": handoff.get("scope"),
                "delivery_context": context,
                "operation": request.get("operation", "file_write"),
            }
            mutation_result = can_mutate(facts, mutation_request)
            findings.extend(mutation_result["must_findings"])
        elif context.get("authorization") == "read_only":
            if write_classes - {"EVIDENCE_WRITE"}:
                findings.append(_finding("READ_ONLY_CHILD_WRITE_CLASS", "A read-only child may only hold EVIDENCE_WRITE.", "fail"))
            destination = str(handoff.get("evidence_destination") or "").rstrip("/") + "/"
            for path in context.get("write_scope") or []:
                if "EVIDENCE_WRITE" not in write_classes or destination == "/" or not str(path).startswith(destination):
                    findings.append(_finding("EVIDENCE_SCOPE_ESCAPE", f"Write scope is outside the evidence destination: {path}", "fail"))
            bounded_reads = set(handoff.get("artifact_paths") or []) | {
                item.get("path") for item in [*(handoff.get("source_fingerprints") or []), *(handoff.get("input_sources") or [])]
                if isinstance(item, dict)
            }
            for path in (handoff.get("scope") or {}).get("paths") or []:
                if path not in bounded_reads:
                    findings.append(_finding("READ_SCOPE_UNBOUND", f"Read-only child scope is not bound to a referenced artifact: {path}", "fail"))
        scope_paths = (handoff.get("delivery_context") or {}).get("write_scope") or []
        if _protected_child_scope(scope_paths):
            findings.append(_finding("LIFECYCLE_AUTHORITY_DELEGATED", "Child write scope includes canonical lifecycle authority.", "fail"))

    observations = request.get("observations") or {}
    if observations.get("spawn_tool_visible") is not True:
        disposition = "fail" if observations.get("spawn_tool_visible") is False else "unavailable"
        findings.append(_finding("SPAWN_TOOL_NOT_OBSERVED", "The active session has not confirmed a usable spawn tool.", disposition))
    checked.append("delegation:parent-context-preserved")
    return _finish(
        facts,
        request,
        "delegation",
        findings,
        checked,
        checked_roles=[str(handoff.get("agent_type"))] if handoff.get("agent_type") else [],
        should_findings=[_finding("PARENT_RETAINED_AUTHORITY", "The parent must retain lifecycle, gate, conflict, and user-decision authority.", "advisory")],
    )


def evaluate(project_root: str | Path, request: dict[str, Any]) -> dict[str, Any]:
    facts = load_project_facts(project_root)
    gate_type = request.get("gate_type")
    if gate_type == "transition":
        return can_transition(facts, request)
    if gate_type == "mutation":
        return can_mutate(facts, request)
    if gate_type == "delegation":
        return can_delegate(facts, request)
    return _finish(
        facts,
        request,
        "transition",
        [_finding("GATE_TYPE_INVALID", "gate_type must be transition, mutation, or delegation.", "fail")],
        [],
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--request", required=True, help="JSON decision request")
    args = parser.parse_args(argv)
    try:
        request = json.loads(Path(args.request).read_text(encoding="utf-8"))
        if not isinstance(request, dict):
            raise ValueError("request must be a JSON object")
        result = evaluate(args.project_root, request)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"error": "CONTROL_PLANE_REQUEST_INVALID", "message": str(exc)}))
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return {"pass": 0, "fail": 1, "needs_human": 2, "partial": 3, "unavailable": 4}[result["verdict"]]


if __name__ == "__main__":
    raise SystemExit(main())