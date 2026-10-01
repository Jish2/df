#!/usr/bin/env bash
# Why this exists: the workspace's $HOME is a persistent EBS volume, but the
# EC2 instance (root disk — including /nix and every nix profile) is recreated
# from the AMI on each workspace rebuild. After a rebuild every HM symlink in
# $HOME dangles, so the config must re-apply itself at boot.
#
# Run once by hand after `yadm pull` on the box (see FLEET.md bootstrap).
set -euo pipefail

FLAKE="$HOME/.config/nix"
SCRIPTS="$FLAKE/scripts"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="devspace-nix-apply.service"
TIMER_UNIT="devspace-nix-apply.timer"
# absolute path: the boot-time user unit runs with a minimal PATH where nix
# isn't discoverable. this is the AMI-baked multi-user nix profile path —
# stable across rebuilds (Determinate installer layout).
NIX="${NIX:-/nix/var/nix/profiles/default/bin/nix}"
# array: 'nix-command flakes' is ONE option value — a flat string would
# word-split and nix would parse 'flakes' as the subcommand (caught live).
# (the AMI's /etc/nix/nix.conf already sets this; the flag is a safety net against AMIs that drop it.)
NIXFLAGS=(--extra-experimental-features 'nix-command flakes')
# HM's profile link: dies (dangles) whenever the workspace is rebuilt —
# every stop recreates the EC2 instance from the AMI, and the store paths
# it points at live on the ephemeral root disk.
HM_LINK="$HOME/.local/state/nix/profiles/home-manager"

# the home EBS volume (/dev/nvme2n1) must be mounted over $HOME before
# anything writes there: the linger user manager starts ~80s before
# home-coder.mount lands (measured live), and a start against the bare
# root-disk $HOME would write symlinks the mount then shadows — silently
# breaking the box until a manual re-run. discriminate by device number:
# same st_dev as / means $HOME is NOT its own volume.
home_mounted() {
  [ "$(stat -c %d /home/coder)" != "$(stat -c %d /)" ]
}

hm_missing() {
  [ ! -e "$HM_LINK" ]
}

apply() {
  # activationPackage (not `nix run home-manager`): the registry alias is
  # unpinned and can drift from the flake.lock home-manager input; the
  # activation package is built by the flake's pinned HM.
  # Retry loop: at boot the nix-daemon and the network may not be up yet.
  local gen="" err=/tmp/devspace-nix-apply.err
  for _ in $(seq 1 30); do
    if gen="$("$NIX" "${NIXFLAGS[@]}" build \
      --no-link --print-out-paths \
      "$FLAKE#homeConfigurations.devspace.activationPackage" 2>"$err")"; then
      break
    fi
    gen=""
    sleep 5
  done
  if [ -z "$gen" ]; then
    echo "devspace-apply: build failed — last error:" >&2
    cat "$err" >&2
    exit 1
  fi
  fix_login_shell
  "$gen/activate"
  echo "devspace-apply: generation activated ($gen)"
}

apply_if_missing() {
  if ! home_mounted; then
    # not an error: the timer retries — next tick is past the mount
    echo "devspace-apply: home volume not mounted yet, skipping this tick"
    exit 0
  fi
  fix_login_shell
  if ! hm_missing; then
    echo "devspace-apply: HM generation present, nothing to do"
    exit 0
  fi
  apply
}

# the AMI ships /bin/bash as the login shell and chsh writes /etc/passwd
# on the ephemeral root disk — every rebuild resets it and every shell
# lands in bash with the stock prompt. the fleet's shell is zsh (macs via
# nix-darwin, pc via NixOS); re-assert it. passwordless sudo is AMI-baked.
fix_login_shell() {
  if [ "$(getent passwd coder | cut -d: -f7)" != /usr/bin/zsh ] && [ -x /usr/bin/zsh ]; then
    if sudo -n chsh -s /usr/bin/zsh coder 2>/dev/null; then
      echo "devspace-apply: login shell restored to /usr/bin/zsh"
    else
      echo "devspace-apply: WARNING could not set zsh as login shell" >&2
    fi
  fi
}

install_units() {
  mkdir -p "$UNIT_DIR"
  # started ONLY by the timer (no default.target WantedBy): at cold boot the
  # user manager reaches default.target ~80s before home-coder.mount lands
  # (measured live), so a boot-triggered oneshot evaluates against the bare
  # root-disk $HOME and skips. the timer re-evaluates every couple of minutes;
  # ConditionPathIsDirectory fails on the unmounted home (the AMI skeleton
  # has no .config/nix) and the st_dev guard inside the script is the
  # belt-and-suspenders for a mounted-home race. RequiresMountsFor orders
  # correctly when the mount unit already exists.
  cat > "$UNIT_DIR/$UNIT" <<EOF
[Unit]
Description=devspace: re-apply nix home-manager after workspace rebuild
RequiresMountsFor=$HOME
ConditionPathIsDirectory=$FLAKE

[Service]
Type=oneshot
ExecStart=$SCRIPTS/devspace-apply.sh apply-if-missing
EOF

  # no RemainAfterExit on the service: an active(exited) oneshot ignores
  # timer re-triggers, and the periodic healthy-check is the design.
  cat > "$UNIT_DIR/$TIMER_UNIT" <<EOF
[Unit]
Description=devspace: re-apply HM after rebuild (no-op when healthy)

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
EOF

  systemctl --user disable --now "$UNIT" >/dev/null 2>&1 || true
  systemctl --user disable --now devspace-nix-apply.path >/dev/null 2>&1 || true
  rm -f "$UNIT_DIR/devspace-nix-apply.path"

  # bash guard: ssh logins land in bash (login shell until fix_login_shell
  # wins the race), and .bashrc's interactive guard returns early — so the
  # zshrc trigger never fires for the FIRST ssh after a rebuild. this file
  # is not yadm-tracked (no conflict) and lives on the home volume, so the
  # guard persists across rebuilds and re-arms the heal at first ssh.
  # systemctl --no-block: never hold the login open for the build.
  cat > "$HOME/.bash_profile" <<'GUARD'
# devspace fleet self-heal: after a workspace rebuild the HM generation
# dies with the root disk; re-arm the re-apply machinery on first login.
# silent no-op when healthy. (written by .config/nix/scripts/devspace-apply.sh)
if [ -e "$HOME/.config/systemd/user/devspace-nix-apply.timer" ] &&
  [ ! -e "$HOME/.local/state/nix/profiles/home-manager" ]; then
  systemctl --user daemon-reload >/dev/null 2>&1
  systemctl --user start --no-block devspace-nix-apply.timer devspace-nix-apply.service >/dev/null 2>&1
fi
GUARD

  systemctl --user daemon-reload
  systemctl --user enable --now "$TIMER_UNIT" >/dev/null
  echo "devspace-apply: units armed ($TIMER_UNIT -> $UNIT)"
}

case "${1:-}" in
  apply) apply ;;
  apply-if-missing) apply_if_missing ;;
  install-unit) install_units ;;
  status)
    if ! home_mounted; then echo "home-unmounted";
    elif hm_missing; then echo missing; else echo present; fi
    ;;
  *) apply && install_units && echo "devspace-apply: done" ;;
esac
