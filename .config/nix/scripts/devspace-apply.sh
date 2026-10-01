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
# afterwards the devspace-nix-apply path unit re-runs `apply` at boot whenever
# the HM generation is missing.
set -euo pipefail

FLAKE="$HOME/.config/nix"
SCRIPTS="$FLAKE/scripts"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="devspace-nix-apply.service"
PATH_UNIT="devspace-nix-apply.path"
# absolute path: the boot-time user unit runs with a minimal PATH where nix
# isn't discoverable. this is the AMI-baked multi-user nix profile path —
# stable across rebuilds (Determinate installer layout).
NIX="${NIX:-/nix/var/nix/profiles/default/bin/nix}"
# array: 'nix-command flakes' is ONE option value — a flat string would
# word-split and nix would parse 'flakes' as the subcommand (caught live).
# (the AMI's /etc/nix/nix.conf already sets this; the flag is a safety net.)
NIXFLAGS=(--extra-experimental-features 'nix-command flakes')
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
  # --- apply service ------------------------------------------------------
  # the linger user manager starts BEFORE home-coder.mount lands (79s late
  # in the live test) — a plain default.target oneshot evaluates against
  # an unmounted $HOME and skips (ConditionResult=no). So this unit never
  # self-triggers at boot; the path unit below fires it the moment the
  # mount lands. RequiresMountsFor adds correct ordering for the rare case
  # where both race together.
  cat > "$UNIT_DIR/$UNIT" <<EOF
[Unit]
Description=devspace: re-apply nix home-manager after workspace rebuild
RequiresMountsFor=$HOME
ConditionPathIsDirectory=$FLAKE

[Service]
Type=oneshot
# Only fires when the HM generation is missing or dangling: every workspace
# stop recreates the EC2 instance from the AMI (fresh /nix store), so the
# profile link dangles. If the generation is healthy the unit skips —
# config updates are manual (\`make here\` on the box, or this script).
ExecCondition=/bin/sh -c 'test ! -e "$HM_LINK"'
ExecStart=$SCRIPTS/devspace-apply.sh apply
RemainAfterExit=yes
EOF

  # --- path watcher -------------------------------------------------------
  # triggers the apply service when the HM profile directory changes —
  # chiefly the moment the home EBS volume mounts at boot (the profiles
  # dir appears) or the link state changes after a rebuild. The service's
  # ExecCondition still gates: a healthy generation means one no-op check.
  cat > "$UNIT_DIR/$PATH_UNIT" <<EOF
[Unit]
Description=devspace: watch for a dangling (rebuilt) HM generation
ConditionPathIsDirectory=$FLAKE

[Path]
PathExists=$HOME/.local/state/nix
PathModified=$HOME/.local/state/nix/profiles
Unit=$UNIT

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable "$UNIT" >/dev/null
  systemctl --user enable --now "$PATH_UNIT" >/dev/null
  echo "devspace-apply: unit armed ($UNIT + $PATH_UNIT)"
}

case "${1:-}" in
  apply) apply ;;
  install-unit) install_unit ;;
  status) hm_missing && echo missing || echo present ;;
  *) apply && install_unit && echo "devspace-apply: done" ;;
esac
