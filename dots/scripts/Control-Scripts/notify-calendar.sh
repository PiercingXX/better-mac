#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Show this month's calendar in a notification.
# macOS port (better-mac): a Notification Center banner can't fit (or
# monospace) the `cal` grid, so it shows the month, week number and this
# week with today in brackets; the full `cal` grid is printed when run from
# a terminal. Notifications go through osascript instead of notify-send.
#   --open   also open Calendar.app

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

MONTH_TITLE="$(date '+%B %Y') · week $(date '+%U' | sed 's/^0//')"

# This week, Sunday first like `cal`. /bin/date: -v is BSD-only and GNU
# coreutils may be first on PATH
dow=$(date '+%w')
CAL_BODY=""
for i in 0 1 2 3 4 5 6; do
    off=$(( i - dow ))
    [ "$off" -ge 0 ] && off="+$off"
    day=$(/bin/date -v"${off}"d '+%a %e' | tr -s ' ')
    day="${day% }"
    [ "$i" -eq "$dow" ] && day="[$day]"
    CAL_BODY="${CAL_BODY:+$CAL_BODY  }$day"
done

if command_exists osascript; then
    notify_replace calendar low 6000 x-office-calendar "$MONTH_TITLE" "$CAL_BODY"
fi
if [ -t 1 ] || ! command_exists osascript; then
    if command_exists cal; then cal; else printf '%s\n%s\n' "$MONTH_TITLE" "$CAL_BODY"; fi
fi

if [ "${1:-}" = "--open" ]; then
    open -a Calendar
fi
