"""Bound Core self-update; the canonical installer remains the sole installer authority."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

import project_compatibility as compatibility
from projection_io import atomic_replace, safe_path, validate_sources

STATE = '.mxagile/state/runs/framework-update-recovery.json'
RESTART_STAGES = ('restart_required', 'restart_observed', 'restart_acknowledged',
                  'contracts_reloaded', 'doctor_completed', 'resync_completed')
CONTRACT_READS = ('AGENT.md', '.mxagile/policies/update-contract.md',
                  '.mxagile/policies/project-compatibility.md', '.mxagile/policies/lifecycle-resync.md',
                  '.mxagile/policies/safety-rules.md', '.mxagile/policies/tool-instruction-conflict.md')


def new_identity(prefix):
    import uuid
    return prefix + '-' + uuid.uuid4().hex


def restart_progress(value):
    required = value.get('restart_requirement') != 'NOT_REQUIRED'
    acknowledged = required and not value['restart_required']
    return value.get('restart_progress', dict(zip(RESTART_STAGES, (required, acknowledged, acknowledged, False, False, False))))


def receipt_restart(root):
    path = safe_path(root, '.mxagile/state/last-update-result.json')
    if not path.is_file():
        return None
    receipt = json.loads(path.read_bytes())
    if not isinstance(receipt, dict):
        fail('UPDATE_RECOVERY_STATE_INVALID')
    framework, transaction = receipt.get('framework', {}), receipt.get('update_transaction', {})
    if not isinstance(framework, dict) or not isinstance(transaction, dict):
        fail('UPDATE_RECOVERY_STATE_INVALID')
    if safe_path(root, '.mxagile/state/update-transaction.json').exists():
        return None  # A still-open transaction cannot supersede any prior recovery.
    if type(receipt.get('restart_required')) is not bool:
        return None
    core = json.loads(safe_path(root, '.mxagile/state/core-provenance.json').read_bytes())
    if not isinstance(core, dict):
        fail('UPDATE_RECOVERY_STATE_INVALID')
    if (framework.get('update_successful') is not True
            or framework.get('commit') != core.get('commit')
            or receipt.get('installed_at') != core.get('installed_at')):
        return None  # A historical handoff does not describe a new update to the installed Core.
    update_id = receipt.get('update_attempt_id')
    if not re.fullmatch(r'UPDATE-[0-9a-f]{32}', update_id or ''):
        fail('UPDATE_RECOVERY_STATE_INVALID')
    value = {'schema_version': 1, 'project_root': str(root), 'update_id': update_id, 'update_attempt_id': update_id,
             'commit': core['commit'], 'started_at': core['installed_at'], 'run_id': transaction.get('run_id'),
             'restart_required': receipt['restart_required'], 'state': 'INSTALLED', 'origin': 'update_receipt'}
    if not receipt['restart_required']:
        value['restart_requirement'] = 'NOT_REQUIRED'
    return value


def fail(code):
    raise compatibility.ResolutionFailure(code)


def authorized_sources(root):
    path = safe_path(root, '.mxagile/state/core-provenance.json')
    core = json.loads(path.read_bytes())
    sources = {core.get('distribution', {}).get('canonical_url')}
    if core.get('source_type') == 'git':
        sources.add(core.get('source'))
    return {source for source in sources if isinstance(source, str) and source}


def validate_source(root, source, ref):
    safe_path(Path(root.anchor), root.relative_to(root.anchor).as_posix())
    if source not in authorized_sources(root):
        fail('UPDATE_SOURCE_NOT_AUTHORIZED')
    if not (source.startswith('https://') or Path(source).is_absolute()) or source.startswith('-'):
        fail('UPDATE_SOURCE_NOT_AUTHORIZED')
    if not isinstance(ref, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_./-]{0,199}', ref) or '..' in ref or '@{' in ref:
        fail('UPDATE_REF_REQUIRED')
    if any(part in ('', '.', '..') for part in ref.split('/')):
        fail('UPDATE_REF_REQUIRED')


def git(*args):
    env = {**{key: value for key, value in os.environ.items() if not key.startswith('GIT_')}, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull,
           'GIT_OPTIONAL_LOCKS': '0', 'GIT_TERMINAL_PROMPT': '0'}
    result = subprocess.run(['git', '-c', 'protocol.ext.allow=never', '-c', 'core.hooksPath=' + os.devnull, *args],
                            env=env, capture_output=True, text=True, timeout=180)
    if result.returncode:
        fail('UPDATE_SOURCE_UNAVAILABLE')
    return result.stdout.strip()


def discover(root, source, ref):
    validate_source(root, source, ref)
    reference = ref if ref.startswith(('refs/heads/', 'refs/tags/')) else 'refs/heads/' + ref
    rows = git('ls-remote', '--', source, reference, reference + '^{}').splitlines()
    matches = {row.split()[1]: row.split()[0] for row in rows if re.fullmatch(r'[0-9a-f]{40}\s+\S+', row)}
    commit = matches.get(reference + '^{}') or matches.get(reference)
    if not commit:
        fail('UPDATE_REF_NOT_FOUND')
    return {'read_only': True, 'source': source, 'ref': ref, 'commit': commit}


@contextmanager
def distribution(root, source, ref, commit):
    discovered = discover(root, source, ref)
    if not re.fullmatch(r'[0-9a-f]{40}', commit or '') or discovered['commit'] != commit:
        fail('STALE_UPDATE_TARGET')
    with tempfile.TemporaryDirectory(prefix='mxagile-update-recovery-') as temporary:
        stage = Path(temporary) / 'distribution'
        git('clone', '--no-checkout', '--', source, str(stage))
        git('-C', str(stage), 'checkout', '--detach', commit)
        validate_sources([stage / '.mxagile', stage / 'products/MxMocketeer/skills'])
        files = git('-C', str(stage), 'ls-files', '-z').split('\x00')
        inventory = {}
        for relative in files:
            if relative:
                path = safe_path(stage, relative)
                if not path.is_file():
                    fail('UPDATE_PAYLOAD_NOT_REGULAR')
                inventory[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        for required in ('scripts/install-core.ps1', 'scripts/update-transaction.ps1', 'scripts/generate-mxagile-platform-skills.ps1',
                         'scripts/projection_io.py', 'scripts/framework_update_recovery.py', 'experiments/control-plane/enforcement.py'):
            if required not in inventory:
                fail('UPDATE_CANONICAL_PAYLOAD_REQUIRED')
        payload = compatibility.digest(json.dumps(inventory, sort_keys=True).encode())
        yield stage, payload


def projection_preflight(root, stage, commit):
    generator = stage / 'scripts/generate-mxagile-platform-skills.ps1'
    wrapper = stage.parent / 'projection-preflight.ps1'
    baseline = stage.parent / 'ownership-baseline.json'
    transaction = safe_path(root, '.mxagile/state/update-transaction.json')
    ownership = []
    if transaction.exists():
        value = json.loads(transaction.read_bytes())
        if value.get('target_core', {}).get('commit') != commit:
            fail('STALE_UPDATE_TARGET')
        ownership = value.get('projection', {}).get('ownership_baseline', [])
    baseline.write_text(json.dumps(ownership), encoding='utf-8')
    wrapper.write_text('param($Generator,$ProjectRoot,$SourceRoot,$BundledSkillRoot,$CoreCommit,$BaselinePath)\n$ErrorActionPreference="Stop"\n$baseline=@(Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json); $r = & $Generator -ProjectRoot $ProjectRoot -SourceRoot $SourceRoot -BundledSkillRoot $BundledSkillRoot -CoreCommit $CoreCommit -OwnershipBaseline $baseline -PreflightOnly -PassThru; if (-not $r.ready) { exit 3 }; $r | ConvertTo-Json -Depth 30 -Compress', encoding='utf-8')
    result = subprocess.run(['pwsh', '-NoProfile', '-File', str(wrapper), str(generator), str(root), str(stage / '.mxagile'),
                             str(stage / 'products/MxMocketeer/skills'), commit, str(baseline)], capture_output=True, text=True, timeout=180)
    if result.returncode:
        fail('UPDATE_PROJECTION_PREFLIGHT_BLOCKED')
    try:
        report = json.loads(result.stdout.strip().splitlines()[-1])
        if not report['ready'] or report.get('applied'):
            fail('UPDATE_PROJECTION_PREFLIGHT_BLOCKED')
        return report['plan_fingerprint']
    except (ValueError, KeyError, IndexError):
        fail('UPDATE_PROJECTION_PREFLIGHT_BLOCKED')


def plan(root, source, ref, commit, stage, payload):
    from build_project_status import build_status
    core = safe_path(root, '.mxagile/state/core-provenance.json').read_bytes()
    transaction = safe_path(root, '.mxagile/state/update-transaction.json')
    previous_locks = os.environ.get('GIT_OPTIONAL_LOCKS')
    os.environ['GIT_OPTIONAL_LOCKS'] = '0'
    try:
        source_fingerprint = build_status(root)['compatibility']['source_fingerprint']
    finally:
        if previous_locks is None:
            os.environ.pop('GIT_OPTIONAL_LOCKS', None)
        else:
            os.environ['GIT_OPTIONAL_LOCKS'] = previous_locks
    value = {'project_root': str(root), 'source': source, 'ref': ref, 'commit': commit, 'payload_fingerprint': payload,
             'previous_core_fingerprint': compatibility.digest(core),
             'transaction_fingerprint': compatibility.digest(transaction.read_bytes()) if transaction.exists() else None,
             'source_fingerprint': source_fingerprint,
             'projection_fingerprint': projection_preflight(root, stage, commit)}
    value['plan_hash'] = compatibility.digest(json.dumps(value, sort_keys=True).encode())
    return value


def preflight(root, source, ref, commit):
    with distribution(root, source, ref, commit) as (stage, payload):
        return {'read_only': True, 'plan': plan(root, source, ref, commit, stage, payload)}


def state(root):
    path = safe_path(root, STATE)
    try:
        value = json.loads(path.read_bytes()) if path.exists() else None
        if value is not None and (not isinstance(value, dict) or not isinstance(value.get('history', []), list)):
            fail('UPDATE_RECOVERY_STATE_INVALID')
        receipt = receipt_restart(root)
        later_install = bool(receipt and value and value.get('restart_acknowledged_at')
                             and receipt['update_attempt_id'] != (value.get('update_attempt_id') or value.get('update_id'))
                             and datetime.fromisoformat(receipt['started_at']) > datetime.fromisoformat(value['restart_acknowledged_at']))
        if receipt and (not value or value.get('commit') != receipt['commit'] or later_install or
                        (value.get('update_attempt_id') and value['update_attempt_id'] != receipt['update_attempt_id']) or
                        (value['restart_required'] and value.get('update_attempt_id') is None
                         and value['update_id'] != receipt['update_id'])):
            if value:
                history = list(value.get('history', []))
                historical = {key: item for key, item in value.items() if key != 'history'}
                history.append({'disposition': 'SUPERSEDED', 'superseded_by': receipt['update_id'],
                                'superseded_at': receipt['started_at'], 'record': historical})
                receipt['history'] = history
            value = receipt
        if value is None:
            return None
        not_required = value.get('restart_requirement') == 'NOT_REQUIRED'
        if not_required and (not receipt or receipt['restart_required'] or value['update_id'] != receipt['update_id']
                             or value['commit'] != receipt['commit'] or value.get('origin') != 'update_receipt'):
            fail('UPDATE_RECOVERY_STATE_INVALID')
        progress = value.get('restart_progress')
        if progress is not None:
            if not isinstance(progress, dict) or set(progress) != set(RESTART_STAGES) or any(type(flag) is not bool for flag in progress.values()):
                fail('UPDATE_RECOVERY_STATE_INVALID')
            if progress['restart_acknowledged'] and value.get('restart_required') is True:
                fail('RESTART_RECOVERY_LOOP')
            if not_required:
                if any(progress[stage] for stage in RESTART_STAGES[:3]):
                    fail('UPDATE_RECOVERY_STATE_INVALID')
                first = 4
            else:
                if not progress['restart_required']:
                    fail('UPDATE_RECOVERY_STATE_INVALID')
                first = 1
            if any(progress[RESTART_STAGES[i]] and not progress[RESTART_STAGES[i - 1]] for i in range(first, len(RESTART_STAGES))):
                fail('UPDATE_RECOVERY_STATE_INVALID')
        if (value['schema_version'] != 1 or value['project_root'] != str(root) or not re.fullmatch(r'UPDATE-[0-9a-f]{32}', value['update_id'])
                or not isinstance(value['restart_required'], bool) or value['state'] not in {'PENDING', 'PARTIAL', 'INSTALLED'}
                or not re.fullmatch(r'[0-9a-f]{40}', value['commit']) or datetime.fromisoformat(value['started_at']).tzinfo is None):
            fail('UPDATE_RECOVERY_STATE_INVALID')
        if not value['restart_required'] and not not_required and (
                value['state'] != 'INSTALLED' or not re.fullmatch(r'USER-[A-Za-z0-9-]{4,120}', value['restart_reference'])
                or not re.fullmatch(r'RUN-[A-Za-z0-9-]{4,80}', value['restart_run_id']) or value['restart_run_id'] == value['run_id']
                or datetime.fromisoformat(value['restart_acknowledged_at']).tzinfo is None):
            fail('UPDATE_RECOVERY_STATE_INVALID')
        return value
    except compatibility.ResolutionFailure:
        raise
    except (ValueError, KeyError, TypeError):
        fail('UPDATE_RECOVERY_STATE_INVALID')


def restart_status(root):
    value = state(root)
    if not value:
        return {'result': 'NO_PENDING_RESTART', 'read_only': True, 'restart_required': False, 'next_action': 'normal_lifecycle_resync'}
    progress = restart_progress(value)
    pending = value['restart_required']
    partial = safe_path(root, '.mxagile/state/update-transaction.json').exists()
    action = ('resume_update' if partial or value['state'] != 'INSTALLED' else 'confirm_actual_host_restart') if pending or partial else (
        'normal_lifecycle_resync' if progress['resync_completed'] else 'read_contracts_then_recover_session')
    contracts = list(CONTRACT_READS)
    contracts += [name for name in ('CLAUDE.md', 'AGENTS.md', '.github/copilot-instructions.md') if safe_path(root, name).is_file()]
    return {'result': 'RESTART_REQUIRED' if pending else ('READY' if progress['resync_completed'] else 'RECOVERY_PENDING'),
            'read_only': True, 'update_id': value['update_id'], 'restart_required': pending,
            'restart_progress': progress, 'next_action': action, 'contract_reads': contracts,
            'delivery_authorized': False}


def require_restarted(root):
    value = state(root)
    if value and value['restart_required']:
        fail('FRAMEWORK_SESSION_RESTART_REQUIRED')
    if value and value.get('restart_requirement') != 'NOT_REQUIRED' and os.environ.get('MXAGILE_RUN_ID') and os.environ['MXAGILE_RUN_ID'] == value.get('run_id'):
        fail('FRAMEWORK_OLD_SESSION_STALE')


def authorization(human_confirmed, human_reference, run_id):
    if human_confirmed is not True or not re.fullmatch(r'USER-[A-Za-z0-9-]{4,120}', human_reference or ''):
        fail('HUMAN_AUTHORIZATION_REQUIRED')
    if not re.fullmatch(r'RUN-[A-Za-z0-9-]{4,80}', run_id or ''):
        fail('RESOLUTION_RUN_REQUIRED')


def apply(root, source, ref, commit, plan_hash, human_reference, human_confirmed, run_id, resume=False):
    authorization(human_confirmed, human_reference, run_id)
    validate_source(root, source, ref)
    _, events = compatibility._auxiliary_runtime()
    safe_path(root, STATE)
    with distribution(root, source, ref, commit) as (stage, payload):
        approved = plan(root, source, ref, commit, stage, payload)
        if plan_hash != approved['plan_hash']:
            fail('STALE_UPDATE_PLAN')
        events._safe_event_dir(root, create=True)
        with events._FileLock(safe_path(root, '.mxagile/state/runs/framework-update-recovery.lock')):
            prior = state(root)
            transaction = safe_path(root, '.mxagile/state/update-transaction.json')
            if transaction.exists() != resume:
                fail('UPDATE_RESUME_REQUIRED' if transaction.exists() else 'UPDATE_RESUME_NOT_AVAILABLE')
            if resume and (not prior or any(prior[key] != val for key, val in {'source': source, 'ref': ref, 'commit': commit}.items())):
                fail('STALE_UPDATE_TARGET')
            if plan(root, source, ref, commit, stage, payload)['plan_hash'] != plan_hash:
                fail('STALE_UPDATE_PLAN')
            import uuid
            value = {**approved, 'schema_version': 1, 'update_id': prior['update_id'] if resume else 'UPDATE-' + uuid.uuid4().hex,
                     'started_at': prior['started_at'] if resume else datetime.now(timezone.utc).isoformat(),
                     'run_id': run_id, 'human_reference': human_reference, 'restart_required': True, 'state': 'PENDING'}
            atomic_replace(safe_path(root, STATE), (json.dumps(value, sort_keys=True, indent=2) + '\n').encode())
            events.append_event(root, 'update_started', run_id=run_id, actor='framework_update_recovery', host='mxagile',
                                payload={'source_commit': commit, 'recovery': 'restart', 'operation_class': 'UPDATE_RECOVERY'})
            command = ['pwsh', '-NoProfile', '-File', str(stage / 'scripts/install-core.ps1'), '-ProjectRoot', str(root),
                       '-IsUpdate:$true', '-ProvenanceCoreSource', source, '-ProvenanceCoreSourceType', 'git',
                       '-ProvenanceCoreRef', ref, '-ProvenanceCoreCommit', commit]
            if resume:
                command.append('-ResumeUpdate')
            completed = subprocess.run(command, capture_output=True, text=True, timeout=1800)
            installed = json.loads(safe_path(root, '.mxagile/state/core-provenance.json').read_bytes())
            value['state'] = 'INSTALLED' if not completed.returncode and installed.get('commit') == commit and not transaction.exists() else 'PARTIAL'
            receipt = safe_path(root, '.mxagile/state/last-update-result.json')
            if value['state'] == 'INSTALLED' and receipt.is_file():
                value['update_attempt_id'] = json.loads(receipt.read_bytes()).get('update_attempt_id')
            atomic_replace(safe_path(root, STATE), (json.dumps(value, sort_keys=True, indent=2) + '\n').encode())
            if value['state'] != 'INSTALLED':
                print(completed.stdout[-8000:] + completed.stderr[-8000:], file=sys.stderr)
                fail('UPDATE_RECOVERY_PARTIAL')
            return {'result': 'INSTALLED_RESTART_REQUIRED', 'update_id': value['update_id'], 'commit': commit,
                    'restart_required': True, 'delivery_authorized': False}


def prepare_restart(root, update_id, human_reference, human_confirmed, run_id):
    value = state(root)
    not_required = value and value.get('restart_requirement') == 'NOT_REQUIRED'
    if not not_required:
        authorization(human_confirmed, human_reference, run_id)
    core = json.loads(safe_path(root, '.mxagile/state/core-provenance.json').read_bytes())
    if (not value or value['update_id'] != update_id or value['state'] != 'INSTALLED' or value['commit'] != core.get('commit')
            or safe_path(root, '.mxagile/state/update-transaction.json').exists()):
        fail('UPDATE_RECOVERY_STATE_INVALID')
    if not not_required and (run_id == value['run_id'] or (os.environ.get('MXAGILE_RUN_ID') and os.environ['MXAGILE_RUN_ID'] == value['run_id'])):
        fail('FRAMEWORK_SESSION_RESTART_REQUIRED' if value['restart_required'] else 'FRAMEWORK_OLD_SESSION_STALE')
    verify_recovery_tools(root, core)
    return value


def verify_recovery_tools(root, core):
    tools = safe_path(root, '.mxagile/tools')
    actual = {}
    for path in tools.rglob('*.py'):
        safe_path(root, path.relative_to(root).as_posix())
        actual[path.relative_to(tools).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    writer = safe_path(root, '.mxagile/tools/Write-MxAgileEpochCheckpoint.ps1')
    actual[writer.name] = hashlib.sha256(writer.read_bytes()).hexdigest()
    if actual != core.get('recovery_tools') or compatibility.contract_snapshot(root) != core.get('artifact_contract'):
        fail('UPDATE_RECOVERY_STATE_INVALID')


def synchronize_update(root):
    if safe_path(root, '.mxagile/state/update-transaction.json').exists():
        fail('UPDATE_RECOVERY_PARTIAL')
    import run_events as events
    with events._FileLock(safe_path(root, '.mxagile/state/runs/framework-update-recovery.lock')):
        value = state(root)
        if not value:
            return restart_status(root)
        # This reconciles receipt identity only; it never attests restart or re-sync completion.
        core = json.loads(safe_path(root, '.mxagile/state/core-provenance.json').read_bytes())
        if value['commit'] != core.get('commit') or value['state'] != 'INSTALLED':
            fail('UPDATE_RECOVERY_STATE_INVALID')
        verify_recovery_tools(root, core)
        path = safe_path(root, STATE)
        persisted = json.loads(path.read_bytes()) if path.is_file() else None
        if persisted != value:
            atomic_replace(path, (json.dumps(value, sort_keys=True, indent=2) + '\n').encode())
    return restart_status(root)


def acknowledge_restart(root, update_id=None, human_reference=None, human_confirmed=False, run_id=None):
    prior = state(root)
    if not prior or (update_id and update_id != prior['update_id']):
        fail('UPDATE_RECOVERY_STATE_INVALID')
    if not prior['restart_required']:
        result = 'RESTART_NOT_REQUIRED' if prior.get('restart_requirement') == 'NOT_REQUIRED' else 'ALREADY_ACKNOWLEDGED'
        return {'result': result, 'update_id': prior['update_id'], 'delivery_authorized': False}
    update_id = update_id or prior['update_id']
    human_reference = human_reference or new_identity('USER')
    run_id = run_id or os.environ.get('MXAGILE_RUN_ID') or new_identity('RUN')
    prepare_restart(root, update_id, human_reference, human_confirmed, run_id)
    _, events = compatibility._auxiliary_runtime()
    events._safe_event_dir(root, create=True)
    with events._FileLock(safe_path(root, '.mxagile/state/runs/framework-update-recovery.lock')):
        value = prepare_restart(root, update_id, human_reference, human_confirmed, run_id)
        if not value['restart_required']:
            return {'result': 'ALREADY_ACKNOWLEDGED', 'update_id': update_id, 'delivery_authorized': False}
        receipt = receipt_restart(root)
        if receipt:
            value['update_attempt_id'] = receipt['update_attempt_id']
        progress = restart_progress(value)
        progress.update(restart_observed=True, restart_acknowledged=True)
        value.update(restart_required=False, restart_reference=human_reference, restart_run_id=run_id,
                     restart_acknowledged_at=datetime.now(timezone.utc).isoformat(), restart_progress=progress,
                     restart_observation={'source': 'human_confirmation_of_actual_host_restart', 'reference': human_reference})
        atomic_replace(safe_path(root, STATE), (json.dumps(value, sort_keys=True, indent=2) + '\n').encode())
        events.append_event(root, 'run_resumed', run_id=run_id, actor='framework_session_restart', host='mxagile',
                            payload={'recovery': 'resync', 'source_commit': value['commit'], 'update_id': update_id})
    return {'result': 'RESTART_ACKNOWLEDGED', 'update_id': update_id, 'run_id': run_id,
            'contract_reads': restart_status(root)['contract_reads'], 'delivery_authorized': False}


def recover_session(root, contracts_reloaded=False):
    value = state(root)
    if not value:
        return restart_status(root)
    synchronize_update(root)
    value = state(root)
    require_restarted(root)
    prepare_restart(root, value['update_id'], value.get('restart_reference'), True, value.get('restart_run_id'))
    if restart_progress(value)['resync_completed']:
        return restart_status(root)
    if not contracts_reloaded:
        fail('CONTRACT_RELOAD_REQUIRED')
    _, events = compatibility._auxiliary_runtime()
    events._safe_event_dir(root, create=True)
    with events._FileLock(safe_path(root, '.mxagile/state/runs/framework-update-recovery.lock')):
        value = state(root)
        require_restarted(root)
        prepare_restart(root, value['update_id'], value.get('restart_reference'), True, value.get('restart_run_id'))
        contracts = {}
        for relative in restart_status(root)['contract_reads']:
            path = safe_path(root, relative)
            if not path.is_file():
                fail('CONTRACT_RELOAD_REQUIRED')
            contracts[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        run_id = new_identity('RUN')
        progress = restart_progress(value)
        progress.update(contracts_reloaded=True, doctor_completed=False, resync_completed=False)
        value.update(restart_progress=progress, recovery_run_id=run_id,
                     contract_reload={'state': 'DECLARED', 'source': 'agent_explicit_contract_reads', 'files': contracts})
        def save():
            atomic_replace(safe_path(root, STATE), (json.dumps(value, sort_keys=True, indent=2) + '\n').encode())
        save()
        doctor_tool = safe_path(root, '.mxagile/tools/project_compatibility.py')
        try:
            completed = subprocess.run([sys.executable, '-B', str(doctor_tool), 'doctor', '--project-root', str(root), '--format', 'json'],
                                       capture_output=True, text=True, timeout=300)
        except (OSError, subprocess.TimeoutExpired):
            fail('DOCTOR_UNAVAILABLE')
        try:
            doctor = json.loads(completed.stdout)
            if (doctor['stage'] != 'PROJECT_COMPATIBILITY_CHECKED' or doctor['read_only'] is not True
                    or completed.returncode != {'COMPATIBLE': 0, 'PARTIAL': 1, 'BLOCKED': 2}.get(doctor['compatibility'])):
                fail('DOCTOR_UNAVAILABLE')
        except (ValueError, KeyError, TypeError):
            fail('DOCTOR_UNAVAILABLE')
        progress['doctor_completed'] = True
        value['recovery_doctor'] = {'compatibility': doctor['compatibility'], 'executed_at': datetime.now(timezone.utc).isoformat()}
        save()
        preflight = compatibility.resync_preflight(root)
        if doctor['compatibility'] == 'BLOCKED' or preflight['state'] != 'READY_FOR_RESYNC':
            return {'result': 'RECONCILIATION_REQUIRED', 'update_id': value['update_id'], 'restart_required': False,
                    'reason_codes': list(dict.fromkeys((['DOCTOR_BLOCKED'] if doctor['compatibility'] == 'BLOCKED' else []) + preflight['reason_codes'])),
                    'next_action': 'reconcile_remaining_blockers', 'delivery_authorized': False}
        epoch = safe_path(root, '.concord/context-epoch.yaml')
        before = hashlib.sha256(epoch.read_bytes()).hexdigest() if epoch.is_file() else None
        writer = safe_path(root, '.mxagile/tools/Write-MxAgileEpochCheckpoint.ps1')
        try:
            written = subprocess.run(['pwsh', '-NoProfile', '-File', str(writer), '-ProjectRoot', str(root), '-PreserveEvidence'],
                                     capture_output=True, text=True, timeout=300)
        except (OSError, subprocess.TimeoutExpired):
            fail('RESYNC_NOT_COMPLETED')
        after = hashlib.sha256(epoch.read_bytes()).hexdigest() if epoch.is_file() else None
        if written.returncode or after is None or after == before:
            fail('RESYNC_NOT_COMPLETED')
        progress['resync_completed'] = True
        value['recovery_resync'] = {'epoch_sha256': after, 'completed_at': datetime.now(timezone.utc).isoformat()}
        save()
        events.append_event(root, 'run_resumed', run_id=run_id, actor='framework_restart_recovery', host='mxagile',
                            payload={'update_id': value['update_id'], 'recovery': 'completed', 'source_commit': value['commit']})
        return {'result': 'READY', 'update_id': value['update_id'], 'restart_required': False,
                'restart_progress': progress, 'delivery_authorized': False, 'next_action': 'normal_lifecycle_resync'}


def controlled_call(root, args):
    if not args:
        return None
    operation, selectors = args[0], args[1:]
    confirmed = selectors.count('--human-confirmed') == 1
    reloaded = selectors.count('--contracts-reloaded') == 1
    if selectors.count('--human-confirmed') > 1 or selectors.count('--contracts-reloaded') > 1:
        return None
    selectors = [item for item in selectors if item not in {'--human-confirmed', '--contracts-reloaded'}]
    if len(selectors) % 2:
        return None
    pairs = dict(zip(selectors[::2], selectors[1::2]))
    if len(pairs) * 2 != len(selectors) or not Path(pairs.get('--project-root', '')).is_absolute() or Path(pairs['--project-root']).resolve() != root:
        return None
    names = {'--project-root', '--source', '--ref'}
    if operation == 'restart-status':
        if set(pairs) != {'--project-root'} or confirmed or reloaded:
            return None
        return 'update_discovery'
    if operation == 'synchronize-update':
        if set(pairs) != {'--project-root'} or confirmed or reloaded:
            return None
        if safe_path(root, '.mxagile/state/update-transaction.json').exists():
            fail('UPDATE_RECOVERY_PARTIAL')
        value = state(root)
        core = json.loads(safe_path(root, '.mxagile/state/core-provenance.json').read_bytes())
        if not value or value['state'] != 'INSTALLED' or value['commit'] != core.get('commit'):
            fail('UPDATE_RECOVERY_STATE_INVALID')
        verify_recovery_tools(root, core)
        return 'update_restart_acknowledgement'
    if operation == 'recover-session':
        if set(pairs) != {'--project-root'} or confirmed or not reloaded:
            return None
        value = state(root)
        if not value or value['restart_required']:
            fail('FRAMEWORK_SESSION_RESTART_REQUIRED')
        prepare_restart(root, value['update_id'], value.get('restart_reference'), True, value.get('restart_run_id'))
        return 'update_restart_acknowledgement'
    if reloaded:
        return None
    if operation == 'check':
        if set(pairs) != names or confirmed:
            return None
        validate_source(root, pairs['--source'], pairs['--ref'])
        return 'update_discovery'
    if operation == 'preflight':
        if set(pairs) != names | {'--commit'} or confirmed or not re.fullmatch(r'[0-9a-f]{40}', pairs['--commit']):
            return None
        validate_source(root, pairs['--source'], pairs['--ref'])
        return 'update_preflight'
    if operation == 'acknowledge-restart':
        if not set(pairs) <= {'--project-root', '--update-id', '--human-reference', '--run-id'}:
            return None
        value = state(root)
        if not value or (pairs.get('--update-id') and pairs['--update-id'] != value['update_id']):
            fail('UPDATE_RECOVERY_STATE_INVALID')
        if value['restart_required']:
            prepare_restart(root, pairs.get('--update-id') or value['update_id'],
                            pairs.get('--human-reference') or new_identity('USER'), confirmed,
                            pairs.get('--run-id') or new_identity('RUN'))
        return 'update_restart_acknowledgement'
    if operation not in {'apply', 'resume'} or set(pairs) != names | {'--commit', '--plan-hash', '--human-reference', '--run-id'} or not confirmed:
        return None
    authorization(True, pairs['--human-reference'], pairs['--run-id'])
    preview = preflight(root, pairs['--source'], pairs['--ref'], pairs['--commit'])['plan']
    if preview['plan_hash'] != pairs['--plan-hash']:
        fail('STALE_UPDATE_PLAN')
    transaction = safe_path(root, '.mxagile/state/update-transaction.json')
    if transaction.exists() != (operation == 'resume'):
        fail('UPDATE_RESUME_REQUIRED' if transaction.exists() else 'UPDATE_RESUME_NOT_AVAILABLE')
    if operation == 'resume':
        prior = state(root)
        if not prior or any(prior.get(key) != val for key, val in {'source': pairs['--source'], 'ref': pairs['--ref'], 'commit': pairs['--commit']}.items()):
            fail('STALE_UPDATE_TARGET')
    return 'update_recovery'


def main():
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument('command', choices=['check', 'preflight', 'apply', 'resume', 'restart-status', 'acknowledge-restart', 'recover-session', 'synchronize-update'])
    parser.add_argument('--project-root', type=Path, required=True)
    for flag in ('source', 'ref', 'commit', 'plan-hash', 'human-reference', 'run-id', 'update-id'):
        parser.add_argument('--' + flag)
    parser.add_argument('--human-confirmed', action='store_true')
    parser.add_argument('--contracts-reloaded', action='store_true')
    args = parser.parse_args()
    root = args.project_root.resolve()
    if not args.project_root.is_absolute():
        parser.error('Absolute project root required.')
    if args.command in ('restart-status', 'acknowledge-restart', 'recover-session', 'synchronize-update'):
        if any((args.source, args.ref, args.commit, args.plan_hash)):
            parser.error('Session recovery cannot update a source.')
        if args.command != 'acknowledge-restart' and any((args.update_id, args.human_reference, args.run_id, args.human_confirmed)):
            parser.error('Only restart acknowledgement accepts identity or confirmation selectors.')
    elif not args.source or not args.ref or args.update_id:
        parser.error('An exact existing source and explicit ref are required.')
    if args.contracts_reloaded and args.command != 'recover-session':
        parser.error('Contract read confirmation requires recover-session.')
    if args.command in ('check', 'preflight') and any((args.plan_hash, args.human_reference, args.run_id, args.human_confirmed)):
        parser.error('Discovery is read-only.')
    try:
        if args.command == 'check':
            if args.commit:
                parser.error('check resolves the explicit ref; commit selectors require preflight.')
            result = discover(root, args.source, args.ref)
        elif args.command == 'preflight':
            result = preflight(root, args.source, args.ref, args.commit)
        elif args.command == 'restart-status':
            result = restart_status(root)
        elif args.command == 'synchronize-update':
            result = synchronize_update(root)
        elif args.command == 'acknowledge-restart':
            result = acknowledge_restart(root, args.update_id, args.human_reference, args.human_confirmed, args.run_id)
        elif args.command == 'recover-session':
            result = recover_session(root, args.contracts_reloaded)
        else:
            result = apply(root, args.source, args.ref, args.commit, args.plan_hash, args.human_reference, args.human_confirmed, args.run_id, args.command == 'resume')
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except compatibility.ResolutionFailure as exc:
        print(json.dumps({'result': 'BLOCKED', 'code': exc.code}))
        return 3


if __name__ == '__main__':
    raise SystemExit(main())
