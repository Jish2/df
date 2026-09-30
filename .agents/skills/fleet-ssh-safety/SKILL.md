---
name: fleet-ssh-safety
description: Required before switching any fleet machine (`make here` only), touching tailscale/tailscaled or sshd/Remote Login, running `brew services` or any brew removal, or editing the df/nix config. mini is a remote box — SSH breakage means a physical visit. Carries the remote-switch procedure (herdr panes). Covers all 5 machines in the df repo.
---

# fleet-ssh-safety

The df repo (`~/github/df`, yadm worktree `~`) manages a 5-machine fleet.
**mini** (Mac mini, always on) is remote: if it drops off the tailnet or ssh
dies, fixing it means physically going there. Everything below exists to make
that class of failure impossible or loudly detected. `make doctor` verifies
the invariants mechanically, sudo-free, over plain ssh.

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
   machine, verify a fresh connection before closing the lifeline.
5. **Plain switches only ever add** (brew cleanup = "none"). Removals happen
   only via `make here-zap`, and only after `make plan` shows a "would be
   REMOVED" list containing nothing ssh depends on (tailscale,
   cloudflared).

## Switching a remote machine (mini) — the procedure

`make here` mutates the system over a network. Read-only steps (`make plan`,
`make doctor`, `yadm pull`, file reads) are safe over plain ssh. **The switch
itself runs in a pane on mini's herdr server**, where it survives ssh
disconnects. Run THIS procedure — do not improvise substitutes (tmux, nohup,
`ssh -t`); herdr is the fleet multiplexer and the only surface an agent can
drive and the human can attach to.

1. **Plan** (over ssh is fine): `ssh mini 'cd ~/.config/nix && make plan'`.
   The "would be REMOVED" list must be empty of anything ssh depends on
   before any switch. Note: non-interactive ssh on mini has a sparse PATH —
   if a bare command is missing, use absolute paths (`/opt/homebrew/bin/yadm`).
2. **Open the pane on mini's server** via the saved-machine API — NOT
   `herdr --remote mini`, which is a human's interactive TUI attach:
   ```
   herdr --machine mini pane list --workspace w1        # find a pane id
   herdr --machine mini pane split --pane w1:p1 --direction right \
     --cwd ~/.config/nix --no-focus                    # new id: .result.pane.pane_id
   ```
   `--current` resolves to the LOCAL session — over `--machine`, always
   use explicit ids from `pane list`.
3. **Lifeline**: keep one plain `ssh mini` session open in the user's
   terminal for the whole switch (existing sessions keep their shell; only
   NEW ones exercise the rewritten `/etc/zshenv`). Stage the rollback line
   in it:
   `$(darwin-rebuild --list-generations | grep <prev-gen> | awk '{print $NF}')/activate`
4. **Launch the switch in the remote pane**:
   `herdr --machine mini pane run <pane-id> 'sudo make here; echo EXIT_CODE=$?'`
   — `pane run` returns immediately; the command runs server-side on mini.
5. **sudo password is the human gate.** macOS sudo needs a password and
   Touch-ID PAM only works at the physical console — an agent CANNOT
   complete sudo remotely and must not try to bypass it (no `sudo -n`, no
   piped passwords). The pane sits at `Password:` until the user attaches
   with `herdr --remote mini` and types it; the switch then runs to
   completion server-side. Say this plainly to the user and stop — don't
   offer a menu of workarounds. (If the fleet later adopts scoped
   NOPASSWD for darwin-rebuild, this becomes unattended; until then it is
   deliberate.)
6. **Watch for completion** — never close anything early:
   `herdr --machine mini pane read <pane-id> --source recent-unwrapped --lines 100`
   or `pane wait-output <pane-id> --match "EXIT_CODE=" --timeout 600000`.
   Non-zero EXIT_CODE → hand the user the rollback line from step 3.
7. **Verify in order**, from the laptop, before the lifeline closes:
   a fresh `ssh mini 'echo ok'` (proves new-session shell init still
   parses), then `ssh mini 'cd ~/.config/nix && make doctor'`.

## Before you touch brew on mini at all

`make plan` first; if tailscale/cloudflared appear under "would be REMOVED",
stop and declare them in `hosts/mini/default.nix` before doing anything else.
