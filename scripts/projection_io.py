"""Ownership, preflight and staged I/O for the canonical platform generator."""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tempfile
import datetime

import yaml

HEADER = b'# GENERATED - DO NOT EDIT - Source: .mxagile/'
HOSTS = {'.claude', '.github', '.agents', '.grok', '.opencode', '.hermes'}
MANIFEST = '.mxagile/state/projections-manifest.json'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(root, relative):
    parts = PurePosixPath(relative).parts
    if not parts or PurePosixPath(relative).is_absolute() or any(p in ('.', '..') or '\\' in p or ':' in p for p in parts):
        raise ValueError('Invalid projection-relative path')
    current = root
    for index, part in enumerate(parts):
        current = current / part
        if current.exists() or current.is_symlink():
            info = current.lstat()
            if index < len(parts) - 1 and not stat.S_ISDIR(info.st_mode):
                raise ValueError('Projection ancestor is not a directory')
            if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 1024):
                raise ValueError('Projection path contains a reparse point')
    return current


def validate_sources(roots):
    for value in roots:
        root = Path(value).absolute()
        safe_path(Path(root.anchor), root.relative_to(root.anchor).as_posix())
        if not root.is_dir():
            raise ValueError(f'Missing canonical source directory: {root}')
        inventory(root, root)
        from jsonschema import Draft7Validator
        for path in root.rglob('*.schema.json'):
            Draft7Validator.check_schema(json.loads(path.read_text(encoding='utf-8-sig')))


def inventory(root, directory):
    result = {}
    for child in directory.iterdir():
        relative = child.relative_to(root).as_posix()
        safe_path(root, relative)
        if child.is_dir():
            result[relative] = None
            result.update(inventory(root, child))
        elif child.is_file():
            result[relative] = digest(child.read_bytes())
        else:
            raise ValueError('Unsupported projection target entry')
    return result


def read_manifest(root):
    path = safe_path(root, MANIFEST)
    if not path.exists():
        return {}
    value = json.loads(path.read_text(encoding='utf-8-sig'))
    if not isinstance(value, dict) or value.get('schema_version') != '1' or value.get('generator') != 'generate-mxagile-platform-skills.ps1' or value.get('generator_owned_by') != 'distribution':
        raise ValueError('Invalid projection manifest ownership')
    outputs = value.get('outputs', [])
    if not isinstance(outputs, list):
        raise ValueError('Invalid projection manifest outputs')
    seen = set()
    for entry in outputs:
        if not isinstance(entry, dict) or not isinstance(entry.get('target'), str) or not re.fullmatch('[a-f0-9]{64}', entry.get('sha256', '')):
            raise ValueError('Invalid projection manifest file binding')
        safe_path(root, entry['target'])
        if entry['target'] in seen:
            raise ValueError('Duplicate projection manifest target')
        seen.add(entry['target'])
    return value


def legacy_bundle(root, owner, files):
    manifest = root / owner / 'bundle-manifest.json'
    if not manifest.is_file():
        return False
    value = json.loads(manifest.read_text(encoding='utf-8-sig'))
    if value.get('managed_by') not in ('skill-bundle-v1', 'mxagile-skill-bundle-v1') or value.get('skill_name') != 'mocketeer-design-contract':
        return False
    expected = {manifest.relative_to(root).as_posix()}
    for entry in value.get('files', []):
        relative = f"{owner}/{entry['path']}"
        path = safe_path(root, relative)
        if not path.is_file() or digest(path.read_bytes()) != entry['sha256']:
            return False
        expected.add(relative)
    directories = set()
    for relative in expected:
        parent = PurePosixPath(relative).parent
        while parent.as_posix() != owner:
            directories.add(parent.as_posix())
            parent = parent.parent
    return {p for p, h in files.items() if h is not None} == expected and all(p in directories for p, h in files.items() if h is None)


def owned_markdown(data, skill_name=None):
    if skill_name is None and data.startswith(HEADER + b'\n'):
        return True
    try:
        text = data.decode('utf-8-sig').replace('\r\n', '\n')
        match = re.match(r'\A---\n(.*?)\n---\n', text, re.S)
        if not match or not text[match.end():].lstrip('\n').startswith(HEADER.decode() + '\n'):
            return False
        fields = yaml.safe_load(match[1])
        return isinstance(fields, dict) and (skill_name is None or fields.get('name') == skill_name)
    except (UnicodeError, yaml.YAMLError):
        return False


