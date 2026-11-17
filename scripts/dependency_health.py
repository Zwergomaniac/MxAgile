"""Bounded dependency evidence and cached release metadata; never installs or updates tools."""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.request import Request, urlopen

import yaml
from projection_io import atomic_replace, safe_path

CACHE = '.mxagile/state/runs/dependency-update-cache.json'
TTL = timedelta(hours=24)


def version(value):
    match = re.fullmatch(r'(\d+)\.(\d+)\.(\d+)', str(value or ''))
    return tuple(map(int, match.groups())) if match else None


def read_json(path):
    if not path.is_file():
        return {}
    try:
        if path.stat().st_size > 262144:
            return {}
        value = json.loads(path.read_bytes())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def fetch_latest(dependency):
    package = dependency.get('npm_package', '')
    if not isinstance(package, str) or not re.fullmatch(r'[a-z0-9][a-z0-9._-]*', package):
        raise ValueError('No supported release metadata source')
    request = Request('https://registry.npmjs.org/' + package + '/latest',
                      headers={'Accept': 'application/json', 'User-Agent': 'MxAgile-dependency-health'})
    with urlopen(request, timeout=1.5) as response:
        value = json.loads(response.read(65536))
    result = value.get('version') if isinstance(value, dict) else None
    if not version(result):
        raise ValueError('Release version is not observable')
    return result


def latest(root, dependency, *, now=None, fetcher=None, check=True, ttl=TTL):
    now = now or datetime.now(timezone.utc)
    path = safe_path(root, CACHE)
    cache = read_json(path)
    entries = cache.get('dependencies', {})
    entries = entries if isinstance(entries, dict) else {}
    entry = entries.get(dependency['id'], {})
    entry = entry if isinstance(entry, dict) else {}
    try:
        checked = datetime.fromisoformat(entry.get('last_update_check', ''))
        fresh = checked.tzinfo is not None and timedelta(0) <= now - checked < ttl
    except (ValueError, TypeError):
        fresh = False
    known = entry.get('latest_known_version') if version(entry.get('latest_known_version')) else None
    status = 'FRESH' if fresh and entry.get('update_check_status') == 'FRESH' else ('STALE' if known else 'UNKNOWN')
    result = {'latest_known_version': known, 'last_update_check': entry.get('last_update_check'),
              'update_check_status': status, 'update_check_due': not fresh,
              'update_check_source': 'PROJECT_CACHE' if entry else 'NONE',
              'update_check_decision': 'TTL_SUPPRESSED' if fresh else 'DUE'}
    if fresh or not check:
        return result
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = path.with_suffix('.lock')
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        # An interrupted check retains its 24-hour lease; only an expired lock is retired.
        if now - datetime.fromtimestamp(lock.stat().st_mtime, timezone.utc) >= ttl:
            lock.unlink(missing_ok=True)
            return latest(root, dependency, now=now, fetcher=fetcher, check=check, ttl=ttl)
        return result
    try:
        os.close(descriptor)
        cached = latest(root, dependency, now=now, check=False, ttl=ttl)
        if not cached['update_check_due']:
            return cached
        cache = read_json(path)
        entries = cache.get('dependencies', {})
        entries = entries if isinstance(entries, dict) else {}
        result = {**cached, 'last_update_check': now.isoformat(), 'update_check_status': 'STALE' if known else 'UNKNOWN',
                  'update_check_due': False, 'update_check_source': 'PROJECT_CACHE', 'update_check_decision': 'CHECK_ATTEMPTED'}
        entries[dependency['id']] = result
        atomic_replace(path, (json.dumps({'schema_version': 1, 'dependencies': entries}, sort_keys=True) + '\n').encode())
        try:
            found = (fetcher or fetch_latest)(dependency)
            if not version(found):
                raise ValueError('Release version is not observable')
            result.update(latest_known_version=found, update_check_status='FRESH')
        except (OSError, ValueError, TimeoutError):
            pass
        entries[dependency['id']] = result
        atomic_replace(path, (json.dumps({'schema_version': 1, 'dependencies': entries}, sort_keys=True) + '\n').encode())
        return result
    finally:
        lock.unlink(missing_ok=True)


