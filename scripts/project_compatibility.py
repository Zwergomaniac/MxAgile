"""Deterministic compatibility diagnostics; never a lifecycle authority."""

from __future__ import annotations

import argparse
import copy
import contextvars
import datetime
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import threading
from contextlib import contextmanager
from functools import lru_cache
from pathlib import Path, PurePosixPath
from typing import Any

import yaml

try:
    import jsonschema
    from referencing import Registry, Resource
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
    ('planning/test-contracts/TC-*.yaml', 'test-contract', 'verification'),
    ('planning/verification-plans/*.yaml', 'verification-plan', 'verification'),
    ('planning/ui-inventory/*.yaml', 'page', 'references'),
    ('planning/evidence/manifests/*-evidence-manifest.yaml', 'evidence-manifest', 'verification'),
    ('planning/parity/*.yaml', 'parity-verification', 'verification'),
    ('planning/target-mockups/*/_history/REV-*/revision.yaml', 'revision', 'references'),
)
SCHEMA_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_ROOT = SCHEMA_ROOT / 'schemas' if SCHEMA_ROOT.name == '.mxagile' else SCHEMA_ROOT / '.mxagile/schemas'
_SCHEMA_CONTEXT: contextvars.ContextVar[dict[str, Any] | None] = contextvars.ContextVar('mxagile_schema_context', default=None)


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


@lru_cache(maxsize=512)
def _parse_yaml(raw: str | bytes) -> Any:
    return yaml.load(raw, Loader=CanonicalLoader)


def load_yaml(raw: str | bytes) -> Any:
    return copy.deepcopy(_parse_yaml(raw))


def compatibility_projection(relative: str, value: Any) -> tuple[Any, list[str], list[str]]:
    projected = copy.deepcopy(value)
    rules: list[str] = []
    conflicts: list[str] = []
    if not isinstance(projected, dict):
        return projected, rules, conflicts

    artifact = (contract_for(relative) or (None, None))[0]
    if artifact == 'requirement':
        if 'created' in projected:
            created = iso_date_value(projected['created'])
            if created is not None:
                current_created = iso_date_value(projected.get('created_at')) if 'created_at' in projected else created
                if current_created != created:
                    conflicts.append('created/created_at')
                else:
                    projected['created_at'] = created
                    del projected['created']
                    rules.append('requirement_created_v1')
        if type(projected.get('created_at')) is datetime.date:
            projected['created_at'] = projected['created_at'].isoformat()
            rules.append('requirement_created_at_yaml_date_v1')

        source = projected.get('source')
        match = re.fullmatch(r'design_contract_rev([0-9]+)', source, re.IGNORECASE) if isinstance(source, str) else None
        if match:
            source_ref = f'REV-{match.group(1)}'
            if 'source_ref' in projected and projected['source_ref'] != source_ref:
                conflicts.append('source/source_ref')
            else:
                projected['source'] = 'design_contract'
                projected['source_ref'] = source_ref
                rules.append('requirement_design_contract_revision_v1')
        raw_status = projected.get('status')
        if isinstance(raw_status, str):
            status_aliases = {
                'ACTIVE': 'accepted', 'DRAFT': 'draft', 'DEFERRED': 'deferred',
                'SUPERSEDED': 'superseded', 'OBSOLETE': 'obsolete', 'RETIRED': 'retired',
                'SPLIT': 'split', 'MERGED': 'merged', 'DUPLICATE': 'duplicate',
                'INVALID': 'invalid', 'AMBIGUOUS': 'ambiguous',
            }
            if raw_status in status_aliases:
                projected['status'] = status_aliases[raw_status]
                rules.append('requirement_lifecycle_status_v1')
    elif artifact == 'decision':
        aliases = {'decided_at': 'confirmed_at', 'decided_by': 'confirmed_by'}
        status = projected.get('status')
        if status == 'DECIDED':
            date = iso_date_value(projected.get('decided_at', projected.get('confirmed_at')))
            owner = projected.get('decided_by', projected.get('confirmed_by'))
            if date is None or not isinstance(owner, str) or not owner.strip():
                conflicts.append('decision approval evidence missing')
            else:
                projected['status'] = 'CONFIRMED'
                rules.append('legacy_decision_aliases_v1')
        elif status == 'OPEN':
            if any(projected.get(field) for field in (*aliases, *aliases.values())):
                conflicts.append('open decision/approval evidence')
            else:
                projected['status'] = 'PROPOSED'
                rules.append('legacy_decision_aliases_v1')
        if projected.get('decision_type') == 'ux':
            projected['decision_type'] = 'ux_interaction'
            rules.append('legacy_decision_aliases_v1')
        for legacy, current in aliases.items():
            if legacy not in projected:
                continue
            if current in projected and projected[current] != projected[legacy]:
                conflicts.append(f'{legacy}/{current}')
            else:
                projected[current] = projected.pop(legacy)
                rules.append('legacy_decision_aliases_v1')
    elif artifact == 'evidence-manifest':
        if 'created' in projected:
            created = iso_date_value(projected['created'])
            if created is not None:
                current_created = iso_date_value(projected.get('created_at')) if 'created_at' in projected else created
                if current_created != created:
                    conflicts.append('created/created_at')
                else:
                    projected['created_at'] = created
                    del projected['created']
                    rules.append('evidence_manifest_created_v1')
        if type(projected.get('created_at')) is datetime.date:
            projected['created_at'] = projected['created_at'].isoformat()
            rules.append('evidence_manifest_created_at_yaml_date_v1')
        if 'scenarios' in projected and isinstance(projected['scenarios'], list):
            scenarios = projected['scenarios']
            if 'entries' in projected and projected['entries'] != scenarios:
                conflicts.append('scenarios/entries')
            else:
                projected.setdefault('entries', scenarios)
                del projected['scenarios']
                rules.append('evidence_manifest_scenarios_v1')
    elif artifact == 'page':
        sections = projected.get('sections')
        if isinstance(sections, list):
            for section in sections:
                if not isinstance(section, dict) or 'section_id' not in section:
                    continue
                if 'id' in section and section['id'] != section['section_id']:
                    conflicts.append('sections[].id/section_id')
                else:
                    section['id'] = section.pop('section_id')
                    rules.append('page_section_id_v1')
        navigation = projected.get('navigation')
        if isinstance(navigation, list):
            for link in navigation:
                if not isinstance(link, dict) or 'target' not in link or 'action_id' not in link:
                    continue
                if 'leads_to_page' in link and link['leads_to_page'] != link['target']:
                    conflicts.append('navigation.target/leads_to_page')
                else:
                    link.setdefault('leads_to_page', link['target'])
                    del link['target']
                    rules.append('page_navigation_target_v1')
    elif artifact == 'task':
        inspect = projected.get('inspect')
        if isinstance(inspect, dict):
            target_types = ('entity', 'microflow', 'association', 'rule', 'snippet', 'page')
            legacy_types = [name for name in target_types if name in inspect]
            if legacy_types:
                typed_fields = {'type', 'target'}.intersection(inspect)
                if len(legacy_types) != 1 or typed_fields:
                    conflicts.append('inspect target cardinality/form')
                elif set(inspect).issubset({legacy_types[0], 'expect'}):
                    target_type = legacy_types[0]
                    target = inspect.pop(target_type)
                    inspect['type'] = target_type
                    inspect['target'] = target
                    rules.append('task_inspect_typed_target_v1')
    return projected, sorted(set(rules)), sorted(set(conflicts))


def iso_date_value(value: Any) -> str | None:
    if isinstance(value, datetime.datetime):
        return None
    if isinstance(value, datetime.date):
        return value.isoformat()
    if isinstance(value, str):
        try:
            datetime.date.fromisoformat(value)
            return value
        except ValueError:
            pass
    return None


def raw_schema_errors(relative: str, value: Any) -> list[str]:
    contract = contract_for(relative)
    if not contract:
        return []
    if jsonschema is None:
        return ['VALIDATOR_UNAVAILABLE']
    schema_path = SCHEMA_ROOT / (contract[0] + '.schema.json')
    if not schema_path.is_file():
        return ['SCHEMA_UNAVAILABLE']
    try:
        validator = schema_validator(schema_path)
        return sorted({str(error.validator) for error in validator.iter_errors(value)})
    except (OSError, ValueError, jsonschema.exceptions.SchemaError):
        return ['SCHEMA_UNAVAILABLE']


def projected_for_validation(relative: str, value: Any) -> Any:
    projected, rules, conflicts = compatibility_projection(relative, value)
    if not rules or conflicts or raw_schema_errors(relative, projected):
        return value
    return projected


def digest(raw: bytes) -> str:
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


@lru_cache(maxsize=8192)
def _canonical_path_key(relative: str) -> str:
    normalized = relative.replace('\\', '/')
    return normalized.casefold() if sys.platform == 'win32' else normalized


def _canonical_pattern_matches(relative: str, pattern: str) -> bool:
    return PurePosixPath(_canonical_path_key(relative)).match(_canonical_path_key(pattern))


@lru_cache(maxsize=8192)
def contract_for(relative: str) -> tuple[str, str] | None:
    if is_standalone_interaction_artifact(relative):
        return None
    return next(((schema, area) for pattern, schema, area in CONTRACTS if _canonical_pattern_matches(relative, pattern)), None)


def is_standalone_interaction_artifact(relative: str) -> bool:
    return any(_canonical_pattern_matches(relative, pattern) for pattern in (
        'planning/ui-inventory/interaction-metadata-*.yaml',
        'planning/ui-inventory/interaction-states-*.yaml',
        'planning/ui-inventory/PAGE-INTERACTION-STATES-*.yaml',
        'planning/ui-inventory/PAGE-INTERACTION-STATES-*.yaml',
    ))


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


@lru_cache(maxsize=64)
def load_schema(path: str, modified: int, size: int, changed: int, content_hash: str) -> dict:
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


@lru_cache(maxsize=4)
def schema_registry(signatures: tuple) -> Any:
    return Registry().with_resources(
        (Path(path).name, Resource.from_contents(load_schema(path, modified, size, changed, content_hash)))
        for path, modified, size, changed, content_hash in signatures
    )


def _schema_signatures(directory: Path) -> tuple[tuple[str, int, int, int, str], ...]:
    result = []
    for path in sorted(directory.glob('*.schema.json')):
        stat = path.stat()
        content_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        result.append((str(path), stat.st_mtime_ns, stat.st_size, stat.st_ctime_ns, content_hash))
    return tuple(result)


@contextmanager
def schema_validation_scope():
    context = {"signatures": _schema_signatures(SCHEMA_ROOT), "validators": {}}
    token = _SCHEMA_CONTEXT.set(context)
    try:
        yield
    finally:
        _SCHEMA_CONTEXT.reset(token)


def schema_validator(path: Path) -> Any:
    context = _SCHEMA_CONTEXT.get()
    if context is None:
        with schema_validation_scope():
            return schema_validator(path)
    key = str(path)
    cached = context["validators"].get(key)
    if cached is not None:
        return cached
    signatures = context["signatures"]
    signature = next((item for item in signatures if item[0] == key), None)
    if signature is None:
        stat = path.stat()
        content_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        signature = (key, stat.st_mtime_ns, stat.st_size, stat.st_ctime_ns, content_hash)
    schema = load_schema(*signature)
    validator = jsonschema.Draft7Validator(schema, registry=schema_registry(signatures))
    context["validators"][key] = validator
    return validator


def schema_errors(relative: str, value: Any) -> list[str]:
    return raw_schema_errors(relative, projected_for_validation(relative, value))


def assignment(
    root: Path,
    task: dict,
    waves: set[str],
    checklist_cache: dict[str, tuple[str, dict | None]] | None = None,
) -> tuple[str, str | None, str | None]:
    provenance = task.get('migrated_from')
    if not isinstance(provenance, str):
        return ('explicit', task['wave_id'], None) if isinstance(task.get('wave_id'), str) and task['wave_id'] in waves else ('missing', None, None)
    from wave_ids import CHECKLIST_PATH_PATTERN
    match = CHECKLIST_PATH_PATTERN.fullmatch(provenance) if provenance.endswith('.yaml') else None
    if match is None:
        return 'ambiguous', None, provenance
    cached = checklist_cache.get(provenance) if checklist_cache is not None else None
    if cached is None:
        path = safe_file(root, provenance)
        if path is None:
            parsed = ('ambiguous', None)
        else:
            try:
                checklist = load_yaml(path.read_text(encoding='utf-8-sig'))
                parsed = ('available', checklist if isinstance(checklist, dict) else None)
            except (OSError, UnicodeError, yaml.YAMLError):
                parsed = ('ambiguous', None)
        if checklist_cache is not None:
            checklist_cache[provenance] = parsed
    else:
        parsed = cached
    wave = match.group(1)
    checklist = parsed[1]
    if not isinstance(checklist, dict) or wave not in waves:
        return 'ambiguous', None, provenance
    declared = checklist.get('wave_id', checklist.get('wave'))
    if declared is not None and declared != wave:
        return 'conflict', None, provenance
    explicit = task.get('wave_id')
    if explicit is not None:
        return ('explicit', explicit, provenance) if explicit == wave else ('conflict', None, provenance)
    return 'derived', wave, provenance


def schema_diagnostics(relative: str, value: Any) -> list[tuple[str, str, str]]:
    contract = contract_for(relative)
    if not contract or jsonschema is None:
        return []
    path = SCHEMA_ROOT / (contract[0] + '.schema.json')
    if not path.is_file():
        return []
    issues = []
    value = projected_for_validation(relative, value)
    for error in schema_validator(path).iter_errors(value):
        location = '/'.join(str(part) for part in error.absolute_schema_path)
        indexes = '/'.join(str(part) for part in error.absolute_path if isinstance(part, int))
        authority = f'.mxagile/schemas/{contract[0]}.schema.json#/{location}@{indexes}'
        repairability = 'AGENT_REPAIRABLE' if error.validator == 'additionalProperties' else 'DECISION_REQUIRED'
        message = None
        if contract[0] == 'process-state' and error.validator == 'additionalProperties' and isinstance(error.instance, dict):
            extra_fields = set(error.instance) - set(error.schema.get('properties', {}))
            misplaced = extra_fields.intersection({'runtime_verification', 'feature_scope', 'terminal_state'})
            if misplaced:
                field = sorted(misplaced)[0]
                targets = {
                    'runtime_verification': '.mxagile/schemas/parity-verification.schema.json',
                    'feature_scope': '.mxagile/schemas/mission-state.schema.json#/properties/progress',
                    'terminal_state': '.mxagile/lifecycle.yaml#/terminal_states',
                }
                repairability = 'DECISION_REQUIRED'
                authority = targets[field]
                message = f'Process-state field {field} is outside wave lifecycle authority; no lossless migration is established.'
        if contract[0] == 'page' and error.validator == 'additionalProperties' and isinstance(error.instance, dict):
            extra_fields = set(error.instance) - set(error.schema.get('properties', {}))
            if extra_fields.intersection({'page', 'source', 'screen_id', 'active_target'}):
                repairability = 'DECISION_REQUIRED'
                authority = '.mxagile/policies/mockup-lifecycle.md'
        if error.validator == 'additionalProperties' and 'inspect' in error.absolute_path:
            repairability = 'DECISION_REQUIRED'
        if error.validator == 'required' and isinstance(error.instance, dict):
            for field in sorted(set(error.validator_value) - error.instance.keys()):
                issues.append((f'Required canonical field is missing: {field}.', repairability, authority + '/' + field))
        else:
            issues.append((message or f'Canonical schema constraint failed: {error.validator}.', repairability, authority))
    return sorted(set(issues))


def wave_review_authority(task: dict, documents: dict[str, dict], waves: set[str]) -> str | None:
    candidates: dict[str, list[str]] = {}
    requirements = {item for item in task.get('req', []) if isinstance(item, str)} if isinstance(task.get('req'), list) else set()
    for relative, manifest in documents.items():
        if contract_for(relative)[0] != 'evidence-manifest' or schema_errors(relative, manifest):
            continue
        wave = manifest.get('wave_id')
        if wave not in waves:
            continue
        for entry in manifest.get('entries', []):
            trace = entry.get('traceability', {})
            if task.get('spec') in trace.get('specs', []) or requirements.intersection(trace.get('requirements', [])):
                candidates.setdefault(wave, []).append(relative)
    return sorted(next(iter(candidates.values())))[0] if len(candidates) == 1 else None


CHANGE_SET_DIRECTORY = 'planning/reconciliation/change-sets'
CHANGE_SET_SCAN_LIMIT = 500
CHANGE_SET_MAX_BYTES = 1024 * 1024
DONE_BASIS_LISTED_WAVES = 8


def _lifecycle_clarity_diagnostics(root: Path, parsed_documents: dict, add: Any) -> None:
    """Informative CS-0 lifecycle diagnostics. Read-only: no repair, no migration, no registry writes,
    and no Markdown parsing of execution-waves.md. None of them is blocking."""
    _done_basis_diagnostic(parsed_documents, add)
    _change_set_diagnostics(root, add)
    _active_revision_diagnostics(root, parsed_documents, add)


def _done_basis_diagnostic(parsed_documents: dict, add: Any) -> None:
    """DONE_BASIS_NOT_RECORDED: a done wave without a structured acceptance_gate record.
    Reported once per project (INFO). It never reopens a wave and never invents a basis."""
    snapshot = parsed_documents.get('planning/lifecycle/process-state.yaml') or {}
    value = snapshot.get('value') if snapshot.get('state') == 'available' else None
    waves = value.get('waves') if isinstance(value, dict) else None
    if not isinstance(waves, dict):
        return
    unrecorded = []
    for wave_id, block in sorted(waves.items(), key=lambda item: str(item[0])):
        if not isinstance(block, dict) or block.get('phase') != 'done':
            continue
        gates = block.get('gates')
        gate = gates.get('acceptance_gate') if isinstance(gates, dict) else None
        result = gate.get('result') if isinstance(gate, dict) else None
        if result in (None, 'not_recorded'):
            unrecorded.append(str(wave_id))
    if unrecorded:
        listed = ', '.join(unrecorded[:DONE_BASIS_LISTED_WAVES])
        if len(unrecorded) > DONE_BASIS_LISTED_WAVES:
            listed += f' (+{len(unrecorded) - DONE_BASIS_LISTED_WAVES} more)'
        add('DONE_BASIS_NOT_RECORDED', 'planning/lifecycle/process-state.yaml', 'lifecycle',
            f'{len(unrecorded)} done wave(s) carry no structured acceptance_gate record ({listed}). '
            'Done stays valid and is not reopened; the acceptance basis is simply not recorded in process-state.yaml.',
            repairability='UNSUPPORTED', severity='INFO', authority='.mxagile/policies/lifecycle-resync.md')


def _change_set_diagnostics(root: Path, add: Any) -> None:
    """CHANGE_SET_SCHEMA_INVALID: a Change-Set record violates change-set.schema.json (for example a
    campaign-log style record with fields the provenance contract does not allow)."""
    base = root / CHANGE_SET_DIRECTORY
    if jsonschema is None or not base.is_dir() or base.is_symlink():
        return
    try:
        validator = jsonschema.Draft7Validator(json.loads((SCHEMA_ROOT / 'change-set.schema.json').read_text(encoding='utf-8-sig')))
    except (OSError, ValueError):
        return  # without the contract no judgement is made
    for path in sorted(base.glob('*.json'))[:CHANGE_SET_SCAN_LIMIT]:
        relative = path.relative_to(root).as_posix()
        safe = safe_file(root, relative)
        if safe is None:
            continue
        try:
            if safe.stat().st_size > CHANGE_SET_MAX_BYTES:
                problem = 'is larger than the allowed size'
            else:
                value = json.loads(safe.read_text(encoding='utf-8-sig'))
                errors = sorted(validator.iter_errors(value), key=lambda error: [str(part) for part in error.path])
                if not errors:
                    continue
                first = errors[0]
                where = '/'.join(str(part) for part in first.path) or '<root>'
                problem = f'violates the Change-Set contract ({len(errors)} violation(s); first at {where}: {first.message[:140]})'
        except (OSError, UnicodeError):
            problem = 'could not be read'
        except ValueError:
            problem = 'is not valid JSON'
        add('CHANGE_SET_SCHEMA_INVALID', relative, 'provenance',
            f'Change-Set {problem}. A Change-Set is commit provenance, not a work container or campaign log; '
            'it is not used as an attribution source until it is valid.',
            repairability='DECISION_REQUIRED', severity='WARNING', authority='.mxagile/schemas/change-set.schema.json')


def _active_revision_diagnostics(root: Path, parsed_documents: dict, add: Any) -> None:
    """Report an active ledger revision lacking explicit current revision binding.
    A shared source/target path is not a revision identity or unchanged-scope proof.
    """
    base = root / 'planning/revisions'
    if not base.is_dir() or base.is_symlink():
        return
    pages = []
    for relative, snapshot in parsed_documents.items():
        value = snapshot.get('value') if isinstance(snapshot, dict) else None
        if (relative.startswith('planning/ui-inventory/') and snapshot.get('state') == 'available' and isinstance(value, dict)
                and not is_standalone_interaction_artifact(relative)):
            pages.append(value)

    def normalized(value: Any) -> str | None:
        return value.replace(chr(92), '/').strip() if isinstance(value, str) and value.strip() else None

    for path in sorted(base.glob('REV-*.yaml')):
        relative = path.relative_to(root).as_posix()
        safe = safe_file(root, relative)
        if safe is None:
            continue
        try:
            value = load_yaml(safe.read_bytes().decode('utf-8-sig'))
        except (OSError, UnicodeError, yaml.YAMLError):
            continue
        if not isinstance(value, dict) or value.get('active_target') is not True:
            continue
        revision_id = normalized(value.get('revision_id')) or path.stem
        identities = {identity for identity in (revision_id, normalized(value.get('revision'))) if identity}
        namespace = normalized(value.get('mockup_name')) or normalized(value.get('mockup_id'))
        bound = any(
            normalized(page.get('target_revision')) in identities
            and (not namespace or not (page.get('mockup_name') or page.get('mockup_id'))
                 or namespace == (normalized(page.get('mockup_name')) or normalized(page.get('mockup_id'))))
            and page_identity_binding(root, page, {'mockup_id': namespace,
                'source_mockup_id': normalized(value.get('mockup_id')) or namespace})['state'] == 'PROVEN'
            for page in pages
        )
        if not bound:
            add('ACTIVE_REVISION_UNBOUND', relative, 'references',
                f'Revision {revision_id} is marked active_target but no Page in planning/ui-inventory binds it '
                '(explicit target_revision and current Page identity evidence required; shared paths or a cosmetic binding do not prove identity). The Board and Doctor cannot show where it applies.',
                repairability='DECISION_REQUIRED', severity='WARNING', authority='ACTIVE_TARGET')


DIAGNOSTIC_GROUPS = ('project_attention', 'projection_health', 'framework_compat', 'optional_metadata')
# CS-3 grouping: project_attention may need project-owner/developer action; framework_compat is
# implementation, compatibility or historical-recording information that is not itself a project blockage.
_DIAGNOSTIC_GROUP_BY_CATEGORY = {
    'AUTHORITY_CONFLICT': 'project_attention', 'REFERENCE_AMBIGUOUS': 'project_attention',
    'DUPLICATE_ID': 'project_attention', 'ACTIVE_REVISION_UNBOUND': 'project_attention',
    'PLAN_PROCESS_STATE_CONFLICT': 'project_attention', 'MOCKETEER_REVISION_UNRECONCILED': 'project_attention',
    'SYNTAX_ERROR': 'projection_health', 'SCHEMA_ERROR': 'projection_health', 'ID_MISMATCH': 'projection_health',
    'REFERENCE_MISSING': 'projection_health', 'MISSING': 'projection_health', 'STALE': 'projection_health',
    'FRESHNESS_UNKNOWN': 'projection_health',
    'LEGACY_VARIANT': 'framework_compat', 'UNSUPPORTED_VARIANT': 'framework_compat',
    'DONE_BASIS_NOT_RECORDED': 'framework_compat', 'CHANGE_SET_SCHEMA_INVALID': 'framework_compat',
    'EXPECTATION_MISSING': 'framework_compat', 'WAVE_RECONCILIATION_REQUIRED': 'framework_compat',
    'UNASSIGNED': 'optional_metadata',
}


