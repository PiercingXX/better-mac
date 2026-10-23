#!/bin/bash
# GitHub.com/PiercingXX
# Focused app's icon and name (waybar hyprland/window with icon: true).
# Under Rift the name and icon come from the focused window, so closing the
# last window of an app clears the item (macOS keeps the app frontmost, and
# front_app_switched never fires). Under AeroSpace, front_app_switched passes
# the app name in $INFO; other events read the frontmost app.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if pgrep -xq rift; then
    state="$(rift-cli query workspaces 2>/dev/null)" || exit 0
    win="$(jq -r 'first(.[] | select(.is_active) | .windows[] | select(.is_focused)) | [.app_name, .bundle_id] | @tsv' <<<"$state")"
    if [ -z "$win" ]; then
        sketchybar --set "$NAME" drawing=off
        exit 0
    fi
    IFS=$'\t' read -r name bundle <<<"$win"
else
    name="$INFO"
    front="$(lsappinfo front 2>/dev/null)"
    bundle="$(lsappinfo info -only bundleid "$front" 2>/dev/null | cut -d'"' -f4)"
    if [ "$SENDER" != "front_app_switched" ] || [ -z "$name" ]; then
        name="$(lsappinfo info -only name "$front" 2>/dev/null | cut -d'"' -f4)"
    fi
fi

sketchybar --set "$NAME" drawing=on label="$name" \
                         icon.background.image="app.${bundle:-com.apple.finder}"
