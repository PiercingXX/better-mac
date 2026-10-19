# shellcheck shell=bash
# GitHub.com/PiercingXX
# The piercing-dots Hyprland desktop, rebuilt from macOS parts:
#   Hyprland  -> AeroSpace        waybar   -> SketchyBar
#   borders   -> JankyBorders     ulauncher -> Sol
#   kb_options caps:backspace, Super tap -> Karabiner-Elements
#   touchpad gestures                   -> piercing-gestures (dots/gestures)

wm_install() {
    say "Installing the Hyprland-style desktop..."
    _wm_packages
    _wm_configs
    _wm_gestures
    _wm_piercing_dots
    _wm_defaults
    _wm_start
    _wm_permissions
    ok "Desktop installed. Log out and back in once so the menu bar and Spaces changes apply."
}

_wm_packages() {
    run brew tap FelixKratz/formulae
    brew_cask nikitabobko/tap/aerospace karabiner-elements sol \
        font-jetbrains-mono-nerd-font font-fira-sans
    brew_formula FelixKratz/formulae/sketchybar FelixKratz/formulae/borders \
        switchaudio-osx sshpass
}

_wm_configs() {
    local dots="$BETTER_MAC_ROOT/dots"
    install_file "$dots/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml"
    install_file "$dots/aerospace/KEYBINDS.md" "$HOME/.config/aerospace/KEYBINDS.md"
    install_dir  "$dots/sketchybar" "$HOME/.config/sketchybar"
    install_file "$dots/borders/bordersrc" "$HOME/.config/borders/bordersrc"
    install_file "$dots/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"
    if [ "$DRY_RUN" -eq 0 ]; then
        chmod +x "$HOME/.config/sketchybar/sketchybarrc" \
                 "$HOME/.config/sketchybar/plugins/"*.sh \
                 "$HOME/.config/borders/bordersrc"
    fi
    ok "AeroSpace, SketchyBar, borders and Karabiner configs in place."
}

# hyprland/keybinds.lua gestures: a small Swift helper built from source and
# run by launchd. Its ad-hoc signature carries a fixed designated requirement,
# so the Accessibility grant survives rebuilds; it only rebuilds when the
# source changes.
_wm_gestures() {
    local src="$BETTER_MAC_ROOT/dots/gestures" bin="$HOME/.local/bin/piercing-gestures"
    local agent="$HOME/Library/LaunchAgents/com.piercingxx.gestures.plist" sum
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "build piercing-gestures -> $bin, LaunchAgent com.piercingxx.gestures"
        return 0
    fi
    sum="$(shasum -a 256 "$src/piercing-gestures.swift" | cut -d' ' -f1)"
    if [ ! -x "$bin" ] || [ "$(cat "$bin.sha256" 2>/dev/null)" != "$sum" ]; then
        mkdir -p "$(dirname "$bin")"
        if swiftc -O -o "$bin" "$src/piercing-gestures.swift" \
            && codesign --force -s - --identifier com.piercingxx.gestures \
                -r='designated => identifier "com.piercingxx.gestures"' "$bin"; then
            printf '%s\n' "$sum" >"$bin.sha256"
        else
            warn "piercing-gestures did not build; touchpad gestures are off."
            return 0
        fi
    fi
    mkdir -p "$(dirname "$agent")"
    sed "s|@HOME@|$HOME|g" "$src/com.piercingxx.gestures.plist" >"$agent"
    launchctl bootout "gui/$(id -u)/com.piercingxx.gestures" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$agent" || warn "piercing-gestures did not start."
    ok "Touchpad gestures: 3 fingers left/right workspaces, up Sol, 4 fingers down close."
}

# Wallpapers (~/.scripts is modules/scripts.sh)
_wm_piercing_dots() {
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "piercing-dots backgrounds -> ~/Pictures/backgrounds, set wallpaper"
        return 0
    fi
    local wall
    ensure_piercing_dots || return 0
    mkdir -p "$HOME/Pictures/backgrounds"
    cp -R "$PIERCING_DOTS_DIR/resources/backgrounds/." "$HOME/Pictures/backgrounds/"

    # hyprpaper.conf wallpaper
    wall="$HOME/Pictures/backgrounds/1346578.jpg"
    if [ -f "$wall" ]; then
        osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$wall\"" >/dev/null 2>&1 \
            || warn "Wallpaper not set: allow your terminal to control System Events, then rerun."
    fi
    ok "Wallpapers copied."
}

_wm_defaults() {
    # SketchyBar replaces the menu bar; it still slides down at the top edge
    run defaults write NSGlobalDomain _HIHideMenuBar -bool true
    # Everything launches from keybinds/Sol: the Dock auto-hides with a
    # 1000s reveal delay, so the screen edge never brings it up
    run defaults write com.apple.dock autohide -bool true
    run defaults write com.apple.dock autohide-delay -float 1000
    run defaults write com.apple.dock show-recents -bool false
    # AeroSpace guide: group windows by app in Mission Control, and one Space
    # across all displays ("Displays have separate Spaces" off)
    run defaults write com.apple.dock expose-group-apps -bool true
    run defaults write com.apple.spaces spans-displays -bool true
    # ctrl+cmd+drag moves a window from anywhere in it
    run defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true
    # No zoom animation when windows open
    run defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
    # 3-finger swipes and 4-finger vertical swipes belong to piercing-gestures;
    # 4 fingers left/right still switch macOS Spaces and full-screen apps
    local trackpad key
    for trackpad in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
        for key in TrackpadThreeFingerHorizSwipeGesture TrackpadThreeFingerVertSwipeGesture \
                   TrackpadFourFingerVertSwipeGesture; do
            run defaults write "$trackpad" "$key" -int 0
        done
    done
    for key in threeFingerHorizSwipeGesture threeFingerVertSwipeGesture fourFingerVertSwipeGesture; do
        run defaults -currentHost write NSGlobalDomain "com.apple.trackpad.$key" -int 0
    done
    # Mission Control (swipe up) and App Exposé (swipe down) have their own
    # switches; the trackpad keys alone leave them on
    run defaults write com.apple.dock showMissionControlGestureEnabled -bool false
    run defaults write com.apple.dock showAppExposeGestureEnabled -bool false
    run killall Dock || true
    run killall SystemUIServer || true
    ok "Menu bar auto-hides, Dock stays hidden, Spaces span displays, ctrl+cmd+drag enabled, macOS swipes handed to piercing-gestures."
}

_wm_start() {
    run brew services restart sketchybar || warn "SketchyBar did not start."
    run brew services restart borders || warn "borders did not start."
    run open -a AeroSpace
    run open -a Karabiner-Elements
    run open -b com.ospfranco.sol
}

# macOS only lets a person grant these, so open each pane and wait
_wm_permissions() {
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "walk through Accessibility, Input Monitoring, Karabiner, Sol and keyboard settings"
        return 0
    fi
    say "A few switches only you can flip. Opening each settings pane:"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    wait_for_user "Accessibility: turn on AeroSpace, Sol and piercing-gestures."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    wait_for_user "Input Monitoring: turn on karabiner_grabber and karabiner_observer."
    wait_for_user "Karabiner-Elements window: allow its driver extension and login items if it asks."
    wait_for_user "Sol settings: hotkey Option-Space (tapping Option sends it), clipboard manager shortcut Option-Shift-Y, Launch at login on."
    open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
    wait_for_user "Keyboard > Text Input > Edit: add Colemak and Piercing Num (under Others), remove U.S. Switch with Ctrl-Space or Globe."
}
