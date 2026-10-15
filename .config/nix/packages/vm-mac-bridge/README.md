# VM–Mac bridge launcher

The launcher fetches the current `main` branch from
[jgoon/vm-mac-bridge](https://github.rbx.com/jgoon/vm-mac-bridge) before starting
or reconnecting the helper. The Mac uses a private, app-owned checkout under
`~/Library/Application Support/vm-mac-bridge/sources`; the dotfiles contain no
copy of `bridge.py`. Git runs with the Mac user's existing authentication,
at runtime. The Nix build only needs the launcher and public notifier source.

Git operations have a 60-second timeout. If fetching fails, the launcher
reports the failure and retries after the reconnect delay; it never starts
the older cached helper after a failed update. It refuses to overwrite local
edits or an unmanaged cache directory. The terminal prints the Git revision
it starts. A running helper picks up upstream changes on its next restart or
reconnect, so an active command is allowed to finish before code changes.
The VM skill and transport remain installed separately; keep them compatible
with the upstream helper.

`runner.py` owns the local single-instance lock and SSH reconnect loop. It
launches the fetched bridge in Terminal, with approval required
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

The update tests use temporary local Git repositories. They do not open
Terminal, send notifications, or connect to GitHub or a VM.
