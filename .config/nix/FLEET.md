# Fleet

One flake, five machines, one router. **nix + home-manager own all config
routing; yadm is retired once the port completes.** Per-machine differences are
module imports in the flake, not filename tricks.

| attr | machine | os | arch | nix role | hostname | user |
|---|---|---|---|---|---|---|
| `work` | MBP M4 Max | macOS 26 | aarch64-darwin | nix-darwin + HM | `HQ-KP2HJMHQ7R` | `jgoon` |
| `personal` | MBP M3 Pro | macOS | aarch64-darwin | nix-darwin + HM | TODO | TODO |
| `mini` | M1 Mac Mini (always on) | macOS 26.6 | aarch64-darwin | nix-darwin + HM, server profile | `Joshuas-Mac-mini` | `jgoon` |
| `pc` | desktop, dual-boots Windows (gaming) | NixOS 26.05 | x86_64-linux | NixOS + HM (folded in) | `pc` | `jgoon` |
| `devspace` | Coder VM (linux-vm-secure) | Ubuntu 24.04 | x86_64-linux | HM standalone | `jgoon-jgoon-box` | `coder` |

Decisions:

- **No second router.** yadm alternates (`##o.Darwin,h.HOST`) become host
  modules; yadm's checkout-to-`~` becomes HM symlinks from the nix store.
- **`.zshrc` stays yadm-owned, permanently** (decided 2026-09-30, after the
  linux plugin work): it must remain a plain editable file because tools
  append to it (`pyenv init`, etc.) — installers can't append to a store
  symlink and won't learn a `.zshrc.local` escape hatch. Nix provides
  (packages ship via HM), dotfiles compose (`.zshrc` sources them). The
  plugin mechanism in `.zshrc` (NIX_PROFILES walk, guarded, in-tree) IS the
  end state for linux boxes — not a bridge to a `programs.zsh` port. See
  "Migration from yadm" for what that means for the waves.
- The repo lives at `~/github/df` (or anywhere); nothing pre-exists at `~`.
- **`pc` is folded in**: its system config now lives in the flake
  (`nixosConfigurations.pc`, hosts/pc/configuration.nix) — the out-of-band
  `/etc/nixos` era ended with the fold. HM rides along as a NixOS module,
  so `sudo nixos-rebuild switch --flake ~/.config/nix#pc` does system+user
  in one shot, same shape as the macs. The box's `/etc/nixos` was emptied
  deliberately (2026-09-30): bare `sudo nixos-rebuild switch` now fails
  loudly instead of silently building the stale pre-fold config. Rollback
  is generations (`nixos-rebuild switch --rollback`); gen 10 is the last
  pre-fold generation.
- Flake attrs are stable role names (`work`, `personal`, ...), not hostnames.

## Layering

- **nix-darwin** (macs): system packages, homebrew, `system.defaults`, fonts.
- **home-manager** (all 5): `~` files, shell config, user packages. On macs as a
  nix-darwin module (one command rebuilds system + user); on linux standalone.