def assess(dependency, observation, update):
    required = list(observation.get('required_capabilities', []))
    discoverable = {name: observation.get('capabilities_discoverable', {}).get(name) for name in required}
    installed = observation.get('installed')
    installed_version = observation.get('installed_version')
    executable = observation.get('executable')
    constraint = dependency.get('version_constraint', '')
    minimum = version(constraint[2:]) if constraint.startswith('>=') else None
    actual = version(installed_version)
    compatible = actual >= minimum if actual is not None and minimum is not None else (
        True if not constraint and executable is True else None)
    newest = version(update.get('latest_known_version'))
    update_available = newest > actual if newest and actual and update.get('update_check_status') == 'FRESH' else None
    route_allowed = bool(required and installed is True and executable is True and compatible is not False
                         and all(value is True for value in discoverable.values()))
    contract_active = bool(required and observation.get('required_contract_active', True))
    blocking = bool(required and compatible is False and contract_active)
    hint = ''
    if required and compatible is False:
        health, severity = 'INCOMPATIBLE', 'ERROR' if blocking else 'WARNING'
        hint = 'Required version contract is incompatible. Request explicit plugin-update approval, then re-probe the current host; no automatic update.'
    elif required and not route_allowed:
        health, severity = 'CAPABILITY_DEGRADED', 'WARNING'
        hint = 'Discover the exact required tool in the current host and run one bounded health probe. Do not recommend or invoke an unloaded/non-executable alternative; use permitted fallback or report the route blocked.'
    elif installed is False and not required:
        health, severity = 'INFO', 'INFO'
    elif update_available:
        health, severity = 'UPDATE_AVAILABLE', 'WARNING'
        hint = 'An update is available; it does not block Delivery. Update only with explicit policy or User approval.'
    elif executable is True and compatible is True and update.get('update_check_status') == 'FRESH':
        health, severity = 'HEALTHY', 'INFO'
    else:
        health = 'STALE' if update.get('update_check_status') == 'STALE' else 'UNKNOWN'
        severity = 'INFO'
    return {'id': dependency['id'], 'installed': installed, 'installed_version': installed_version,
            'executable': executable, 'required_capabilities': required,
            'capabilities_discoverable': discoverable, 'compatible': compatible,
            **update, 'update_available': update_available, 'health_status': health, 'severity': severity,
            'blocking': blocking, 'required_contract_active': contract_active,
            'route_allowed': route_allowed, 'recovery_hint': hint, 'automatic_action': 'none'}


def unknown(dependency_id='context_mode'):
    report = assess({'id': dependency_id}, {'installed': None},
        {'latest_known_version': None, 'last_update_check': None, 'update_check_status': 'UNKNOWN', 'update_check_due': True})
    report['check_execution'] = 'FAILED'
    return visibility(report)


def definition(root, dependency_id):
    path = safe_path(root, '.mxagile/capabilities.yaml')
    if not path.is_file():
        base = Path(__file__).resolve().parent.parent
        path = base / ('capabilities.yaml' if base.name == '.mxagile' else '.mxagile/capabilities.yaml')
    catalog = yaml.safe_load(path.read_bytes()) or {}
    for capability in catalog.get('capabilities', []):
        for dependency in capability.get('external_dependencies', []):
            if dependency.get('id') == dependency_id:
                return dependency
    raise ValueError('Dependency is not declared in the canonical capability registry')


