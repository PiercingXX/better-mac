#!/usr/bin/env bash
# GitHub.com/PiercingXX
# macOS port (better-mac): "Everything" pulls better-mac and reruns it (it
# fetches piercing-dots fresh each run). No Hyprland on macOS, so the
# "without Hyprland configs" option is gone; GNOME Customizations become
# better-mac's macOS settings.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

install_gum_if_needed() {
    command_exists gum && return 0
    echo "gum not found. Installing..."
    if command_exists brew; then
        brew install gum
    else
        echo "Please install gum manually."
        exit 1
    fi
}

# Where better-mac.sh was last run from (it records this on every run)
find_better_mac() {
    local root=""
    [ -f "$HOME/.config/better-mac/root" ] && root="$(head -n 1 "$HOME/.config/better-mac/root")"
    if [ -z "$root" ] || [ ! -x "$root/better-mac.sh" ]; then
        for alt in "$HOME/better-mac" "$HOME/GitHub/better-mac" /media/Working-Storage/GitHub/better-mac; do
            if [ -x "$alt/better-mac.sh" ]; then
                root="$alt"
                break
            fi
        done
    fi
    [ -x "$root/better-mac.sh" ] || return 1
    printf '%s\n' "$root"
}

clone_rice() {
    rm -rf "$CLONE_DIR"
    git clone --depth 1 https://github.com/Piercingxx/piercing-dots.git "$CLONE_DIR"
    chmod -R u+x "$CLONE_DIR"
}

cleanup_clone() {
    cd "$builddir" || true
    rm -rf "$CLONE_DIR"
}

# Check for active network connection (macOS ping: -t is the timeout)
if ! ping -c 1 -t 2 8.8.8.8 >/dev/null 2>&1 && ! ping -c 1 -t 2 1.1.1.1 >/dev/null 2>&1; then
    echo "Network connectivity is required to continue."
    exit 1
fi

install_gum_if_needed

builddir="$(mktemp -d)"
CLONE_DIR="$builddir/piercing-dots"
trap 'cd "$HOME"; rm -rf "$builddir"' EXIT

if ! BETTER_MAC_ROOT="$(find_better_mac)"; then
    echo "better-mac checkout not found. Clone it and run ./better-mac.sh once:"
    echo "  git clone https://github.com/PiercingXX/better-mac.git"
    exit 1
fi

while true; do
    clear
    choice=$(printf "%s\n" \
        "Apply PiercingXX - Everything" \
        "Apply PiercingXX - Gimp Only" \
        "Apply PiercingXX - macOS Settings ONLY" \
        "Exit" | \
        gum choose --header "PiercingXX Update Options" --cursor.foreground 212 --selected.foreground 212)
    case $choice in
        "Apply PiercingXX - Everything")
            echo -e "\033[1;33mUpdating better-mac in $BETTER_MAC_ROOT...\033[0m"
            if ! git -C "$BETTER_MAC_ROOT" pull --ff-only; then
                echo -e "\033[1;33mgit pull failed (local changes or diverged branch); fix that in $BETTER_MAC_ROOT first.\033[0m"
                read -r -p "Press Enter to continue..." _
                continue
            fi
            if gum confirm "Run ./better-mac.sh now? (pulls the latest piercing-dots and reapplies everything)"; then
                echo -e "\033[1;33mDownloading and Applying PiercingXX Rice...\033[0m"
                (cd "$BETTER_MAC_ROOT" && ./better-mac.sh)
                echo -e "\033[0;32mPiercingXX Rice Applied Successfully!\033[0m"
            fi
            read -r -p "Press Enter to continue..." _
            ;;
        "Apply PiercingXX - Gimp Only")
            echo -e "\033[1;33mInstalling PiercingXX - Gimp Presets...\033[0m"
            clone_rice
            # GIMP keeps its profile under Application Support on macOS
            gimp_dir="$HOME/Library/Application Support/GIMP"
            rm -Rf "$gimp_dir/"*
            mkdir -p "$gimp_dir"
            cp -Rf "$CLONE_DIR/dots/GIMP/"* "$gimp_dir/"
            cleanup_clone
            echo -e "\033[0;32mPiercing Gimp Presets Installed Successfully!\033[0m"
            read -r -p "Press Enter to continue..." _
            ;;
        "Apply PiercingXX - macOS Settings ONLY")
            echo -e "\033[1;33mApplying PiercingXX - macOS Settings ONLY...\033[0m"
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
            read -r -p "Press Enter to continue..." _
            ;;
        "Exit"|"")
            clear
            exit 0
            ;;
    esac
done
