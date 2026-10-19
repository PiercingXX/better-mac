#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Network status notification daemon (any WM).
# macOS port (better-mac): NetworkManager doesn't exist; the state is the
# default-route interface and its address (route/ipconfig), the Wi-Fi name
# comes from networksetup/ipconfig, and `route -n monitor` (routing socket
# events) replaces `nmcli monitor`. Upstream's "Connecting" state has no
# equivalent and is dropped; a VPN default route (utun/ipsec/ppp) is reported.
# Notification timeouts/icons are ignored by Notification Center.

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

POLL_INTERVAL=30   # safety re-check; route monitor delivers changes instantly
STATE_TIMEOUT=2200

if ! command_exists route || ! command_exists ipconfig; then
    echo "network-notify: route/ipconfig not found." >&2
    exit 1
fi

single_instance network-notify || exit 0

notify() {
    local summary="$1" body="$2" icon="$3" urgency="$4"
    notify_replace network "$urgency" "$STATE_TIMEOUT" "$icon" "$summary" "$body"
}

# The Wi-Fi interface (usually en0, but not on every Mac)
WIFI_DEV=$(networksetup -listallhardwareports 2>/dev/null \
    | awk '/^Hardware Port: (Wi-Fi|AirPort)/ {getline; print $2; exit}')

# Fields are joined with a unit separator (\x1f) like upstream
SEP=$'\x1f'
snapshot_state() {
    local iface ip=""
    iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')
    [ -n "$iface" ] && ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
    printf '%s%s%s\n' "$iface" "$SEP" "$ip"
}

# Recent macOS hides the SSID from tools without Location access, so try a
# few sources and fall back to no name
wifi_ssid() {
    local ssid=""
    [ -n "$WIFI_DEV" ] || return 0
    ssid=$(networksetup -getairportnetwork "$WIFI_DEV" 2>/dev/null | sed -n 's/^Current Wi-Fi Network: //p')
    if [ -z "$ssid" ]; then
        ssid=$(ipconfig getsummary "$WIFI_DEV" 2>/dev/null | awk -F ' SSID : ' '/ SSID : / {print $2; exit}')
    fi
    case "$ssid" in
        *redacted*) ssid="" ;;
    esac
    printf '%s\n' "$ssid"
}

build_message() {
    local iface="$1" ip="$2" wifi_ssid

    # A VPN default route may have no IPv4 address of its own
    case "$iface" in
        utun*|ipsec*|ppp*)
            SUMMARY="Network - VPN"
            BODY="Traffic routed through ${iface}"
            ICON="network-vpn"
            URGENCY="low"
            return
            ;;
    esac

    if [[ -z "$iface" || -z "$ip" ]]; then
        SUMMARY="Network - Disconnected"
        BODY="No active network connection"
        ICON="network-offline"
        URGENCY="low"
        return
    fi

    if [[ "$iface" == "$WIFI_DEV" ]]; then
        wifi_ssid=$(wifi_ssid)
        SUMMARY="Network - Wi-Fi"
        if [[ -n "$wifi_ssid" ]]; then
            BODY="Connected to ${wifi_ssid}"
        else
            BODY="Connected (${ip})"
        fi
        ICON="network-wireless"
        URGENCY="low"
        return
    fi

    SUMMARY="Network - Ethernet"
    BODY="Connected on ${iface} (${ip})"
    ICON="network-wired"
    URGENCY="low"
}

check_network() {
    local current iface ip
    current="$(snapshot_state)"
    [[ "$current" == "$last" ]] && return 0
    IFS="$SEP" read -r iface ip <<< "$current"
    build_message "$iface" "$ip"
    notify "$SUMMARY" "$BODY" "$ICON" "$URGENCY"
    last="$current"
}

# One line per routing change. route monitor also echoes every lookup
# (RTM_GET, including our own `route get`) and ARP misses; skip those or
# each check would trigger the next.
route_events() {
    route -n monitor 2>/dev/null \
        | awk '/^RTM_/ && !/^RTM_(GET|MISS|RESOLVE|GET_SILENT)/ {print; fflush()}'
}

last="$(snapshot_state)"

while true; do
    # route monitor prints a block on every routing change; read -t keeps a
    # slow periodic re-check in case the monitor stream stalls.
    while IFS= read -r -t "$POLL_INTERVAL" _ || [ $? -gt 128 ]; do
        # One change prints a burst of messages (and DHCP lags the route);
        # let it settle before re-reading
        while IFS= read -r -t 1 _; do :; done
        check_network
    done < <(route_events)
    sleep 5
done
