## Work Mac VM–Mac bridge

`hosts/work` enables `fleet.vmMacBridge`. After merging, stop the old manually
started helper with Ctrl-C, then apply the work Mac's config with `make here`
from `~/.config/nix`. The Home Manager login agent opens a Terminal window for
the approval helper at graphical login; it also starts when its new agent is
loaded. The helper reconnects to the existing `devspace` SSH alias every 15
seconds after a disconnect. SSH keys, Coder access, and the alias are existing
prerequisites; this module does not create them.

Every command still requires local approval. Short commands have notification
Approve/Reject actions; long commands require review in the Terminal window.
Keep that window open. The dedicated `vm-mac-bridge` notifier app needs its
normal macOS notification permission. Set its style to Alerts for persistent
prompts, or Banners if preferred; regular terminal-notifier has its own setting.
macOS may also ask to allow the Home Manager login item in the background.

```sh
vm-mac-bridge          # open the helper in Terminal if it is not already running
vm-mac-bridge status   # running / stopped
vm-mac-bridge run      # use this terminal instead
```

Ctrl-C stops the helper without a restart loop. To pick up a later helper/config
update, stop it and run `vm-mac-bridge` again; an existing helper is left alone
on rebuild. Disable `fleet.vmMacBridge.enable` to remove automatic startup.
Other Macs keep their current config.

The VM must have the matching protocol-2 script installed at
`/home/coder/.codex/skills/mac-command/scripts/bridge.py`. The VM
`mac-command send` returns an ID immediately; poll `mac-command status ID --json`
for the result. `--expires-in SECONDS` controls the queue/approval window (600
seconds by default), while `send --wait` selects blocking behavior. The Mac
uses the request's expiry unless `fleet.vmMacBridge.notificationTimeout` sets
a shorter approval cap. Execution remains capped at 120 seconds by default.

The module lives in `modules/darwin/fleet-vm-mac-bridge.nix`; source provenance
and test instructions are in [packages/vm-mac-bridge](packages/vm-mac-bridge/README.md).

## setup log

1. install nix
   `$ sh <(curl -L https://nixos.org/nix/install)`

2. create a flake
   `$ nix flake init -t nix-darwin/master`

3. update flake hostname
   `$ sed -i '' "s/simple/$(scutil --get LocalHostName)/" flake.nix`

4. install nix-darwin
   `$ nix run --extra-experimental-features 'nix-command flakes' nix-darwin -- switch --flake ~/.config/nix`

### updating nix

   `$ nix flake update`

### installing home-manager [^1]

### vscode syncing

1. `settings.json` and `keybindings.json` managed through yadm.
2. extensions managed through `Brewfile.vscode`
3. extension installation managed through `flake.nix`
4. disabled extensions managed through `flake.nix` sqlite injection script.

[^1]: <https://nix-community.github.io/home-manager/#sec-install-nix-darwin-module>
