"""FINDING-023: preserve complete Wave identities across canonical readers."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

import yaml
from jsonschema import Draft7Validator
import test_control_plane_guard as fixture

sys.path.insert(0, str(fixture.ROOT / 'scripts'))
import build_project_status as status
import build_project_timeline as timeline
import canonicalize_artifacts as canonicalize


class WaveReaderTests(unittest.TestCase):
    def test_board_natural_order_preserves_suffix_and_legacy_identity(self):
        expected = ['W2', 'W15', 'W16a', 'W16b', 'W17e', 'W018a', 'W18A', 'W18a', 'W18b', 'W123', 'WAVE-01', 'Imported']
        waves = {wave: {'phase': 'not_started', 'gates': {}} for wave in reversed(expected)}
        _, items, _ = status.wave_projection({'waves': waves})
        self.assertEqual([item['wave_id'] for item in items], expected)
        self.assertTrue(all(item['phase'] != 'done' for item in items))

    def test_timeline_mentions_use_full_canonical_tokens(self):
        pattern = dict(timeline._MENTION_PATTERNS)['wave']
        text = 'W15 W16a W16b W17e W18a W18b W123 W18ab WAVE-01 AW18a xW18b _W15 w18a W éW18a W18bé'
        self.assertEqual(pattern.findall(text), ['W15', 'W16a', 'W16b', 'W17e', 'W18a', 'W18b', 'W123', 'W18ab', 'WAVE-01'])

    def test_checklist_conversion_preserves_identity_and_rejects_invalid_names(self):
        with tempfile.TemporaryDirectory(prefix='mxagile-wave-id-') as directory:
            root = Path(directory)
            for wave in ('W16a', 'W16b', 'W018a', 'W18A', 'W18a', 'W18b', 'WAVE-01'):
                path = root / f'{wave}-implementation-checklist.yaml'
                path.write_text('items: [Fixture action]\n', encoding='utf-8')
                tasks = canonicalize.convert_checklist_yaml_to_tasks(path, root, 1)
                self.assertEqual(tasks[0]['wave_id'], wave)
            path = root / 'w18a-implementation-checklist.yaml'
            path.write_text('items: [Fixture action]\n', encoding='utf-8')
            self.assertNotIn('wave_id', canonicalize.convert_checklist_yaml_to_tasks(path, root, 1)[0])

    def test_board_checklist_mapping_does_not_truncate_compound_ids(self):
        path = 'planning/checklists/WAVE-01-implementation-checklist.yaml'
        task = {'id': 'TASK-001', 'status': 'pending', 'wave_id': 'WAVE-01', 'migrated_from': path, 'workpackage_id': 'WP-1'}
        waves, _, _ = status.delivery_projection('available', [task], [{'wave_id': 'WAVE-01', 'phase': 'ready', 'gates': {}}], [path], [])
        self.assertEqual(waves[0]['checklist_progress']['source'], path)
        self.assertEqual(waves[0]['checklist_progress']['total'], 1)

    def test_finding_schema_accepts_existing_task_wave_grammar(self):
        schema = json.loads((fixture.ROOT / '.mxagile/schemas/finding.schema.json').read_bytes())
        document = {'ID': 'FIND-023', 'title': 'Fixture', 'gap_type': 'STATE_GAP', 'severity': 'MATERIAL',
                    'lifecycle_status': 'DETECTED', 'observation': 'Fixture only', 'source_artifacts': []}
        for wave in ('W15', 'W16a', 'W16b', 'W17e', 'W18a', 'W18b', 'W123', 'WAVE-01'):
            self.assertEqual(list(Draft7Validator(schema).iter_errors({**document, 'wave_id': wave})), [])
        for wave in ('W', 'w18a', '18a', 'W18a!', 'W18 a'):
            self.assertTrue(list(Draft7Validator(schema).iter_errors({**document, 'wave_id': wave})))


class PlannedWaveTests(fixture.GuardFixture):
    def test_anonymized_suffix_plan_recognizes_active_wave_without_promoting_history(self):
        identifiers = ['W15', 'W16e', 'W17a', 'W17d', 'W17e', 'W18a', 'W18b']
        mission = yaml.safe_load((self.root / 'planning/mission/mission-state.yaml').read_text())
        mission['active_wave'] = 'W18a'
        self.write_yaml('planning/mission/mission-state.yaml', mission)
        self.write_yaml('planning/lifecycle/process-state.yaml', {'waves': {
            'W18a': {'phase': 'ready', 'gates': {'gate_to_refinement': {'result': 'passed'}, 'gate_to_ready': {'result': 'passed'}}},
            'W18b': {'phase': 'not_started', 'gates': {'gate_to_refinement': {'result': 'passed'}, 'gate_to_ready': {'result': 'passed'}}},
        }})
        self.write('planning/execution-waves.md', '# Execution Waves\n\n' + '\n'.join(f'## Wave {wave} - Fixture' for wave in identifiers))
        before = (self.root / 'planning/lifecycle/process-state.yaml').read_bytes()
        result = self.evaluate({'gate_type': 'transition', 'wave_id': 'W18a', 'target_phase': 'implementing', 'authorization': fixture.AUTHORIZED})
        self.assertNotIn('WAVE_PLAN_MISSING', self.codes(result))
        self.assertEqual(result['verdict'], 'pass', result['must_findings'])
        facts = fixture.guard.load_project_facts(self.root)
        self.assertEqual(facts.planned_waves, set(identifiers))
        self.assertEqual(set(facts.process_state['waves']), {'W18a', 'W18b'})
        self.assertEqual((self.root / 'planning/lifecycle/process-state.yaml').read_bytes(), before)
        missing_authority = self.evaluate({'gate_type': 'transition', 'wave_id': 'W18a', 'target_phase': 'implementing'})
        self.assertIn('USER_AUTHORIZATION_NOT_OBSERVED', self.codes(missing_authority))

    def test_plan_reader_does_not_accept_prefixes_or_invalid_whole_identifiers(self):
        self.write('planning/execution-waves.md', '\n'.join([
            '## W15 - Numeric', '### Wave W16a: Suffix', '## W16b', '## W17e', '## W18a', '## W18b', '## W123',
            '## Wave AW18a', '## Wave w18a', '## Wave W18a.invalid', '## Wave W18b/other', '## Wave W',
        ]))
        self.assertEqual(fixture.guard.load_project_facts(self.root).planned_waves, {'W15', 'W16a', 'W16b', 'W17e', 'W18a', 'W18b', 'W123'})


if __name__ == '__main__':
    unittest.main()
