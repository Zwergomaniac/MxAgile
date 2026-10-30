"""Canonical capture fixtures and asset-allowlist regression."""

import copy
import hashlib
import json
import shutil
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import build_project_status
import project_compatibility
import serve_project_board


def fixture(root):
    reference = 'planning/target-mockups/Board/_history/REV-001/index.html'
    path = root / reference
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('''<!doctype html><html><meta charset="utf-8"><title>Review queue fixture</title>
            <style>body{margin:0;font:16px Georgia;background:#edf2ef;color:#18392d}header{padding:24px;background:#18392d;color:white}main{padding:28px}table{width:100%;border-collapse:collapse;background:white}td,th{padding:18px;text-align:left;border-bottom:1px solid #d5dfd9}.role{float:right;color:#c1eed3}h1{font-size:28px}small{color:#587667}</style>
            <header>REVIEW WORKSPACE <span class="role">CEKO</span></header><main><h1>Review queue</h1><p>October 2026 <small> / Synthetic framework evidence</small></p>
            <table><thead><tr><th>Request</th><th>Owner</th><th>State</th></tr></thead><tbody><tr><td>REQ-001</td><td>Planning</td><td>In review</td></tr><tr><td>REQ-002</td><td>Delivery</td><td>Ready</td></tr></tbody></table></main></html>''', encoding='utf-8')
    fingerprint = 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
    (path.parent / 'revision.yaml').write_text(project_compatibility.yaml.safe_dump({
        'revision': 1, 'revision_id': 'REV-001', 'mockup_name': 'Board', 'created_at': '2026-10-30',
        'lifecycle_status': 'SUPERSEDED_TARGET', 'refinement_status': 'ACCEPTED', 'active_target': False,
        'entry_point': 'index.html', 'bundle_hash': fingerprint, 'lifecycle_trigger': 'initial_acceptance',
        'change_classification': 'material', 'impact_scope': 'full'}), encoding='utf-8')
    identity = {'status': 'BOUND', 'active_target': 'Board', 'canonical_mockup_path': reference,
                'revision': 'REV-001', 'fingerprint': fingerprint, 'target_page': 'PAGE-1',
                'roles': ['CEKO', 'E2'], 'states': ['populated'], 'app_revision': 'app-1', 'model_revision': 'model-1'}
    entry = {'entry_id': 'EVD-1', 'scenario_id': 'SCN-1', 'screen_id': 'PAGE-1', 'role': 'CEKO',
             'data_state': 'populated', 'parity_result': 'NOT_VERIFIED', 'comparison_identity': identity,
             'parity_report_path': 'planning/parity/PAGE-1.yaml', 'capture_groups': [], 'target_evidence': [], 'actual_evidence': []}
    for side, role in (('mockup', 'CEKO'), ('application', 'CEKO'), ('application', 'E2')):
        capture_id = f'CAP-{side}-{role}'
        image = f'planning/evidence/screenshots/{capture_id}.png'
        image_path = root / image
        image_path.parent.mkdir(parents=True, exist_ok=True)
        def chunk(name, data):
            return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data))
        pixels = b'\x00' + (b'\x83\xd6\xb2' if side == 'mockup' else b'\x94\xb9\xd1') * 320
        image_path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 320, 180, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels * 180)) + chunk(b'IEND', b''))
        snapshot = f'planning/evidence/snapshots/{capture_id}.yaml'
        snapshot_path = root / snapshot
        snapshot_path.parent.mkdir(parents=True, exist_ok=True)
        snapshot_path.write_text('page: PAGE-1\n', encoding='utf-8')
        entry['capture_groups'].append({'capture_id': capture_id, 'capture_source': side, 'captured_at': '2026-10-30T12:00:00Z',
            'comparison_identity': identity, 'runtime_url': 'http://user:SECRET@localhost:8080/p/review?token=SECRET#SECRET',
            'role': role, 'target_screen': 'PAGE-1', 'session_id': 'SECRET-SESSION', 'run_id': 'RUN-1',
            'screenshot_path': image, 'snapshots': [{'path': snapshot, 'type': 'yaml'}], 'cleanliness_state': 'clean'})
        entry['target_evidence' if side == 'mockup' else 'actual_evidence'].append({'artifact_id': capture_id, 'type': 'screenshot', 'path': image, 'capture_id': capture_id, 'source': side})
    parity = {'page_id': 'PAGE-1', 'verified_at': '2026-10-30', 'evidence_level': 'browser', 'overall_result': 'NOT_VERIFIED',
              'comparison_identity': identity, 'dimensions': {name: {'result': 'NOT_VERIFIED'} for name in ('visual', 'content', 'structure', 'state', 'interaction', 'responsive', 'role')},
              'evidence_matrix': {name + '_parity': {'status': 'NOT_VERIFIED'} for name in ('contract', 'model', 'structural_dom', 'behavioral', 'role', 'visual_whole_screen')}}
    parity_path = root / entry['parity_report_path']
    parity_path.parent.mkdir(parents=True, exist_ok=True)
    parity_path.write_text(project_compatibility.yaml.safe_dump(parity), encoding='utf-8')
    manifest = {'manifest_id': 'MFT-W01', 'wave_id': 'W01', 'entries': [entry]}
    target = {'screen_ids': ['PAGE-1'], 'availability': 'available', 'canonical_path': reference, 'revision_id': 'REV-001', 'bundle_hash': fingerprint, 'content_hash': None}
    return manifest, target


