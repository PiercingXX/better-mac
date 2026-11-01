#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Step the keyboard backlight through its presets (off, 5, 30, 60, 90%) and
# show the shared on-screen bubble. better-mac only: Apple Silicon keyboards
# have no backlight keys, so Karabiner sends F6 (Do Not Disturb) here.
# piercing-kbd (dots/kbd) does the work; macOS has no CLI for it.

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

KBD="$HOME/.local/bin/piercing-kbd"

if ! level="$("$KBD" cycle 2>&1)"; then
    notify_replace osd normal 3000 dialog-error "Keyboard backlight" "$level"
    exit 1
fi

if [ "$level" -eq 0 ]; then
    notify_replace osd low 1500 keyboard-brightness "Keyboard backlight" "Off"
else
    osd keyboard-brightness "Keyboard backlight" "$level"
fi
