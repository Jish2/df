#!/bin/sh
# EarPods KEY UP.
#   Ghost / too-short → undo a keydown start.
#   Hold-flag → music already ran; do nothing.
#   Started on down → leave Handy recording (this was a tap-to-start).
#   Already recording → tap-to-stop (F18 up).
#   Idle-gap press → start on release if it was a real tap.

. /Users/jgoon/.config/karabiner/scripts/earpods-lib.sh

NOW=$(now_ms)
DOWN=0
if [ -f "$DOWN_TS" ]; then
    DOWN=$(cat "$DOWN_TS" 2>/dev/null)
    /bin/rm -f "$DOWN_TS"
fi
DUR=0
if [ -n "$DOWN" ] && [ "$DOWN" -gt 0 ]; then
    DUR=$((NOW - DOWN))
fi

if [ -e "$GHOST_FLAG" ] || [ "$DUR" -lt "$MIN_TAP_MS" ]; then
    /bin/rm -f "$GHOST_FLAG" "$HOLD_FLAG" "$STARTED_ON_DOWN" "$MAYBE_RECONNECT"
    handy_fn_release
    log "RELEASE ignored (ghost/short ${DUR}ms)"
    exit 0
fi

if [ -e "$HOLD_FLAG" ]; then
    /bin/rm -f "$HOLD_FLAG" "$STARTED_ON_DOWN" "$MAYBE_RECONNECT"
    log "RELEASE hold (music, no tap)"
    exit 0
fi

if [ -e "$STARTED_ON_DOWN" ]; then
    /bin/rm -f "$STARTED_ON_DOWN"
    log "RELEASE keep recording (started on press)"
    exit 0
fi

if f18_is_held; then
    RESULT=$(handy_f18_up)
    log "RELEASE F18 up ($RESULT)"
    exit 0
fi

if [ -e "$MAYBE_RECONNECT" ]; then
    /bin/rm -f "$MAYBE_RECONNECT"
    RESULT=$(handy_f18_down)
    switch_earpods_mic_bg
    log "RELEASE delayed F18 down ($RESULT)"
    exit 0
fi

log "RELEASE noop"
exit 0