- **hosts/\<attr\>/** = the routing. Each host composes shared modules plus its
  own overrides — this is what replaces yadm alternates.

## Layout

Flake lives at `.config/nix/` during the yadm transition (yadm already
delivers it to `~/.config/nix` on every machine, linux included). Flatten to
the repo root once yadm is retired; commands below assume that final shape.

```
.config/nix/
├── flake.nix
├── hosts/{work,personal,mini,pc,devspace}/default.nix   # per-host routing
├── modules/
│   ├── darwin/common.nix        # system pkgs, defaults, activation scripts
│   └── home/{common,darwin,linux}.nix
├── vscode/
└── Makefile                     # make work | personal | mini | pc | devspace
```

## Tailnet (headscale)

One join mechanism everywhere: the **tailnet-join wizard**
(`~/.agents/skills/tailnet-join/`, shipped to every box by yadm). It
handles every variant — App Store app, standalone pkg, brew formula,
NixOS system CLI — mints a fresh 30d reusable pre-auth key over SSM
(never written to disk, never displayed), runs `tailscale up
--login-server https://headscale.jgoon.com --accept-dns=false`, and
verifies the node on the control plane. Join state persists on disk, so
it runs exactly once per box.

What nix still owns: the aws cli on every box (`tools.nix`) so the
wizard can mint locally; the tailscale daemon/CLI themselves are
bootstrapped however each host gets them (cask, App Store, brew, NixOS
system — the wizard probes all variants). pc (NixOS, folded into the flake
since the system-config fold) gets the same wizard; its config
deliberately does NOT adopt `services.tailscale.authKeyFile` —
that would be a second join mechanism.

Private facts (control-plane instance ID) live in
`~/.config/nix/secrets/` (gitignored); the repo is public. All joins use
`--accept-dns=false` (company VPN DNS conflict).

Facts about the tailnet, decided (do not re-derive):

- **Control plane is headscale** (`https://headscale.jgoon.com`, runs on
  mini). MagicDNS suffix is `tailnet.jgoon.com` (custom), not
  `*.tailnet.ts.net`.
- **`tailscale serve --https` / `tailscale cert` DO NOT WORK** on this
  tailnet: cert provisioning is a Tailscale SaaS endpoint headscale doesn't
  implement (verified 2026-10-07: `tailscale cert` → 500 "account does not
  support getting TLS certs"; `serve --https` → headscale 404). Plain
  `tailscale serve --http=<port> ...` works fine — mappings are local
  tailscaled state, persist across restarts, and are safe.
- Consequence: any tool that assumes Serve HTTPS or `*.tailnet.ts.net`
  names won't work here (e.g. `t3 pair --tailscale`). Plan around it —
  plain-HTTP serve mappings, or a self-cert reverse proxy, or T3 Connect.
- **devspace is NOT on the tailnet, deliberately.** It is a Coder VM
  (company-managed, linux-vm-secure) reachable only via the Coder SSH
  proxy. Do not attempt to install/join tailscale there; if something
  needs tailnet-style reachability to devspace, the answer is Coder or
  T3 Connect, not tailscale.

## Apply

### Hard rules (SSH-critical — breaking one on mini = physical visit)

Authoritative copy: `.agents/skills/fleet-ssh-safety/SKILL.md` (agent-facing)
— this is the human summary:

1. Switch with `make here` only. No per-host switch targets exist.
2. mini's tailscaled is the nix daemon (`org.jgoon.tailscaled`); never brew
   services tailscale. work stays App Store variant (Falcon kills the nix
   daemon). Joins wizard-only; no auth keys in the repo.
3. sshd / Remote Login unmanaged and on — never touch them.
4. After any switch on a remote box, verify a fresh ssh session before
   closing the lifeline (broken `/etc/zsh*` kills new sessions only).
5. Removals only via `make here-zap` after a clean `make plan`; plain
   switches only ever add.

`make doctor` verifies all of these mechanically, sudo-free, over plain
ssh.

### Commands

```sh
make here        # switch THIS machine (host inferred from hostname) — the only way to switch
make here-zap    # same, plus one self-cleaning brew activation; check `make plan` first
make plan        # dry-run: build + brew drift report, changes nothing
make doctor      # verify SSH-critical invariants (see hard rules above)
```

There are no per-host switch targets (`make work` etc. were removed): they
applied a named host's config to whatever machine ran the command — the
classic lockout was `make work` while SSH'd into mini. `make here` maps this
machine's LocalHostName to its flake attr, so cross-applying is impossible.
New hosts get wired in by adding to the host map in the Makefile.

### Switching a remote machine (mini) — the protocol

The authoritative, agent-executable procedure is the **fleet-ssh-safety
skill** (`~/.agents/skills/fleet-ssh-safety/`) — read-only steps over ssh,
the switch itself in a pane on mini's herdr server (`herdr --machine mini
pane ...`), the sudo password as the human gate, fresh-connection verify
before closing the lifeline. Do not improvise a substitute (tmux, nohup,
`ssh -t`). Shape:

- plan (`make plan`) → pane on mini's herdr server → lifeline ssh session
  with the rollback line staged → `sudo make here` in the pane → user
  types the sudo password once (Touch-ID can't fire remotely) → watch to
  completion (`EXIT_CODE=`) → fresh `ssh mini 'echo ok'` → `make doctor`.

`herdr --remote mini` is the human's way to attach to that pane; the
machine API (`herdr --machine mini ...`) is the agent's way to drive it.

## Bootstrap (post-yadm)

**mac:** install nix → `yadm pull` (delivers `~/.config/nix`) → rename the
nix installer's snippets aside so nix-darwin's /etc guard passes
(`sudo mv /etc/zshrc /etc/zshrc.before-nix-darwin`, same for `/etc/bashrc`)
→ `make here`. the Makefile fallback uses the daemon-profile nix path, so
the switch still works after the rename drops nix from new shells.

**pc:** NixOS is installed from the ISO as usual, then `yadm pull`
delivers the flake and `make here` applies it (hostmap infers `pc`). The
system half goes through `nixos-rebuild switch --flake ~/.config/nix#pc`
(sudo) — HM rides along in the same rebuild.

**devspace:** the workspace's $HOME is a persistent EBS volume, but every
workspace stop recreates the EC2 instance from the AMI (root disk — /nix
store, dpkg installs like yadm — is ephemeral). The coder-dotfiles path
is the bootstrap entrypoint: the repo carries a root `install.sh`, the
script `coder dotfiles` runs instead of symlinking dotfiles into `$HOME`
(coder.com/docs/user-guides/workspace-dotfiles). On the box:
`coder dotfiles --yes -b main https://github.com/Jish2/df.git` — it
runs install.sh, which yadm-clones the fleet repo if the volume is
fresh, then hands off to `.config/nix/scripts/devspace-apply.sh`
apply-if-missing: applies the HM generation if the rebuild killed it,
re-asserts the zsh login shell, and arms
devspace-nix-apply.timer (systemd user timer, checks every couple of
minutes, no-op when the generation is healthy). The manual `yadm pull`
+ devspace-apply.sh sequence remains the fallback if `coder dotfiles`
isn't usable (e.g. template constraints). The root `install.sh` is a
no-op on every other host (hostname guard), so `coder dotfiles` on a
mac is harmless.

The herdr server runs as the `herdr-server` systemd user service
(`systemd.user.services.herdr-server` in hosts/devspace): waits for the
home-volume mount with the same st_dev guard, restarts on failure. The
binary is herdr's self-updating `~/.local/bin/herdr` (on the home
volume), not a nix store path — `herdr update` works and the unit
follows it. NOTE: because the linger user manager starts ~70s before
home-coder.mount (facts above), the unit dir is not visible at boot —
the server comes back when the re-apply guard chain runs HM activation
on first login, not at boot.

## Herdr server as a fleet-wide service

herdr is the fleet multiplexer — the only surface an agent can drive and
the human can attach to. Every box now declares its server in nix
(`fleet.herdr` module on darwin, `systemd.user.services.herdr-server` on
linux), so a rebooted or rebuilt box comes back with the server already
running instead of sitting dead until someone notices:

- **mini** — LaunchDaemon (`fleet.herdr.daemon = true`): runs from boot
  WITHOUT login, as the user (the box is headless with auto-login off;
  a LaunchAgent would never fire after a reboot).
- **work / personal** — LaunchAgent: starts at login, alive while logged
  in. Daily laptops; that is the right lifecycle.
- **pc** — systemd user service + `linger = true` on the user (set in
  hosts/pc/configuration.nix): user manager runs from boot (pc has no
  separate home mount, so units load normally). The herdr **binary is
  flake-managed** (`inputs.herdr` in hosts/pc — pinned release tag, CLI
  and server from one closure); `~/.local/bin/herdr` stays first in the
  wrapper's resolution order as the self-update escape hatch.
- **devspace** — HM user service (see the devspace paragraphs above):
  returns via the re-apply guard chain on first login after a rebuild;
  the boot-time unit dir is not visible before the home mount.

All of them resolve the herdr binary at start (`~/.local/bin/herdr`,
nix profile, brew formula — whichever the box has) instead of pinning a
nix store path: `herdr update` / `brew upgrade` keep working, and the
service follows the upgraded binary. KeepAlive/Restart covers crashes;
`herdr server stop` (clean exit) is not fought by the supervisor.

Two rebuild-recovery facts, both measured live:
- the linger user manager reaches default.target ~70s BEFORE
  home-coder.mount lands, so $HOME/.config/systemd/user units never load
  at boot (the template's own services dodge this by being explicitly
  started by the Coder startup script). The `.zshrc.local##o.Linux,h.jgoon-jgoon-box`
  alternate re-arms the timer+service on the first interactive zsh after
  a rebuild.
- the yadm binary is dpkg-installed on the (ephemeral) root disk — it
dies on every rebuild. tools.nix ships yadm in the HM profile, so the
re-apply restores it. Same for the login shell: the AMI ships /bin/bash
and chsh resets on rebuild — the re-apply re-asserts /usr/bin/zsh
(passwordless sudo is AMI-baked). Later config updates:
`yadm pull && make here` on the box (the hostmap maps
jgoon-jgoon-box → devspace).

## If onboarding hurt: rollback

- packages: cleanup defaults to `"none"` — nothing was ever uninstalled,
  nothing to restore. `make plan` shows drift going forward.
- system: `darwin-rebuild --list-generations`, then
  `$(darwin-rebuild --list-generations | grep <prev> | awk '{print $NF}')/activate`
  to roll back one generation. nix-darwin generations are additive-safe.
- nix itself: the official uninstaller removes /nix + /etc edits; brew
  remains your package manager again.
- defaults: the 617 imported keys re-assert each rebuild — delete a key from
  hand-curated keys in modules/darwin/common.nix — change or delete them
  there. macs never inherit a bulk snapshot (see below).

## Per-mac onboarding (work: done · mini: import verified, first switch pending)

1. `brew bundle dump` → reconcile into `hosts/<name>/default.nix`.
   Removal is opt-in: cleanup defaults to `"none"` fleet-wide, so a rebuild
   only ever ADDS. Review with `make plan HOST=<name>` on the host (builds
   without activating + reports brew/cask drift); when the 'would be REMOVED'
   list is empty the host is zap-ready — `make <host>-zap` (or `make
   here-zap`) runs one explicit self-cleaning switch, and plain switches
   never remove anything.
2. defaults: the mac inherits the hand-curated set in
   `modules/darwin/common.nix`. To hunt for more: `scripts/fetch-baseline.sh`
   once, then `scripts/export-defaults.py --baseline baseline/tahoe
   /tmp/current.nix` writes a gitignored report of this machine's
   non-factory keys — hand-pick lines into modules, never import the file.
3. HM `.bak`-backs-up any dotfile it replaces on first switch.

## Migration from yadm

yadm stays live until the last file moves. Port in waves:

1. Stand up the flake + module split on `work`; HM manages nothing yet.
2. Move files wave by wave — git/tmux → nvim → the rest. Each landing:
   delete from the yadm repo, wire as `home.file`/`programs.*` (HM
   auto-backs-up and replaces the real file with a store symlink).
   `.zshrc` is NOT in the waves: it stays yadm-owned permanently (see
   Decisions) — `programs.zsh.enable` would take over the whole file and
   break the installer-append workflow.
3. GUI-mutated files (`karabiner.json`, iterm2 plist, zen mods) can't be
   read-only store symlinks — keep imperative or copy-on-activation; decide
   per file.
4. Empty yadm repo → delete it and the README's install steps.

## Open questions

- [x] devspace arch and home persistence → x86_64, persistent $HOME volume,
      ephemeral root (AMI-baked nix) — re-apply unit landed 2026-09-30
- [ ] hostnames + users for personal (devspace resolved: jgoon-jgoon-box/coder)
- [x] what services does mini run → tailscaled (system daemon, NOT brew
  services — ssh depends on it), postgresql@14 (brew service), plus a fleet
  of hand-rolled launchagents: cloudflared tunnels, BlueBubbles, headscale,
  hub-mac-control, agent-device proxy, t3code, openpoker sim… none
  nix-managed yet (see the comment block in hosts/mini/default.nix); no
  plex/homebridge
- [ ] which work-only tools live only on `work` vs all macs — deferred
  until `personal` onboards; then curate the every-machine set from three
  imports (mini keeps its pure status-quo import per the 2026-09-23
  decision; its overlap with work is the seed of a shared devtools set)
- [ ] secrets strategy (currently out of band; sops-nix later if desired)
