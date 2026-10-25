# shellcheck shell=bash
# GitHub.com/PiercingXX
# Colemak (built into macOS) + Piercing Num from
# github.com/PiercingXX/piercing-keyboard-layout:
#   - piercing-num.keylayout -> ~/Library/Keyboard Layouts
#   - Caps=Backspace, Backspace=Delete (every layout) and the AltGr arrows are
#     Karabiner rules (dots/karabiner) instead of the repo's hidutil agent:
#     hidutil can't tell layouts apart and would stack on Karabiner's remaps.
#   - AeroSpace binds follow the active layout (sketchybar/plugins/keyboard.sh)
#   - Ctrl-Space is freed for the tmux prefix (same as on Arch); Globe and
#     Ctrl-Option-Space still switch layouts

PIERCING_KEYBOARD_REPO="https://github.com/PiercingXX/piercing-keyboard-layout.git"

keyboard_install() {
    say "Installing the Piercing Num layout..."
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "piercing-num.keylayout -> ~/Library/Keyboard Layouts/"
        dry "remove any hidutil keyremap LaunchAgents (Karabiner owns those keys)"
        dry "turn off Ctrl-Space 'Select the previous input source' (tmux prefix)"
        return 0
    fi

    # Symbolic hotkey 60 = Select the previous input source (Ctrl-Space)
    defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 60 \
        '<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>262144</integer></array><key>type</key><string>standard</string></dict></dict>'
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
    ok "Ctrl-Space freed for the tmux prefix."

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

    # Any hidutil remap agent (ours was com.piercingxx.keyremap; hand-made ones
    # like com.local.capslock-backspace too) would stack on Karabiner's remaps
    local agent removed=0
    for agent in "$HOME"/Library/LaunchAgents/*.plist; do
        [ -f "$agent" ] || continue
        grep -q '/usr/bin/hidutil' "$agent" && grep -q 'UserKeyMapping' "$agent" || continue
        launchctl unload "$agent" 2>/dev/null || true
        rm -f "$agent"
        ok "Removed hidutil keyremap agent $(basename "$agent")."
        removed=1
    done
    if [ "$removed" -eq 1 ]; then
        hidutil property --set '{"UserKeyMapping":[]}' >/dev/null 2>&1 || true
        ok "Karabiner handles those keys per layout now."
    fi
    ok "Piercing Num installed."
}
