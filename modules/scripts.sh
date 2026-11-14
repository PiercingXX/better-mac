# shellcheck shell=bash
# GitHub.com/PiercingXX
# ~/.scripts on macOS: better-mac's own copy in dots/scripts/, ported from
# piercing-dots resources/.scripts. Nothing is taken from piercing-dots here.
# Linux-only scripts aren't carried over: the session launchers (start-*,
# start-wm, start-session.sh, wm-logout-to-tty.sh), the launcher/clipboard/
# emoji menus and touchpad toggle (piercing-launcher and macOS cover them), the
# volume/brightness OSDs and workspace-notify (native HUD, SketchyBar),
# skippy-desk (GTK), keybinds.html (~/.config/aerospace/KEYBINDS.md) and
# update-mirrors.sh (Arch). Also links /media -> /Volumes so the hardcoded
# /media/Archived-Storage/... paths (notes, inventory, nvim todo) keep working,
# and runs setup-claude-accounts.sh / setup-grok-accounts.sh for the
# claude1..claude6 and grok1..grok4 commands.

scripts_install() {
    say "Installing ~/.scripts..."
    _scripts_tree
    _scripts_media_link
    _scripts_ai_accounts claude 6 'auth login'
    _scripts_ai_accounts grok 4 login
}

_scripts_tree() {
    local src="$BETTER_MAC_ROOT/dots/scripts" stage
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "dots/scripts/ -> ~/.scripts/"
        return 0
    fi
    stage="$(mktemp -d)"
    cp -R "$src/." "$stage/"
    chmod -R u+x "$stage"
    install_dir "$stage" "$HOME/.scripts"
    rm -rf "$stage"
    ok "~/.scripts installed."
}

# /media -> /Volumes via /etc/synthetic.conf (the root volume is read-only;
# macOS creates the link at boot). An SMB share named Archived-Storage then
# shows up at /media/Archived-Storage, same as on Linux.
_scripts_media_link() {
    if [ -e /media ] || grep -q '^media	' /etc/synthetic.conf 2>/dev/null; then
        return 0
    fi
    run sudo sh -c "printf 'media\tVolumes\n' >> /etc/synthetic.conf" \
        || { warn "Could not write /etc/synthetic.conf; /media paths won't resolve."; return 0; }
    ok "/media -> /Volumes after the next reboot."
}

# claude1..claude6 + claude-status and grok1..grok4 + grok-status
# (Useful-Scripts/setup-{claude,grok}-accounts.sh): each installs its CLI if
# it's missing, the wrappers in ~/.local/bin, and the account dirs linked to
# the shared ~/.claude or ~/.grok store. Signing in stays manual.
_scripts_ai_accounts() {
    local tool="$1" last="$2" login="$3"
    local setup="$HOME/.scripts/Useful-Scripts/setup-$tool-accounts.sh"
    local log="$HOME/.config/$tool/setup.log"
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "setup-$tool-accounts.sh setup -> ${tool}1..$tool$last, $tool-status"
        return 0
    fi
    mkdir -p "$HOME/.config/$tool"
    if bash "$setup" setup >"$log" 2>&1; then
        ok "${tool}1..$tool$last ready. Sign in: $tool $login, ${tool}2 $login, ... (check with $tool-status)"
    else
        warn "$tool account setup failed; see $log, then rerun: bash $setup"
    fi
}
