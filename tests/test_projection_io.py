"""Filesystem safety of the canonical platform generator's output plan."""
import base64
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import projection_io


class ProjectionIOTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mxagile-projection-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plan = {'core_commit': 'b' * 40, 'core_version': '1.10.0', 'outputs': []}
        for host in ('.claude', '.github', '.agents'):
            directory = f'{host}/skills/example-skill'
            content = b'---\nname: example-skill\ndescription: fixture skill\n---\n# GENERATED - DO NOT EDIT - Source: .mxagile/\nBody\n'
            for name, data in (('SKILL.md', content), ('assets/example.html', b'<html>fixture</html>')):
                self.plan['outputs'].append({'target': f'{directory}/{name}', 'owner_root': directory, 'source': f'.mxagile/skills/example-skill/{name}', 'data': base64.b64encode(data).decode()})

    def write(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def fingerprint(self):
        return {p.relative_to(self.root).as_posix(): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}

    def test_missing_and_empty_all_hosts_are_safe_and_idempotent(self):
        for output in self.plan['outputs']:
            (self.root / output['owner_root']).mkdir(parents=True, exist_ok=True)
        report = projection_io.execute(self.root, self.plan, apply=False)
        self.assertTrue(report['ready'])
        self.assertEqual({t['state'] for t in report['targets']}, {'TARGET_EMPTY_UNOWNED'})
        self.assertEqual(self.fingerprint(), {})
        projection_io.execute(self.root, self.plan, apply=True)
        before = self.fingerprint()
        projection_io.execute(self.root, self.plan, apply=True)
        self.assertEqual(self.fingerprint(), before)
        manifest = json.loads((self.root / '.mxagile/state/projections-manifest.json').read_text())
        self.assertEqual(len(manifest['outputs']), 6)

    def test_all_conflicts_are_collected_without_any_write(self):
        self.write('.claude/skills/example-skill/SKILL.md', b'foreign skill')
        self.write('.github/skills/example-skill/.hidden', b'unknown hidden file')
        self.write('.agents/skills/example-skill/assets/example.html', b'foreign asset')
        before = self.fingerprint()
        report = projection_io.execute(self.root, self.plan, apply=False)
        self.assertFalse(report['ready'])
        self.assertEqual(len(report['conflicts']), 3)
        self.assertEqual(self.fingerprint(), before)

    def test_owned_stale_updates_but_mixed_foreign_content_blocks(self):
        projection_io.execute(self.root, self.plan, apply=True)
        updated = copy.deepcopy(self.plan)
        for output in updated['outputs']:
            if output['target'].endswith('.html'):
                output['data'] = base64.b64encode(b'<html>updated</html>').decode()
        projection_io.execute(self.root, updated, apply=True)
        self.write('.claude/skills/example-skill/assets/unknown.txt', b'foreign')
        before = self.fingerprint()
        self.assertFalse(projection_io.execute(self.root, updated, apply=False)['ready'])
        self.assertEqual(self.fingerprint(), before)

    def test_invalid_and_empty_subdirectory_are_not_adopted(self):
        self.write('.claude/skills/example-skill', b'not a directory')
        (self.root / '.github/skills/example-skill/unknown').mkdir(parents=True)
        report = projection_io.execute(self.root, self.plan, apply=False)
        self.assertFalse(report['ready'])
        self.assertTrue(any(c['target'].startswith('.claude/') and c['state'] == 'TARGET_INVALID' for c in report['conflicts']))
        self.assertTrue(any(c['target'].startswith('.github/') and c['state'] == 'TARGET_NONEMPTY_UNKNOWN' for c in report['conflicts']))

    def test_manifest_remains_old_when_apply_fails(self):
        projection_io.execute(self.root, self.plan, apply=True)
        manifest = self.root / '.mxagile/state/projections-manifest.json'
        old = manifest.read_bytes()
        updated = copy.deepcopy(self.plan)
        updated['core_commit'] = 'c' * 40
        updated['outputs'][0]['data'] = base64.b64encode(base64.b64decode(updated['outputs'][0]['data']) + b'new body\n').decode()
        with patch.object(projection_io, 'atomic_replace', side_effect=OSError('fixture write failure')):
            with self.assertRaises(OSError):
                projection_io.execute(self.root, updated, apply=True)
        self.assertEqual(manifest.read_bytes(), old)

    def test_unknown_modified_asset_and_corrupt_manifest_fail_closed(self):
        projection_io.execute(self.root, self.plan, apply=True)
        self.write('.claude/skills/example-skill/assets/example.html', b'foreign replacement')
        self.assertFalse(projection_io.execute(self.root, self.plan, apply=False)['ready'])
        self.write('.mxagile/state/projections-manifest.json', b'{invalid')
        self.assertFalse(projection_io.execute(self.root, self.plan, apply=False)['ready'])

    def test_legacy_bundle_is_replaced_only_with_complete_hash_proof(self):
        self.plan['outputs'] = []
        owner = '.claude/skills/mocketeer-design-contract'
        skill = b'legacy skill'
        asset = b'legacy asset'
        import hashlib
        self.write(owner + '/SKILL.md', skill)
        self.write(owner + '/assets/old.html', asset)
        manifest = {'managed_by': 'skill-bundle-v1', 'skill_name': 'mocketeer-design-contract', 'files': [{'path': 'SKILL.md', 'sha256': hashlib.sha256(skill).hexdigest()}, {'path': 'assets/old.html', 'sha256': hashlib.sha256(asset).hexdigest()}]}
        self.write(owner + '/bundle-manifest.json', json.dumps(manifest).encode())
        content = b'---\nname: mocketeer-design-contract\ndescription: fixture skill\n---\n' + projection_io.HEADER + b'\nnew body'
        self.plan['outputs'].append({'target': owner + '/SKILL.md', 'owner_root': owner, 'source': '.mxagile/skills/mocketeer-design-contract/SKILL.md', 'data': base64.b64encode(content).decode()})
        report = projection_io.execute(self.root, self.plan, apply=False)
        self.assertTrue(report['ready'], report)
        self.assertEqual(report['targets'][0]['state'], 'TARGET_STALE_GENERATED')
        projection_io.execute(self.root, self.plan, apply=True)
        self.assertFalse((self.root / owner / 'bundle-manifest.json').exists())
        self.assertFalse((self.root / owner / 'assets/old.html').exists())
        self.assertEqual((self.root / owner / 'SKILL.md').read_bytes(), content)

    def test_preflight_asset_proof_survives_core_source_replacement(self):
        projection_io.execute(self.root, self.plan, apply=True)
        manifest = self.root / '.mxagile/state/projections-manifest.json'
        old = json.loads(manifest.read_text())
        old.pop('outputs')
        manifest.write_text(json.dumps(old))
        for output in self.plan['outputs']:
            if output['target'].endswith('.html'):
                self.write(output['source'], base64.b64decode(output['data']))
        updated = copy.deepcopy(self.plan)
        for output in updated['outputs']:
            if output['target'].endswith('.html'):
                output['data'] = base64.b64encode(b'new core asset').decode()
        proof = projection_io.execute(self.root, updated, apply=False)
        self.assertTrue(proof['ready'], proof)
        for output in updated['outputs']:
            if output['target'].endswith('.html'):
                self.write(output['source'], base64.b64decode(output['data']))
        updated['ownership_baseline'] = proof['ownership_baseline']
        projection_io.execute(self.root, updated, apply=True)
        self.assertEqual((self.root / '.claude/skills/example-skill/assets/example.html').read_bytes(), b'new core asset')

    def test_foreign_embedded_marker_and_wrong_skill_identity_are_not_owned(self):
        self.write('.claude/skills/example-skill/SKILL.md', b'foreign body\n' + projection_io.HEADER + b'\n')
        self.write('.github/skills/example-skill/SKILL.md', b'---\nname: foreign\ndescription: foreign skill\n---\n' + projection_io.HEADER + b'\n')
        before = self.fingerprint()
        report = projection_io.execute(self.root, self.plan, apply=True)
        self.assertEqual({c['state'] for c in report['conflicts']}, {'TARGET_FOREIGN'})
        self.assertEqual(self.fingerprint(), before)

    def test_changed_plan_and_source_binding_fail_before_apply(self):
        projection_io.execute(self.root, self.plan, apply=True)
        before = self.fingerprint()
        changed = copy.deepcopy(self.plan)
        changed['expected_plan_fingerprint'] = '0' * 64
        self.assertFalse(projection_io.execute(self.root, changed, apply=True)['ready'])
        self.assertEqual(self.fingerprint(), before)
        path = self.root / projection_io.MANIFEST
        manifest = json.loads(path.read_text(encoding='utf-8'))
        manifest['outputs'][0]['source'] = '.mxagile/skills/foreign/SKILL.md'
        path.write_text(json.dumps(manifest), encoding='utf-8')
        changed = copy.deepcopy(self.plan)
        changed['ownership_baseline'] = [{'target': o['target'], 'sha256': o['sha256']} for o in manifest['outputs']]
        self.assertFalse(projection_io.execute(self.root, changed, apply=True)['ready'])

    def test_concurrent_manifest_edit_is_not_overwritten(self):
        projection_io.execute(self.root, self.plan, apply=True)
        changed = copy.deepcopy(self.plan)
        changed['outputs'][0]['data'] = base64.b64encode(base64.b64decode(changed['outputs'][0]['data']) + b'changed body\n').decode()
        manifest = self.root / projection_io.MANIFEST
        replace = projection_io.atomic_replace
        def concurrent_edit(path, data):
            replace(path, data)
            manifest.write_bytes(b'concurrent manifest edit')
        with patch.object(projection_io, 'atomic_replace', side_effect=concurrent_edit):
            with self.assertRaisesRegex(ValueError, 'manifest changed'):
                projection_io.execute(self.root, changed, apply=True)
        self.assertEqual(manifest.read_bytes(), b'concurrent manifest edit')
        self.assertEqual(list((self.root / '.mxagile/state').glob('.projection-stage-*')), [])

    def test_symlink_target_is_rejected_without_following(self):
        outside = self.root / 'outside'
        outside.mkdir()
        link = self.root / '.claude/skills/example-skill'
        link.parent.mkdir(parents=True)
        try:
            link.symlink_to(outside, target_is_directory=True)
        except OSError as exc:
            self.skipTest(f'OS symlink privilege unavailable: {exc}')
        self.assertFalse(projection_io.execute(self.root, self.plan, apply=False)['ready'])
        self.assertEqual(list(outside.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
