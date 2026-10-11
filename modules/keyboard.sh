# shellcheck shell=bash
# GitHub.com/PiercingXX
# Colemak (built into macOS) + Piercing Num from
# github.com/PiercingXX/piercing-keyboard-layout:
#   - piercing-num.keylayout -> ~/Library/Keyboard Layouts
#   - Caps=Backspace, Backspace=Delete (Piercing only) and the AltGr arrows are
#     Karabiner rules (dots/karabiner) instead of the repo's hidutil agent:
#     hidutil can't tell layouts apart and would stack on Karabiner's remaps.
#   - AeroSpace binds follow the active layout (sketchybar/plugins/keyboard.sh)

PIERCING_KEYBOARD_REPO="https://github.com/PiercingXX/piercing-keyboard-layout.git"

keyboard_install() {
    say "Installing the Piercing Num layout..."
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "piercing-num.keylayout -> ~/Library/Keyboard Layouts/"
        dry "remove the hidutil keyremap LaunchAgent if present (Karabiner owns those keys)"
        return 0
    fi

    local src="${PIERCING_KEYBOARD_DIR:-}" tmp=""
    if [ -z "$src" ]; then
        tmp="$(mktemp -d)"
        if ! git clone --depth 1 -q "$PIERCING_KEYBOARD_REPO" "$tmp/kb"; then
            warn "Could not clone piercing-keyboard-layout; Piercing Num not installed."
            rm -rf "$tmp"
            return 0
        fi
        src="$tmp/kb"
    fi
    install_file "$src/piercing-num/macos/piercing-num.keylayout" \
        "$HOME/Library/Keyboard Layouts/piercing-num.keylayout"
    [ -n "$tmp" ] && rm -rf "$tmp"

    local agent="$HOME/Library/LaunchAgents/com.piercingxx.keyremap.plist"
    if [ -f "$agent" ]; then
        launchctl unload "$agent" 2>/dev/null || true
        rm -f "$agent"
        hidutil property --set '{"UserKeyMapping":[]}' >/dev/null 2>&1 || true
        ok "Removed the hidutil keyremap agent; Karabiner handles those keys per layout now."
    fi
    ok "Piercing Num installed."
}
