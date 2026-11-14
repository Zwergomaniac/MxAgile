"""Bound self-update authorization and legacy bootstrap regression fixtures."""
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from unittest import mock
import unittest

from test_control_plane_phase1b import Phase1BFixture, RecoveryScopeTests, enforcement, GUARD_DIR
import framework_update_recovery as recovery


class UpdateRecoveryTests(Phase1BFixture):
    def setUp(self):
        super().setUp()
        self.tools, self.compatibility = RecoveryScopeTests.recovery_tools(self)
        source = GUARD_DIR.parents[1] / 'scripts/framework_update_recovery.py'
        (self.tools / source.name).write_bytes(source.read_bytes())
        core_path = self.root / '.mxagile/state/core-provenance.json'
        self.core = json.loads(core_path.read_bytes())
        self.source = 'https://github.com/Zwergomaniac/MxAgile.git'
        self.core.update(source=self.source, source_type='git', distribution={'canonical_url': self.source})
        self.core['recovery_tools'][source.name] = hashlib.sha256(source.read_bytes()).hexdigest()
        core_path.write_text(json.dumps(self.core))
        self.base = f'python -B "{self.tools / source.name}"'
        self.selectors = f'--project-root "{self.root}" --source {self.source} --ref experiment/control-plane-sak-principles'
        self.commit = 'c' * 40

    def test_blocked_discovery_and_only_bound_update_recovery(self):
        check = self.hook('Bash', {'command': self.base + ' check ' + self.selectors})
        self.assertEqual(check['decision'], 'allow', check)
        self.assertEqual(check['operation_class'], enforcement.UPDATE_DISCOVERY)
        raw = self.hook('Bash', {'command': f'git ls-remote {self.source} experiment/control-plane-sak-principles'})
        self.assertEqual(raw['decision'], 'allow', raw)
        preview = self.hook('Bash', {'command': self.base + ' preflight ' + self.selectors + ' --commit ' + self.commit})
        self.assertEqual(preview['decision'], 'allow', preview)
        command = self.base + ' apply ' + self.selectors + f' --commit {self.commit} --plan-hash approved --human-reference USER-UPDATE-FIXTURE --run-id RUN-UPDATE-FIXTURE --human-confirmed'
        with mock.patch.object(recovery, 'preflight', return_value={'plan': {'plan_hash': 'approved'}}):
            result = self.hook('Bash', {'command': command})
        self.assertEqual(result['decision'], 'allow', result)
        self.assertEqual(result['operation_class'], enforcement.UPDATE_RECOVERY)
        for path in ('requirements/REQ-001.yml', 'planning/mission/mission-state.yaml', 'planning/lifecycle/process-state.yaml', 'javascriptsource/example.js'):
            self.assertEqual(self.hook('Edit', {'file_path': path})['decision'], 'deny')
        self.assertEqual(self.hook('Bash', {'command': 'mxcli exec changes.mdl'})['decision'], 'deny')
        self.assertEqual(self.hook('Agent', {'subagent_type': 'general-purpose', 'prompt': 'write product'})['decision'], 'deny')
        self.assertNotEqual(self.hook('Bash', {'command': 'git push'})['decision'], 'allow')

    def test_wrong_source_root_script_and_extra_shell_are_not_update_authority(self):
        check = self.base + ' check ' + self.selectors
        for command in (check.replace(self.source, 'https://example.invalid/other.git'), check.replace(str(self.root), str(self.root.parent)),
                        check + ' && git push', check + ' > requirements/REQ-001.yml',
                        check.replace(str(self.tools / 'framework_update_recovery.py'), str(self.root / 'framework_update_recovery.py')),
                        f'pwsh -NoProfile -File "{self.root / "mxagile-setup-company-layer.ps1"}" -ProjectRoot "{self.root}"',
                        f'git ls-remote {self.source} --upload-pack=other'):
            with self.subTest(command=command):
                self.assertEqual(self.hook('Bash', {'command': command})['decision'], 'deny')
        (self.tools / 'framework_update_recovery.py').write_text('# altered updater\n')
        self.assertEqual(self.hook('Bash', {'command': check})['decision'], 'deny')

    def test_discovery_resolves_annotated_tag_to_commit_not_tag_object(self):
        tag = 'refs/tags/recovery-v1'
        with mock.patch.object(recovery, 'git', return_value='a' * 40 + '\t' + tag + '\n' + self.commit + '\t' + tag + '^{}'):
            result = recovery.discover(self.root, self.source, tag)
        self.assertEqual(result['commit'], self.commit)

    def test_unapproved_or_stale_plan_never_authorizes_update(self):
        command = self.base + ' apply ' + self.selectors + f' --commit {self.commit} --plan-hash wrong --human-reference USER-UPDATE-FIXTURE --run-id RUN-UPDATE-FIXTURE --human-confirmed'
        with mock.patch.object(recovery, 'preflight', return_value={'plan': {'plan_hash': 'approved'}}):
            self.assertEqual(self.hook('Bash', {'command': command})['decision'], 'deny')
            self.assertEqual(self.hook('Bash', {'command': command.replace(' --human-confirmed', '')})['decision'], 'deny')

    def test_restart_barrier_protects_human_resolution_and_resync(self):
        self.core['commit'] = self.commit
        (self.root / '.mxagile/state/core-provenance.json').write_text(json.dumps(self.core))
        value = {'schema_version': 1, 'project_root': str(self.root), 'update_id': 'UPDATE-' + 'a' * 32, 'source': self.source,
                 'ref': 'experiment/control-plane-sak-principles', 'commit': self.commit, 'started_at': '2026-01-01T00:00:00+00:00',
                 'run_id': 'RUN-UPDATE-OLDSESSION', 'restart_required': True, 'state': 'INSTALLED'}
        path = self.root / recovery.STATE
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({**value, 'restart_required': False}))
        with self.assertRaisesRegex(ValueError, 'UPDATE_RECOVERY_STATE_INVALID'):
            recovery.require_restarted(self.root)
        path.write_text(json.dumps(value))
        result = enforcement.guard.delivery_authorization(enforcement.guard.load_project_facts(self.root), enforcement.DELIVERY_WRITE)
        self.assertIn('FRAMEWORK_SESSION_RESTART_REQUIRED', {f['code'] for f in result['must_findings']})
        self.assertIn('FRAMEWORK_SESSION_RESTART_REQUIRED', self.compatibility.resync_preflight(self.root)['reason_codes'])
        with self.assertRaisesRegex(ValueError, 'FRAMEWORK_SESSION_RESTART_REQUIRED'):
            self.compatibility.prepare_human_resolution(self.root, diagnostic_id='', migration_id='', source_path='', field='', source_fingerprint='', value='', human_reference='USER-HUMAN-CASE', human_confirmed=True, run_id='RUN-HUMAN-CASE')
        cli = subprocess.run([sys.executable, '-B', str(self.tools / 'project_compatibility.py'), 'resolve', '--project-root', str(self.root),
                              '--format', 'json', '--diagnostic-id', 'DIAG-TEST', '--migration-id', 'MIG-TEST', '--source-path', 'requirements/REQ-001.yml',
                              '--field', 'superseded_by', '--source-fingerprint', 'a' * 64, '--value', 'REQ-068', '--human-reference', 'USER-RESTART-CASE',
                              '--run-id', 'RUN-RESTART-CASE', '--human-confirmed'], capture_output=True, text=True)
        self.assertEqual(cli.returncode, 3)
        self.assertEqual(json.loads(cli.stderr)['error'], 'FRAMEWORK_SESSION_RESTART_REQUIRED')
        for confirmed, run in ((False, 'RUN-NEW-SESSION'), (True, 'RUN-UPDATE-OLDSESSION')):
            with self.assertRaises(ValueError):
                recovery.acknowledge_restart(self.root, value['update_id'], 'USER-RESTART-FIXTURE', confirmed, run)
        result = recovery.acknowledge_restart(self.root, value['update_id'], 'USER-RESTART-FIXTURE', True, 'RUN-NEW-SESSION')
        self.assertFalse(result['delivery_authorized'])
        recovery.require_restarted(self.root)
        self.assertEqual(self.hook('Edit', {'file_path': 'requirements/REQ-001.yml'})['decision'], 'deny')

    def test_partial_update_resumes_only_same_transaction_without_delivery_authority(self):
        from contextlib import contextmanager
        @contextmanager
        def staged(*_args):
            yield self.root, 'payload'
        preview = {'project_root': str(self.root), 'source': self.source, 'ref': 'experiment/control-plane-sak-principles',
                   'commit': self.commit, 'plan_hash': 'approved'}
        transaction = self.root / '.mxagile/state/update-transaction.json'
        def installer(command, **_kwargs):
            if '-ResumeUpdate' not in command:
                transaction.write_text(json.dumps({'state': 'PARTIAL_UPDATE', 'target_core': {'commit': self.commit}}))
                return subprocess.CompletedProcess(command, 1, '', 'projection apply failed')
            transaction.unlink()
            self.core['commit'] = self.commit
            (self.root / '.mxagile/state/core-provenance.json').write_text(json.dumps(self.core))
            return subprocess.CompletedProcess(command, 0, '', '')
        with mock.patch.object(recovery, 'distribution', staged), mock.patch.object(recovery, 'plan', return_value=preview), mock.patch.object(recovery.subprocess, 'run', side_effect=installer):
            with self.assertRaisesRegex(ValueError, 'UPDATE_RECOVERY_PARTIAL'):
                recovery.apply(self.root, self.source, preview['ref'], self.commit, 'approved', 'USER-UPDATE-FIXTURE', True, 'RUN-UPDATE-FIXTURE')
            pending = recovery.state(self.root)
            self.assertEqual(pending['state'], 'PARTIAL')
            self.assertTrue(pending['restart_required'])
            with self.assertRaisesRegex(ValueError, 'STALE_UPDATE_TARGET'):
                recovery.apply(self.root, self.source, 'other-ref', self.commit, 'approved', 'USER-UPDATE-FIXTURE', True, 'RUN-UPDATE-FIXTURE', resume=True)
            result = recovery.apply(self.root, self.source, preview['ref'], self.commit, 'approved', 'USER-UPDATE-FIXTURE', True, 'RUN-UPDATE-FIXTURE', resume=True)
        self.assertEqual(result['update_id'], pending['update_id'])
        self.assertFalse(result['delivery_authorized'])
        self.assertTrue(result['restart_required'])
        self.assertEqual(self.hook('Edit', {'file_path': 'requirements/REQ-001.yml'})['decision'], 'deny')

    def test_immutable_old_guard_cannot_bootstrap_new_recovery_rule(self):
        old = subprocess.check_output(['git', '-C', str(GUARD_DIR.parents[1]), 'show', '7b8d96a:experiments/control-plane/enforcement.py'])
        path = self.root / 'legacy_enforcement.py'
        path.write_bytes(old)
        spec = importlib.util.spec_from_file_location('legacy_enforcement_fixture', path)
        legacy = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = legacy
        spec.loader.exec_module(legacy)
        for command in (f'git ls-remote {self.source} experiment/control-plane-sak-principles', self.base + ' check ' + self.selectors,
                        self.base + ' apply ' + self.selectors):
            result = legacy.decide(self.root, {'tool_name': 'Bash', 'tool_input': {'command': command}})
            self.assertEqual(result['decision'], 'deny', result)
        self.assertEqual(path.read_bytes(), old)


