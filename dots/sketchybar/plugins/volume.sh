#!/bin/bash
# GitHub.com/PiercingXX
# volume_change passes the percentage in $INFO; on startup, ask macOS.

if [ "$SENDER" = "volume_change" ]; then
    volume="$INFO"
else
    volume="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
fi

case "$volume" in
    [6-9][0-9]|100) icon="󰕾" ;;
    [3-5][0-9])     icon="󰖀" ;;
    [1-9]|[1-2][0-9]) icon="󰕿" ;;
    *)              icon="󰖁" ;;
esac

sketchybar --set "$NAME" icon="$icon" label="${volume:-0}%"
