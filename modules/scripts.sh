# shellcheck shell=bash
# GitHub.com/PiercingXX
# ~/.scripts on macOS: better-mac's own copy in dots/scripts/, ported from
# piercing-dots resources/.scripts. Nothing is taken from piercing-dots here.
# Linux-only scripts aren't carried over: the session launchers (start-*,
# start-wm, start-session.sh, wm-logout-to-tty.sh), the launcher/clipboard/
# emoji menus and touchpad toggle (Sol and macOS cover them), the
# volume/brightness OSDs and workspace-notify (native HUD, SketchyBar),
# skippy-desk (GTK), keybinds.html (~/.config/aerospace/KEYBINDS.md) and
# update-mirrors.sh (Arch). Also links /media -> /Volumes so the hardcoded
# /media/Archived-Storage/... paths (notes, inventory, nvim todo) keep working.

scripts_install() {
    say "Installing ~/.scripts..."
    _scripts_tree
    _scripts_media_link
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
