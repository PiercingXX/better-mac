# shellcheck shell=bash
# GitHub.com/PiercingXX
# The rest of step-1.sh's apps, their piercing-dots configs, and the git
# commit-msg hook.

apps_install() {
    say "Installing apps and their configs..."
    _apps_packages
    apps_unquarantine
    _apps_login_items
    _apps_configs
    _apps_git_hook
}

_apps_packages() {
    # Apps the AeroSpace keybinds launch (also the Dock favorites)
    brew_cask waterfox discord obsidian gimp visual-studio-code opencode-desktop
    # flatpaks/AUR from step-1.sh and linux-mod: LibreOffice, qBittorrent,
    # GitHub Desktop, ProtonVPN, Synology Drive + Chat, Tailscale;
    # ttf-nerd-fonts-symbols
    brew_cask libreoffice qbittorrent github protonvpn synology-drive synology-chat \
        tailscale-app font-symbols-only-nerd-font
    # nvtop doesn't support Apple GPUs; macmon shows GPU/CPU/power instead
    brew_formula htop btop lnav macmon mpv ranger cava
    # ~/.scripts: settings menu (gum), Bluetooth, virus scan, backups
    brew_formula gum blueutil clamav rsync
}

# No "is an app downloaded from the Internet" prompt: drop the quarantine tag
# browsers and Homebrew put on downloads. XProtect and notarization checks
# still run. wm_install calls this again after its own casks.
apps_unquarantine() {
    local app n=0 opened=0
    for app in /Applications/*.app "$HOME"/Applications/*.app; do
        [ -d "$app" ] || continue
        xattr -p com.apple.quarantine "$app" >/dev/null 2>&1 || continue
        # An app that has already run is guarded by App Management (sudo
        # doesn't get past it), but it has also had its one prompt already
        if run xattr -dr com.apple.quarantine "$app" 2>/dev/null; then
            n=$((n + 1))
        else
            opened=$((opened + 1))
        fi
    done
    ok "No downloaded-from-the-Internet prompts ($n apps cleared, $opened already opened before)."
}

# Apps that should be running after every login (Tailscale keeps the tailnet
# up). Login items show under General > Login Items & Extensions.
_apps_login_items() {
    login_item /Applications/Tailscale.app
    [ "$DRY_RUN" -eq 1 ] || open /Applications/Tailscale.app 2>/dev/null || true
    ok "Tailscale opens at login."
}

_apps_configs() {
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "overlay piercing-dots btop, htop, mpv, ranger, ncmpcpp, opencode, cava, ollama -> ~/.config/"
        dry "overlay mpd (audio output pulse -> osx) -> ~/.config/mpd/"
        dry "overlay GIMP 3.2 -> ~/Library/Application Support/GIMP/3.2/"
        return 0
    fi
    ensure_piercing_dots || return 0
    local dots="$PIERCING_DOTS_DIR/dots" app stage
    for app in btop htop mpv ranger ncmpcpp opencode cava ollama; do
        [ -d "$dots/$app" ] || { warn "piercing-dots has no $app config; skipped."; continue; }
        overlay_dir "$dots/$app" "$HOME/.config/$app"
    done

    # mpd: CoreAudio instead of PulseAudio
    stage="$(mktemp -d)"
    cp -R "$dots/mpd/." "$stage/"
    sed 's/type "pulse"/type "osx"/' "$dots/mpd/mpd.conf" >"$stage/mpd.conf"
    overlay_dir "$stage" "$HOME/.config/mpd"
    rm -rf "$stage"

    # GIMP keeps its profile under Application Support on macOS
    overlay_dir "$dots/GIMP/3.2" "$HOME/Library/Application Support/GIMP/3.2"
    ok "btop, htop, mpv, ranger, ncmpcpp, mpd, opencode, cava, ollama and GIMP configs in place."
}

# Strips AI-vendor Co-authored-by trailers (piercing-dots .githooks/commit-msg)
_apps_git_hook() {
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "install the piercing-dots commit-msg hook (pointed at GNU sed)"
        return 0
    fi
    ensure_piercing_dots || return 0
    local hook="$PIERCING_DOTS_DIR/.githooks/commit-msg"
    local gsed="${HOMEBREW_PREFIX:-/opt/homebrew}/bin/gsed" stage
    # The hook needs GNU sed (-i with no suffix, the I flag), and git runs hooks
    # from GUI apps without the GNU PATH, so point it at gsed directly
    stage="$(mktemp)"
    sed "s|^sed -i -E|\"$gsed\" -i -E|" "$hook" >"$stage" && cat "$stage" >"$hook"
    rm -f "$stage"
    # The installer looks up HOME with getent, which macOS lacks; we never run as
    # root, so $HOME is already the right home
    local installer="$PIERCING_DOTS_DIR/scripts/install-git-vendor-trailer-hook.sh"
    stage="$(mktemp)"
    sed 's|^home_dir="\$(getent .*|home_dir="$HOME"|' "$installer" >"$stage" && cat "$stage" >"$installer"
    rm -f "$stage"
    if (cd "$PIERCING_DOTS_DIR/scripts" && bash ./install-git-vendor-trailer-hook.sh >/dev/null); then
        ok "Git commit-msg hook installed (new clones and ~/GitHub repos)."
    else
        warn "Git commit-msg hook install failed."
    fi
}
