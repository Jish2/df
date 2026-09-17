#!/usr/bin/env bash
# fetch-baseline.sh — download the pristine-guest defaults snapshot into
# baseline/tahoe (gitignored build input; not committed to the repo).
#
# release-asset source of truth; re-capture per macOS major with
# capture-baseline.sh, scrub with scrub-baseline.py, upload as a new
# baseline-<ver> tag.

set -euo pipefail

NAME="${1:-tahoe}"
VER="${VER:-26.6.2}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/baseline/$NAME"
URL="https://github.com/Jish2/df/releases/download/baseline-$VER/baseline-$NAME.tar.gz"

if [ -d "$DEST" ] && [ "$(find "$DEST" -name '*.plist' | wc -l)" -gt 100 ]; then
  echo "baseline already present at $DEST"
  exit 0
fi

echo "== $URL -> $DEST"
mkdir -p "$DEST"
curl -fsSL "$URL" | tar xz -C "$DEST"
echo "ok: $(find "$DEST" -name '*.plist' | wc -l | tr -d ' ') plists"
