#!/bin/bash
# GitHub.com/PiercingXX
# Show workspaces that have windows plus the focused one; the focused one gets
# the #2c2c2c pill (waybar #workspaces button.active).

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

focused="$(aerospace list-workspaces --focused)"
occupied=" $(aerospace list-workspaces --monitor all --empty no | tr '\n' ' ') "

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
