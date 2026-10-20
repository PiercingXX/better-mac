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
    _system_desktop
    _system_screenshots
    _system_notifications
    _system_stock_apps
    _system_night_shift
    _system_services
    # set_boot_beep.sh: the startup chime (Apple Silicon mutes it by default)
    run sudo nvram StartupMute=%00 || warn "Could not turn on the startup chime."
    run killall Dock || true
    run killall SystemUIServer || true
    run killall Finder || true
    run killall WindowManager || true
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
        || warn "Reduce Motion not set (needs Full Disk Access); turn it on under Accessibility > Motion."
    # Instant window resizes, and no giant cursor when the mouse is shaken
    run defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
    run defaults write NSGlobalDomain CGDisableCursorLocationMagnification -bool true
    # Monochrome like the GNOME/Hyprland theme: Graphite accent and highlight
    # instead of macOS blue
    run defaults write NSGlobalDomain AppleAccentColor -int -1
    run defaults write NSGlobalDomain AppleHighlightColor -string "0.847059 0.847059 0.862745 Graphite"
    # Like a Linux login: start clean, don't reopen apps and windows from last time
    run defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool false
    run defaults write com.apple.loginwindow TALLogoutSavesState -bool false
    run defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool false
}

_system_input() {
    # touchpad tap-to-click, natural-scroll (two-finger right click is the default)
    run defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
    run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
    run defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
    run defaults write NSGlobalDomain com.apple.swipescrolldirection -bool true
    # mouse accel-profile flat ("Pointer acceleration" off)
    run defaults write NSGlobalDomain com.apple.mouse.linear -bool true
    # Held keys repeat, like Linux, instead of opening the accent picker; a
    # fast rate (30ms) after a short delay (225ms). Applies after logging out.
    run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
    run defaults write NSGlobalDomain KeyRepeat -int 2
    run defaults write NSGlobalDomain InitialKeyRepeat -int 15
}

_system_power() {
    # sleep-inactive-ac-timeout 3600, battery 1800, idle-delay 900, idle-dim false
    run sudo pmset -c sleep 60 displaysleep 15
    run sudo pmset -b sleep 30 displaysleep 15
    run sudo pmset -a halfdim 0
    _system_shutdown_sudo
}

# Ctrl ⌘ ⇧ K / Backspace shut down at once, like systemctl poweroff: let this
# user run `shutdown -h now` without a password (nothing else)
_system_shutdown_sudo() {
    local rule="/etc/sudoers.d/piercingxx-shutdown" tmp
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "sudoers: $USER may run /sbin/shutdown -h now without a password"
        return 0
    fi
    tmp="$(mktemp)"
    printf '%s ALL=(root) NOPASSWD: /sbin/shutdown -h now\n' "$USER" >"$tmp"
    if sudo visudo -cqf "$tmp" && sudo install -m 0440 -o root -g wheel "$tmp" "$rule"; then
        ok "Shutdown keybind runs without a password."
    else
        warn "Could not add $rule; the shutdown keybind will ask for a password."
    fi
    rm -f "$tmp"
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
    # GNOME favorite-apps minus VS Code. Finder (Nautilus) is always first.
    run dockutil --remove all --no-restart
    local app
    for app in /Applications/Waterfox.app /Applications/LibreOffice.app \
               /System/Applications/Calculator.app /Applications/Obsidian.app \
               "/Applications/Synology Chat.app"; do
        if [ "$DRY_RUN" -eq 1 ] || [ -d "$app" ]; then
            run dockutil --add "$app" --no-restart
        fi
    done
}

# ⌘⇧3/4/5 save where wm-screenshot.sh does (⌥E), without window shadows
_system_screenshots() {
    run mkdir -p "$HOME/Pictures/Screenshots"
    run defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"
    run defaults write com.apple.screencapture disable-shadow -bool true
}

# Every macOS notification off: the ~/.scripts notifiers show their own
# popups (piercing-notify, modules/wm.sh), like mako on Linux. macOS 26 keeps
# the per-app switches in usernoted's group container, readable only with
# Full Disk Access; bit 25 of each app's flags is "Allow notifications".
# Only apps that have already asked to notify are listed there, so apps
# installed later start allowed until this runs again.
_system_notifications() {
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "every macOS notification off"
        return 0
    fi
    # The bare domain name resolves to an empty plist outside the container
    local domain="$HOME/Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted"
    local stage
    stage="$(mktemp)"
    if ! defaults export "$domain" "$stage" 2>/dev/null \
        || ! /usr/bin/python3 -I - "$stage" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as f:
    d = plistlib.load(f)
if not d.get('apps'):
    sys.exit(1)
for app in d.get('apps', []):
    app['flags'] = app.get('flags', 0) & ~(1 << 25)
with open(path, 'wb') as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
PY
    then
        rm -f "$stage"
        warn "Notifications not changed (Terminal needs Full Disk Access); use System Settings > Notifications."
        return 0
    fi
    defaults import "$domain" "$stage"
    rm -f "$stage"
    killall usernoted NotificationCenter 2>/dev/null || true
    ok "Every macOS notification off (the scripts use piercing-notify)."
}

_system_desktop() {
    # Clean desktop: no icons (drives included) and no widgets. The drives
    # still show in the Finder sidebar.
    run defaults write com.apple.finder CreateDesktop -bool false
    run defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
    run defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
    run defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool false
    run defaults write com.apple.finder ShowMountedServersOnDesktop -bool false
    run defaults write com.apple.WindowManager StandardHideWidgets -int 1
    run defaults write com.apple.WindowManager StageManagerHideWidgets -int 1
}

# Apple's optional apps and GarageBand's sound library. Matched by bundle id
# because the names change (Keynote is "Keynote Creator Studio" on macOS 26).
# The apps in /System/Applications are on the sealed system volume and can't
# be removed.
_system_stock_apps() {
    local app id
    for app in /Applications/*.app; do
        id="$(defaults read "$app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)" || continue
        case "$id" in
            com.apple.garageband10|com.apple.iMovieApp|com.apple.Keynote|com.apple.Numbers|com.apple.Pages)
                run sudo rm -rf "$app" ;;
        esac
    done
    # Logic Pro shares these; keep them if it's installed
    if [ ! -d "/Applications/Logic Pro.app" ]; then
        run sudo rm -rf "/Library/Application Support/GarageBand" \
                        "/Library/Application Support/Logic" \
                        "/Library/Audio/Apple Loops"
    fi
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
