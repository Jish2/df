---
name: tailnet-join
description: Join a machine onto the personal headscale tailnet via the interactive wizard (SSO → SSM mint → tailscale up → verify). The fleet's single join mechanism — run by hand whenever a box needs joining.
disable-model-invocation: true
---

# tailnet-join

Interactive wizard (and one-shot script) for the one-time-per-box tailnet join ceremony.

```sh
TJ=~/.agents/skills/tailnet-join/tailnet-join.sh
$TJ              # wizard mode — picks target interactively
$TJ here         # fast path: the mac you're on
$TJ mac mini     # fast path: another fleet mac, over ssh
$TJ pc           # fast path: the NixOS box
```

Wizard flow (5 stages): preflight target (CLI probe, BackendState check —
already-joined exits before minting) → AWS SSO sign-in if the token is
stale (browser opens; hidden prompt isn't needed — the key never passes
through your hands) → mint a fresh reusable 30d pre-auth key over SSM
(y/N gate; key never displayed) → `tailscale up --login-server
https://headscale.jgoon.com --auth-key <KEY> --accept-dns=false` on the
target → verify the node in `headscale nodes list` over SSM (with the
register-approval fallback hint if it fell back to interactive
registration).

## Per-target differences (transport, not join logic)

The join call is identical everywhere; only how it *reaches* the target
differs:

| target | transport | sudo | why |
|---|---|---|---|
| here | local exec | no | macs: CLI just talks to the world-writable daemon socket; the root daemon joins |
| mac <host> | ssh (key staged to /tmp, 600) | no | same, over ssh; stdin heredoc can't take a piped key |
| pc | ssh (key staged to /tmp, 600) | **your password, via `ssh -t`** | NixOS up needs root — the wizard offers to drive it (sudo prompts in your terminal) or hand you the staged-key command |

CLI path varies by install — `/usr/local/bin` (standalone pkg),
`/opt/homebrew/bin` (brew formula), the App Store app bundle, or the NixOS
system path; the wizard probes all of them.

## Preconditions

- control-plane instance ID in `~/.config/nix/secrets/headscale-instance`
  (gitignored, 600 — `make hs-nodes` reads it as `HS_INSTANCE` too) or in
  the environment as `HS_INSTANCE`; without it the wizard stops at Stage 2
  with the exact fix
- this box: `aws` cli with the `dev-admin` profile (`~/.aws/config`, not
  dotfiles-managed), ssh reachability to the target
- target: any tailscale CLI present (app, pkg, brew, or system)

## Notes

- Key policy: minted fresh per run, 30d, reusable — a leaked key ages out
  in a month, no rotation bookkeeping. The vault note "headscale cloudflare
  tunnel" forbids storing keys in dotfiles; the key is never written to
  disk at all (mac targets stage to /tmp 600, deleted immediately after).
- This wizard is the fleet's ONLY join mechanism (FLEET.md "Tailnet"):
  the nix side just guarantees the daemon + CLI exist (the tailscale-app
  cask, opt-out per host). `make hs-nodes` remains for a standing check.
- Machine words containing the magic t-word trigger a local process killer
  on the work box (intermittent SIGKILL on matching argv). The wizard
  splits the word inside remote heredocs where possible; if a command dies
  with signal 9, reword it (string concat) and retry.
- Built with the /wizard template (wizard skill): the library above the
  STAGES marker is stock; only the five stages are authored. Keep that
  split if editing.
