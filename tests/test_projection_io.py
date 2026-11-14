"""Filesystem safety of the canonical platform generator's output plan."""
import base64
import copy
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
from types import SimpleNamespace
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
        preflight = projection_io.execute(self.root, updated, apply=False)
        self.assertTrue(preflight['ready'])
        self.assertEqual({t['state'] for t in preflight['targets']}, {'TARGET_OWNED_STALE'})
        projection_io.execute(self.root, updated, apply=True)
        for host in ('.claude', '.github', '.agents'):
            self.write(f'{host}/skills/example-skill/assets/unknown.txt', b'foreign')
        before = self.fingerprint()
        for apply in (False, True):
            report = projection_io.execute(self.root, updated, apply=apply)
            self.assertFalse(report['ready'])
            self.assertEqual(len(report['conflicts']), 3)
            self.assertEqual(self.fingerprint(), before)

    def test_invalid_target_is_not_adopted(self):
        self.write('.claude/skills/example-skill', b'not a directory')
        report = projection_io.execute(self.root, self.plan, apply=False)
        self.assertFalse(report['ready'])
        self.assertTrue(any(c['target'].startswith('.claude/') and c['state'] == 'TARGET_INVALID' for c in report['conflicts']))

    def test_directory_only_trees_are_safe_for_all_hosts_and_repeat_apply(self):
        original_root = self.root
        structures = (('',), ('assets',), ('assets/images/nested',), ('assets/images', 'empty-sibling/child', 'other'), ('ASSETS/images',))
        for index, directories in enumerate(structures):
            with self.subTest(directories=directories):
                self.root = original_root / str(index)
                self.root.mkdir()
                for host in ('.claude', '.github', '.agents'):
                    for directory in directories:
                        (self.root / host / 'skills/example-skill' / directory).mkdir(parents=True, exist_ok=True)
                before = projection_io.inventory(self.root, self.root)
                preflight = projection_io.execute(self.root, self.plan, apply=False)
                self.assertTrue(preflight['ready'], preflight)
                self.assertEqual({t['state'] for t in preflight['targets']}, {'TARGET_EMPTY_UNOWNED'})
                self.assertEqual(projection_io.inventory(self.root, self.root), before)
                applied = projection_io.execute(self.root, self.plan, apply=True)
                self.assertTrue(applied['ready'] and applied['applied'])
                after = projection_io.inventory(self.root, self.root)
                self.assertTrue(projection_io.execute(self.root, self.plan, apply=False)['ready'])
                self.assertTrue(projection_io.execute(self.root, self.plan, apply=True)['applied'])
                self.assertEqual(projection_io.inventory(self.root, self.root), after)
        self.root = original_root

    def test_file_directory_collisions_block_before_apply_for_all_hosts(self):
        original_root = self.root
        names = ('SKILL.md', 'assets/example.html')
        if os.name == 'nt':
            names += ('skill.md', 'assets/EXAMPLE.HTML')
        for index, name in enumerate(names):
            with self.subTest(name=name):
                self.root = original_root / str(index)
                for host in ('.claude', '.github', '.agents'):
                    (self.root / host / 'skills/example-skill' / name).mkdir(parents=True)
                before = projection_io.inventory(self.root, self.root)
                for apply in (False, True):
                    report = projection_io.execute(self.root, self.plan, apply=apply)
                    self.assertFalse(report['ready'])
                    self.assertEqual({c['state'] for c in report['conflicts']}, {'TARGET_INVALID'})
                    self.assertEqual(projection_io.inventory(self.root, self.root), before)
        self.root = original_root

    def test_any_file_blocks_unowned_trees_for_all_hosts(self):
        original_root = self.root
        cases = (('assets/.keep', b''), ('.hidden', b'hidden'), ('SKILL.md', b'foreign skill'),
                 ('assets/foo.png', b'foreign asset'), ('assets/zero-byte', b''),
                 ('owned-marker', b'owner'), ('bundle-manifest.json', b'{}'),
                 ('empty-sibling/foreign.txt', b'mixed content'))
        for index, (name, content) in enumerate(cases):
            with self.subTest(name=name):
                self.root = original_root / str(index)
                for host in ('.claude', '.github', '.agents'):
                    (self.root / host / 'skills/example-skill/assets/images').mkdir(parents=True)
                    self.write(f'{host}/skills/example-skill/{name}', content)
                before = projection_io.inventory(self.root, self.root)
                for apply in (False, True):
                    report = projection_io.execute(self.root, self.plan, apply=apply)
                    self.assertFalse(report['ready'], report)
                    self.assertEqual(len(report['conflicts']), 3)
                    self.assertEqual(projection_io.inventory(self.root, self.root), before)
                self.assertFalse((self.root / '.mxagile').exists())
        self.root = original_root

    def test_case_aliases_without_filesystem_identity_do_not_hide_content(self):
        if os.name != 'nt':
            self.skipTest('Windows case alias classifier')
        projection_io.execute(self.root, self.plan, apply=True)
        for host in ('.claude', '.github', '.agents'):
            assets = self.root / host / 'skills/example-skill/assets'
            assets.rename(assets.with_name('ASSETS'))
        before = self.fingerprint()
        with patch.object(Path, 'samefile', return_value=False):
            for apply in (False, True):
                report = projection_io.execute(self.root, self.plan, apply=apply)
                self.assertFalse(report['ready'])
                self.assertEqual(len(report['conflicts']), 3)
                self.assertEqual(self.fingerprint(), before)

    def test_duplicate_case_alias_entries_do_not_hide_unknown_files(self):
        if os.name != 'nt':
            self.skipTest('Windows case alias classifier')
        projection_io.execute(self.root, self.plan, apply=True)
        before = self.fingerprint()
        inventory = projection_io.inventory
        def duplicate_alias(root, directory):
            entries = inventory(root, directory)
            skill = directory / 'SKILL.md'
            if skill.is_file():
                entries[(directory / 'skill.md').relative_to(root).as_posix()] = projection_io.digest(skill.read_bytes())
            return entries
        with patch.object(projection_io, 'inventory', side_effect=duplicate_alias):
            for apply in (False, True):
                report = projection_io.execute(self.root, self.plan, apply=apply)
                self.assertFalse(report['ready'])
                self.assertEqual(len(report['conflicts']), 3)
                self.assertEqual(self.fingerprint(), before)

    def test_foreign_file_added_after_empty_preflight_blocks_apply(self):
        for host in ('.claude', '.github', '.agents'):
            (self.root / host / 'skills/example-skill/assets').mkdir(parents=True)
        self.assertTrue(projection_io.execute(self.root, self.plan, apply=False)['ready'])
        mkdtemp = tempfile.mkdtemp
        def add_foreign_file(*args, **kwargs):
            stage = mkdtemp(*args, **kwargs)
            self.write('.github/skills/example-skill/assets/.keep', b'concurrent content')
            return stage
        with patch.object(projection_io.tempfile, 'mkdtemp', side_effect=add_foreign_file):
            with self.assertRaisesRegex(ValueError, 'changed after preflight'):
                projection_io.execute(self.root, self.plan, apply=True)
        self.assertEqual(self.fingerprint(), {'.github/skills/example-skill/assets/.keep': b'concurrent content'})
        self.assertFalse((self.root / projection_io.MANIFEST).exists())
        self.assertEqual(list((self.root / '.mxagile/state').glob('.projection-stage-*')), [])

    def test_nested_reparse_attribute_blocks_all_hosts_without_reading_contents(self):
        reparses = set()
        for host in ('.claude', '.github', '.agents'):
            directory = self.root / host / 'skills/example-skill/assets/nested'
            directory.mkdir(parents=True)
            reparses.add(directory)
        lstat = Path.lstat
        def reparse_info(path, *args, **kwargs):
            if path in reparses:
                return SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_file_attributes=1024)
            return lstat(path, *args, **kwargs)
        with patch.object(Path, 'lstat', reparse_info):
            for apply in (False, True):
                report = projection_io.execute(self.root, self.plan, apply=apply)
                self.assertFalse(report['ready'])
                self.assertEqual({c['target'] for c in report['conflicts']}, {f'{h}/skills/example-skill' for h in ('.claude', '.github', '.agents')})
        self.assertEqual(self.fingerprint(), {})

    def test_nested_symlinks_and_dangling_links_block_all_hosts(self):
        original_root = self.root
        for kind in ('directory', 'file', 'dangling'):
            with self.subTest(kind=kind):
                self.root = original_root / kind
                outside = self.root / 'outside'
                outside.mkdir(parents=True)
                foreign = outside / 'foreign'
                foreign.write_bytes(b'outside content')
                destination = outside if kind == 'directory' else (foreign if kind == 'file' else outside / 'missing')
                for host in ('.claude', '.github', '.agents'):
                    parent = self.root / host / 'skills/example-skill/assets'
                    parent.mkdir(parents=True)
                    try:
                        (parent / 'link').symlink_to(destination, target_is_directory=kind != 'file')
                    except OSError as exc:
                        self.skipTest(f'OS symlink privilege unavailable: {exc}')
                for apply in (False, True):
                    report = projection_io.execute(self.root, self.plan, apply=apply)
                    self.assertFalse(report['ready'])
                    self.assertEqual({c['state'] for c in report['conflicts']}, {'TARGET_INVALID'})
                self.assertEqual(foreign.read_bytes(), b'outside content')
                self.assertFalse((self.root / '.mxagile').exists())
        self.root = original_root

    def test_nested_windows_junction_blocks_all_hosts(self):
        if os.name != 'nt':
            self.skipTest('Windows junction fixture')
        outside = self.root / 'outside'
        outside.mkdir()
        for host in ('.claude', '.github', '.agents'):
            parent = self.root / host / 'skills/example-skill/assets'
            parent.mkdir(parents=True)
            result = subprocess.run([os.environ.get('COMSPEC', 'cmd.exe'), '/c', 'mklink', '/J', str(parent / 'junction'), str(outside)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for apply in (False, True):
            report = projection_io.execute(self.root, self.plan, apply=apply)
            self.assertFalse(report['ready'])
            self.assertEqual({c['state'] for c in report['conflicts']}, {'TARGET_INVALID'})
        self.assertEqual(list(outside.iterdir()), [])

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
        skill = b'legacy skill'
        asset = b'legacy asset'
        manifest = {'managed_by': 'skill-bundle-v1', 'skill_name': 'mocketeer-design-contract', 'files': [{'path': 'SKILL.md', 'sha256': projection_io.digest(skill)}, {'path': 'assets/old.html', 'sha256': projection_io.digest(asset)}]}
        content = b'---\nname: mocketeer-design-contract\ndescription: fixture skill\n---\n' + projection_io.HEADER + b'\nnew body'
        owners = [f'{host}/skills/mocketeer-design-contract' for host in ('.claude', '.github', '.agents')]
        for owner in owners:
            self.write(owner + '/SKILL.md', skill)
            self.write(owner + '/assets/old.html', asset)
            self.write(owner + '/bundle-manifest.json', json.dumps(manifest).encode())
            self.plan['outputs'].append({'target': owner + '/SKILL.md', 'owner_root': owner, 'source': '.mxagile/skills/mocketeer-design-contract/SKILL.md', 'data': base64.b64encode(content).decode()})
        report = projection_io.execute(self.root, self.plan, apply=False)
        self.assertTrue(report['ready'], report)
        self.assertEqual({t['state'] for t in report['targets']}, {'TARGET_STALE_GENERATED'})
        projection_io.execute(self.root, self.plan, apply=True)
        for owner in owners:
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
