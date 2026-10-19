#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Show the time and date in a notification.
# macOS port (better-mac): notifications always go through osascript, so
# the notify-send check is dropped; prints instead when osascript is missing.

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

TIME_TEXT="$(date '+%H:%M:%S')"
DATE_TEXT="$(date '+%a %b %d')"

if command_exists osascript; then
    notify_replace time low 2500 preferences-system-time "$TIME_TEXT" "$DATE_TEXT"
else
    printf '%s %s\n' "$TIME_TEXT" "$DATE_TEXT"
fi