def classify(root, owner, outputs, previous):
    try:
        path = safe_path(root, owner)
        expected = {o['target']: digest(o['_bytes']) for o in outputs}
        desired_sources = {o['target']: o['source'] for o in outputs}
        if any(entry.get('source') and entry['target'] in desired_sources and entry['source'] != desired_sources[entry['target']] for entry in previous.get('outputs', [])):
            return 'TARGET_INVALID', {}, 'Manifest source binding contradicts the target owner'
        if not path.exists():
            return 'TARGET_MISSING', {}, None
        directory = any(o['target'] != owner for o in outputs)
        if not directory:
            if not path.is_file():
                return 'TARGET_INVALID', {}, 'Expected generated file'
            data = path.read_bytes()
            if not owned_markdown(data):
                return 'TARGET_FOREIGN', {}, 'Generated ownership marker missing'
            current = {owner: digest(data)}
            return ('TARGET_OWNED_CURRENT' if current == expected else 'TARGET_OWNED_STALE'), current, None
        if not path.is_dir():
            return 'TARGET_INVALID', {}, 'Expected skill directory'
        entries = inventory(root, path)
        if not entries:
            return 'TARGET_EMPTY_UNOWNED', entries, None
        skill = path / 'SKILL.md'
        # Portable neutral skills share a directory; every file still needs its own marker.
        portable = all(o['target'].endswith('.md') and not o['target'].endswith('/SKILL.md') for o in outputs)
        legacy = False
        if not portable:
            if not skill.is_file():
                return 'TARGET_NONEMPTY_UNKNOWN', entries, 'Nonempty skill target has no owned SKILL.md'
            if not owned_markdown(skill.read_bytes(), PurePosixPath(owner).name) or any(p.endswith('/bundle-manifest.json') for p in entries):
                legacy = legacy_bundle(root, owner, entries)
                proofs = {o['target']: o['sha256'] for o in previous.get('outputs', []) if o.get('legacy_generated') and o['target'].startswith(owner + '/')}
                proof_dirs = set()
                for relative in proofs:
                    parent = PurePosixPath(relative).parent
                    while parent.as_posix() != owner:
                        proof_dirs.add(parent.as_posix())
                        parent = parent.parent
                if proofs:
                    legacy = all((relative in proof_dirs if value is None else value in (proofs.get(relative), expected.get(relative))) for relative, value in entries.items())
                if not legacy and not owned_markdown(skill.read_bytes(), PurePosixPath(owner).name):
                    return 'TARGET_FOREIGN', entries, 'Foreign SKILL.md'
        prior = {o['target']: o['sha256'] for o in previous.get('outputs', [])}
        allowed_dirs = set()
        for target in expected:
            parent = PurePosixPath(target).parent
            while parent.as_posix() != owner:
                allowed_dirs.add(parent.as_posix())
                parent = parent.parent
        for target, current in entries.items():
            if legacy:
                continue
            if current is None:
                if target not in allowed_dirs:
                    return 'TARGET_NONEMPTY_UNKNOWN', entries, f'Unknown directory: {target}'
                continue
            if legacy and target.endswith('/bundle-manifest.json'):
                continue
            if target not in expected:
                return 'TARGET_FOREIGN', entries, f'Unknown file: {target}'
            if target.endswith('.md') and (portable or target.endswith('/SKILL.md')):
                if not legacy and not owned_markdown((root / target).read_bytes(), None if portable else PurePosixPath(owner).name):
                    return 'TARGET_FOREIGN', entries, f'Foreign generated Markdown: {target}'
                continue
            source = next(o['source'] for o in outputs if o['target'] == target)
            installed_source = safe_path(root, source)
            installed_hash = digest(installed_source.read_bytes()) if installed_source.is_file() else None
            if current not in (expected[target], prior.get(target), installed_hash) and not legacy:
                return 'TARGET_FOREIGN', entries, f'Unowned asset content: {target}'
        actual = {p: h for p, h in entries.items() if h is not None and not p.endswith('/bundle-manifest.json')}
        return ('TARGET_STALE_GENERATED' if legacy else ('TARGET_OWNED_CURRENT' if actual == expected else 'TARGET_OWNED_STALE')), entries, None
    except (OSError, ValueError, KeyError, TypeError) as exc:
        return 'TARGET_INVALID', {}, f'{type(exc).__name__}: {exc}'


