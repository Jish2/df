#!/usr/bin/env bash
# Coder dotfiles entrypoint (coder.com/docs/user-guides/workspace-dotfiles).
# `coder dotfiles <repo>` runs this script INSTEAD of its fallback step
# (symlinking every root dotfile into $HOME) — the fallback must never fire
# on this repo: yadm owns $HOME as real files (FLEET.md "Decisions"), and
# coder would .bak each one for a symlink into its clone.
#
# Only devspace takes the coder path; the other hosts boot from real disks
# where yadm already delivered everything, so a stray invocation elsewhere
# exits 0 as a no-op.
#
# Runs with CWD = the repo checkout coder cloned (~/.config/coderv2/dotfiles
# on coder v2.35+). Two paths, both idempotent:
#
#   Fresh home volume (yadm repo gone — the volume was recreated):
#     1. get a yadm binary (its HM symlink dangles until step 3; the
#        single-file script from upstream is the same bootstrap nix would
#        deliver anyway)
#     2. `yadm clone` LOCALLY from this checkout — no network, no git
#        credentials (the coder agent's GIT_ASKPASS covers ssh, but local
#        clone sidesteps auth ordering entirely) — then point origin at
#        GitHub for later manual pulls
#     3. fall through to apply
#
#   Existing checkout (the common case after a workspace rebuild):
#     just apply — devspace-apply.sh apply-if-missing is a no-op when the
#     HM generation is healthy, and re-arms the self-heal chain when the
#     rebuild killed it (root disk is recreated from the AMI; /nix survives
#     as an AMI artifact, the $HOME symlinks dangle).
set -euo pipefail

DF_URL="https://github.com/Jish2/df.git"

# the fleet's devspace box; `make here` maps this same hostname
[ "$(hostname -s)" = "jgoon-jgoon-box" ] || exit 0

YADM_REPO="$HOME/.local/share/yadm/repo.git"

# --- 1. yadm binary ---------------------------------------------------------
# .local/bin survives rebuilds only if the volume does; after a fresh
# volume the HM symlink at ~/.local/bin/yadm dangles. prefer PATH yadm,
# else the one on the volume, else fetch upstream's single-file script.
if ! command -v yadm >/dev/null 2>&1 &&
   [ ! -x "$HOME/.local/bin/yadm" ]; then
  mkdir -p "$HOME/.local/bin"
  curl -fsSL -o "$HOME/.local/bin/yadm" \
    https://raw.githubusercontent.com/TheLocehiliosan/yadm/master/yadm
  chmod +x "$HOME/.local/bin/yadm"
fi
YADM="$(command -v yadm || echo "$HOME/.local/bin/yadm")"

# --- 2. fleet repo into $HOME (yadm worktree), once ------------------------
if [ ! -d "$YADM_REPO" ]; then
  # -f: a fresh volume still carries the AMI skeleton's conflicting files
  # (.bashrc, .profile); the repo is authoritative.
  # -b main: pin the integration branch — a WIP branch left checked out
  # would strand the box off main (the Sep-14 linux-zshrc incident).
  "$YADM" clone -f -b main "$PWD"
  "$YADM" alt
  "$YADM" remote set-url origin "$DF_URL"
fi

# --- 3. apply nix config ----------------------------------------------------
# applies the HM generation if missing, re-asserts the zsh login shell
# (chsh writes the ephemeral root disk; every rebuild resets it), installs
# + arms devspace-nix-apply.timer. exits 0 as a no-op when healthy, and
# exits 0 (not an error) if the home volume isn't mounted yet — the timer
# retries past the mount.
exec "$HOME/.config/nix/scripts/devspace-apply.sh" apply-if-missing
