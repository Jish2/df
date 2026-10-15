import io
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

import install_notifier
import prepare_plist
import runner


class StartupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.config = {
            "python": "/nix/python3", "git": "git", "host": "devspace",
            "repository": "https://github.rbx.com/jgoon/vm-mac-bridge.git",
            "branch": "main", "update_timeout": 60,
            "remote_script": "/home/coder/.codex/skills/mac-command/scripts/bridge.py",
            "notifier": str(self.home / "Applications/vm-mac-bridge.app/Contents/MacOS/terminal-notifier"),
            "terminal_command": str(self.home / "Library/Application Support/vm-mac-bridge/start.command"),
            "reconnect_seconds": 15, "max_timeout": 120, "notification_timeout": None,
        }

    def test_start_opens_command_in_terminal(self):
        with mock.patch.object(runner.subprocess, "run") as execute:
            self.assertEqual(runner.start(self.config, self.home), 0)
        execute.assert_called_once_with(
            ["/usr/bin/open", "-a", "Terminal", self.config["terminal_command"]], check=True,
        )

    def test_duplicate_start_does_not_open_another_terminal(self):
        with runner.lock_file(self.home), mock.patch.object(runner.subprocess, "run") as execute:
            self.assertTrue(runner.running(self.home))
            self.assertEqual(runner.start(self.config, self.home), 0)
            execute.assert_not_called()
        self.assertFalse(runner.running(self.home))

    def test_run_requires_interactive_input(self):
        with mock.patch.object(runner.sys, "stdin", io.StringIO("yes\n")), \
                mock.patch.object(runner.subprocess, "Popen") as execute:
            with self.assertRaisesRegex(RuntimeError, "interactive terminal"):
                runner.run(self.config, self.home)
            execute.assert_not_called()

    def test_reconnect_keeps_local_approval_and_stops_on_interrupt(self):
        first = mock.MagicMock()
        first.__enter__.return_value = first
        first.wait.return_value = 255
        second = mock.MagicMock()
        second.__enter__.return_value = second
        second.wait.return_value = 130
        with mock.patch.object(runner.sys.stdin, "isatty", return_value=True), \
                mock.patch.object(runner, "refresh_bridge", return_value=Path("/latest/bridge.py")) as update, \
                mock.patch.object(runner.subprocess, "Popen", side_effect=[first, second]) as execute, \
                mock.patch.object(runner.time, "sleep") as sleep, \
                mock.patch.object(runner.sys, "stdout", io.StringIO()):
            self.assertEqual(runner.run(self.config, self.home), 0)
        sleep.assert_called_once_with(15)
        self.assertEqual(execute.call_count, 2)
        args = execute.call_args.args[0]
        self.assertEqual(args[:4], ["/nix/python3", "/latest/bridge.py", "mac", "devspace"])
        self.assertEqual(update.call_count, 2)
        self.assertIn("--notify", args)
        self.assertNotIn("--notification-timeout", args)
        self.assertFalse(runner.running(self.home))

    def test_second_runner_does_not_connect(self):
        with runner.lock_file(self.home), \
                mock.patch.object(runner.sys.stdin, "isatty", return_value=True), \
                mock.patch.object(runner.subprocess, "Popen") as execute, \
                mock.patch.object(runner.sys, "stdout", io.StringIO()):
            self.assertEqual(runner.run(self.config, self.home), 0)
            execute.assert_not_called()

    def test_failed_update_does_not_launch_a_cached_helper(self):
        with mock.patch.object(runner.sys.stdin, "isatty", return_value=True), \
                mock.patch.object(runner, "refresh_bridge", side_effect=RuntimeError("update failed")), \
                mock.patch.object(runner.subprocess, "Popen") as execute, \
                mock.patch.object(runner.time, "sleep", side_effect=KeyboardInterrupt), \
                mock.patch.object(runner.sys, "stdout", io.StringIO()), \
                mock.patch.object(runner.sys, "stderr", io.StringIO()):
            self.assertEqual(runner.run(self.config, self.home), 0)
            execute.assert_not_called()
        self.assertFalse(runner.running(self.home))


class SourceUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.remote = self.root / "upstream"
        self.git = shutil.which("git")
        self.assertIsNotNone(self.git, "git is required for source-update tests")
        self.command("init", "--initial-branch", "main", str(self.remote))
        self.commit("first")
        self.config = {"git": self.git, "repository": str(self.remote),
                       "branch": "main", "update_timeout": 5}

    def command(self, *arguments, cwd=None):
        return subprocess.run([self.git, *arguments], cwd=cwd, check=True,
                              capture_output=True, text=True)

    def commit(self, version):
        (self.remote / "bridge.py").write_text(f"print({version!r})\n")
        self.command("add", "bridge.py", cwd=self.remote)
        self.command("-c", "user.name=Bridge Tests", "-c", "user.email=bridge-tests@example.invalid",
                     "commit", "-m", version, cwd=self.remote)

    def test_initial_checkout_and_later_main_commit_are_used(self):
        with mock.patch.object(runner.sys, "stdout", io.StringIO()):
            bridge = runner.refresh_bridge(self.config, self.home)
            self.assertEqual(bridge.read_text(), "print('first')\n")
            self.commit("latest")
            updated = runner.refresh_bridge(self.config, self.home)
        self.assertEqual(updated, bridge)
        self.assertEqual(updated.read_text(), "print('latest')\n")
        cached_revision = self.command("rev-parse", "HEAD", cwd=bridge.parent).stdout
        upstream_revision = self.command("rev-parse", "HEAD", cwd=self.remote).stdout
        self.assertEqual(cached_revision, upstream_revision)

    def test_local_edits_are_preserved_and_update_is_refused(self):
        with mock.patch.object(runner.sys, "stdout", io.StringIO()):
            bridge = runner.refresh_bridge(self.config, self.home)
        bridge.write_text("local edits\n")
        self.commit("latest")
        with self.assertRaisesRegex(RuntimeError, "local changes"):
            runner.refresh_bridge(self.config, self.home)
        self.assertEqual(bridge.read_text(), "local edits\n")

    def test_main_history_rewrite_tracks_current_tip(self):
        with mock.patch.object(runner.sys, "stdout", io.StringIO()):
            bridge = runner.refresh_bridge(self.config, self.home)
            self.commit("second")
            runner.refresh_bridge(self.config, self.home)
            self.assertEqual(bridge.read_text(), "print('second')\n")
            self.command("reset", "--hard", "HEAD~1", cwd=self.remote)
            runner.refresh_bridge(self.config, self.home)
        self.assertEqual(bridge.read_text(), "print('first')\n")

    def test_unavailable_upstream_is_an_error_with_cache_preserved(self):
        with mock.patch.object(runner.sys, "stdout", io.StringIO()):
            bridge = runner.refresh_bridge(self.config, self.home)
        self.remote.rename(self.root / "moved-upstream")
        with self.assertRaises(subprocess.CalledProcessError):
            runner.refresh_bridge(self.config, self.home)
        self.assertEqual(bridge.read_text(), "print('first')\n")

    def test_failed_initial_clone_leaves_no_partial_cache(self):
        self.remote.rename(self.root / "moved-upstream")
        with self.assertRaises(subprocess.CalledProcessError):
            runner.refresh_bridge(self.config, self.home)
        self.assertFalse(runner.source_cache(self.config, self.home).exists())
        self.assertEqual(list((self.home / "Library/Application Support/vm-mac-bridge/sources").iterdir()), [])

    def test_existing_unmanaged_directory_is_not_modified(self):
        cache = runner.source_cache(self.config, self.home)
        cache.mkdir(parents=True)
        (cache / "keep.txt").write_text("keep")
        with self.assertRaisesRegex(RuntimeError, "unmanaged"):
            runner.refresh_bridge(self.config, self.home)
        self.assertEqual((cache / "keep.txt").read_text(), "keep")

    def test_missing_entrypoint_is_not_accepted(self):
        self.command("rm", "bridge.py", cwd=self.remote)
        self.command("-c", "user.name=Bridge Tests", "-c", "user.email=bridge-tests@example.invalid",
                     "commit", "-m", "remove entrypoint", cwd=self.remote)
        with self.assertRaisesRegex(RuntimeError, "entrypoint"):
            runner.refresh_bridge(self.config, self.home)
        self.assertFalse(runner.source_cache(self.config, self.home).exists())


class NotifierTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source.app"
        self.target = self.root / "Applications/vm-mac-bridge.app"
        self.make_app(self.source, "new")

    def make_app(self, app, content, bundle_id=install_notifier.BUNDLE_ID):
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": bundle_id}))
        binary = app / "Contents/MacOS/terminal-notifier"
        binary.write_text(content)
        binary.chmod(0o555)

    def content(self):
        return (self.target / "Contents/MacOS/terminal-notifier").read_text()

    def test_install_signs_before_replacing_and_registers_then_is_idempotent(self):
        self.make_app(self.target, "previous")

        def execute(args, check):
            self.assertTrue(check)
            if args[0] == "/usr/bin/codesign":
                self.assertEqual(self.content(), "previous")
                self.assertEqual(install_notifier.bundle_id(Path(args[-1])), install_notifier.BUNDLE_ID)
            else:
                self.assertEqual(args, [install_notifier.REGISTER, "-f", str(self.target)])
                self.assertEqual(self.content(), "new")

        with mock.patch.object(install_notifier.subprocess, "run", side_effect=execute) as run:
            install_notifier.install(self.source, self.target)
            install_notifier.install(self.source, self.target)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(self.content(), "new")

    def test_failed_signing_preserves_existing_app(self):
        self.make_app(self.target, "previous")
        with mock.patch.object(install_notifier.subprocess, "run",
                               side_effect=subprocess.CalledProcessError(1, "codesign")):
            with self.assertRaises(subprocess.CalledProcessError):
                install_notifier.install(self.source, self.target)
        self.assertEqual(self.content(), "previous")

    def test_failed_registration_restores_existing_app(self):
        self.make_app(self.target, "previous")
        with mock.patch.object(install_notifier.subprocess, "run",
                               side_effect=[None, subprocess.CalledProcessError(1, "lsregister")]):
            with self.assertRaises(subprocess.CalledProcessError):
                install_notifier.install(self.source, self.target)
        self.assertEqual(self.content(), "previous")

    def test_other_app_and_symlink_are_not_replaced(self):
        self.make_app(self.target, "unrelated", "com.example.other")
        with mock.patch.object(install_notifier.subprocess, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "another app"):
                install_notifier.install(self.source, self.target)
            run.assert_not_called()
        self.assertEqual(self.content(), "unrelated")
        linked = self.root / "linked.app"
        linked.symlink_to(self.root / "missing.app")
        with self.assertRaisesRegex(RuntimeError, "another app"):
            install_notifier.install(self.source, linked)
        self.assertTrue(linked.is_symlink())

    def test_plist_keeps_upstream_version_with_separate_identity(self):
        source = self.root / "source.plist"
        target = self.root / "Info.plist"
        source.write_bytes(plistlib.dumps({"CFBundleExecutable": "${EXECUTABLE_NAME}",
                                          "CFBundleName": "${PRODUCT_NAME}",
                                          "CFBundleIdentifier": "fr.julienxx.oss.terminal-notifier",
                                          "CFBundleShortVersionString": "3.1.0", "LSUIElement": True}))
        prepare_plist.prepare(source, target)
        info = plistlib.loads(target.read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], install_notifier.BUNDLE_ID)
        self.assertEqual(info["CFBundleName"], "vm-mac-bridge")
        self.assertEqual(info["CFBundleExecutable"], "terminal-notifier")
        self.assertEqual(info["CFBundleShortVersionString"], "3.1.0")
        self.assertTrue(info["LSUIElement"])


if __name__ == "__main__":
    unittest.main()
