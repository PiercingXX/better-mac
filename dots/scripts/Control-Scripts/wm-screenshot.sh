#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Screenshot helper for every WM in the rice.
# Usage: wm-screenshot.sh [region|select|window|full|fulltime|selecttime]
#   *time modes wait 5 seconds first.
# macOS port (better-mac): one backend, screencapture, instead of
# hyprshot > grim+slurp > flameshot. region is a drag (Space switches to
# window picking), window is a click, full is the main display. The PNG is
# saved and copied to the clipboard like the grim/flameshot paths. Needs
# Screen Recording permission for whatever launches it (rift).

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

mode="${1:-region}"
DELAY=5
QUICK_TIMEOUT=1500

case "$mode" in
    region|select)   kind=region ;;
    selecttime)      kind=region; sleep "$DELAY" ;;
    window)          kind=window ;;
    full)            kind=full ;;
    fulltime)        kind=full; sleep "$DELAY" ;;
    *)
        echo "Usage: $(basename "$0") [region|select|window|full|fulltime|selecttime]" >&2
        exit 2 ;;
esac

screenshot_dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
shot_name="$(date +%F-%H%M%S).png"
shot_file="$screenshot_dir/$shot_name"

notify_saved() {
    notify_replace screenshot low "$QUICK_TIMEOUT" camera-photo "Screenshot saved" "$1"
}

if ! command_exists screencapture; then
    notify_replace screenshot normal 3000 dialog-error "Screenshot" "screencapture not found."
    echo "No screenshot backend found: screencapture is missing." >&2
    exit 1
fi

mkdir -p "$screenshot_dir"

# -x: no shutter sound
case "$kind" in
    region) screencapture -x -i "$shot_file" ;;
    window) screencapture -x -i -W "$shot_file" ;;
    full)   screencapture -x -m "$shot_file" ;;
esac

# Esc in interactive mode returns without a file; trust the file
[ -f "$shot_file" ] || exit 0

osascript -e "set the clipboard to (read (POSIX file \"$(_px_osa_escape "$shot_file")\") as «class PNGf»)" >/dev/null 2>&1 || true
notify_saved "$shot_file"