def atomic_replace(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    fd, temp = tempfile.mkstemp(prefix='.projection-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def execute(root, plan, *, apply=False):
    root = Path(root).resolve()
    conflicts = []
    groups = {}
    outputs = []
    try:
        previous = read_manifest(root)
        original_manifest = dict(previous)
        manifest_path = safe_path(root, MANIFEST)
        original_manifest_bytes = manifest_path.read_bytes() if manifest_path.exists() else None
        baseline = plan.get('ownership_baseline', [])
        if baseline:
            previous = dict(previous)
            combined = {entry['target']: entry for entry in previous.get('outputs', [])}
            for entry in baseline:
                safe_path(root, entry['target'])
                if not re.fullmatch('[a-f0-9]{64}', entry.get('sha256', '')):
                    raise ValueError('Invalid preflight ownership hash')
                combined[entry['target']] = {**combined.get(entry['target'], {}), **entry}
            previous['outputs'] = list(combined.values())
    except (OSError, ValueError, TypeError) as exc:
        previous = {}
        conflicts.append({'target': MANIFEST, 'state': 'TARGET_INVALID', 'reason': str(exc)})
    for value in plan['outputs']:
        output = dict(value)
        try:
            target = output['target']
            owner = output['owner_root']
            if PurePosixPath(target).parts[0] not in HOSTS or not (target == owner or target.startswith(owner + '/')):
                raise ValueError('Target is outside its generated host/owner scope')
            safe_path(root, target)
            if any(o['target'] == target for o in outputs):
                raise ValueError('Duplicate generated target')
            output['_bytes'] = base64.b64decode(output['data'], validate=True)
            if target.endswith('/SKILL.md'):
                text = output['_bytes'].decode('utf-8')
                match = re.match(r'\A---\r?\n(.*?)\r?\n---\r?\n', text, re.S)
                fields = yaml.safe_load(match[1]) if match else None
                if not isinstance(fields, dict) or fields.get('name') != PurePosixPath(owner).name or not isinstance(fields.get('description'), str):
                    raise ValueError('Invalid generated skill frontmatter')
            outputs.append(output)
            groups.setdefault(owner, []).append(output)
        except (OSError, ValueError, KeyError, TypeError, yaml.YAMLError) as exc:
            conflicts.append({'target': value.get('target'), 'state': 'TARGET_INVALID', 'reason': str(exc)})
    targets = []
    snapshots = {}
    for owner, values in groups.items():
        state, snapshot, reason = classify(root, owner, values, previous)
        targets.append({'target': owner, 'state': state})
        snapshots[owner] = snapshot
        if reason:
            conflicts.append({'target': owner, 'state': state, 'reason': reason})
    legacy_owners = {target['target'] for target in targets if target['state'] == 'TARGET_STALE_GENERATED'}
    ownership = [{'target': target, 'sha256': value, 'legacy_generated': owner in legacy_owners} for owner, snapshot in snapshots.items() for target, value in snapshot.items() if value is not None]
    expected_outputs = [{'target': output['target'], 'source': output['source'], 'owner_root': output['owner_root'], 'sha256': digest(output['_bytes'])} for output in outputs]
    plan_fingerprint = digest(json.dumps(sorted(expected_outputs, key=lambda entry: entry['target']), sort_keys=True).encode())
    report = {'stage': 'PROJECTION_PREFLIGHT', 'ready': not conflicts, 'targets': targets, 'conflicts': conflicts, 'output_count': len(outputs), 'applied': False, 'ownership_baseline': ownership if not conflicts else [], 'plan_fingerprint': plan_fingerprint}
    if plan.get('expected_plan_fingerprint') and plan['expected_plan_fingerprint'] != plan_fingerprint:
        report['ready'] = False
        report['conflicts'].append({'target': 'canonical sources', 'state': 'TARGET_INVALID', 'reason': 'Rendered outputs changed after installer preflight'})
    if not report['ready'] or not apply:
        return report
    # Stage bytes captured by the renderer, then recheck the entire target inventory before applying.
    parent = safe_path(root, '.mxagile/state')
    parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.projection-stage-', dir=parent))
    try:
        for index, output in enumerate(outputs):
            (stage / str(index)).write_bytes(output['_bytes'])
        for owner, values in groups.items():
            _, current, reason = classify(root, owner, values, previous)
            if reason or current != snapshots[owner]:
                raise ValueError(f'Projection target changed after preflight: {owner}')
        for target in targets:
            if target['state'] != 'TARGET_STALE_GENERATED':
                continue
            owner = target['target']
            previous = dict(previous)
            previous['outputs'] = [*previous.get('outputs', []), *(entry for entry in ownership if entry['legacy_generated'])]
            wanted = {output['target'] for output in groups[owner]}
            skill_output = next(output for output in groups[owner] if output['target'].endswith('/SKILL.md'))
            skill_path = safe_path(root, skill_output['target'])
            if digest(skill_path.read_bytes()) != snapshots[owner][skill_output['target']]:
                raise ValueError('Legacy SKILL.md changed after validation')
            atomic_replace(skill_path, skill_output['_bytes'])
            for relative, before in snapshots[owner].items():
                if before is not None and relative not in wanted:
                    path = safe_path(root, relative)
                    if digest(path.read_bytes()) != before:
                        raise ValueError('Legacy bundle changed after validation')
                    path.unlink()
            for relative, value in sorted(snapshots[owner].items(), reverse=True):
                if value is None and relative not in {str(PurePosixPath(p).parent) for p in wanted}:
                    path = safe_path(root, relative)
                    if not any(path.iterdir()):
                        path.rmdir()
        for index, output in enumerate(outputs):
            owner = output['owner_root']
            _, current, reason = classify(root, owner, groups[owner], previous)
            if reason:
                raise ValueError(f'Projection target changed during apply: {owner}: {reason}')
            path = safe_path(root, output['target'])
            original = snapshots[owner].get(output['target'])
            actual = digest(path.read_bytes()) if path.is_file() else None
            wanted = digest(output['_bytes'])
            if actual not in (original, wanted):
                raise ValueError(f'Concurrent projection edit: {output["target"]}')
            if actual != wanted:
                atomic_replace(path, (stage / str(index)).read_bytes())
        bindings = []
        for output in outputs:
            path = safe_path(root, output['target'])
            if not path.is_file() or path.read_bytes() != output['_bytes']:
                raise ValueError(f'Projection validation failed: {output["target"]}')
            bindings.append({'target': output['target'], 'source': output['source'], 'host_family': PurePosixPath(output['target']).parts[0], 'sha256': digest(output['_bytes'])})
        for owner, values in groups.items():
            _, _, reason = classify(root, owner, values, previous)
            if reason:
                raise ValueError(f'Projection inventory invalid after apply: {owner}')
        if plan.get('core_commit') or plan.get('core_version'):
            manifest = {'schema_version': '1', 'projection_version': '2', 'generated_from_core_commit': plan.get('core_commit') or None, 'generated_from_core_version': plan.get('core_version') or None, 'generator': 'generate-mxagile-platform-skills.ps1', 'generator_owned_by': 'distribution', 'outputs': sorted(bindings, key=lambda o: o['target'])}
            manifest_path = safe_path(root, MANIFEST)
            current_manifest_bytes = manifest_path.read_bytes() if manifest_path.exists() else None
            if current_manifest_bytes != original_manifest_bytes:
                raise ValueError('Projection manifest changed during apply')
            comparable = {k: v for k, v in original_manifest.items() if k not in ('generated_at', 'regeneration_note')}
            if comparable != manifest:
                manifest['generated_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                atomic_replace(safe_path(root, MANIFEST), (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode())
        report.update(stage='PROJECTIONS_VALIDATED', applied=True)
        return report
    finally:
        shutil.rmtree(stage)


def main():
    try:
        request = json.load(sys.stdin)
        report = execute(request['project_root'], request, apply=request.get('apply', False))
        print(json.dumps(report, sort_keys=True))
        return 0 if report['ready'] else 2
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({'stage': 'PROJECTION_FAILURE', 'ready': False, 'error': type(exc).__name__, 'reason': str(exc)}))
        return 3


if __name__ == '__main__':
    raise SystemExit(main())
