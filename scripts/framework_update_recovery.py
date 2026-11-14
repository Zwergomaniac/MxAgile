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
    if not path.exists():
        return None
    try:
        value = json.loads(path.read_bytes())
        if (value['schema_version'] != 1 or value['project_root'] != str(root) or not re.fullmatch(r'UPDATE-[0-9a-f]{32}', value['update_id'])
                or not isinstance(value['restart_required'], bool) or value['state'] not in {'PENDING', 'PARTIAL', 'INSTALLED'}
                or not re.fullmatch(r'[0-9a-f]{40}', value['commit']) or datetime.fromisoformat(value['started_at']).tzinfo is None):
            fail('UPDATE_RECOVERY_STATE_INVALID')
        if not value['restart_required'] and (
                value['state'] != 'INSTALLED' or not re.fullmatch(r'USER-[A-Za-z0-9-]{4,120}', value['restart_reference'])
                or not re.fullmatch(r'RUN-[A-Za-z0-9-]{4,80}', value['restart_run_id']) or value['restart_run_id'] == value['run_id']
                or datetime.fromisoformat(value['restart_acknowledged_at']).tzinfo is None):
            fail('UPDATE_RECOVERY_STATE_INVALID')
        return value
    except (ValueError, KeyError, TypeError):
        fail('UPDATE_RECOVERY_STATE_INVALID')


def require_restarted(root):
    value = state(root)
    if value and value['restart_required']:
        fail('FRAMEWORK_SESSION_RESTART_REQUIRED')


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
            atomic_replace(safe_path(root, STATE), (json.dumps(value, sort_keys=True, indent=2) + '\n').encode())
            if value['state'] != 'INSTALLED':
                print(completed.stdout[-8000:] + completed.stderr[-8000:], file=sys.stderr)
                fail('UPDATE_RECOVERY_PARTIAL')
            return {'result': 'INSTALLED_RESTART_REQUIRED', 'update_id': value['update_id'], 'commit': commit,
                    'restart_required': True, 'delivery_authorized': False}


def prepare_restart(root, update_id, human_reference, human_confirmed, run_id):
    authorization(human_confirmed, human_reference, run_id)
    value = state(root)
    core = json.loads(safe_path(root, '.mxagile/state/core-provenance.json').read_bytes())
    if (not value or value['update_id'] != update_id or value['state'] != 'INSTALLED' or value['commit'] != core.get('commit')
            or run_id == value['run_id'] or safe_path(root, '.mxagile/state/update-transaction.json').exists()):
        fail('FRAMEWORK_SESSION_RESTART_REQUIRED')
    tools = safe_path(root, '.mxagile/tools')
    actual = {}
    for path in tools.rglob('*.py'):
        safe_path(root, path.relative_to(root).as_posix())
        actual[path.relative_to(tools).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    writer = safe_path(root, '.mxagile/tools/Write-MxAgileEpochCheckpoint.ps1')
    actual[writer.name] = hashlib.sha256(writer.read_bytes()).hexdigest()
    if actual != core.get('recovery_tools') or compatibility.contract_snapshot(root) != core.get('artifact_contract'):
        fail('UPDATE_RECOVERY_STATE_INVALID')
    return value


def acknowledge_restart(root, update_id, human_reference, human_confirmed, run_id):
    prepare_restart(root, update_id, human_reference, human_confirmed, run_id)
    _, events = compatibility._auxiliary_runtime()
    events._safe_event_dir(root, create=True)
    with events._FileLock(safe_path(root, '.mxagile/state/runs/framework-update-recovery.lock')):
        value = prepare_restart(root, update_id, human_reference, human_confirmed, run_id)
        value.update(restart_required=False, restart_reference=human_reference, restart_run_id=run_id,
                     restart_acknowledged_at=datetime.now(timezone.utc).isoformat())
        atomic_replace(safe_path(root, STATE), (json.dumps(value, sort_keys=True, indent=2) + '\n').encode())
        events.append_event(root, 'run_resumed', run_id=run_id, actor='framework_session_restart', host='mxagile',
                            payload={'recovery': 'resync', 'source_commit': value['commit']})
    return {'result': 'RESTART_ACKNOWLEDGED', 'delivery_authorized': False}


def controlled_call(root, args):
    if not args:
        return None
    operation, selectors = args[0], args[1:]
    confirmed = selectors.count('--human-confirmed') == 1
    selectors = [item for item in selectors if item != '--human-confirmed']
    if len(selectors) % 2:
        return None
    pairs = dict(zip(selectors[::2], selectors[1::2]))
    if len(pairs) * 2 != len(selectors) or not Path(pairs.get('--project-root', '')).is_absolute() or Path(pairs['--project-root']).resolve() != root:
        return None
    names = {'--project-root', '--source', '--ref'}
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
        if set(pairs) != {'--project-root', '--update-id', '--human-reference', '--run-id'} or not confirmed:
            return None
        prepare_restart(root, pairs['--update-id'], pairs['--human-reference'], True, pairs['--run-id'])
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
    parser.add_argument('command', choices=['check', 'preflight', 'apply', 'resume', 'acknowledge-restart'])
    parser.add_argument('--project-root', type=Path, required=True)
    for flag in ('source', 'ref', 'commit', 'plan-hash', 'human-reference', 'run-id', 'update-id'):
        parser.add_argument('--' + flag)
    parser.add_argument('--human-confirmed', action='store_true')
    args = parser.parse_args()
    root = args.project_root.resolve()
    if not args.project_root.is_absolute():
        parser.error('Absolute project root required.')
    if args.command == 'acknowledge-restart':
        if any((args.source, args.ref, args.commit, args.plan_hash)):
            parser.error('Restart acknowledgement cannot update a source.')
    elif not args.source or not args.ref or args.update_id:
        parser.error('An exact existing source and explicit ref are required.')
    if args.command in ('check', 'preflight') and any((args.plan_hash, args.human_reference, args.run_id, args.human_confirmed)):
        parser.error('Discovery is read-only.')
    try:
        if args.command == 'check':
            if args.commit:
                parser.error('check resolves the explicit ref; commit selectors require preflight.')
            result = discover(root, args.source, args.ref)
        elif args.command == 'preflight':
            result = preflight(root, args.source, args.ref, args.commit)
        elif args.command == 'acknowledge-restart':
            result = acknowledge_restart(root, args.update_id, args.human_reference, args.human_confirmed, args.run_id)
        else:
            result = apply(root, args.source, args.ref, args.commit, args.plan_hash, args.human_reference, args.human_confirmed, args.run_id, args.command == 'resume')
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except compatibility.ResolutionFailure as exc:
        print(json.dumps({'result': 'BLOCKED', 'code': exc.code}))
        return 3


if __name__ == '__main__':
    raise SystemExit(main())