def diagnostic_group(category: str, blocking: bool = False) -> str:
    """Deterministic CS-3 presentation group; never changes severity, blocking or compatibility."""
    if category == 'WAVE_ASSIGNMENT_MISSING':
        return 'projection_health' if blocking else 'optional_metadata'
    return _DIAGNOSTIC_GROUP_BY_CATEGORY.get(category, 'projection_health')

def diagnostic_summary(diagnostics: list[dict]) -> dict[str, Any]:
    """Count existing Doctor findings without changing severity or blocking semantics."""
    def counts(field: str, items: list[dict]) -> dict[str, int]:
        result: dict[str, int] = {}
        for item in items:
            key = str(item.get(field) or 'UNKNOWN')
            result[key] = result.get(key, 0) + 1
        return dict(sorted(result.items()))

    unsupported = [item for item in diagnostics if item.get('repairability') == 'UNSUPPORTED']
    return {
        'total': len(diagnostics),
        'blocking': sum(1 for item in diagnostics if item.get('blocking') is True),
        'by_severity': counts('severity', diagnostics),
        'by_repairability': counts('repairability', diagnostics),
        'by_category': counts('category', diagnostics),
        'by_area': counts('affected_board_area', diagnostics),
        'unsupported_by_category': counts('category', unsupported),
        'unsupported_by_area': counts('affected_board_area', unsupported),
    }


DOCUMENT_RESULT_RULE_VERSION = 1
_DOCUMENT_RESULT_CACHE_LIMIT = 8192
_DOCUMENT_RESULT_CACHE: dict[tuple, dict] = {}
_DOCUMENT_RESULT_LOCK = threading.Lock()


def _document_result(relative: str, value: dict, contract: tuple[str, str]) -> dict:
    """Pure per-document compatibility result; depends only on path, content and schemas."""
    calls: list[tuple[tuple, dict]] = []

    def add(*args: Any, **kwargs: Any) -> None:
        calls.append((args, kwargs))

    projected, projection_rules, projection_conflicts = compatibility_projection(relative, value)
    if projection_conflicts:
        for fields in projection_conflicts:
            add('AUTHORITY_CONFLICT', relative, contract[1],
                'Legacy and current fields disagree; no compatibility projection was applied.',
                blocking=True, repairability='DECISION_REQUIRED', authority=fields)
    projection_valid = not projection_conflicts and not raw_schema_errors(relative, projected)
    document = projected if projection_valid else value
    if projection_rules and projection_valid:
        for rule in projection_rules:
            add('LEGACY_VARIANT', relative, contract[1],
                'Legacy Task inspect target can be migrated losslessly to the typed contract; source bytes are unchanged.'
                if rule == 'task_inspect_typed_target_v1'
                else 'Known legacy shape is projected read-only to the current contract; source bytes are unchanged.',
                repairability='SAFE_DETERMINISTIC',
                repair={'task_inspect_typed_target_v1': 'TASK_INSPECT_TYPED_TARGET_V1',
                        'legacy_decision_aliases_v1': 'LEGACY_DECISION_ALIASES_V1'}.get(rule, rule),
                authority='.mxagile/policies/project-compatibility.md', severity='INFO')
    errors = schema_errors(relative, value)
    if errors:
        issues = [] if any(error in ('SCHEMA_UNAVAILABLE', 'VALIDATOR_UNAVAILABLE') for error in errors) else schema_diagnostics(relative, value)
        if not issues:
            issues = [('Schema validation unavailable: ' + ', '.join(errors) + '.', 'UNSUPPORTED',
                       f'.mxagile/schemas/{contract[0]}.schema.json')]
        for message, repairability, authority in issues:
            add('SCHEMA_ERROR', relative, contract[1], message,
                blocking=True, repairability=repairability, authority=authority)
    return {"calls": tuple(calls), "invalid": bool(errors), "document": copy.deepcopy(document)}


def _store_document_result(key: tuple, result: dict) -> None:
    # Unavailable validators are an environment state, never a cacheable content result.
    if any(call[0][0] == 'SCHEMA_ERROR' and str(call[0][3]).startswith('Schema validation unavailable') for call in result["calls"]):
        return
    with _DOCUMENT_RESULT_LOCK:
        if len(_DOCUMENT_RESULT_CACHE) >= _DOCUMENT_RESULT_CACHE_LIMIT:
            _DOCUMENT_RESULT_CACHE.pop(next(iter(_DOCUMENT_RESULT_CACHE)))
        _DOCUMENT_RESULT_CACHE[key] = result


def _replay_document_result(result: dict, counts: dict, documents: dict, relative: str, add: Any) -> None:
    counts['parsed'] += 1
    documents[relative] = copy.deepcopy(result["document"])
    for args, kwargs in result["calls"]:
        add(*args, **kwargs)
    if result["invalid"]:
        counts['invalid'] += 1


def compatibility_report(
    root: Path,
    status: dict,
    hashes: dict[str, str],
    *,
    parsed_documents: dict[str, dict[str, Any]] | None = None,
) -> dict:
    diagnostics: list[dict] = []
    coverage: dict[str, dict[str, int]] = {}
    documents: dict[str, dict] = {}
    parsed_documents = parsed_documents or {}
    assignment_cache: dict[str, tuple[str, dict | None]] = {}
    for relative, snapshot in parsed_documents.items():
        if not relative.startswith('planning/checklists/') or not isinstance(snapshot.get('raw'), bytes):
            continue
        try:
            parsed_checklist = load_yaml(snapshot['raw'].decode('utf-8-sig'))
            assignment_cache[relative] = ('available', parsed_checklist if isinstance(parsed_checklist, dict) else None)
        except (UnicodeError, yaml.YAMLError):
            assignment_cache[relative] = ('ambiguous', None)

    def add(category: str, source: str | None, area: str, message: str, *,
            blocking: bool = False, repairability: str = 'UNSUPPORTED', repair: str | None = None,
            line: int | None = None, column: int | None = None, authority: str | None = None,
            severity: str = 'WARNING') -> None:
        identity = json.dumps([category, source, area, line, column, repair, authority], sort_keys=True)
        entry = {
            'diagnostic_id': 'DX-' + hashlib.sha256(identity.encode()).hexdigest()[:16],
            'severity': 'ERROR' if blocking else severity, 'category': category,
            'source_path': source, 'line': line, 'column': column,
            'artifact_type': (contract_for(source) or ('unknown', area))[0] if source else 'unknown',
            'affected_board_area': area, 'message': message, 'repairability': repairability,
            'proposed_repair_type': repair, 'authority': authority,
            'blocking': blocking,
            'diagnostic_group': diagnostic_group(category, blocking),
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
            if category == 'DUPLICATE_ID' and contract and contract[0] == 'page':
                continue
            repairable = 'AGENT_REPAIRABLE' if category in ('SYNTAX_ERROR', 'SCHEMA_ERROR') else 'UNSUPPORTED'
            add(category, source, contract[1] if contract else 'sources',
                ('Canonical artifact is invalid' + (': ' + gap['parser_cause'] if gap.get('parser_cause') else '') + '.') if category != 'LEGACY_VARIANT' else 'Descriptive legacy filename accepted; canonical identity remains the artifact ID field.',
                blocking=category != 'LEGACY_VARIANT', repairability=repairable,
                line=gap.get('line'), column=gap.get('column'),
                authority='.mxagile/policies/project-compatibility.md',
                severity='INFO' if category == 'LEGACY_VARIANT' else 'WARNING')
        elif gap['code'] == 'CAPTURE_ID_CONFLICT':
            add('AUTHORITY_CONFLICT', source, 'verification', 'Capture ID has no unique canonical binding.',
                blocking=True, repairability='DECISION_REQUIRED', authority='capture_id')
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
    schema_context = _SCHEMA_CONTEXT.get()
    schema_key = (
        DOCUMENT_RESULT_RULE_VERSION,
        jsonschema is not None,
        schema_context["signatures"] if schema_context is not None else _schema_signatures(SCHEMA_ROOT),
    )
    for relative in paths:
        contract = contract_for(relative)
        counts = coverage.setdefault(contract[0], {'recognized': 0, 'parsed': 0, 'invalid': 0, 'unassigned': 0})
        counts['recognized'] += 1
        path = safe_file(root, relative)
        if path is None:
            counts['invalid'] += 1
            continue
        snapshot = parsed_documents.get(relative)
        if snapshot is not None:
            raw = snapshot.get('raw')
            value = snapshot.get('value')
            if snapshot.get('state') != 'available' or not isinstance(raw, bytes) or not isinstance(value, dict):
                counts['invalid'] += 1
                continue
            if hashlib.sha256(raw).hexdigest() != hashes[relative]:
                add('AUTHORITY_CONFLICT', relative, contract[1], 'Source changed during diagnosis; rerun Doctor.', blocking=True)
                continue
            cached = _DOCUMENT_RESULT_CACHE.get((relative, hashes[relative], schema_key))
            if cached is not None:
                _replay_document_result(cached, counts, documents, relative, add)
                continue
            value = copy.deepcopy(value)
        else:
            try:
                raw = path.read_bytes()
                if hashlib.sha256(raw).hexdigest() != hashes[relative]:
                    add('AUTHORITY_CONFLICT', relative, contract[1], 'Source changed during diagnosis; rerun Doctor.', blocking=True)
                    continue
                cached = _DOCUMENT_RESULT_CACHE.get((relative, hashes[relative], schema_key))
                if cached is not None:
                    _replay_document_result(cached, counts, documents, relative, add)
                    continue
                value = json.loads(raw.decode('utf-8-sig')) if path.suffix == '.json' else load_yaml(raw.decode('utf-8-sig'))
            except (OSError, UnicodeError, ValueError, yaml.YAMLError):
                counts['invalid'] += 1
                continue
        if not isinstance(value, dict):
            counts['invalid'] += 1
            continue
        result = _document_result(relative, value, contract)
        _store_document_result((relative, hashes[relative], schema_key), result)
        _replay_document_result(result, counts, documents, relative, add)

    identities: dict[str, list[str]] = {}
    for relative, value in documents.items():
        if isinstance(value.get('ID'), str):
            identities.setdefault(value['ID'], []).append(relative)
    requirement_identities: dict[str, list[str]] = {}
    for relative, value in documents.items():
        if (contract_for(relative)[0] == 'requirement' and isinstance(value.get('ID'), str)
                and value['ID'] == PurePosixPath(relative).stem and not schema_errors(relative, value)):
            requirement_identities.setdefault(value['ID'], []).append(relative)
    page_identities: dict[str, list[str]] = {}
    page_names: dict[str, list[str]] = {}
    page_inventory_present = any(contract_for(relative)[0] == 'page' for relative in documents)
    for relative, value in documents.items():
        if (contract_for(relative)[0] == 'page' and isinstance(value.get('page_id'), str)
                and not schema_errors(relative, value)):
            page_identities.setdefault(value['page_id'], []).append(relative)
            if isinstance(value.get('page_name'), str) and value['page_name']:
                page_names.setdefault(value['page_name'], []).append(relative)
    for page_id, paths_for_id in page_identities.items():
        if len(paths_for_id) > 1:
            for relative in paths_for_id:
                add('DUPLICATE_ID', relative, 'references', 'Page logical identity occurs in multiple UI inventory artifacts.',
                    blocking=True, repairability='DECISION_REQUIRED', authority='page_id')
    for paths_for_id in identities.values():
        if len(paths_for_id) > 1:
            for relative in paths_for_id:
                add('DUPLICATE_ID', relative, contract_for(relative)[1], 'ID occurs in multiple canonical artifacts.',
                    blocking=True, repairability='DECISION_REQUIRED')

    for relative, value in documents.items():
        if contract_for(relative)[0] != 'finding' or value.get('lifecycle_status') != 'SUPERSEDED':
            continue
        successor = value.get('superseded_by')
        targets = identities.get(successor, []) if isinstance(successor, str) else []
        if len(targets) != 1 or targets[0] == relative:
            category = 'REFERENCE_MISSING' if not targets else 'REFERENCE_AMBIGUOUS'
            add(category, relative, 'findings', 'Superseded Finding must reference one different canonical Finding ID.',
                blocking=True, repairability='DECISION_REQUIRED', authority='superseded_by')

    for relative, value in documents.items():
        if contract_for(relative)[0] != 'requirement':
            continue
        req_status = value.get('status')
        if req_status == 'superseded':
            successor = value.get('superseded_by')
            targets = requirement_identities.get(successor, []) if isinstance(successor, str) else []
            if not isinstance(successor, str) or not successor:
                category = 'REFERENCE_MISSING'
            elif len(targets) != 1 or targets[0] == relative:
                category = 'REFERENCE_MISSING' if not targets else 'REFERENCE_AMBIGUOUS'
            else:
                continue
            add(category, relative, 'requirements',
                'Superseded Requirement needs one different, unique canonical successor; no successor is inferred.',
                blocking=True, repairability='DECISION_REQUIRED', authority='superseded_by')
        elif req_status in ('obsolete', 'retired', 'invalid'):
            if value.get('superseded_by'):
                add('AUTHORITY_CONFLICT', relative, 'requirements',
                    'Obsolete/retired Requirement is retired without replacement and must not declare superseded_by.',
                    blocking=True, repairability='DECISION_REQUIRED', authority='superseded_by')
            impact = value.get('implementation_impact')
            if isinstance(impact, dict) and impact.get('disposition') == 'NEEDS_HUMAN' and not impact.get('decision_ref'):
                add('AUTHORITY_CONFLICT', relative, 'requirements',
                    'Obsolete/retired Requirement implementation impact requires an explicit human decision before keeping or removing artifacts.',
                    blocking=True, repairability='DECISION_REQUIRED', authority='implementation_impact')
        elif req_status == 'split':
            replacements = value.get('replacement_ids')
            if not isinstance(replacements, list) or len(set(replacements)) < 2:
                add('REFERENCE_MISSING', relative, 'requirements',
                    'Split Requirement needs at least two distinct canonical replacement_ids.',
                    blocking=True, repairability='DECISION_REQUIRED', authority='replacement_ids')
            elif any(not isinstance(item, str) or not requirement_identities.get(item) or requirement_identities.get(item) == [relative] for item in replacements):
                add('REFERENCE_MISSING', relative, 'requirements',
                    'Split Requirement replacement_ids must resolve to existing distinct canonical Requirements.',
                    blocking=True, repairability='DECISION_REQUIRED', authority='replacement_ids')
            elif any(len(requirement_identities.get(item, [])) != 1 for item in replacements):
                add('REFERENCE_AMBIGUOUS', relative, 'requirements',
                    'Split Requirement replacement_ids resolve to multiple canonical targets.',
                    blocking=True, repairability='DECISION_REQUIRED', authority='replacement_ids')
        elif req_status in ('merged', 'duplicate'):
            target_id = value.get('merged_into') or value.get('superseded_by')
            targets = requirement_identities.get(target_id, []) if isinstance(target_id, str) else []
            if not isinstance(target_id, str) or not target_id or not targets or targets == [relative]:
                add('REFERENCE_MISSING', relative, 'requirements',
                    'Merged/duplicate Requirement needs one different, unique canonical merged_into or superseded_by target.',
                    blocking=True, repairability='DECISION_REQUIRED', authority='merged_into')
            elif len(targets) > 1:
                add('REFERENCE_AMBIGUOUS', relative, 'requirements',
                    'Merged/duplicate Requirement target resolves to multiple canonical Requirements.',
                    blocking=True, repairability='DECISION_REQUIRED', authority='merged_into')
        elif req_status == 'ambiguous':
            add('AUTHORITY_CONFLICT', relative, 'requirements',
                'Requirement has unresolved AMBIGUOUS lifecycle status.',
                blocking=True, repairability='DECISION_REQUIRED', authority='status')

    waves_doc = documents.get('planning/lifecycle/process-state.yaml', {}).get('waves', {})
    waves = set(waves_doc) if isinstance(waves_doc, dict) else set()
    reference_fields = ('req', 'requirement_ids', 'affected_requirements', 'decision_ids', 'depends_on', 'test_contract_ids')
    for relative, value in documents.items():
        area = contract_for(relative)[1]
        if contract_for(relative)[0] == 'page':
            for legacy, current in (('page', 'page_id'), ('source', 'source_mockup')):
                if legacy in value and current in value and value[legacy] != value[current]:
                    add('AUTHORITY_CONFLICT', relative, area, 'Legacy and current UI inventory fields disagree.',
                        blocking=True, repairability='DECISION_REQUIRED', authority=f'{legacy}/{current}')
        for field in reference_fields:
            refs = value.get(field, [])
            if not isinstance(refs, list):
                continue
            targets = requirement_identities if contract_for(relative)[0] == 'test-contract' and field == 'requirement_ids' else identities
            if any(not isinstance(ref, str) or ref not in targets for ref in refs):
                add('REFERENCE_MISSING', relative, area, 'An artifact ID reference has no unique canonical target.',
                    blocking=True, repairability='AGENT_REPAIRABLE', authority=field)
            elif any(len(targets[ref]) != 1 for ref in refs):
                add('REFERENCE_AMBIGUOUS', relative, area, 'An artifact ID reference has multiple canonical targets.',
                    blocking=True, repairability='DECISION_REQUIRED', authority=field)
        if contract_for(relative)[0] == 'test-contract':
            for point in value.get('proof_points', []) if isinstance(value.get('proof_points'), list) else []:
                traceability = point.get('traceability', {}) if isinstance(point, dict) else {}
                refs = traceability.get('requirement_ids', []) if isinstance(traceability, dict) else []
                if not isinstance(refs, list):
                    continue
                if any(not isinstance(ref, str) or not requirement_identities.get(ref) for ref in refs):
                    add('REFERENCE_MISSING', relative, area,
                        'A proof-point Requirement reference has no canonical target.',
                        blocking=True, repairability='AGENT_REPAIRABLE',
                        authority='proof_points[].traceability.requirement_ids')
                elif any(len(requirement_identities[ref]) != 1 for ref in refs):
                    add('REFERENCE_AMBIGUOUS', relative, area,
                        'A proof-point Requirement reference has multiple canonical targets.',
                        blocking=True, repairability='DECISION_REQUIRED',
                        authority='proof_points[].traceability.requirement_ids')
        if contract_for(relative)[0] == 'page' and not schema_errors(relative, value):
            for field in ('source_mockup', 'target_mockup'):
                reference = value.get(field)
                if isinstance(reference, str) and safe_file(root, reference) is None:
                    add('REFERENCE_MISSING', relative, area, 'Page mockup path is missing or unsafe.',
                        blocking=True, repairability='AGENT_REPAIRABLE', authority=field)
            for link in value.get('navigation', []) if isinstance(value.get('navigation'), list) else []:
                target = link.get('leads_to_page') if isinstance(link, dict) else None
                if not isinstance(target, str) or not page_inventory_present:
                    continue
                targets = page_identities.get(target, []) or page_names.get(target, [])
                if not targets:
                    add('REFERENCE_MISSING', relative, area, 'Navigation target has no canonical Page target.',
                        blocking=True, repairability='AGENT_REPAIRABLE', authority='navigation[].leads_to_page')
                elif len(targets) != 1:
                    add('REFERENCE_AMBIGUOUS', relative, area, 'Navigation target resolves to multiple Pages.',
                        blocking=True, repairability='DECISION_REQUIRED', authority='navigation[].leads_to_page')
            revision_id = value.get('target_revision')
            mockup_name = value.get('mockup_name')
            if isinstance(revision_id, str):
                revisions = [item for path, item in documents.items()
                             if contract_for(path)[0] == 'revision' and item.get('revision_id') == revision_id
                             and (not isinstance(mockup_name, str) or item.get('mockup_name') == mockup_name)]
                if not revisions:
                    add('REFERENCE_MISSING', relative, area, 'Page target revision has no canonical revision manifest.',
                        blocking=True, repairability='AGENT_REPAIRABLE', authority='mockup_name/target_revision')
                elif len(revisions) > 1:
                    add('REFERENCE_AMBIGUOUS', relative, area, 'Page target revision resolves to multiple manifests.',
                        blocking=True, repairability='DECISION_REQUIRED', authority='mockup_name/target_revision')
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
            manifest_wave = value.get('wave_id')
            if not isinstance(manifest_wave, str) or manifest_wave not in waves:
                add('WAVE_ASSIGNMENT_MISSING', relative, area, 'Evidence manifest has no resolvable canonical wave.',
                    repairability='DECISION_REQUIRED', authority='planning/lifecycle/process-state.yaml')
            for entry in value.get('entries', []) if isinstance(value.get('entries'), list) else []:
                if not isinstance(entry, dict):
                    continue
                screen_id = entry.get('screen_id')
                if isinstance(screen_id, str) and page_inventory_present and len(page_identities.get(screen_id, [])) != 1:
                    category = 'REFERENCE_AMBIGUOUS' if page_identities.get(screen_id) else 'REFERENCE_MISSING'
                    add(category, relative, area, 'Evidence screen reference has no unique canonical Page target.',
                        blocking=True, repairability='DECISION_REQUIRED' if category == 'REFERENCE_AMBIGUOUS' else 'AGENT_REPAIRABLE',
                        authority='entries[].screen_id')
                traceability = entry.get('traceability', {})
                references = traceability.get('requirements', []) if isinstance(traceability, dict) else []
                if isinstance(references, list) and any(not isinstance(ref, str) or len(requirement_identities.get(ref, [])) != 1 for ref in references):
                    add('REFERENCE_MISSING', relative, area, 'Evidence requirement references are missing or ambiguous.',
                        blocking=True, repairability='AGENT_REPAIRABLE', authority='traceability.requirements')
                artifacts = entry.get('actual_evidence', [])
                source_paths = [artifact.get('path') for artifact in artifacts if isinstance(artifact, dict)] if isinstance(artifacts, list) else []
                if entry.get('parity_report_path'):
                    source_paths.append(entry['parity_report_path'])
                if any(not isinstance(source, str) or not source.startswith('planning/') or not safe_file(root, source) for source in source_paths):
                    add('REFERENCE_MISSING', relative, area, 'Evidence artifact paths are missing or unsafe.',
                        blocking=True, repairability='AGENT_REPAIRABLE', authority='actual_evidence')
        if contract_for(relative)[0] == 'parity-verification' and page_inventory_present:
            page_id = value.get('page_id')
            if isinstance(page_id, str) and len(page_identities.get(page_id, [])) != 1:
                category = 'REFERENCE_AMBIGUOUS' if page_identities.get(page_id) else 'REFERENCE_MISSING'
                add(category, relative, area, 'Parity report has no unique canonical Page target.',
                    blocking=True, repairability='DECISION_REQUIRED' if category == 'REFERENCE_AMBIGUOUS' else 'AGENT_REPAIRABLE',
                    authority='page_id')
        if area == 'tasks':
            task_inspect = documents.get(relative, {}).get('inspect')
            expectation = task_inspect.get('expect') if isinstance(task_inspect, dict) else None
            if (isinstance(task_inspect, dict) and 'type' in task_inspect
                    and 'target' in task_inspect
                    and (not isinstance(expectation, str) or not expectation.strip())):
                add('EXPECTATION_MISSING', relative, area,
                    'Inspect target is valid, but no authoritative semantic expectation is recorded.',
                    blocking=True, repairability='DECISION_REQUIRED', authority='inspect.expect')
            state, wave, provenance = assignment(root, value, waves, assignment_cache)
            if state not in ('explicit',):
                coverage['task']['unassigned'] += 1
                review_authority = wave_review_authority(value, documents, waves) if state in ('ambiguous', 'missing') else None
                add('AUTHORITY_CONFLICT' if state == 'conflict' else 'WAVE_ASSIGNMENT_MISSING', relative, area,
                    'Task wave assignment needs reconciliation.', blocking=state == 'conflict',
                    repairability='SAFE_DETERMINISTIC' if state == 'derived' else ('AGENT_REPAIRABLE' if review_authority else 'DECISION_REQUIRED'),
                    repair='ADD_WAVE_ID' if state == 'derived' else None,
                    authority=review_authority or provenance or 'planning/lifecycle/process-state.yaml')
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
            for path in sorted(parent.glob('*.md')) + sorted(parent.glob('*.yml' if pattern.endswith('.yml') else '*.yaml')) + sorted(parent.glob('*.json')):
                relative = path.relative_to(root).as_posix()
                if path.stem.lower() in ('readme', 'template'):
                    continue
                if relative not in allowed and safe_file(root, relative):
                    hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
                    if artifact == 'decision' and path.suffix == '.md' and re.fullmatch(r'DEC-[0-9]{3,}', path.stem):
                        add('LEGACY_VARIANT', relative, area, 'Historical Decision retained; no current lifecycle status inferred.',
                            severity='INFO', authority='.mxagile/policies/project-compatibility.md')
                        continue
                    add('UNSUPPORTED_VARIANT', relative, area, 'Legacy extension is not consumed by this projection.',
                        repairability='UNSUPPORTED', authority='.mxagile/policies/project-compatibility.md')
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

    _lifecycle_clarity_diagnostics(root, parsed_documents, add)

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


def task_inspect_candidate(relative: str, raw: bytes) -> bytes | None:
    if not contract_for(relative) or contract_for(relative)[0] != 'task':
        return None
    try:
        text = raw.decode('utf-8-sig')
        original = load_yaml(text)
        projected, rules, conflicts = compatibility_projection(relative, original)
        root_node = yaml.compose(text, Loader=CanonicalLoader)
    except (UnicodeError, yaml.YAMLError):
        return None
    if rules != ['task_inspect_typed_target_v1'] or conflicts or schema_errors(relative, original):
        return None
    if not isinstance(root_node, yaml.MappingNode):
        return None
    inspect_nodes = [value for key, value in root_node.value
                     if isinstance(key, yaml.ScalarNode) and key.value == 'inspect']
    if len(inspect_nodes) != 1 or not isinstance(inspect_nodes[0], yaml.MappingNode) or inspect_nodes[0].flow_style:
        return None
    inspect_node = inspect_nodes[0]
    target_types = {'entity', 'microflow', 'association', 'rule', 'snippet', 'page'}
    entries = [(key, value) for key, value in inspect_node.value if isinstance(key, yaml.ScalarNode)]
    legacy = [(key, value) for key, value in entries if key.value in target_types]
    if len(legacy) != 1 or any(key.value not in target_types | {'expect'} for key, _ in entries):
        return None
    key_node, value_node = legacy[0]
    if not isinstance(value_node, yaml.ScalarNode) or key_node.start_mark.line != value_node.start_mark.line or value_node.end_mark.line != key_node.start_mark.line:
        return None
    key_start = key_node.start_mark.index
    value_end = value_node.end_mark.index
    line_start = text.rfind('\n', 0, key_start) + 1
    indent = text[line_start:key_start]
    if indent.strip() or ':' not in text[key_node.end_mark.index:value_node.start_mark.index]:
        return None
    target_text = text[value_node.start_mark.index:value_end]
    newline = '\r\n' if '\r\n' in text else '\n'
    replacement = f'type: {key_node.value}{newline}{indent}target: {target_text}'
    converted = text[:key_start] + replacement + text[value_end:]
    bom = b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b''
    candidate = bom + converted.encode('utf-8')
    try:
        converted_value = load_yaml(converted)
    except yaml.YAMLError:
        return None
    if converted_value != projected or schema_errors(relative, converted_value):
        return None
    return candidate


def legacy_decision_candidate(relative: str, raw: bytes) -> bytes | None:
    if (contract_for(relative) or (None,))[0] != 'decision':
        return None
    try:
        text = raw.decode('utf-8-sig')
        original = load_yaml(text)
        projected, rules, conflicts = compatibility_projection(relative, original)
        node = yaml.compose(text, Loader=CanonicalLoader)
    except (UnicodeError, yaml.YAMLError):
        return None
    if rules != ['legacy_decision_aliases_v1'] or conflicts or raw_schema_errors(relative, projected):
        return None
    if not isinstance(node, yaml.MappingNode) or node.flow_style:
        return None
    edits = []
    aliases = {'decided_at': 'confirmed_at', 'decided_by': 'confirmed_by'}
    for key, value in node.value:
        if not isinstance(key, yaml.ScalarNode):
            return None
        if key.value in aliases:
            if aliases[key.value] in original:
                return None
            edits.append((key.start_mark.index, key.end_mark.index, aliases[key.value]))
        elif key.value in {'status', 'decision_type'} and original.get(key.value) != projected.get(key.value):
            if not isinstance(value, yaml.ScalarNode):
                return None
            edits.append((value.start_mark.index, value.end_mark.index, json.dumps(projected[key.value])))
    for start, end, replacement in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    try:
        if load_yaml(text) != projected:
            return None
    except yaml.YAMLError:
        return None
    return (b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'') + text.encode('utf-8')


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
    assignment_cache: dict[str, tuple[str, dict | None]] = {}
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
        elif diagnostic['proposed_repair_type'] == 'TASK_INSPECT_TYPED_TARGET_V1':
            replacement = task_inspect_candidate(relative, raw)
            if replacement is not None:
                candidates[relative] = replacement, 'TASK_INSPECT_TYPED_TARGET_V1'
        elif diagnostic['proposed_repair_type'] == 'LEGACY_DECISION_ALIASES_V1':
            replacement = legacy_decision_candidate(relative, raw)
            if replacement is not None:
                candidates[relative] = replacement, 'LEGACY_DECISION_ALIASES_V1'
        elif diagnostic['proposed_repair_type'] == 'ADD_WAVE_ID':
            value = load_yaml(raw.decode('utf-8-sig'))
            state, wave, provenance = assignment(root, value, waves, assignment_cache)
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


def repair_plan(root: Path, report: dict, candidate_dir: Path | None = None, *, safe_only: bool = False,
                allowed_types: frozenset[str] | None = None) -> dict:
    candidates = repair_candidates(root, report, candidate_dir)
    if allowed_types is not None:
        candidates = {path: candidate for path, candidate in candidates.items() if candidate[1] in allowed_types}
    if safe_only:
        candidates = {path: candidate for path, candidate in candidates.items() if any(
            item['source_path'] == path and item['proposed_repair_type'] == candidate[1]
            and item['repairability'] == 'SAFE_DETERMINISTIC' for item in report['diagnostics'])}
    entries = []
    for relative, (replacement, kind) in sorted(candidates.items()):
        path = safe_file(root, relative)
        preview = {'before': '[REDACTED TEXT SCALAR]', 'after': '[SAME TEXT SCALAR, QUOTED]' if kind == 'QUOTE_TEXT_SCALAR' else '[REDACTED REVIEWED CANDIDATE]'}
        if kind == 'ADD_WAVE_ID':
            preview = {'field': 'wave_id', 'before': None, 'after': load_yaml(replacement.decode('utf-8-sig'))['wave_id']}
        elif kind == 'TASK_INSPECT_TYPED_TARGET_V1':
            preview = {'field': 'inspect', 'before': 'legacy structured target', 'after': 'typed type/target; expect preserved'}
        entries.append({
            'source_path': relative, 'repair_type': kind,
            'before_fingerprint': digest(path.read_bytes()), 'after_fingerprint': digest(replacement),
            'diagnostic_ids': sorted(item['diagnostic_id'] for item in report['diagnostics'] if item['source_path'] == relative and (item['proposed_repair_type'] == kind or kind == 'AGENT_CANDIDATE' and item['repairability'] == 'AGENT_REPAIRABLE')),
            'preview': preview,
        })
    targeted_diagnostics = {
        diagnostic_id for entry in entries for diagnostic_id in entry['diagnostic_ids']
    }
    contract_fingerprint = digest(b''.join(path.read_bytes() for path in sorted(SCHEMA_ROOT.glob('*.json'))))
    plan = {
        'schema_version': 1, 'source_fingerprint': report['source_fingerprint'],
        'contract_fingerprint': contract_fingerprint,
        'file_scope': [entry['source_path'] for entry in entries], 'repairs': entries,
        'deferred_diagnostic_ids': sorted(item['diagnostic_id'] for item in report['diagnostics']
                          if item['repairability'] != 'UNSUPPORTED'
                          and item['diagnostic_id'] not in targeted_diagnostics),
    }
    if safe_only:
        plan['repairability_scope'] = 'SAFE_DETERMINISTIC'
    if allowed_types is not None:
        plan['allowed_repair_types'] = sorted(allowed_types)
    plan['plan_hash'] = digest(json.dumps(plan, sort_keys=True).encode('utf-8'))
    return plan


def atomic_replace(path: Path, raw: bytes) -> None:
    mode = path.stat().st_mode if path.exists() else 0o600
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


def apply_repair(root: Path, expected_hash: str, candidate_dir: Path | None = None, *, safe_only: bool = False,
                 allowed_types: frozenset[str] | None = None) -> dict:
    from build_project_status import build_status
    before = build_status(root)
    report = before['compatibility']
    plan = repair_plan(root, report, candidate_dir, safe_only=safe_only, allowed_types=allowed_types)
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


CONTRACT_MIGRATION_VERSION = 'core-contract-reconciliation/1'


def contract_migration_validator(schema: dict):
    checker = jsonschema.FormatChecker()

    @checker.checks('date-time', raises=(ValueError, TypeError))
    def valid_timestamp(value):
        if not isinstance(value, str):
            return True
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})', value):
            return False
        return datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).tzinfo is not None

    return jsonschema.Draft7Validator(schema, format_checker=checker)