def visibility(report):
    """Project all health dimensions, including unknowns and warnings masked by a route failure."""
    def observed(value):
        return 'NOT_OBSERVABLE' if value is None else str(value).lower()
    update = ('UPDATE_AVAILABLE' if report.get('update_available') is True else 'UP_TO_DATE'
              if report.get('update_available') is False else 'STALE'
              if report.get('update_check_status') == 'STALE' else 'UNKNOWN')
    discovery = ','.join(name + '=' + observed(value) for name, value in report.get('capabilities_discoverable', {}).items()) or 'not_required'
    report['summary'] = (f"{report['id']}: check={report.get('check_execution', 'NOT_OBSERVABLE')}; installed={observed(report.get('installed'))}; "
        f"version={report.get('installed_version') or 'NOT_OBSERVABLE'} "
        f"({report.get('version_source', 'NOT_OBSERVABLE')}); health={report['health_status']}; "
        f"discovery={discovery}; execution={observed(report.get('executable'))}; compatible={observed(report.get('compatible'))}; "
        f"latest={report.get('latest_known_version') or 'UNKNOWN'}; update={update}; "
        f"cache={report.get('update_check_status', 'UNKNOWN')}/{report.get('update_check_decision', 'UNKNOWN')}; "
        f"last_check={report.get('last_update_check') or 'UNKNOWN'}")
    actions = [{'action': 'REPORT_DEPENDENCY_HEALTH', 'required': True, 'after': 'RECOVERY_AND_FRESHNESS'}]
    if report.get('required_capabilities') and not report.get('route_allowed'):
        actions.append({'action': 'DISCOVER_AND_PROBE_REQUIRED_OPERATIONS', 'required': True,
                        'after': 'RECOVERY_AND_FRESHNESS', 'tools': report['required_capabilities']})
    if report.get('update_check_due') and (report.get('installed') is True or report.get('required_capabilities')):
        actions.append({'action': 'CHECK_RELEASE_METADATA', 'required': True, 'after': 'RECOVERY_AND_FRESHNESS',
                        'helper': '.mxagile/tools/dependency_health.py', 'cache_ttl_hours': 24})
    report['next_actions'] = actions
    return report


def claude_plugin_declaration(root, home):
    enabled = {}
    for path in (home / '.claude/settings.json', root / '.claude/settings.json', root / '.claude/settings.local.json'):
        plugins = read_json(path).get('enabledPlugins', {})
        if isinstance(plugins, dict):
            enabled.update({key: value for key, value in plugins.items() if key.startswith('context-mode@') and isinstance(value, bool)})
    return any(enabled.values())


def context_mode(root, *, home=None, tools=None, health=None, required_tools=None, executed_tools=None,
                 check_updates=False, harness=None):
    root = Path(root).resolve()
    home = Path(home) if home is not None else Path.home()
    dependency = definition(root, 'context_mode')
    config_path = safe_path(root, '.mxagile/config.yaml')
    config = yaml.safe_load(config_path.read_bytes()) if config_path.is_file() else {}
    enabled = ((config or {}).get('context_optimization', {}).get('context_mode', {}).get('enabled') is True)
    harness = harness or os.environ.get('MXAGILE_HARNESS') or ('claude_code' if os.environ.get('CLAUDECODE') == '1' else 'unknown')
    plugin_declared = harness == 'claude_code' and claude_plugin_declaration(root, home)
    sources = (['explicit_task'] if required_tools is not None else
               (['framework_config'] if enabled else []) + (['claude_plugin_declaration'] if plugin_declared else []))
    required = list(required_tools) if required_tools is not None else (['ctx_execute'] if enabled or plugin_declared else [])
    candidates = []
    command = shutil.which('context-mode')
    if command:
        candidates.append(('PATH_PACKAGE', Path(command).parent / 'node_modules/context-mode/package.json'))
    candidates.append(('PROJECT_PACKAGE', root / 'node_modules/context-mode/package.json'))
    plugins_path = home / '.claude/plugins/installed_plugins.json'
    plugins = read_json(plugins_path).get('plugins')
    present = None if plugins_path.is_file() and not isinstance(plugins, dict) else bool(command)
    versions_by_source = {}
    def record_version(source, value):
        if version(value):
            versions_by_source.setdefault(source, set()).add(value)
    if isinstance(plugins, dict):
        for key, records in plugins.items():
            if not key.startswith('context-mode@') or not isinstance(records, list):
                continue
            for record in records:
                if not isinstance(record, dict):
                    continue
                if record.get('scope') in ('project', 'local') and Path(record.get('projectPath', '')).resolve() != root:
                    continue
                install = Path(record.get('installPath', ''))
                if not install.is_dir() or not record.get('installPath'):
                    continue
                present = True
                record_version('CLAUDE_PLUGIN_REGISTRY', record.get('version'))
                candidates.extend((('CLAUDE_PLUGIN_PACKAGE', install / 'package.json'),
                                   ('CLAUDE_PLUGIN_MANIFEST', install / '.claude-plugin/plugin.json')))
    if command:
        present = True
    for source, candidate in candidates:
        package = read_json(candidate)
        if package.get('name') == 'context-mode':
            present = True
            record_version(source, package.get('version'))
    selected = [values for source, values in versions_by_source.items()
                if not plugin_declared or source.startswith('CLAUDE_PLUGIN_')]
    versions = set().union(*selected)
    version_source = ('AMBIGUOUS_METADATA' if len(versions) > 1 else 'NOT_OBSERVABLE' if not versions else
                      'CLAUDE_PLUGIN_METADATA' if plugin_declared else 'INSTALLATION_METADATA')
    observed = None if tools is None else set(tools)
    if observed:
        present = True
    executable = None
    successful = set(executed_tools or []) & (observed or set())
    if observed is not None:
        if 'ctx_doctor' in observed and health in ('failed', 'timeout'):
            executable = False
        elif required and all(name in successful for name in required):
            executable = True
        elif not required and 'ctx_doctor' in observed and health == 'healthy':
            executable = True
    observation = {'installed': present, 'installed_version': next(iter(versions)) if len(versions) == 1 else None,
                   'executable': executable, 'required_capabilities': required,
                   'required_contract_active': bool(required) if required_tools is not None else enabled,
                   'capabilities_discoverable': {name: None if observed is None else name in observed for name in required}}
    report = assess(dependency, observation, latest(root, dependency, check=check_updates))
    report['observation_source'] = 'caller_current_session_probe' if observed is not None else 'metadata_only_tools_NOT_OBSERVABLE'
    report['execution_proof'] = {name: True if name in successful else None for name in required}
    report.update(check_execution='EXECUTED', harness=harness, requirement_sources=sources,
                  claude_plugin_declared=plugin_declared, version_source=version_source,
                  versions_by_source={source: sorted(values) for source, values in versions_by_source.items()})
    return visibility(report)


