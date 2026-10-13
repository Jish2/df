#!/usr/bin/env python3
"""Exercise private skill selection and link ownership in temporary folders."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

source = Path(__file__).resolve().parents[2] / '.local/bin/skills-sync'
spec = importlib.util.spec_from_loader('skills_sync', importlib.machinery.SourceFileLoader('skills_sync', str(source)))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class SkillLinks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repo = self.root / 'repo'
        self.links = self.root / 'links'
        self.state = self.root / 'state'
        self.state.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def skill(self, relative):
        path = self.repo / relative
        path.mkdir(parents=True)
        (path / 'SKILL.md').write_text('---\nname: example\ndescription: Example skill\n---\n')
        return path.resolve()

    def load(self, machine='work'):
        return sync.link_skills(self.repo, self.links, self.state, machine)

    def test_common_and_machine_override(self):
        common = self.skill('common/shared')
        self.skill('common/example')
        specific = self.skill('machines/work/example')
        other = self.skill('machines/pc/desktop')
        self.assertEqual(self.load(), 2)
        self.assertEqual((self.links / 'shared').resolve(), common)
        self.assertEqual((self.links / 'example').resolve(), specific)
        self.assertFalse((self.links / 'desktop').exists())
        self.assertEqual(self.load('pc'), 3)
        self.assertEqual((self.links / 'example').resolve(), self.repo / 'common/example')
        self.assertEqual((self.links / 'desktop').resolve(), other)

    def test_collisions_preserve_existing_skills_before_any_changes(self):
        self.skill('common/a-new')
        self.skill('common/z-public')
        public = self.links / 'z-public'
        public.mkdir(parents=True)
        with self.assertRaises(sync.SyncError):
            self.load()
        self.assertTrue(public.is_dir())
        self.assertFalse((self.links / 'a-new').exists())

    def test_stale_links_removed_but_user_replacements_preserved(self):
        self.skill('machines/work/old')
        self.assertEqual(self.load(), 1)
        replacement = self.root / 'my-skill'
        replacement.mkdir()
        (self.links / 'old').unlink()
        (self.links / 'old').symlink_to(replacement)
        self.assertEqual(self.load('pc'), 0)
        self.assertEqual((self.links / 'old').resolve(), replacement)
        (self.links / 'old').unlink()
        self.load()
        self.load('pc')
        self.assertFalse((self.links / 'old').is_symlink())

    def test_idempotent_loading(self):
        self.skill('common/example')
        self.load()
        before = (self.state / 'links.json').read_text()
        self.load()
        self.assertEqual((self.state / 'links.json').read_text(), before)
        self.assertEqual(len(list(self.links.iterdir())), 1)

    def test_matching_unmanaged_symlink_is_not_adopted(self):
        target = self.skill('common/example')
        self.links.mkdir()
        (self.links / 'example').symlink_to(target)
        with self.assertRaises(sync.SyncError):
            self.load()
        self.assertEqual((self.links / 'example').resolve(), target)
        self.assertFalse((self.state / 'links.json').exists())

    def test_offline_and_optional_missing_checkout(self):
        args = ['--machine', 'work', '--repo-dir', str(self.repo), '--link-dir', str(self.links),
                '--state-dir', str(self.state), '--offline']
        self.assertEqual(sync.main(args), 1)
        self.assertEqual(sync.main(args + ['--optional']), 0)

    def test_skills_cannot_point_outside_the_checkout(self):
        external = self.root / 'external'
        external.mkdir()
        (external / 'SKILL.md').write_text('Example')
        common = self.repo / 'common'
        common.mkdir(parents=True)
        (common / 'external').symlink_to(external)
        with self.assertRaises(sync.SyncError):
            self.load()

    def test_role_uses_existing_host_map(self):
        with patch.object(sync, 'command', return_value='devspace') as command:
            self.assertEqual(sync.machine_role(None, self.state), 'devspace')
        self.assertEqual(command.call_args.args[0][-1], 'skills-machine')

    def test_saved_role_and_explicit_override(self):
        (self.state / 'machine').write_text('personal\n')
        with patch.object(sync, 'command') as command:
            self.assertEqual(sync.machine_role(None, self.state), 'personal')
            self.assertEqual(sync.machine_role('work', self.state), 'work')
        command.assert_not_called()

    def test_unknown_machine_can_load_common_skills(self):
        self.skill('common/example')
        self.skill('machines/work/specific')
        with patch.object(sync, 'command', side_effect=sync.SyncError('Unavailable')):
            role = sync.machine_role(None, self.state)
        self.assertEqual(role, 'unknown')
        self.assertEqual(self.load(role), 1)

    def test_invalid_role_is_rejected(self):
        for role in ('', '..', '../work', '/work'):
            with self.assertRaises(sync.SyncError):
                sync.machine_role(role, self.state)


if __name__ == '__main__':
    unittest.main()
