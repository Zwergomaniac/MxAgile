"""Phase 1B: mandatory enforcement, visual gate, child transition contract and reality regressions."""

from __future__ import annotations

import hashlib
import json
import shutil
import tempfile
import subprocess
import sys
from pathlib import Path
from unittest import mock

import unittest

from test_control_plane_guard import AUTHORIZED, MISSION, GuardFixture, _git

GUARD_DIR = Path(__file__).resolve().parents[1] / "experiments" / "control-plane"
sys.path.insert(0, str(GUARD_DIR))
import child_contract  # noqa: E402
import enforcement  # noqa: E402

LIVE = {"operating_mode": "LIVE-SP-CURRENT", "project_identity_confirmed": True, "observed_at": "2026-11-11T10:00:00Z"}
CLOSED = {**LIVE, "operating_mode": "CLOSED-AUTONOM"}


class Phase1BFixture(GuardFixture):
    def setUp(self) -> None:
        super().setUp()
        self.write(".gitignore", ".concord/\n.mxagile/state/runs/\n")
        self.write("input-resources/ui-ux/orders/index.html", "<html>orders REV-037</html>\n")
        self.write("docs/fixture/REQ-001.md", "Orders overview shows a filter.\n")
        self.write("docs/fixture/DEC-001.md", "Modal confirms deletion.\n")
        self.write("javascriptsource/orders/overview.js", "export const overview = 1;\n")
        _git(self.root, "add", "-A")
        _git(self.root, "commit", "-qm", "visual inputs")
        self.resync()
        self.contract = {
            "mockup": {"identity": "REV-037", "path": "input-resources/ui-ux/orders/index.html"},
            "requirements": [{"id": "REQ-001", "path": "docs/fixture/REQ-001.md"}],
            "decisions": [{"id": "DEC-001", "path": "docs/fixture/DEC-001.md"}],
            "page": {"identity": "Orders.OrderOverview", "path": "javascriptsource/orders/overview.js"},
            "implementation_paths": ["javascriptsource/orders/overview.js"],
            "roles": ["User"], "states": ["default", "modal_open"],
            "evidence_destination": ".concord/evidence/visual", "max_rounds": 2,
        }

    def hook(self, tool_name: str, tool_input: dict) -> dict:
        return enforcement.decide(self.root, {"tool_name": tool_name, "tool_input": tool_input, "cwd": str(self.root)})

    def visual_handoff(self, observations: dict = CLOSED, parent_run_id: str | None = None,
                       delegation_id: str = "DELEGATION-V1") -> dict:
        facts = enforcement.guard.load_project_facts(self.root)
        handoff = child_contract.build_visual_handoff(
            facts, self.contract, agent_type="mxagile-ui-agent", delegation_id=delegation_id,
            route_decision_reference=".concord/routing-decisions/ROUTE-V1.json", parent_observations=observations,
            parent_run_id=parent_run_id)
        route = {
            "schema_version": "1.0", "mission_id": MISSION, "decision_id": "ROUTE-V1", "recorded_at": "2026-11-11T10:00:00Z",
            "session_identity": None, "work_package": handoff["delivery_context"]["work_package_id"],
            "requested_agent_type": "mxagile-ui-agent", "work_class": "bounded_semantic", "scope": handoff["scope"],
            "artifact_count": len(handoff["scope"]["paths"]), "semantic": True, "deterministic": False,
            "capability_state": "supported", "requested_profile": "MID", "route": "DELEGATE", "reason": "runtime visual verification",
            "fallback_reason": None, "delegation_attempted": False, "spawn_outcome": "pending", "delegation_id": delegation_id,
            "result_reference": None, "main_consumed": False, "compaction_occurred": False, "result_reused": False,
            "stale_result_rejected": False, "batch_restarted": False, "source_fingerprints": handoff["source_fingerprints"],
        }
        self.write(".concord/routing-decisions/ROUTE-V1.json", json.dumps(route))
        self.write(f".concord/delegation-handoffs/{delegation_id}.json", json.dumps(handoff))
        return handoff

    def evidence(self, state: str, layer: str = "runtime", role: str = "User") -> dict:
        relative = f".concord/evidence/visual/{role}-{state}-{layer}.png"
        path = self.write(relative, f"png {role} {state} {layer}")
        return {"role": role, "state": state, "kind": "screenshot", "layer": layer, "path": relative,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

    def verdict(self, handoff: dict, evidence: list[dict], *, claim: str = "pass", must=(), should=(), round_number: int = 1,
                mode: str = "runtime") -> dict:
        finding = lambda code: {"code": code, "summary": code.replace("_", " "), "disposition": "fail"}
        return {
            "schema_version": "1.0", "gate_id": "GATE-visual-orders", "gate_type": "visual_verification", "verdict": claim,
            "run_id": handoff["run_id"], "mission_id": MISSION, "wave_id": "W01", "producer": "mxagile-ui-agent",
            "input_references": [], "evidence_references": [], "must_findings": [finding(code) for code in must],
            "should_findings": [{**finding(code), "disposition": "advisory"} for code in should],
            "scope": {"summary": "visual", "paths": []}, "checked_roles": ["User"], "checked_states": ["default", "modal_open"],
            "created_at": "2026-11-11T10:00:00Z", "round": round_number,
            "visual": {"mockup_revision": "REV-037", "page": "Orders.OrderOverview", "html_first_source": "javascriptsource/orders/overview.js",
                       "route": "/p/orders", "roles": ["User"], "states": ["default", "modal_open"], "requirements": ["REQ-001"],
                       "decisions": ["DEC-001"], "verification_mode": mode, "evidence": evidence,
                       "input_fingerprint": child_contract.input_fingerprint(self.root, self.contract)},
        }


class BlockedRealityTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='mxagile-blocked-reality-'))
        self.facts = enforcement.guard.ProjectFacts(root=self.root)
        self.facts.mission = {'mission_id': 'MISSION-fixture', 'active_wave': 'W01', 'progress': {'mission': 'active'}}
        self.facts.process_state = {'waves': {'W01': {'phase': 'implementing'}}}
        self.facts.planned_waves = {'W01'}
        self.facts.branch = 'dev/current'
        self.facts.head = 'b' * 40
        self.facts.context_epoch = {'mission': {'id': 'MISSION-old'}, 'repository': {'branch': 'dev/old', 'commit': 'a' * 40, 'checkpoint_time': '2026-01-01T00:00:00Z'}}
        self.facts.doctor_compatibility = 'BLOCKED'
        self.facts.doctor_blocking = ['REFERENCE_MISSING']
        self.facts.core_provenance = {'installed_at': '2026-01-02T00:00:00Z', 'commit': 'b' * 40}

    def tearDown(self):
        shutil.rmtree(self.root)

    def decide(self, tool, values):
        with mock.patch.object(enforcement.guard, 'load_project_facts', return_value=self.facts), mock.patch.object(enforcement, '_persist_event'):
            return enforcement.decide(self.root, {'tool_name': tool, 'tool_input': values})

    def test_all_normal_consumer_writes_are_blocked(self):
        for path in ('requirements/REQ-001.yml', 'planning/decisions/DEC-001.yml', 'planning/mission/mission-state.yaml', 'planning/lifecycle/process-state.yaml', 'planning/tasks/TASK-001.yml', '.mxagile/migration/state.yaml', '.mxagile/state/core-provenance.json', 'planning/evidence/proof.json', 'javascriptsource/example.js'):
            with self.subTest(path=path):
                self.assertEqual(self.decide('Write', {'file_path': path})['decision'], 'deny')
        self.assertEqual(self.decide('Bash', {'command': 'python project_compatibility.py repair --apply --plan-hash x'})['decision'], 'deny')

    def test_stdout_sed_reads_and_mutating_sed_are_distinguished(self):
        for command in ("sed -n '1,20p' file", "sed 's/a/b/' file", "sed -n '1,20p' file | head -5"):
            with self.subTest(command=command):
                self.assertEqual(enforcement.classify_shell(self.root, command), enforcement.READ)
                self.assertEqual(self.decide('Bash', {'command': command})['decision'], 'allow')
        for command in ("sed -i 's/a/b/' file", "sed 's/a/b/' file > requirements/REQ-001.yml", "sed 's/a/b/w output' file", "sed -n '1,20p' file && rm requirements/REQ-001.yml"):
            with self.subTest(command=command):
                self.assertEqual(self.decide('Bash', {'command': command})['decision'], 'deny')

    def test_mxcli_help_syntax_and_doctor_are_reads_not_word_matches(self):
        for command in ('mxcli help exec', 'mxcli syntax create-page', 'mxcli --version', 'mxcli lint', 'python project_compatibility.py doctor --format json', 'git status', 'git log -1'):
            with self.subTest(command=command):
                self.assertEqual(enforcement.classify_shell(self.root, command), enforcement.READ)
        self.assertEqual(self.decide('Bash', {'command': 'mxcli exec changes.mdl'})['decision'], 'deny')

    def test_unobserved_dispatcher_and_taskstop_remain_closed(self):
        for tool in ('mcp__concord-v2-mcp__concord_invoke', 'mcp__mendix-studio-pro__execute_handler', 'TaskStop'):
            self.assertEqual(self.decide(tool, {'read_only': True})['decision'], 'deny')
        for tool in ('mcp__concord-v2-mcp__concord_discover', 'mcp__mendix-studio-pro__list_modules', 'mcp__mendix-studio-pro__query_handlers'):
            self.assertEqual(self.decide(tool, {})['decision'], 'allow')

    def test_inner_operation_requires_out_of_band_evidence(self):
        payload = {'tool_name': 'mcp__concord-v2-mcp__concord_invoke', 'tool_input': {'inner': {'operation': 'fixture.inspect', 'args': {}}}}
        def classify(tool, values):
            inner = values.get('inner', {})
            return enforcement.READ if inner == {'operation': 'fixture.inspect', 'args': {}} else enforcement.IMPLEMENTATION_WRITE
        evidence = enforcement.HostBoundaryEvidence(classify_dispatch=classify)
        self.assertEqual(enforcement.classify_tool_call(self.root, payload, evidence)[0], enforcement.READ)
        self.assertEqual(enforcement.classify_tool_call(self.root, payload)[0], enforcement.IMPLEMENTATION_WRITE)
        payload['tool_input']['inner']['args']['apply'] = True
        self.assertEqual(enforcement.classify_tool_call(self.root, payload, evidence)[0], enforcement.IMPLEMENTATION_WRITE)

    def test_doctor_precedes_resync_in_recovery(self):
        result = self.decide('Write', {'file_path': 'requirements/REQ-001.yml'})
        self.assertEqual(result['recovery'], 'doctor')
        self.assertIn('resync', result['verdict']['recovery_plan']['blocked_recovery_actions'])

    def test_migration_and_missing_decision_precede_resync(self):
        self.facts.doctor_diagnostics = [{'diagnostic_id': 'DX-0000000000000001', 'source_path': 'requirements/REQ-001.yml', 'authority': 'superseded_by', 'category': 'REFERENCE_MISSING', 'repairability': 'DECISION_REQUIRED'}]
        result = self.decide('Write', {'file_path': 'requirements/REQ-001.yml'})
        self.assertEqual(result['recovery'], 'human_resolution')
        self.assertEqual(result['verdict']['recovery_plan']['decision_references'][0]['authority'], 'superseded_by')
        self.facts.migration_state = {'status': 'in_progress', 'artifact_canonicalization': 'in_progress'}
        self.assertEqual(self.decide('Write', {'file_path': 'requirements/REQ-001.yml'})['recovery'], 'resume')

    def test_epoch_resync_precedes_delivery_phase_re_evaluation(self):
        findings = [enforcement.guard._finding('CONTEXT_STALE_AFTER_UPDATE', 'stale', 'unavailable', recovery='resync'),
                    enforcement.guard._finding('MUTATION_PHASE_BLOCKED', 'ready', 'fail', recovery='human_resolution')]
        self.assertEqual(enforcement.guard._recovery_plan(self.facts, findings)['primary_next_action'], 'resync')

    def test_missing_current_provenance_is_unobservable_not_current(self):
        self.facts.core_provenance = {}
        self.facts.last_update = {'installed_at': '2026-01-02T00:00:00Z'}
        findings, _ = enforcement.guard._lifecycle_integrity(self.facts)
        self.assertIn('UPDATE_IDENTITY_NOT_OBSERVABLE', {f['code'] for f in findings})
        self.assertNotIn('CONTEXT_STALE_AFTER_UPDATE', {f['code'] for f in findings})

    def test_shell_quotes_cannot_hide_mutations_or_relabel_command_payloads(self):
        for command in ('cat file\nrm requirements/REQ-001.yml', 'echo text >& requirements/REQ-001.yml', 'cat <(rm file)', 'mxcli lint --fix', 'git branch -D other', 'python -c "print(1)" project_compatibility.py doctor'):
            with self.subTest(command=command):
                self.assertEqual(self.decide('Bash', {'command': command})['decision'], 'deny')
        self.assertEqual(enforcement.classify_shell(self.root, "sed -n '1,20p' 'path with spaces; name'"), enforcement.READ)

    def test_historical_update_result_cannot_override_current_provenance(self):
        self.facts.doctor_compatibility = 'COMPATIBLE'
        self.facts.context_epoch['repository']['checkpoint_time'] = '2026-01-03T00:00:00Z'
        self.facts.last_update = {'installed_at': '2026-01-10T00:00:00Z', 'framework': {'commit': 'a' * 40}}
        self.facts.core_provenance = {'installed_at': '2026-01-02T00:00:00Z', 'commit': 'b' * 40}
        findings, _ = enforcement.guard._lifecycle_integrity(self.facts)
        self.assertNotIn('CONTEXT_STALE_AFTER_UPDATE', {f['code'] for f in findings})
        self.facts.core_provenance['installed_at'] = '2026-01-04T00:00:00Z'
        findings, _ = enforcement.guard._lifecycle_integrity(self.facts)
        self.assertIn('CONTEXT_STALE_AFTER_UPDATE', {f['code'] for f in findings})


