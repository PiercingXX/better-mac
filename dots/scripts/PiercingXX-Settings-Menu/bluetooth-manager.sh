#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Bluetooth Manager: bluetui (preferred), bluetuith, or bluetoothctl.
#
# macOS port (better-mac): those TUIs need BlueZ, so this is a small gum menu
# over blueutil (Homebrew) instead. "Powered off" stands in for the rfkill
# soft-block check; the bluetooth service check is dropped (bluetoothd is
# always running under launchd).

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"
detect_distro

if ! command_exists blueutil; then
    warn "blueutil not found."
    if confirm "Install it now?"; then
        pkg_install blueutil
    fi
    command_exists blueutil || die "No Bluetooth tool available. Install it with: brew install blueutil"
fi
command_exists gum || die "gum is required for this menu."

bt_powered() { [ "$(blueutil -p 2>/dev/null)" = 1 ]; }

# Powered off shows up as "no devices" everywhere
if ! bt_powered; then
    warn "Bluetooth is turned off."
    if confirm "Turn it on?"; then
        blueutil -p 1 || warn "Could not turn Bluetooth on."
    fi
fi

# paired_devices: "address<TAB>name<TAB>connected|disconnected" per line
paired_devices() {
    local line addr name state
    blueutil --paired 2>/dev/null | while IFS= read -r line; do
        addr=$(printf '%s\n' "$line" | sed -n 's/^address: \([^,]*\),.*/\1/p')
        [ -n "$addr" ] || continue
        name=$(printf '%s\n' "$line" | sed -n 's/.*name: "\([^"]*\)".*/\1/p')
        case "$line" in
            *", not connected"*) state=disconnected ;;
            *", connected"*)     state=connected ;;
            *)                   state=disconnected ;;
        esac
        printf '%s\t%s\t%s\n' "$addr" "${name:-$addr}" "$state"
    done
}

# choose_device connected|disconnected|any -> address on stdout
choose_device() {
    local want="$1" list pick
    list=$(paired_devices | awk -F '\t' -v want="$want" 'want == "any" || $3 == want { printf "%s  [%s]  %s\n", $2, $3, $1 }')
    [ -n "$list" ] || { warn "No matching paired devices."; return 1; }
    pick=$(printf '%s\n' "$list" | gum choose --header "Select a device:") || return 1
    [ -n "$pick" ] || return 1
    printf '%s\n' "${pick##* }"
}

scan_and_pair() {
    local found list pick addr
    say "Scanning for 10 seconds... put the device in pairing mode."
    found=$(blueutil --inquiry 10 2>/dev/null | grep '^address: ')
    [ -n "$found" ] || { warn "No devices found."; return 0; }
    list=$(printf '%s\n' "$found" | sed -n 's/^address: \([^,]*\),.*name: "\([^"]*\)".*/\2  \1/p; t; s/^address: \([^,]*\),.*/unknown  \1/p')
    pick=$(printf '%s\n' "$list" | gum choose --header "Pair with:") || return 0
    [ -n "$pick" ] || return 0
    addr="${pick##* }"
    if blueutil --pair "$addr" && blueutil --connect "$addr"; then
        ok "Paired and connected."
    else
        err "Pairing failed."
    fi
}

while true; do
    clear
    if bt_powered; then echo "Bluetooth: on"; else echo "Bluetooth: off"; fi
    action=$(gum choose --header "Bluetooth Manager" \
        "Paired devices" "Connect" "Disconnect" "Scan & pair" "Forget a device" \
        "Turn Bluetooth on" "Turn Bluetooth off" "Back") || exit 0
    case "$action" in
        "Paired devices")
            paired_devices | awk -F '\t' '{ printf "  %-32s %-13s %s\n", $2, $3, $1 }' ;;
        "Connect")
            if addr=$(choose_device disconnected); then
                gum spin --spinner dot --title "Connecting..." -- blueutil --connect "$addr" \
                    && ok "Connected." || err "Could not connect."
            fi ;;
        "Disconnect")
            if addr=$(choose_device connected); then
                blueutil --disconnect "$addr" && ok "Disconnected." || err "Could not disconnect."
            fi ;;
        "Scan & pair") scan_and_pair ;;
        "Forget a device")
            if addr=$(choose_device any) && gum confirm "Forget $addr?" --default=false; then
                blueutil --unpair "$addr" && ok "Forgotten." || err "Could not forget $addr."
            fi ;;
        "Turn Bluetooth on")  blueutil -p 1 && ok "Bluetooth on." ;;
        "Turn Bluetooth off") blueutil -p 0 && ok "Bluetooth off." ;;
        *) exit 0 ;;
    esac
    pause
done
