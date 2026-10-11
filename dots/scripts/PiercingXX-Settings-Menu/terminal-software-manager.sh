#!/usr/bin/env bash
# GitHub.com/PiercingXX
# macOS port (better-mac): Homebrew formulae and casks instead of distro
# repos, AUR and flatpak.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

#########################################################
# Software Manager: Install and Uninstall Packages
#########################################################

clear
# Function to search and install software
install_software() {
    local selection sel name
    selection=$(
        (
            brew formulae 2>/dev/null | grep -v '^$' | LC_ALL=C grep -v '[^[:print:]]' | sed 's/^/[formula] /'
            brew casks 2>/dev/null | grep -v '^$' | LC_ALL=C grep -v '[^[:print:]]' | sed 's/^/[cask] /'
        ) | fzf --multi \
            --preview='name=$(echo {} | cut -d" " -f2-); if echo {} | grep -q "^\[cask\]"; then brew info --cask "$name" 2>/dev/null || echo ""; else brew info --formula "$name" 2>/dev/null || echo ""; fi' \
            --preview-window=down:50%
    )
    [[ -z "$selection" ]] && return 0
    while IFS= read -r sel; do
        name=$(printf "%s" "$sel" | cut -d" " -f2-)
        if [[ "$sel" == "[cask] "* ]]; then
            brew install --cask "$name"
        else
            brew install --formula "$name"
        fi
    done <<< "$selection"
}

# Function to uninstall software
uninstall_software() {
    local pkgs selection sel name
    pkgs=$(
        brew list --formula -1 2>/dev/null | sed 's/^/[formula] /'
        brew list --cask -1 2>/dev/null | sed 's/^/[cask] /'
    )
    [ -z "$pkgs" ] && return 0
    selection=$(printf "%s\n" "$pkgs" | fzf --multi --prompt="Uninstall (enter to select): " \
                            --preview 'name=$(echo {} | cut -d" " -f2-); if echo {} | grep -q "^\[cask\]"; then brew info --cask "$name" 2>/dev/null; else brew info --formula "$name" 2>/dev/null; fi' \
                            --preview-window=down:50% --border)
    [[ -z "$selection" ]] && return 0
    while IFS= read -r sel; do
        name=$(printf "%s" "$sel" | cut -d" " -f2-)
        if [[ "$sel" == "[cask] "* ]]; then
            brew uninstall --cask "$name"
        elif [[ "$sel" == "[formula] "* ]]; then
            brew uninstall --formula "$name"
        else
            echo "Unknown or unsupported package for uninstall: $sel"
        fi
    done <<< "$selection"
}

if ! command -v brew &>/dev/null; then
    echo "Homebrew is not installed (https://brew.sh)."
    exit 1
fi

while true; do
    clear
    if [ -z "$1" ]; then
        if ! command -v gum &>/dev/null; then
            echo "gum not found. Installing gum with brew..."
            brew install gum
        fi
        if ! command -v gum &>/dev/null; then
            echo "gum is not installed and could not be installed automatically. Please install gum for a modern menu (https://github.com/charmbracelet/gum)."
            exit 1
        fi
        mode=$(gum choose --header="Software Manager" "📦 Install" "🗑️ Uninstall" "🚪 Quit")
        case $mode in
            "📦 Install") set -- install ;;
            "🗑️ Uninstall") set -- uninstall ;;
            "🚪 Quit"|"") exit 0 ;;
        esac
    fi

    case "$1" in
        install)
            install_software
            ;;
        uninstall)
            uninstall_software
            ;;
        *)
            echo "Usage: $0 {install|uninstall}"
            exit 1
            ;;
    esac
    # Reset $1 so the menu shows again
    set --
done
