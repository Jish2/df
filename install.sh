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
# on coder v2.35+). Re-runs are the UPDATE path, not just delivery:
#
#   1. yadm binary — PATH, then ~/.local/bin (HM symlink dangles after a
#      rebuild until step 4 heals it), then upstream's single-file script
#      (the same bootstrap nix would deliver).
#   2. Fleet repo into $HOME (yadm worktree) — clone LOCALLY from this
#      checkout on a fresh home volume (no network/auth), else keep the
#      existing checkout. Re-point origin at GitHub for pulls.
#   3. Sync: force the worktree onto main (a WIP branch left checked out
#      is how devspace got stranded on Sep-14), `yadm pull --ff-only`,
#      `yadm alt`. A pull failure (e.g. dirty .zshrc — tools append to it,
#      FLEET.md) warns and continues on the current checkout: the worktree
#      may then lag main until reconciled by hand.
#   4. Apply: if main moved, rebuild + activate the HM generation (a new
#      fleet package lands on the box); if not, apply-if-missing — a no-op
#      when the generation is healthy, and the rebuild-heal when it isn't.
#      Both re-assert the zsh login shell and arm the self-heal timer.
set -euo pipefail

DF_URL="https://github.com/Jish2/df.git"

# the fleet's devspace box; `make here` maps this same hostname
[ "$(hostname -s)" = "jgoon-jgoon-box" ] || exit 0

# st_dev guard (mirrors devspace-apply.sh): same device as / means $HOME is
# the bare AMI skeleton — the home volume isn't mounted, nothing to do.
[ "$(stat -c %d "$HOME")" != "$(stat -c %d /)" ] || {
  echo "install.sh: home volume not mounted, skipping" >&2
  exit 0
}

YADM_REPO="$HOME/.local/share/yadm/repo.git"

# --- 1. yadm binary ---------------------------------------------------------
# a dangling symlink is not -x, so each probe survives a root-disk rebuild
YADM=""
if command -v yadm >/dev/null 2>&1 && [ -x "$(command -v yadm)" ]; then
  YADM="$(command -v yadm)"
elif [ -x "$HOME/.local/bin/yadm" ]; then
  YADM="$HOME/.local/bin/yadm"
else
  mkdir -p "$HOME/.local/bin"
  curl -fsSL -o "$HOME/.local/bin/yadm" \
    https://raw.githubusercontent.com/TheLocehiliosan/yadm/master/yadm
  chmod +x "$HOME/.local/bin/yadm"
  YADM="$HOME/.local/bin/yadm"
fi

# --- 2. fleet repo into $HOME (yadm worktree), once ------------------------
if [ ! -d "$YADM_REPO" ]; then
  # -f: a fresh volume still carries the AMI skeleton's conflicting files
  #     (.bashrc, .profile); the repo is authoritative.
  # -b main: pin the integration branch — a WIP branch left checked out
  #     would strand the box off main (the Sep-14 linux-zshrc incident).
  "$YADM" clone -f -b main "$PWD"
  "$YADM" remote set-url origin "$DF_URL"
fi

# --- 3. sync: main + latest ------------------------------------------------
if [ "$("$YADM" rev-parse --abbrev-ref HEAD)" != main ]; then
  echo "install.sh: yadm worktree not on main, switching" >&2
  if ! "$YADM" checkout main >/dev/null 2>&1; then
    echo "install.sh: WARNING checkout main failed — pulling on current branch" >&2
  fi
fi

before="$("$YADM" rev-parse HEAD)"
if ! "$YADM" pull --ff-only; then
  echo "install.sh: WARNING pull failed (dirty worktree?) — staying on current HEAD" >&2
fi
after="$("$YADM" rev-parse HEAD)"
"$YADM" alt

# --- 4. apply ---------------------------------------------------------------
APPLY="$HOME/.config/nix/scripts/devspace-apply.sh"
if [ "$before" != "$after" ]; then
  echo "install.sh: main moved ($before → $after), applying"
  exec "$APPLY" apply
fi
exec "$APPLY" apply-if-missing
