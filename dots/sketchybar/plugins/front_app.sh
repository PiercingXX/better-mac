#!/bin/bash
# GitHub.com/PiercingXX
# Focused app's icon and name (waybar hyprland/window with icon: true).
# front_app_switched passes the app name in $INFO; the icon comes from the
# app's bundle id. Other events (startup, wake) read the frontmost app.

name="$INFO"
front="$(lsappinfo front 2>/dev/null)"
bundle="$(lsappinfo info -only bundleid "$front" 2>/dev/null | cut -d'"' -f4)"
if [ "$SENDER" != "front_app_switched" ] || [ -z "$name" ]; then
    name="$(lsappinfo info -only name "$front" 2>/dev/null | cut -d'"' -f4)"
fi

sketchybar --set "$NAME" label="$name" \
                         icon.background.image="app.${bundle:-com.apple.finder}"
