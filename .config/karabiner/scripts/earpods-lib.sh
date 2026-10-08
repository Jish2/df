#!/bin/sh
# Shared helpers for EarPods center-button scripts.

LOG=/tmp/handy-earpods-debug.log
HOLD_FLAG=/tmp/handy-earpods-hold
DOWN_TS=/tmp/handy-earpods-down
GHOST_FLAG=/tmp/handy-earpods-ghost
STARTED_ON_DOWN=/tmp/handy-earpods-started-on-down
MAYBE_RECONNECT=/tmp/handy-earpods-maybe-reconnect
LAST_EVENT=/tmp/handy-earpods-last-event
FN_SIM_STATE=/tmp/handy-fn-sim-held
FN_SIM=/Users/jgoon/.config/karabiner/scripts/handy-fn-sim.sh
IDLE_GAP_MS=3000
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

idle_gap_ms() {
    if [ ! -f "$LAST_EVENT" ]; then
        echo 999999
        return
    fi
    _last=$(cat "$LAST_EVENT" 2>/dev/null)
    _now=$(now_ms)
    if [ -z "$_last" ]; then
        echo 999999
        return
    fi
    echo $((_now - _last))
}

f18_is_held() {
    [ -e "$FN_SIM_STATE" ]
}

ensure_handy() {
    /usr/bin/pgrep -x handy >/dev/null 2>&1
}

# Switch mic off the hot path so F18 is not blocked on SwitchAudioSource.
switch_earpods_mic_bg() {
    (
        if [ "$(/opt/homebrew/bin/SwitchAudioSource -c -t input 2>/dev/null)" != "EarPods Microphone" ]; then
            /opt/homebrew/bin/SwitchAudioSource -t input -s "EarPods Microphone" >/dev/null 2>&1 || true
        fi
    ) &
}

handy_f18_down() {
    if ! ensure_handy; then
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
