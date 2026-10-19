#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Lock the screen with whatever fits the session.
# macOS port (better-mac): one session type, so the hyprlock/swaylock/
# betterlockscreen/i3lock chain becomes the real lock screen (Ctrl-⌘-Q via
# System Events, which needs Accessibility for AeroSpace), then sleeping the
# display, which locks when "Require password" is set to Immediately.

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

if osascript -e 'tell application "System Events" to keystroke "q" using {control down, command down}' >/dev/null 2>&1; then
    exit 0
fi

if command_exists pmset; then
    exec pmset displaysleepnow
fi

notify_replace lock critical 5000 dialog-error "Screen lock" "Allow AeroSpace under Accessibility to lock with Ctrl-Cmd-Q."
echo "No supported lock command found." >&2
exit 1
