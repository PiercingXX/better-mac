#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Show the time and date as a notification (⌥P). macOS port.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

TIME_TEXT="$(date '+%H:%M:%S')"
DATE_TEXT="$(date '+%a %b %d')"

# notify <title> <body>
notify() {
    local title="${1//\\/\\\\}" body="${2//\\/\\\\}"
    title="${title//\"/\\\"}"
    body="${body//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\"" >/dev/null 2>&1
}

notify "$TIME_TEXT" "$DATE_TEXT" || printf '%s %s\n' "$TIME_TEXT" "$DATE_TEXT"
