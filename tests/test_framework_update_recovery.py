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

    def installed_restart(self):
        self.core['commit'] = self.commit
        (self.root / '.mxagile/state/core-provenance.json').write_text(json.dumps(self.core))
        value = {'schema_version': 1, 'project_root': str(self.root), 'update_id': 'UPDATE-' + 'a' * 32,
                 'commit': self.commit, 'started_at': '2026-01-01T00:00:00+00:00',
                 'run_id': 'RUN-UPDATE-OLDSESSION', 'restart_required': True, 'state': 'INSTALLED'}
        path = self.root / recovery.STATE
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))
        return value, path

    def test_startup_discovers_pending_restart_and_acknowledges_once_without_user_ids(self):
        value, path = self.installed_restart()
        before = path.read_bytes()
        status = recovery.restart_status(self.root)
        self.assertEqual(status['update_id'], value['update_id'])
        self.assertEqual(status['next_action'], 'confirm_actual_host_restart')
        self.assertEqual(path.read_bytes(), before)
        with self.assertRaisesRegex(ValueError, 'HUMAN_AUTHORIZATION_REQUIRED'):
            recovery.acknowledge_restart(self.root, human_confirmed=False)
        acknowledged = recovery.acknowledge_restart(self.root, human_confirmed=True)
        self.assertEqual(acknowledged['result'], 'RESTART_ACKNOWLEDGED')
        record = json.loads(path.read_bytes())
        self.assertNotEqual(record['restart_run_id'], value['run_id'])
        self.assertTrue(record['restart_progress']['restart_observed'])
        self.assertTrue(record['restart_progress']['restart_acknowledged'])
        acknowledged_bytes = path.read_bytes()
        again = recovery.acknowledge_restart(self.root)
        self.assertEqual(again['result'], 'ALREADY_ACKNOWLEDGED')
        self.assertEqual(path.read_bytes(), acknowledged_bytes)
        self.assertFalse(recovery.restart_status(self.root)['restart_required'])
        recovery.require_restarted(self.root)

    def test_known_old_host_run_cannot_fake_restart_using_new_uuid(self):
        value, path = self.installed_restart()
        before = path.read_bytes()
        with mock.patch.dict(os.environ, {'MXAGILE_RUN_ID': value['run_id']}):
            with self.assertRaisesRegex(ValueError, 'FRAMEWORK_SESSION_RESTART_REQUIRED'):
                recovery.acknowledge_restart(self.root, human_confirmed=True, run_id='RUN-FABRICATED-NEW')
        self.assertEqual(path.read_bytes(), before)
        with mock.patch.dict(os.environ, {'MXAGILE_RUN_ID': 'RUN-GENUINELY-NEW'}):
            result = recovery.acknowledge_restart(self.root, human_confirmed=True)
            self.assertEqual(result['run_id'], 'RUN-GENUINELY-NEW')
        with mock.patch.dict(os.environ, {'MXAGILE_RUN_ID': value['run_id']}):
            with self.assertRaisesRegex(ValueError, 'FRAMEWORK_OLD_SESSION_STALE'):
                recovery.require_restarted(self.root)
        self.assertFalse(recovery.restart_status(self.root)['restart_required'])

    def test_acknowledged_update_does_not_repeat_historical_restart_but_new_update_does(self):
        value, path = self.installed_restart()
        recovery.acknowledge_restart(self.root, human_confirmed=True)
        self.write('.mxagile/state/last-update-result.json', json.dumps({
            'restart_required': True, 'session_contract': {'state': 'SESSION_RESTART_REQUIRED'}}))
        self.assertFalse(recovery.restart_status(self.root)['restart_required'])
        updated = {**value, 'update_id': 'UPDATE-' + 'b' * 32, 'run_id': 'RUN-LATER-UPDATE'}
        path.write_text(json.dumps(updated))
        self.assertTrue(recovery.restart_status(self.root)['restart_required'])
        with self.assertRaisesRegex(ValueError, 'FRAMEWORK_SESSION_RESTART_REQUIRED'):
            recovery.require_restarted(self.root)

    def test_restart_recovery_loop_is_a_finding_not_another_restart_instruction(self):
        _, path = self.installed_restart()
        recovery.acknowledge_restart(self.root, human_confirmed=True)
        record = json.loads(path.read_bytes())
        record['restart_required'] = True
        path.write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, 'RESTART_RECOVERY_LOOP'):
            recovery.require_restarted(self.root)
        decision = self.hook('Edit', {'file_path': 'requirements/REQ-001.yml'})
        self.assertEqual(decision['decision'], 'deny')
        self.assertIn('RESTART_RECOVERY_LOOP', decision['reason'])
        self.assertNotEqual(decision['recovery'], 'restart')

    def test_installer_receipt_discovers_restart_without_store_and_new_same_commit_update(self):
        from datetime import datetime, timedelta
        value, path = self.installed_restart()
        path.unlink()
        self.core['installed_at'] = '2000-01-01T00:00:00+00:00'
        core_path = self.root / '.mxagile/state/core-provenance.json'
        core_path.write_text(json.dumps(self.core))
        receipt = {'restart_required': True, 'installed_at': self.core['installed_at'],
                   'framework': {'update_successful': True, 'commit': self.commit},
                   'update_attempt_id': value['update_id']}
        self.write('.mxagile/state/last-update-result.json', json.dumps(receipt))
        self.assertEqual(recovery.restart_status(self.root)['update_id'], value['update_id'])
        self.assertFalse(path.exists())
        self.assertIsNone(recovery.state(self.root)['run_id'])
        recovery.acknowledge_restart(self.root, human_confirmed=True)
        self.assertFalse(recovery.restart_status(self.root)['restart_required'])
        acknowledged = json.loads(path.read_bytes())
        self.core['installed_at'] = (datetime.fromisoformat(acknowledged['restart_acknowledged_at']) + timedelta(seconds=1)).isoformat()
        core_path.write_text(json.dumps(self.core))
        receipt.update(installed_at=self.core['installed_at'], update_attempt_id='UPDATE-' + 'b' * 32)
        self.write('.mxagile/state/last-update-result.json', json.dumps(receipt))
        later = recovery.restart_status(self.root)
        self.assertEqual(later['update_id'], receipt['update_attempt_id'])
        self.assertTrue(later['restart_required'])
        with self.assertRaisesRegex(ValueError, 'FRAMEWORK_SESSION_RESTART_REQUIRED'):
            recovery.require_restarted(self.root)

    def test_resync_only_followup_supersedes_pending_restart_and_keeps_history(self):
        old, path = self.installed_restart()
        self.core.update(commit='d' * 40, installed_at='2026-11-16T16:00:00+00:00')
        (self.root / '.mxagile/state/core-provenance.json').write_text(json.dumps(self.core))
        receipt = {'restart_required': False, 'resync_required': True, 'installed_at': self.core['installed_at'],
                   'framework': {'update_successful': True, 'commit': self.core['commit']},
                   'update_attempt_id': 'UPDATE-' + 'b' * 32}
        self.write('.mxagile/state/last-update-result.json', json.dumps(receipt))
        before = path.read_bytes()
        current = recovery.restart_status(self.root)
        self.assertEqual(current['update_id'], receipt['update_attempt_id'])
        self.assertFalse(current['restart_required'])
        self.assertEqual(path.read_bytes(), before)  # Discovery stays read-only.
        command = self.base + f' synchronize-update --project-root "{self.root}"'
        self.assertEqual(self.hook('Bash', {'command': command})['decision'], 'allow')
        synchronized = subprocess.run([sys.executable, '-B', str(self.tools / 'framework_update_recovery.py'),
                                       'synchronize-update', '--project-root', str(self.root)],
                                      capture_output=True, text=True, timeout=60)
        self.assertEqual(synchronized.returncode, 0, synchronized.stdout + synchronized.stderr)
        self.assertEqual(json.loads(synchronized.stdout)['update_id'], receipt['update_attempt_id'])
        self.assertEqual(recovery.acknowledge_restart(self.root)['result'], 'RESTART_NOT_REQUIRED')
        record = json.loads(path.read_bytes())
        self.assertEqual(record['commit'], self.core['commit'])
        self.assertEqual(record['history'][0]['record']['update_id'], old['update_id'])
        self.assertEqual(record['history'][0]['record']['commit'], old['commit'])
        self.assertEqual(record['history'][0]['disposition'], 'SUPERSEDED')
        self.assertFalse(record['history'][0]['record'].get('restart_progress', {}).get('resync_completed', False))
        before = path.read_bytes()
        recovery.synchronize_update(self.root)
        self.assertEqual(path.read_bytes(), before)
        for relative in recovery.CONTRACT_READS:
            if not (self.root / relative).is_file():
                self.write(relative, 'Recovery contract\n')
        doctor = subprocess.CompletedProcess([], 0, json.dumps({
            'stage': 'PROJECT_COMPATIBILITY_CHECKED', 'read_only': True, 'compatibility': 'COMPATIBLE'}), '')
        def invoke(args, **kwargs):
            if 'doctor' in args:
                return doctor
            self.write('.concord/context-epoch.yaml', 'current_update: B\n')
            return subprocess.CompletedProcess(args, 0, '', '')
        with mock.patch.object(recovery.subprocess, 'run', side_effect=invoke), mock.patch.object(
                recovery.compatibility, 'resync_preflight', return_value={'state': 'READY_FOR_RESYNC', 'reason_codes': []}):
            ready = recovery.recover_session(self.root, contracts_reloaded=True)
        self.assertEqual(ready['result'], 'READY')
        self.assertEqual(recovery.restart_status(self.root)['update_id'], receipt['update_attempt_id'])
        self.assertEqual(recovery.restart_status(self.root)['result'], 'READY')
        self.assertEqual(len(json.loads(path.read_bytes())['history']), 1)

    def test_followup_same_commit_recovery_is_idempotent_without_fabricated_restart(self):
        old, path = self.installed_restart()
        recovery.acknowledge_restart(self.root, human_confirmed=True)
        self.core['installed_at'] = '2099-01-01T00:00:00+00:00'
        (self.root / '.mxagile/state/core-provenance.json').write_text(json.dumps(self.core))
        self.write('.mxagile/state/last-update-result.json', json.dumps({
            'restart_required': False, 'resync_required': True, 'installed_at': self.core['installed_at'],
            'framework': {'update_successful': True, 'commit': old['commit']},
            'update_attempt_id': 'UPDATE-' + 'b' * 32}))
        with self.assertRaisesRegex(ValueError, 'CONTRACT_RELOAD_REQUIRED'):
            recovery.recover_session(self.root)
        record = json.loads(path.read_bytes())
        self.assertEqual(record['update_id'], 'UPDATE-' + 'b' * 32)
        self.assertEqual(record['commit'], old['commit'])
        self.assertEqual(record['restart_requirement'], 'NOT_REQUIRED')
        self.assertNotIn('restart_observation', record)
        self.assertNotIn('restart_reference', record)
        self.assertFalse(any(recovery.restart_progress(record)[stage] for stage in recovery.RESTART_STAGES[:3]))
        before = path.read_bytes()
        recovery.synchronize_update(self.root)
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(len(record['history']), 1)

    def test_partial_followup_does_not_supersede_pending_restart(self):
        old, path = self.installed_restart()
        self.write('.mxagile/state/update-transaction.json', json.dumps({'state': 'PARTIAL_UPDATE'}))
        self.core.update(commit='d' * 40, installed_at='2026-11-16T16:00:00+00:00')
        (self.root / '.mxagile/state/core-provenance.json').write_text(json.dumps(self.core))
        self.write('.mxagile/state/last-update-result.json', json.dumps({
            'restart_required': False, 'resync_required': True, 'installed_at': self.core['installed_at'],
            'framework': {'update_successful': True, 'commit': self.core['commit']},
            'update_attempt_id': 'UPDATE-' + 'b' * 32}))
        before = path.read_bytes()
        self.assertEqual(recovery.state(self.root)['update_id'], old['update_id'])
        with self.assertRaisesRegex(ValueError, 'UPDATE_RECOVERY_PARTIAL'):
            recovery.synchronize_update(self.root)
        self.assertEqual(path.read_bytes(), before)

    def test_invalid_restart_receipt_is_a_structured_blocker(self):
        self.installed_restart()
        for receipt in ([], {'restart_required': True, 'framework': []},
                        {'restart_required': True, 'framework': {'update_successful': True, 'commit': self.commit},
                         'update_attempt_id': 'UPDATE-' + 'b' * 32, 'update_transaction': []}):
            with self.subTest(receipt=receipt):
                self.write('.mxagile/state/last-update-result.json', json.dumps(receipt))
                with self.assertRaisesRegex(ValueError, 'UPDATE_RECOVERY_STATE_INVALID'):
                    recovery.restart_status(self.root)

    def test_complete_recovery_records_stages_and_preserves_concrete_blockers(self):
        _, path = self.installed_restart()
        for relative in recovery.CONTRACT_READS:
            if not (self.root / relative).is_file():
                self.write(relative, 'Recovery contract\n')
        self.core['artifact_contract'] = self.compatibility.contract_snapshot(self.root)
        (self.root / '.mxagile/state/core-provenance.json').write_text(json.dumps(self.core))
        recovery.acknowledge_restart(self.root, human_confirmed=True)
        with self.assertRaisesRegex(ValueError, 'CONTRACT_RELOAD_REQUIRED'):
            recovery.recover_session(self.root)
        doctor = {'stage': 'PROJECT_COMPATIBILITY_CHECKED', 'read_only': True, 'compatibility': 'BLOCKED'}
        calls = []
        def invoke(args, **kwargs):
            calls.append(args)
            if 'doctor' in args:
                code = 2 if doctor['compatibility'] == 'BLOCKED' else 0
                return subprocess.CompletedProcess(args, code, json.dumps(doctor), '')
            self.write('.concord/context-epoch.yaml', 'recovered: true\n')
            return subprocess.CompletedProcess(args, 0, '', '')
        preflight = {'state': 'RECONCILIATION_REQUIRED', 'reason_codes': ['MIGRATION_INCOMPLETE']}
        with mock.patch.object(recovery.subprocess, 'run', side_effect=invoke), mock.patch.object(
                recovery.compatibility, 'resync_preflight', return_value=preflight):
            blocked = recovery.recover_session(self.root, contracts_reloaded=True)
            self.assertFalse(blocked['restart_required'])
            self.assertIn('MIGRATION_INCOMPLETE', blocked['reason_codes'])
            self.assertEqual(len(calls), 1)
            progress = json.loads(path.read_bytes())['restart_progress']
            self.assertTrue(progress['doctor_completed'])
            self.assertFalse(progress['resync_completed'])
            doctor['compatibility'] = 'COMPATIBLE'
            preflight.update(state='READY_FOR_RESYNC', reason_codes=[])
            ready = recovery.recover_session(self.root, contracts_reloaded=True)
        self.assertEqual(ready['result'], 'READY')
        self.assertTrue(all(ready['restart_progress'].values()))
        self.assertIn('-PreserveEvidence', calls[-1])
        self.assertEqual(json.loads(path.read_bytes())['contract_reload']['state'], 'DECLARED')
        self.assertEqual(recovery.restart_status(self.root)['next_action'], 'normal_lifecycle_resync')
        before = path.read_bytes()
        self.assertEqual(recovery.acknowledge_restart(self.root)['result'], 'ALREADY_ACKNOWLEDGED')
        with mock.patch.object(recovery.subprocess, 'run') as runner:
            self.assertEqual(recovery.recover_session(self.root)['result'], 'READY')
            runner.assert_not_called()
        self.assertEqual(path.read_bytes(), before)

    def test_recovery_reports_missing_contract_failed_doctor_and_failed_writer_without_restart(self):
        _, path = self.installed_restart()
        recovery.acknowledge_restart(self.root, human_confirmed=True)
        for relative in recovery.CONTRACT_READS:
            if not (self.root / relative).is_file():
                self.write(relative, 'Recovery contract\n')
        (self.root / 'AGENT.md').unlink()
        with self.assertRaisesRegex(ValueError, 'CONTRACT_RELOAD_REQUIRED'):
            recovery.recover_session(self.root, contracts_reloaded=True)
        self.write('AGENT.md', 'Recovery contract\n')
        for failure in (OSError('not executable'), subprocess.TimeoutExpired('doctor', 300),
                        subprocess.CompletedProcess([], 1, 'invalid json', '')):
            with self.subTest(failure=failure):
                kwargs = {'side_effect': failure} if isinstance(failure, Exception) else {'return_value': failure}
                with mock.patch.object(recovery.subprocess, 'run', **kwargs):
                    with self.assertRaisesRegex(ValueError, 'DOCTOR_UNAVAILABLE'):
                        recovery.recover_session(self.root, contracts_reloaded=True)
                self.assertFalse(recovery.restart_status(self.root)['restart_required'])
        doctor = subprocess.CompletedProcess([], 0, json.dumps({
            'stage': 'PROJECT_COMPATIBILITY_CHECKED', 'read_only': True, 'compatibility': 'COMPATIBLE'}), '')
        for failure in (subprocess.CompletedProcess([], 1, '', 'failed'), OSError('missing pwsh')):
            with self.subTest(writer=failure):
                with mock.patch.object(recovery.subprocess, 'run', side_effect=[doctor, failure]), mock.patch.object(
                        recovery.compatibility, 'resync_preflight', return_value={'state': 'READY_FOR_RESYNC', 'reason_codes': []}):
                    with self.assertRaisesRegex(ValueError, 'RESYNC_NOT_COMPLETED'):
                        recovery.recover_session(self.root, contracts_reloaded=True)
                record = json.loads(path.read_bytes())
                self.assertTrue(record['restart_progress']['doctor_completed'])
                self.assertFalse(record['restart_progress']['resync_completed'])
                self.assertFalse(recovery.restart_status(self.root)['restart_required'])

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


