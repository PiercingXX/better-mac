#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Bluetooth status notification daemon (any WM; needs blueutil).
# Polls blueutil; useful with the menu bar hidden.
# macOS port (better-mac): blueutil replaces bluetoothctl. macOS has no
# bluez D-Bus signal stream, so the upstream polling fallback is the event
# source. Notification timeouts/icons are ignored by Notification Center.

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

POLL_INTERVAL=5      # blueutil poll (no event stream on macOS)
RECHECK_INTERVAL=60  # safety re-check while the event stream is quiet
STATE_TIMEOUT=2200

if ! command_exists blueutil; then
    echo "bluetooth-notify: blueutil not found (brew install blueutil)." >&2
    exit 1
fi

single_instance bluetooth-notify || exit 0

notify() {
    local summary="$1" body="$2" icon="$3" urgency="$4"
    notify_replace bluetooth "$urgency" "$STATE_TIMEOUT" "$icon" "$summary" "$body"
}

SEP=$'\x1f'
get_snapshot() {
    local powered connected
    # blueutil --power prints 1/0; map to bluetoothctl's yes/no
    case "$(blueutil --power 2>/dev/null)" in
        1) powered=yes ;;
        *) powered=no ;;
    esac
    connected=$(blueutil --connected 2>/dev/null \
        | sed -n 's/.*name: "\([^"]*\)".*/\1/p' \
        | paste -sd ',' - | sed 's/,/, /g')
    printf '%s%s%s\n' "$powered" "$SEP" "$connected"
}

build_message() {
    local powered="$1" connected="$2"
    if [[ "$powered" != "yes" ]]; then
        SUMMARY="Bluetooth - Off"
        BODY="Adapter is powered off"
        ICON="bluetooth-disabled"
        URGENCY="low"
        return
    fi

    if [[ -n "$connected" ]]; then
        SUMMARY="Bluetooth - Connected"
        BODY="$connected"
        ICON="bluetooth-active"
        URGENCY="low"
    else
        SUMMARY="Bluetooth - On"
        BODY="No connected devices"
        ICON="bluetooth"
        URGENCY="low"
    fi
}

check_bluetooth() {
    local current powered connected
    current="$(get_snapshot)"
    [[ "$current" == "$last" ]] && return 0
    IFS="$SEP" read -r powered connected <<< "$current"
    build_message "$powered" "$connected"
    notify "$SUMMARY" "$BODY" "$ICON" "$URGENCY"
    last="$current"
}

event_source() {
    while sleep "$POLL_INTERVAL"; do echo tick; done
}

last="$(get_snapshot)"

while true; do
    while IFS= read -r -t "$RECHECK_INTERVAL" _ || [ $? -gt 128 ]; do
        # One state change emits a burst of signals; drain it before re-reading
        while IFS= read -r -t 0.5 _; do :; done
        check_bluetooth
    done < <(event_source)
    sleep 5
done