class RecoveryScopeTests(Phase1BFixture):
    def recovery_tools(self):
        enforcement.guard._run_doctor(enforcement.guard.ProjectFacts(root=self.root))
        import project_compatibility
        tools = self.root / '.mxagile' / 'tools'
        tools.mkdir(parents=True, exist_ok=True)
        sources = GUARD_DIR.parents[1] / 'scripts'
        for name in ('project_compatibility.py', 'projection_io.py', 'wave_ids.py', 'run_events.py', 'build_project_status.py', 'reconciliation_git.py', 'build_project_timeline.py', 'Write-MxAgileEpochCheckpoint.ps1'):
            shutil.copyfile(sources / name, tools / name)
        hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in tools.iterdir() if p.is_file()}
        self.write('.mxagile/state/core-provenance.json', json.dumps({'installed_at': '2020-01-01T00:00:00Z', 'commit': _git(self.root, 'rev-parse', 'HEAD'), 'artifact_contract': project_compatibility.contract_snapshot(self.root), 'recovery_tools': hashes}))
        self.write_yaml('.mxagile/migration/state.yaml', {'status': 'complete', 'artifact_canonicalization': 'complete'})
        return tools, project_compatibility

    def test_only_integrity_bound_safe_contract_helper_can_run_while_blocked(self):
        tools, _ = self.recovery_tools()
        command = f'python -B "{tools / "project_compatibility.py"}" migrate --apply-safe --project-root "{self.root}" --format json'
        allowed = self.hook('Bash', {'command': command})
        self.assertEqual(allowed['decision'], 'allow', allowed)
        self.assertEqual(allowed['controlled_recovery'], 'contract_reconciliation')
        self.assertEqual(self.hook('Write', {'file_path': 'requirements/REQ-002.yml'})['decision'], 'deny')
        for altered in (command + ' && mxcli exec changes.mdl', command + ' --candidate-dir elsewhere', command + ' > output.json'):
            self.assertEqual(self.hook('Bash', {'command': altered})['decision'], 'deny')
        with (tools / 'project_compatibility.py').open('a', encoding='utf-8') as stream:
            stream.write('\n# tampered\n')
        self.assertEqual(self.hook('Bash', {'command': command})['decision'], 'deny')

    def human_resolution_request(self):
        tools, compatibility = self.recovery_tools()
        self.write_yaml('requirements/REQ-001.yml', {'ID': 'REQ-001', 'title': 'Old', 'description': 'Old behavior', 'status': 'superseded'})
        self.write_yaml('requirements/REQ-068.yml', {'ID': 'REQ-068', 'title': 'Current', 'description': 'Current behavior', 'status': 'accepted'})
        compatibility.reconcile_contract(self.root, apply_safe=True)
        contract = compatibility.human_resolution_contracts(self.root)[0]
        request = {'diagnostic_id': contract['diagnostic_id'], 'migration_id': contract['migration_id'],
                   'source_path': contract['source_path'], 'field': contract['field'],
                   'source_fingerprint': contract['current_source_fingerprint'], 'value': 'REQ-068',
                   'human_reference': 'USER-FIXTURE-SUCCESSOR', 'human_confirmed': True, 'run_id': 'RUN-HUMAN-FIXTURE'}
        def command(values):
            args = ' '.join(f'--{key.replace("_", "-")} "{value}"' for key, value in values.items() if key != 'human_confirmed')
            confirmed = ' --human-confirmed' if values.get('human_confirmed') else ''
            return f'python -B "{tools / "project_compatibility.py"}" resolve --project-root "{self.root}" --format json {args}{confirmed}'
        return compatibility, request, command

    def test_only_bound_human_resolution_receives_recovery_authority(self):
        compatibility, request, command = self.human_resolution_request()
        allowed = self.hook('Bash', {'command': command(request)})
        self.assertEqual(allowed['decision'], 'allow', allowed)
        self.assertEqual(allowed['operation_class'], enforcement.HUMAN_RESOLUTION_WRITE)
        cases = ({'human_confirmed': False}, {'human_reference': ''}, {'diagnostic_id': 'DX-wrong'},
                 {'source_path': 'requirements/REQ-068.yml'}, {'field': 'status'},
                 {'source_fingerprint': 'sha256:' + '0' * 64}, {'value': 'REQ-999'}, {'value': 'not-a-requirement'})
        for changes in cases:
            with self.subTest(changes=changes):
                self.assertEqual(self.hook('Bash', {'command': command({**request, **changes})})['decision'], 'deny')
        for changed in (command(request) + ' && python -c "print(1)"', command(request) + ' > result.json', command(request) + ' --candidate-dir elsewhere'):
            self.assertEqual(self.hook('Bash', {'command': changed})['decision'], 'deny')
        for path in ('requirements/REQ-001.yml', 'requirements/REQ-068.yml', 'planning/mission/mission-state.yaml', 'planning/lifecycle/process-state.yaml', '.concord/context-epoch.yaml', '.mxagile/migration/state.yaml'):
            for tool in ('Write', 'Edit'):
                self.assertEqual(self.hook(tool, {'file_path': path})['decision'], 'deny')
        for shell in ('python -c "print(1)"', 'pwsh -Command "Set-Content requirements/REQ-001.yml altered"', 'sed -i s/old/new/ requirements/REQ-001.yml', 'mxcli exec change.mdl'):
            self.assertEqual(self.hook('Bash', {'command': shell})['decision'], 'deny')
        self.assertNotEqual(self.hook('Bash', {'command': 'git push'})['decision'], 'allow')
        self.assertEqual(self.hook('Agent', {'subagent_type': 'general-purpose', 'prompt': 'write requirement'})['decision'], 'deny')
        result = compatibility.resolve_human_resolution(self.root, **request)
        self.assertEqual(result['result'], 'APPLIED')
        self.assertEqual(self.hook('Bash', {'command': command(request)})['decision'], 'allow')
        self.assertEqual(self.hook('Bash', {'command': command({**request, 'value': 'REQ-999'})})['decision'], 'deny')
        self.assertEqual(self.hook('Edit', {'file_path': 'requirements/REQ-001.yml'})['decision'], 'deny')

    def test_human_resolution_source_staleness_blocks_hook(self):
        _, request, command = self.human_resolution_request()
        path = self.root / request['source_path']
        path.write_bytes(path.read_bytes() + b'\n# later source\n')
        self.assertEqual(self.hook('Bash', {'command': command(request)})['decision'], 'deny')

    def test_epoch_recovery_requires_completed_migration_and_preserves_scope(self):
        tools, compatibility = self.recovery_tools()
        command = f'pwsh -NoProfile -File "{tools / "Write-MxAgileEpochCheckpoint.ps1"}" -ProjectRoot "{self.root}" -PreserveEvidence'
        self.assertEqual(self.hook('Bash', {'command': command})['decision'], 'deny')
        compatibility.reconcile_contract(self.root, apply_safe=True)
        epoch = enforcement.guard.load_project_facts(self.root).context_epoch
        epoch['repository']['commit'] = '1' * 40
        self.write_yaml('.concord/context-epoch.yaml', epoch)
        allowed = self.hook('Bash', {'command': command})
        self.assertEqual(allowed['decision'], 'allow', allowed)
        self.assertEqual(allowed['controlled_recovery'], 'context_resync')
        self.assertEqual(self.hook('Bash', {'command': command + ' -WriteHandoffCopy'})['decision'], 'deny')
        self.assertEqual(self.hook('Write', {'file_path': 'planning/lifecycle/process-state.yaml'})['decision'], 'deny')


