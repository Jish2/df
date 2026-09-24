# Fleet

One flake, five machines, one router. **nix + home-manager own all config
routing; yadm is retired once the port completes.** Per-machine differences are
module imports in the flake, not filename tricks.

| attr | machine | os | arch | nix role | hostname | user |
|---|---|---|---|---|---|---|
| `work` | MBP M4 Max | macOS 26 | aarch64-darwin | nix-darwin + HM | `HQ-KP2HJMHQ7R` | `jgoon` |
| `personal` | MBP M3 Pro | macOS | aarch64-darwin | nix-darwin + HM | TODO | TODO |
| `mini` | M1 Mac Mini (always on) | macOS 26.6 | aarch64-darwin | nix-darwin + HM, server profile | `Joshuas-Mac-mini` | `jgoon` |
| `pc` | desktop, dual-boots Windows (gaming) | Omarchy (Arch) | x86_64-linux | HM standalone | TODO | TODO |
| `devspace` | Coder VM | Linux | TODO | HM standalone | n/a (ephemeral) | TODO |

Decisions:

- **No second router.** yadm alternates (`##o.Darwin,h.HOST`) become host
  modules; yadm's checkout-to-`~` becomes HM symlinks from the nix store.
- The repo lives at `~/github/df` (or anywhere); nothing pre-exists at `~`.
- **`pc` stays Omarchy** — nix layers the user env on top; revisit only if
  Omarchy becomes annoying.
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

## Apply

```sh
make work        # darwin-rebuild switch --flake ~/.config/nix#work   (macs; HM rides along)
make pc          # home-manager switch --flake ~/.config/nix#pc       (linux)
make plan HOST=work   # dry-run: build + brew drift report, changes nothing
```

## Bootstrap (post-yadm)

**mac:** install nix → `git clone` → `nix run nix-darwin -- switch --flake ~/github/df#work`

**pc:** `sudo pacman -S nix` → clone → `make pc`
(first run uses the `nix run home-manager` fallback in the Makefile)

**devspace:** same, `--no-daemon` if no sudo; put both steps in the Coder
startup script so rebuilds re-apply. TODO: confirm arch + home persistence.

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
2. Move files wave by wave — zsh/git/tmux → nvim → the rest. Each landing:
   delete from the yadm repo, wire as `home.file`/`programs.*` (HM
   auto-backs-up and replaces the real file with a store symlink).
3. GUI-mutated files (`karabiner.json`, iterm2 plist, zen mods) can't be
   read-only store symlinks — keep imperative or copy-on-activation; decide
   per file.
4. Empty yadm repo → delete it and the README's install steps.

## Open questions

- [ ] hostnames + users for personal / pc / devspace
- [ ] devspace arch and home persistence
- [x] what services does mini run → tailscaled (system daemon, NOT brew
  services — ssh depends on it), postgresql@14 (brew service), plus a fleet
  of hand-rolled launchagents: cloudflared tunnels, BlueBubbles, headscale,
  hub-mac-control, agent-device proxy, t3code, openpoker sim… none
  nix-managed yet (see the comment block in hosts/mini/default.nix); no
  plex/homebridge
- [ ] which work-only tools live only on `work` vs all macs (mini's brew
  import shows heavy overlap with work — argocd/helm/awscli/etc. — so
  consider promoting a shared `modules/darwin/devtools` brew set)
- [ ] secrets strategy (currently out of band; sops-nix later if desired)
