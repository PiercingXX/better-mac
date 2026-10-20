#!/bin/bash
# GitHub.com/PiercingXX
# Show workspaces that have windows plus the focused one; the focused one gets
# the #2c2c2c pill (waybar #workspaces button.active). Works with Rift or
# AeroSpace, whichever is running.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if pgrep -xq rift; then
    # Rift numbers workspaces from 0; the pills are 1-10
    state="$(rift-cli query workspaces 2>/dev/null)" || exit 0
    focused="$(jq -r '.[] | select(.is_active) | .index + 1' <<<"$state" | head -n1)"
    occupied=" $(jq -r '.[] | select(.window_count > 0) | .index + 1' <<<"$state" | tr '\n' ' ') "
else
    focused="$(aerospace list-workspaces --focused)"
    occupied=" $(aerospace list-workspaces --monitor all --empty no | tr '\n' ' ') "
fi

args=()
for sid in 1 2 3 4 5 6 7 8 9 10; do
    if [ "$sid" = "$focused" ]; then
        args+=(--set "space.$sid" drawing=on background.drawing=on)
    elif [[ "$occupied" == *" $sid "* ]]; then
        args+=(--set "space.$sid" drawing=on background.drawing=off)
    else
        args+=(--set "space.$sid" drawing=off)
    fi
done

sketchybar "${args[@]}"
