#!/bin/sh
# EarPods macro self-test. One command instead of hand-probing state.
#
#   earpods-selftest.sh          static checks only (safe, no dictation)
#   earpods-selftest.sh --live   also runs one real tap on/off cycle
#
# The static checks encode the three invariants that each cost a debugging
# session: no script may launch a dictation app, taps drive the app's CLI
# rather than a synthetic F18, and Hex must actually be bound to F18 for the
# real-keyboard Fn path.

set -u

SCRIPTS=/Users/jgoon/.config/karabiner/scripts
HEX_BIN=/Applications/Hex.app/Contents/MacOS/hex
SETTINGS="$HOME/Library/Application Support/Hex/settings.json"
FAIL=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

echo "static"
for f in "$SCRIPTS"/*.sh; do
    sh -n "$f" 2>/dev/null || fail "$(basename "$f") does not parse"
done
pass "all scripts parse"

# A script that starts another app takes the hotkey back and kills the macro.
# Ignore comment lines and this test file (which mentions the pattern).
if grep -nE '/usr/bin/open -a|open -a (Handy|Hex)' "$SCRIPTS"/earpods-*.sh \
    | grep -v 'earpods-selftest\.sh' \
    | grep -vE ':[0-9]+: *#' >/dev/null 2>&1; then
    fail "an earpods script launches an app (never do this)"
else
    pass "no earpods script launches an app"
fi

# Synthetic F18 gets discarded as a suspected chord; the CLI does not.
if grep -q 'hex_dictation toggle' "$SCRIPTS/earpods-release.sh"; then
    pass "tap drives 'hex dictation toggle'"
else
    fail "tap does not call the hex CLI"
fi

if [ -x "$HEX_BIN" ]; then
    pass "hex binary present"
else
    fail "no hex binary at $HEX_BIN"
fi

if /usr/bin/pgrep -x hex >/dev/null 2>&1; then
    pass "hex running"
else
    fail "hex not running (tap will no-op)"
fi

if [ -f "$SETTINGS" ] && python3 - "$SETTINGS" <<'PY' >/dev/null 2>&1
import json,sys
d=json.load(open(sys.argv[1]))
keys=d.get("dictation_hotkey",{}).get("keys",[])
assert any(k.get("code")==79 for k in keys), keys
PY
then
    pass "hex dictation hotkey is still F18 (Fn path)"
else
    fail "hex dictation hotkey is not F18 (Fn remap would break)"
fi

if [ "${1:-}" = "--live" ]; then
    echo "live (records and discards a short dictation)"
    state() { "$HEX_BIN" status --json 2>/dev/null \
        | python3 -c 'import json,sys;print(json.load(sys.stdin)["capture"]["state"])'; }
    "$HEX_BIN" dictation stop >/dev/null 2>&1
    sleep 1
    sh "$SCRIPTS/earpods-press.sh" center
    sleep 0.15
    sh "$SCRIPTS/earpods-release.sh" >/dev/null 2>&1
    sleep 1.5
    [ "$(state)" = "recording" ] && pass "tap started dictation" || fail "tap did not start dictation"

    sleep 2
    sh "$SCRIPTS/earpods-press.sh" center
    sleep 0.15
    sh "$SCRIPTS/earpods-release.sh" >/dev/null 2>&1
    sleep 2.5
    [ "$(state)" = "idle" ] && pass "tap stopped dictation" || fail "tap did not stop dictation"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "all checks passed"
    exit 0
fi
echo "$FAIL check(s) failed"
exit 1
