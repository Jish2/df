# df — dotfiles & fleet config

Fleet plan and per-machine docs: [`.config/nix/FLEET.md`](.config/nix/FLEET.md)

## Commands

- `make here` — switch this machine to its own config (host inferred from hostname). **This is the only way to switch any machine.** The per-host targets (`make work`, `make mini`, ...) were removed: they applied a *named* host's config to whatever machine ran them, so `make work` while SSH'd into mini rewired mini with work's config. If a new machine joins the fleet, add its hostname to the host map in `.config/nix/Makefile` and it gets `make here` for free.
- `make here-zap` — one explicit self-cleaning switch (removes undeclared brews/casks). Run `make plan` first and check the "would be REMOVED" list — never zap if anything SSH depends on (tailscale, cloudflared) shows up there.
- `make plan` — dry-run: builds without activating + reports brew drift both directions. Run before every zap and after every import.
- `make doctor` — checks the SSH-critical invariants (see below). Runs sudo-free, so it works over plain `ssh mini 'make -C ~/.config/nix doctor'` too.

## SSH-critical invariants (mini is the remote box)

If these break on mini, the only fix is a physical visit. `make doctor` verifies them; follow these rules regardless.

1. **tailscaled on mini is the nix launchd daemon** (`fleet.tailscaled.enable = true` in hosts/mini → LaunchDaemon `org.jgoon.tailscaled`, state in `/var/lib/tailscale/tailscaled.state`). The daemon binary comes from the nix store — never installed, upgraded, or removed by brew. Keep the brew `tailscale` formula CLI declared in hosts/mini, but brew must never own a *second* daemon. **work is the exception**: `fleet.tailscaled.enable = false` there because corporate EDR (CrowdStrike Falcon) SIGKILLs the nix daemon; work stays on the App Store network-extension variant. Never enable the nix daemon on work.
2. **Joins are wizard-only.** The tailnet-join wizard (~/.agents/skills/tailnet-join) is the only join mechanism — this module and this repo never ship auth keys (no `authKeyFile` anywhere). Node identity lives in `/var/lib/tailscale/tailscaled.state` on each box.
3. **Remote Login stays on, sshd unmanaged.** The flake deliberately doesn't configure sshd or Remote Login. Never disable them, never add `services.openssh` config on mini.
4. **`/etc/zshenv` and friends.** sshd runs remote commands through the login shell, so a broken shell init file kills every *new* ssh session while old ones keep working — it looks exactly like a dead box. `make here` rewrites these files (nix-darwin's set-environment); always verify a fresh connection after switching.
5. **Zap rules.** Cleanup defaults to `none` — plain switches only ever add. Before any `here-zap`, confirm the plan's "would be REMOVED" list contains nothing SSH depends on (tailscale, cloudflared).

## Protocol: switching a remote machine (mini)

1. `make plan HOST=mini` — dry-run, changes nothing. Fix anything surprising before proceeding.
2. Run the switch in a **herdr remote pane**: `herdr --remote mini` attaches to herdr's server on mini, where panes are persistent — a mid-activation disconnect must not abort the switch, and the pane keeps the log. Bare `ssh` in a scratch terminal can do neither.
3. Open a **second ssh session to mini** and keep it open as a lifeline for the whole switch. Existing sessions keep their shell — only new connections exercise the new `/etc/zshenv`.
4. Keep the rollback one-liner ready in the lifeline:
   `$(darwin-rebuild --list-generations | grep <prev-gen-id> | awk '{print $NF}')/activate`
5. Run `make here` in the herdr remote pane.
6. From your laptop, open a **fresh** ssh session: `ssh mini 'echo ok'`. Only close the lifeline after this succeeds.
7. Optional belt-and-suspenders: run `make doctor` on mini (fresh session) after the switch.

## Machine map

| attr | machine | role |
|---|---|---|
| `work` | MBP M4 Max | nix-darwin + HM, App Store tailscale (Falcon) |
| `personal` | MBP M3 Pro | nix-darwin + HM (not onboarded yet) |
| `mini` | M1 Mac Mini, always-on server | nix-darwin + HM, nix tailscaled daemon |
| `pc` | NixOS desktop | out-of-band, `/etc/nixos` (not this flake) |
| `devspace` | Coder VM | HM standalone, ephemeral, x86_64 |

New machines: add the hostname→attr mapping to `.config/nix/Makefile` (host map), create `hosts/<attr>/default.nix`, then `make here` on the machine works. Tailnet peers + stable IPs live in `fleet.nix`.
