#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Re-apply the PiercingXX rice from the latest piercing-dots on GitHub.
# Clones into a private temp dir, shows what would change, backs up the
# current configs, then runs the repo's install.sh.
# macOS port (better-mac): "Everything" pulls the better-mac checkout and
# reruns better-mac.sh on the fresh clone instead of install.sh; the preview
# compares what better-mac copies as-is (~/.scripts is an exact copy of
# better-mac's dots/scripts, nothing from piercing-dots). No Hyprland, so "without Hyprland
# configs" is gone; GNOME Customizations become better-mac's macOS settings;
# GIMP lives under ~/Library/Application Support.

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

refuse_root

REPO_URL="https://github.com/Piercingxx/piercing-dots.git"
BACKUP_ROOT="$PX_STATE_DIR/backups"
KEEP_BACKUPS=5
GIMP_DIR="$HOME/Library/Application Support/GIMP"

WORK_DIR=""
CLONE_DIR=""
BETTER_MAC_ROOT=""

cleanup_clone() {
    [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    WORK_DIR=""
    CLONE_DIR=""
}
trap cleanup_clone EXIT

check_internet() {
    local url code
    for url in https://connectivitycheck.gstatic.com/generate_204 http://www.google.com/generate_204; do
        code=$(curl -4 -fsS --max-time 4 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)
        [ "$code" = 204 ] && return 0
    done
    # GitHub itself is what we actually need
    curl -fsS --max-time 6 -o /dev/null https://github.com 2>/dev/null && return 0
    return 1
}

ensure_gum() {
    command_exists gum && return 0
    say "gum not found. Installing..."
    detect_distro
    pkg_install gum >/dev/null 2>&1 && command_exists gum
}

# Where better-mac.sh was last run from (it records this on every run)
find_better_mac() {
    local root="" alt
    [ -f "$HOME/.config/better-mac/root" ] && root="$(head -n 1 "$HOME/.config/better-mac/root")"
    if [ -z "$root" ] || [ ! -x "$root/better-mac.sh" ]; then
        for alt in "$HOME/better-mac" "$HOME/GitHub/better-mac" "$PX_WORK_ROOT/GitHub/better-mac"; do
            if [ -x "$alt/better-mac.sh" ]; then
                root="$alt"
                break
            fi
        done
    fi
    [ -x "$root/better-mac.sh" ] || return 1
    printf '%s\n' "$root"
}

choose() {
    local header="$1"; shift
    if command_exists gum; then
        printf '%s\n' "$@" | gum choose --header "$header" --cursor.foreground 212 --selected.foreground 212
    else
        local opt
        PS3="$header > "
        select opt in "$@"; do
            [ -n "$opt" ] && { echo "$opt"; return 0; }
        done
    fi
}

# Fresh shallow clone into a private temp dir (never the caller's cwd)
clone_rice() {
    cleanup_clone
    WORK_DIR=$(mktemp -d) || return 1
    CLONE_DIR="$WORK_DIR/piercing-dots"
    say "Downloading piercing-dots..."
    if ! git clone --quiet --depth 1 "$REPO_URL" "$CLONE_DIR"; then
        err "Could not clone $REPO_URL"
        cleanup_clone
        return 1
    fi
}

# List files better-mac would add or change (checksum compare, no writes).
# kitty, yazi, tmux and .bashrc get macOS edits on install, so they're not
# compared here.
preview_changes() {
    local out app
    command_exists rsync || { warn "rsync not installed; skipping preview."; return 0; }
    out=$(
        {
            for app in nvim btop htop mpv ranger ncmpcpp opencode cava ollama; do
                [ -d "$CLONE_DIR/dots/$app" ] || continue
                rsync -rcn --itemize-changes "$CLONE_DIR/dots/$app/" "$HOME/.config/$app/" \
                    | awk -v p="~/.config/$app/" '$1 ~ /^>f/ {print p $2}'
            done
            for app in aerospace sketchybar borders karabiner; do
                rsync -rcn --itemize-changes --exclude KEYBINDS.html "$BETTER_MAC_ROOT/dots/$app/" "$HOME/.config/$app/" \
                    | awk -v p="~/.config/$app/" '$1 ~ /^>f/ {print p $2}'
            done
            # better-mac replaces ~/.scripts whole, so extra files go too
            rsync -rcn --delete --itemize-changes --exclude .DS_Store "$BETTER_MAC_ROOT/dots/scripts/" "$HOME/.scripts/" \
                | awk '$1 ~ /^>f/ {print "~/.scripts/" $2} $1 == "*deleting" && $2 !~ /\/$/ {print "~/.scripts/" $2 " (removed)"}'
            cmp -s "$CLONE_DIR/dots/starship.toml" "$HOME/.config/starship.toml" || echo "~/.config/starship.toml"
            cmp -s "$CLONE_DIR/dots/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc" \
                || echo "~/.config/fastfetch/config.jsonc"
        } 2>/dev/null
    )
    if [ -z "$out" ]; then
        ok "Your configs already match the latest rice."
        return 0
    fi
    say "$(printf '%s\n' "$out" | wc -l | tr -d ' ') file(s) will be added, overwritten or removed:"
    if command_exists gum && [ -t 1 ]; then
        printf '%s\n' "$out" | gum pager
    else
        printf '%s\n' "$out" | head -n 60
        [ "$(printf '%s\n' "$out" | wc -l)" -gt 60 ] && echo "..."
    fi
}

list_backups() {
    local d
    for d in "$BACKUP_ROOT"/rice-*/; do
        [ -d "$d" ] && basename "$d"
    done | sort -r
}

# Copy everything better-mac overwrites into a timestamped backup
backup_current() {
    local ts dest name path f
    ts=$(date +%Y%m%d-%H%M%S)
    dest="$BACKUP_ROOT/rice-$ts"
    mkdir -p "$dest/config"
    for path in "$CLONE_DIR"/dots/* "$BETTER_MAC_ROOT"/dots/*; do
        name=$(basename "$path")
        case "$name" in scripts|bash|tmux) continue ;; esac
        [ -e "$HOME/.config/$name" ] || continue
        [ -e "$dest/config/$name" ] && continue
        cp -a "$HOME/.config/$name" "$dest/config/" 2>/dev/null
    done
    [ -d "$HOME/.scripts" ] && cp -a "$HOME/.scripts" "$dest/scripts"
    [ -d "$GIMP_DIR" ] && cp -a "$GIMP_DIR" "$dest/GIMP"
    for f in .bashrc .bash_profile .tmux.conf; do
        [ -f "$HOME/$f" ] && cp -a "$HOME/$f" "$dest/"
    done
    ok "Backed up current configs to $dest"

    # Keep only the newest backups
    list_backups | tail -n +$((KEEP_BACKUPS + 1)) \
        | while read -r old; do rm -rf "${BACKUP_ROOT:?}/$old"; done
}

restore_backup() {
    local -a backups
    mapfile -t backups < <(list_backups)
    if [ ${#backups[@]} -eq 0 ]; then
        warn "No backups found in $BACKUP_ROOT"
        return 1
    fi
    local pick
    pick=$(choose "Restore which backup?" "${backups[@]}" "Cancel")
    [ -z "$pick" ] || [ "$pick" = "Cancel" ] && return 0
    local src="$BACKUP_ROOT/$pick"
    confirm "Restore $pick over your current ~/.config, ~/.scripts and dotfiles?" || return 0
    [ -d "$src/config" ] && cp -a "$src/config/." "$HOME/.config/"
    [ -d "$src/scripts" ] && cp -a "$src/scripts/." "$HOME/.scripts/"
    [ -d "$src/GIMP" ] && mkdir -p "$GIMP_DIR" && cp -a "$src/GIMP/." "$GIMP_DIR/"
    for f in .bashrc .bash_profile .tmux.conf; do
        [ -f "$src/$f" ] && cp -a "$src/$f" "$HOME/$f"
    done
    ok "Restored $pick."
}

# Pull better-mac so its ports match the piercing-dots being applied
update_better_mac() {
    say "Updating better-mac in $BETTER_MAC_ROOT..."
    git -C "$BETTER_MAC_ROOT" pull --ff-only && return 0
    warn "git pull failed (local changes or diverged branch) in $BETTER_MAC_ROOT."
    confirm "Continue with the checkout as it is?"
}

apply_rice() {
    update_better_mac || return 1
    clone_rice || return 1
    preview_changes
    if ! confirm "Apply the PiercingXX rice now?"; then
        say "Nothing changed."
        cleanup_clone
        return 0
    fi
    backup_current
    # Hand better-mac this clone so it applies exactly what was previewed
    if (cd "$BETTER_MAC_ROOT" && PIERCING_DOTS_DIR="$CLONE_DIR" ./better-mac.sh); then
        ok "PiercingXX Rice Applied Successfully!"
    else
        warn "better-mac.sh reported errors. Your previous configs are in $BACKUP_ROOT."
    fi
    cleanup_clone
}

# gimp-mod.sh: replace the GIMP profile, backing up the current one
apply_gimp() {
    clone_rice || return 1
    [ -d "$CLONE_DIR/dots/GIMP" ] || { err "GIMP dots not found in piercing-dots."; return 1; }
    confirm "Replace GIMP config (current config is backed up)?" || { say "Cancelled."; return 0; }
    local stamp staging
    stamp=$(date +%Y%m%d-%H%M%S)
    if [ -d "$GIMP_DIR" ] && [ -n "$(ls -A "$GIMP_DIR" 2>/dev/null)" ]; then
        cp -a "$GIMP_DIR" "$GIMP_DIR.bak-$stamp"
        say "Backed up $GIMP_DIR -> $GIMP_DIR.bak-$stamp"
    fi
    # Copy into a staging dir first so a failed copy never leaves an empty config
    mkdir -p "$(dirname "$GIMP_DIR")"
    staging=$(mktemp -d "$(dirname "$GIMP_DIR")/.gimp-staging.XXXXXX") || return 1
    cp -R "$CLONE_DIR/dots/GIMP/." "$staging/" || { rm -rf "$staging"; return 1; }
    rm -rf "$GIMP_DIR"
    mv "$staging" "$GIMP_DIR"
    chmod 755 "$GIMP_DIR"
    ok "Installed GIMP config -> $GIMP_DIR"
}

# better-mac's macOS settings module (gnome-customizations.sh translated)
apply_macos_settings() {
    (
        cd "$BETTER_MAC_ROOT" || exit 1
        export BETTER_MAC_ROOT DRY_RUN=0
        # shellcheck disable=SC1091
        . lib/common.sh
        # shellcheck disable=SC1091
        . modules/system.sh
        ensure_brew && system_install
        install_summary
    )
}

if ! check_internet; then
    die "Network connectivity is required to continue."
fi
command_exists git || die "git is required."
BETTER_MAC_ROOT=$(find_better_mac) \
    || die "better-mac checkout not found. Clone https://github.com/PiercingXX/better-mac and run ./better-mac.sh once."
ensure_gum || warn "gum unavailable; using a plain menu."

while true; do
    [ -t 1 ] && clear
    choice=$(choose "PiercingXX Update Options" \
        "Apply PiercingXX - Everything" \
        "Apply PiercingXX - Gimp Only" \
        "Apply PiercingXX - macOS Settings ONLY" \
        "Preview changes only" \
        "Restore a previous backup" \
        "Exit")
    case $choice in
        "Apply PiercingXX - Everything")
            say "Downloading and Applying PiercingXX Rice..."
            apply_rice
            ;;
        "Apply PiercingXX - Gimp Only")
            say "Installing PiercingXX - Gimp Presets..."
            apply_gimp && ok "Piercing Gimp Presets Installed Successfully!"
            cleanup_clone
            ;;
        "Apply PiercingXX - macOS Settings ONLY")
            say "Applying PiercingXX - macOS Settings ONLY..."
            apply_macos_settings
            ;;
        "Preview changes only")
            if clone_rice; then
                preview_changes
                cleanup_clone
            fi
            ;;
        "Restore a previous backup")
            restore_backup
            ;;
        "Exit"|"")
            [ -t 1 ] && clear
            exit 0
            ;;
    esac
    pause
done
