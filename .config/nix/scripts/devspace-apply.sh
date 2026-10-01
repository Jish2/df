#!/usr/bin/env bash
# devspace (Coder VM) — apply the fleet home-manager config, and arm the
# boot-time re-apply unit.
#
# Why this exists: the workspace's $HOME is a persistent EBS volume, but the
# EC2 instance (root disk — including /nix and every nix profile) is recreated
# from the AMI on each workspace rebuild. After a rebuild every HM symlink in
# $HOME dangles, so the config must re-apply itself at boot.
#
# Run once by hand after `yadm pull` on the box (see FLEET.md bootstrap);
# afterwards the devspace-nix-apply user unit re-runs `apply` on boot whenever
# the HM generation is missing.
set -euo pipefail

FLAKE="$HOME/.config/nix"
SCRIPTS="$FLAKE/scripts"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="devspace-nix-apply.service"
# absolute path: the boot-time user unit runs with a minimal PATH where nix
# isn't discoverable. this is the AMI-baked multi-user nix profile path —
# stable across rebuilds (Determinate installer layout).
NIX="${NIX:-/nix/var/nix/profiles/default/bin/nix}"
NIXFLAGS="--extra-experimental-features nix-command flakes"
# HM's profile link: dies (dangles) whenever the workspace is rebuilt —
# every stop recreates the EC2 instance from the AMI, and the store paths
# it points at live on the ephemeral root disk.
HM_LINK="$HOME/.local/state/nix/profiles/home-manager"

apply() {
  # activationPackage (not `nix run home-manager`): the registry alias is
  # unpinned and can drift from the flake.lock home-manager input; the
  # activation package is built by the flake's pinned HM.
  # Retry loop: at boot the nix-daemon and the network may not be up yet
  # (linger starts the user manager before the daemon settles).
  local gen="" err=/tmp/devspace-nix-apply.err
  for _ in $(seq 1 30); do
    if gen="$("$NIX" $NIXFLAGS build \
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
  "$gen/activate"
  echo "devspace-apply: generation activated ($gen)"
}

# true when the HM generation is missing or dangling (the workspace was
# rebuilt; the generation's store paths on the ephemeral root disk are gone)
hm_missing() {
  [ ! -e "$HM_LINK" ]
}

install_unit() {
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_DIR/$UNIT" <<EOF
[Unit]
Description=devspace: re-apply nix home-manager after workspace rebuild
ConditionPathIsDirectory=$FLAKE

[Service]
Type=oneshot
# Only fires when the HM generation died with the root disk: every workspace
# stop recreates the EC2 instance from the AMI (fresh /nix store), so the
# profile link dangles. If the generation is healthy the unit skips — config
# updates are manual (\`make here\` on the box, or this script).
ExecCondition=/bin/sh -c 'test ! -e "$HM_LINK"'
ExecStart=$SCRIPTS/devspace-apply.sh apply
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable "$UNIT" >/dev/null
  echo "devspace-apply: unit armed ($UNIT)"
}

case "${1:-}" in
  apply) apply ;;
  install-unit) install_unit ;;
  status) hm_missing && echo missing || echo present ;;
  *) apply && install_unit && echo "devspace-apply: done" ;;
esac