def controlled_call(root, args):
    """Accept only the installed helper's bounded metadata/cache query, never shell composition."""
    pairs = {}
    flags = set()
    index = 0
    while index < len(args):
        key = args[index]
        index += 1
        if key in ('--check-updates', '--tools-observed'):
            if key in flags:
                return None
            flags.add(key)
            continue
        if key not in ('--project-root', '--probe-status', '--tool', '--required-tool', '--executed-tool', '--harness') or index == len(args):
            return None
        value = args[index]
        index += 1
        if key in ('--tool', '--required-tool', '--executed-tool'):
            if not re.fullmatch(r'ctx_[a-z0-9_]+', value):
                return None
        elif key in pairs:
            return None
        pairs[key] = value
    selected = Path(pairs.get('--project-root', ''))
    if not selected.is_absolute() or selected.resolve() != root:
        return None
    if pairs.get('--probe-status', 'unknown') not in ('unknown', 'healthy', 'failed', 'timeout'):
        return None
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,63}', pairs.get('--harness', 'unknown')):
        return None
    if '--check-updates' in flags:
        from framework_update_recovery import restart_status
        if restart_status(root)['result'] not in ('NO_PENDING_RESTART', 'READY'):
            return None
    return 'dependency_health'


def main():
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument('--project-root', type=Path, required=True)
    parser.add_argument('--check-updates', action='store_true')
    parser.add_argument('--home-dir', type=Path)
    parser.add_argument('--harness')
    parser.add_argument('--tools-observed', action='store_true')
    parser.add_argument('--tool', action='append', default=[])
    parser.add_argument('--required-tool', action='append')
    parser.add_argument('--executed-tool', action='append', default=[])
    parser.add_argument('--probe-status', choices=('healthy', 'failed', 'timeout', 'unknown'), default='unknown')
    args = parser.parse_args()
    if not args.project_root.is_absolute():
        parser.error('Absolute project root required')
    try:
        report = context_mode(args.project_root, home=args.home_dir, tools=args.tool if args.tools_observed else None,
                              health=args.probe_status, required_tools=args.required_tool, executed_tools=args.executed_tool,
                              check_updates=args.check_updates, harness=args.harness)
        print(json.dumps(report, sort_keys=True))
        return 0
    except (OSError, ValueError, TypeError, AttributeError, yaml.YAMLError):
        report = unknown()
        print(json.dumps(report, sort_keys=True))
        return 3


if __name__ == '__main__':
    raise SystemExit(main())