class AuxiliaryScopeTests(Phase1BFixture):
    recovery_tools = RecoveryScopeTests.recovery_tools

    def request(self, target='README.md', role='documentation', mutation='create'):
        tools, compatibility = self.recovery_tools()
        request = {'request_reference': 'USER-REALITY-FINDING', 'request_summary': 'Document the current finding only',
                   'target_path': target, 'artifact_role': role, 'scope_relation': 'independent_noncanonical',
                   'mutation': mutation, 'before_fingerprint': 'ABSENT', 'content': '# Reality finding\nBlocked delivery remains blocked.\n'}
        return tools, compatibility, request

    def command(self, tools, compatibility, request, confirmed=True):
        import base64
        encoded = base64.urlsafe_b64encode(json.dumps(request).encode()).decode()
        plan = compatibility.auxiliary_write_plan(self.root, request)
        command = f'python -B "{tools / "project_compatibility.py"}" auxiliary --apply --project-root "{self.root}" --format json --auxiliary-request {encoded} --plan-hash {plan["plan_hash"]} --human-reference {request["request_reference"]} --run-id RUN-AUXILIARY-FIXTURE'
        return command + (' --human-confirmed' if confirmed else '')

    def test_blocked_delivery_allows_only_bound_documentation_and_diagnostic_writes(self):
        for target, role in (('README.md', 'documentation'), ('docs/reality-findings.md', 'documentation'), ('.concord/scratch/CAP/REALITY-FINDING.md', 'diagnostic_findings')):
            tools, compatibility, request = self.request(target, role)
            command = self.command(tools, compatibility, request)
            allowed = self.hook('Bash', {'command': command})
            self.assertEqual(allowed['decision'], 'allow', allowed)
            self.assertEqual(allowed['operation_class'], enforcement.EVIDENCE_WRITE if role == 'diagnostic_findings' else enforcement.AUXILIARY_WRITE)
            before = (self.root / 'planning/mission/mission-state.yaml').read_bytes()
            plan = compatibility.auxiliary_write_plan(self.root, request)
            result = compatibility.apply_auxiliary_write(self.root, request, plan_hash=plan['plan_hash'], human_reference=request['request_reference'], human_confirmed=True, run_id='RUN-AUXILIARY-FIXTURE')
            self.assertEqual(result['result'], 'APPLIED')
            self.assertEqual((self.root / target).read_text(), request['content'])
            self.assertEqual((self.root / 'planning/mission/mission-state.yaml').read_bytes(), before)
            self.assertEqual(self.hook('Edit', {'file_path': 'requirements/REQ-001.yml'})['decision'], 'deny')

    def test_auxiliary_cannot_claim_canonical_or_product_authority(self):
        _, compatibility, request = self.request()
        for target, role in (('requirements/REQ-001.yml', 'documentation'), ('planning/lifecycle/process-state.yaml', 'documentation'), ('planning/mission/mission-state.yaml', 'documentation'), ('.mxagile/migration/state.yaml', 'documentation'), ('App.mpr', 'documentation'), ('javascriptsource/example.js', 'documentation'), ('docs/schemas.md', 'documentation'), ('docs/fixture/REQ-001.md', 'documentation'), ('planning/evidence/diagnostics/report.md', 'diagnostic_findings'), ('.mxagile./policies/support.md', 'documentation'), ('.mxagile /policies/support.md', 'documentation'), ('.mxagi~1/policies/support.md', 'documentation'), ('docs/CON.md', 'documentation'), ('README.md', 'canonical_contract')):
            with self.subTest(target=target):
                with self.assertRaises(ValueError):
                    compatibility.auxiliary_write_plan(self.root, {**request, 'target_path': target, 'artifact_role': role})
        self.write_yaml('requirements/REQ-004.yml', {'ID': 'REQ-004', 'source_path': 'docs/design.md'})
        with self.assertRaisesRegex(ValueError, 'AUXILIARY_SCOPE_PROTECTED'):
            compatibility.auxiliary_write_plan(self.root, {**request, 'target_path': 'docs/design.md'})

    def test_auxiliary_authorization_is_not_a_general_user_or_shell_bypass(self):
        tools, compatibility, request = self.request()
        command = self.command(tools, compatibility, request)
        for altered in (self.command(tools, compatibility, request, False), command.replace('USER-REALITY-FINDING --run-id', 'USER-OTHER-REQUEST --run-id'), command + ' && mxcli exec changes.mdl', command + ' > requirements/REQ-001.yml', command + ' --field status'):
            self.assertEqual(self.hook('Bash', {'command': altered})['decision'], 'deny')
        self.assertEqual(self.hook('Edit', {'file_path': 'README.md', 'user_authorized': True})['decision'], 'deny')
        self.assertEqual(self.hook('Bash', {'command': 'mxcli exec changes.mdl'})['decision'], 'deny')
        self.assertEqual(self.hook('mcp__mendix-studio-pro__create_entity', {'name': 'Admin_CenterYear'})['decision'], 'deny')
        self.assertNotEqual(self.hook('Bash', {'command': 'git push'})['decision'], 'allow')
        plan = compatibility.auxiliary_write_plan(self.root, request)
        for changed in ({'content': 'Other content'}, {'target_path': 'docs/other.md'}, {'artifact_role': 'diagnostic_findings'}, {'mutation': 'replace'}):
            with self.assertRaises(ValueError):
                compatibility.prepare_auxiliary_write(self.root, {**request, **changed}, plan_hash=plan['plan_hash'], human_reference=request['request_reference'], human_confirmed=True, run_id='RUN-AUXILIARY-FIXTURE')

    def test_auxiliary_replace_staleness_and_atomic_failure_remain_scoped(self):
        _, compatibility, request = self.request(mutation='replace')
        target = self.write('README.md', 'Original documentation\n')
        request['before_fingerprint'] = compatibility.digest(target.read_bytes())
        plan = compatibility.auxiliary_write_plan(self.root, request)
        authorization = {'plan_hash': plan['plan_hash'], 'human_reference': request['request_reference'], 'human_confirmed': True, 'run_id': 'RUN-AUXILIARY-FIXTURE'}
        target.write_text('Concurrent documentation\n')
        with self.assertRaisesRegex(ValueError, 'STALE_AUXILIARY_REQUEST'):
            compatibility.apply_auxiliary_write(self.root, request, **authorization)
        self.assertFalse((self.root / compatibility.AUXILIARY_INTERRUPT).exists())
        target.write_text('Original documentation\n')
        replace = compatibility.atomic_replace
        def fail_target(path, raw):
            if path == target:
                raise OSError('interrupted atomic target write')
            return replace(path, raw)
        with mock.patch.object(compatibility, 'atomic_replace', side_effect=fail_target):
            with self.assertRaises(OSError):
                compatibility.apply_auxiliary_write(self.root, request, **authorization)
        self.assertEqual(target.read_text(), 'Original documentation\n')
        self.assertTrue((self.root / compatibility.AUXILIARY_INTERRUPT).is_file())
        self.assertEqual(compatibility.apply_auxiliary_write(self.root, request, **authorization)['result'], 'APPLIED')

    def test_auxiliary_interrupt_requires_resync_without_completing_delivery(self):
        _, compatibility, request = self.request()
        compatibility.reconcile_contract(self.root, apply_safe=True)
        self.resync()
        plan = compatibility.auxiliary_write_plan(self.root, request)
        compatibility.apply_auxiliary_write(self.root, request, plan_hash=plan['plan_hash'], human_reference=request['request_reference'], human_confirmed=True, run_id='RUN-AUXILIARY-FIXTURE')
        facts = enforcement.guard.load_project_facts(self.root)
        result = enforcement.guard.delivery_authorization(facts, enforcement.DELIVERY_WRITE)
        self.assertIn('AUXILIARY_INTERRUPTION_REQUIRES_RESYNC', {f['code'] for f in result['must_findings']})
        self.assertEqual(compatibility.resync_preflight(self.root)['state'], 'READY_FOR_RESYNC')
        self.resync()
        facts = enforcement.guard.load_project_facts(self.root)
        result = enforcement.guard.delivery_authorization(facts, enforcement.DELIVERY_WRITE)
        self.assertNotIn('AUXILIARY_INTERRUPTION_REQUIRES_RESYNC', {f['code'] for f in result['must_findings']})


