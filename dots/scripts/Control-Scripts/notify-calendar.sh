#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Show this week of the month as a notification (⌥⇧P). macOS port.
# A macOS notification can't fit the whole `cal` grid, so it shows the month,
# week number and the current week with today in brackets.
#   --open   also open Calendar.app on today

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MONTH_TITLE="$(date '+%B %Y') · week $(date '+%U' | sed 's/^0//')"

# day_offset <n> <format>: date n days from today (BSD date, GNU fallback)
day_offset() {
    date -v"${1}"d "+$2" 2>/dev/null || date -d "${1} day" "+$2"
}

dow="$(date '+%w')"    # 0 = Sunday, same week layout as `cal`
week=""
for i in 0 1 2 3 4 5 6; do
    off=$(( i - dow ))
    [ "$off" -ge 0 ] && off="+$off"
    day="$(day_offset "$off" '%a %e' | tr -s ' ')"
    day="${day% }"
    if [ "$i" -eq "$dow" ]; then
        day="[$day]"
    fi
    week="${week:+$week  }$day"
done

# notify <title> <body>
notify() {
    local title="${1//\\/\\\\}" body="${2//\\/\\\\}"
    title="${title//\"/\\\"}"
    body="${body//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\"" >/dev/null 2>&1
}

notify "$MONTH_TITLE" "$week" || printf '%s\n%s\n' "$MONTH_TITLE" "$week"

if [ "${1:-}" = "--open" ]; then
    open -a Calendar
fi
