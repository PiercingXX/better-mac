#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Network status notification daemon. macOS port (route/ipconfig/networksetup
# instead of nmcli). Useful with the menu bar hidden.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

POLL_INTERVAL=5

# One instance only
PIDFILE="${TMPDIR:-/tmp}/network-notify.pid"
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

# The Wi-Fi interface (usually en0, but not on every Mac)
WIFI_DEV="$(networksetup -listallhardwareports 2>/dev/null \
    | awk '/^Hardware Port: (Wi-Fi|AirPort)/ {getline; print $2; exit}')"

# Default-route interface and its address: cheap enough to poll every 5s
snapshot_state() {
    local iface ip
    iface="$(route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')"
    [ -n "$iface" ] && ip="$(ipconfig getifaddr "$iface" 2>/dev/null)"
    printf '%s|%s\n' "$iface" "$ip"
}

# Recent macOS hides the SSID from tools without Location access, so try a
# few sources and fall back to no name
wifi_ssid() {
    local ssid=""
    [ -n "$WIFI_DEV" ] || return 0
    ssid="$(networksetup -getairportnetwork "$WIFI_DEV" 2>/dev/null | sed -n 's/^Current Wi-Fi Network: //p')"
    if [ -z "$ssid" ]; then
        ssid="$(ipconfig getsummary "$WIFI_DEV" 2>/dev/null | awk -F ' SSID : ' '/ SSID : / {print $2; exit}')"
    fi
    case "$ssid" in
        *redacted*) ssid="" ;;
    esac
    printf '%s\n' "$ssid"
}

build_message() {
    local iface="$1" ip="$2" ssid

    if [[ -z "$iface" || -z "$ip" ]] && [[ "$iface" != utun* ]]; then
        SUMMARY="Network - Disconnected"
        BODY="No active network connection"
        return
    fi

    case "$iface" in
        utun*|ipsec*|ppp*)
            SUMMARY="Network - VPN"
            BODY="Traffic routed through ${iface}"
            ;;
        "$WIFI_DEV")
            ssid="$(wifi_ssid)"
            SUMMARY="Network - Wi-Fi"
            if [[ -n "$ssid" ]]; then
                BODY="Connected to ${ssid}"
            else
                BODY="Connected (${ip})"
            fi
            ;;
        *)
            SUMMARY="Network - Ethernet"
            BODY="Connected on ${iface} (${ip})"
            ;;
    esac
}

last="$(snapshot_state)"

while true; do
    current="$(snapshot_state)"
    if [[ "$current" != "$last" ]]; then
        IFS='|' read -r iface ip <<<"$current"
        build_message "$iface" "$ip"
        notify "$SUMMARY" "$BODY"
        last="$current"
    fi
    sleep "$POLL_INTERVAL"
done
