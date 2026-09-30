# df — dotfiles & fleet config

Fleet map, per-machine details, tailnet, bootstrap: [`.config/nix/FLEET.md`](.config/nix/FLEET.md)

## Switching

- `make here` — the ONLY way to switch. Host is inferred from this machine's LocalHostName. There are deliberately no per-host switch targets: `make work` while ssh'd into mini rewired mini with work's config — that class of failure is now impossible by construction.
- `make here-zap` — one self-cleaning switch. Run `make plan` first; if anything ssh depends on (tailscale, cloudflared) appears under "would be REMOVED", declare it in the host module before zapping.
- `make plan` — dry-run: build + brew drift report. Nothing activates.
- `make doctor` — verify the SSH-critical invariants (below); sudo-free, runs over plain `ssh mini 'make -C ~/.config/nix doctor'`.

**Switching a machine over ssh (mini): follow the protocol in FLEET.md** — herdr remote pane, second ssh lifeline, fresh-connection verify before closing anything. Don't improvise.

## SSH-critical invariants

mini is a remote box — if these break, fixing it means a physical visit. `make doctor` verifies them; follow them regardless.

1. **mini's tailscaled is the nix daemon** (`fleet.tailscaled.enable = true` → LaunchDaemon `org.jgoon.tailscaled`). Never start a second daemon via brew services. **work is the exception**: Falcon SIGKILLs the nix daemon — keep `mkForce false` there (App Store variant).
2. **Tailnet joins are wizard-only** (`~/.agents/skills/tailnet-join`). No auth keys in this repo.
3. **sshd / Remote Login stay unmanaged and on.** Never touch `/etc/ssh/sshd_config` or disable Remote Login.
4. **`/etc/zsh*` files**: a broken one kills every *new* ssh session while old ones live. After any switch on a remote box, verify with a fresh `ssh mini 'echo ok'` before closing the lifeline.
5. **Plain switches only ever add** (cleanup = "none"). Removals happen only via `here-zap` after a clean plan.
