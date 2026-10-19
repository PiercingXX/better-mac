#!/usr/bin/env bash
# GitHub.com/PiercingXX
# WiFi Manager: nmtui for NetworkManager, impala/iwctl for iwd.
# Runs unprivileged; NetworkManager/iwd authorize through polkit.
#
# macOS port (better-mac): no nmtui/iwd, so this is a small gum menu over
# networksetup. macOS 14+ redacts SSIDs (current and scanned) unless the
# terminal has Location access, so the connect list starts with the saved
# (preferred) networks, which stay readable; scans skip <redacted> names.

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"
detect_distro

command_exists networksetup || die "networksetup not found."
command_exists gum || die "gum is required for this menu."

# Wi-Fi device (usually en0)
WIFI_DEV=$(networksetup -listallhardwareports | awk '/^Hardware Port: (Wi-Fi|AirPort)$/ { getline; print $2; exit }')
[ -n "$WIFI_DEV" ] || die "No Wi-Fi hardware found."

wifi_power() {
    networksetup -getairportpower "$WIFI_DEV" 2>/dev/null | awk '{ print $NF }'
}

# current_network -> SSID, "<redacted>" when hidden, empty when not associated
current_network() {
    ipconfig getsummary "$WIFI_DEV" 2>/dev/null | awk -F ' : ' '/^ +SSID : / { print $2; exit }'
}

saved_networks() {
    networksetup -listpreferredwirelessnetworks "$WIFI_DEV" 2>/dev/null | sed -n 's/^[[:space:]]\{1,\}//p'
}

# nearby_networks: SSIDs from system_profiler (the airport tool is gone; ~10s)
nearby_networks() {
    system_profiler SPAirPortDataType 2>/dev/null | awk '
        /Other Local Wi-Fi Networks:/ { other = 1; next }
        other && /PHY Mode:/ && prev ~ /:$/ {
            ssid = prev
            sub(/^[[:space:]]+/, "", ssid); sub(/:$/, "", ssid)
            if (ssid != "<redacted>" && !(ssid in seen)) { seen[ssid] = 1; print ssid }
        }
        { prev = $0 }
    '
}

connect_network() {
    local list ssid pass out
    list=$(saved_networks)
    if gum confirm "Scan for nearby networks too? (takes ~10s)" --default=false; then
        list=$(printf '%s\n%s\n' "$list" "$(gum spin --spinner dot --title "Scanning..." --show-output -- \
            bash -c "$(declare -f nearby_networks); nearby_networks")" | awk 'NF && !seen[$0]++')
    fi
    ssid=$(printf '%s\n' "$list" "Other..." | grep . | gum choose --header "Select a network:") || return 0
    [ "$ssid" = "Other..." ] && { ssid=$(gum input --placeholder "Network name (SSID)") || return 0; }
    [ -n "$ssid" ] || return 0
    # Saved networks reuse the keychain password; an empty answer tries that
    pass=$(gum input --password --placeholder "Password (empty for open or saved networks)") || return 0
    if [ -n "$pass" ]; then
        out=$(networksetup -setairportnetwork "$WIFI_DEV" "$ssid" "$pass" 2>&1)
    else
        out=$(networksetup -setairportnetwork "$WIFI_DEV" "$ssid" 2>&1)
    fi
    if [ -z "$out" ]; then ok "Connected to $ssid."; else err "$out"; fi
}

while true; do
    clear
    net=$(current_network)
    case "$net" in
        "")           net="not connected" ;;
        "<redacted>") net="connected (name hidden: give your terminal Location access)" ;;
    esac
    echo "Wi-Fi ($WIFI_DEV): $(wifi_power)  Network: $net"
    action=$(gum choose --header "WiFi Manager" \
        "Connect to a network" "Scan nearby networks" "Saved networks" \
        "Turn Wi-Fi on" "Turn Wi-Fi off" "Open Wi-Fi settings" "Back") || exit 0
    case "$action" in
        "Connect to a network") connect_network ;;
        "Scan nearby networks")
            gum spin --spinner dot --title "Scanning (system_profiler is slow)..." --show-output -- \
                bash -c "$(declare -f nearby_networks); nearby_networks"
            say "Hidden names (<redacted>) need Location access for your terminal." ;;
        "Saved networks")  saved_networks ;;
        "Turn Wi-Fi on")   networksetup -setairportpower "$WIFI_DEV" on && ok "Wi-Fi on." ;;
        "Turn Wi-Fi off")  networksetup -setairportpower "$WIFI_DEV" off && ok "Wi-Fi off." ;;
        "Open Wi-Fi settings")
            open "x-apple.systempreferences:com.apple.wifi-settings-extension"; continue ;;
        *) exit 0 ;;
    esac
    pause
done
