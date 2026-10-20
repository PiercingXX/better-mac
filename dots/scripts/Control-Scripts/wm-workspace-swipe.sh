#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Hyprland's workspace swipe for Rift (piercing-gestures, 3 fingers left/right).
# Usage: wm-workspace-swipe.sh next|prev
# Like Hyprland, a swipe only visits workspaces in use (the current one counts
# even when empty), and swiping past the last one opens one new empty
# workspace (workspace_swipe_create_new). Rift numbers workspaces 0-9.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

dir="${1:-next}"
state="$(rift-cli query workspaces 2>/dev/null)" || exit 0
current="$(jq -r '.[] | select(.is_active) | .index' <<<"$state" | head -n1)"
[ -n "$current" ] || exit 0
last="$(jq -r 'length - 1' <<<"$state")"

if [ "$dir" = next ]; then
    target="$(jq -r --argjson c "$current" \
        '[.[] | select(.index > $c and .window_count > 0) | .index] | min // empty' <<<"$state")"
    # Past the last one in use: a new empty workspace, unless this one is it
    if [ -z "$target" ]; then
        empty="$(jq -r --argjson c "$current" '.[] | select(.index == $c) | .window_count == 0' <<<"$state")"
        [ "$empty" = true ] && exit 0
        [ "$current" -lt "$last" ] || exit 0
        target=$((current + 1))
    fi
else
    target="$(jq -r --argjson c "$current" \
        '[.[] | select(.index < $c and .window_count > 0) | .index] | max // empty' <<<"$state")"
    # Nothing in use to the left: workspace 1, as Hyprland stops at 1
    if [ -z "$target" ]; then
        [ "$current" -gt 0 ] || exit 0
        target=0
    fi
fi

rift-cli execute workspace switch "$target" >/dev/null