class UpdateHandoffTests(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.workspace = tempfile.TemporaryDirectory(prefix='mxagile-update-result-')
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.state_dir = self.root / '.mxagile/state'
        self.state_dir.mkdir(parents=True)
        self.repo = GUARD_DIR.parents[1]

    def run_powershell(self, body):
        def quote(value):
            return "'" + str(value).replace("'", "''") + "'"
        script = f"$ErrorActionPreference='Stop'; $root={quote(self.root)}; $repo={quote(self.repo)}; " + r'''
. (Join-Path $repo 'scripts/update-transaction.ps1')
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'scripts/install-core.ps1'),[ref]$tokens,[ref]$errors)
$function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-PostUpdateCompatibility'},$true)
Invoke-Expression $function.Extent.Text
$transaction=New-MxAgileCoreUpdateTransaction -Root $root -TargetCore @{commit=('b'*40);version='2';source='fixture-core';ref='fixture-ref'}
$transaction.completed_stages=@('CORE_UPDATE','GENERATED_PROJECTIONS')
$core=@{commit=('b'*40);version='2';installed_at='2026-11-15T00:00:00Z';install_mode='update';previous_version='1';previous_commit=('a'*40)}
$core | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root '.mxagile/state/core-provenance.json')
''' + body + "\nWrite-Output 'FIXTURE_VALIDATED'\n"
        result = subprocess.run(['pwsh', '-NoProfile', '-Command', script], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_company_handoff_never_merges_previous_generation(self):
        previous = {'schema_version': 1, 'installed_at': 'old', 'framework': {'commit': 'a' * 40, 'update_successful': True},
                    'migration': {'status': 'COMPLETE'}, 'completed_stages': ['DOCTOR'], 'restart_required': False,
                    'update_transaction': {'update_attempt_id': 'OLD'}, 'unknown_historical_field': 'old'}
        handoff = self.state_dir / 'last-update-result.json'
        handoff.write_text(json.dumps(previous))
        # Exercise the public adapter; it must delegate to the canonical writer.
        self.run_powershell(r'''
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'mxagile-setup-company-layer.ps1'),[ref]$tokens,[ref]$errors)
$function=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Save-UpdateHandoff'},$true)
Invoke-Expression $function.Extent.Text
$ProjectRoot=$root
$transaction.state='PARTIAL_UPDATE'; $transaction.restart_required=$true
$core | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root '.mxagile/state/core-provenance.json')
$doctor=@{executed=$false;compatibility='NOT_VERIFIED';reason='PROJECTIONS_INCOMPLETE'}
Save-UpdateHandoff -Transaction $transaction -Doctor $doctor
''')
        value = json.loads(handoff.read_bytes())
        self.assertEqual(value['framework']['commit'], 'b' * 40)
        self.assertFalse(value['framework']['update_successful'])
        self.assertEqual(value['installed_at'], '2026-11-15T00:00:00Z')
        self.assertEqual(value['migration']['status'], 'NOT_VERIFIED')
        self.assertNotIn('DOCTOR', value['completed_stages'])
        self.assertNotIn('unknown_historical_field', value)
        self.assertEqual(value['update_attempt_id'], value['update_transaction']['update_attempt_id'])
        self.assertTrue(value['restart_required'])
        self.assertEqual(value['session_contract']['state'], 'SESSION_RESTART_REQUIRED')

    def test_core_completion_rejects_another_attempt_even_at_same_commit(self):
        self.run_powershell(r'''
Invoke-PostUpdateCompatibility -Root $root -ToolsDir $root -CoreProvenance $core -Transaction $transaction | Out-Null
$transaction.update_attempt_id='UPDATE-another-attempt'
$before=[IO.File]::ReadAllText((Join-Path $root '.mxagile/state/last-update-result.json'))
try { Complete-MxAgileCoreUpdateTransaction -Root $root -Transaction $transaction; throw 'accepted stale handoff' }
catch { if ($_.Exception.Message -notmatch 'UPDATE_RESULT_GENERATION_MISMATCH') { throw } }
if ([IO.File]::ReadAllText((Join-Path $root '.mxagile/state/last-update-result.json')) -ne $before) { throw 'stale handoff changed' }
''')

    def test_core_handoff_persistence_failure_is_not_success(self):
        self.run_powershell(r'''
New-Item -ItemType Directory -Path (Join-Path $root '.mxagile/state/last-update-result.json') | Out-Null
try { Invoke-PostUpdateCompatibility -Root $root -ToolsDir $root -CoreProvenance $core -Transaction $transaction; throw 'accepted missing result' }
catch { if ($_.Exception.Message -notmatch 'UPDATE_RESULT_PERSISTENCE_FAILED') { throw } }
''')

    def test_dedicated_restart_console_matches_persisted_result(self):
        output = self.run_powershell(r'''
New-Item -ItemType Directory -Path (Join-Path $root '.mxagile/state/runs') -Force | Out-Null
@{restart_required=$true;commit=$core.commit} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root '.mxagile/state/runs/framework-update-recovery.json')
Invoke-PostUpdateCompatibility -Root $root -ToolsDir $root -CoreProvenance $core -Transaction $transaction
Complete-MxAgileCoreUpdateTransaction -Root $root -Transaction $transaction
''')
        self.assertIn('SESSION_CONTRACT: SESSION_RESTART_REQUIRED', output)
        self.assertNotIn('Report CONTRACTS_RE_SYNCED', output)
        self.assertNotIn('same-session contract re-sync', output)
        value = json.loads((self.state_dir / 'last-update-result.json').read_bytes())
        self.assertEqual(value['update_attempt_id'], value['update_transaction']['update_attempt_id'])
        self.assertTrue(value['restart_required'])


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
            for relative in ('.mxagile/policies/project-compatibility.md', '.mxagile/policies/lifecycle-resync.md',
                             '.mxagile/policies/update-contract.md', '.mxagile/policies/agent-delegation.md',
                             '.mxagile/agents/diagnostic-agent.md', '.mxagile/schemas/delegation-handoff.schema.json',
                             '.mxagile/schemas/finding.schema.json', '.mxagile/schemas/project-timeline.schema.json',
                             'scripts/wave_ids.py', 'scripts/framework_update_recovery.py', 'scripts/install-core.ps1',
                             'scripts/update-transaction.ps1', 'scripts/setup-agent-system.ps1', 'scripts/project_compatibility.py',
                             'scripts/apply-project-agent-instructions.ps1', 'scripts/generate-mxagile-platform-skills.ps1',
                             'experiments/control-plane/child_contract.py', 'experiments/control-plane/guard.py',
                             'experiments/control-plane/enforcement.py', 'experiments/control-plane/control-plane-verdict.schema.json'):
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
            installed_core = json.loads(core_path.read_bytes())
            self.assertEqual(installed_core['product_flavor'], 'fixture-product')
            self.assertEqual(installed_core['flavor'], 'fixture-product')
            self.assertEqual(installed_core['installation_flavor'], 'company-layer')
            self.assertEqual(installed_core['source'], str(candidate))
            self.assertEqual(installed_core['source_type'], 'git')
            self.assertEqual(installed_core['ref'], 'recovery-fixture')
            self.assertEqual(installed_core['commit'], commit)
            self.assertEqual(installed_core['source_identity'], f'git:{candidate}#{commit}')
            self.assertEqual(handoff['framework']['version'], installed_core['version'])
            self.assertEqual(handoff['update_attempt_id'], handoff['update_transaction']['update_attempt_id'])
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
            status_args = [sys.executable, '-B', str(installed), 'restart-status', '--project-root', str(self.root)]
            self.assertEqual(hook('Bash', {'command': installed_command + f' restart-status --project-root "{self.root}"'}), 'allow')
            pending = json.loads(run(status_args))
            self.assertEqual(pending['update_id'], update['update_id'])
            self.assertEqual(pending['next_action'], 'confirm_actual_host_restart')
            # Fixture boundary evidence only: this is not a live host-session restart attestation.
            env['MXAGILE_RUN_ID'] = 'RUN-LEGACY-OLDSESSION'
            ack_args = [sys.executable, '-B', str(installed), 'acknowledge-restart', '--project-root', str(self.root), '--human-confirmed']
            denied_old = json.loads(run(ack_args, 3))
            self.assertEqual(denied_old['code'], 'FRAMEWORK_SESSION_RESTART_REQUIRED')
            env['MXAGILE_RUN_ID'] = 'RUN-FIXTURE-NEWSESSION'
            ack_command = installed_command + f' acknowledge-restart --project-root "{self.root}" --human-confirmed'
            self.assertEqual(hook('Bash', {'command': ack_command}), 'allow')
            acknowledged = json.loads(run(ack_args))
            self.assertEqual(acknowledged['update_id'], pending['update_id'])
            for relative in acknowledged['contract_reads']:
                self.assertTrue((self.root / relative).read_bytes(), relative)
            recovery_args = [sys.executable, '-B', str(installed), 'recover-session', '--project-root', str(self.root), '--contracts-reloaded']
            recovery_command = installed_command + f' recover-session --project-root "{self.root}" --contracts-reloaded'
            self.assertEqual(hook('Bash', {'command': recovery_command}), 'allow')
            remaining = json.loads(run(recovery_args))
            self.assertEqual(remaining['result'], 'RECONCILIATION_REQUIRED')
            self.assertFalse(remaining['restart_required'])
            self.assertTrue(remaining['reason_codes'])
            self.assertEqual(json.loads(run(status_args))['next_action'], 'read_contracts_then_recover_session')
            resolved = json.loads(run([sys.executable, '-B', str(doctor), 'resolve', *resolve_args]))
            self.assertEqual(resolved['migration']['status'], 'COMPLETE')
            self.assertTrue(resolved['doctor']['executed'])
            self.assertNotEqual(resolved['doctor']['compatibility'], 'BLOCKED')
            blocked()
            for relative in json.loads(run(status_args))['contract_reads']:
                self.assertTrue((self.root / relative).read_bytes(), relative)
            ready = json.loads(run(recovery_args))
            self.assertEqual(ready['result'], 'READY')
            self.assertTrue(all(ready['restart_progress'].values()))
            self.assertFalse(ready['delivery_authorized'])
            receipt_path = self.root / recovery.STATE
            completed_receipt = receipt_path.read_bytes()
            env['MXAGILE_RUN_ID'] = 'RUN-ANOTHER-NEWSESSION'
            self.assertEqual(json.loads(run(status_args))['result'], 'READY')
            self.assertEqual(json.loads(run(ack_args))['result'], 'ALREADY_ACKNOWLEDGED')
            self.assertEqual(json.loads(run(recovery_args))['result'], 'READY')
            self.assertEqual(receipt_path.read_bytes(), completed_receipt)
            self.assertTrue(json.loads((self.root / '.mxagile/state/last-update-result.json').read_bytes())['restart_required'])
            for relative in ('CLAUDE.md', 'AGENTS.md', '.github/copilot-instructions.md'):
                startup = (self.root / relative).read_text(encoding='utf-8-sig')
                self.assertLess(startup.index('Pending restart recovery'), startup.index('1. **Lifecycle Re-Sync FIRST**'))
                self.assertIn('recover-session', startup)
                self.assertIn('operational restart receipt supersedes', startup)
            # Existing canonical guard derives readiness; Auxiliary/Update never promotes the Wave.
            facts = enforcement.guard.load_project_facts(self.root)
            verdict = enforcement.guard.delivery_authorization(facts, enforcement.DELIVERY_WRITE, require_implementing=False)
            self.assertEqual(verdict['verdict'], 'pass', verdict['must_findings'])
            self.assertEqual(facts.process_state['waves']['W01']['phase'], 'ready')


if __name__ == '__main__':
    unittest.main()