class DiagnosticChildTests(Phase1BFixture):
    def test_diagnostic_handoff_cannot_be_relabelled_as_visual_acceptance(self):
        handoff = self.visual_handoff()
        handoff['capability'] = 'read_only_diagnostic'
        evidence = [self.evidence('default'), self.evidence('modal_open')]
        verdict = self.verdict(handoff, evidence)
        result = child_contract.accept_child_result(self.root, handoff, verdict, self.contract, changed_paths=[])
        self.assertEqual(result['status'], 'REJECTED', result)
        self.assertIn('DIAGNOSTIC_RESULT_NOT_DELIVERY', {finding['code'] for finding in result['findings']})
        self.assertIsNone(result['gate'])

    def test_generic_read_only_child_requires_actual_host_constraints(self):
        handoff = self.visual_handoff(parent_run_id='RUN-aabbccddee11')
        handoff.update(capability='read_only_diagnostic', agent_type='fixture-specialist', write_classes=[], evidence_destination=None,
                       allowed_tools=['Read', 'Glob', 'Grep'], required_tools=['Read'],
                       forbidden_mutations=['ALL_WRITES', 'ACCEPTANCE', 'DELIVERY_AUTHORIZATION'], output_contract='diagnostic-findings/1')
        handoff['delivery_context'].update(authorization='read_only', write_scope=[], output_artifacts=[], evidence_destinations=[], commit_expectation='no_commit')
        reference = '.concord/delegation-handoffs/DELEGATION-V1.json'
        self.write(reference, json.dumps(handoff))
        facts = enforcement.guard.load_project_facts(self.root)
        facts.doctor_compatibility = 'BLOCKED'
        payload = {'tool_name': 'Agent', 'tool_input': {'subagent_type': 'fixture-specialist', 'prompt': f'MXAGILE_HANDOFF:{reference}', 'read_only': True}}
        evidence = enforcement.HostBoundaryEvidence(attest_diagnostic_child=lambda h, p: h['parent_run_id'] == 'RUN-aabbccddee11' and h['allowed_tools'] == ['Read', 'Glob', 'Grep'])
        with mock.patch.object(enforcement.guard, 'load_project_facts', return_value=facts), mock.patch.object(enforcement, '_persist_event'), mock.patch.dict(enforcement.os.environ, {'MXAGILE_RUN_ID': 'RUN-aabbccddee11'}):
            self.assertEqual(enforcement.decide(self.root, payload)['decision'], 'deny')
            allowed = enforcement.decide(self.root, payload, evidence=evidence)
            self.assertEqual(allowed['decision'], 'allow', allowed)
            handoff['delivery_context']['write_scope'] = ['requirements/']
            self.write(reference, json.dumps(handoff))
            self.assertEqual(enforcement.decide(self.root, payload, evidence=evidence)['decision'], 'deny')


