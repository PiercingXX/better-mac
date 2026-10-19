#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Battery level notification daemon.
# Notifies at 40%, 30%, 20%, and 10% while discharging, plus plug/unplug.
# Event-driven via `pmset -g pslog`; falls back to polling pmset.
# Exits silently on desktops (no battery present).
# macOS port (better-mac): pmset replaces sysfs, and `pmset -g pslog`
# (prints on every power-source notification) replaces upower/udev.
# Notification timeouts/icons are ignored by Notification Center.

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

POLL_INTERVAL=60  # safety re-check even when events are flowing
STATE_TIMEOUT=2200
CRITICAL_TIMEOUT=7000
THRESHOLDS=(10 20 30 40)  # ascending

# No battery = desktop Mac, exit cleanly
pmset -g batt 2>/dev/null | grep -q 'InternalBattery' || exit 0

single_instance battery-notify || exit 0

# read_battery: sets level and status (Charging / Discharging / Full / Not charging),
# the same words sysfs uses upstream
read_battery() {
    local line
    line=$(pmset -g batt 2>/dev/null | grep 'InternalBattery')
    level=$(printf '%s' "$line" | grep -Eo '[0-9]+%' | head -n1 | tr -d '%')
    case "$line" in
        *"; discharging;"*)                      status="Discharging" ;;
        *"; charged;"*)                          status="Full" ;;
        *"; charging;"*|*"; finishing charge;"*) status="Charging" ;;
        *"not charging"*|*"AC attached"*)        status="Not charging" ;;
        *)                                       status="" ;;
    esac
}

LAST_NOTIFIED=100  # lowest threshold already notified this discharge cycle
read_battery
LAST_STATUS="$status"

check_battery() {
    local level status
    read_battery
    [[ "$level" =~ ^[0-9]+$ ]] || return 0

    if [[ -n "$status" && "$status" != "$LAST_STATUS" ]]; then
        case "$status" in
            Charging)
                notify_replace battery-state low "$STATE_TIMEOUT" battery-good-charging "Power connected" "Charging (${level}%)" ;;
            Discharging)
                notify_replace battery-state low "$STATE_TIMEOUT" battery-low "On battery" "Discharging (${level}%)" ;;
            Full)
                notify_replace battery-state low "$STATE_TIMEOUT" battery-full-charged "Battery full" "100%" ;;
            "Not charging")
                notify_replace battery-state low "$STATE_TIMEOUT" battery "Power state changed" "Not charging (${level}%)" ;;
        esac
        LAST_STATUS="$status"
    fi

    if [[ "$status" == "Discharging" ]]; then
        # Lowest threshold crossed since the last notification, one bubble only
        local threshold crossed=""
        for threshold in "${THRESHOLDS[@]}"; do
            if (( level <= threshold && LAST_NOTIFIED > threshold )); then
                crossed=$threshold
                break
            fi
        done
        if [ -n "$crossed" ]; then
            LAST_NOTIFIED=$crossed
            if (( crossed <= 20 )); then
                notify_replace battery critical "$CRITICAL_TIMEOUT" battery-caution "Battery ${level}%" "Plug in soon."
            else
                notify_replace battery low "$STATE_TIMEOUT" battery-low "Battery ${level}%" "Plug in soon."
            fi
        fi
    else
        # Charging or Full — reset so we notify again next discharge cycle
        LAST_NOTIFIED=100
    fi
}

# Event source: any line means "something changed, re-read pmset"
event_source() {
    if command_exists pmset; then
        exec pmset -g pslog 2>/dev/null
    else
        # No event source: emit a tick every interval
        while sleep "$POLL_INTERVAL"; do echo tick; done
    fi
}

check_battery
while true; do
    # read -t gives a periodic re-check even if the event stream is quiet
    while IFS= read -r -t "$POLL_INTERVAL" _ || [ $? -gt 128 ]; do
        # pslog prints several lines per event; drain the burst first
        while IFS= read -r -t 0.5 _; do :; done
        check_battery
    done < <(event_source)
    # Event source died; back off and reconnect
    sleep 5
done
