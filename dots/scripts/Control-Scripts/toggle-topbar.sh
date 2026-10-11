#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Toggle the top bar (⌥R). macOS port: the bar is SketchyBar, and AeroSpace's
# top gap follows it (44 with the bar, 10 without) so windows reclaim the space.
# The on/off choice survives logins:
#   toggle-topbar.sh            toggle and remember
#   toggle-topbar.sh --startup  re-apply the remembered state at login

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/topbar/state"
TOML="$HOME/.config/aerospace/aerospace.toml"
GAP_WITH_BAR="${TOPBAR_GAP_ON:-44}"
GAP_WITHOUT_BAR="${TOPBAR_GAP_OFF:-10}"

mkdir -p "$STATE_DIR/topbar"

read_state() {
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$STATE_FILE"
    fi
    LAST_ENABLED="${LAST_ENABLED:-on}"
}

write_state() {
    printf 'LAST_ENABLED=%s\n' "$1" >"$STATE_FILE"
}

# bar_hidden: prints on/off, or nothing if SketchyBar isn't answering
bar_hidden() {
    sketchybar --query bar 2>/dev/null | sed -n 's/.*"hidden"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' | head -n1
}

# set_gap <n>: rewrite a plain `gaps.outer.top = N` line and reload AeroSpace.
# A per-monitor gap list is left alone.
set_gap() {
    local gap="$1" tmp
    [ -f "$TOML" ] || return 0
    grep -qE '^gaps\.outer\.top = [0-9]+[[:space:]]*$' "$TOML" || return 0
    tmp="$(mktemp)"
    sed -E "s/^gaps\.outer\.top = [0-9]+[[:space:]]*$/gaps.outer.top = $gap/" "$TOML" >"$tmp"
    if ! cmp -s "$tmp" "$TOML"; then
        cat "$tmp" >"$TOML"    # keep the inode for AeroSpace's file watcher
        aerospace reload-config >/dev/null 2>&1 || true
    fi
    rm -f "$tmp"
}

show_bar() {
    sketchybar --bar hidden=off >/dev/null 2>&1
    set_gap "$GAP_WITH_BAR"
    write_state on
}

hide_bar() {
    sketchybar --bar hidden=on >/dev/null 2>&1
    set_gap "$GAP_WITHOUT_BAR"
    write_state off
}

read_state

if [ "${1:-}" = "--startup" ]; then
    # SketchyBar may still be starting at login
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -n "$(bar_hidden)" ] && break
        sleep 1
    done
    if [ "$LAST_ENABLED" = "off" ]; then
        hide_bar
    else
        show_bar
    fi
    exit 0
fi

if [ "$(bar_hidden)" = "on" ]; then
    show_bar
else
    hide_bar
fi