class EnforcementTests(Phase1BFixture):
    def test_healthy_planning_and_evidence_do_not_require_implementing(self):
        for path in ('requirements/REQ-002.yml', 'planning/tasks/TASK-002.yml', '.concord/evidence/proof.json'):
            with self.subTest(path=path):
                self.assertEqual(self.hook('Write', {'file_path': path})['decision'], 'allow')
        self.assertEqual(enforcement.classify_path(self.root, 'planning/tasks/TASK-002.yml'), enforcement.DELIVERY_WRITE)
    def test_reads_stay_lightweight_and_never_call_the_guard(self):
        with mock.patch.object(enforcement.guard, "load_project_facts", side_effect=AssertionError("guard called")):
            result = self.hook("Read", {"file_path": str(self.root / "README.md")})
            self.assertEqual(result["decision"], "allow")
            self.assertIsNone(enforcement.hook_output(result))
            self.assertEqual(self.hook("mcp__mendix-studio-pro__get_page", {})["operation_class"], "READ")

    def test_implementation_write_needs_an_implementing_wave(self):
        denied = self.hook("Write", {"file_path": "javascriptsource/orders/overview.js"})
        self.assertEqual((denied["decision"], denied["operation_class"]), ("deny", "IMPLEMENTATION_WRITE"))
        self.assertIn("MUTATION_PHASE_BLOCKED", denied["reason"])
        self.assertEqual(enforcement.hook_output(denied)["hookSpecificOutput"]["permissionDecision"], "deny")
        self.set_wave("implementing")
        allowed = self.hook("Write", {"file_path": "javascriptsource/orders/overview.js"})
        self.assertEqual(allowed["decision"], "allow")
        self.assertIn("MODEL_SCOPE_NOT_OBSERVABLE", {f["code"] for f in allowed["verdict"]["should_findings"]})
        self.assertEqual(allowed["event"]["type"], "delivery_authorized")

    def test_tool_classification_covers_host_paths(self):
        cases = {
            ("mcp__mendix-studio-pro__create_page", "{}"): "IMPLEMENTATION_WRITE",
            ("Bash", "./mxcli.exe exec mdlsource/w1.mdl -p Fixture.mpr"): "IMPLEMENTATION_WRITE",
            ("Bash", "pwsh ./mxagile-setup.ps1"): "FRAMEWORK_WRITE",
            ("Bash", "git commit -m x"): "CONTROLLED_MUTATION",
            ("Write", "planning/evidence/x.png"): "EVIDENCE_WRITE",
            ("Write", "planning/lifecycle/process-state.yaml"): "LIFECYCLE_WRITE",
            ("UnknownTool", ""): "IMPLEMENTATION_WRITE",
        }
        for (tool, value), expected in cases.items():
            tool_input = {"command": value} if tool == "Bash" else {"file_path": value}
            with self.subTest(tool=tool, value=value):
                self.assertEqual(enforcement.classify_tool_call(self.root, {"tool_name": tool, "tool_input": tool_input})[0], expected)

    def test_normal_framework_command_is_not_recovery_authority(self):
        self.write(".mxagile/state/update-transaction.json", json.dumps({"state": "PARTIAL_UPDATE"}))
        self.assertEqual(self.hook("Bash", {"command": "pwsh ./mxagile-setup-company-layer.ps1 -ResumeUpdate"})["decision"], "deny")
        self.assertEqual(self.hook('Bash', {'command': 'python project_compatibility.py doctor --format json'})['decision'], 'allow')
        self.set_wave("implementing")
        self.assertEqual(self.hook("Write", {"file_path": "javascriptsource/a.js"})["decision"], "deny")

    def test_unavailable_guard_fails_closed(self):
        with mock.patch.object(enforcement.guard, "load_project_facts", side_effect=RuntimeError("boom")):
            result = self.hook("Write", {"file_path": "javascriptsource/a.js"})
        self.assertEqual(result["decision"], "deny")
        self.assertIn("GUARD_UNAVAILABLE", result["reason"])

    def test_child_spawn_requires_a_validated_handoff(self):
        allowed = self.hook("Agent", {"subagent_type": "Explore", "prompt": "look"})
        self.assertEqual(allowed["decision"], "allow")
        event = next(event for event in enforcement.run_events.read_events(self.root)["events"]
                     if event["event_type"] == "child_started")
        self.assertEqual(event["correlation"], {})
        self.assertEqual(enforcement.run_events.validate_event(event), [])
        denied = self.hook("Agent", {"subagent_type": "mxagile-implementation-agent", "prompt": "build pages"})
        self.assertEqual(denied["decision"], "deny")
        self.assertIn("CHILD_HANDOFF_MISSING", denied["reason"])


