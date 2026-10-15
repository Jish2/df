# VM–Mac bridge snapshot

`bridge.py` is copied unchanged from
[jgoon/vm-mac-bridge](https://github.rbx.com/jgoon/vm-mac-bridge), commit
`ca0a3365dac821c66cf8ea36ed1f68a8b7d0ea9f`. Keeping this small stdlib-only
snapshot in the dotfiles avoids requiring Enterprise GitHub authentication
inside a Nix build. Update it deliberately alongside the VM copy; both ends
must support protocol version 2. The VM skill and CLI remain installed separately.

`runner.py` owns the local single-instance lock and SSH reconnect loop. It
launches the existing bridge unchanged, in Terminal, with approval required
for every command. Reconnecting never resubmits a command. `Ctrl-C` stops it.

`notifier.nix` builds pinned terminal-notifier 3.1.0 with the Nix compiler and
SDK. Home Manager installs a writable user-owned copy in
`~/Applications/vm-mac-bridge.app`, signs the complete app with Apple's
`codesign`, and registers it with LaunchServices. The bundle identifier matches
the manually built app, so its notification settings remain separate from
regular terminal-notifier. Permission and Alerts/Banners stay macOS settings.

Run the local startup/installation tests with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .config/nix/packages/vm-mac-bridge -v
```

These tests do not open Terminal, send notifications, or connect to a VM.
