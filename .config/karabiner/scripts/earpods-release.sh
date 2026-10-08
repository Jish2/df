#!/bin/sh
# EarPods TAP (to_if_alone). Toggle Handy F18 hold.
# Karabiner does not call this if the press crossed the hold threshold.

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

if [ "$DUR" -lt "$MIN_TAP_MS" ]; then
    log "TAP ignored (ghost/short ${DUR}ms)"
    exit 0
fi

if f18_is_held; then
    RESULT=$(handy_f18_up)
    log "TAP F18 up ${DUR}ms ($RESULT)"
    exit 0
fi

RESULT=$(handy_f18_down)
switch_earpods_mic_bg
log "TAP F18 down ${DUR}ms ($RESULT)"
exit 0
