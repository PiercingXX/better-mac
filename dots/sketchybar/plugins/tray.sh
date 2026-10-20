#!/bin/bash
# GitHub.com/PiercingXX
# The waybar tray and bluetooth module, drawn by SketchyBar itself (macOS 26
# names most menu bar icons "Item-0", so they can't be mirrored):
#   tailscale   tray icon, dimmed when Tailscale isn't connected
#   wifi        nm-applet: Wi-Fi, Ethernet or disconnected
#   bluetooth   shown only while Bluetooth is on (format-off: "")

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
ON=0xffffffff
DIM=0xff6c6c6c

case "$NAME" in
    tailscale)
        state="$(/Applications/Tailscale.app/Contents/MacOS/Tailscale status --json 2>/dev/null | jq -r '.BackendState // empty')"
        if [ -z "$state" ]; then
            sketchybar --set "$NAME" drawing=off
        elif [ "$state" = Running ]; then
            sketchybar --set "$NAME" drawing=on icon.color=$ON
        else
            sketchybar --set "$NAME" drawing=on icon.color=$DIM
        fi
        ;;
    wifi)
        if [ -n "$(ipconfig getifaddr en0 2>/dev/null)" ]; then
            sketchybar --set "$NAME" icon="󰖩" icon.color=$ON
        elif route -n get default 2>/dev/null | grep -q interface; then
            sketchybar --set "$NAME" icon="󰈀" icon.color=$ON
        else
            sketchybar --set "$NAME" icon="󰖪" icon.color=$DIM
        fi
        ;;
    bluetooth)
        if [ "$(blueutil -p 2>/dev/null)" != 1 ]; then
            sketchybar --set "$NAME" drawing=off
        elif [ "$(blueutil --connected --format json 2>/dev/null | jq length)" -gt 0 ] 2>/dev/null; then
            sketchybar --set "$NAME" drawing=on icon="󰂱"
        else
            sketchybar --set "$NAME" drawing=on icon="󰂯"
        fi
        ;;
esac
