#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Lock the screen (⌥`). macOS port: the real lock screen (Ctrl-⌘-Q, like
# hyprlock), falling back to sleeping the display, which locks when
# "Require password" is set to Immediately.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if osascript -e 'tell application "System Events" to keystroke "q" using {control down, command down}' >/dev/null 2>&1; then
    exit 0
fi

exec pmset displaysleepnow
