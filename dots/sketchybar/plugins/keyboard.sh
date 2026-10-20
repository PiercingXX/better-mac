#!/bin/bash
# GitHub.com/PiercingXX
# Hyprland binds follow the letters of the active layout (keysyms). Rift does
# the same on its own; AeroSpace (the fallback WM) binds physical keys, so on
# every input-source change this swaps AeroSpace's key map to match and
# reloads it, and shows the layout in the bar (waybar's #language).

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
TOML="$HOME/.config/aerospace/aerospace.toml"

# The notification can arrive a moment before the new source is readable
[ "$SENDER" = "input_change" ] && sleep 0.3

source_id="$(defaults read com.apple.HIToolbox AppleCurrentKeyboardLayoutInputSourceID 2>/dev/null)"
case "$source_id" in
    *[Pp]iercing*)
        label="PRC"
        # From piercing-num.keylayout: letter -> the QWERTY key it sits on
        block="key-mapping.preset = 'qwerty'
key-mapping.key-notation-to-key-code = { b = 'comma', c = 'x', comma = 'z', d = 'g', e = 'd', f = 'e', g = 't', i = 'l', j = 'period', k = 'n', l = 'u', n = 'j', o = 'semicolon', p = 'i', period = 'slash', r = 'w', semicolon = 'y', slash = 'b', t = 'f', u = 'k', w = 'r', x = 'c', y = 'o', z = 'p' }"
        ;;
    *[Cc]olemak*)
        label="CMK"
        block="key-mapping.preset = 'colemak'"
        ;;
    *)
        label="QWE"
        block="key-mapping.preset = 'qwerty'"
        ;;
esac

if [ -f "$TOML" ]; then
    tmp="$(mktemp)"
    BLOCK="$block" awk '
        /^# >>> keyboard layout/ { print; print ENVIRON["BLOCK"]; skip = 1; next }
        /^# <<< keyboard layout/ { skip = 0 }
        !skip { print }
    ' "$TOML" >"$tmp"
    if ! cmp -s "$tmp" "$TOML"; then
        # Write in place so AeroSpace's file watcher keeps the same inode
        cat "$tmp" >"$TOML"
        aerospace reload-config >/dev/null 2>&1
    fi
    rm -f "$tmp"
fi

[ -n "$NAME" ] && sketchybar --set "$NAME" label="$label"