class VisualGateTests(Phase1BFixture):
    def test_full_runtime_coverage_passes_with_non_blocking_should_findings(self):
        handoff = self.visual_handoff()
        verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")], should=["MINOR_SPACING"])
        gate = child_contract.evaluate_visual_gate(self.root, self.contract, verdict)
        self.assertEqual(gate["gate_result"], "PASS", gate)
        self.assertNotIn("wave", gate["allowed_consequence"].lower().split(" ")[0])

    def test_without_runtime_evidence_never_pass(self):
        handoff = self.visual_handoff()
        static = self.verdict(handoff, [self.evidence("default", "static"), self.evidence("modal_open", "static")], mode="static")
        self.assertEqual(child_contract.evaluate_visual_gate(self.root, self.contract, static)["gate_result"], "PARTIAL")
        none = self.verdict(handoff, [])
        self.assertEqual(child_contract.evaluate_visual_gate(self.root, self.contract, none)["gate_result"], "UNAVAILABLE")
        missing_state = self.verdict(handoff, [self.evidence("default")])
        self.assertEqual(child_contract.evaluate_visual_gate(self.root, self.contract, missing_state)["gate_result"], "PARTIAL")

    def test_must_findings_block_and_round_limit_escalates(self):
        handoff = self.visual_handoff()
        evidence = [self.evidence("default"), self.evidence("modal_open")]
        first = child_contract.evaluate_visual_gate(self.root, self.contract, self.verdict(handoff, evidence, must=["GAP_001"]))
        self.assertEqual((first["gate_result"], first["event"]["type"]), ("FAIL", "repair_round_started"))
        second = child_contract.evaluate_visual_gate(self.root, self.contract, self.verdict(handoff, evidence, must=["GAP_001"], round_number=2))
        self.assertEqual(second["gate_result"], "NEEDS_HUMAN")
        self.assertIn("ROUND_LIMIT", second["reasons"])

    def test_child_claim_cannot_raise_and_evidence_must_match(self):
        handoff = self.visual_handoff()
        evidence = [self.evidence("default"), self.evidence("modal_open")]
        lowered = self.verdict(handoff, evidence, claim="partial")
        self.assertEqual(child_contract.evaluate_visual_gate(self.root, self.contract, lowered)["gate_result"], "PARTIAL")
        self.write(evidence[0]["path"], "tampered")
        tampered = child_contract.evaluate_visual_gate(self.root, self.contract, self.verdict(handoff, evidence))
        self.assertEqual(tampered["gate_result"], "FAIL")

    def test_mockup_revision_change_makes_pass_stale_with_reason(self):
        handoff = self.visual_handoff()
        verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")])
        self.write("input-resources/ui-ux/orders/index.html", "<html>orders REV-038</html>\n")
        self.contract["mockup"]["identity"] = "REV-038"
        gate = child_contract.evaluate_visual_gate(self.root, self.contract, verdict)
        self.assertEqual(gate["gate_result"], "STALE")
        self.assertIn({"code": "MOCKUP_REVISION_CHANGED", "input": "mockup_revision:input-resources/ui-ux/orders/index.html",
                       "from": "REV-037", "to": "REV-038"}, gate["stale_reasons"])


