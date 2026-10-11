# shellcheck shell=bash
# GitHub.com/PiercingXX
# ~/.scripts on macOS: piercing-dots resources/.scripts, minus the files in
# dots/scripts/macos-drop.txt, with the macOS ports in dots/scripts/ laid on
# top at the same paths. Also links /media -> /Volumes so the hardcoded
# /media/Archived-Storage/... paths (notes, inventory, nvim todo) keep working.

scripts_install() {
    say "Installing ~/.scripts..."
    _scripts_tree
    _scripts_media_link
}

_scripts_tree() {
    local ports="$BETTER_MAC_ROOT/dots/scripts"
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "piercing-dots .scripts - macos-drop.txt + dots/scripts/ ports -> ~/.scripts/"
        return 0
    fi
    ensure_piercing_dots || return 0

    local stage line
    stage="$(mktemp -d)"
    cp -R "$PIERCING_DOTS_DIR/resources/.scripts/." "$stage/"
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        rm -f "$stage/$line"
    done <"$ports/macos-drop.txt"
    (cd "$ports" && find . -type f ! -name macos-drop.txt -print) | while IFS= read -r line; do
        mkdir -p "$stage/$(dirname "$line")"
        cp "$ports/$line" "$stage/$line"
    done
    chmod -R u+x "$stage"
    install_dir "$stage" "$HOME/.scripts"
    rm -rf "$stage"
    ok "~/.scripts installed (macOS ports applied, Linux-only scripts left out)."
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
