#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Battery level notification daemon. macOS port (pmset).
# Notifies at 40%, 30%, 20%, and 10% while discharging, and when the
# power source changes. Exits silently on Macs without a battery.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

POLL_INTERVAL=60  # seconds between checks

# One instance only
PIDFILE="${TMPDIR:-/tmp}/battery-notify.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo $$ >"$PIDFILE"

# No battery = desktop Mac, exit cleanly
pmset -g batt 2>/dev/null | grep -q 'InternalBattery' || exit 0

# notify <title> <body>
notify() {
    local title="${1//\\/\\\\}" body="${2//\\/\\\\}"
    title="${title//\"/\\\"}"
    body="${body//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\"" >/dev/null 2>&1
}

# read_battery: sets level and status (Charging / Discharging / Full / Not charging)
read_battery() {
    local line
    line="$(pmset -g batt 2>/dev/null | grep 'InternalBattery')"
    level="$(printf '%s' "$line" | grep -Eo '[0-9]+%' | head -n1 | tr -d '%')"
    case "$line" in
        *"; discharging;"*)        status="Discharging" ;;
        *"; charged;"*)            status="Full" ;;
        *"; charging;"*|*"; finishing charge;"*) status="Charging" ;;
        *"not charging"*|*"AC attached"*) status="Not charging" ;;
        *)                         status="" ;;
    esac
}

LAST_NOTIFIED=100  # tracks lowest threshold already notified this discharge cycle
read_battery
LAST_STATUS="$status"

while true; do
    read_battery
    if [[ -z "$level" ]]; then
        sleep "$POLL_INTERVAL"
        continue
    fi

    if [[ "$status" != "$LAST_STATUS" && -n "$status" ]]; then
        case "$status" in
            Charging)       notify "Power connected" "Charging (${level}%)" ;;
            Discharging)    notify "On battery" "Discharging (${level}%)" ;;
            Full)           notify "Battery full" "100%" ;;
            "Not charging") notify "Power state changed" "Not charging (${level}%)" ;;
        esac
        LAST_STATUS="$status"
    fi

    if [[ "$status" == "Discharging" ]]; then
        # Walk thresholds from highest to lowest; notify once per crossing going down
        for threshold in 40 30 20 10; do
            if (( level <= threshold && LAST_NOTIFIED > threshold )); then
                LAST_NOTIFIED=$threshold
                notify "Battery ${level}%" "Plug in soon."
                break
            fi
        done
    else
        # Charging or Full — reset so we notify again next discharge cycle
        LAST_NOTIFIED=100
    fi

    sleep "$POLL_INTERVAL"
done