class RealityRegressionTests(Phase1BFixture):
    def test_a_concord_html_first_build_without_valid_delivery_context(self):
        self.set_wave("implementing")
        self.write("src/unrelated.py", "x = 1\n")
        _git(self.root, "add", "-A")
        _git(self.root, "commit", "-qm", "context drift without re-sync")
        process_state = (self.root / "planning/lifecycle/process-state.yaml").read_bytes()
        intent = "Baue alle verlinkten Pages HTML-first."
        self.assertEqual(child_contract.route_intent(intent)["capability"], "static_analysis")
        decisions = [
            self.hook("Write", {"file_path": "javascriptsource/orders/overview.js"}),
            self.hook("mcp__mendix-studio-pro__create_page", {"name": "Orders"}),
            self.hook("Agent", {"subagent_type": "mxagile-implementation-agent", "prompt": intent}),
        ]
        self.assertEqual({d["decision"] for d in decisions}, {"deny"})
        self.assertIn("HEAD_STALE", decisions[0]["reason"])
        self.assertEqual(decisions[0]["recovery"], "resync")
        self.assertEqual((self.root / "planning/lifecycle/process-state.yaml").read_bytes(), process_state)
        self.write_yaml("planning/mission/mission-state.yaml", {
            "schema_version": 1, "mission_id": MISSION, "created_at": "2026-11-11", "objective": "x",
            "completion_boundary": "WAVE_IMPLEMENTATION_COMPLETE",
            "criteria": {"lifecycle_derived": {"implementation": {"required": True, "status": "pending"}}},
            "progress": {"mission": "active"}})
        self.resync()
        no_wave = self.hook("Write", {"file_path": "javascriptsource/orders/overview.js"})
        self.assertEqual((no_wave["decision"], no_wave["recovery"]), ("deny", "human_resolution"))
        self.assertIn("MISSION_WAVE_REQUIRED", no_wave["reason"])
        self.assertNotIn("W0", (self.root / "planning/lifecycle/process-state.yaml").read_text(encoding="utf-8").replace("W01", ""))

    def test_b_visual_gap_analysis_routes_to_runtime_verification(self):
        route = child_contract.route_intent("Vollständige Lücken-/Blocker-/Dynamik-Analyse Mockup vs. App.")
        self.assertEqual(route["capability"], "runtime_visual_verification")
        self.assertTrue(route["requires_runtime_evidence"])
        handoff = self.visual_handoff()
        spawn = self.hook("Agent", {"subagent_type": "mxagile-ui-agent", "prompt": "MXAGILE_HANDOFF: .concord/delegation-handoffs/DELEGATION-V1.json"})
        self.assertEqual(spawn["decision"], "allow", spawn.get("reason"))
        self.assertEqual(spawn["event"], {"type": "child_started", "run_id": handoff["run_id"], "operation_class": "CHILD_SPAWN"})
        without_runtime = child_contract.accept_child_result(self.root, handoff, self.verdict(handoff, []), self.contract)
        self.assertEqual((without_runtime["status"], without_runtime["gate"]["gate_result"]), ("PARTIAL", "UNAVAILABLE"))
        full = child_contract.accept_child_result(self.root, handoff, self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")]), self.contract)
        self.assertEqual((full["status"], full["gate"]["gate_result"]), ("ACCEPTED", "PASS"))

    def test_b_spawn_with_tampered_scope_or_lifecycle_write_class_is_denied(self):
        handoff = self.visual_handoff()
        handoff["write_classes"] = ["EVIDENCE_WRITE", "LIFECYCLE_WRITE"]
        self.write(".concord/delegation-handoffs/DELEGATION-V1.json", json.dumps(handoff))
        spawn = self.hook("Agent", {"subagent_type": "mxagile-ui-agent", "prompt": "MXAGILE_HANDOFF: .concord/delegation-handoffs/DELEGATION-V1.json"})
        self.assertEqual(spawn["decision"], "deny")
        self.assertIn("LIFECYCLE_AUTHORITY_DELEGATED", spawn["reason"])

    def test_c_forbidden_child_write_is_rejected_after_termination(self):
        handoff = self.visual_handoff()
        verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")])
        self.write("theme/web/main.scss", "body { color: red; }\n")
        self.write("javascriptsource/orders/overview.js", "export const overview = 2;\n")
        result = child_contract.accept_child_result(self.root, handoff, verdict, self.contract)
        self.assertEqual(result["status"], "REJECTED")
        self.assertIsNone(result["gate"])
        self.assertEqual({item["path"] for item in result["forbidden_changes"]}, {"theme/web/main.scss", "javascriptsource/orders/overview.js"})
        self.assertEqual(result["event"]["type"], "child_rejected")

    def test_c_live_studio_pro_model_scope_is_not_observable_and_never_pass(self):
        handoff = self.visual_handoff(LIVE)
        verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")])
        result = child_contract.accept_child_result(self.root, handoff, verdict, self.contract)
        self.assertEqual((result["status"], result["gate"]["gate_result"]), ("PARTIAL", "PARTIAL"))
        self.assertIn("MODEL_SCOPE_NOT_OBSERVABLE", {finding["code"] for finding in result["findings"]})

    def test_d_context_invalidation_after_authorized_start(self):
        changes = {
            "REQUIREMENT_CHANGED": lambda: self.write("docs/fixture/REQ-001.md", "Filter is optional.\n"),
            "WAVE_STATE_CHANGED": lambda: self.set_wave("verifying"),
            "UPDATE_NOT_READY": lambda: self.write(".mxagile/state/update-transaction.json", json.dumps({"state": "UPDATE_IN_PROGRESS"})),
        }
        for code, change in changes.items():
            with self.subTest(code=code):
                handoff = self.visual_handoff()
                verdict = self.verdict(handoff, [self.evidence("default"), self.evidence("modal_open")])
                change()
                result = child_contract.accept_child_result(self.root, handoff, verdict, self.contract)
                self.assertEqual(result["status"], "STALE")
                self.assertIn(code, {finding["code"] for finding in result["findings"]})
                self.assertIsNone(result["gate"])
                (self.root / ".mxagile/state/update-transaction.json").unlink(missing_ok=True)
                self.write("docs/fixture/REQ-001.md", "Orders overview shows a filter.\n")
                self.set_wave("ready")


if __name__ == "__main__":
    unittest.main()
