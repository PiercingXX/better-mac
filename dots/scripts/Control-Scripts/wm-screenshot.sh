#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Screenshot to ~/Pictures/Screenshots and the clipboard. macOS port
# (screencapture instead of hyprshot/grim/flameshot). Same modes:
#   region|select   drag a region (Space switches to window picking)
#   window          click a window
#   full            whole screen
#   selecttime      region after 5 seconds
#   fulltime        whole screen after 5 seconds
# Needs Screen Recording permission for whatever launches it (AeroSpace).

set -e

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

mode="${1:-region}"
screenshot_dir="$HOME/Pictures/Screenshots"
mkdir -p "$screenshot_dir"
screenshot_file="$screenshot_dir/$(date +%F-%H%M%S).png"

# notify <title> <body>
notify_screenshot() {
    local title="${1//\\/\\\\}" body="${2//\\/\\\\}"
    title="${title//\"/\\\"}"
    body="${body//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\"" >/dev/null 2>&1 || true
}

case "$mode" in
    region|select) screencapture -x -i "$screenshot_file" ;;
    window)        screencapture -x -i -W "$screenshot_file" ;;
    selecttime)    screencapture -x -T 5 -i "$screenshot_file" ;;
    fulltime)      screencapture -x -T 5 "$screenshot_file" ;;
    full|*)        screencapture -x "$screenshot_file" ;;
esac

# Esc in interactive mode leaves no file
[ -f "$screenshot_file" ] || exit 0

osascript -e "set the clipboard to (read (POSIX file \"$screenshot_file\") as «class PNGf»)" >/dev/null 2>&1 || true

notify_screenshot "Screenshot saved" "$screenshot_file"
