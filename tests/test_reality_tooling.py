"""Bounded synthetic observations; no live host, Mendix or browser claims."""
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import sys
from datetime import datetime, timedelta, timezone

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import dependency_health
RESOLVER = ROOT / 'scripts' / 'Get-MxAgileCapabilities.ps1'
WRITER = ROOT / 'scripts' / 'Write-MxAgileEpochCheckpoint.ps1'


class DependencyHealthTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix='mxagile-dependency-health-')
        self.root = Path(self.fixture.name)
        self.now = datetime(2026, 11, 17, tzinfo=timezone.utc)
        self.dependency = {'id': 'context_mode', 'npm_package': 'context-mode', 'version_constraint': '>=1.0.33'}
        self.observation = {'installed': True, 'installed_version': '2.2.0', 'executable': True,
                            'required_capabilities': ['ctx_execute'],
                            'capabilities_discoverable': {'ctx_execute': True}}
        self.update = {'latest_known_version': '2.2.0', 'last_update_check': self.now.isoformat(),
                       'update_check_status': 'FRESH', 'update_check_due': False}

    def tearDown(self):
        self.fixture.cleanup()

    def test_current_and_executable_is_healthy(self):
        result = dependency_health.assess(self.dependency, self.observation, self.update)
        self.assertEqual(result['health_status'], 'HEALTHY')
        self.assertTrue(result['route_allowed'])
        self.assertFalse(result['blocking'])

    def test_available_update_is_warning_not_delivery_blocker(self):
        observation = {**self.observation, 'installed_version': '1.0.169'}
        result = dependency_health.assess(self.dependency, observation, self.update)
        self.assertEqual(result['health_status'], 'UPDATE_AVAILABLE')
        self.assertEqual(result['severity'], 'WARNING')
        self.assertTrue(result['compatible'])
        self.assertTrue(result['route_allowed'])
        self.assertFalse(result['blocking'])
        self.assertEqual(result['automatic_action'], 'none')

    def test_required_tool_missing_or_not_executable_cannot_be_a_routing_recovery(self):
        for change in ({'capabilities_discoverable': {'ctx_execute': False}}, {'executable': False},
                       {'capabilities_discoverable': {'ctx_execute': None}}, {'executable': None}):
            with self.subTest(change=change):
                result = dependency_health.assess(self.dependency, {**self.observation, **change}, self.update)
                self.assertEqual(result['health_status'], 'CAPABILITY_DEGRADED')
                self.assertFalse(result['route_allowed'])
                self.assertFalse(result['blocking'])
                self.assertTrue(result['recovery_hint'])

    def test_known_incompatible_required_contract_is_blocked_not_merely_outdated(self):
        result = dependency_health.assess(self.dependency,
            {**self.observation, 'installed_version': '1.0.32'}, self.update)
        self.assertEqual(result['health_status'], 'INCOMPATIBLE')
        self.assertTrue(result['blocking'])
        self.assertFalse(result['route_allowed'])
        self.assertEqual(result['automatic_action'], 'none')
        optional = dependency_health.assess(self.dependency,
            {**self.observation, 'installed': False, 'required_capabilities': []}, self.update)
        self.assertEqual(optional['health_status'], 'INFO')
        self.assertFalse(optional['blocking'])

    def test_update_ttl_suppresses_repeated_external_checks_and_allows_expired_check(self):
        fetch = mock.Mock(return_value='2.2.0')
        first = dependency_health.latest(self.root, self.dependency, now=self.now, fetcher=fetch)
        cached = dependency_health.latest(self.root, self.dependency, now=self.now + timedelta(hours=23), fetcher=fetch)
        self.assertEqual(first['latest_known_version'], cached['latest_known_version'])
        self.assertEqual(fetch.call_count, 1)
        dependency_health.latest(self.root, self.dependency, now=self.now + timedelta(hours=24), fetcher=fetch)
        self.assertEqual(fetch.call_count, 2)

    def test_inflight_check_lease_prevents_a_second_external_request(self):
        other = mock.Mock(return_value='2.2.0')
        def fetch(_):
            concurrent = dependency_health.latest(self.root, self.dependency, now=self.now, fetcher=other)
            self.assertFalse(concurrent['update_check_due'])
            return '2.2.0'
        result = dependency_health.latest(self.root, self.dependency, now=self.now, fetcher=fetch)
        self.assertEqual(result['update_check_status'], 'FRESH')
        other.assert_not_called()

    def test_offline_update_check_preserves_known_version_as_stale_not_up_to_date(self):
        dependency_health.latest(self.root, self.dependency, now=self.now, fetcher=lambda _: '2.2.0')
        fetch = mock.Mock(side_effect=OSError('offline'))
        result = dependency_health.latest(self.root, self.dependency,
            now=self.now + timedelta(hours=25), fetcher=fetch)
        self.assertEqual(result['latest_known_version'], '2.2.0')
        self.assertEqual(result['update_check_status'], 'STALE')
        health = dependency_health.assess(self.dependency, self.observation, result)
        self.assertIsNone(health['update_available'])
        self.assertEqual(health['health_status'], 'STALE')
        dependency_health.latest(self.root, self.dependency, now=self.now + timedelta(hours=26), fetcher=fetch)
        self.assertEqual(fetch.call_count, 1)
        empty = dependency_health.latest(self.root / 'empty', self.dependency,
            now=self.now, fetcher=mock.Mock(side_effect=OSError('offline')))
        self.assertEqual(empty['update_check_status'], 'UNKNOWN')

    def test_invalid_release_response_preserves_stale_evidence(self):
        dependency_health.latest(self.root, self.dependency, now=self.now, fetcher=lambda _: '2.2.0')
        with mock.patch.object(dependency_health, 'urlopen') as request:
            request.return_value.__enter__.return_value.read.return_value = b'[]'
            result = dependency_health.latest(self.root, self.dependency, now=self.now + timedelta(hours=25))
        self.assertEqual(result['latest_known_version'], '2.2.0')
        self.assertEqual(result['update_check_status'], 'STALE')
        self.assertIsNone(dependency_health.assess(self.dependency, self.observation, result)['update_available'])

    def test_session_start_reads_cache_without_network_or_assuming_tool_loading(self):
        (self.root / '.mxagile').mkdir()
        (self.root / '.mxagile/config.yaml').write_text('context_optimization:\n  context_mode:\n    enabled: true\n')
        with mock.patch.object(dependency_health, 'fetch_latest', side_effect=AssertionError('No startup network')):
            result = dependency_health.context_mode(self.root, home=self.root / 'isolated-home', check_updates=False)
        self.assertEqual(result['health_status'], 'CAPABILITY_DEGRADED')
        self.assertFalse(result['route_allowed'])
        self.assertIsNone(result['capabilities_discoverable']['ctx_execute'])
        self.assertTrue(result['update_check_due'])


class DependencyHealthIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix='mxagile-dependency-integration-')
        self.root = Path(self.fixture.name)
        self.home = self.root / 'isolated-home'
        self.write('.mxagile/config.yaml', 'context_optimization:\n  context_mode:\n    enabled: true\n')
        shutil.copyfile(ROOT / '.mxagile/capabilities.yaml', self.root / '.mxagile/capabilities.yaml')
        shutil.copytree(ROOT / '.mxagile/adapters', self.root / '.mxagile/adapters')
        self.write('isolated-home/.claude/settings.json', json.dumps({'enabledPlugins': {'context-mode@context-mode': True}}))
        self.install('1.0.169')
        dependency_health.latest(self.root, {'id': 'context_mode'}, fetcher=lambda _: '2.2.0')

    def tearDown(self):
        self.fixture.cleanup()

    def write(self, relative, value):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value, encoding='utf-8')
        return path

    def install(self, version):
        package = self.write('plugin/package.json', json.dumps({'name': 'context-mode', 'version': version}))
        self.write('isolated-home/.claude/plugins/installed_plugins.json', json.dumps({'plugins': {
            'context-mode@context-mode': [{'scope': 'user', 'installPath': str(package.parent), 'version': version}]}}))

    def snapshot(self):
        return {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}

    def test_doctor_metadata_is_read_only_and_distinguishes_warning_from_incompatibility(self):
        import build_project_status
        before = self.snapshot()
        with mock.patch.object(Path, 'home', return_value=self.home), mock.patch.object(
                dependency_health, 'fetch_latest', side_effect=AssertionError('Doctor must stay offline')):
            report = build_project_status.build_status(self.root)['compatibility']
        dependency = report['dependency_health'][0]
        self.assertEqual(dependency['installed_version'], '1.0.169')
        self.assertTrue(dependency['update_available'])
        self.assertFalse(dependency['blocking'])
        self.assertIsNone(dependency['executable'])
        self.assertEqual(before, self.snapshot())
        self.install('1.0.32')
        with mock.patch.object(Path, 'home', return_value=self.home), mock.patch.object(dependency_health.shutil, 'which', return_value=None):
            report = build_project_status.build_status(self.root)['compatibility']
        diagnostics = [item for item in report['diagnostics'] if item['category'] == 'DEPENDENCY_INCOMPATIBLE']
        self.assertEqual(len(diagnostics), 1)
        self.assertTrue(diagnostics[0]['blocking'])

    def test_operation_probe_not_doctor_alone_proves_execution_and_is_not_cached(self):
        options = {'home': self.home, 'tools': ['ctx_doctor', 'ctx_execute'], 'health': 'healthy'}
        before = self.snapshot()
        unprobed = dependency_health.context_mode(self.root, **options)
        self.assertEqual(unprobed['health_status'], 'CAPABILITY_DEGRADED')
        self.assertIsNone(unprobed['executable'])
        verified = dependency_health.context_mode(self.root, **options, executed_tools=['ctx_execute'])
        self.assertEqual(verified['health_status'], 'UPDATE_AVAILABLE')
        self.assertTrue(verified['route_allowed'])
        next_session = dependency_health.context_mode(self.root, home=self.home, executed_tools=['ctx_execute'])
        self.assertFalse(next_session['route_allowed'])
        self.assertIsNone(next_session['executable'])
        self.assertEqual(before, self.snapshot())

    def test_real_resolver_exposes_update_without_blocking_verified_operations(self):
        def quote(value):
            return "'" + str(value).replace("'", "''") + "'"
        command = (f'& {quote(RESOLVER)} -ProjectRoot {quote(self.root)} -HomeDir {quote(self.home)} -Format json '
                   "-ContextModeToolsObserved -ContextModeTools @('ctx_doctor','ctx_execute') "
                   "-ContextModeRequiredTools ctx_execute -ContextModeHealth healthy")
        env = os.environ.copy()
        env['MXAGILE_HARNESS'] = 'claude_code'
        env['CLAUDECODE'] = '1'
        for key in ('OPENCODE_SESSION_ID', 'OPENCODE_BASE_URL'):
            env.pop(key, None)
        before = self.snapshot()
        for proof, expected in (('', 'CAPABILITY_DEGRADED'), (' -ContextModeExecutableTools ctx_execute', 'UPDATE_AVAILABLE')):
            with self.subTest(proof=bool(proof)):
                result = subprocess.run(['pwsh', '-NoProfile', '-Command', command + proof],
                    env=env, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                capability = next(item for item in json.loads(result.stdout)['capabilities'] if item['id'] == 'context_mode_integration')
                health = capability['integration']['dependency_health']
                self.assertEqual(health['health_status'], expected)
                self.assertEqual(capability['integration']['usable'], bool(proof))
                self.assertTrue(health['update_available'])
                self.assertFalse(health['blocking'])
        self.assertEqual(before, self.snapshot())

    def test_bad_plugin_metadata_does_not_claim_absence_or_trigger_updates(self):
        self.write('isolated-home/.claude/plugins/installed_plugins.json', 'invalid json')
        with mock.patch.object(dependency_health.shutil, 'which', return_value=None):
            report = dependency_health.context_mode(self.root, home=self.home, required_tools=[])
        self.assertIsNone(report['installed'])
        self.assertEqual(report['automatic_action'], 'none')


class RealityToolingTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix='reality-fixture-', dir=ROOT / 'tests')
        self.root = Path(self.fixture.name)

    def tearDown(self):
        self.fixture.cleanup()

    def resolve(self, parameter, evidence):
        path = self.root / 'evidence.json'
        path.write_text(json.dumps(evidence), encoding='utf-8')
        result = subprocess.run(['pwsh', '-NoProfile', '-File', str(RESOLVER),
                                 '-ProjectRoot', str(ROOT), '-Format', 'json', parameter, str(path)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def check(self, invariant, expected, observed, freshness='FRESH'):
        record = {'invariant': invariant, 'artifact': 'Module.Subject',
                  'evidence_reference': 'observations/model.json', 'view_state': freshness,
                  'expected': expected, 'observed': observed}
        result = self.resolve('-ArtifactInvariantEvidenceFile', {'checks': [record]})
        return result['artifact_invariants'][0]['result']

    def test_nanoflow_roles_match_the_accepted_scope(self):
        key = 'EXECUTABLE_NANOFLOW_ROLE_INVARIANT'
        self.assertEqual(self.check(key, {'required_roles': ['Module.Editor']},
                                    {'excluded': False, 'allowed_roles': []}), 'FAIL')
        self.assertEqual(self.check(key, {'required_roles': ['Module.Editor']},
                                    {'excluded': False, 'allowed_roles': ['Module.Editor']}), 'PASS')
        self.assertEqual(self.check(key, {'required_roles': ['Module.Editor']},
                                    {'excluded': False, 'allowed_roles': ['Module.Editor', 'Module.Unapproved']}), 'FAIL')
        self.assertEqual(self.check(key, {}, {'allowed_roles': ['Module.Editor']}), 'NOT_OBSERVABLE')

    def test_replacement_checks_navigation_exclusion_and_backup_disposition(self):
        key = 'REPLACEMENT_TARGET_INVARIANT'
        expected = {'active_page': 'Module.New', 'required_roles': ['Module.Reader'],
                    'backup_pages': ['Module.Old']}
        observed = {'active_page': 'Module.New', 'excluded': False,
                    'allowed_roles': ['Module.Reader'], 'navigation_targets': ['Module.New'],
                    'backup_pages': [{'page': 'Module.Old', 'excluded': True, 'allowed_roles': []}]}
        self.assertEqual(self.check(key, expected, observed), 'PASS')
        for changes in ({'navigation_targets': ['Module.Old']}, {'excluded': True},
                        {'allowed_roles': []},
                        {'backup_pages': [{'page': 'Module.Old', 'excluded': False, 'allowed_roles': []}]}):
            self.assertEqual(self.check(key, expected, dict(observed, **changes)), 'FAIL')
        missing = copy.deepcopy(observed)
        del missing['backup_pages'][0]['excluded']
        self.assertEqual(self.check(key, expected, missing), 'NOT_OBSERVABLE')
        self.assertEqual(self.check(key, expected, observed, 'SYNC_REQUIRED'), 'NOT_OBSERVABLE')

    def test_js_generated_identifiers_are_case_sensitive_not_display_names(self):
        key = 'JS_ACTION_PARAMETER_INVARIANT'
        expected = {'user_code_identifiers': ['KnowledgeContext']}
        self.assertEqual(self.check(key, expected, {'generated_identifiers': ['knowledgeContext']}), 'FAIL')
        self.assertEqual(self.check(key, expected, {'generated_identifiers': ['KnowledgeContext']}), 'PASS')

    def test_bridge_resources_must_be_in_materialized_scope_or_explicitly_loaded(self):
        key = 'HTML_BRIDGE_MATERIALIZATION_INVARIANT'
        expected = {'root_selector': '#project-root', 'required_resources': ['template-year']}
        observed = {'root_selector': '#project-root', 'root_materialized': True,
                    'materialized_resources': [], 'explicitly_loaded_resources': []}
        self.assertEqual(self.check(key, expected, observed), 'FAIL')
        observed['explicitly_loaded_resources'] = ['template-year']
        self.assertEqual(self.check(key, expected, observed), 'PASS')
        observed['root_materialized'] = False
        self.assertEqual(self.check(key, expected, observed), 'FAIL')

    def browser(self, **overrides):
        evidence = {'provider': 'studio_pro_mcp', 'host': 'UNKNOWN', 'run_id': 'RUN-fixture',
                    'observed_at': '2026-11-14T12:00:00Z', 'operation': 'browser.navigate',
                    'declared_available': True, 'tools_observed': True, 'operation_discovered': False,
                    'execution_status': 'NOT_OBSERVED', 'execution_reference': 'observations/browser.json',
                    'current_run_id': 'RUN-fixture', 'session_generation': 'generation-1',
                    'current_session_generation': 'generation-1', 'view_state': 'FRESH',
                    'bound_target': 'runtime-fixture', 'required_target': 'runtime-fixture'}
        evidence.update(overrides)
        return self.resolve('-BrowserEvidenceFile', evidence)['browser']

    def test_browser_declaration_is_not_execution_and_alternative_is_provider_scoped(self):
        result = self.browser()
        self.assertEqual(result['state'], 'PARTIAL')
        self.assertFalse(result['route_allowed'])
        result = self.browser(operation_discovered=True)
        self.assertEqual(result['state'], 'DISCOVERED_AVAILABLE')
        self.assertFalse(result['route_allowed'])
        result = self.browser(provider='local_node_playwright', operation_discovered=True,
                              execution_status='PASSED')
        self.assertEqual(result['state'], 'EXECUTABLE_AVAILABLE')
        self.assertTrue(result['route_allowed'])
        self.assertEqual(result['host'], 'UNKNOWN')
        self.assertEqual(self.browser(tools_observed=False)['state'], 'DECLARED_AVAILABLE')
        self.assertEqual(self.browser(declared_available=False)['state'], 'UNAVAILABLE')
        self.assertEqual(self.browser(operation_discovered=True, execution_status='FAILED')['state'], 'PARTIAL')

    def test_browser_historical_or_reconnected_execution_cannot_authorize_routing(self):
        for changes in ({'current_run_id': 'RUN-new'}, {'view_state': 'STALE'},
                        {'current_session_generation': 'generation-2'},
                        {'required_target': 'other-runtime'}, {'session_generation': None},
                        {'tools_observed': False}, {'operation_discovered': False}):
            with self.subTest(changes=changes):
                result = self.browser(**dict({'operation_discovered': True, 'execution_status': 'PASSED'}, **changes))
                self.assertFalse(result['route_allowed'])
        self.assertEqual(self.browser(operation_discovered=True, execution_status='PASSED')['last_verified'],
                         '2026-11-14T12:00:00Z')

    def test_mcp_enablement_reads_declared_config_without_claiming_execution(self):
        core = self.root / '.mxagile'
        core.mkdir()
        for name in ('capabilities.yaml', 'version.yaml', 'config.yaml'):
            shutil.copyfile(ROOT / '.mxagile' / name, core / name)
        config = self.root / '.vscode' / 'mcp.json'
        config.parent.mkdir()
        for enabled in (True, False):
            config.write_text(json.dumps({'servers': {'mendix-studio-pro': {'type': 'http',
                'url': 'http://localhost:7782/mcp', 'enabled': enabled}}}), encoding='utf-8')
            result = subprocess.run(['pwsh', '-NoProfile', '-File', str(RESOLVER), '-ProjectRoot', str(self.root),
                '-Capability', 'studio_pro_mcp', '-Format', 'json'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            capability = json.loads(result.stdout)['capabilities'][0]
            self.assertEqual(capability['state']['enabled'], enabled)
            self.assertFalse(capability['state']['active'])
            self.assertIsNone(capability['integration']['executable'])

    def test_operation_selection_is_capability_and_instance_scoped(self):
        base = dict(provider='studio_pro_mcp', host='UNKNOWN', run_id='RUN-fixture',
                    current_run_id='RUN-fixture', observed_at='2026-11-15T12:00:00Z',
                    operation='browser.snapshot', declared_available=True, tools_observed=True,
                    operation_discovered=True, execution_status='PASSED', execution_reference='observations/probe.json',
                    session_generation='one', current_session_generation='one', view_state='FRESH',
                    bound_target='runtime-fixture', required_target='runtime-fixture', limitations=[])
        envelope = dict(operation='browser.snapshot', preferred_providers=['studio_pro_mcp', 'local_node_playwright'],
                        preference_reason='Same Studio Pro/runtime binding; project runner is the configured fallback.',
                        current_run_id='RUN-fixture', current_session_generation='one', required_target='runtime-fixture',
                        providers=[dict(base, provider='concord_mcp', operation_discovered=False),
                                   base, dict(base, provider='local_node_playwright')])
        selected = self.resolve('-OperationEvidenceFile', envelope)['provider_selection']
        self.assertEqual(selected['selected_provider'], 'studio_pro_mcp')
        self.assertEqual(selected['fallback_providers'], ['local_node_playwright'])
        envelope['preferred_providers'] = ['studio_pro_mcp', 'studio_pro_mcp', 'local_node_playwright']
        selected = self.resolve('-OperationEvidenceFile', envelope)['provider_selection']
        self.assertEqual(selected['fallback_providers'], ['local_node_playwright'], 'Fallback must not retry the selected provider')
        envelope['providers'][1]['current_session_generation'] = 'two'
        self.assertEqual(self.resolve('-OperationEvidenceFile', envelope)['provider_selection']['selected_provider'],
                         'local_node_playwright')
        envelope['providers'][2]['bound_target'] = 'wrong-runtime'
        self.assertIsNone(self.resolve('-OperationEvidenceFile', envelope)['provider_selection']['selected_provider'])

    def test_empty_reference_results_require_complete_fresh_dynamic_coverage(self):
        evidence = dict(provider='concord_mcp', operation='references.scan', host='UNKNOWN',
                        run_id='RUN-fixture', current_run_id='RUN-fixture', observed_at='2026-11-15T12:00:00Z',
                        session_generation='one', current_session_generation='one', view_state='FRESH',
                        bound_target='model-fixture', required_target='model-fixture',
                        scan_status='COMPLETE', reference_count=0, index_state='FRESH',
                        dynamic_reference_possible=False, coverage_complete=True,
                        evidence_reference='observations/reference-scan.json')
        result = self.resolve('-ReferenceEvidenceFile', evidence)['reference_safety']
        self.assertEqual(result['state'], 'COMPLETE_SCAN_NO_REFERENCES')
        self.assertTrue(result['reference_clearance'])
        self.assertFalse(result['mutation_authorized'])
        for changes, state in (({'scan_status': 'TIMEOUT'}, 'PARTIAL_SCAN'),
                               ({'index_state': 'STALE'}, 'STALE_INDEX'),
                               ({'dynamic_reference_possible': True}, 'DYNAMIC_REFERENCE_POSSIBLE'),
                               ({'coverage_complete': False}, 'PARTIAL_SCAN'),
                               ({'current_session_generation': 'two'}, 'UNKNOWN'),
                               ({'scan_status': 'NOT_OBSERVABLE'}, 'NOT_OBSERVABLE')):
            with self.subTest(changes=changes):
                result = self.resolve('-ReferenceEvidenceFile', dict(evidence, **changes))['reference_safety']
                self.assertEqual(result['state'], state)
                self.assertFalse(result['reference_clearance'])
                self.assertFalse(result['mutation_authorized'])

    def test_browser_execution_claim_needs_a_source_reference(self):
        path = self.root / 'browser.json'
        path.write_text(json.dumps({'provider': 'local_node_playwright', 'host': 'UNKNOWN',
                                    'run_id': 'RUN-fixture', 'observed_at': '2026-11-14T12:00:00Z',
                                    'operation': 'browser.navigate', 'declared_available': True,
                                    'tools_observed': True, 'operation_discovered': True,
                                    'execution_status': 'PASSED'}), encoding='utf-8')
        result = subprocess.run(['pwsh', '-NoProfile', '-File', str(RESOLVER),
                                 '-ProjectRoot', str(ROOT), '-Format', 'json', '-BrowserEvidenceFile', str(path)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, 'An unreferenced execution claim enabled routing')

    def test_routing_writer_rejects_schema_type_coercion_before_persistence(self):
        initial = subprocess.run(['pwsh', '-NoProfile', '-File', str(WRITER), '-ProjectRoot', str(self.root),
                                  '-MissionId', 'MISSION-fixture'], capture_output=True, text=True)
        self.assertEqual(initial.returncode, 0, initial.stdout + initial.stderr)
        route = dict(schema_version='1.0', mission_id='MISSION-fixture', decision_id='ROUTE-fixture',
                     session_identity=None, work_package='bounded syntax check', requested_agent_type=None,
                     work_class='deterministic', scope={'summary': 'one source', 'paths': []},
                     artifact_count=0, semantic=False, deterministic=True, capability_state='not_applicable',
                     requested_profile=None, route='HELPER', reason='deterministic helper suffices',
                     fallback_reason=None, delegation_attempted=False, spawn_outcome='not_attempted',
                     delegation_id=None, result_reference=None, main_consumed=False,
                     compaction_occurred=False, result_reused=False, stale_result_rejected=False,
                     batch_restarted=False, references=[])
        for number, changes in enumerate(({'compaction_occurred': 'false'}, {'artifact_count': 1.5},
                                          {'scope': {'summary': 'one source', 'paths': 'requirements/REQ-001.yml'}},
                                          {'delegation_id': 'invalid'}, {'delegation_id': 'delegation-lowercase'},
                                          {'decision_id': 'route-lowercase'}, {'route': 'helper'},
                                          {'session_identity': 123}, {'reason': {'inferred': 'text'}})):
            route['decision_id'] = f'ROUTE-fixture-{number}'
            with self.subTest(changes=changes):
                path = self.root / 'routing.json'
                path.write_text(json.dumps(dict(route, **changes)), encoding='utf-8')
                result = subprocess.run(['pwsh', '-NoProfile', '-File',
                                         str(ROOT / 'scripts' / 'Save-MxAgileRoutingDecision.ps1'),
                                         '-ProjectRoot', str(self.root), '-InputFile', str(path)],
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, 'schema-invalid route was persisted')
                self.assertFalse((self.root / '.concord' / 'routing-decisions' / f'ROUTE-fixture-{number}.json').exists())

    def test_epoch_preflight_omits_empty_native_arguments_on_both_powershell_hosts(self):
        tool = self.root / '.mxagile' / 'tools' / 'project_compatibility.py'
        tool.parent.mkdir(parents=True)
        tool.write_text('import json,sys\n'
                        'args=sys.argv[1:]\n'
                        'for flag in ("--mission-id", "--wave", "--phase"):\n'
                        ' if flag in args and (args.index(flag)+1 == len(args) or args[args.index(flag)+1].startswith("--") or not args[args.index(flag)+1]):\n'
                        '  print(json.dumps({"state":"BLOCKED", "reason_codes":["EMPTY_NATIVE_ARGUMENT"]}));sys.exit(3)\n'
                        'print(json.dumps({"state":"READY_FOR_RESYNC", "mission_id":"MISSION-fixture", "wave_id":"W1", "phase":"implementing"}))\n', encoding='utf-8')
        state = self.root / '.mxagile' / 'state'
        state.mkdir()
        (state / 'core-provenance.json').write_text(json.dumps({
            'artifact_contract': {'version': 'fixture'},
            'recovery_tools': {'project_compatibility.py': hashlib.sha256(tool.read_bytes()).hexdigest()}
        }), encoding='utf-8')
        for host in ('powershell', 'pwsh'):
            if not shutil.which(host):
                self.fail(f'{host} unavailable: cross-host verification incomplete')
            environment = os.environ.copy()
            if host == 'powershell':
                environment['PSModulePath'] = str(Path(shutil.which(host)).parent / 'Modules')
            result = subprocess.run([host, '-NoProfile', '-File', str(WRITER),
                                     '-ProjectRoot', str(self.root)], capture_output=True, text=True, env=environment)
            self.assertEqual(result.returncode, 0, host + ': ' + result.stdout + result.stderr)
            checkpoint = self.root / '.concord' / 'context-epoch.yaml'
            self.assertIn('MISSION-fixture', checkpoint.read_text(encoding='utf-8-sig'))
            before = checkpoint.read_bytes()
            script = tool.read_text(encoding='utf-8')
            tool.write_text('import json,sys\nprint(json.dumps({"state":"BLOCKED", "reason_codes":["GUARD_BLOCKED"]}));sys.exit(3)\n', encoding='utf-8')
            provenance = json.loads((state / 'core-provenance.json').read_text(encoding='utf-8'))
            provenance['recovery_tools']['project_compatibility.py'] = hashlib.sha256(tool.read_bytes()).hexdigest()
            (state / 'core-provenance.json').write_text(json.dumps(provenance), encoding='utf-8')
            blocked = subprocess.run([host, '-NoProfile', '-File', str(WRITER),
                                      '-ProjectRoot', str(self.root)], capture_output=True, text=True, env=environment)
            self.assertNotEqual(blocked.returncode, 0)
            self.assertIn('GUARD_BLOCKED', blocked.stderr)
            self.assertEqual(checkpoint.read_bytes(), before, 'Blocked recovery mutated the checkpoint')
            tool.write_text('print("unstructured preflight failure")\n', encoding='utf-8')
            provenance['recovery_tools']['project_compatibility.py'] = hashlib.sha256(tool.read_bytes()).hexdigest()
            (state / 'core-provenance.json').write_text(json.dumps(provenance), encoding='utf-8')
            malformed = subprocess.run([host, '-NoProfile', '-File', str(WRITER), '-ProjectRoot', str(self.root)],
                                       capture_output=True, text=True, env=environment)
            self.assertNotEqual(malformed.returncode, 0)
            self.assertIn('RESYNC_PREFLIGHT_INVALID_OUTPUT', malformed.stderr)
            self.assertEqual(checkpoint.read_bytes(), before, 'Unstructured preflight mutated the checkpoint')
            tool.write_text(script, encoding='utf-8')
            provenance['recovery_tools']['project_compatibility.py'] = hashlib.sha256(tool.read_bytes()).hexdigest()
            (state / 'core-provenance.json').write_text(json.dumps(provenance), encoding='utf-8')


if __name__ == '__main__':
    unittest.main()
