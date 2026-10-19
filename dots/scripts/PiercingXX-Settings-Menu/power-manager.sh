#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Power & Night Light: power profile (power-profiles-daemon / TLP / tuned)
# and the hyprsunset night light on Hyprland.
#
# macOS port (better-mac): the power profile is Low Power Mode through pmset
# (always / battery only / adapter only / off; changing it asks for sudo),
# with battery and sleep timers shown alongside. Night light is Night Shift
# through the nightlight CLI (smudge/nightlight); its temperature takes
# 3500K-6500K or a 0-100 warmth. Dropped: ppd/TLP/tuned and the eww toggle.

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

command_exists gum || die "gum is required for this menu."

# lpm_for "Battery Power"|"AC Power" -> 0/1 from the per-source pmset settings
lpm_for() {
    pmset -g custom 2>/dev/null | awk -v src="$1:" '
        /^[A-Z]/ { in_src = ($0 == src) }
        in_src && $1 == "lowpowermode" { print $2; exit }'
}

current_profile() {
    local bat ac
    bat=$(lpm_for "Battery Power"); ac=$(lpm_for "AC Power")
    case "${bat:-0}${ac:-0}" in
        11) echo "Low Power Mode: always" ;;
        10) echo "Low Power Mode: on battery" ;;
        01) echo "Low Power Mode: on power adapter" ;;
        *)  echo "Low Power Mode: off" ;;
    esac
}

set_profile() {
    local pick
    pick=$(gum choose --header "Low Power Mode (now: $(current_profile | sed 's/^Low Power Mode: //'))" \
        "Off" "Always" "On battery only" "On power adapter only") || return 0
    case "$pick" in
        Off)                     sudo pmset -a lowpowermode 0 ;;
        Always)                  sudo pmset -a lowpowermode 1 ;;
        "On battery only")       sudo pmset -b lowpowermode 1 && sudo pmset -c lowpowermode 0 ;;
        "On power adapter only") sudo pmset -b lowpowermode 0 && sudo pmset -c lowpowermode 1 ;;
        *) return 0 ;;
    esac && ok "$(current_profile)"
}

power_status() {
    local batt
    batt=$(pmset -g batt 2>/dev/null | sed -n 's/^ *-InternalBattery-[0-9]* ([^)]*)[[:space:]]*//p' | cut -d' ' -f1-3)
    echo "Power source: $(pmset -g batt 2>/dev/null | sed -n "s/^Now drawing from '\(.*\)'/\1/p")${batt:+  Battery: $batt}"
    echo "Sleep: display $(pmset -g | awk '$1 == "displaysleep" {print $2}') min, system $(pmset -g | awk '$1 == "sleep" {print $2}') min"
}

nightlight_available() {
    command_exists nightlight
}

nightlight_toggle() {
    nightlight toggle >/dev/null || return 1
    ok "Night light: $(nightlight status)."
}

nightlight_temperature() {
    local t
    t=$(gum input --placeholder "3500-6500 (Kelvin) or 0-100 (warmth)" --value "$(nightlight temp)") || return 0
    if [[ "$t" =~ ^[0-9]{4}$ ]] && [ "$t" -ge 3500 ] && [ "$t" -le 6500 ]; then
        nightlight temp "${t}K" >/dev/null && ok "Night light set to ${t}K."
    elif [[ "$t" =~ ^[0-9]{1,3}$ ]] && [ "$t" -le 100 ]; then
        nightlight temp "$t" >/dev/null && ok "Night light warmth set to $t."
    else
        err "Enter 3500-6500 or 0-100."
        return 1
    fi
}

while true; do
    clear
    current_profile
    power_status
    nightlight_available && echo "Night light: $(nightlight status) (warmth $(nightlight temp), schedule $(nightlight schedule))"
    options=("Power profile")
    if nightlight_available; then
        options+=("Toggle night light" "Night light temperature")
    fi
    options+=("Back")
    choice=$(printf '%s\n' "${options[@]}" | gum choose --header "Power & Night Light") || exit 0
    case "$choice" in
        "Power profile")           set_profile ;;
        "Toggle night light")      nightlight_toggle ;;
        "Night light temperature") nightlight_temperature ;;
        *) exit 0 ;;
    esac
    pause
done
