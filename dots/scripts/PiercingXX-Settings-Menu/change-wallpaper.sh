#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Pick a wallpaper with yazi and apply it for the running desktop:
#   Hyprland -> hyprpaper (IPC, config written for next login)
#   Sway     -> swaybg
#   GNOME    -> gsettings
#   X11 WMs  -> ~/.config/wall.png (read by bspwm/dwm/i3 autostarts) + feh/hsetroot
#
# macOS port (better-mac): one path, System Events sets the desktop picture
# per display (same or different per display, like the Hyprland branch).
# Dropped: hyprpaper/swaybg/gsettings/feh and ~/.config/wall.png (nothing on
# macOS reads it). First run asks to let the terminal control System Events.

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

WALLPAPER_DIR="$HOME/Pictures/backgrounds"

YAZI_BIN="$(command -v yazi 2>/dev/null || true)"
if [[ -z "$YAZI_BIN" && -x "$HOME/.cargo/bin/yazi" ]]; then
    YAZI_BIN="$HOME/.cargo/bin/yazi"
fi

clear
if [ ! -d "$WALLPAPER_DIR" ]; then
    mkdir -p "$WALLPAPER_DIR"
    die "Created $WALLPAPER_DIR. Add some wallpapers there and run this again."
fi
[ -n "$YAZI_BIN" ] || die "yazi not found. Please install yazi."

# Pick one image with yazi (image preview) -> absolute path on stdout
select_wallpaper() {
    local chooser_file selected_file
    echo "Launching yazi in $WALLPAPER_DIR..." >&2
    chooser_file=$(mktemp)
    "$YAZI_BIN" "$WALLPAPER_DIR" --chooser-file "$chooser_file"
    selected_file=$(head -n 1 "$chooser_file")
    command rm -f "$chooser_file"
    if [ -n "$selected_file" ] && [ "${selected_file:0:1}" != "/" ]; then
        selected_file="$WALLPAPER_DIR/$selected_file"
    fi
    echo "$selected_file"
}

choose_mode() {
    if command_exists gum; then
        printf "Same wallpaper on all displays\nDifferent wallpaper for each display" \
            | gum choose --header "Multiple displays detected. How do you want to set wallpapers?"
    else
        local c
        echo "Multiple displays detected."
        echo "1) Same wallpaper on all displays"
        echo "2) Different wallpaper for each display"
        read -rp "Choose [1-2]: " c
        [ "$c" = 2 ] && echo "Different wallpaper for each display" || echo "Same wallpaper on all displays"
    fi
}

# set_desktop INDEX|all FILE (System Events numbers desktops from 1)
set_desktop() {
    local target="desktop $1" file
    [ "$1" = all ] && target="every desktop"
    file=$(_px_osa_escape "$2")
    osascript -e "tell application \"System Events\" to tell $target to set picture to POSIX file \"$file\""
}

macos_wallpaper() {
    command_exists osascript || die "osascript not found."
    local -a displays
    local names
    names=$(osascript -e 'tell application "System Events" to get display name of every desktop' 2>/dev/null)
    mapfile -t displays < <(printf '%s\n' "${names//, /$'\n'}" | grep .)
    [ ${#displays[@]} -gt 0 ] || die "No displays found. Allow your terminal to control System Events (Privacy & Security > Automation)."

    local mode="Same wallpaper on all displays"
    [ ${#displays[@]} -gt 1 ] && mode=$(choose_mode)
    [ -n "$mode" ] || exit 0

    local i wp
    if [ "$mode" = "Same wallpaper on all displays" ]; then
        wp=$(select_wallpaper)
        [ -n "$wp" ] || { echo "No wallpaper selected."; exit 0; }
        set_desktop all "$wp" || die "Could not set the wallpaper."
    else
        for i in "${!displays[@]}"; do
            printf '\n--- Selecting wallpaper for display: %s ---\n' "${displays[$i]}"
            wp=$(select_wallpaper)
            [ -n "$wp" ] || { echo "No wallpaper selected for ${displays[$i]}."; exit 0; }
            set_desktop $((i + 1)) "$wp" || die "Could not set the wallpaper for ${displays[$i]}."
        done
    fi
    ok "Wallpaper set for: ${displays[*]}"
}

macos_wallpaper
