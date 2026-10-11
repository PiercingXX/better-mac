#!/usr/bin/env bash
# GitHub.com/PiercingXX

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

YAZI_BIN="$(command -v yazi 2>/dev/null || true)"

if [[ -z "$YAZI_BIN" && -x "$HOME/.cargo/bin/yazi" ]]; then
    YAZI_BIN="$HOME/.cargo/bin/yazi"
fi

# --- macOS wallpaper changer (System Events sets every display's desktop) ---
WALLPAPER_DIR="$HOME/Pictures/backgrounds"
clear
# Ensure wallpaper directory exists
if [ ! -d "$WALLPAPER_DIR" ]; then
    mkdir -p "$WALLPAPER_DIR"
    echo "Created $WALLPAPER_DIR directory. Please add wallpapers to this directory."
    exit 1
fi
if [[ -z "$YAZI_BIN" ]]; then
    echo "yazi not found. Please install yazi."
    exit 1
fi
if ! command -v osascript &>/dev/null; then
    echo "osascript not found. This wallpaper changer needs macOS."
    exit 1
fi

# Display names, one per line (first use asks to let your terminal control System Events)
displays=()
while IFS= read -r line; do
    [ -n "$line" ] && displays+=("$line")
done < <(osascript -e 'tell application "System Events" to get display name of every desktop' 2>/dev/null | tr ',' '\n' | sed 's/^[[:space:]]*//')
if [ ${#displays[@]} -eq 0 ]; then
    echo "No displays found. Allow your terminal to control System Events (Privacy & Security > Automation)."
    exit 1
fi

# set_wallpaper <index|all> <file>
set_wallpaper() {
    local target="$1" file="$2"
    file="${file//\"/\\\"}"
    if [ "$target" = "all" ]; then
        osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$file\""
    else
        osascript -e "tell application \"System Events\" to tell desktop $target to set picture to POSIX file \"$file\""
    fi
}

# Ask user for mode if multiple displays
if [ ${#displays[@]} -gt 1 ]; then
    if command -v gum &>/dev/null; then
        mode=$(printf "Same wallpaper on all displays\nDifferent wallpaper for each display" | gum choose --header "Multiple displays detected. How do you want to set wallpapers?")
    else
        echo "Multiple displays detected."
        echo "1) Same wallpaper on all displays"
        echo "2) Different wallpaper for each display"
        read -rp "Choose [1-2]: " mode_choice
        if [ "$mode_choice" = "2" ]; then
            mode="Different wallpaper for each display"
        else
            mode="Same wallpaper on all displays"
        fi
    fi
else
    mode="Same wallpaper on all displays"
fi

# Function to select a wallpaper using yazi (with image preview)
select_wallpaper_yazi() {
    echo "Launching yazi in $WALLPAPER_DIR..." 1>&2
    local chooser_file selected_file
    chooser_file=$(mktemp)
    "$YAZI_BIN" "$WALLPAPER_DIR" --chooser-file "$chooser_file"
    selected_file=$(cat "$chooser_file")
    rm -f "$chooser_file"
    echo "yazi returned: $selected_file" 1>&2
    # Ensure absolute path
    if [ -n "$selected_file" ] && [ "${selected_file:0:1}" != "/" ]; then
        selected_file="$WALLPAPER_DIR/$selected_file"
    fi
    echo "$selected_file"
}

if [ "$mode" = "Same wallpaper on all displays" ]; then
    selected=$(select_wallpaper_yazi)
    if [ -z "$selected" ]; then
        echo "No wallpaper selected. Exiting."
        exit 0
    fi
    set_wallpaper all "$selected"
    echo "Wallpaper set to $selected for displays: ${displays[*]}"
else
    for i in "${!displays[@]}"; do
        printf '\n--- Selecting wallpaper for display: %s ---\n' "${displays[$i]}"
        wp=$(select_wallpaper_yazi)
        if [ -z "$wp" ]; then
            echo "No wallpaper selected for ${displays[$i]}. Exiting."
            exit 0
        fi
        set_wallpaper $((i + 1)) "$wp"
    done
    echo "Wallpapers set for displays: ${displays[*]}"
fi
exit 0
