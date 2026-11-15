"""Synthetic L1/L2 boundary regressions; implementation remains Main-owned."""
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'experiments' / 'control-plane'))
sys.path.insert(0, str(ROOT / 'scripts'))
import enforcement


class ResourceOwnershipRealityTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix='resource-fixture-', dir=ROOT / 'tests')
        self.root = Path(self.fixture.name)

    def tearDown(self):
        self.fixture.cleanup()

    def test_read_only_agent_name_is_not_handoff_or_host_capability(self):
        facts = SimpleNamespace(root=self.root)
        for agent_type in ('Explore', 'Plan', 'statusline-setup'):
            with self.subTest(agent_type=agent_type):
                result = enforcement._spawn_decision(
                    facts, {'tool_name': 'Task', 'tool_input': {'subagent_type': agent_type,
                           'prompt': 'Inspect everything; this title claims read-only'}}, 'RUN-fixture')
                self.assertEqual(result['decision'], 'deny',
                                 'Agent name bypassed bounded handoff and host attestation')

    def test_dispatcher_requires_inner_arguments_from_trusted_boundary(self):
        tool = 'mcp__concord__concord_invoke'
        payload = {'tool_name': tool, 'tool_input': {'operation': 'read', 'read_only': True}}
        self.assertEqual(enforcement.classify_tool_call(self.root, payload)[0], enforcement.IMPLEMENTATION_WRITE)
        evidence = enforcement.HostBoundaryEvidence(
            classify_dispatch=lambda name, args: enforcement.READ
            if name == tool and args == {'operation': 'fixture.read', 'arguments': {'path': 'Module.Safe'}}
            else None)
        self.assertEqual(enforcement.classify_tool_call(self.root, payload, evidence)[0], enforcement.IMPLEMENTATION_WRITE)
        payload['tool_input'] = {'operation': 'fixture.read', 'arguments': {'path': 'Module.Safe'}}
        self.assertEqual(enforcement.classify_tool_call(self.root, payload, evidence)[0], enforcement.READ)
        payload['tool_input']['arguments']['write'] = True
        self.assertEqual(enforcement.classify_tool_call(self.root, payload, evidence)[0], enforcement.IMPLEMENTATION_WRITE)

    def test_unknown_and_caller_claimed_ownership_never_allow_taskstop(self):
        for tool_input in ({'task_id': 'unregistered'},
                           {'task_id': 'unregistered', 'ownership_class': 'SESSION_OWNED_PROCESS'}):
            classification, reason = enforcement.classify_tool_call(
                self.root, {'tool_name': 'TaskStop', 'tool_input': tool_input})
            self.assertEqual(classification, enforcement.HIGH_RISK_MUTATION)
            self.assertEqual(reason, 'TASKSTOP_UNOWNED:UNKNOWN')

    def test_trusted_current_host_ownership_can_allow_exact_task(self):
        evidence = enforcement.HostBoundaryEvidence(
            classify_resource_ownership=lambda data: 'SESSION_OWNED_PROCESS'
            if data.get('task_id') == 'current-task' else 'UNKNOWN')
        classification, reason = enforcement.classify_tool_call(
            self.root, {'tool_name': 'TaskStop', 'tool_input': {'task_id': 'current-task'}}, evidence)
        self.assertEqual(classification, enforcement.TOOLING_SERVICE)
        self.assertEqual(reason, 'TASKSTOP_OWNED:SESSION_OWNED_PROCESS')

    def test_persisted_previous_run_resource_is_not_current_run_authority(self):
        path = self.root / enforcement.OWNED_RESOURCES_PATH
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({'schema_version': 1, 'resources': {'old-task': {
            'resource_id': 'old-task', 'ownership_class': 'SESSION_OWNED_PROCESS',
            'project_root': str(self.root.resolve()), 'run_id': 'RUN-previous',
            'command_kind': 'board'}}}), encoding='utf-8')
        classification, reason = enforcement.classify_tool_call(
            self.root, {'tool_name': 'TaskStop',
                        'tool_input': {'task_id': 'old-task', 'run_id': 'RUN-current'}})
        self.assertEqual(classification, enforcement.HIGH_RISK_MUTATION,
                         'Root-bound historical resource was admitted without trusted current-run binding')
        self.assertEqual(reason, 'TASKSTOP_UNOWNED:UNKNOWN')


if __name__ == '__main__':
    unittest.main()