def projection_integrity(root: Path, core: dict | None = None) -> dict:
    if core is None:
        path = safe_file(root, '.mxagile/state/core-provenance.json')
        core = json.loads(path.read_text(encoding='utf-8-sig')) if path else {}
    manifest_path = safe_file(root, '.mxagile/state/projections-manifest.json')
    if not core.get('distribution') and 'activation_state' not in core and manifest_path is None:
        return {'required': False, 'ready': True, 'reason': None}
    try:
        manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig')) if manifest_path else {}
        if core.get('activation_state') == 'CORE_APPLIED_PROJECTIONS_PENDING' or not core.get('commit') or manifest.get('generated_from_core_commit') != core['commit']:
            raise ValueError('Core/projection identity mismatch or pending activation')
        if manifest.get('schema_version') != '1' or manifest.get('projection_version') not in (None,'2'):
            raise ValueError('Projection manifest format invalid')
        if manifest.get('generator_owned_by') != 'distribution' or manifest.get('generator') != 'generate-mxagile-platform-skills.ps1':
            raise ValueError('Projection ownership not observable')
        if manifest.get('projection_version') == '2':
            outputs = manifest.get('outputs')
            if not isinstance(outputs, list) or not outputs:
                raise ValueError('Projection file proof missing')
            targets = set()
            for output in outputs:
                relative = output['target']
                path = safe_file(root, relative)
                if relative in targets or relative.split('/')[0] not in {'.claude','.github','.agents','.grok','.opencode','.hermes'} or path is None or hashlib.sha256(path.read_bytes()).hexdigest() != output['sha256']:
                    raise ValueError('Projection file binding invalid')
                targets.add(relative)
            names = ('discovery','design-contract','refinement','preservation','business-flows','mockup-generation','handoff')
            mandatory = {f'{host}/skills/mocketeer-{name}/SKILL.md' for host in ('.claude','.github','.agents') for name in names}
            if not mandatory <= targets or not {'.claude','.github','.agents','.grok','.opencode','.hermes'} <= {p.split('/')[0] for p in targets}:
                raise ValueError('Mandatory host projection coverage incomplete')
        return {'required': True, 'ready': True, 'reason': None}
    except (OSError, ValueError, TypeError, KeyError) as exc:
        return {'required': True, 'ready': False, 'reason': str(exc)}


def contract_snapshot(root: Path) -> dict | None:
    directory = root / '.mxagile' / 'schemas'
    if not directory.is_dir() or directory.is_symlink():
        return None
    schemas = {}
    for path in sorted(directory.glob('*.json')):
        if path.is_symlink():
            raise ValueError('Contract schema path is unsafe.')
        value = json.loads(path.read_text(encoding='utf-8-sig'))
        schemas[path.name] = digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode('utf-8'))
    if not schemas:
        return None
    identity = {'contract_version': CONTRACT_MIGRATION_VERSION, 'schemas': schemas}
    return {**identity, 'fingerprint': digest(json.dumps(identity, sort_keys=True, separators=(',', ':')).encode('utf-8'))}


def _migration_state(root: Path) -> tuple[Path, bytes, dict]:
    path = root / '.mxagile' / 'migration' / 'state.yaml'
    current = root
    for part in ('.mxagile', 'migration', 'state.yaml'):
        current /= part
        if current.is_symlink():
            raise ValueError('Migration state path is unsafe.')
    raw = path.read_bytes() if path.exists() else b''
    value = load_yaml(raw.decode('utf-8-sig')) if raw else {}
    if not isinstance(value, dict):
        raise ValueError('Migration state is not a mapping.')
    return path, raw, value


def _save_contract_migration(root: Path, record: dict, expected: bytes) -> bytes:
    path, raw, value = _migration_state(root)
    if raw != expected:
        raise ValueError('Migration history changed concurrently.')
    schema = json.loads((root / '.mxagile' / 'schemas' / 'contract-migration.schema.json').read_text(encoding='utf-8-sig'))
    if jsonschema is None or list(contract_migration_validator(schema).iter_errors(record)):
        raise ValueError('Contract migration record failed validation.')
    text = raw.decode('utf-8-sig')
    newline = '\r\n' if b'\r\n' in raw else '\n'
    block = yaml.safe_dump({'contract_migration': record}, sort_keys=False, allow_unicode=True).replace('\n', newline)
    if 'contract_migration' in value:
        node = yaml.compose(text, Loader=CanonicalLoader)
        key, child = next((key, child) for key, child in node.value if key.value == 'contract_migration')
        if key.start_mark.column != 0 or not isinstance(child, yaml.MappingNode) or child.flow_style:
            raise ValueError('Migration record cannot be updated surgically.')
        lines = text.splitlines(keepends=True)
        start = sum(len(line) for line in lines[:key.start_mark.line])
        end_line = key.start_mark.line + 1
        while end_line < len(lines) and (not lines[end_line].strip() or lines[end_line][0].isspace()):
            end_line += 1
        end = sum(len(line) for line in lines[:end_line])
        text = text[:start] + block + text[end:]
    else:
        text += (newline if text and not text.endswith(('\r', '\n')) else '') + block
    replacement = (b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'') + text.encode('utf-8')
    parsed = load_yaml(replacement.decode('utf-8-sig'))
    if {k: v for k, v in parsed.items() if k != 'contract_migration'} != {k: v for k, v in value.items() if k != 'contract_migration'}:
        raise ValueError('Migration history would change.')
    if replacement != raw:
        path.parent.mkdir(parents=True, exist_ok=True)
        atomic_replace(path, replacement)
    return replacement