def historical_entry(entry):
    history = copy.deepcopy(entry)
    history['entry_id'] = 'EVD-0'
    for group in history['capture_groups']:
        group['capture_id'] += '-old'
        group['run_id'] = 'RUN-0'
        group['captured_at'] = '2026-10-29T12:00:00Z'
    for artifact in history['target_evidence'] + history['actual_evidence']:
        artifact['capture_id'] += '-old'
        artifact['artifact_id'] += '-old'
        artifact['lifecycle_stage'] = 'historical'
    return history


class GalleryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mxagile-gallery-')
        self.root = Path(self.temp.name)
        self.manifest, self.target = fixture(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def project(self):
        return build_project_status.visual_evidence_projection(self.root, [self.manifest], ['planning/evidence/manifests/W01-evidence-manifest.yaml'], [self.target], {}, [])

    def test_mock_ceko_e2_are_bound_and_sanitized(self):
        gallery = self.project()
        self.assertEqual(len(gallery), 1)
        self.assertFalse(gallery[0]['historical'])
        self.assertEqual({capture['role'] for capture in gallery[0]['captures']}, {'CEKO', 'E2'})
        self.assertEqual(len(gallery[0]['captures']), 3)
        self.assertNotIn('SECRET', json.dumps(gallery))
        self.assertEqual(gallery[0]['parity_result'], 'NOT_VERIFIED')

    def test_missing_captures_never_uses_unbound_images(self):
        self.manifest['entries'][0].pop('capture_groups')
        self.assertEqual(self.project(), [])

    def test_drifted_identity_and_unsafe_images_are_not_authorized(self):
        self.manifest['entries'][0]['capture_groups'][0]['comparison_identity'] = {**self.manifest['entries'][0]['comparison_identity'], 'revision': 'REV-999'}
        gallery = self.project()
        self.assertEqual(len(gallery[0]['captures']), 2)
        self.assertIsNone(serve_project_board.resolve_capture_file(self.root, {'verification': {'gallery': gallery}}, '.env.mendix'))
        self.assertIsNone(serve_project_board.resolve_capture_file(self.root, {'verification': {'gallery': gallery}}, '../planning/evidence/screenshots/any.png'))
        self.assertIsNone(serve_project_board.resolve_capture_file(self.root, {'verification': {'gallery': gallery}}, 'planning/evidence/screenshots/CAP-mockup-CEKO.png'))

    def test_historical_target_is_not_current_pass(self):
        self.target['revision_id'] = 'REV-002'
        gallery = self.project()
        self.assertTrue(gallery[0]['historical'])
        self.assertTrue(all(capture['freshness'] == 'HISTORICAL_TARGET' for capture in gallery[0]['captures']))

    def test_schema_invalid_manifest_and_parity_are_not_gallery_authority(self):
        self.manifest['entries'][0]['capture_groups'][0]['cleanliness_state'] = 'contaminated'
        self.assertEqual(self.project(), [])

    def test_only_allowlisted_capture_is_served(self):
        gallery = self.project()
        path = gallery[0]['captures'][0]['screenshot_path']
        self.assertEqual(serve_project_board.resolve_capture_file(self.root, {'verification': {'gallery': gallery}}, path), self.root / path)

    def test_duplicate_capture_id_never_selects_first(self):
        entry = self.manifest['entries'][0]
        entry['capture_groups'].append(copy.deepcopy(entry['capture_groups'][0]))
        self.assertEqual(len(self.project()[0]['captures']), 2)

    def test_unbound_historical_reference_is_rejected(self):
        self.target['revision_id'] = 'REV-002'
        self.manifest['entries'][0]['comparison_identity']['fingerprint'] = 'sha256:' + 'f' * 64
        self.assertEqual(self.project(), [])

    def test_current_and_previous_groups_remain_separate(self):
        self.manifest['entries'].append(historical_entry(self.manifest['entries'][0]))
        self.assertEqual([run['historical'] for run in self.project()], [False, True])

    def test_conflicting_capture_identity_across_entries_is_not_gallery_authority(self):
        other = copy.deepcopy(self.manifest['entries'][0])
        other['entry_id'] = 'EVD-2'
        for group in other['capture_groups']:
            group['run_id'] = 'CONFLICTING-RUN'
        self.manifest['entries'].append(other)
        gaps = []
        gallery = build_project_status.visual_evidence_projection(self.root, [self.manifest], ['planning/evidence/manifests/W01-evidence-manifest.yaml'], [self.target], {}, gaps)
        self.assertEqual(gallery, [])
        self.assertTrue(any(gap['code'] == 'CAPTURE_ID_CONFLICT' for gap in gaps))
        report = project_compatibility.compatibility_report(self.root, {'gaps': gaps, 'project': {'active_targets': {'items': []}}}, {})
        self.assertTrue(any(item['category'] == 'AUTHORITY_CONFLICT' and item['authority'] == 'capture_id' and item['repairability'] == 'DECISION_REQUIRED' for item in report['diagnostics']))

    def test_historical_single_file_reference_is_exactly_allowlisted(self):
        relative = 'input-resources/ui-ux/previous.html'
        path = self.root / relative
        path.parent.mkdir(parents=True)
        path.write_text('<html>Historical reference</html>', encoding='utf-8')
        status = {'verification': {'gallery': [{'reference_path': relative, 'revision': 'LEGACY', 'captures': []}]}}
        self.assertEqual(serve_project_board.resolve_reference_file(self.root, status, relative), path)
        self.assertIsNone(serve_project_board.resolve_reference_file(self.root, status, 'input-resources/ui-ux/unbound.html'))

    def test_multiple_runs_in_one_entry_do_not_merge(self):
        entry = self.manifest['entries'][0]
        for field in ('target_evidence', 'actual_evidence'):
            for artifact in list(entry[field]):
                entry[field].append({**artifact, 'capture_id': artifact['capture_id'] + '-old', 'artifact_id': artifact['artifact_id'] + '-old', 'lifecycle_stage': 'historical'})
        for group in list(entry['capture_groups']):
            entry['capture_groups'].append({**group, 'capture_id': group['capture_id'] + '-old', 'run_id': 'RUN-0'})
        runs = self.project()
        self.assertEqual([(run['run_id'], run['historical']) for run in runs], [('RUN-1', False), ('RUN-0', True)])
        self.assertTrue(all(len(run['captures']) == 3 for run in runs))

    def test_http_endpoint_only_serves_explicit_images(self):
        import threading
        import urllib.request
        import urllib.error
        from unittest.mock import patch
        gallery = self.project()
        server = serve_project_board.ProjectBoardServer(self.root, self.root, 0)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        with patch.object(serve_project_board.ProjectBoardHandler, '_status', return_value={'verification': {'gallery': gallery}}):
            worker.start()
            try:
                base = f'http://127.0.0.1:{server.server_port}'
                with urllib.request.urlopen(base + '/capture/' + gallery[0]['captures'][0]['screenshot_path']) as response:
                    self.assertEqual(response.headers['Content-Type'], 'image/png')
                for path in ('.env.mendix', '../.git/index', 'planning/evidence/snapshots/CAP-mockup-CEKO.yaml', 'planning/evidence/screenshots/unbound.png'):
                    with self.assertRaises(urllib.error.HTTPError) as failure:
                        urllib.request.urlopen(base + '/capture/' + path)
                    self.assertEqual(failure.exception.code, 404)
                    failure.exception.close()
            finally:
                server.shutdown()
                server.server_close()
                worker.join()


def serve_fixture():
    with tempfile.TemporaryDirectory(prefix='mxagile-gallery-browser-') as directory:
        root = Path(directory)
        manifest, target = fixture(root)
        for relative in ('requirements', 'specs', 'planning/tasks', 'planning/findings', 'planning/decisions', 'planning/test-contracts', 'planning/verification-plans', 'planning/ui-inventory', 'planning/evidence/manifests', 'planning/lifecycle'):
            (root / relative).mkdir(parents=True, exist_ok=True)
        shutil.copytree(ROOT / '.mxagile/board', root / '.mxagile/board')
        (root / '.mxagile/version.yaml').write_text("version: '1.8.0'\n", encoding='utf-8')
        (root / 'mxagile-project.yaml').write_text('name: Parity Evidence Fixture\n', encoding='utf-8')
        revision_path = (root / target['canonical_path']).parent / 'revision.yaml'
        revision = project_compatibility.load_yaml(revision_path.read_bytes())
        revision.update(active_target=True, lifecycle_status='REFINED_TARGET')
        revision_path.write_text(project_compatibility.yaml.safe_dump(revision), encoding='utf-8')
        (root / 'planning/ui-inventory/PAGE-1.yaml').write_text('page_id: PAGE-1\nmockup_name: Board\ntarget_revision: REV-001\n', encoding='utf-8')
        manifest['entries'].append(historical_entry(manifest['entries'][0]))
        (root / 'planning/evidence/manifests/W01-evidence-manifest.yaml').write_text(project_compatibility.yaml.safe_dump(manifest), encoding='utf-8')
        server = serve_project_board.ProjectBoardServer(root, root / '.mxagile/board', 0)
        print(json.dumps({'url': f'http://127.0.0.1:{server.server_port}/#gallery', 'fixture_root': str(root)}), flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()


if __name__ == '__main__':
    if '--serve-fixture' in sys.argv:
        serve_fixture()
    else:
        unittest.main()