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

ROOT = Path(__file__).resolve().parents[1]
RESOLVER = ROOT / 'scripts' / 'Get-MxAgileCapabilities.ps1'
WRITER = ROOT / 'scripts' / 'Write-MxAgileEpochCheckpoint.ps1'


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
                    'execution_status': 'NOT_OBSERVED', 'execution_reference': 'observations/browser.json'}
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
