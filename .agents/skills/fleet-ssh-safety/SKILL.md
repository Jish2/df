---
name: fleet-ssh-safety
description: Required before switching any fleet machine (`make here` only), touching tailscale/tailscaled or sshd/Remote Login, running `brew services` or any brew removal, or editing the df/nix config. mini is a remote box — SSH breakage means a physical visit. Covers all 5 machines in the df repo.
---

# fleet-ssh-safety

The df repo (`~/github/df`, yadm worktree `~`) manages a 5-machine fleet.
**mini** (Mac mini, always on) is remote: if it drops off the tailnet or ssh
dies, fixing it means physically going there. Everything below exists to make
that class of failure impossible or loudly detected. Full detail + the
remote-switch protocol: `.config/nix/FLEET.md`. Mechanical check: `make
doctor` (sudo-free, runs over plain ssh).

## Hard rules

1. **Switch with `make here` only** (`.config/nix/Makefile`). Per-host
   targets were removed — a named target applied a *different* machine's
   config to this one. If `make here` says the machine isn't in the host
   map, add it to the Makefile rather than reaching for flake attrs
   directly.
2. **tailscaled on mini is the nix launchd daemon** (`org.jgoon.tailscaled`,
   from `fleet.tailscaled.enable = true` in hosts/mini). Never `brew
   services start/stop/restart tailscale` — a second daemon fights the nix
   one for the socket and state. **work is the exception**: keep
   `fleet.tailscaled.enable = lib.mkForce false` there — Falcon SIGKILLs
   the nix daemon; work uses the App Store variant. Tailnet joins are
   wizard-only (`~/.agents/skills/tailnet-join`); no auth keys anywhere
   in the repo.
3. **sshd / Remote Login are unmanaged and stay on.** Never edit
   `/etc/ssh/sshd_config`, never disable Remote Login on any fleet box.
4. **A broken `/etc/zsh*` file kills every NEW ssh session while old ones
   live** — it looks exactly like a dead box. After any switch on a remote
   machine, verify a fresh connection (`ssh mini 'echo ok'`) before
   closing the lifeline session.
5. **Plain switches only ever add** (brew cleanup = "none"). Removals happen
   only via `make here-zap`, and only after `make plan` shows a "would be
   REMOVED" list containing nothing ssh depends on (tailscale,
   cloudflared).

## Switching a remote machine (mini)

Don't improvise — the full protocol is in FLEET.md's Apply section. Shape:
plan → herdr remote pane (`herdr --remote mini`) → second ssh lifeline with
the rollback one-liner ready → `make here` → fresh `ssh mini 'echo ok'` from
the laptop before closing anything → `make doctor`.

## Before you touch brew on mini at all

`make plan` first; if tailscale/cloudflared appear under "would be REMOVED",
stop and declare them in `hosts/mini/default.nix` before doing anything else.