def reconcile_contract(root: Path, *, apply_safe: bool = False, repair_sources: bool = True, persist: bool = True,
                       contract_only: bool = False) -> dict:
    from build_project_status import build_status
    root = root.resolve()
    target = contract_snapshot(root)
    if target is None:
        raise ValueError('Current artifact contract is not observable.')
    provenance_path = safe_file(root, '.mxagile/state/core-provenance.json')
    provenance = json.loads(provenance_path.read_text(encoding='utf-8-sig')) if provenance_path else {}
    if provenance.get('artifact_contract') != target:
        raise ValueError('Installed contract differs from current Core provenance.')
    if apply_safe and not projection_integrity(root, provenance)['ready']:
        raise ValueError('Projection recovery must finish before contract writes.')
    transaction_path = safe_file(root, '.mxagile/state/update-transaction.json')
    if apply_safe and transaction_path:
        transaction = json.loads(transaction_path.read_text(encoding='utf-8-sig'))
        if (transaction.get('state') != 'UPDATE_IN_PROGRESS' or transaction.get('current_stage') != 'POST_UPDATE_DOCTOR'
                or not {'CORE_UPDATE', 'COMPANY_LAYER_UPDATE'} <= set(transaction.get('completed_stages', []))):
            raise ValueError('Update recovery must finish its installation stages before contract writes.')
    _, raw, state = _migration_state(root)
    previous = state.get('contract_migration') or {}
    if previous:
        schema = json.loads((root / '.mxagile' / 'schemas' / 'contract-migration.schema.json').read_text(encoding='utf-8-sig'))
        if jsonschema is None or list(contract_migration_validator(schema).iter_errors(previous)):
            raise ValueError('Prior contract migration record is invalid.')
    same_target = previous.get('target') == target
    if apply_safe and (repair_sources or persist) and any(item.get('result') == 'PENDING' for item in previous.get('resolution_receipts', [])):
        raise ResolutionFailure('RESOLUTION_RECOVERY_REQUIRED')
    report = build_status(root)['compatibility']
    allowed_types = frozenset({'LEGACY_DECISION_ALIASES_V1', 'TASK_INSPECT_TYPED_TARGET_V1'}) if contract_only else None
    plan = repair_plan(root, report, safe_only=True, allowed_types=allowed_types)
    required = not same_target or previous.get('status') != 'COMPLETE' or bool(plan['repairs']) or report['compatibility'] == 'BLOCKED'
    if not required:
        return {'stage': 'CONTRACT_MIGRATION_CHECKED', 'read_only': True, 'required': False, 'migration': previous, 'plan': plan, 'doctor': report}
    record = {
        'schema_version': '1', 'status': 'PLANNED',
        'source': previous.get('source') if same_target else provenance.get('previous_artifact_contract'),
        'target': target,
        'from_core_commit': previous.get('from_core_commit') if same_target else provenance.get('previous_commit'),
        'to_core_commit': provenance.get('commit'),
        'plan_hash': plan['plan_hash'], 'planned_repairs': plan['repairs'],
        'applied': list(previous.get('applied', [])) if same_target else [],
        'checked_source_fingerprint': report['source_fingerprint'],
        'decision_references': [], 'completed_at': None,
    }
    if previous.get('resolution_receipts'):
        if not same_target and any(item.get('result') == 'PENDING' for item in previous['resolution_receipts']):
            raise ResolutionFailure('RESOLUTION_RECOVERY_REQUIRED')
        record['resolution_receipts'] = copy.deepcopy(previous['resolution_receipts'])
    legacy_partial = state.get('status') not in (None, 'complete') or state.get('artifact_canonicalization') == 'in_progress'
    if apply_safe and not legacy_partial and repair_sources and persist:
        raw = _save_contract_migration(root, record, raw)
        for entry in previous.get('planned_repairs', []) if same_target else []:
            path = safe_file(root, entry['source_path'])
            if path and digest(path.read_bytes()) == entry['after_fingerprint']:
                record['applied'].append(entry['source_path'])
        try:
            applied = apply_repair(root, plan['plan_hash'], safe_only=True, allowed_types=allowed_types)
        except Exception:
            record['status'] = 'FAILED'
            _save_contract_migration(root, record, raw)
            raise
        record['applied'] = sorted(set(record['applied'] + applied['applied']))
        report = applied['compatibility']
    if apply_safe:
        blocking = [item for item in report['diagnostics'] if item['blocking']]
        decisions = [item for item in blocking if item['repairability'] == 'DECISION_REQUIRED']
        record['status'] = 'NEEDS_HUMAN' if decisions else ('NEEDS_REVIEW' if blocking or legacy_partial else 'COMPLETE')
        record['decision_references'] = [{key: item[key] for key in ('diagnostic_id', 'source_path', 'authority', 'category', 'repairability') if key in item} for item in blocking]
        migration_schema = json.loads((root / '.mxagile/schemas/contract-migration.schema.json').read_bytes())
        if 'resolution' in migration_schema['properties']['decision_references']['items']['properties']:
            for reference in record['decision_references']:
                resolution = _human_resolution_contract(root, record, reference)
                if resolution:
                    reference['resolution'] = resolution
        record['checked_source_fingerprint'] = report['source_fingerprint']
        if record['status'] == 'COMPLETE':
            record['completed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        if same_target and previous.get('status') == record['status'] and previous.get('checked_source_fingerprint') == record['checked_source_fingerprint'] and not plan['repairs']:
            record = previous
        if persist:
            _save_contract_migration(root, record, raw)
    return {'stage': 'CONTRACT_MIGRATION_CHECKED', 'read_only': not (apply_safe and persist), 'required': True, 'migration': record, 'plan': plan, 'doctor': report}


class ResolutionFailure(ValueError):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def migration_identity(record: dict) -> str:
    identity = {key: record.get(key) for key in ('source', 'target', 'from_core_commit', 'to_core_commit')}
    return digest(json.dumps(identity, sort_keys=True).encode())


def _human_resolution_contract(root: Path, record: dict, diagnostic: dict) -> dict | None:
    relative = diagnostic.get('source_path')
    if (diagnostic.get('repairability') != 'DECISION_REQUIRED' or diagnostic.get('authority') != 'superseded_by'
            or diagnostic.get('category') != 'REFERENCE_MISSING' or not isinstance(relative, str)
            or not re.fullmatch(r'requirements/REQ-[0-9]{3,}\.yml', relative)):
        return None
    path = safe_file(root, relative)
    value = load_yaml(path.read_bytes()) if path else None
    if not isinstance(value, dict) or value.get('ID') != Path(relative).stem or value.get('status') != 'superseded' or value.get('superseded_by') not in (None, ''):
        return None
    return {'diagnostic_id': diagnostic['diagnostic_id'], 'migration_id': migration_identity(record),
            'resolution_type': 'requirement_successor', 'artifact_id': value.get('ID'), 'source_path': relative,
            'field': 'superseded_by', 'current_source_fingerprint': digest(path.read_bytes()),
            'target_contract': record['target']['fingerprint'],
            'allowed_value_shape': {'type': 'string', 'pattern': '^REQ-[0-9]{3,}$'}, 'human_decision_status': 'OPEN'}


def human_resolution_contracts(root: Path) -> list[dict]:
    from build_project_status import build_status
    root = root.resolve()
    _, _, state = _migration_state(root)
    record = state.get('contract_migration') or {}
    if record.get('status') != 'NEEDS_HUMAN':
        return []
    diagnostics = build_status(root)['compatibility']['diagnostics']
    persisted = {item['diagnostic_id']: item for item in record.get('decision_references', [])}
    result = []
    for diagnostic in diagnostics:
        reference = persisted.get(diagnostic['diagnostic_id'])
        if not reference or any(reference.get(k) != diagnostic.get(k) for k in ('source_path', 'authority', 'category')):
            continue
        contract = _human_resolution_contract(root, record, diagnostic)
        if contract:
            result.append(contract)
    return result


def _successor_value(root: Path, source_id: str, value: str) -> None:
    if not isinstance(value, str) or not re.fullmatch(r'REQ-[0-9]{3,}', value):
        raise ResolutionFailure('INVALID_RESOLUTION_VALUE')
    seen = {source_id}
    successor = value
    while successor:
        if successor in seen:
            raise ResolutionFailure('INVALID_REQUIREMENT_REFERENCE')
        seen.add(successor)
        matches = []
        for path in (root / 'requirements').glob('*.yml'):
            safe = safe_file(root, path.relative_to(root).as_posix())
            if safe is None:
                raise ResolutionFailure('INVALID_REQUIREMENT_REFERENCE')
            document = load_yaml(safe.read_bytes())
            if isinstance(document, dict) and document.get('ID') == successor:
                matches.append((path, document))
        if len(matches) != 1 or matches[0][0].name != successor + '.yml':
            raise ResolutionFailure('INVALID_REQUIREMENT_REFERENCE')
        path, document = matches[0]
        projected = compatibility_projection(path.relative_to(root).as_posix(), document)[0]
        if not schema_validator(root / '.mxagile/schemas/requirement.schema.json').is_valid(projected):
            raise ResolutionFailure('INVALID_REQUIREMENT_REFERENCE')
        successor = document.get('superseded_by') if document.get('status') == 'superseded' else None
        if document.get('status') == 'superseded' and not successor:
            raise ResolutionFailure('INVALID_REQUIREMENT_REFERENCE')


def prepare_human_resolution(root: Path, *, diagnostic_id: str, migration_id: str, source_path: str,
                             field: str, source_fingerprint: str, value: str, human_reference: str,
                             human_confirmed: bool, run_id: str) -> dict:
    from build_project_status import build_status
    from projection_io import safe_path
    root = root.resolve()
    if os.path.lexists(root / '.mxagile/state/runs/framework-update-recovery.json'):
        from framework_update_recovery import require_restarted
        try:
            require_restarted(root)
        except ValueError as exc:
            raise ResolutionFailure(str(exc)) from None
    for relative in ('.mxagile/state/core-provenance.json', '.mxagile/migration/state.yaml', '.mxagile/schemas', source_path or ''):
        try:
            safe_path(root, relative)
        except (OSError, ValueError):
            raise ResolutionFailure('STALE_RESOLUTION') from None
    if human_confirmed is not True or not isinstance(human_reference, str) or not re.fullmatch(r'USER-[A-Za-z0-9-]{4,120}', human_reference):
        raise ResolutionFailure('HUMAN_AUTHORIZATION_REQUIRED')
    if not isinstance(run_id, str) or not re.fullmatch(r'RUN-[A-Za-z0-9-]{4,80}', run_id):
        raise ResolutionFailure('RESOLUTION_RUN_REQUIRED')
    provenance_path = safe_file(root, '.mxagile/state/core-provenance.json')
    provenance = json.loads(provenance_path.read_bytes()) if provenance_path else {}
    _, raw, state = _migration_state(root)
    record = state.get('contract_migration') or {}
    schema_path = safe_file(root, '.mxagile/schemas/contract-migration.schema.json')
    migration_schema = json.loads(schema_path.read_bytes()) if schema_path else {}
    if 'resolution_receipts' not in migration_schema.get('properties', {}):
        raise ResolutionFailure('HUMAN_RESOLUTION_CONTRACT_UNAVAILABLE')
    if (not schema_path or list(contract_migration_validator(migration_schema).iter_errors(record))
            or contract_snapshot(root) != provenance.get('artifact_contract') or record.get('target') != provenance.get('artifact_contract')
            or record.get('to_core_commit') != provenance.get('commit') or migration_identity(record) != migration_id
            or safe_file(root, '.mxagile/state/update-transaction.json') or not projection_integrity(root, provenance)['ready']
            or state.get('status') not in (None, 'complete') or state.get('artifact_canonicalization') == 'in_progress'):
        raise ResolutionFailure('STALE_RESOLUTION')
    if field != 'superseded_by' or not isinstance(source_path, str) or not re.fullmatch(r'requirements/REQ-[0-9]{3,}\.yml', source_path):
        raise ResolutionFailure('RESOLUTION_SCOPE_MISMATCH')
    path = safe_file(root, source_path)
    if path is None:
        raise ResolutionFailure('STALE_RESOLUTION')
    original = path.read_bytes()
    document = load_yaml(original)
    if not isinstance(document, dict) or document.get('ID') != Path(source_path).stem or document.get('status') != 'superseded':
        raise ResolutionFailure('STALE_RESOLUTION')
    receipts = record.get('resolution_receipts', [])
    if len({(item['migration_id'], item['diagnostic_id']) for item in receipts}) != len(receipts):
        raise ResolutionFailure('STALE_RESOLUTION')
    receipt = next((item for item in receipts if item['diagnostic_id'] == diagnostic_id and item['migration_id'] == migration_id), None)
    if receipt:
        if any(receipt.get(k) != v for k, v in {'migration_id': migration_id, 'source_path': source_path, 'field': field, 'current_source_fingerprint': source_fingerprint, 'artifact_id': document['ID'], 'target_contract': record['target']['fingerprint']}.items()):
            raise ResolutionFailure('STALE_RESOLUTION')
        if receipt['resolved_value'] != value:
            raise ResolutionFailure('CONFLICTING_RESOLUTION')
        if digest(original) == receipt['after_source_fingerprint'] and document.get(field) == value:
            _successor_value(root, document['ID'], value)
            return {'result': 'ALREADY_RESOLVED' if receipt['result'] == 'APPLIED' else 'RECOVER_RESOLUTION',
                    'record': record, 'state_bytes': raw, 'receipt': receipt, 'path': path, 'original': original}
        if receipt['result'] == 'APPLIED':
            raise ResolutionFailure('STALE_RESOLUTION')
    if record.get('status') != 'NEEDS_HUMAN' or digest(original) != source_fingerprint:
        raise ResolutionFailure('STALE_RESOLUTION')
    report = build_status(root)['compatibility']
    if report['source_fingerprint'] != record.get('checked_source_fingerprint'):
        raise ResolutionFailure('STALE_RESOLUTION')
    contract = next((item for item in human_resolution_contracts(root) if item['diagnostic_id'] == diagnostic_id), None)
    if not contract or any(contract[k] != v for k, v in {'migration_id': migration_id, 'source_path': source_path, 'field': field, 'current_source_fingerprint': source_fingerprint}.items()):
        raise ResolutionFailure('STALE_RESOLUTION')
    stored = next(item for item in record['decision_references'] if item['diagnostic_id'] == diagnostic_id)
    if stored.get('resolution') and stored['resolution'] != contract:
        raise ResolutionFailure('STALE_RESOLUTION')
    if any(item['result'] == 'PENDING' and item['diagnostic_id'] != diagnostic_id for item in receipts):
        raise ResolutionFailure('RESOLUTION_RECOVERY_REQUIRED')
    _successor_value(root, document['ID'], value)
    text = original.decode('utf-8-sig')
    node = yaml.compose(text, Loader=CanonicalLoader)
    if not isinstance(node, yaml.MappingNode) or node.flow_style:
        raise ResolutionFailure('UNSUPPORTED_RESOLUTION_SOURCE')
    existing = next((child for key, child in node.value if key.value == field), None)
    if existing:
        if not isinstance(existing, yaml.ScalarNode):
            raise ResolutionFailure('UNSUPPORTED_RESOLUTION_SOURCE')
        start, end = existing.start_mark.index, existing.end_mark.index
        prefix = ' ' if start and not text[start - 1].isspace() else ''
        text = text[:start] + prefix + value + text[end:]
    else:
        newline = '\r\n' if b'\r\n' in original else '\n'
        end_marker = re.search(r'^\.\.\.[ \t]*(?:#.*)?$', text, re.M)
        index = end_marker.start() if end_marker else len(text)
        prefix = newline if index and text[index - 1] not in '\r\n' else ''
        text = text[:index] + prefix + field + ': ' + value + newline + text[index:]
    replacement = (b'\xef\xbb\xbf' if original.startswith(b'\xef\xbb\xbf') else b'') + text.encode('utf-8')
    updated = load_yaml(replacement)
    if ({k: v for k, v in updated.items() if k != field} != {k: v for k, v in document.items() if k != field}
            or updated.get(field) != value or not schema_validator(root / '.mxagile/schemas/requirement.schema.json').is_valid(compatibility_projection(source_path, updated)[0])):
        raise ResolutionFailure('INVALID_RESOLUTION_VALUE')
    return {'result': 'READY_FOR_RESOLUTION', 'record': record, 'state_bytes': raw, 'contract': contract,
            'path': path, 'original': original, 'replacement': replacement, 'receipt': receipt}


def resolve_human_resolution(root: Path, **request) -> dict:
    from build_project_status import build_status
    try:
        from run_events import _FileLock, _safe_event_dir
    except ImportError:
        sys.path.insert(0, str(Path(__file__).resolve().parent / 'control-plane'))
        from run_events import _FileLock, _safe_event_dir
    root = root.resolve()
    prepared = prepare_human_resolution(root, **request)
    if prepared['result'] == 'ALREADY_RESOLVED':
        return {'result': 'ALREADY_RESOLVED', 'migration': prepared['record'], 'receipt': prepared['receipt']}
    with _FileLock(_safe_event_dir(root, create=True) / 'human-resolution.lock'):
        prepared = prepare_human_resolution(root, **request)
        if prepared['result'] == 'ALREADY_RESOLVED':
            return {'result': 'ALREADY_RESOLVED', 'migration': prepared['record'], 'receipt': prepared['receipt']}
        expected_state = prepared['state_bytes']
        if prepared['result'] == 'READY_FOR_RESOLUTION':
            record = copy.deepcopy(prepared['record'])
            receipt = prepared['receipt'] or {**prepared['contract'], 'resolved_value': request['value'],
                'human_reference': request['human_reference'], 'human_decision_status': 'CONFIRMED',
                'run_id': request['run_id'], 'result': 'PENDING',
                'after_source_fingerprint': digest(prepared['replacement']),
                'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'applied_at': None}
            if not prepared['receipt']:
                record.setdefault('resolution_receipts', []).append(receipt)
            expected_state = _save_contract_migration(root, record, prepared['state_bytes'])
            fresh = prepare_human_resolution(root, **request)
            if fresh['result'] != 'READY_FOR_RESOLUTION' or fresh['original'] != prepared['original']:
                raise ResolutionFailure('STALE_RESOLUTION')
            atomic_replace(prepared['path'], prepared['replacement'])
        migration = reconcile_contract(root, apply_safe=True, repair_sources=False, persist=False)['migration']
        _, raw, _ = _migration_state(root)
        if raw != expected_state or migration_identity(migration) != request['migration_id']:
            raise ResolutionFailure('STALE_RESOLUTION')
        record = migration
        receipt = next(item for item in record['resolution_receipts'] if item['diagnostic_id'] == request['diagnostic_id'] and item['migration_id'] == request['migration_id'])
        if digest(prepared['path'].read_bytes()) != receipt['after_source_fingerprint']:
            raise ResolutionFailure('STALE_RESOLUTION')
        receipt['result'] = 'APPLIED'
        receipt['applied_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        _save_contract_migration(root, record, raw)
        doctor = {'executed': False, 'reason': 'CONTRACT_MIGRATION_NOT_COMPLETE'}
        if migration['status'] == 'COMPLETE':
            doctor = {'executed': True, **build_status(root)['compatibility']}
        return {'result': 'APPLIED', 'migration': record, 'receipt': receipt, 'doctor': doctor,
                'next_action': 'resync-preflight' if doctor['executed'] and doctor['compatibility'] != 'BLOCKED' else 'inspect'}


AUXILIARY_INTERRUPT = '.mxagile/state/runs/auxiliary-interruption.json'


def _auxiliary_runtime():
    directory = Path(__file__).resolve().parent / 'control-plane'
    if not directory.is_dir():
        directory = Path(__file__).resolve().parents[1] / 'experiments/control-plane'
    sys.path.insert(0, str(directory))
    import guard
    import run_events
    return guard, run_events


def auxiliary_interruption(root: Path) -> dict | None:
    from projection_io import safe_path
    try:
        path = safe_path(root, AUXILIARY_INTERRUPT)
        if not path.exists():
            return None
        value = json.loads(path.read_bytes())
        keys = {'request_reference', 'request_fingerprint', 'target_path', 'artifact_role', 'mutation', 'operation_class',
                'before_fingerprint', 'after_fingerprint', 'context_fingerprint', 'plan_hash', 'schema_version', 'project_root', 'run_id', 'interrupted_at'}
        if not isinstance(value, dict) or set(value) != keys:
            raise ValueError('unknown interruption metadata')
        timestamp = datetime.datetime.fromisoformat(value['interrupted_at'])
        plan = {k: v for k, v in value.items() if k not in {'schema_version', 'project_root', 'run_id', 'interrupted_at', 'plan_hash'}}
        if (value['plan_hash'] != digest(json.dumps(plan, sort_keys=True).encode())
                or value.get('schema_version') != 1 or value.get('project_root') != str(root.resolve()) or timestamp.tzinfo is None
                or value.get('operation_class') not in {'AUXILIARY_WRITE', 'EVIDENCE_WRITE'}
                or not re.fullmatch(r'RUN-[A-Za-z0-9-]{4,80}', value.get('run_id', ''))
                or not re.fullmatch(r'sha256:[0-9a-f]{64}', value.get('plan_hash', ''))):
            raise ValueError('invalid interruption')
        return value
    except (OSError, ValueError, TypeError, KeyError):
        raise ResolutionFailure('INVALID_AUXILIARY_INTERRUPT') from None


def decode_auxiliary_request(encoded: str) -> dict:
    import base64
    if not isinstance(encoded, str) or len(encoded) > 262144 or not re.fullmatch(r'[A-Za-z0-9_=-]+', encoded):
        raise ResolutionFailure('INVALID_AUXILIARY_REQUEST')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate request key')
            result[key] = value
        return result
    try:
        value = json.loads(base64.b64decode(encoded, altchars=b'-_', validate=True), object_pairs_hook=unique)
    except (ValueError, UnicodeDecodeError):
        raise ResolutionFailure('INVALID_AUXILIARY_REQUEST') from None
    if not isinstance(value, dict):
        raise ResolutionFailure('INVALID_AUXILIARY_REQUEST')
    return value


def auxiliary_write_plan(root: Path, request: dict) -> dict:
    from projection_io import safe_path
    root = root.resolve()
    keys = {'request_reference', 'request_summary', 'target_path', 'artifact_role', 'scope_relation',
            'mutation', 'before_fingerprint', 'content'}
    if (not isinstance(request, dict) or set(request) != keys or any(not isinstance(v, str) for v in request.values())
            or not re.fullmatch(r'USER-[A-Za-z0-9-]{4,120}', request['request_reference'])
            or not 1 <= len(request['request_summary']) <= 2000 or len(request['content'].encode()) > 131072
            or '\x00' in request['content'] or request['scope_relation'] != 'independent_noncanonical'
            or request['artifact_role'] not in {'documentation', 'diagnostic_findings', 'retrospective', 'support_note', 'auxiliary_script'}
            or request['mutation'] not in {'create', 'replace', 'delete'}
            or (request['mutation'] == 'delete' and request['content'] != '')):
        raise ResolutionFailure('INVALID_AUXILIARY_REQUEST')
    relative = request['target_path']
    if (not relative or '\\' in relative or PurePosixPath(relative).is_absolute()
            or any(part in ('', '.', '..') or part != part.rstrip(' .') or '~' in part
                   or re.search(r'[<>"|?*[\]\x00-\x1f]', part)
                   or re.fullmatch(r'CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³]', part.split('.')[0].rstrip().upper())
                   for part in relative.split('/')) or ':' in relative):
        raise ResolutionFailure('AUXILIARY_SCOPE_PROTECTED')
    try:
        path = safe_path(root, relative)
        safe_path(root, AUXILIARY_INTERRUPT)
        safe_path(root, '.mxagile/state/runs')
        auxiliary_interruption(root)
    except (OSError, ValueError):
        raise ResolutionFailure('AUXILIARY_SCOPE_PROTECTED') from None
    lower = relative.lower()
    diagnostic_area = lower.startswith(('.concord/scratch/', '.concord/evidence/diagnostics/'))
    protected = ('requirements', 'specs', 'planning', 'sprints', '.mxagile', '.claude', '.github', '.agents', '.git',
                 'javascriptsource', 'javasource', 'src', 'themesource', 'theme', 'widgets', 'deployment', 'resources',
                 'input-resources', 'userlib', 'scripts', 'tests', 'experiments', 'products')
    canonical_docs = {'schemas.md', 'injection-contract.md', 'installation.md', 'architecture.md', 'agent.md', 'agents.md',
                      'claude.md', 'mxagile-project.yaml', 'mxagile-setup.ps1', 'mxagile-setup-company-layer.ps1',
                      'install-mxagile.ps1', 'install-mxagile-company-layer.ps1', 'update-mxcli.ps1'}
    allowed_suffixes = {'.ps1', '.sh', '.py', '.mjs', '.js', '.cmd', '.bat'} if request['artifact_role'] == 'auxiliary_script' else {'.md', '.txt', '.rst', '.json', '.yaml', '.yml'}
    if (path.suffix.lower() not in allowed_suffixes or path.name.lower() in canonical_docs
            or re.match(r'(req|spec|task|dec|tc|vpl|find|rev|page)-[0-9a-z_-]+', path.name, re.I)
            or (lower.split('/')[0] in protected and not diagnostic_area)
            or (lower.startswith('.concord/') and not diagnostic_area)
            or (diagnostic_area and request['artifact_role'] != 'diagnostic_findings')):
        raise ResolutionFailure('AUXILIARY_SCOPE_PROTECTED')
    # References in canonical inputs make a document delivery-relevant regardless of its folder or claimed role.
    references = [root / 'AGENT.md', root / 'AGENTS.md', root / 'CLAUDE.md', root / 'mxagile-project.yaml']
    for directory in ('requirements', 'specs', 'planning', '.mxagile/policies'):
        references.extend(p for p in (root / directory).rglob('*') if p.suffix.lower() in {'.yml', '.yaml', '.md', '.json', '.txt'})
    needle = re.compile(r'(?<![\w./-])' + re.escape(lower) + r'(?![\w./-])')
    for reference in references:
        if reference == path:
            continue
        safe = safe_file(root, reference.relative_to(root).as_posix())
        if safe and needle.search(safe.read_text(encoding='utf-8-sig', errors='replace').lower().replace('\\', '/')):
            raise ResolutionFailure('AUXILIARY_SCOPE_PROTECTED')
    before = digest(path.read_bytes()) if path.is_file() else 'ABSENT'
    if path.exists() and not path.is_file():
        raise ResolutionFailure('AUXILIARY_SCOPE_PROTECTED')
    if (request['before_fingerprint'] != before
            or (request['mutation'] == 'create' and before != 'ABSENT')
            or (request['mutation'] in {'replace', 'delete'} and before == 'ABSENT')):
        raise ResolutionFailure('STALE_AUXILIARY_REQUEST')
    guard, _ = _auxiliary_runtime()
    facts = guard.load_project_facts(root)
    if (facts.update_transaction_present or not facts.core_provenance.get('artifact_contract')
            or contract_snapshot(root) != facts.core_provenance['artifact_contract']
            or not projection_integrity(root, facts.core_provenance)['ready']):
        raise ResolutionFailure('AUXILIARY_AUTHORITY_UNAVAILABLE')
    from build_project_status import build_status
    context = {'project_root': str(root), 'branch': facts.branch, 'head': facts.head,
               'sources': facts.source_fingerprints, 'doctor_source': build_status(root)['compatibility']['source_fingerprint']}
    after_fp = 'ABSENT' if request['mutation'] == 'delete' else digest(request['content'].encode())
    result = {'request_reference': request['request_reference'], 'request_fingerprint': digest(json.dumps(request, sort_keys=True).encode()),
              'target_path': relative, 'artifact_role': request['artifact_role'], 'mutation': request['mutation'],
              'operation_class': 'EVIDENCE_WRITE' if request['artifact_role'] == 'diagnostic_findings' else 'AUXILIARY_WRITE',
              'before_fingerprint': before, 'after_fingerprint': after_fp,
              'context_fingerprint': digest(json.dumps(context, sort_keys=True).encode())}
    result['plan_hash'] = digest(json.dumps(result, sort_keys=True).encode())
    return result


def prepare_auxiliary_write(root: Path, request: dict, *, plan_hash: str, human_reference: str, human_confirmed: bool, run_id: str) -> dict:
    if human_confirmed is not True or human_reference != request.get('request_reference'):
        raise ResolutionFailure('HUMAN_AUTHORIZATION_REQUIRED')
    if not isinstance(run_id, str) or not re.fullmatch(r'RUN-[A-Za-z0-9-]{4,80}', run_id):
        raise ResolutionFailure('RESOLUTION_RUN_REQUIRED')
    plan = auxiliary_write_plan(root, request)
    if plan_hash != plan['plan_hash']:
        raise ResolutionFailure('STALE_AUXILIARY_REQUEST')
    return plan


def apply_auxiliary_write(root: Path, request: dict, **authorization) -> dict:
    from projection_io import safe_path
    root = root.resolve()
    prepare_auxiliary_write(root, request, **authorization)
    _, events = _auxiliary_runtime()
    with events._FileLock(events._safe_event_dir(root, create=True) / 'auxiliary-write.lock'):
        plan = prepare_auxiliary_write(root, request, **authorization)
        interruption = {**plan, 'schema_version': 1, 'project_root': str(root), 'run_id': authorization['run_id'],
                        'interrupted_at': datetime.datetime.now(datetime.timezone.utc).isoformat()}
        marker = safe_path(root, AUXILIARY_INTERRUPT)
        atomic_replace(marker, (json.dumps(interruption, sort_keys=True, indent=2) + '\n').encode())
        events.append_event(root, 'run_interrupted', run_id=authorization['run_id'], actor='auxiliary_write', host='mxagile',
                            payload={'operation_class': plan['operation_class'], 'request_reference': plan['request_reference'],
                                     'plan_hash': plan['plan_hash'], 'target_path': plan['target_path'], 'recovery': 'resync'})
        # Recheck the exact approved content, canonical references and context after journaling, before any target write.
        prepare_auxiliary_write(root, request, **authorization)
        path = safe_path(root, plan['target_path'])
        if plan['mutation'] == 'delete':
            path.unlink()
            if path.exists():
                raise ResolutionFailure('STALE_AUXILIARY_REQUEST')
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path = safe_path(root, plan['target_path'])
            atomic_replace(path, request['content'].encode())
            if digest(path.read_bytes()) != plan['after_fingerprint']:
                raise ResolutionFailure('STALE_AUXILIARY_REQUEST')
        return {'result': 'APPLIED', 'authorization': plan, 'delivery_resumed': False, 'next_action': 'resync-preflight'}


def resync_preflight(root: Path, mission_id: str = '', wave_id: str = '', phase: str = '') -> dict:
    from build_project_status import build_status
    root = root.resolve()
    target = contract_snapshot(root)
    _, _, state = _migration_state(root)
    record = state.get('contract_migration') or {}
    reasons = []
    if os.path.lexists(root / '.mxagile/state/runs/framework-update-recovery.json'):
        from framework_update_recovery import require_restarted
        try:
            require_restarted(root)
        except ValueError as exc:
            reasons.append(str(exc))
    if safe_file(root, '.mxagile/state/update-transaction.json'):
        reasons.append('UPDATE_RECOVERY_REQUIRED')
    provenance_path = safe_file(root, '.mxagile/state/core-provenance.json')
    provenance = json.loads(provenance_path.read_text(encoding='utf-8-sig')) if provenance_path else {}
    if not projection_integrity(root, provenance)['ready']:
        reasons.append('PROJECTION_RECOVERY_REQUIRED')
    schema_path = safe_file(root, '.mxagile/schemas/contract-migration.schema.json')
    schema = json.loads(schema_path.read_text(encoding='utf-8-sig')) if schema_path else {}
    valid_record = jsonschema is not None and schema_path is not None and not list(contract_migration_validator(schema).iter_errors(record))
    if target is None or provenance.get('artifact_contract') != target:
        reasons.append('CONTRACT_IDENTITY_NOT_OBSERVABLE')
    if not valid_record or record.get('target') != target or record.get('status') != 'COMPLETE':
        reasons.append('CONTRACT_MIGRATION_REQUIRED')
    if any(item.get('result') == 'PENDING' for item in record.get('resolution_receipts', [])):
        reasons.append('HUMAN_RESOLUTION_RECOVERY_REQUIRED')
    if state.get('status') not in (None, 'complete') or state.get('artifact_canonicalization') == 'in_progress':
        reasons.append('LEGACY_MIGRATION_INCOMPLETE')
    report = build_status(root)['compatibility']
    if report['compatibility'] == 'BLOCKED':
        reasons.append('DOCTOR_BLOCKED')
    mission_path = safe_file(root, 'planning/mission/mission-state.yaml')
    process_path = safe_file(root, 'planning/lifecycle/process-state.yaml')
    mission = load_yaml(mission_path.read_text(encoding='utf-8-sig')) if mission_path else {}
    process = load_yaml(process_path.read_text(encoding='utf-8-sig')) if process_path else {}
    if schema_errors('planning/mission/mission-state.yaml', mission) or schema_errors('planning/lifecycle/process-state.yaml', process):
        reasons.append('CANONICAL_STATE_INVALID')
    canonical_mission = mission.get('mission_id') if isinstance(mission, dict) else None
    canonical_wave = mission.get('active_wave') if isinstance(mission, dict) else None
    waves = process.get('waves', {}) if isinstance(process, dict) else {}
    active = waves.get(canonical_wave, {}) if isinstance(waves, dict) else {}
    canonical_phase = active.get('phase') if isinstance(active, dict) else None
    if not canonical_mission or not canonical_wave or canonical_phase in (None, 'not_started'):
        reasons.append('CANONICAL_ACTIVE_SCOPE_UNRESOLVED')
    if mission_id and mission_id != canonical_mission:
        reasons.append('MISSION_ID_CONFLICT')
    if wave_id and wave_id != canonical_wave:
        reasons.append('ACTIVE_WAVE_CONFLICT')
    if phase and phase != canonical_phase:
        reasons.append('CANONICAL_PHASE_CONFLICT')
    resume_reasons = []
    try:
        interruption = auxiliary_interruption(root)
        if interruption:
            epoch_file = safe_file(root, '.concord/context-epoch.yaml')
            epoch = load_yaml(epoch_file.read_text(encoding='utf-8-sig')) if epoch_file else {}
            timestamp = (epoch.get('repository') or {}).get('checkpoint_time') if isinstance(epoch, dict) else None
            checkpoint = datetime.datetime.fromisoformat(str(timestamp).replace('Z', '+00:00')) if timestamp else None
            interrupted = datetime.datetime.fromisoformat(interruption['interrupted_at'])
            if checkpoint is None or checkpoint.tzinfo is None or checkpoint < interrupted:
                resume_reasons.append('AUXILIARY_INTERRUPTION_REQUIRES_RESYNC')
    except (ResolutionFailure, ValueError, TypeError, OSError, yaml.YAMLError):
        reasons.append('INVALID_AUXILIARY_INTERRUPT_OR_EPOCH')
    return {'stage': 'RESYNC_PREFLIGHT', 'read_only': True, 'state': 'RECONCILIATION_REQUIRED' if reasons else 'READY_FOR_RESYNC',
            'reason_codes': reasons + resume_reasons, 'mission_id': canonical_mission, 'wave_id': canonical_wave, 'phase': canonical_phase,
            'delivery_resume_allowed': False, 'resume_reason_codes': resume_reasons,
            'primary_recovery': 'reconcile' if reasons else 'resync',
            'next_action': 'reconcile' if reasons else 'write_epoch_checkpoint_then_rerun_delivery_preflight'}


LAST_CANONICAL_WRITE = '.mxagile/state/runs/last-canonical-write.json'
EXTRA_CANONICAL_PATTERNS = (
    ('.concord/context-epoch.yaml', 'context-epoch', 'context'),
    ('.concord/routing-decisions/*.json', 'routing-decision', 'routing'),
    ('.concord/delegation-handoffs/*.json', 'delegation-handoff', 'delegation'),
    ('planning/reconciliation/change-sets/*.json', 'change-set', 'provenance'),
    ('planning/revisions/REV-*.yaml', 'revision-ledger', 'references'),
    ('planning/checklists/W*-implementation-checklist.yaml', 'checklist', 'tasks'),
    ('.mxagile/config.yaml', 'mxagile-config', 'project'),
)


def canonical_write_contract(relative: str) -> tuple[str, str] | None:
    if not isinstance(relative, str) or not relative:
        return None
    normalized = relative.replace('\\', '/')
    contract = contract_for(normalized)
    if contract:
        return contract
    return next(((schema, area) for pattern, schema, area in EXTRA_CANONICAL_PATTERNS
                 if _canonical_pattern_matches(normalized, pattern)), None)


def is_canonical_write_target(relative: str) -> bool:
    return canonical_write_contract(relative) is not None


def project_candidate_bytes(root: Path, tool_name: str, tool_input: dict) -> tuple[str, bytes | None, str | None] | None:
    """Compute candidate bytes in memory before a Write/Edit/MultiEdit on a canonical artifact.

    Returns None when the call is not a canonical write or has no mutation payload (e.g. path-only probe).
    Returns (relative_path, candidate_bytes, error_code) otherwise.
    """
    if tool_name not in {'Write', 'Edit', 'MultiEdit'} or not isinstance(tool_input, dict):
        return None
    raw_target = tool_input.get('file_path') or tool_input.get('path')
    if not isinstance(raw_target, str) or not raw_target:
        return None
    try:
        resolved = (Path(raw_target) if Path(raw_target).is_absolute() else (root / raw_target)).resolve()
        relative = resolved.relative_to(root.resolve()).as_posix()
    except (OSError, ValueError):
        return None
    if not is_canonical_write_target(relative):
        return None
    has_payload = any(key in tool_input for key in ('content', 'new_string', 'old_string', 'edits'))
    if not has_payload:
        return None
    if tool_name == 'Write':
        content = tool_input.get('content')
        if not isinstance(content, str):
            return relative, None, 'CANDIDATE_CONTENT_INVALID'
        return relative, content.encode('utf-8'), None
    existing_path = safe_file(root, relative)
    if existing_path is None:
        return relative, None, 'CANDIDATE_TARGET_MISSING'
    try:
        current_raw = existing_path.read_bytes()
        bom = b'\xef\xbb\xbf' if current_raw.startswith(b'\xef\xbb\xbf') else b''
        text = current_raw.decode('utf-8-sig')
    except (OSError, UnicodeDecodeError):
        return relative, None, 'CANDIDATE_TARGET_UNREADABLE'
    edits = tool_input.get('edits') if tool_name == 'MultiEdit' else [tool_input]
    if not isinstance(edits, list) or not edits:
        return relative, None, 'CANDIDATE_MUTATION_UNAPPLICABLE'
    for edit_op in edits:
        if not isinstance(edit_op, dict):
            return relative, None, 'CANDIDATE_MUTATION_UNAPPLICABLE'
        old_str = edit_op.get('old_string')
        new_str = edit_op.get('new_string')
        replace_all = bool(edit_op.get('replace_all'))
        if not isinstance(old_str, str) or not isinstance(new_str, str) or not old_str:
            return relative, None, 'CANDIDATE_MUTATION_UNAPPLICABLE'
        occurrences = text.count(old_str)
        if occurrences == 0 or (occurrences > 1 and not replace_all):
            return relative, None, 'CANDIDATE_MUTATION_UNAPPLICABLE'
        text = text.replace(old_str, new_str) if replace_all else text.replace(old_str, new_str, 1)
    return relative, bom + text.encode('utf-8'), None


def prevalidate_canonical_write(root: Path, relative: str, candidate_bytes: bytes) -> dict[str, Any]:
    """Validate projected candidate bytes in-memory before any canonical write (A1)."""
    root = root.resolve()
    normalized = relative.replace('\\', '/')
    contract = canonical_write_contract(normalized)
    if contract is None:
        return {'valid': True, 'target_path': normalized, 'artifact_type': 'non_canonical', 'diagnostics': []}
    artifact_type, area = contract
    diagnostics: list[dict[str, str]] = []

    def fail_diag(category: str, message: str, authority: str | None = None) -> None:
        diagnostics.append({
            'category': category,
            'source_path': normalized,
            'artifact_type': artifact_type,
            'affected_board_area': area,
            'message': message,
            'authority': authority or f'.mxagile/schemas/{artifact_type}.schema.json',
        })

    if not isinstance(candidate_bytes, (bytes, bytearray)) or not candidate_bytes.strip():
        fail_diag('SYNTAX_ERROR', 'Candidate canonical payload is empty.')
        return {'valid': False, 'code': 'CANONICAL_WRITE_PREVALIDATION_FAILED', 'target_path': normalized,
                'artifact_type': artifact_type, 'diagnostics': diagnostics}

    try:
        text = bytes(candidate_bytes).decode('utf-8-sig')
    except UnicodeDecodeError:
        fail_diag('SYNTAX_ERROR', 'Candidate canonical payload is not valid UTF-8.')
        return {'valid': False, 'code': 'CANONICAL_WRITE_PREVALIDATION_FAILED', 'target_path': normalized,
                'artifact_type': artifact_type, 'diagnostics': diagnostics}

    if PurePosixPath(normalized).suffix.casefold() == '.json':
        def _unique_json_pairs(pairs):
            obj = {}
            for key, val in pairs:
                if key in obj:
                    raise ValueError(f'duplicate JSON key: {key}')
                obj[key] = val
            return obj
        try:
            value = json.loads(text, object_pairs_hook=_unique_json_pairs)
        except ValueError as exc:
            fail_diag('SYNTAX_ERROR', f'Candidate JSON is syntactically invalid: {exc}.')
            return {'valid': False, 'code': 'CANONICAL_WRITE_PREVALIDATION_FAILED', 'target_path': normalized,
                    'artifact_type': artifact_type, 'diagnostics': diagnostics}
    else:
        try:
            value = load_yaml(text)
        except yaml.YAMLError as exc:
            fail_diag('SYNTAX_ERROR', f'Candidate YAML is syntactically invalid ({type(exc).__name__}).')
            return {'valid': False, 'code': 'CANONICAL_WRITE_PREVALIDATION_FAILED', 'target_path': normalized,
                    'artifact_type': artifact_type, 'diagnostics': diagnostics}

    if not isinstance(value, dict):
        fail_diag('SCHEMA_ERROR', 'Candidate canonical artifact root must be a mapping/object.')
        return {'valid': False, 'code': 'CANONICAL_WRITE_PREVALIDATION_FAILED', 'target_path': normalized,
                'artifact_type': artifact_type, 'diagnostics': diagnostics}

    # 1. Schema validation (including compatibility projection where applicable)
    if contract_for(normalized) is not None:
        _, _, conflicts = compatibility_projection(normalized, value)
        for field_conflict in conflicts:
            fail_diag('AUTHORITY_CONFLICT', f'Legacy and current fields disagree ({field_conflict}).', field_conflict)
        for message, _rep, auth in schema_diagnostics(normalized, value):
            fail_diag('SCHEMA_ERROR', message, auth)
        if not diagnostics and schema_errors(normalized, value):
            fail_diag('SCHEMA_ERROR', 'Candidate failed canonical schema validation: ' + ', '.join(schema_errors(normalized, value)))
    elif artifact_type in {'context-epoch', 'routing-decision', 'delegation-handoff', 'change-set'}:
        schema_path = (root / '.mxagile/schemas' / f'{artifact_type}.schema.json')
        if not schema_path.is_file():
            schema_path = SCHEMA_ROOT / f'{artifact_type}.schema.json'
        if not schema_path.is_file() or jsonschema is None:
            fail_diag('SCHEMA_UNAVAILABLE', f'Canonical validator unavailable for {artifact_type}.')
        else:
            for err in sorted(schema_validator(schema_path).iter_errors(value), key=lambda e: [str(p) for p in e.path])[:5]:
                loc = '/'.join(str(p) for p in err.path) or '$'
                fail_diag('SCHEMA_ERROR', f'Canonical schema constraint failed at {loc}: {err.validator}.', f'{artifact_type}.schema.json#/{loc}')
    elif artifact_type == 'revision-ledger':
        stem = PurePosixPath(normalized).stem
        rev_id = value.get('revision_id')
        if rev_id != stem or not re.fullmatch(r'REV-[0-9]{3,}', str(rev_id or '')):
            fail_diag('ID_MISMATCH', f'Revision ledger revision_id must match filename stem {stem}.', 'revision_id')
        # A historical ledger is not a SPA bundle manifest; do not invent bundle fields.
        if value.get('lifecycle_status') not in {None, 'SOURCE', 'REFINED_TARGET', 'SUPERSEDED_TARGET'}:
            fail_diag('SCHEMA_ERROR', 'Invalid lifecycle_status in revision ledger.', 'lifecycle_status')
        if value.get('refinement_status') not in {None, 'PROPOSED', 'ACCEPTED', 'REJECTED'}:
            fail_diag('SCHEMA_ERROR', 'Invalid refinement_status in revision ledger.', 'refinement_status')
        if 'active_target' in value and not isinstance(value.get('active_target'), bool):
            fail_diag('SCHEMA_ERROR', 'active_target must be a boolean.', 'active_target')
        if value.get('active_target') is True and (value.get('refinement_status') != 'ACCEPTED'
                or value.get('lifecycle_status') not in {'SOURCE', 'REFINED_TARGET'}):
            fail_diag('REVISION_ACTIVE_WITHOUT_ACCEPTANCE', 'Active ledger target requires accepted, current lifecycle state.', 'active_target')
        if 'acceptance_decisions' in value and (not isinstance(value.get('acceptance_decisions'), list)
                or any(not isinstance(ref, str) or not re.fullmatch(r'DEC-[0-9]{3,}', ref) for ref in value['acceptance_decisions'])):
            fail_diag('SCHEMA_ERROR', 'acceptance_decisions must contain canonical DEC-NNN identifiers.', 'acceptance_decisions')
    elif artifact_type in {'checklist', 'mxagile-config'}:
        schema_name = 'implementation-checklist' if artifact_type == 'checklist' else 'framework-config'
        schema_path = SCHEMA_ROOT / f'{schema_name}.schema.json'
        if jsonschema is None or not schema_path.is_file():
            fail_diag('SCHEMA_UNAVAILABLE', f'Canonical validator unavailable for {artifact_type}.')
        else:
            for err in schema_validator(schema_path).iter_errors(value):
                loc = '/'.join(str(p) for p in err.path) or '$'
                fail_diag('SCHEMA_ERROR', f'Canonical schema constraint failed at {loc}: {err.validator}.', f'{schema_name}.schema.json#/{loc}')
    if artifact_type == 'checklist':
        from wave_ids import checklist_wave_id
        expected_wave = checklist_wave_id(PurePosixPath(normalized).name)
        declared_wave = value.get('wave_id', value.get('wave'))
        if declared_wave is not None and declared_wave != expected_wave:
            fail_diag('ID_MISMATCH', f'Checklist declared wave ({declared_wave}) disagrees with filename wave ({expected_wave}).', 'wave_id')

    document = projected_for_validation(normalized, value) if contract_for(normalized) else value
    stem = PurePosixPath(normalized).stem

    # 2. Stem & primary-key identity invariants
    if artifact_type in {'requirement', 'spec', 'task', 'decision', 'finding', 'verification-plan'}:
        doc_id = document.get('ID')
        if not isinstance(doc_id, str) or doc_id != stem:
            fail_diag('ID_MISMATCH', f'Artifact ID ({doc_id!r}) does not match filename stem ({stem!r}).', 'ID')
    elif artifact_type == 'test-contract':
        if not identity_matches(normalized, document.get('ID'), stem):
            fail_diag('ID_MISMATCH', f'Test Contract ID ({document.get("ID")!r}) does not match filename ({stem!r}).', 'ID')
    elif artifact_type == 'routing-decision':
        if document.get('decision_id') != stem:
            fail_diag('ID_MISMATCH', f'Routing decision_id ({document.get("decision_id")!r}) does not match filename ({stem!r}).', 'decision_id')

    # 3. Cross-contract reference & invariant validation against existing project artifacts
    if artifact_type == 'page' and isinstance(document.get('revision_binding'), dict) and not diagnostics:
        binding = document['revision_binding']
        if (binding['page_id'] != document.get('page_id') or binding['page_name'] != document.get('page_name')
                or binding['current_revision'] != document.get('target_revision')):
            fail_diag('PAGE_IDENTITY_CONFLICT', 'Revision binding must match the Page identity, implementation and current revision.', 'revision_binding')
        previous_path = safe_file(root, normalized)
        if previous_path:
            try:
                previous_doc = load_yaml(previous_path.read_text(encoding='utf-8-sig'))
                previous_revision = previous_doc.get('target_revision') if isinstance(previous_doc, dict) else None
                if previous_revision != document.get('target_revision') and binding['previous_revision'] != previous_revision:
                    fail_diag('PAGE_BINDING_PREVIOUS_REVISION_CONFLICT', 'Rebinding must preserve the actual previous revision.', 'revision_binding')
            except (OSError, UnicodeError, yaml.YAMLError):
                fail_diag('PAGE_BINDING_PREVIOUS_REVISION_UNKNOWN', 'Previous binding cannot be observed.', 'revision_binding')
    if artifact_type == 'finding' and not diagnostics:
        claim = document.get('claim_provenance') or {}
        authority = claim.get('authority_ref')
        if claim.get('reported_as') in ('OBSERVED_DEFECT', 'DECLARED_RULE'):
            authority_path = safe_file(root, authority) if isinstance(authority, str) else None
            try:
                authority_doc = load_yaml(authority_path.read_text(encoding='utf-8-sig')) if authority_path else None
                authority_valid = (isinstance(authority_doc, dict) and authority_doc.get('status') in ('CONFIRMED', 'accepted')
                                   and canonical_write_contract(authority)[0] in ('requirement', 'decision')
                                   and authority_doc.get('ID') == PurePosixPath(authority).stem
                                   and not schema_errors(authority, authority_doc))
            except (OSError, UnicodeError, yaml.YAMLError, TypeError):
                authority_valid = False
            if not authority_valid:
                fail_diag('CLAIM_AUTHORITY_NOT_CONFIRMED', 'A defect/rule claim requires a valid canonical accepted Requirement or CONFIRMED Decision path; inference is not authority.', 'claim_provenance')
        previous_path = safe_file(root, normalized)
        if previous_path:
            try:
                previous_doc = load_yaml(previous_path.read_text(encoding='utf-8-sig'))
                previous_claim = previous_doc.get('claim_provenance') or {} if isinstance(previous_doc, dict) else {}
            except (OSError, UnicodeError, yaml.YAMLError):
                previous_claim = {}
            if previous_claim.get('state') in ('INFERRED', 'PROPOSED') and claim.get('state') not in ('INFERRED', 'PROPOSED'):
                if claim.get('reported_as') not in ('OBSERVED_DEFECT', 'DECLARED_RULE'):
                    fail_diag('CLAIM_PROMOTION_REQUIRES_AUTHORITY', 'Do not erase an inferred/proposed origin through a cosmetic state edit.', 'claim_provenance')
    if artifact_type in {'revision', 'revision-ledger'} and not diagnostics:
        if document.get('refinement_status') == 'ACCEPTED' or document.get('active_target') is True:
            acceptance = document.get('acceptance_decisions')
            if not isinstance(acceptance, list) or not acceptance:
                fail_diag('REVISION_ACCEPTANCE_NOT_CONFIRMED', 'Accepted revision requires canonical confirmation references.', 'acceptance_decisions')
                acceptance = []
            for decision_id in acceptance:
                decision_relative = f'planning/decisions/{decision_id}.yml'
                decision_file = safe_file(root, decision_relative)
                try:
                    decision = load_yaml(decision_file.read_text(encoding='utf-8-sig')) if decision_file else None
                    confirmed = (isinstance(decision, dict) and decision.get('ID') == decision_id
                                 and decision.get('status') == 'CONFIRMED' and not schema_errors(decision_relative, decision))
                except (OSError, UnicodeError, yaml.YAMLError):
                    confirmed = False
                if not confirmed:
                    fail_diag('REVISION_ACCEPTANCE_NOT_CONFIRMED', f'Acceptance requires canonical CONFIRMED {decision_id}.', 'acceptance_decisions')
        if document.get('active_target') is True:
            namespace = document.get('mockup_name') or document.get('mockup_id')
            namespace = _canonical_path_key(namespace.strip()) if isinstance(namespace, str) and namespace.strip() else None
            if namespace is None:
                fail_diag('ACTIVE_TARGET_STATE_NOT_OBSERVABLE', 'Active target requires an explicit mockup namespace.', 'active_target')
            revision_paths = list(root.glob('planning/revisions/REV-*.yaml')) + list(root.glob('planning/target-mockups/*/_history/REV-*/revision.yaml'))
            for revision_file in revision_paths:
                other_relative = revision_file.relative_to(root).as_posix()
                if _canonical_path_key(other_relative) == _canonical_path_key(normalized):
                    continue
                safe = safe_file(root, other_relative)
                try:
                    other = load_yaml(safe.read_text(encoding='utf-8-sig')) if safe else None
                except (OSError, UnicodeError, yaml.YAMLError):
                    other = None
                if not isinstance(other, dict):
                    fail_diag('ACTIVE_TARGET_STATE_NOT_OBSERVABLE', f'Cannot establish active-target scope of {other_relative}.', 'active_target')
                    continue
                if other.get('active_target') is True:
                    other_namespace = other.get('mockup_name') or other.get('mockup_id')
                    other_namespace = _canonical_path_key(other_namespace.strip()) if isinstance(other_namespace, str) and other_namespace.strip() else None
                    if other_namespace is None or other_namespace == namespace:
                        fail_diag('ACTIVE_TARGET_CONFLICT', f'Existing active target in the same or unknown namespace: {other_relative}.', 'active_target')
    page_ids: set[str] = set()
    ui_dir = root / 'planning/ui-inventory'
    if ui_dir.is_dir() and not ui_dir.is_symlink():
        for p in sorted(ui_dir.glob('*.yaml')):
            rel_p = p.relative_to(root).as_posix()
            if _canonical_path_key(rel_p) == _canonical_path_key(normalized) or is_standalone_interaction_artifact(rel_p):
                continue
            safe_p = safe_file(root, rel_p)
            if safe_p is None:
                continue
            try:
                doc_p = load_yaml(safe_p.read_bytes().decode('utf-8-sig'))
                if isinstance(doc_p, dict) and isinstance(doc_p.get('page_id'), str):
                    if artifact_type == 'page' and doc_p.get('page_id') == document.get('page_id'):
                        fail_diag('DUPLICATE_ID', f'page_id {document.get("page_id")} already exists in {rel_p}.', 'page_id')
                    page_ids.add(doc_p['page_id'])
            except (OSError, UnicodeError, yaml.YAMLError):
                continue
    if artifact_type == 'page' and isinstance(document.get('page_id'), str):
        page_ids.add(document['page_id'])

    req_ids: set[str] = set()
    req_dir = root / 'requirements'
    if req_dir.is_dir() and not req_dir.is_symlink():
        for p in sorted(req_dir.glob('*.yml')):
            rel_p = p.relative_to(root).as_posix()
            if _canonical_path_key(rel_p) == _canonical_path_key(normalized):
                continue
            safe_p = safe_file(root, rel_p)
            if safe_p is None:
                continue
            try:
                doc_r = load_yaml(safe_p.read_bytes().decode('utf-8-sig'))
                if isinstance(doc_r, dict) and isinstance(doc_r.get('ID'), str) and doc_r['ID'] == p.stem:
                    req_ids.add(doc_r['ID'])
            except (OSError, UnicodeError, yaml.YAMLError):
                continue
    if artifact_type == 'requirement' and isinstance(document.get('ID'), str):
        req_ids.add(document['ID'])

    dec_ids: set[str] = set()
    dec_dir = root / 'planning/decisions'
    if dec_dir.is_dir() and not dec_dir.is_symlink():
        for p in sorted(dec_dir.glob('*.yml')):
            rel_p = p.relative_to(root).as_posix()
            if _canonical_path_key(rel_p) == _canonical_path_key(normalized):
                continue
            safe_p = safe_file(root, rel_p)
            if safe_p is None:
                continue
            try:
                doc_d = load_yaml(safe_p.read_bytes().decode('utf-8-sig'))
                if isinstance(doc_d, dict) and isinstance(doc_d.get('ID'), str) and doc_d['ID'] == p.stem:
                    dec_ids.add(doc_d['ID'])
            except (OSError, UnicodeError, yaml.YAMLError):
                continue
    if artifact_type == 'decision' and isinstance(document.get('ID'), str):
        dec_ids.add(document['ID'])

    for screen_field in ('affected_screens', 'screens'):
        screens = document.get(screen_field)
        if isinstance(screens, list):
            for scr in screens:
                if not isinstance(scr, str) or not re.fullmatch(r'PAGE-[A-Z0-9_-]+', scr):
                    fail_diag('SCHEMA_ERROR', f'{screen_field} entry {scr!r} is not a canonical PAGE-ID (^PAGE-[A-Z0-9_-]+$).', screen_field)
                elif scr not in page_ids:
                    fail_diag('REFERENCE_MISSING', f'{screen_field} references unknown canonical Page ID {scr}.', screen_field)
    for single_screen_field in ('derivedFrom', 'page_id'):
        scr = document.get(single_screen_field)
        if isinstance(scr, str) and single_screen_field == 'derivedFrom':
            if not re.fullmatch(r'PAGE-[A-Z0-9_-]+', scr):
                fail_diag('SCHEMA_ERROR', f'derivedFrom ({scr!r}) is not a canonical PAGE-ID.', 'derivedFrom')
            elif scr not in page_ids:
                fail_diag('REFERENCE_MISSING', f'derivedFrom references unknown canonical Page ID {scr}.', 'derivedFrom')
    if artifact_type == 'parity-verification' and isinstance(document.get('page_id'), str) and document['page_id'] not in page_ids:
        fail_diag('REFERENCE_MISSING', f'Parity report page_id {document["page_id"]} has no canonical UI inventory target.', 'page_id')

    for req_field in ('req', 'requirements', 'requirement_ids', 'affected_requirements'):
        refs = document.get(req_field)
        if isinstance(refs, list):
            for ref in refs:
                if not isinstance(ref, str) or ref not in req_ids:
                    fail_diag('REFERENCE_MISSING', f'{req_field} references missing canonical Requirement {ref!r}.', req_field)

    parent_documents: dict[str, dict] = {}
    for field in ('spec', 'test_contract', 'test_contract_id'):
        ref = document.get(field)
        if not isinstance(ref, str):
            continue
        paths = [root / 'specs' / f'{ref}.yml'] if field == 'spec' else sorted((root / 'planning/test-contracts').glob('TC-*.yaml'))
        matches: list[tuple[str, dict]] = []
        for path in paths:
            try:
                parent_relative = path.relative_to(root).as_posix()
                safe_parent = safe_file(root, parent_relative)
                if safe_parent is None:
                    continue
                parent = load_yaml(safe_parent.read_bytes().decode('utf-8-sig'))
                if isinstance(parent, dict) and parent.get('ID') == ref:
                    matches.append((parent_relative, parent))
            except (OSError, ValueError, UnicodeError, yaml.YAMLError):
                continue
        if not matches:
            fail_diag('REFERENCE_MISSING', f'{field} references missing canonical parent {ref}.', field)
        elif len(matches) != 1:
            fail_diag('REFERENCE_AMBIGUOUS', f'{field} resolves to multiple canonical parents {ref}.', field)
        else:
            parent_relative, parent = matches[0]
            valid_parent = identity_matches(parent_relative, ref, PurePosixPath(parent_relative).stem) and not schema_errors(parent_relative, parent)
            req_field = 'requirements' if field == 'spec' else 'requirement_ids'
            valid_parent = valid_parent and all(req in req_ids for req in parent.get(req_field, []))
            if valid_parent and field != 'spec':
                valid_parent = all(req in req_ids for point in parent.get('proof_points', [])
                                   for req in (point.get('traceability') or {}).get('requirement_ids', []))
            if not valid_parent:
                fail_diag('REFERENCE_AMBIGUOUS', f'{field} parent identity, schema or requirements are invalid.', field)
            else:
                parent_documents[field] = parent
    if artifact_type == 'verification-plan' and 'test_contract_id' in parent_documents:
        proof_points = {point.get('id') for point in parent_documents['test_contract_id'].get('proof_points', []) if isinstance(point, dict)}
        assignments = document.get('layer_assignments')
        for assignment in assignments if isinstance(assignments, list) else []:
            if isinstance(assignment, dict) and assignment.get('proof_point_id') not in proof_points:
                fail_diag('REFERENCE_MISSING', 'Verification plan references an absent parent proof point.', 'layer_assignments/proof_point_id')

    for dec_field in ('decision_ids', 'acceptance_decisions'):
        refs = document.get(dec_field)
        if isinstance(refs, list):
            for ref in refs:
                if not isinstance(ref, str) or ref not in dec_ids:
                    fail_diag('REFERENCE_MISSING', f'{dec_field} references missing canonical Decision {ref!r}.', dec_field)

    if artifact_type == 'requirement':
        req_status = document.get('status')
        self_id = document.get('ID')
        if req_status == 'superseded':
            succ = document.get('superseded_by')
            if not isinstance(succ, str) or not succ or succ == self_id or (req_ids and succ not in req_ids):
                fail_diag('REFERENCE_MISSING', 'Superseded Requirement requires one valid, distinct canonical superseded_by target.', 'superseded_by')
        elif req_status in ('obsolete', 'retired', 'invalid'):
            if document.get('superseded_by'):
                fail_diag('AUTHORITY_CONFLICT', 'Obsolete/retired Requirement must not declare superseded_by.', 'superseded_by')
        elif req_status == 'split':
            reps = document.get('replacement_ids')
            if not isinstance(reps, list) or len(set(reps)) < 2 or (self_id in (reps or [])) or (req_ids and any(r not in req_ids for r in reps)):
                fail_diag('REFERENCE_MISSING', 'Split Requirement requires at least two distinct existing canonical replacement_ids.', 'replacement_ids')
        elif req_status in ('merged', 'duplicate'):
            target_id = document.get('merged_into') or document.get('superseded_by')
            if not isinstance(target_id, str) or not target_id or target_id == self_id or (req_ids and target_id not in req_ids):
                fail_diag('REFERENCE_MISSING', 'Merged/duplicate Requirement requires one valid, distinct canonical merged_into or superseded_by target.', 'merged_into')
        elif req_status == 'ambiguous':
            fail_diag('AUTHORITY_CONFLICT', 'Canonical Requirement cannot be written with unresolved AMBIGUOUS status.', 'status')

    if artifact_type == 'decision' and document.get('status') == 'SUPERSEDED':
        succ = document.get('superseded_by')
        if not isinstance(succ, str) or not succ or succ == document.get('ID') or (dec_ids and succ not in dec_ids):
            fail_diag('REFERENCE_MISSING', 'SUPERSEDED Decision requires one valid, distinct canonical superseded_by target.', 'superseded_by')

    return {
        'valid': not diagnostics,
        'code': None if not diagnostics else 'CANONICAL_WRITE_PREVALIDATION_FAILED',
        'target_path': normalized,
        'artifact_type': artifact_type,
        'diagnostics': diagnostics,
    }


def record_last_canonical_write(root: Path, relative: str, operation_class: str, run_id: str,
                                candidate_fingerprint: str | None = None) -> None:
    """Bind recovery to the before snapshot and exact authorized candidate, not any later edit."""
    import base64
    from projection_io import safe_path
    root = root.resolve()
    normalized = relative.replace('\\', '/')
    if not is_canonical_write_target(normalized):
        return
    try:
        target = safe_path(root, normalized)
        journal_path = safe_path(root, LAST_CANONICAL_WRITE)
        safe_path(root, '.mxagile/state/runs')
        journal_path.parent.mkdir(parents=True, exist_ok=True)
        existed = target.is_file()
        raw = target.read_bytes() if existed else b''
        before_fp = digest(raw) if existed else 'ABSENT'
        record = {
            'schema_version': 1,
            'project_root': str(root),
            'run_id': run_id,
            'target_path': normalized,
            'operation_class': operation_class,
            'existed': existed,
            'before_fingerprint': before_fp,
            'authorized_result_fingerprint': candidate_fingerprint,
            'before_content_b64': base64.b64encode(raw).decode('ascii') if existed and len(raw) <= 262144 else None,
            'authorized_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        }
        atomic_replace(journal_path, (json.dumps(record, sort_keys=True, indent=2) + '\n').encode('utf-8'))
    except (OSError, ValueError):
        pass


def last_canonical_write_journal(root: Path) -> dict | None:
    from projection_io import safe_path
    try:
        path = safe_path(root.resolve(), LAST_CANONICAL_WRITE)
        if not path.is_file():
            return None
        value = json.loads(path.read_text(encoding='utf-8-sig'))
        if (not isinstance(value, dict) or value.get('schema_version') != 1
                or value.get('project_root') != str(root.resolve())
                or not isinstance(value.get('target_path'), str)
                or not is_canonical_write_target(value['target_path'])):
            return None
        return value
    except (OSError, ValueError):
        return None


def last_canonical_write_repair_plan(
    root: Path,
    *,
    target_path: str | None = None,
    candidate_bytes: bytes | None = None,
) -> dict[str, Any]:
    """Build a tightly bound recovery plan for the last invalid canonical write when Doctor is BLOCKED (A2)."""
    import base64
    from build_project_status import build_status
    from projection_io import safe_path
    root = root.resolve()
    if os.path.lexists(root / '.mxagile/state/runs/framework-update-recovery.json'):
        from framework_update_recovery import require_restarted
        try:
            require_restarted(root)
        except ValueError as exc:
            raise ResolutionFailure(str(exc)) from None
    if safe_file(root, '.mxagile/state/update-transaction.json'):
        raise ResolutionFailure('BOUNDED_REPAIR_UNAVAILABLE')
    _, _, mig_state = _migration_state(root)
    mig_record = mig_state.get('contract_migration') or {}
    if mig_state.get('status') not in (None, 'complete') or mig_state.get('artifact_canonicalization') == 'in_progress':
        raise ResolutionFailure('BOUNDED_REPAIR_UNAVAILABLE')
    if mig_record and mig_record.get('status') not in (None, 'COMPLETE'):
        raise ResolutionFailure('BOUNDED_REPAIR_UNAVAILABLE')

    journal = last_canonical_write_journal(root)
    if journal is None:
        raise ResolutionFailure('BOUNDED_REPAIR_NO_JOURNAL')
    journal_target = journal['target_path']
    if target_path is not None and _canonical_path_key(target_path) != _canonical_path_key(journal_target):
        raise ResolutionFailure('BOUNDED_REPAIR_SCOPE_MISMATCH')
    report = build_status(root)['compatibility']
    blocking = [item for item in report['diagnostics'] if item.get('blocking')]
    if report['compatibility'] != 'BLOCKED' or not blocking:
        raise ResolutionFailure('BOUNDED_REPAIR_NOT_BLOCKED')
    if any(_canonical_path_key(str(item.get('source_path') or '')) != _canonical_path_key(journal_target) for item in blocking):
        raise ResolutionFailure('BOUNDED_REPAIR_MULTIPLE_TARGETS')

    current_file = safe_path(root, journal_target)
    if not current_file.is_file():
        raise ResolutionFailure('BOUNDED_REPAIR_TARGET_MISSING')
    current_raw = current_file.read_bytes()
    current_fp = digest(current_raw)
    expected_result = journal.get('authorized_result_fingerprint')
    if (not isinstance(expected_result, str) or not re.fullmatch(r'sha256:[a-f0-9]{64}', expected_result)
            or current_fp != expected_result or current_fp == journal['before_fingerprint']):
        raise ResolutionFailure('BOUNDED_REPAIR_NOT_CAUSAL')

    if candidate_bytes is not None:
        preval = prevalidate_canonical_write(root, journal_target, candidate_bytes)
        if not preval['valid']:
            raise ResolutionFailure('BOUNDED_REPAIR_CANDIDATE_INVALID')
        if digest(candidate_bytes) != journal['before_fingerprint']:
            if not journal.get('existed') or not isinstance(journal.get('before_content_b64'), str):
                raise ResolutionFailure('BOUNDED_REPAIR_BEFORE_SNAPSHOT_UNAVAILABLE')
            try:
                before_bytes = base64.b64decode(journal['before_content_b64'].encode('ascii'), validate=True)
                if digest(before_bytes) != journal['before_fingerprint']:
                    raise ResolutionFailure('BOUNDED_REPAIR_JOURNAL_CORRUPT')
                before_value = load_yaml(before_bytes.decode('utf-8-sig'))
                candidate_value = load_yaml(candidate_bytes.decode('utf-8-sig'))
            except (ValueError, UnicodeError, yaml.YAMLError):
                raise ResolutionFailure('BOUNDED_REPAIR_JOURNAL_CORRUPT') from None
            if not isinstance(before_value, dict) or protected_values(before_value) != protected_values(candidate_value):
                raise ResolutionFailure('BOUNDED_REPAIR_PROTECTED_VALUES_CHANGED')
        action = 'replace'
        after_fp = digest(candidate_bytes)
    else:
        if journal['existed'] and isinstance(journal.get('before_content_b64'), str):
            restored = base64.b64decode(journal['before_content_b64'].encode('ascii'))
            if digest(restored) != journal['before_fingerprint']:
                raise ResolutionFailure('BOUNDED_REPAIR_JOURNAL_CORRUPT')
            preval = prevalidate_canonical_write(root, journal_target, restored)
            if not preval['valid']:
                raise ResolutionFailure('BOUNDED_REPAIR_ROLLBACK_INVALID')
            action = 'rollback'
            after_fp = journal['before_fingerprint']
        elif not journal['existed']:
            action = 'rollback_delete'
            after_fp = 'ABSENT'
        else:
            raise ResolutionFailure('BOUNDED_REPAIR_ROLLBACK_UNAVAILABLE')

    plan = {
        'schema_version': 1,
        'target_path': journal_target,
        'action': action,
        'journal_run_id': journal['run_id'],
        'before_fingerprint': journal['before_fingerprint'],
        'current_invalid_fingerprint': current_fp,
        'after_fingerprint': after_fp,
        'blocking_diagnostic_ids': sorted(item['diagnostic_id'] for item in blocking),
        'source_fingerprint': report['source_fingerprint'],
    }
    plan['plan_hash'] = digest(json.dumps(plan, sort_keys=True).encode('utf-8'))
    return plan


def apply_last_canonical_write_repair(
    root: Path,
    *,
    plan_hash: str,
    run_id: str,
    target_path: str | None = None,
    candidate_bytes: bytes | None = None,
) -> dict[str, Any]:
    """Atomically execute the bounded last-write rollback or prevalidated repair (A2)."""
    import base64
    from build_project_status import build_status
    from projection_io import safe_path
    if not isinstance(run_id, str) or not re.fullmatch(r'RUN-[A-Za-z0-9-]{4,80}', run_id):
        raise ResolutionFailure('RESOLUTION_RUN_REQUIRED')
    active_run = os.environ.get('MXAGILE_RUN_ID', '')
    if not active_run:
        raise ResolutionFailure('BOUNDED_REPAIR_RUN_NOT_OBSERVABLE')
    if active_run != run_id:
        raise ResolutionFailure('BOUNDED_REPAIR_RUN_MISMATCH')
    root = root.resolve()
    plan = last_canonical_write_repair_plan(root, target_path=target_path, candidate_bytes=candidate_bytes)
    if plan['journal_run_id'] != run_id:
        raise ResolutionFailure('BOUNDED_REPAIR_RUN_MISMATCH')
    if plan['plan_hash'] != plan_hash:
        raise ResolutionFailure('STALE_BOUNDED_REPAIR_PLAN')
    journal = last_canonical_write_journal(root)
    target = safe_path(root, plan['target_path'])
    original_invalid = target.read_bytes()
    if digest(original_invalid) != plan['current_invalid_fingerprint']:
        raise ResolutionFailure('STALE_BOUNDED_REPAIR_PLAN')
    try:
        if plan['action'] == 'replace' and candidate_bytes is not None:
            atomic_replace(target, candidate_bytes)
        elif plan['action'] == 'rollback' and journal and isinstance(journal.get('before_content_b64'), str):
            restored = base64.b64decode(journal['before_content_b64'].encode('ascii'))
            atomic_replace(target, restored)
        elif plan['action'] == 'rollback_delete':
            target.unlink()
        else:
            raise ResolutionFailure('BOUNDED_REPAIR_UNAVAILABLE')
        after = build_status(root)['compatibility']
        remaining_blocking = [item for item in after['diagnostics'] if item.get('blocking')]
        if remaining_blocking:
            raise ResolutionFailure('BOUNDED_REPAIR_POSTCHECK_FAILED')
        _, events = _auxiliary_runtime()
        try:
            events.append_event(root, 'recovery_required', run_id=run_id, actor='bounded_write_repair', host='mxagile',
                                payload={'operation_class': 'CONTROLLED_MUTATION', 'target_path': plan['target_path'],
                                         'action': plan['action'], 'plan_hash': plan['plan_hash']})
        except Exception:
            pass
        return {'result': 'APPLIED', 'plan': plan, 'compatibility': after['compatibility'], 'blocking_diagnostic_count': 0}
    except Exception:
        atomic_replace(target, original_invalid)
        raise


def inspect_mocketeer_sources(root: Path, source_paths: list[Path] | None = None) -> list[dict[str, Any]]:
    """Observe embedded source declarations, including nested SPA entry points."""
    root = root.resolve()
    ui_ux = root / 'input-resources/ui-ux'
    if source_paths is None and (not ui_ux.is_dir() or ui_ux.is_symlink()):
        return []
    sources: list[dict[str, Any]] = []
    spec_re = re.compile(r'<script[^>]*\bid=["\']mocketeer-spec["\'][^>]*>(.*?)</script>', re.I | re.S)
    for html_path in sorted(source_paths if source_paths is not None else ui_ux.rglob('*')):
        if html_path.suffix.lower() not in ('.html', '.htm') or (source_paths is None and any(
            part in ('_archive', '_history') for part in html_path.relative_to(ui_ux).parts
        )):
            continue
        relative = html_path.relative_to(root).as_posix()
        safe = safe_file(root, relative)
        if safe is None:
            continue
        try:
            raw = safe.read_bytes()
            match = spec_re.search(raw.decode('utf-8-sig', errors='replace'))
        except OSError:
            continue
        if not match:
            continue
        try:
            spec = json.loads(match.group(1))
        except ValueError:
            spec = None
        if not isinstance(spec, dict):
            sources.append({'path': relative, 'sha256': digest(raw), 'valid_json': False,
                            'contract_readiness': 'MALFORMED_CONTRACT', 'handoff_ready': False})
            continue
        mockup = spec.get('mockup') if isinstance(spec.get('mockup'), dict) else {}
        readiness = spec.get('consumer_readiness') if isinstance(spec.get('consumer_readiness'), dict) else {}
        assessment = spec.get('assessment') if isinstance(spec.get('assessment'), dict) else {}
        mockup_id = mockup.get('id') if isinstance(mockup.get('id'), str) and mockup['id'].strip() else None
        revision = mockup.get('revision')
        revision = revision if type(revision) is int and revision >= 1 else None
        previous = mockup.get('previous_revision')
        previous = previous if type(previous) is int and previous >= 1 else None
        contract_ready = (type(spec.get('schema_version')) is int and spec['schema_version'] == 1
                          and mockup_id is not None and revision is not None
                          and (mockup.get('previous_revision') is None or (previous is not None and previous < revision))
                          and isinstance(spec.get('roles'), list) and isinstance(spec.get('requirements'), list))
        handoff_ready = (readiness.get('status') == 'READY'
                         or readiness.get('MOCKETEER_HANDOFF_READY') in ('JA', 'YES', True)
                         or assessment.get('development_handoff_readiness') in ('HANDOFF_READY', 'READY'))
        runtime_claim = ('VERIFIED' if readiness.get('runtime_verified') is True
                         else 'PARTIAL' if readiness.get('runtime_validation') == 'PARTIAL' else 'NOT_VERIFIED')
        screens = spec.get('screens') if isinstance(spec.get('screens'), list) else []
        lifecycle = spec.get('requirement_lifecycle') if isinstance(spec.get('requirement_lifecycle'), list) else []
        sources.append({
            'path': relative, 'sha256': digest(raw), 'valid_json': True,
            'canonical_source_type': 'embedded_mocketeer_spec', 'mockup_id': mockup_id,
            'revision': revision, 'previous_revision': previous,
            'contract_readiness': 'CONTRACT_READY' if contract_ready else 'INCOMPLETE',
            'handoff_ready': bool(handoff_ready), 'readiness_origin': 'SOURCE_DECLARATION',
            'runtime_verification': runtime_claim, 'runtime_verification_origin': 'SOURCE_DECLARATION',
            'embedded_active_target_claim': mockup.get('active_target') is True,
            'requirement_count': len(spec['requirements']) if isinstance(spec.get('requirements'), list) else 0,
            'decision_count': len(spec['decisions']) if isinstance(spec.get('decisions'), list) else 0,
            'screen_ids': [s.get('id') or s.get('screen_id') for s in screens
                           if isinstance(s, dict) and isinstance(s.get('id') or s.get('screen_id'), str)],
            'requirement_lifecycle_summary': {
                status: sum(1 for item in lifecycle if isinstance(item, dict) and item.get('lifecycle') == status)
                for status in ('UNCHANGED', 'MODIFIED', 'SUPERSEDED', 'OBSOLETE', 'SPLIT', 'MERGED', 'NEW', 'AMBIGUOUS')
                if any(isinstance(item, dict) and item.get('lifecycle') == status for item in lifecycle)
            },
        })
    return sources


def classify_revision_dimensions(root: Path, revision_doc: dict, mocketeer_source: dict | None = None) -> dict[str, Any]:
    """Project acceptance needs actual canonical approvals; source claims remain declarations."""
    root = root.resolve()
    decisions: dict[str, list[dict]] = {}
    for path in sorted((root / 'planning/decisions').glob('*.yml')):
        safe = safe_file(root, path.relative_to(root).as_posix())
        if safe is None:
            continue
        try:
            doc = load_yaml(safe.read_text(encoding='utf-8-sig'))
        except (OSError, UnicodeError, yaml.YAMLError):
            continue
        if isinstance(doc, dict) and isinstance(doc.get('ID'), str):
            decisions.setdefault(doc['ID'], []).append({'path': path, 'document': doc})
    refs = revision_doc.get('acceptance_decisions')
    refs_valid = (isinstance(refs, list) and bool(refs) and all(
        isinstance(ref, str) and re.fullmatch(r'DEC-[0-9]{3,}', ref) for ref in refs
    ) and len(set(refs)) == len(refs))
    confirmed, unresolved = [], []
    for ref in refs if refs_valid else []:
        matches = decisions.get(ref, [])
        if (len(matches) == 1 and matches[0]['path'].stem == ref
                and matches[0]['document'].get('status') == 'CONFIRMED'
                and not raw_schema_errors(matches[0]['path'].relative_to(root).as_posix(), matches[0]['document'])):
            confirmed.append(ref)
        else:
            unresolved.append(ref)
    project_accepted = revision_doc.get('refinement_status') == 'ACCEPTED' and bool(refs_valid) and not unresolved
    active_claim = revision_doc.get('active_target') is True
    lifecycle_valid = revision_doc.get('lifecycle_status') in ('SOURCE', 'REFINED_TARGET')
    source = mocketeer_source or {}
    return {
        'revision_id': revision_doc.get('revision_id'),
        'mocketeer_contract_ready': source.get('contract_readiness') == 'CONTRACT_READY',
        'mocketeer_handoff_ready': source.get('handoff_ready') is True,
        'readiness_origin': 'SOURCE_DECLARATION' if mocketeer_source else 'UNASSESSED',
        'runtime_verification': 'NOT_VERIFIED',
        'source_runtime_verification_claim': source.get('runtime_verification', 'NOT_VERIFIED'),
        'project_accepted_revision': project_accepted,
        'project_active_target': active_claim and project_accepted and lifecycle_valid,
        'active_target_without_acceptance': active_claim and not project_accepted,
        'active_target_lifecycle_conflict': active_claim and not lifecycle_valid,
        'confirmed_acceptance_decisions': confirmed, 'unresolved_acceptance_decisions': unresolved,
    }


def evaluate_mocketeer_reconciliation(root: Path) -> dict[str, Any]:
    """Read both revision stores; reconcile exact source identities without target mutations."""
    root = root.resolve()
    sources = inspect_mocketeer_sources(root)
    records, diagnostics = [], []
    paths = sorted(set((root / 'planning/revisions').glob('REV-*.yaml')) | set(
        (root / 'planning/target-mockups').glob('*/_history/REV-*/revision.yaml')))
    for path in paths:
        relative = path.relative_to(root).as_posix()
        safe = safe_file(root, relative)
        if safe is None:
            diagnostics.append({'path': relative, 'reason': 'REVISION_UNREADABLE'})
            continue
        try:
            raw = safe.read_bytes()
            doc = load_yaml(raw.decode('utf-8-sig'))
        except (OSError, UnicodeError, yaml.YAMLError):
            doc = None
        if not isinstance(doc, dict):
            diagnostics.append({'path': relative, 'reason': 'REVISION_INVALID_DOCUMENT'})
            continue
        archive = path.name == 'revision.yaml'
        container_id = path.parent.name if archive else path.stem
        rid = doc.get('revision_id')
        namespace = doc.get('mockup_name') or (path.parent.parent.parent.name if archive else doc.get('mockup_id'))
        namespace_valid = isinstance(namespace, str) and bool(namespace.strip())
        if doc.get('mockup_id') is not None and not (isinstance(doc['mockup_id'], str) and doc['mockup_id'].strip()):
            namespace_valid = False
        if archive and namespace_valid:
            namespace_valid = _canonical_path_key(namespace) == _canonical_path_key(path.parent.parent.parent.name)
        if not namespace_valid or rid != container_id or not re.fullmatch(r'REV-[0-9]{3,}', rid or ''):
            diagnostics.append({'path': relative, 'reason': 'REVISION_IDENTITY_AMBIGUOUS'})
            continue
        number = int(rid.split('-')[1])
        if number < 1 or ('revision' in doc and (type(doc['revision']) is not int or doc['revision'] != number)):
            diagnostics.append({'path': relative, 'reason': 'REVISION_NUMBER_CONFLICT'})
            continue
        predecessor = doc.get('previous_revision')
        predecessor_id = doc.get('predecessor_revision_id')
        lineage_valid = (predecessor is None or (type(predecessor) is int and 1 <= predecessor < number))
        if predecessor_id is not None:
            lineage_valid = lineage_valid and isinstance(predecessor_id, str) and bool(re.fullmatch(r'REV-[0-9]{3,}', predecessor_id))
            if lineage_valid:
                pred_num = int(predecessor_id.split('-')[1])
                lineage_valid = 1 <= pred_num < number and (predecessor is None or pred_num == predecessor)
        fingerprint = doc.get('artifact_hash')
        fingerprint_valid = fingerprint is None or (isinstance(fingerprint, str) and bool(re.fullmatch(r'sha256:[a-f0-9]{64}', fingerprint)))
        fingerprint_scope = 'source_artifact'
        source_id = doc.get('mockup_id') or namespace
        source_revision = number
        source_previous = predecessor if predecessor is not None else (int(predecessor_id.split('-')[1]) if lineage_valid and predecessor_id else None)
        if archive:
            entry = doc.get('entry_point', 'index.html')
            entry_path = safe_file(root, (path.parent.relative_to(root) / entry).as_posix()) if isinstance(entry, str) else None
            if entry_path:
                try:
                    snapshot_hash = digest(entry_path.read_bytes())
                    if fingerprint and fingerprint != doc.get('bundle_hash') and fingerprint != snapshot_hash:
                        fingerprint_valid = False
                    if doc.get('bundle_hash'):
                        from artifact_hashing import hash_spa_bundle
                        if any(item.is_symlink() for item in path.parent.rglob('*')) or hash_spa_bundle(path.parent, exclude_revision_yaml=True) != doc['bundle_hash']:
                            fingerprint_valid = False
                    fingerprint = snapshot_hash
                    fingerprint_scope = 'archived_entry_point'
                    archived_sources = inspect_mocketeer_sources(root, [entry_path])
                    archived_source = archived_sources[0] if len(archived_sources) == 1 else {}
                    source_id = archived_source.get('mockup_id')
                    source_revision = archived_source.get('revision')
                    source_previous = archived_source.get('previous_revision')
                except (OSError, ValueError):
                    fingerprint_valid = False
            else:
                fingerprint = None
                fingerprint_valid = False
                source_id = source_revision = source_previous = None
        observed_fields = ('revision_id', 'revision', 'mockup_id', 'mockup_name', 'previous_revision',
                           'predecessor_revision_id', 'artifact_path', 'artifact_hash', 'bundle_hash',
                           'entry_point', 'refinement_status', 'lifecycle_status', 'active_target',
                           'acceptance_decisions', 'impact_scope', 'affected_screens', 'screens', 'revision_delta')
        observed_doc = {key: doc[key] for key in observed_fields if key in doc}
        record = {
            'path': relative, 'manifest_fingerprint': digest(raw), 'document': observed_doc,
            'mockup_id': namespace, 'revision': number, 'revision_id': rid,
            'source_mockup_id': source_id, 'source_revision': source_revision, 'source_previous_revision': source_previous,
            'source_fingerprint': fingerprint, 'fingerprint_valid': bool(fingerprint_valid),
            'fingerprint_scope': fingerprint_scope, 'lineage_valid': bool(lineage_valid),
            'dimensions': classify_revision_dimensions(root, doc),
        }
        records.append(record)
    by_identity: dict[tuple, list[dict]] = {}
    for record in records:
        by_identity.setdefault((record['source_mockup_id'], record['source_revision']), []).append(record)
    source_hashes: dict[tuple, set[str]] = {}
    for source in sources:
        source_hashes.setdefault((source.get('mockup_id'), source.get('revision')), set()).add(source['sha256'])
    unreconciled, reconciled, unassessed = [], [], []
    for source in sources:
        key = (source.get('mockup_id'), source.get('revision'))
        matches = by_identity.get(key, [])
        reason = None
        if source.get('contract_readiness') != 'CONTRACT_READY':
            reason = 'SOURCE_CONTRACT_UNASSESSED'
        elif len(source_hashes[key]) > 1 or len(matches) > 1:
            reason = 'SOURCE_REVISION_AMBIGUOUS'
        elif not matches:
            reason = 'SOURCE_REVISION_NOT_RECORDED'
        else:
            record = matches[0]
            if not record['lineage_valid']:
                reason = 'REVISION_LINEAGE_CONFLICT'
            elif source.get('previous_revision') is not None and source['previous_revision'] != record['source_previous_revision']:
                reason = 'SOURCE_LINEAGE_UNRECONCILED'
            elif not record['fingerprint_valid'] or record['source_fingerprint'] != source['sha256']:
                reason = 'SOURCE_FINGERPRINT_CHANGED_OR_UNVERIFIED'
        if reason is None:
            reconciled.append({**source, 'reconciliation_state': 'RECONCILED', 'revision_path': matches[0]['path'],
                               'fingerprint_scope': matches[0]['fingerprint_scope'],
                               'dimensions': classify_revision_dimensions(root, matches[0]['document'], source)})
        else:
            item = {**source, 'reconciliation_state': 'RECONCILIATION_REQUIRED', 'reason': reason,
                    'auto_set_active_target': False, 'recommended_action': 'initiate_mocketeer_delta_and_impact_reconciliation'}
            (unreconciled if source.get('handoff_ready') else unassessed).append(item)
    return {
        'canonical_delivery_source': 'embedded_mocketeer_spec', 'sources_inspected': len(sources),
        'reconciled': reconciled, 'unreconciled_handoff_ready': unreconciled, 'unassessed_sources': unassessed,
        'reconciliation_required': bool(unreconciled), 'revision_records': records, 'revision_diagnostics': diagnostics,
    }


def page_identity_binding(root: Path, page: dict, target: dict) -> dict:
    """Validate bounded recorded identity and its current inputs, not a live Mendix attestation."""
    result = {'state': 'NOT_OBSERVABLE', 'identity_evidence': None}
    binding = page.get('revision_binding')
    if not isinstance(binding, dict):
        return result
    if jsonschema is None:
        return result
    binding_schema = schema_validator(SCHEMA_ROOT / 'page.schema.json').schema['properties']['revision_binding']
    if not jsonschema.Draft7Validator(binding_schema).is_valid(binding):
        return {**result, 'state': 'PAGE_IDENTITY_CONFLICT'}
    evidence = binding.get('identity_evidence')
    if not isinstance(evidence, dict):
        return result
    path = safe_file(root, evidence.get('path')) if isinstance(evidence.get('path'), str) else None
    if path is None:
        return result
    result['identity_evidence'] = evidence['path']
    try:
        if path.stat().st_size > 262144:
            return result
        raw = path.read_bytes()
    except OSError:
        return result
    if digest(raw) != evidence.get('sha256'):
        return {**result, 'state': 'STALE_IDENTITY_EVIDENCE'}
    try:
        observed = json.loads(raw)
    except (ValueError, UnicodeError):
        return result
    if not isinstance(observed, dict) or observed.get('provenance') != 'OBSERVED' or observed.get('view_state') != 'FRESH':
        return result
    inputs = observed.get('source_fingerprints')
    identity = observed.get('page_identity')
    if not isinstance(inputs, list) or not inputs or not isinstance(identity, dict):
        return result
    for item in inputs:
        source = safe_file(root, item.get('path')) if isinstance(item, dict) and isinstance(item.get('path'), str) else None
        if source is None:
            return {**result, 'state': 'STALE_IDENTITY_EVIDENCE'}
        source_hash = hashlib.sha256()
        try:
            with source.open('rb') as handle:
                for chunk in iter(lambda: handle.read(65536), b''):
                    source_hash.update(chunk)
        except OSError:
            return result
        if 'sha256:' + source_hash.hexdigest() != item.get('sha256'):
            return {**result, 'state': 'STALE_IDENTITY_EVIDENCE'}
    fields = ('mocketeer_screen_id', 'page_id', 'page_name', 'mockup_id', 'backup_pages')
    if (any(field not in binding or identity.get(field) != binding[field] for field in fields)
            or any(not isinstance(binding.get(field), str) or not binding[field].strip() for field in fields[:-1])
            or binding['page_id'] != page.get('page_id') or binding['page_name'] != page.get('page_name')
            or binding['mockup_id'] != target.get('source_mockup_id', target['mockup_id'])
            or not isinstance(binding['backup_pages'], list) or binding['page_name'] in binding['backup_pages']
            or binding.get('current_revision') != page.get('target_revision')
            or binding.get('delta_impact') not in ('IMPACTED', 'UNCHANGED', 'UNKNOWN')
            or 'previous_revision' not in binding or not isinstance(binding.get('existing_evidence'), list)):
        return {**result, 'state': 'PAGE_IDENTITY_CONFLICT'}
    return {**result, 'state': 'PROVEN', 'binding': binding}


def reconcile_page_revision_bindings(root: Path, revision_id: str | None = None, *, mockup_name: str | None = None,
                                     _evaluation: dict[str, Any] | None = None) -> dict[str, Any]:
    """Evaluate accepted-target bindings and reuse eligibility without rewriting artifacts or declaring evidence PASS."""
    root = root.resolve()
    evaluation = _evaluation if _evaluation is not None else evaluate_mocketeer_reconciliation(root)
    records = evaluation['revision_records']
    candidates = [r for r in records if (r['revision_id'] == revision_id if revision_id
                                       else r['document'].get('active_target') is True)
                  and (mockup_name is None or _canonical_path_key(r['mockup_id']) == _canonical_path_key(mockup_name))]
    result = {'revision_id': revision_id, 'state': 'NO_ACTIVE_REVISION', 'bound_pages': [],
              'impacted_pages': [], 'unchanged_pages': [], 'missing_pages': [], 'ambiguous_pages': [],
              'unrelated_pages': [], 'identity_unresolved_pages': [], 'revision_diagnostics': evaluation['revision_diagnostics'],
              'selective_binding_rule': 'only_impacted_pages_require_re_binding_and_stale_propagation',
              'retention_requires_existing_valid_evidence': True, 'evidence_retention_is_pass': False}
    if len(candidates) > 1:
        result['state'] = 'AMBIGUOUS_REVISION'
        return result
    if not candidates:
        if evaluation['revision_diagnostics']:
            result['state'] = 'REVISION_SCOPE_UNASSESSED'
        return result
    target = candidates[0]
    if sum(_canonical_path_key(r['mockup_id']) == _canonical_path_key(target['mockup_id']) and r['revision_id'] == target['revision_id'] for r in records) != 1:
        result['state'] = 'AMBIGUOUS_REVISION'
        return result
    result['revision_id'] = target['revision_id']
    result['mockup_id'] = target['mockup_id']
    if not target['dimensions']['project_active_target'] or not target['lineage_valid']:
        result['state'] = 'REVISION_NOT_ACTIVE_OR_ACCEPTED'
        return result
    if not target['fingerprint_valid']:
        result['state'] = 'REVISION_FINGERPRINT_CONFLICT'
        return result
    doc = target['document']
    scope = doc.get('impact_scope', 'unknown')
    affected = set()
    scope_invalid = scope not in ('targeted', 'full', 'cross_cutting', 'unknown')
    screen_refs = doc.get('affected_screens', [])
    if not isinstance(screen_refs, list):
        screen_refs, scope_invalid = [], True
    for sid in screen_refs:
        if isinstance(sid, str) and re.fullmatch(r'PAGE-[A-Z0-9_-]+', sid):
            affected.add(sid)
        else:
            scope_invalid = True
    unchanged_proven = set()
    screens = doc.get('screens') if isinstance(doc.get('screens'), list) else []
    for screen in screens:
        if not isinstance(screen, dict):
            scope_invalid = True
            continue
        sid = screen.get('page_id') or screen.get('screen_id')
        deltas = [v for k, v in screen.items() if k.startswith('delta_')]
        if not isinstance(sid, str) or not re.fullmatch(r'PAGE-[A-Z0-9_-]+', sid):
            scope_invalid = True
        elif deltas and all(delta == 'UNCHANGED' for delta in deltas):
            unchanged_proven.add(sid)
        elif deltas:
            affected.add(sid)
    delta = doc.get('revision_delta') if isinstance(doc.get('revision_delta'), dict) else {}
    effects = delta.get('effects') if isinstance(delta.get('effects'), list) else []
    shared_change = any(delta.get(flag) is True for flag in ('roles_refined', 'permissions_refined', 'business_rules_refined', 'platform_boundaries_refined'))
    for effect in effects:
        if not isinstance(effect, dict):
            scope_invalid = True
            continue
        if effect.get('type') in ('NAVIGATION', 'ROLE', 'PERMISSION', 'BUSINESS_RULE') and effect.get('change') != 'NO_CHANGE':
            shared_change = True
        sid = effect.get('target')
        if isinstance(sid, str) and re.fullmatch(r'PAGE-[A-Z0-9_-]+', sid):
            (unchanged_proven if effect.get('change') == 'NO_CHANGE' else affected).add(sid)
    if scope == 'targeted' and not affected:
        scope_invalid = True
    pages: dict[str, list[dict]] = {}
    for path in sorted((root / 'planning/ui-inventory').glob('*.yaml')):
        relative = path.relative_to(root).as_posix()
        if is_standalone_interaction_artifact(relative):
            continue
        safe = safe_file(root, relative)
        if safe is None:
            continue
        try:
            page = load_yaml(safe.read_text(encoding='utf-8-sig'))
        except (OSError, UnicodeError, yaml.YAMLError):
            continue
        if not isinstance(page, dict) or not isinstance(page.get('page_id'), str):
            continue
        pid = page['page_id']
        page_namespace = page.get('mockup_name')
        namespaces = {page_namespace} if isinstance(page_namespace, str) and page_namespace.strip() else set()
        if len(namespaces) != 1:
            artifact_path = doc.get('artifact_path')
            related_path = isinstance(artifact_path, str) and artifact_path in (page.get('target_mockup'), page.get('source_mockup'))
            if pid in affected or page.get('target_revision') == target['revision_id'] or related_path or target['mockup_id'] in namespaces:
                result['ambiguous_pages'].append(pid)
        elif _canonical_path_key(target['mockup_id']) not in {_canonical_path_key(name) for name in namespaces}:
            result['unrelated_pages'].append(pid)
        else:
            pages.setdefault(pid, []).append(page)
    broad_scope = scope in ('full', 'cross_cutting', 'unknown') or shared_change or scope_invalid
    if broad_scope:
        affected.update(pages)
    result['missing_pages'] = sorted(affected - pages.keys())
    implementation_names: dict[str, list[str]] = {}
    screen_identities: dict[str, list[str]] = {}
    for pid, matches in pages.items():
        for page in matches:
            name = page.get('page_name')
            binding = page.get('revision_binding') or {}
            screen = binding.get('mocketeer_screen_id') if isinstance(binding, dict) else None
            if isinstance(name, str) and name.strip():
                implementation_names.setdefault(name, []).append(pid)
            if isinstance(screen, str) and screen.strip():
                screen_identities.setdefault(screen, []).append(pid)
    duplicate_identities = {pid for index in (implementation_names, screen_identities)
                            for ids in index.values() if len(ids) > 1 for pid in ids}
    for pid, matches in sorted(pages.items()):
        if len(matches) != 1 or pid in duplicate_identities:
            result['ambiguous_pages'].append(pid)
            continue
        identity = page_identity_binding(root, matches[0], target)
        is_bound = matches[0].get('target_revision') == target['revision_id'] and identity['state'] == 'PROVEN'
        if pid in affected and identity['state'] != 'PROVEN':
            result['identity_unresolved_pages'].append({'page_id': pid, **identity})
        if is_bound:
            result['bound_pages'].append(pid)
        if pid in affected:
            result['impacted_pages'].append({'page_id': pid, 'bound_to_active': is_bound,
                                            'evidence_disposition': 'STALE_REVERIFY_REQUIRED'})
        else:
            result['unchanged_pages'].append({'page_id': pid, 'bound_to_active': is_bound,
                'evidence_disposition': 'RETAIN_VALID_EVIDENCE' if pid in unchanged_proven and identity['state'] == 'PROVEN' else 'UNCHANGED_SCOPE_UNVERIFIED'})
    if scope_invalid or scope == 'unknown':
        result['state'] = 'IMPACT_SCOPE_UNASSESSED'
    elif result['ambiguous_pages']:
        result['state'] = 'AMBIGUOUS_PAGE_MAPPING'
    elif result['missing_pages'] or not result['impacted_pages']:
        result['state'] = 'MISSING_PAGE_MAPPING'
    elif result['identity_unresolved_pages']:
        result['state'] = 'PAGE_IDENTITY_UNRESOLVED'
    elif all(page['bound_to_active'] for page in result['impacted_pages']):
        result['state'] = 'BOUND'
    elif any(page['bound_to_active'] for page in result['impacted_pages']):
        result['state'] = 'PARTIALLY_BOUND'
    else:
        result['state'] = 'ACTIVE_REVISION_UNBOUND'
    return result


def evaluate_wave_reconciliation(root: Path) -> dict[str, Any]:
    """Compare execution-waves.md claims against canonical process-state.yaml (C2, C3)."""
    from wave_ids import extract_plan_wave_claims
    root = root.resolve()
    plan_path = safe_file(root, 'planning/execution-waves.md')
    process_path = safe_file(root, 'planning/lifecycle/process-state.yaml')
    plan_text = plan_path.read_text(encoding='utf-8-sig') if plan_path else ''
    process_doc = load_yaml(process_path.read_text(encoding='utf-8-sig')) if process_path else {}
    waves = process_doc.get('waves', {}) if isinstance(process_doc, dict) and isinstance(process_doc.get('waves'), dict) else {}
    claims = extract_plan_wave_claims(plan_text)
    conflicts = []
    legacy_unreconciled = []

    for wave_id, entry in sorted(claims.items()):
        statuses = {item[0] for item in entry['statuses']}
        commits = {item[0] for item in entry['commits']}
        if len(statuses) > 1:
            conflicts.append({
                'wave_id': wave_id,
                'conflict_type': 'INTERNAL_PLAN_STATUS_CONFLICT',
                'status': 'RECONCILIATION_REQUIRED',
                'claimed_statuses': sorted(statuses),
            })
        if len(commits) > 1:
            conflicts.append({
                'wave_id': wave_id,
                'conflict_type': 'INTERNAL_PLAN_COMMIT_CONFLICT',
                'status': 'RECONCILIATION_REQUIRED',
                'claimed_commits': sorted(commits),
            })
        canonical = waves.get(wave_id)
        canonical_phase = canonical.get('phase') if isinstance(canonical, dict) else None
        if 'done' in statuses and canonical_phase != 'done':
            conflicts.append({
                'wave_id': wave_id,
                'conflict_type': 'PLAN_DONE_VS_PROCESS_STATE',
                'status': 'RECONCILIATION_REQUIRED',
                'plan_claim': 'done',
                'canonical_phase': canonical_phase,
            })

    for wave_id, block in sorted(waves.items()):
        if not isinstance(block, dict):
            continue
        resume_note = str(block.get('resume_from') or '')
        if 'UNKNOWN_REQUIRES_RECONCILIATION' in resume_note:
            legacy_unreconciled.append({
                'wave_id': wave_id,
                'phase': block.get('phase'),
                'classification': 'UNKNOWN_REQUIRES_RECONCILIATION',
                'auto_promote_to_done': False,
            })

    return {
        'reconciliation_required': bool(conflicts or legacy_unreconciled),
        'plan_process_conflicts': conflicts,
        'legacy_waves_requiring_reconciliation': legacy_unreconciled,
    }


def wave_delivery_prerequisites(root: Path, wave_id: str | None) -> dict[str, Any]:
    """Read governing decisions and current work from canonical Task/Spec links, not plan prose."""
    result: dict[str, Any] = {'requirement_ids': [], 'open_decisions': [], 'unfinished_tasks': [], 'security_required': False}
    if not wave_id:
        return result
    req_ids: set[str] = set()
    for path in sorted((root / 'planning/tasks').glob('*.yml')):
        relative = path.relative_to(root).as_posix()
        safe = safe_file(root, relative)
        if safe is None:
            continue
        try:
            task = load_yaml(safe.read_bytes().decode('utf-8-sig'))
        except (OSError, UnicodeError, yaml.YAMLError):
            continue
        if (not isinstance(task, dict) or schema_errors(relative, task)
                or assignment(root, task, {wave_id})[1] != wave_id):
            continue
        req_ids.update(ref for ref in task.get('req', []) if isinstance(ref, str))
        spec_id = task.get('spec')
        spec_file = safe_file(root, f'specs/{spec_id}.yml') if isinstance(spec_id, str) else None
        if spec_file:
            try:
                spec = load_yaml(spec_file.read_bytes().decode('utf-8-sig'))
                if isinstance(spec, dict) and not schema_errors(f'specs/{spec_id}.yml', spec):
                    req_ids.update(ref for ref in spec.get('requirements', []) if isinstance(ref, str))
            except (OSError, UnicodeError, yaml.YAMLError):
                pass
        if task.get('status', 'pending') in {'pending', 'in_progress', 'failed', 'blocked'}:
            result['unfinished_tasks'].append(task.get('ID') or path.stem)
        if task.get('type') == 'security':
            result['security_required'] = True
    for path in sorted((root / 'planning/decisions').glob('*.yml')):
        relative = path.relative_to(root).as_posix()
        safe = safe_file(root, relative)
        if safe is None:
            continue
        try:
            decision = projected_for_validation(relative, load_yaml(safe.read_bytes().decode('utf-8-sig')))
        except (OSError, UnicodeError, yaml.YAMLError):
            continue
        if (isinstance(decision, dict) and not schema_errors(relative, decision)
                and decision.get('status') == 'PROPOSED'
                and req_ids.intersection(decision.get('affected_requirements') or [])):
            result['open_decisions'].append({'id': decision.get('ID') or path.stem,
                                              'affected_requirements': decision.get('affected_requirements', [])})
    result['requirement_ids'] = sorted(req_ids)
    return result


def delivery_preflight(root: Path, *, require_capability: str = '') -> dict[str, Any]:
    """Fast, scope-aware preflight before starting a Delivery phase or larger Workpackage (B1, B2, H2)."""
    from build_project_status import build_status
    root = root.resolve()
    guard, _ = _auxiliary_runtime()
    facts = guard.load_project_facts(root)
    auth = guard.delivery_authorization(facts, 'IMPLEMENTATION_WRITE')
    blocker_codes = [item['code'] for item in auth.get('must_findings', [])]
    warning_codes = [item['code'] for item in auth.get('should_findings', []) if item.get('code') not in {'MODEL_SCOPE_NOT_OBSERVABLE', 'PROJECT_IDENTITY_NOT_OBSERVED'}]

    wave_id = facts.mission.get('active_wave') if isinstance(facts.mission, dict) else None
    wave_block = (facts.process_state.get('waves') or {}).get(wave_id) if isinstance(facts.process_state, dict) and wave_id else {}
    wave_block = wave_block if isinstance(wave_block, dict) else {}
    prerequisites = wave_delivery_prerequisites(root, wave_id)
    open_decisions = prerequisites['open_decisions']
    if open_decisions:
        blocker_codes.append('OPEN_WAVE_DECISION_PROPOSED')

    # Check Security Gate status (H2: No Model Error != Security Gate Passed)
    resume_text = str(wave_block.get('resume_from') or '')
    gates = wave_block.get('gates') if isinstance(wave_block.get('gates'), dict) else {}
    security_gate = gates.get('security_gate') if isinstance(gates, dict) else None
    security_gate_open = bool(
        (isinstance(security_gate, dict) and security_gate.get('result') != 'passed')
        or re.search(r'security[-_\s]?gate.*(offen|ausstehend|pending|nicht dokumentiert)|update security.*steht aus', resume_text, re.I)
    )
    if security_gate_open:
        warning_codes.append('SECURITY_GATE_OPEN')

    mocketeer = evaluate_mocketeer_reconciliation(root)
    if mocketeer['reconciliation_required'] or mocketeer['revision_diagnostics']:
        warning_codes.append('MOCKETEER_REVISION_UNRECONCILED')
    active_scopes = sorted({(record['mockup_id'], record['revision_id']) for record in mocketeer['revision_records']
                            if record['document'].get('active_target') is True})
    page_bindings = [reconcile_page_revision_bindings(root, rid, mockup_name=name, _evaluation=mocketeer)
                     for name, rid in active_scopes]
    if any(binding['state'] != 'BOUND' for binding in page_bindings):
        warning_codes.append('ACTIVE_REVISION_PAGE_BINDING_UNRECONCILED')

    wave_reconcil = evaluate_wave_reconciliation(root)
    if wave_reconcil['plan_process_conflicts']:
        warning_codes.append('PLAN_PROCESS_STATE_CONFLICT')

    # Pre-Implementation Checkpoint check (B2)
    dirty_output = guard._git_value(root, 'status', '--porcelain')
    working_tree_clean = None if dirty_output is None else not bool(dirty_output)
    checkpoints = facts.mission.get('checkpoint_commits') if isinstance(facts.mission, dict) and isinstance(facts.mission.get('checkpoint_commits'), list) else []
    if working_tree_clean is None:
        warning_codes.append('PRE_IMPLEMENTATION_CHECKPOINT_NOT_OBSERVABLE')
    elif not working_tree_clean:
        warning_codes.append('PRE_IMPLEMENTATION_CHECKPOINT_RECOMMENDED')

    capability_state = 'NOT_REQUESTED'
    if require_capability:
        # A registry declaration is not a current host/provider execution probe.
        capability_state = 'NOT_OBSERVABLE'
        blocker_codes.append(f'REQUIRED_CAPABILITY_NOT_OBSERVABLE:{require_capability}')

    state = 'DELIVERY_PREFLIGHT_BLOCKED' if blocker_codes else ('DELIVERY_PREFLIGHT_WARNING' if warning_codes else 'READY_FOR_DELIVERY')
    return {
        'stage': 'DELIVERY_PHASE_PREFLIGHT',
        'read_only': True,
        'state': state,
        'mission_id': facts.mission.get('mission_id') if isinstance(facts.mission, dict) else None,
        'active_wave': wave_id,
        'wave_phase': wave_block.get('phase'),
        'doctor_compatibility': facts.doctor_compatibility,
        'blocker_codes': sorted(set(blocker_codes)),
        'warning_codes': sorted(set(warning_codes)),
        'open_decisions': open_decisions,
        'security_gate': {
            'open': security_gate_open,
            'model_clean_implies_security_passed': False,
        },
        'mocketeer_reconciliation': {
            'reconciliation_required': mocketeer['reconciliation_required'],
            'unreconciled_count': len(mocketeer['unreconciled_handoff_ready']),
            'page_bindings': page_bindings,
            'revision_diagnostics': mocketeer['revision_diagnostics'],
        },
        'wave_reconciliation': wave_reconcil,
        'pre_implementation_checkpoint': {
            'working_tree_clean': working_tree_clean,
            'recorded_checkpoints': len(checkpoints),
            'checkpoint_provenance': 'MISSION_DECLARED_NOT_GIT_VERIFIED',
            'recommended_before_major_wave': working_tree_clean is not True,
        },
        'required_capability': {'id': require_capability or None, 'state': capability_state},
    }


BOARD_SMOKE_FAILING_RESULTS = ('FAIL', 'TIMEOUT', 'ERROR')
BOARD_SMOKE_EXIT_CODE = 4

CONTROL_PLANE_DIR = '.mxagile/tools/control-plane'
CONTROL_PLANE_COMPONENTS = ('guard.py', 'enforcement.py', 'child_contract.py', 'control-plane-verdict.schema.json',
                           'run_events.py', 'run-event.schema.json')
CONTROL_PLANE_MARKER = '.mxagile/tools/control-plane/enforcement.py'
CONTROL_PLANE_REQUIRED_MATCHERS = ('Write', 'Edit', 'Bash', 'Agent', 'mcp__')


def control_plane_health(root: Path) -> dict:
    """Read-only installation health of the experimental control plane; never claims live host verification."""
    findings: list[dict] = []

    def finding(code: str, detail: str) -> None:
        findings.append({'code': code, 'detail': detail})

    components = {name: (root / CONTROL_PLANE_DIR / name).is_file() for name in CONTROL_PLANE_COMPONENTS}
    registration: dict[str, Any] = {'state': 'HOST_REGISTRATION_MISSING', 'foreign_pre_tool_groups': 0,
                                    'fail_closed': False, 'matcher_complete': False, 'command_target_present': False}
    registration['python_available'] = shutil.which('python') is not None
    settings_path = root / '.claude/settings.json'
    if settings_path.is_file():
        try:
            settings = json.loads(settings_path.read_text(encoding='utf-8-sig'))
        except (OSError, ValueError):
            settings = None
            registration['state'] = 'CONFIG_UNKNOWN_OWNERSHIP'
        hooks = settings.get('hooks', {}) if isinstance(settings, dict) else None
        pre_tool = hooks.get('PreToolUse', []) if isinstance(hooks, dict) else None
        if settings is not None and not isinstance(pre_tool, list):
            registration['state'] = 'CONFIG_UNKNOWN_OWNERSHIP'
        elif isinstance(pre_tool, list):
            owned, foreign = [], 0
            for group in pre_tool:
                commands = [str(hook.get('command', '')) for hook in (group.get('hooks') or []) if isinstance(hook, dict)] if isinstance(group, dict) else []
                marked = [command for command in commands if CONTROL_PLANE_MARKER in command]
                if marked and len(marked) != len(commands):
                    registration['state'] = 'CONFIG_UNKNOWN_OWNERSHIP'
                elif marked:
                    owned.append((group, marked[0]))
                else:
                    foreign += 1
            registration['foreign_pre_tool_groups'] = foreign
            if registration['state'] != 'CONFIG_UNKNOWN_OWNERSHIP' and len(owned) > 1:
                registration['state'] = 'CONFIG_UNKNOWN_OWNERSHIP'
            elif registration['state'] != 'CONFIG_UNKNOWN_OWNERSHIP' and owned:
                group, command = owned[0]
                matcher = str(group.get('matcher', ''))
                registration.update({
                    'state': 'REGISTERED',
                    'fail_closed': command.rstrip().endswith('|| exit 2'),
                    'matcher_complete': all(token in matcher for token in CONTROL_PLANE_REQUIRED_MATCHERS),
                    'command_target_present': (root / CONTROL_PLANE_MARKER).is_file(),
                    'first_in_pre_tool_use': pre_tool[0] is group,
                })
    for name, present in components.items():
        if not present:
            finding('ADAPTER_FILE_MISSING', f'{CONTROL_PLANE_DIR}/{name}')
    if registration['state'] == 'HOST_REGISTRATION_MISSING':
        finding('HOST_REGISTRATION_MISSING', 'No MxAgile PreToolUse group in .claude/settings.json.')
    elif registration['state'] == 'CONFIG_UNKNOWN_OWNERSHIP':
        finding('CONFIG_UNKNOWN_OWNERSHIP', '.claude/settings.json hook ownership is ambiguous or unparseable.')
    else:
        if not registration['command_target_present']:
            finding('ADAPTER_FILE_MISSING', 'Registered command points to a missing adapter; the hook blocks every matched call (exit 2).')
        if not registration['fail_closed']:
            finding('REGISTRATION_NOT_FAIL_CLOSED', 'Registered command does not end with `|| exit 2`.')
        if not registration['matcher_complete']:
            finding('REGISTRATION_MATCHER_INCOMPLETE', 'Matcher does not cover Write/Edit/Bash/Agent/mcp__ tools.')
        if not registration['python_available']:
            finding('ADAPTER_RUNTIME_UNAVAILABLE', 'The registered `python` executable is not on the Doctor process PATH.')
    handoff_schema = root / '.mxagile/schemas/delegation-handoff.schema.json'
    try:
        versions = json.loads(handoff_schema.read_text(encoding='utf-8-sig'))['properties']['schema_version']['enum']
        if '1.4' not in versions:
            finding('SCHEMA_INCOMPATIBLE', 'Installed delegation handoff schema does not accept 1.4.')
    except (OSError, ValueError, KeyError, TypeError):
        finding('SCHEMA_INCOMPATIBLE', 'Installed delegation handoff schema is missing or unreadable.')
    event_schema_path = root / CONTROL_PLANE_DIR / 'run-event.schema.json'
    try:
        event_schema = json.loads(event_schema_path.read_text(encoding='utf-8-sig'))
        if jsonschema is None:
            finding('SCHEMA_VALIDATION_UNAVAILABLE', 'jsonschema is unavailable; run-event schema could not be checked.')
        else:
            jsonschema.Draft7Validator.check_schema(event_schema)
    except (OSError, ValueError, jsonschema.exceptions.SchemaError if jsonschema else ValueError):
        finding('SCHEMA_INCOMPATIBLE', 'Installed run-event schema is missing, unreadable or invalid.')

    if not any(components.values()) and registration['state'] == 'HOST_REGISTRATION_MISSING':
        installation = 'NOT_INSTALLED'
    elif findings:
        installation = 'DEGRADED'
    else:
        installation = 'HEALTHY'
    concord = (root / '.mcp.json').is_file() and 'concord' in (root / '.mcp.json').read_text(encoding='utf-8-sig', errors='replace')
    return {
        'installation_health': installation,
        'potentially_active': installation == 'HEALTHY' and registration['python_available'],
        'components': components,
        'claude_registration': registration,
        'findings': findings,
        # Installation health is no proof of enforcement; live verification only comes from a real host run.
        'live_host_verification': {
            'claude_code': 'NOT_VERIFIED',
            'concord': 'NOT_VERIFIED' if concord else 'HOST_NOT_CONFIGURED',
            'vscode_copilot': 'HOST_UNSUPPORTED',
            'reason': 'LIVE_VERIFICATION_NOT_PERFORMED',
        },
    }


def run_board_smoke(root: Path) -> dict:
    """Run the opt-in Board smoke in its own process; never raises, never changes the Doctor report."""
    import subprocess
    script = Path(__file__).resolve().parent / 'board_smoke.py'
    if not script.is_file():
        return {'check': 'board_smoke', 'result': 'UNAVAILABLE', 'reason': 'BOARD_SMOKE_SCRIPT_MISSING', 'duration_seconds': 0.0}
    try:
        completed = subprocess.run(
            [sys.executable, '-B', str(script), '--project-root', str(root), '--format', 'json'],
            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90, check=False,
        )
        result = json.loads(completed.stdout)
        if not isinstance(result, dict) or 'result' not in result:
            raise ValueError('board smoke returned no result object')
        return result
    except subprocess.TimeoutExpired:
        return {'check': 'board_smoke', 'result': 'TIMEOUT', 'reason': 'BOARD_SMOKE_PROCESS_TIMEOUT', 'duration_seconds': 90.0}
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        return {'check': 'board_smoke', 'result': 'ERROR', 'reason': f'BOARD_SMOKE_NOT_EXECUTABLE: {type(exc).__name__}', 'duration_seconds': 0.0}


def board_smoke_exit_code(doctor_code: int, smoke: dict | None, *, required: bool) -> int:
    """Doctor exit codes 0/1/2 stay unchanged; 4 is reachable only when the smoke was explicitly requested."""
    if smoke is None:
        return doctor_code
    result = smoke.get('result')
    if result in BOARD_SMOKE_FAILING_RESULTS or (required and result == 'UNAVAILABLE'):
        return BOARD_SMOKE_EXIT_CODE
    return doctor_code


def main() -> int:
    parser = argparse.ArgumentParser(description='Project compatibility Doctor and scoped contract recovery.', allow_abbrev=False)
    parser.add_argument('command', choices=['doctor', 'repair', 'contract-snapshot', 'migrate', 'resolve', 'auxiliary', 'resync-preflight', 'validate-write', 'repair-last-write', 'delivery-preflight'], nargs='?', default='doctor')
    parser.add_argument('--project-root', type=Path, default=Path.cwd())
    parser.add_argument('--format', choices=['json', 'human'], default='human')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run', action='store_true')
    mode.add_argument('--apply', action='store_true')
    mode.add_argument('--apply-safe', action='store_true')
    migration_scope = parser.add_mutually_exclusive_group()
    migration_scope.add_argument('--record-only', action='store_true', help='persist reconciliation without source repairs (migrate --apply-safe only)')
    migration_scope.add_argument('--contract-only', action='store_true', help='apply only lossless versioned contract normalizations, not assignments or ordinary source repairs (migrate --apply-safe only)')
    parser.add_argument('--mission-id', default='')
    parser.add_argument('--wave', default='')
    parser.add_argument('--phase', default='')
    parser.add_argument('--plan-hash')
    parser.add_argument('--candidate-dir', type=Path)
    parser.add_argument('--target-path')
    parser.add_argument('--candidate-file', type=Path)
    parser.add_argument('--require-capability', default='')
    for flag in ('diagnostic-id', 'migration-id', 'source-path', 'field', 'source-fingerprint', 'value', 'human-reference', 'run-id'):
        parser.add_argument('--' + flag)
    parser.add_argument('--human-confirmed', action='store_true')
    parser.add_argument('--auxiliary-request')
    parser.add_argument('--board-smoke', action='store_true',
                        help='after the Doctor run, also run the bounded Board smoke (opt-in; Doctor exit codes 0/1/2 are kept, exit 4 on a failed smoke)')
    parser.add_argument('--require-board-smoke', action='store_true',
                        help='like --board-smoke, but an UNAVAILABLE smoke (no browser) also exits 4')
    args = parser.parse_args()
    from build_project_status import build_status
    root = args.project_root.resolve()
    if args.command == 'doctor' and (args.apply or args.plan_hash or args.candidate_dir):
        parser.error('doctor is read-only; repair arguments require repair.')
    if args.command == 'repair' and (args.board_smoke or args.require_board_smoke):
        parser.error('the Board smoke is a Doctor option; it cannot be combined with repair.')
    if args.apply_safe and args.command != 'migrate':
        parser.error('--apply-safe requires migrate.')
    if (args.record_only or args.contract_only) and (args.command != 'migrate' or not args.apply_safe):
        parser.error('--record-only / --contract-only require migrate --apply-safe.')
    if args.command != 'resync-preflight' and (args.mission_id or args.wave or args.phase):
        parser.error('Mission, Wave and phase selectors require resync-preflight.')
    if args.command in ('contract-snapshot', 'migrate', 'resync-preflight') and (args.apply or args.plan_hash or args.candidate_dir or args.board_smoke or args.require_board_smoke):
        parser.error('Contract recovery does not accept arbitrary repair or smoke arguments.')
    resolution_request = {key: getattr(args, key) for key in ('diagnostic_id', 'migration_id', 'source_path', 'field', 'source_fingerprint', 'value', 'human_reference', 'human_confirmed', 'run_id')}
    if args.command not in ('resolve', 'auxiliary', 'repair-last-write') and any(resolution_request.values()):
        parser.error('Human resolution selectors require resolve.')
    if args.command != 'auxiliary' and args.auxiliary_request:
        parser.error('--auxiliary-request requires auxiliary.')
    if args.command == 'auxiliary' and (not args.auxiliary_request or not (args.dry_run or args.apply)
            or args.candidate_dir or args.apply_safe or args.board_smoke or args.require_board_smoke
            or any(resolution_request[key] for key in ('diagnostic_id', 'migration_id', 'source_path', 'field', 'source_fingerprint', 'value'))
            or (args.dry_run and (args.plan_hash or args.human_reference or args.human_confirmed or args.run_id))):
        parser.error('Auxiliary accepts only its bounded request and dry-run or confirmed apply authorization.')
    if args.command == 'resolve' and (args.apply or args.apply_safe or args.plan_hash or args.candidate_dir or args.board_smoke or args.require_board_smoke or (args.dry_run and any(resolution_request.values()))):
        parser.error('Resolve accepts only a bound resolution or a read-only --dry-run.')
    run_smoke = args.board_smoke or args.require_board_smoke
    try:
        if args.command == 'validate-write':
            if not args.target_path or not args.candidate_file:
                parser.error('validate-write requires --target-path and --candidate-file.')
            result = prevalidate_canonical_write(root, args.target_path, args.candidate_file.read_bytes())
            print(json.dumps(result, sort_keys=True, indent=2))
            return 0 if result['valid'] else 2
        if args.command == 'repair-last-write':
            candidate_raw = args.candidate_file.read_bytes() if args.candidate_file else None
            if args.apply:
                if not args.plan_hash or not args.run_id:
                    parser.error('--apply requires --plan-hash and --run-id.')
                result = apply_last_canonical_write_repair(root, plan_hash=args.plan_hash, run_id=args.run_id,
                                                           target_path=args.target_path, candidate_bytes=candidate_raw)
            else:
                result = {'read_only': True, 'plan': last_canonical_write_repair_plan(root, target_path=args.target_path, candidate_bytes=candidate_raw)}
            print(json.dumps(result, sort_keys=True, indent=2))
            return 0
        if args.command == 'delivery-preflight':
            result = delivery_preflight(root, require_capability=args.require_capability)
            print(json.dumps(result, sort_keys=True, indent=2))
            return 0 if result['state'] != 'DELIVERY_PREFLIGHT_BLOCKED' else 2
        if args.command == 'auxiliary':
            request = decode_auxiliary_request(args.auxiliary_request)
            result = {'read_only': True, 'plan': auxiliary_write_plan(root, request)} if args.dry_run else apply_auxiliary_write(
                root, request, plan_hash=args.plan_hash, human_reference=args.human_reference,
                human_confirmed=args.human_confirmed, run_id=args.run_id)
            print(json.dumps(result, sort_keys=True, indent=2))
            return 0
        if args.command == 'resolve':
            if args.dry_run:
                _, _, state = _migration_state(root)
                result = {'read_only': True, 'resolutions': human_resolution_contracts(root),
                          'pending_recovery': [item for item in (state.get('contract_migration') or {}).get('resolution_receipts', []) if item['result'] == 'PENDING']}
            else:
                result = resolve_human_resolution(root, **resolution_request)
            print(json.dumps(result, sort_keys=True, indent=2))
            return 0
        if args.command == 'contract-snapshot':
            print(json.dumps(contract_snapshot(root), sort_keys=True))
            return 0
        if args.command == 'migrate':
            result = reconcile_contract(root, apply_safe=args.apply_safe, repair_sources=not args.record_only, contract_only=args.contract_only)
            print(json.dumps(result, sort_keys=True, indent=2))
            return {'COMPATIBLE': 0, 'PARTIAL': 1, 'BLOCKED': 2}[result['doctor']['compatibility']]
        if args.command == 'resync-preflight':
            result = resync_preflight(root, args.mission_id, args.wave, args.phase)
            print(json.dumps(result, sort_keys=True, indent=2))
            return 0 if result['state'] == 'READY_FOR_RESYNC' else 2
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
    except ResolutionFailure as exc:
        print(json.dumps({'error': exc.code, 'action': 'Refresh the migration diagnosis before retrying.'}), file=sys.stderr)
        return 3
    except RepairFailure as exc:
        print(json.dumps({'error': exc.code, 'action': 'Review Doctor before any retry.'}), file=sys.stderr)
        return 3
    except (OSError, ValueError, yaml.YAMLError):
        print(json.dumps({'error': 'COMPATIBILITY_OPERATION_FAILED', 'action': 'Rerun Doctor and review the scoped repair plan.'}), file=sys.stderr)
        return 3
    smoke = run_board_smoke(root) if run_smoke else None
    summary = diagnostic_summary(report['diagnostics'])
    control_plane = control_plane_health(root)
    if args.format == 'json':
        printable = dict(report)
        printable['diagnostic_summary'] = summary
        printable['control_plane'] = control_plane
        if smoke is not None:
            printable['board_smoke'] = smoke
        print(json.dumps(printable, sort_keys=True, indent=2))
    else:
        print(f"PROJECT_COMPATIBILITY_CHECKED: {report['compatibility']} (read-only)")
        print("DIAGNOSTIC SUMMARY (counts, not additional failures):")
        for key, count in summary['by_repairability'].items():
            print(f"  {key}: {count}")
        if summary['unsupported_by_category']:
            print("  UNSUPPORTED breakdown by category:")
            for key, count in summary['unsupported_by_category'].items():
                print(f"    {key}: {count}")
        for item in report['diagnostics']:
            location = item['source_path'] or item['affected_board_area']
            if item['line'] is not None:
                location += f":{item['line']}:{item['column']}"
            print(f"{item['severity']} {item['category']} {location} [{item['repairability']}]")
        live = control_plane['live_host_verification']
        print(f"CONTROL_PLANE_INSTALLATION: {control_plane['installation_health']} "
              f"(claude registration: {control_plane['claude_registration']['state']})")
        print(f"CONTROL_PLANE_LIVE: claude_code={live['claude_code']} concord={live['concord']} ({live['reason']})")
        for item in control_plane['findings']:
            print(f"  {item['code']}: {item['detail']}")
        if smoke is not None:
            print(f"BOARD_SMOKE: {smoke.get('result')} ({smoke.get('duration_seconds')} s)"
                  + (f" - {smoke.get('reason')}" if smoke.get('reason') else ''))
            for failure in smoke.get('failures', [])[:5]:
                print(f"  FAILURE [{failure.get('stage')}] {failure.get('kind')}: {failure.get('message')}")
            for warning in smoke.get('warnings', []):
                print(f"  WARNING: {warning}")
    code = {'COMPATIBLE': 0, 'PARTIAL': 1, 'BLOCKED': 2}[report['compatibility']]
    return board_smoke_exit_code(code, smoke, required=args.require_board_smoke)


if __name__ == '__main__':
    raise SystemExit(main())