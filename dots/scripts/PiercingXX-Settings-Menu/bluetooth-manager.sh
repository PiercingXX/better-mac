#!/usr/bin/env bash
# GitHub.com/PiercingXX

# Bluetooth Manager using blueutil (bluetuith needs BlueZ, which macOS doesn't have)

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Ensure blueutil and gum are installed
for tool in blueutil gum; do
    if ! command -v "$tool" &>/dev/null && command -v brew &>/dev/null; then
        echo "$tool not found. Installing $tool with brew..."
        brew install "$tool"
    fi
    if ! command -v "$tool" &>/dev/null; then
        echo "$tool is not installed and could not be installed automatically. Please install $tool."
        exit 1
    fi
done

# paired_devices: "address<TAB>name<TAB>connected|disconnected" per line
paired_devices() {
    blueutil --paired 2>/dev/null | while IFS= read -r line; do
        local addr name state
        addr=$(printf '%s\n' "$line" | sed -n 's/^address: \([^,]*\),.*/\1/p')
        [ -n "$addr" ] || continue
        name=$(printf '%s\n' "$line" | sed -n 's/.*name: "\([^"]*\)".*/\1/p')
        case "$line" in
            *", not connected"*) state="disconnected" ;;
            *", connected"*) state="connected" ;;
            *) state="disconnected" ;;
        esac
        printf '%s\t%s\t%s\n' "$addr" "${name:-$addr}" "$state"
    done
}

# choose_device <connected|disconnected|any>: prints the chosen address
choose_device() {
    local want="$1" list choice
    list=$(paired_devices | awk -F '\t' -v want="$want" 'want == "any" || $3 == want { printf "%s  [%s]  %s\n", $2, $3, $1 }')
    if [ -z "$list" ]; then
        echo "No matching paired devices." >&2
        return 1
    fi
    choice=$(printf '%s\n' "$list" | gum choose --header="Select a device:") || return 1
    [ -n "$choice" ] || return 1
    printf '%s\n' "${choice##* }"
}

while true; do
    clear
    if [ "$(blueutil -p 2>/dev/null)" = "1" ]; then
        power_state="On"
    else
        power_state="Off"
    fi
    gum style --border rounded --padding "0 2" --foreground 6 "Bluetooth: $power_state"

    action=$(gum choose --header="Bluetooth Manager" \
        "Paired Devices" \
        "Connect" \
        "Disconnect" \
        "Scan & Pair" \
        "Turn Bluetooth On" \
        "Turn Bluetooth Off" \
        "Back")
    case "$action" in
        "Paired Devices")
            paired_devices | awk -F '\t' '{ printf "  %-32s %-13s %s\n", $2, $3, $1 }'
            ;;
        "Connect")
            if addr=$(choose_device disconnected); then
                gum spin --spinner dot --title "Connecting..." -- blueutil --connect "$addr" \
                    && echo "✓ Connected." || echo "✗ Could not connect."
            fi
            ;;
        "Disconnect")
            if addr=$(choose_device connected); then
                blueutil --disconnect "$addr" && echo "✓ Disconnected." || echo "✗ Could not disconnect."
            fi
            ;;
        "Scan & Pair")
            echo "Scanning for 10 seconds... put the device in pairing mode."
            found=$(blueutil --inquiry 10 2>/dev/null | awk '/^address: /' )
            if [ -z "$found" ]; then
                echo "No devices found."
            else
                list=$(printf '%s\n' "$found" | while IFS= read -r line; do
                    a=$(printf '%s\n' "$line" | sed -n 's/^address: \([^,]*\),.*/\1/p')
                    n=$(printf '%s\n' "$line" | sed -n 's/.*name: "\([^"]*\)".*/\1/p')
                    printf '%s  %s\n' "${n:-unknown}" "$a"
                done)
                choice=$(printf '%s\n' "$list" | gum choose --header="Pair with:")
                if [ -n "$choice" ]; then
                    addr="${choice##* }"
                    blueutil --pair "$addr" && blueutil --connect "$addr" \
                        && echo "✓ Paired and connected." || echo "✗ Pairing failed."
                fi
            fi
            ;;
        "Turn Bluetooth On")
            blueutil -p 1 && echo "Bluetooth on."
            ;;
        "Turn Bluetooth Off")
            blueutil -p 0 && echo "Bluetooth off."
            ;;
        "Back"|"")
            break
            ;;
    esac
    echo "Press Enter to continue..."
    read -r
done

# After exiting, return to the settings menu
SCRIPT_DIR="$(dirname "$0")"
SETTINGS_MENU="$SCRIPT_DIR/settings-menu.sh"
if [ -x "$SETTINGS_MENU" ]; then
    "$SETTINGS_MENU"
else
    echo "Settings menu not found at $SETTINGS_MENU."
fi
