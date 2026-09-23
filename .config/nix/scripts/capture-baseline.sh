#!/usr/bin/env bash
# capture-baseline.sh — dump a pristine macOS guest's Apple defaults domains
# to baseline/<name>/ for use with export-defaults.py --baseline.
#
# one-time per macOS major; ~15GB download, ~40GB free disk, no sudo.
# the VM is disposable afterwards (tart delete df-baseline).
#
# usage:  ./capture-baseline.sh [name]   (default: tahoe)
#
# output lands in baseline/<name> which is GITIGNORED — it's a build input,
# not a repo artifact. to share a new os major: scrub-baseline.py, then
# tar czf baseline-<name>.tar.gz -C baseline <name>, upload as a
# `baseline-<ver>` release asset; fetch-baseline.sh downloads it again.
# deps:   curl, sshpass (brew install sshpass); tart is auto-installed to
# NOTE: run scripts/scrub-baseline.py on the output before sharing it.
#         ~/.local/bin (the cirruslabs brew tap formula is broken on modern
#         brew, so we fetch the signed release binary directly)

set -euo pipefail

NAME="${1:-tahoe}"
IMAGE="${IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"
VM="df-baseline-$NAME"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/baseline/$NAME"

TART="$HOME/.local/bin/tart"
if ! command -v tart >/dev/null && [ ! -x "$TART" ]; then
  echo "== installing tart binary -> $TART"
  mkdir -p "$HOME/.local/bin"
  curl -fsSL https://github.com/cirruslabs/tart/releases/latest/download/tart.tar.gz |
    tar xz -C "$HOME/.local/bin"
  # tarball ships an app bundle; expose the binary directly
  ln -sf "tart.app/Contents/MacOS/tart" "$HOME/.local/bin/tart"
else
  TART="$(command -v tart || echo "$TART")"
fi
command -v sshpass >/dev/null || {
  echo "== installing sshpass"; brew install sshpass; }

AVAIL=$(df -g / | awk 'NR==2 {print $4}')
[ "$AVAIL" -ge 40 ] || { echo "only ${AVAIL}GB free, want >= 40GB"; exit 1; }

if ! "$TART" list | grep -q "^$VM"; then
  echo "== cloning $IMAGE -> $VM (this is the ~15GB part)"
  "$TART" clone "$IMAGE" "$VM"
fi

echo "== booting (headless)"
"$TART" run --no-graphics "$VM" &
RUN_PID=$!
cleanup() { "$TART" stop "$VM" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== waiting for guest ip"
IP=$("$TART" ip --wait 600 "$VM")
echo "   guest at $IP"

SSH="sshpass -p admin ssh
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$IP"

echo "== dumping defaults domains in guest"
# shellcheck disable=SC2086
$SSH 'rm -rf /tmp/baseline && mkdir -p /tmp/baseline && cd /tmp/baseline &&
  defaults domains | tr "," "\n" | sed "s/^ *//" | while read -r d; do
    case "$d" in
      # only apple system domains; skip per-machine ByHost here too
      *????????-????-????-????-???????????? ) : ;;
      *) defaults export "$d" "$d.plist" 2>/dev/null || true ;;
    esac
  done; cd /tmp/baseline && tar czf - .' > /tmp/baseline.tgz

mkdir -p "$OUT"
tar xzf /tmp/baseline.tgz -C "$OUT"
N=$(find "$OUT" -name '*.plist' | wc -l | tr -d ' ')
V=$($SSH sw_vers -productVersion 2>/dev/null || echo unknown)
echo "== captured $N domain plists from macOS $V guest -> $OUT"

echo "== stopping vm (kept for re-runs; delete later with: $TART delete $VM)"
echo
echo "done. regenerate with:"
echo "  python3 scripts/export-defaults.py --baseline '$OUT' modules/darwin/imported-defaults.nix"
