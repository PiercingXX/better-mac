#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Toggle the top bar (⌥R).
# --startup restores the last on/off state at login.
# macOS port (better-mac): the bar is SketchyBar, run by brew services, so
# "off" means `--bar hidden=on` instead of killing the process. waybar,
# polybar and the per-session bar memory are dropped (one bar, one session).
# SketchyBar sits in the notch strip, which macOS keeps windows out of either
# way, so AeroSpace's top gap stays 5 with or without it.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/topbar/state"
TOML="$HOME/.config/aerospace/aerospace.toml"
GAP_WITH_BAR="${TOPBAR_GAP_ON:-5}"
GAP_WITHOUT_BAR="${TOPBAR_GAP_OFF:-5}"

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

# wait_for_bar <seconds>: SketchyBar may still be starting (login, restart)
wait_for_bar() {
    local i
    for ((i = 0; i < $1; i++)); do
        [ -n "$(bar_hidden)" ] && return 0
        sleep 1
    done
    [ -n "$(bar_hidden)" ]
}

# start_bar: SketchyBar isn't running at all (upstream starts waybar/polybar)
start_bar() {
    command -v sketchybar >/dev/null 2>&1 || return 1
    if command -v brew >/dev/null 2>&1; then
        brew services restart sketchybar >"$STATE_DIR/topbar/sketchybar.log" 2>&1
    else
        nohup sketchybar >"$STATE_DIR/topbar/sketchybar.log" 2>&1 &
    fi
    wait_for_bar 10
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

startup_mode=false
if [ "${1:-}" = "--startup" ]; then
    startup_mode=true
fi

read_state

if [ "$startup_mode" = true ]; then
    if ! wait_for_bar 10; then
        [ "$LAST_ENABLED" = "off" ] && exit 0
        start_bar || exit 0
    fi
    if [ "$LAST_ENABLED" = "off" ]; then
        hide_bar
    else
        show_bar
    fi
    exit 0
fi

current="$(bar_hidden)"

# Nothing running: start it shown, like upstream starting a bar
if [ -z "$current" ]; then
    start_bar && show_bar
    exit 0
fi

if [ "$current" = "on" ]; then
    show_bar
else
    hide_bar
fi
