"""Deterministic compatibility diagnostics; never a lifecycle authority."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from functools import lru_cache
from pathlib import Path, PurePosixPath
from typing import Any

import yaml

try:
    import jsonschema
except ImportError:
    jsonschema = None


CONTRACTS = (
    ('mxagile-project.yaml', 'mxagile-project', 'project'),
    ('planning/lifecycle/process-state.yaml', 'process-state', 'waves'),
    ('planning/mission/mission-state.yaml', 'mission-state', 'mission'),
    ('planning/lifecycle/context-epoch.yaml', 'context-epoch', 'context'),
    ('requirements/*.yml', 'requirement', 'requirements'),
    ('specs/*.yml', 'spec', 'requirements'),
    ('planning/tasks/*.yml', 'task', 'tasks'),
    ('planning/decisions/*.yml', 'decision', 'decisions'),
    ('planning/findings/*.yml', 'finding', 'findings'),
    ('planning/test-contracts/*.yaml', 'test-contract', 'verification'),
    ('planning/verification-plans/*.yaml', 'verification-plan', 'verification'),
    ('planning/ui-inventory/*.yaml', 'page', 'references'),
    ('planning/evidence/manifests/*-evidence-manifest.yaml', 'evidence-manifest', 'verification'),
    ('planning/target-mockups/*/_history/REV-*/revision.yaml', 'revision', 'references'),
)
SCHEMA_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_ROOT = SCHEMA_ROOT / 'schemas' if SCHEMA_ROOT.name == '.mxagile' else SCHEMA_ROOT / '.mxagile/schemas'


class CanonicalLoader(yaml.SafeLoader):
    def construct_mapping(self, node: Any, deep: bool = False) -> dict:
        self.flatten_mapping(node)
        result = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                duplicate = key in result
            except TypeError:
                raise yaml.constructor.ConstructorError(None, None, 'invalid mapping key', key_node.start_mark) from None
            if duplicate:
                raise yaml.constructor.ConstructorError(None, None, 'duplicate mapping key', key_node.start_mark)
            result[key] = self.construct_object(value_node, deep=deep)
        return result


def load_yaml(raw: str | bytes) -> Any:
    return yaml.load(raw, Loader=CanonicalLoader)


def digest(raw: bytes) -> str:
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def contract_for(relative: str) -> tuple[str, str] | None:
    return next(((schema, area) for pattern, schema, area in CONTRACTS if PurePosixPath(relative).match(pattern)), None)


def safe_file(root: Path, relative: str) -> Path | None:
    if not isinstance(relative, str) or not relative or '\\' in relative or ':' in relative or '%' in relative:
        return None
    parts = relative.split('/')
    if any(part in ('', '.', '..') or part.startswith('.env') for part in parts):
        return None
    current = root
    for part in parts:
        current = current / part
        if current.is_symlink():
            return None
    try:
        current.resolve().relative_to(root.resolve())
    except (OSError, ValueError):
        return None
    return current if current.is_file() else None


def identity_matches(relative: str, identity: Any, expected: str) -> bool:
    if identity == expected:
        return True
    return bool(
        relative.startswith('planning/test-contracts/')
        and isinstance(identity, str) and re.fullmatch(r'TC-[0-9]{3,}', identity)
        and re.fullmatch(re.escape(identity) + r'-[A-Za-z0-9][A-Za-z0-9_-]*', expected)
    )


@lru_cache(maxsize=32)
def load_schema(path: str, modified: int, size: int) -> dict:
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def schema_errors(relative: str, value: Any) -> list[str]:
    contract = contract_for(relative)
    if not contract:
        return []
    if jsonschema is None:
        return ['VALIDATOR_UNAVAILABLE']
    schema_path = SCHEMA_ROOT / (contract[0] + '.schema.json')
    if not schema_path.is_file():
        return ['SCHEMA_UNAVAILABLE']
    try:
        stat = schema_path.stat()
        schema = load_schema(str(schema_path), stat.st_mtime_ns, stat.st_size)
        validator = jsonschema.Draft7Validator(schema)
        return sorted({str(error.validator) for error in validator.iter_errors(value)})
    except (OSError, ValueError, jsonschema.exceptions.SchemaError):
        return ['SCHEMA_UNAVAILABLE']


def assignment(root: Path, task: dict, waves: set[str]) -> tuple[str, str | None, str | None]:
    provenance = task.get('migrated_from')
    if not isinstance(provenance, str):
        return ('explicit', task['wave_id'], None) if isinstance(task.get('wave_id'), str) and task['wave_id'] in waves else ('missing', None, None)
    match = re.fullmatch(r'planning/checklists/(W[A-Za-z0-9_-]+)-implementation-checklist\.yaml', provenance)
    path = safe_file(root, provenance) if match else None
    if path is None or match is None:
        return 'ambiguous', None, None
    try:
        checklist = load_yaml(path.read_text(encoding='utf-8-sig'))
    except (OSError, UnicodeError, yaml.YAMLError):
        return 'ambiguous', None, provenance
    wave = match.group(1)
    if not isinstance(checklist, dict) or wave not in waves:
        return 'ambiguous', None, provenance
    declared = checklist.get('wave_id', checklist.get('wave'))
    if declared is not None and declared != wave:
        return 'conflict', None, provenance
    explicit = task.get('wave_id')
    if explicit is not None:
        return ('explicit', explicit, provenance) if explicit == wave else ('conflict', None, provenance)
    return 'derived', wave, provenance


def compatibility_report(root: Path, status: dict, hashes: dict[str, str]) -> dict:
    diagnostics: list[dict] = []
    coverage: dict[str, dict[str, int]] = {}
    documents: dict[str, dict] = {}

    def add(category: str, source: str | None, area: str, message: str, *,
            blocking: bool = False, repairability: str = 'UNSUPPORTED', repair: str | None = None,
            line: int | None = None, column: int | None = None, authority: str | None = None,
            severity: str = 'WARNING') -> None:
        identity = json.dumps([category, source, area, line, column, repair], sort_keys=True)
        entry = {
            'diagnostic_id': 'DX-' + hashlib.sha256(identity.encode()).hexdigest()[:16],
            'severity': 'ERROR' if blocking else severity, 'category': category,
            'source_path': source, 'line': line, 'column': column,
            'artifact_type': (contract_for(source) or ('unknown', area))[0] if source else 'unknown',
            'affected_board_area': area, 'message': message, 'repairability': repairability,
            'proposed_repair_type': repair, 'authority': authority,
            'blocking': blocking,
        }
        if not any(item['diagnostic_id'] == entry['diagnostic_id'] for item in diagnostics):
            diagnostics.append(entry)

    gap_categories = {
        'SOURCE_PARSE_FAILED': 'SYNTAX_ERROR', 'SOURCE_SHAPE_INVALID': 'SCHEMA_ERROR',
        'SOURCE_PATH_INVALID': 'UNSUPPORTED_VARIANT', 'ARTIFACT_ID_MISMATCH': 'ID_MISMATCH',
        'DUPLICATE_ID': 'DUPLICATE_ID', 'LEGACY_FILENAME': 'LEGACY_VARIANT',
    }
    for gap in status['gaps']:
        source = gap.get('source')
        if gap['code'] in gap_categories:
            category = gap_categories[gap['code']]
            contract = contract_for(source) if source else None
            repairable = 'AGENT_REPAIRABLE' if category in ('SYNTAX_ERROR', 'SCHEMA_ERROR') else 'UNSUPPORTED'
            add(category, source, contract[1] if contract else 'sources',
                'Canonical artifact is invalid.' if category != 'LEGACY_VARIANT' else 'Documented descriptive Test Contract filename accepted.',
                blocking=category != 'LEGACY_VARIANT', repairability=repairable,
                line=gap.get('line'), column=gap.get('column'),
                authority='.mxagile/policies/project-compatibility.md',
                severity='INFO' if category == 'LEGACY_VARIANT' else 'WARNING')
        elif 'AMBIGUOUS' in gap['code'] or 'MULTIPLE_ACTIVE' in gap['code']:
            add('AUTHORITY_CONFLICT', source, 'references', 'Reference authority is ambiguous.', blocking=True,
                repairability='DECISION_REQUIRED', authority='ACTIVE_TARGET')
        elif gap['code'] in ('MODEL_FRESHNESS_UNAVAILABLE', 'CONTEXT_SESSION_STATE_UNAVAILABLE', 'OPERATING_MODE_UNAVAILABLE', 'CAPABILITY_SESSION_STATE_UNAVAILABLE'):
            add('FRESHNESS_UNKNOWN', None, 'session', 'Current machine/session or model evidence is not durably attested.', severity='INFO')
        elif gap['code'].endswith('_UNAVAILABLE') and source and source.startswith('planning/'):
            if source not in hashes:
                add('MISSING', source, (contract_for(source) or ('unknown', 'sources'))[1],
                    'Projection source is missing; installation does not establish compatibility.')
        elif 'DRIFT' in gap['code'] or 'STALE' in gap['code']:
            add('STALE', source, 'references', 'Recorded reference differs from current canonical authority.')

    if jsonschema is None:
        add('UNSUPPORTED_VARIANT', None, 'schemas', 'JSON Schema validator unavailable; install the distributed requirements before retrying.', blocking=True)

    paths = sorted(path for path in hashes if not path.startswith('!') and contract_for(path))
    for relative in paths:
        contract = contract_for(relative)
        counts = coverage.setdefault(contract[0], {'recognized': 0, 'parsed': 0, 'invalid': 0, 'unassigned': 0})
        counts['recognized'] += 1
        path = safe_file(root, relative)
        if path is None:
            counts['invalid'] += 1
            continue
        try:
            raw = path.read_bytes()
            if hashlib.sha256(raw).hexdigest() != hashes[relative]:
                add('AUTHORITY_CONFLICT', relative, contract[1], 'Source changed during diagnosis; rerun Doctor.', blocking=True)
                continue
            value = json.loads(raw.decode('utf-8-sig')) if path.suffix == '.json' else load_yaml(raw.decode('utf-8-sig'))
        except (OSError, UnicodeError, ValueError, yaml.YAMLError):
            counts['invalid'] += 1
            continue
        if not isinstance(value, dict):
            counts['invalid'] += 1
            continue
        counts['parsed'] += 1
        documents[relative] = value
        errors = schema_errors(relative, value)
        if errors:
            counts['invalid'] += 1
            add('SCHEMA_ERROR', relative, contract[1], 'Schema constraints failed: ' + ', '.join(errors) + '.',
                blocking=True, repairability='AGENT_REPAIRABLE', authority=f'.mxagile/schemas/{contract[0]}.schema.json')

    identities: dict[str, list[str]] = {}
    for relative, value in documents.items():
        if isinstance(value.get('ID'), str):
            identities.setdefault(value['ID'], []).append(relative)
    for paths_for_id in identities.values():
        if len(paths_for_id) > 1:
            for relative in paths_for_id:
                add('DUPLICATE_ID', relative, contract_for(relative)[1], 'ID occurs in multiple canonical artifacts.',
                    blocking=True, repairability='DECISION_REQUIRED')

    waves_doc = documents.get('planning/lifecycle/process-state.yaml', {}).get('waves', {})
    waves = set(waves_doc) if isinstance(waves_doc, dict) else set()
    reference_fields = ('req', 'requirement_ids', 'affected_requirements', 'decision_ids', 'depends_on', 'test_contract_ids')
    for relative, value in documents.items():
        area = contract_for(relative)[1]
        for field in reference_fields:
            refs = value.get(field, [])
            if not isinstance(refs, list):
                continue
            if any(not isinstance(ref, str) or ref not in identities for ref in refs):
                add('REFERENCE_MISSING', relative, area, 'An artifact ID reference has no unique canonical target.',
                    blocking=True, repairability='AGENT_REPAIRABLE', authority=field)
            elif any(len(identities[ref]) != 1 for ref in refs):
                add('REFERENCE_AMBIGUOUS', relative, area, 'An artifact ID reference has multiple canonical targets.',
                    blocking=True, repairability='DECISION_REQUIRED', authority=field)
        for field in ('spec', 'test_contract', 'test_contract_id'):
            ref = value.get(field)
            if isinstance(ref, str):
                reference_path = f'specs/{ref}.yml' if field == 'spec' else None
                if ref not in identities and not (reference_path and re.fullmatch(r'SPEC-[0-9]{3,}', ref) and safe_file(root, reference_path)):
                    add('REFERENCE_MISSING', relative, area, 'A parent artifact reference is missing.',
                        blocking=True, repairability='AGENT_REPAIRABLE', authority=field)
                elif reference_path:
                    reference_file = safe_file(root, reference_path)
                    if reference_file:
                        try:
                            raw_spec = reference_file.read_bytes()
                            hashes[reference_path] = hashlib.sha256(raw_spec).hexdigest()
                            spec = load_yaml(raw_spec.decode('utf-8-sig'))
                            valid_spec = isinstance(spec, dict) and spec.get('ID') == ref and not schema_errors(reference_path, spec)
                            if valid_spec:
                                valid_spec = all(isinstance(identity, str) and len(identities.get(identity, [])) == 1 for identity in spec.get('requirements', []))
                        except (OSError, UnicodeError, yaml.YAMLError):
                            valid_spec = False
                        if not valid_spec:
                            add('REFERENCE_AMBIGUOUS', relative, area, 'Referenced Spec is invalid or its ID/requirements do not agree.',
                                blocking=True, repairability='AGENT_REPAIRABLE', authority=reference_path)
        if contract_for(relative)[0] == 'verification-plan':
            targets = identities.get(value.get('test_contract_id'), []) if isinstance(value.get('test_contract_id'), str) else []
            if len(targets) == 1:
                points = documents[targets[0]].get('proof_points', [])
                point_ids = {point.get('id') for point in points if isinstance(point, dict) and isinstance(point.get('id'), str)} if isinstance(points, list) else set()
                assignments = value.get('layer_assignments', [])
                if isinstance(assignments, list) and any(not isinstance(item, dict) or item.get('proof_point_id') not in point_ids for item in assignments):
                    add('REFERENCE_MISSING', relative, area, 'Verification plan names an absent Test Contract proof point.',
                        blocking=True, repairability='AGENT_REPAIRABLE', authority='test_contract_id/proof_points')
        if contract_for(relative)[0] == 'evidence-manifest':
            for entry in value.get('entries', []) if isinstance(value.get('entries'), list) else []:
                if not isinstance(entry, dict):
                    continue
                traceability = entry.get('traceability', {})
                references = traceability.get('requirements', []) if isinstance(traceability, dict) else []
                if isinstance(references, list) and any(not isinstance(ref, str) or len(identities.get(ref, [])) != 1 for ref in references):
                    add('REFERENCE_MISSING', relative, area, 'Evidence requirement references are missing or ambiguous.',
                        blocking=True, repairability='AGENT_REPAIRABLE', authority='traceability.requirements')
                artifacts = entry.get('actual_evidence', [])
                source_paths = [artifact.get('path') for artifact in artifacts if isinstance(artifact, dict)] if isinstance(artifacts, list) else []
                if entry.get('parity_report_path'):
                    source_paths.append(entry['parity_report_path'])
                if any(not isinstance(source, str) or not source.startswith('planning/') or not safe_file(root, source) for source in source_paths):
                    add('REFERENCE_MISSING', relative, area, 'Evidence artifact paths are missing or unsafe.',
                        blocking=True, repairability='AGENT_REPAIRABLE', authority='actual_evidence')
        if area == 'tasks':
            state, wave, provenance = assignment(root, value, waves)
            if state not in ('explicit',):
                coverage['task']['unassigned'] += 1
                add('AUTHORITY_CONFLICT' if state == 'conflict' else 'WAVE_ASSIGNMENT_MISSING', relative, area,
                    'Task wave assignment needs reconciliation.', blocking=state == 'conflict',
                    repairability='SAFE_DETERMINISTIC' if state == 'derived' else 'DECISION_REQUIRED',
                    repair='ADD_WAVE_ID' if state == 'derived' else None,
                    authority=provenance or 'planning/lifecycle/process-state.yaml')
            if not value.get('workpackage_id'):
                add('UNASSIGNED', relative, area, 'No explicit optional workpackage assignment is recorded.', severity='INFO')
        for field in ('evidence_refs', 'source_artifacts'):
            for reference in value.get(field, []) if isinstance(value.get(field), list) else []:
                if isinstance(reference, str) and reference.startswith(('planning/', 'requirements/')) and not safe_file(root, reference):
                    add('REFERENCE_MISSING', relative, area, 'A canonical source/evidence path is missing or unsafe.', blocking=True,
                        repairability='AGENT_REPAIRABLE', authority=field)

    for pattern, artifact, area in CONTRACTS:
        parent = root / str(PurePosixPath(pattern).parent)
        if '*' not in str(parent) and parent.is_dir() and '*' in pattern:
            allowed = {relative for relative in paths if contract_for(relative)[0] == artifact}
            for path in sorted(parent.glob('*.md')) + sorted(parent.glob('*.yaml' if pattern.endswith('.yml') else '*.yml')) + sorted(parent.glob('*.json')):
                relative = path.relative_to(root).as_posix()
                if path.stem.lower() in ('readme', 'template'):
                    continue
                if relative not in allowed and safe_file(root, relative):
                    hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
                    add('UNSUPPORTED_VARIANT', relative, area, 'Legacy extension is not consumed by this projection.',
                        repairability='AGENT_REPAIRABLE', authority='.mxagile/policies/project-compatibility.md')
                    if path.suffix == '.json':
                        try:
                            json.loads(path.read_text(encoding='utf-8-sig'))
                        except json.JSONDecodeError as exc:
                            add('SYNTAX_ERROR', relative, area, 'Legacy JSON source is syntactically invalid.', blocking=True,
                                line=exc.lineno, column=exc.colno)

    for target in status['project']['active_targets']['items']:
        source = target.get('canonical_path') or 'planning/target-mockups'
        if target.get('availability') != 'available':
            ambiguous = target.get('availability') == 'ambiguous'
            add('AUTHORITY_CONFLICT' if ambiguous else 'REFERENCE_MISSING', source, 'references',
                'Declared design target does not resolve to exactly one usable canonical reference.',
                blocking=ambiguous, repairability='DECISION_REQUIRED', authority='ACTIVE_TARGET')
        drift = target.get('inventory_drift', {})
        if isinstance(drift, dict) and drift.get('state') == 'mismatch':
            add('STALE', source, 'references', 'UI inventory refers to a different target revision.',
                repairability='DECISION_REQUIRED', authority='ACTIVE_TARGET')

    diagnostics.sort(key=lambda item: (item['source_path'] or '', item['category'], item['diagnostic_id']))
    for item in diagnostics:
        if item['category'] == 'SYNTAX_ERROR' and item['source_path']:
            path = safe_file(root, item['source_path'])
            if path and quoted_yaml_candidate(item['source_path'], path.read_bytes()) is not None:
                item['repairability'] = 'SAFE_DETERMINISTIC'
                item['proposed_repair_type'] = 'QUOTE_TEXT_SCALAR'
    compatibility = 'BLOCKED' if any(item['blocking'] for item in diagnostics) else (
        'PARTIAL' if any(item['severity'] == 'WARNING' for item in diagnostics) else 'COMPATIBLE')
    fingerprint = 'sha256:' + hashlib.sha256('\n'.join(f'{path}:{value}' for path, value in sorted(hashes.items())).encode('utf-8')).hexdigest()
    return {
        'schema_version': 1, 'read_only': True, 'stage': 'PROJECT_COMPATIBILITY_CHECKED',
        'compatibility': compatibility, 'source_fingerprint': fingerprint,
        'repair_status': 'DECISION_REQUIRED' if any(item['repairability'] == 'DECISION_REQUIRED' for item in diagnostics)
        else ('PROJECT_REPAIR_REQUIRED' if any(item['repairability'] in ('SAFE_DETERMINISTIC', 'AGENT_REPAIRABLE') for item in diagnostics) else None),
        'coverage': coverage, 'diagnostics': diagnostics,
    }


TEXT_FIELDS = {'note', 'notes', 'description', 'rationale', 'resume_from', 'basis', 'action', 'detail', 'objective', 'claim', 'message'}
PROTECTED_FIELDS = {
    'id', 'phase', 'status', 'result', 'progress', 'blockers', 'gates', 'active_wave',
    'lifecycle_status', 'parity_result', 'verification_result', 'legacy_completion',
    'workpackage_id', 'wave_id', 'active_target', 'refinement_status',
}


class RepairFailure(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def quoted_yaml_candidate(relative: str, raw: bytes) -> bytes | None:
    try:
        text = raw.decode('utf-8-sig')
    except UnicodeError:
        return None
    original = text
    for _ in range(32):
        try:
            value = load_yaml(text)
            if text == original or schema_errors(relative, value):
                return None
            bom = b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b''
            return bom + text.encode('utf-8')
        except yaml.YAMLError as exc:
            mark = getattr(exc, 'problem_mark', None)
            if mark is None or getattr(exc, 'problem', '') != 'mapping values are not allowed here':
                return None
            lines = text.splitlines(keepends=True)
            if mark.line >= len(lines):
                return None
            line = lines[mark.line]
            match = re.fullmatch(r'( *)([A-Za-z_][A-Za-z0-9_]*):( +)([^\r\n]+)(\r?\n)?', line)
            if not match or match.group(2) not in TEXT_FIELDS:
                return None
            scalar = match.group(4).rstrip()
            if not scalar or scalar[0] in '-?:,[]{}#&*!|>\'"%@`' or any(token in scalar for token in ('#', ' &', ' *', ' !', '\t')):
                return None
            replacement = json.dumps(scalar, ensure_ascii=True)
            if load_yaml(replacement) != scalar:
                return None
            lines[mark.line] = match.group(1) + match.group(2) + ':' + match.group(3) + replacement + (match.group(5) or '')
            text = ''.join(lines)
    return None


def protected_values(value: Any, prefix: tuple = ()) -> dict:
    result = {}
    if isinstance(value, dict):
        for key, child in value.items():
            path = prefix + (key,)
            if str(key).lower() in PROTECTED_FIELDS:
                result[path] = child
            result.update(protected_values(child, path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            result.update(protected_values(child, prefix + (index,)))
    return result


def repair_candidates(root: Path, report: dict, candidate_dir: Path | None = None) -> dict[str, tuple[bytes, str]]:
    candidates: dict[str, tuple[bytes, str]] = {}
    waves_path = safe_file(root, 'planning/lifecycle/process-state.yaml')
    try:
        process = load_yaml(waves_path.read_text(encoding='utf-8-sig')) if waves_path else {}
        waves = set(process.get('waves', {})) if isinstance(process, dict) and isinstance(process.get('waves', {}), dict) else set()
    except (OSError, UnicodeError, yaml.YAMLError):
        waves = set()
    for diagnostic in report['diagnostics']:
        relative = diagnostic['source_path']
        if not relative or relative in candidates:
            continue
        path = safe_file(root, relative)
        if path is None or not contract_for(relative):
            continue
        raw = path.read_bytes()
        if diagnostic['proposed_repair_type'] == 'QUOTE_TEXT_SCALAR':
            replacement = quoted_yaml_candidate(relative, raw)
            if replacement is not None:
                candidates[relative] = replacement, 'QUOTE_TEXT_SCALAR'
        elif diagnostic['proposed_repair_type'] == 'ADD_WAVE_ID':
            value = load_yaml(raw.decode('utf-8-sig'))
            state, wave, provenance = assignment(root, value, waves)
            if state == 'derived' and not schema_errors(relative, value):
                newline = '\r\n' if b'\r\n' in raw else '\n'
                text = raw.decode('utf-8-sig')
                if not text.endswith(('\n', '\r')):
                    text += newline
                text += f'wave_id: {wave}{newline}assignment_provenance:{newline}  rule: migrated_from_checklist_v1{newline}  source: {provenance}{newline}'
                replacement = (b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'') + text.encode('utf-8')
                if not schema_errors(relative, load_yaml(replacement.decode('utf-8-sig'))):
                    candidates[relative] = replacement, 'ADD_WAVE_ID'
        elif candidate_dir and diagnostic['repairability'] == 'AGENT_REPAIRABLE':
            staged = safe_file(candidate_dir, relative)
            if staged is None:
                continue
            replacement = staged.read_bytes()
            try:
                previous = load_yaml(raw.decode('utf-8-sig'))
                proposed = load_yaml(replacement.decode('utf-8-sig'))
            except (UnicodeError, yaml.YAMLError):
                continue
            if (isinstance(previous, dict) and isinstance(proposed, dict)
                    and protected_values(previous) == protected_values(proposed)
                    and not schema_errors(relative, proposed) and replacement != raw):
                candidates[relative] = replacement, 'AGENT_CANDIDATE'
    return candidates


def repair_plan(root: Path, report: dict, candidate_dir: Path | None = None) -> dict:
    candidates = repair_candidates(root, report, candidate_dir)
    entries = []
    for relative, (replacement, kind) in sorted(candidates.items()):
        path = safe_file(root, relative)
        preview = {'before': '[REDACTED TEXT SCALAR]', 'after': '[SAME TEXT SCALAR, QUOTED]' if kind == 'QUOTE_TEXT_SCALAR' else '[REDACTED REVIEWED CANDIDATE]'}
        if kind == 'ADD_WAVE_ID':
            preview = {'field': 'wave_id', 'before': None, 'after': load_yaml(replacement.decode('utf-8-sig'))['wave_id']}
        entries.append({
            'source_path': relative, 'repair_type': kind,
            'before_fingerprint': digest(path.read_bytes()), 'after_fingerprint': digest(replacement),
            'diagnostic_ids': sorted(item['diagnostic_id'] for item in report['diagnostics'] if item['source_path'] == relative and (item['proposed_repair_type'] == kind or kind == 'AGENT_CANDIDATE' and item['repairability'] == 'AGENT_REPAIRABLE')),
            'preview': preview,
        })
    contract_fingerprint = digest(b''.join(path.read_bytes() for path in sorted(SCHEMA_ROOT.glob('*.json'))))
    plan = {
        'schema_version': 1, 'source_fingerprint': report['source_fingerprint'],
        'contract_fingerprint': contract_fingerprint,
        'file_scope': [entry['source_path'] for entry in entries], 'repairs': entries,
        'deferred_diagnostic_ids': sorted(item['diagnostic_id'] for item in report['diagnostics'] if item['repairability'] != 'UNSUPPORTED' and item['source_path'] not in candidates),
    }
    plan['plan_hash'] = digest(json.dumps(plan, sort_keys=True).encode('utf-8'))
    return plan


def atomic_replace(path: Path, raw: bytes) -> None:
    mode = path.stat().st_mode
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.mxagile-repair-', delete=False) as handle:
            temporary = handle.name
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)


def apply_repair(root: Path, expected_hash: str, candidate_dir: Path | None = None) -> dict:
    from build_project_status import build_status
    before = build_status(root)
    report = before['compatibility']
    plan = repair_plan(root, report, candidate_dir)
    if plan['plan_hash'] != expected_hash:
        raise ValueError('Repair plan is stale or unapproved; rerun dry run.')
    replacements = repair_candidates(root, report, candidate_dir)
    originals: dict[str, bytes] = {}
    written: dict[str, bytes] = {}
    try:
        for entry in plan['repairs']:
            relative = entry['source_path']
            path = safe_file(root, relative)
            if path is None:
                raise ValueError('Repair scope is unsafe.')
            original = path.read_bytes()
            replacement = replacements[relative][0]
            if digest(original) != entry['before_fingerprint'] or digest(replacement) != entry['after_fingerprint']:
                raise ValueError('Repair inputs changed.')
            value = load_yaml(replacement.decode('utf-8-sig'))
            if schema_errors(relative, value):
                raise ValueError('Repaired artifact failed schema validation.')
            if build_status(root)['source_fingerprint'] != before['source_fingerprint'] and not written:
                raise ValueError('Canonical inputs changed before repair.')
            originals[relative] = original
            atomic_replace(path, replacement)
            written[relative] = replacement
        after = build_status(root)
        previous = {item['diagnostic_id'] for item in report['diagnostics'] if item['severity'] != 'INFO'}
        introduced = [item for item in after['compatibility']['diagnostics'] if item['blocking'] and item['diagnostic_id'] not in previous]
        selected = {identity for entry in plan['repairs'] for identity in entry['diagnostic_ids']}
        unresolved = selected.intersection(item['diagnostic_id'] for item in after['compatibility']['diagnostics'])
        if introduced or unresolved:
            raise ValueError('Post-repair parser/schema/reference/Doctor validation failed.')
        return {'applied': plan['file_scope'], 'plan_hash': plan['plan_hash'], 'compatibility': after['compatibility']}
    except Exception:
        conflicts = []
        for relative, replacement in reversed(list(written.items())):
            path = safe_file(root, relative)
            if path is None or path.read_bytes() != replacement:
                conflicts.append(relative)
                continue
            atomic_replace(path, originals[relative])
        if conflicts:
            raise RepairFailure('ROLLBACK_REQUIRES_MANUAL_RECOVERY') from None
        raise RepairFailure('SCOPED_ROLLBACK_COMPLETED') from None


def main() -> int:
    parser = argparse.ArgumentParser(description='Read-only project compatibility Doctor.')
    parser.add_argument('command', choices=['doctor', 'repair'], nargs='?', default='doctor')
    parser.add_argument('--project-root', type=Path, default=Path.cwd())
    parser.add_argument('--format', choices=['json', 'human'], default='human')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run', action='store_true')
    mode.add_argument('--apply', action='store_true')
    parser.add_argument('--plan-hash')
    parser.add_argument('--candidate-dir', type=Path)
    args = parser.parse_args()
    from build_project_status import build_status
    root = args.project_root.resolve()
    if args.command == 'doctor' and (args.apply or args.plan_hash or args.candidate_dir):
        parser.error('doctor is read-only; repair arguments require repair.')
    try:
        report = build_status(root)['compatibility']
        if args.command == 'repair':
            if args.apply:
                if not args.plan_hash:
                    parser.error('--apply requires an approved --plan-hash from dry run.')
                result = apply_repair(root, args.plan_hash, args.candidate_dir)
            else:
                result = repair_plan(root, report, args.candidate_dir)
            print(json.dumps(result, sort_keys=True, indent=2))
            return 0
    except RepairFailure as exc:
        print(json.dumps({'error': exc.code, 'action': 'Review Doctor before any retry.'}), file=sys.stderr)
        return 3
    except (OSError, ValueError, yaml.YAMLError):
        print(json.dumps({'error': 'COMPATIBILITY_OPERATION_FAILED', 'action': 'Rerun Doctor and review the scoped repair plan.'}), file=sys.stderr)
        return 3
    if args.format == 'json':
        print(json.dumps(report, sort_keys=True, indent=2))
    else:
        print(f"PROJECT_COMPATIBILITY_CHECKED: {report['compatibility']} (read-only)")
        for item in report['diagnostics']:
            location = item['source_path'] or item['affected_board_area']
            if item['line'] is not None:
                location += f":{item['line']}:{item['column']}"
            print(f"{item['severity']} {item['category']} {location} [{item['repairability']}]")
    return {'COMPATIBLE': 0, 'PARTIAL': 1, 'BLOCKED': 2}[report['compatibility']]


if __name__ == '__main__':
    raise SystemExit(main())