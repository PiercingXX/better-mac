# shellcheck shell=bash
# GitHub.com/PiercingXX
# The piercing-dots Hyprland desktop, rebuilt from macOS parts:
#   Hyprland  -> AeroSpace        waybar   -> SketchyBar
#   borders   -> JankyBorders     ulauncher -> Raycast
#   kb_options caps:backspace, Super tap -> Karabiner-Elements

wm_install() {
    say "Installing the Hyprland-style desktop..."
    _wm_packages
    _wm_configs
    _wm_piercing_dots
    _wm_defaults
    _wm_start
    _wm_permissions
    ok "Desktop installed. Log out and back in once so the menu bar and Spaces changes apply."
}

_wm_packages() {
    run brew tap FelixKratz/formulae
    brew_cask nikitabobko/tap/aerospace karabiner-elements raycast \
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

# ~/.scripts (notes, server monitor, AI launchers) and wallpapers
_wm_piercing_dots() {
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "clone piercing-dots: ~/.scripts, ~/Pictures/backgrounds, set wallpaper"
        return 0
    fi
    local wall
    ensure_piercing_dots || return 0
    mkdir -p "$HOME/.scripts" "$HOME/Pictures/backgrounds"
    cp -R "$PIERCING_DOTS_DIR/resources/.scripts/." "$HOME/.scripts/"
    chmod -R u+x "$HOME/.scripts"
    cp -R "$PIERCING_DOTS_DIR/resources/backgrounds/." "$HOME/Pictures/backgrounds/"

    # hyprpaper.conf wallpaper
    wall="$HOME/Pictures/backgrounds/1346578.jpg"
    if [ -f "$wall" ]; then
        osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$wall\"" >/dev/null 2>&1 \
            || warn "Wallpaper not set: allow your terminal to control System Events, then rerun."
    fi
    ok "piercing-dots scripts and wallpapers copied."
}

_wm_defaults() {
    # SketchyBar replaces the menu bar; it still slides down at the top edge
    run defaults write NSGlobalDomain _HIHideMenuBar -bool true
    run defaults write com.apple.dock autohide -bool true
    run defaults write com.apple.dock autohide-delay -float 0
    # AeroSpace guide: group windows by app in Mission Control, and one Space
    # across all displays ("Displays have separate Spaces" off)
    run defaults write com.apple.dock expose-group-apps -bool true
    run defaults write com.apple.spaces spans-displays -bool true
    # ctrl+cmd+drag moves a window from anywhere in it
    run defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true
    # No zoom animation when windows open
    run defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
    run killall Dock || true
    run killall SystemUIServer || true
    ok "Menu bar and Dock auto-hide, Spaces span displays, ctrl+cmd+drag enabled."
}

_wm_start() {
    run brew services restart sketchybar || warn "SketchyBar did not start."
    run brew services restart borders || warn "borders did not start."
    run open -a AeroSpace
    run open -a Karabiner-Elements
    run open -a Raycast
}

# macOS only lets a person grant these, so open each pane and wait
_wm_permissions() {
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "walk through Accessibility, Input Monitoring, Karabiner, Raycast and keyboard settings"
        return 0
    fi
    say "A few switches only you can flip. Opening each settings pane:"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    wait_for_user "Accessibility: turn on AeroSpace and Raycast."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    wait_for_user "Input Monitoring: turn on karabiner_grabber and karabiner_observer."
    wait_for_user "Karabiner-Elements window: allow its driver extension and login items if it asks."
    wait_for_user "Raycast welcome window: set the Raycast hotkey to Option-Space (tapping left Option sends it)."
    open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
    wait_for_user "Keyboard > Text Input > Edit: add Colemak and Piercing Num (under Others), remove U.S. Switch with Ctrl-Space or Globe."
}
