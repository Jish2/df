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
NIX="${NIX:-nix}" # AMI-baked on devspace; no absolute-path fallback needed

apply() {
  # activationPackage (not `nix run home-manager`): the registry alias is
  # unpinned and can drift from the flake.lock home-manager schema-wise;
  # the activation package is built by the flake's pinned HM input.
  # Retry loop: at boot the nix-daemon and the network may not be up yet.
  local gen="" err=/tmp/devspace-nix-apply.err
  for _ in $(seq 1 30); do
    if gen="$("$NIX" --extra-experimental-features 'nix-command flakes' build \
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

install_unit() {
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_DIR/$UNIT" <<EOF
[Unit]
Description=devspace: re-apply nix home-manager after workspace rebuild
# Only fires when the HM generation died with the root disk (rebuild): the
# profile link dangles or is gone. Plain stop/start keeps the root volume,
# so the condition is false and normal boots skip this. Updates are not
# this unit's job — run \`make here\` (or this script) by hand for those.
ExecCondition=/bin/sh -c 'test ! -e "$HOME/.nix-profile"'
ConditionPathIsDirectory=$FLAKE

[Service]
Type=oneshot
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
  *) apply && install_unit && echo "devspace-apply: done" ;;
esac
