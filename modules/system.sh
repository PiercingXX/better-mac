# shellcheck shell=bash
# GitHub.com/PiercingXX
# piercing-dots gnome-customizations.sh translated to macOS settings, plus the
# services step-1.sh turns on (ufw -> firewall, sshd -> Remote Login).

system_install() {
    say "Applying macOS settings..."
    brew_formula dockutil smudge/smudge/nightlight
    _system_appearance
    _system_input
    _system_power
    _system_finder_dock
    _system_night_shift
    _system_services
    run killall Dock || true
    run killall SystemUIServer || true
    ok "macOS settings applied (some take effect after you log out)."
}

_system_appearance() {
    # color-scheme prefer-dark, clock-format 24h, clock-show-weekday,
    # show-battery-percentage
    run defaults write NSGlobalDomain AppleInterfaceStyle -string Dark
    run defaults write NSGlobalDomain AppleICUForce24HourTime -bool true
    run defaults write com.apple.menuextra.clock ShowDayOfWeek -bool true
    run defaults -currentHost write com.apple.controlcenter BatteryShowPercentage -bool true
    # enable-animations false
    run defaults write com.apple.dock launchanim -bool false
    run defaults write com.apple.dock expose-animation-duration -float 0.1
    run defaults write com.apple.universalaccess reduceMotion -bool true \
        || warn "Reduce Motion not set (needs Full Disk Access); turn it on under Accessibility > Display."
}

_system_input() {
    # touchpad tap-to-click, natural-scroll (two-finger right click is the default)
    run defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
    run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
    run defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
    run defaults write NSGlobalDomain com.apple.swipescrolldirection -bool true
    # mouse accel-profile flat ("Pointer acceleration" off)
    run defaults write NSGlobalDomain com.apple.mouse.linear -bool true
}

_system_power() {
    # sleep-inactive-ac-timeout 3600, battery 1800, idle-delay 900, idle-dim false
    run sudo pmset -c sleep 60 displaysleep 15
    run sudo pmset -b sleep 30 displaysleep 15
    run sudo pmset -a halfdim 0
}

_system_finder_dock() {
    # remove-old-trash-files (macOS only offers 30 days, not 1)
    run defaults write com.apple.finder FXRemoveOldTrashItems -bool true
    # enable-hot-corners false
    local corner
    for corner in tl tr bl br; do
        run defaults write com.apple.dock "wvous-$corner-corner" -int 0
        run defaults write com.apple.dock "wvous-$corner-modifier" -int 0
    done
    # favorite-apps (Finder is always first)
    run dockutil --remove all --no-restart
    local app
    for app in /Applications/Waterfox.app /Applications/Obsidian.app; do
        if [ "$DRY_RUN" -eq 1 ] || [ -d "$app" ]; then
            run dockutil --add "$app" --no-restart
        fi
    done
}

_system_night_shift() {
    # night-light 20:00-04:00 at 2300K (nightlight's warmest setting is 100)
    run nightlight schedule 20:00 4:00 || warn "Night Shift schedule not set; use Displays > Night Shift."
    run nightlight temp 100 || true
}

_system_services() {
    # ufw: the macOS application firewall
    run sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
    # sshd: Remote Login
    run sudo systemsetup -setremotelogin on \
        || warn "Remote Login not enabled (systemsetup needs Full Disk Access); use General > Sharing."
}
