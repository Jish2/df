#!/bin/sh
# Shared helpers for EarPods center-button scripts.
#
# Test seams (unset in production):
#   EARPODS_STATE_DIR  put flag files here instead of /tmp
#   EARPODS_FN_SIM     stub for handy-fn-sim.sh
#   EARPODS_SKIP_MIC   skip SwitchAudioSource
#   EARPODS_SKIP_MUSIC skip nowplaying-cli

STATE_DIR="${EARPODS_STATE_DIR:-/tmp}"
LOG="${EARPODS_LOG:-$STATE_DIR/handy-earpods-debug.log}"
HOLD_FLAG="$STATE_DIR/handy-earpods-hold"
DOWN_TS="$STATE_DIR/handy-earpods-down"
GHOST_FLAG="$STATE_DIR/handy-earpods-ghost"
STARTED_ON_DOWN="$STATE_DIR/handy-earpods-started-on-down"
MAYBE_RECONNECT="$STATE_DIR/handy-earpods-maybe-reconnect"
LAST_EVENT="$STATE_DIR/handy-earpods-last-event"
MUSIC_LAST="$STATE_DIR/handy-earpods-music-last"
FN_SIM_STATE="$STATE_DIR/handy-fn-sim-held"
FN_SIM="${EARPODS_FN_SIM:-/Users/jgoon/.config/karabiner/scripts/handy-fn-sim.sh}"
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

f18_is_held() {
    [ -e "$FN_SIM_STATE" ]
}

ensure_handy() {
    /usr/bin/pgrep -x handy >/dev/null 2>&1
}

# Switch mic off the hot path so F18 is not blocked on SwitchAudioSource.
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

handy_f18_down() {
    if [ -z "$EARPODS_FN_SIM" ] && ! ensure_handy; then
        /usr/bin/open -a Handy
        return 1
    fi
    "$FN_SIM" down
}

handy_f18_up() {
    "$FN_SIM" up
}

handy_fn_release() {
    handy_f18_up >/dev/null 2>&1 || true
}