class DisposableSelfUpdateTests(Phase1BFixture):
    def test_legacy_operator_bootstrap_to_resolution_and_ready(self):
        import io
        import shutil
        import tarfile
        import tempfile
        from test_control_plane_guard import _git
        binary = Path(os.environ.get('MXCLI_TEST_BINARY', str(Path(os.environ['TEMP']) / 'mxagile-mxcli-test-cache/mxcli.exe')))
        if not binary.is_file():
            self.fail('UNAVAILABLE: cached mxcli is required for Disposable acceptance')
        repo = GUARD_DIR.parents[1]
        with tempfile.TemporaryDirectory(prefix='mxagile-self-update-fixture-') as work:
            work = Path(work)
            print(f'Disposable Consumer: {self.root}; distribution workspace: {work}', flush=True)
            old_dist, candidate = work / 'old', work / 'candidate'
            for destination, ref in ((old_dist, '7b8d96a'), (candidate, 'HEAD')):
                destination.mkdir()
                archive = subprocess.check_output(['git', '-C', str(repo), 'archive', ref])
                with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
                    tar.extractall(destination, filter='data')
            for relative in ('.mxagile/policies/project-compatibility.md', '.mxagile/schemas/finding.schema.json', '.mxagile/schemas/project-timeline.schema.json', 'scripts/wave_ids.py', 'scripts/framework_update_recovery.py', 'scripts/install-core.ps1', 'scripts/update-transaction.ps1', 'scripts/setup-agent-system.ps1', 'scripts/project_compatibility.py',
                             'experiments/control-plane/guard.py', 'experiments/control-plane/enforcement.py',
                             'experiments/control-plane/control-plane-verdict.schema.json'):
                shutil.copyfile(repo / relative, candidate / relative)
            _git(candidate, 'init', '-q')
            _git(candidate, 'checkout', '-qb', 'recovery-fixture')
            _git(candidate, 'add', '-A')
            _git(candidate, 'commit', '-qm', 'disposable new framework payload')
            commit = _git(candidate, 'rev-parse', 'HEAD')
            self.write('fixture.mpr', '')
            self.write_yaml('requirements/REQ-001.yml', {'ID': 'REQ-001', 'title': 'Old', 'description': 'Old behavior', 'status': 'superseded'})
            self.write_yaml('requirements/REQ-068.yml', {'ID': 'REQ-068', 'title': 'Current', 'description': 'Current behavior', 'status': 'accepted'})
            env = {**os.environ, 'MXCLI_TEST_BINARY': str(binary), 'PYTHONDONTWRITEBYTECODE': '1', 'GIT_OPTIONAL_LOCKS': '0'}
            def run(args, expected=0):
                result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=1800)
                self.assertEqual(result.returncode, expected, result.stdout[-5000:] + result.stderr[-5000:])
                return result.stdout or result.stderr
            run(['pwsh', '-NoProfile', '-File', str(old_dist / 'scripts/install-core.ps1'), '-ProjectRoot', str(self.root), '-IsUpdate:$true',
                 '-ProvenanceCoreSource', str(candidate), '-ProvenanceCoreSourceType', 'git', '-ProvenanceCoreRef', 'recovery-fixture', '-ProvenanceCoreCommit', '7b8d96aebd9d4627f6c9eefab3332f9a6a2c8b73'])
            tools = self.root / '.mxagile/tools'
            old_guard = (tools / 'control-plane/enforcement.py').read_bytes()
            doctor = tools / 'project_compatibility.py'
            migration = json.loads(run([sys.executable, '-B', str(doctor), 'migrate', '--apply-safe', '--project-root', str(self.root), '--format', 'json'], 2))
            self.assertEqual(migration['migration']['status'], 'NEEDS_HUMAN')
            layer = self.write('.mxagile/layers/fixture-company/provenance.json', '{"source":"fixture-company","sourceCommit":"company-pinned","installedVersion":"1"}')
            layer_bytes = layer.read_bytes()
            core_path = self.root / '.mxagile/state/core-provenance.json'
            branded = json.loads(core_path.read_bytes())
            branded.update(flavor='fixture-product', product_flavor='fixture-product')
            core_path.write_text(json.dumps(branded))
            def hook(tool, arguments):
                payload = json.dumps({'tool_name': tool, 'tool_input': arguments, 'cwd': str(self.root)})
                result = subprocess.run([sys.executable, '-B', str(tools / 'control-plane/enforcement.py')], input=payload, env=env, capture_output=True, text=True, timeout=240)
                self.assertEqual(result.returncode, 0, result.stderr)
                return json.loads(result.stdout)['hookSpecificOutput']['permissionDecision']
            def blocked():
                for target in ('requirements/REQ-001.yml', 'planning/mission/mission-state.yaml', 'planning/lifecycle/process-state.yaml', 'javascriptsource/example.js'):
                    self.assertEqual(hook('Edit', {'file_path': str(self.root / target)}), 'deny')
                self.assertEqual(hook('Bash', {'command': 'mxcli exec changes.mdl'}), 'deny')
                self.assertNotEqual(hook('Bash', {'command': 'git push'}), 'allow')
            blocked()
            source_args = ['--project-root', str(self.root), '--source', str(candidate), '--ref', 'recovery-fixture']
            bootstrap = candidate / 'scripts/framework_update_recovery.py'
            self.assertEqual(hook('Bash', {'command': f'python -B "{bootstrap}" check --project-root "{self.root}" --source "{candidate}" --ref recovery-fixture'}), 'deny')
            self.assertEqual(hook('Bash', {'command': f'git ls-remote "{candidate}" recovery-fixture'}), 'deny')
            def snapshot():
                return {path.relative_to(self.root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in self.root.rglob('*') if path.is_file()}
            before_discovery = snapshot()
            discovered = json.loads(run([sys.executable, '-B', str(bootstrap), 'check', *source_args]))
            self.assertEqual(discovered['commit'], commit)
            self.assertEqual(snapshot(), before_discovery)
            projection = self.root / '.claude/skills/mocketeer-discovery/SKILL.md'
            original = projection.read_bytes()
            foreign = projection.parent / 'foreign-user.md'
            provenance = (self.root / '.mxagile/state/core-provenance.json').read_bytes()
            foreign.write_text('Foreign consumer content\n')
            before_conflict = snapshot()
            blocked_preflight = json.loads(run([sys.executable, '-B', str(bootstrap), 'preflight', *source_args, '--commit', commit], 3))
            self.assertEqual(blocked_preflight['code'], 'UPDATE_PROJECTION_PREFLIGHT_BLOCKED')
            self.assertEqual(snapshot(), before_conflict)
            self.assertEqual((self.root / '.mxagile/state/core-provenance.json').read_bytes(), provenance)
            self.assertFalse((self.root / '.mxagile/state/update-transaction.json').exists())
            self.assertFalse((self.root / recovery.STATE).exists())
            self.assertEqual(projection.read_bytes(), original)
            foreign.unlink()
            before_preflight = snapshot()
            proposal = json.loads(run([sys.executable, '-B', str(bootstrap), 'preflight', *source_args, '--commit', commit]))
            self.assertEqual(snapshot(), before_preflight)
            self.assertEqual((tools / 'control-plane/enforcement.py').read_bytes(), old_guard)
            # Explicit maintainer boundary: the old agent is still denied; no hook is disabled or patched.
            update = json.loads(run([sys.executable, '-B', str(bootstrap), 'apply', *source_args, '--commit', commit,
                                    '--plan-hash', proposal['plan']['plan_hash'], '--human-reference', 'USER-LEGACY-BOOTSTRAP', '--run-id', 'RUN-LEGACY-OLDSESSION', '--human-confirmed']))
            self.assertEqual(update['result'], 'INSTALLED_RESTART_REQUIRED')
            handoff = json.loads((self.root / '.mxagile/state/last-update-result.json').read_bytes())
            self.assertTrue(handoff['restart_required'])
            self.assertEqual(handoff['session_contract']['state'], 'SESSION_RESTART_REQUIRED')
            self.assertTrue(handoff['update_transaction']['restart_required'])
            self.assertEqual(layer.read_bytes(), layer_bytes)
            self.assertEqual(json.loads(core_path.read_bytes())['product_flavor'], 'fixture-product')
            self.assertEqual(json.loads(core_path.read_bytes())['commit'], commit)
            self.assertNotEqual((tools / 'control-plane/enforcement.py').read_bytes(), old_guard)
            blocked()
            installed = tools / 'framework_update_recovery.py'
            installed_command = f'python -B "{installed}"'
            selectors = f'--project-root "{self.root}" --source "{candidate}" --ref recovery-fixture'
            self.assertEqual(hook('Bash', {'command': installed_command + ' check ' + selectors}), 'allow')
            self.assertEqual(hook('Bash', {'command': f'git ls-remote "{candidate}" recovery-fixture'}), 'allow')
            self.assertEqual(hook('Bash', {'command': installed_command + ' preflight ' + selectors + ' --commit ' + commit}), 'allow')
            current_plan = json.loads(run([sys.executable, '-B', str(installed), 'preflight', *source_args, '--commit', commit]))
            authorized = installed_command + ' apply ' + selectors + f' --commit {commit} --plan-hash {current_plan["plan"]["plan_hash"]} --human-reference USER-VERIFIED-UPDATE --run-id RUN-FIXTURE-UPDATE --human-confirmed'
            self.assertEqual(hook('Bash', {'command': authorized}), 'allow')
            bindings = json.loads(run([sys.executable, '-B', str(doctor), 'resolve', '--dry-run', '--project-root', str(self.root), '--format', 'json']))['resolutions']
            binding = next(item for item in bindings if item['artifact_id'] == 'REQ-001')
            resolve_args = ['--project-root', str(self.root), '--format', 'json', '--diagnostic-id', binding['diagnostic_id'], '--migration-id', binding['migration_id'],
                            '--source-path', binding['source_path'], '--field', binding['field'], '--source-fingerprint', binding['current_source_fingerprint'],
                            '--value', 'REQ-068', '--human-reference', 'USER-FIXTURE-SUCCESSOR', '--run-id', 'RUN-FIXTURE-NEWSESSION', '--human-confirmed']
            stopped = json.loads(run([sys.executable, '-B', str(doctor), 'resolve', *resolve_args], 3))
            self.assertEqual(stopped['error'], 'FRAMEWORK_SESSION_RESTART_REQUIRED')
            installed = tools / 'framework_update_recovery.py'
            run([sys.executable, '-B', str(installed), 'acknowledge-restart', '--project-root', str(self.root), '--update-id', update['update_id'],
                 '--human-reference', 'USER-REAL-RESTART', '--run-id', 'RUN-FIXTURE-NEWSESSION', '--human-confirmed'])
            resolved = json.loads(run([sys.executable, '-B', str(doctor), 'resolve', *resolve_args]))
            self.assertEqual(resolved['migration']['status'], 'COMPLETE')
            self.assertTrue(resolved['doctor']['executed'])
            self.assertNotEqual(resolved['doctor']['compatibility'], 'BLOCKED')
            blocked()
            run(['pwsh', '-NoProfile', '-File', str(tools / 'Write-MxAgileEpochCheckpoint.ps1'), '-ProjectRoot', str(self.root), '-PreserveEvidence'])
            # Existing canonical guard derives readiness; Auxiliary/Update never promotes the Wave.
            facts = enforcement.guard.load_project_facts(self.root)
            verdict = enforcement.guard.delivery_authorization(facts, enforcement.DELIVERY_WRITE, require_implementing=False)
            self.assertEqual(verdict['verdict'], 'pass', verdict['must_findings'])
            self.assertEqual(facts.process_state['waves']['W01']['phase'], 'ready')


if __name__ == '__main__':
    unittest.main()
