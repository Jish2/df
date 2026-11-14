#!/bin/sh
# EarPods TAP (to_if_alone). Toggle push-to-talk for Hex.
# Karabiner does not call this if the press crossed the hold threshold.

. /Users/jgoon/.config/karabiner/scripts/earpods-lib.sh

NOW=$(now_ms)
DOWN=0
if [ -f "$DOWN_TS" ]; then
    DOWN=$(cat "$DOWN_TS" 2>/dev/null)
    /bin/rm -f "$DOWN_TS"
fi
BUTTON=center
if [ -f "$BUTTON_FILE" ]; then
    BUTTON=$(cat "$BUTTON_FILE" 2>/dev/null)
    /bin/rm -f "$BUTTON_FILE"
fi
DUR=0
if [ -n "$DOWN" ] && [ "$DOWN" -gt 0 ]; then
    DUR=$((NOW - DOWN))
fi

if [ "$DUR" -lt "$MIN_TAP_MS" ]; then
    log "TAP ignored (ghost/short ${DUR}ms $BUTTON)"
    exit 0
fi

# One tap = one toggle. `hex dictation toggle` starts when idle and finishes
# when recording, so a tap always does the visible thing — no stale flag to
# desynchronize us from Hex's real state.
switch_earpods_mic_bg
RESULT=$(hex_dictation toggle)
log "TAP toggle ${DUR}ms $BUTTON -> ${RESULT:-hex not running}"
exit 0
