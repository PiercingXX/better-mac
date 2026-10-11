#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Bluetooth status notification daemon. macOS port (blueutil instead of
# bluetoothctl). Useful with the menu bar hidden.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

POLL_INTERVAL=5

if ! command -v blueutil &>/dev/null; then
    echo "bluetooth-notify: blueutil not found (brew install blueutil)." >&2
    exit 1
fi

# One instance only
PIDFILE="${TMPDIR:-/tmp}/bluetooth-notify.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo $$ >"$PIDFILE"

# notify <title> <body>
notify() {
    local title="${1//\\/\\\\}" body="${2//\\/\\\\}"
    title="${title//\"/\\\"}"
    body="${body//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\"" >/dev/null 2>&1
}

get_snapshot() {
    local powered connected
    powered="$(blueutil --power 2>/dev/null)"
    connected="$(blueutil --connected 2>/dev/null \
        | sed -n 's/.*name: "\([^"]*\)".*/\1/p' \
        | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }')"
    printf '%s|%s\n' "$powered" "$connected"
}

build_message() {
    local powered="$1" connected="$2"
    if [[ "$powered" != "1" ]]; then
        SUMMARY="Bluetooth - Off"
        BODY="Adapter is powered off"
        return
    fi

    if [[ -n "$connected" ]]; then
        SUMMARY="Bluetooth - Connected"
        BODY="$connected"
    else
        SUMMARY="Bluetooth - On"
        BODY="No connected devices"
    fi
}

last="$(get_snapshot)"

while true; do
    current="$(get_snapshot)"
    if [[ "$current" != "$last" ]]; then
        IFS='|' read -r powered connected <<<"$current"
        build_message "$powered" "$connected"
        notify "$SUMMARY" "$BODY"
        last="$current"
    fi
    sleep "$POLL_INTERVAL"
done
