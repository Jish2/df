#!/bin/sh
# EarPods center-button HOLD → toggle music.
# Fired by Karabiner's to_if_held_down at the 500ms threshold, mid-press —
# no need to release. Sets the hold-flag so the release handler knows this
# press was a hold and shouldn't be treated as a tap.

LOG=/tmp/handy-earpods-debug.log
FLAG=/tmp/handy-earpods-hold
STATE=/tmp/handy-earpods-music-last

/usr/bin/touch "$FLAG"
echo "HELD_DOWN → music (flag set)" >> "$LOG"

# Debounce: one hold = one toggle (guards against doubled event delivery).
NOW=$(/usr/bin/perl -MTime::HiRes=time -e 'printf("%d", time*1000)')
if [ -f "$STATE" ]; then
    LAST=$(cat "$STATE" 2>/dev/null)
    if [ -n "$LAST" ] && [ $((NOW - LAST)) -lt 700 ]; then
        echo "  music toggle SKIPPED (debounce)" >> "$LOG"
        exit 0
    fi
fi
echo "$NOW" > "$STATE"

/opt/homebrew/bin/nowplaying-cli togglePlayPause
echo "  music togglePlayPause sent" >> "$LOG"
