#!/usr/bin/env bash
# GitHub.com/PiercingXX

# Simple WiFi Manager using networksetup (nmtui is NetworkManager-only)

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v networksetup &>/dev/null; then
    echo "networksetup not found. This WiFi manager needs macOS."
    exit 1
fi
if ! command -v gum &>/dev/null; then
    echo "gum is not installed. Please install gum (brew install gum)."
    exit 1
fi

# Wi-Fi device (usually en0)
WIFI_DEV=$(networksetup -listallhardwareports | awk '/^Hardware Port: (Wi-Fi|AirPort)$/ { getline; print $2; exit }')
if [ -z "$WIFI_DEV" ]; then
    echo "No Wi-Fi hardware found."
    exit 1
fi

current_network() {
    # macOS 14.4+ may hide the SSID ("not associated") without Location access
    networksetup -getairportnetwork "$WIFI_DEV" 2>/dev/null | sed -n 's/^Current Wi-Fi Network: //p'
}

# nearby_networks: SSIDs from system_profiler (the airport tool is gone)
nearby_networks() {
    system_profiler SPAirPortDataType 2>/dev/null | awk '
        /Other Local Wi-Fi Networks:/ { other = 1; next }
        other && /PHY Mode:/ && prev ~ /:$/ {
            ssid = prev
            sub(/^[[:space:]]+/, "", ssid)
            sub(/:$/, "", ssid)
            if (!(ssid in seen)) { seen[ssid] = 1; print ssid }
        }
        { prev = $0 }
    '
}

while true; do
    clear
    power=$(networksetup -getairportpower "$WIFI_DEV" 2>/dev/null | awk '{ print $NF }')
    net=$(current_network)
    gum style --border rounded --padding "0 2" --foreground 6 \
        "Wi-Fi ($WIFI_DEV): ${power:-?}" "Network: ${net:-not connected}"

    action=$(gum choose --header="WiFi Manager" \
        "Connect to Network" \
        "Scan Nearby Networks" \
        "Turn Wi-Fi On" \
        "Turn Wi-Fi Off" \
        "Open Wi-Fi Settings" \
        "Back")
    case "$action" in
        "Connect to Network")
            ssid=""
            if gum confirm "Scan for nearby networks first? (takes ~10s)"; then
                list=$(gum spin --spinner dot --title "Scanning..." --show-output -- bash -c "$(declare -f nearby_networks); nearby_networks")
                if [ -n "$list" ]; then
                    ssid=$(printf '%s\n' "$list" | gum choose --header="Select a network:")
                else
                    echo "No networks found (macOS may hide names without Location access)."
                fi
            fi
            [ -n "$ssid" ] || ssid=$(gum input --placeholder="Network name (SSID)")
            if [ -n "$ssid" ]; then
                pass=$(gum input --password --placeholder="Password (leave empty for open networks)")
                if [ -n "$pass" ]; then
                    out=$(networksetup -setairportnetwork "$WIFI_DEV" "$ssid" "$pass" 2>&1)
                else
                    out=$(networksetup -setairportnetwork "$WIFI_DEV" "$ssid" 2>&1)
                fi
                if [ -z "$out" ]; then
                    echo "✓ Connected to $ssid."
                else
                    echo "✗ $out"
                fi
            fi
            ;;
        "Scan Nearby Networks")
            gum spin --spinner dot --title "Scanning (system_profiler is slow)..." --show-output -- \
                bash -c "$(declare -f nearby_networks); nearby_networks"
            ;;
        "Turn Wi-Fi On")
            networksetup -setairportpower "$WIFI_DEV" on && echo "Wi-Fi on."
            ;;
        "Turn Wi-Fi Off")
            networksetup -setairportpower "$WIFI_DEV" off && echo "Wi-Fi off."
            ;;
        "Open Wi-Fi Settings")
            open "x-apple.systempreferences:com.apple.wifi-settings-extension"
            ;;
        "Back"|"")
            break
            ;;
    esac
    echo "Press Enter to continue..."
    read -r
done

# After exiting, return to the settings menu if available
SCRIPT_DIR="$(dirname "$0")"
SETTINGS_MENU="$SCRIPT_DIR/settings-menu.sh"
if [ -x "$SETTINGS_MENU" ]; then
    "$SETTINGS_MENU"
else
    echo "Settings menu not found at $SETTINGS_MENU."
fi
