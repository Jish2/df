#!/bin/sh
# Shared helpers for EarPods center-button scripts.
#
# The USB-C center button drives push-to-talk for Hex, the dictation app.
# Taps go through `hex dictation toggle`, not synthetic key events: Hex's
# suppression layer drops fabricated chords, so the CLI is the reliable seam.
#
# Test seams (unset in production):
#   EARPODS_STATE_DIR  put flag files here instead of /tmp
#   EARPODS_SKIP_MIC   skip SwitchAudioSource
#   EARPODS_SKIP_MUSIC skip nowplaying-cli

STATE_DIR="${EARPODS_STATE_DIR:-/tmp}"
LOG="${EARPODS_LOG:-$STATE_DIR/handy-earpods-debug.log}"
DOWN_TS="$STATE_DIR/handy-earpods-down"
LAST_EVENT="$STATE_DIR/handy-earpods-last-event"
MUSIC_LAST="$STATE_DIR/handy-earpods-music-last"
BUTTON_FILE="$STATE_DIR/handy-earpods-button"
MIN_TAP_MS=30

now_ms() {
    /usr/bin/perl -MTime::HiRes=time -e 'printf("%d", time*1000)'
}

log() {
    echo "$(now_ms) $*" >> "$LOG"
}

mark_event() {
    now_ms > "$LAST_EVENT"
}

# Never launch a dictation app from here. Handy is retired, and an app we
# start would take F18 back from Hex and leave the macro silently dead.
dictation_app_running() {
    /usr/bin/pgrep -x hex >/dev/null 2>&1
}

# Resolve the bundled binary rather than trusting PATH: Karabiner's
# shell_command environment is minimal.
HEX_BIN=/Applications/Hex.app/Contents/MacOS/hex

# Drive dictation through Hex's own CLI rather than posting a synthetic F18.
# Hex's suppression layer discards fabricated key events it judges to be part
# of a chord ("dictation press discarded as a chord", "resynchronized stale
# input tracking"), which made taps flaky and sometimes needed two tries.
# The CLI is idempotent ("already recording") and answers in ~50ms, and Hex
# still binds F18 for real keyboards — the Fn key path is untouched.
hex_dictation() {
    if ! dictation_app_running; then
        return 1
    fi
    "$HEX_BIN" dictation "$1" 2>&1 | tail -1
}

# Switch mic off the hot path so dictation is not blocked on SwitchAudioSource.
switch_earpods_mic_bg() {
    if [ -n "$EARPODS_SKIP_MIC" ]; then
        return 0
    fi
    (
        if [ "$(/opt/homebrew/bin/SwitchAudioSource -c -t input 2>/dev/null)" != "EarPods Microphone" ]; then
            /opt/homebrew/bin/SwitchAudioSource -t input -s "EarPods Microphone" >/dev/null 2>&1 || true
        fi
    ) &
}
