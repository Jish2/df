#!/bin/sh
# EarPods HOLD → music. Dictation is not started on keydown, so this
# does not need to cancel F18 (a tap never got that far).

. /Users/jgoon/.config/karabiner/scripts/earpods-lib.sh

NOW=$(now_ms)
/bin/rm -f "$DOWN_TS" "$STARTED_ON_DOWN"

if [ -f "$MUSIC_LAST" ]; then
    LAST=$(cat "$MUSIC_LAST" 2>/dev/null)
    if [ -n "$LAST" ] && [ $((NOW - LAST)) -lt 700 ]; then
        log "HELD_DOWN music skipped (debounce)"
        exit 0
    fi
fi
echo "$NOW" > "$MUSIC_LAST"

if [ -z "$EARPODS_SKIP_MUSIC" ]; then
    /opt/homebrew/bin/nowplaying-cli togglePlayPause
fi
log "HELD_DOWN music"
exit 0
