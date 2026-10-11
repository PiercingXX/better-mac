#!/usr/bin/env bash
# GitHub.com/PiercingXX
# macOS port (better-mac): Homebrew instead of distro package managers.
# ~/Library/Caches and ~/Downloads ask first; /tmp is left to macOS (it
# holds live sockets such as tmux's and is cleared at reboot).

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Define colors
yellow='\033[1;33m'
green='\033[0;32m'
blue='\033[0;34m'
nc='\033[0m'

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Yes/no prompt: gum when available, plain read otherwise (default: no)
confirm() {
    if command_exists gum; then
        gum confirm --default=false "$1"
    else
        local reply
        read -r -p "$1 [y/N] " reply
        [[ "$reply" == [yY]* ]]
    fi
}

echo -e "${blue}Cleaning up system...${nc}"
if command_exists brew; then
    # Remove orphaned dependencies and clean the download cache
    brew autoremove
    brew cleanup --prune=all -s
else
    echo -e "${yellow}Homebrew not found; skipping package cleanup.${nc}"
fi

# Silently clean user cache (XDG tools on macOS use ~/.cache too)
rm -rf ~/.cache/* 2>/dev/null
echo -e "${green}System cleaning complete!${nc}"

# macOS app caches: apps rebuild them, but some (browsers, Xcode) are large
# and slow to repopulate
if [ -d "$HOME/Library/Caches" ] && confirm "Clear ~/Library/Caches ($(du -sh "$HOME/Library/Caches" 2>/dev/null | cut -f1))?"; then
    rm -rf "$HOME/Library/Caches/"* 2>/dev/null
    echo "Cleared ~/Library/Caches."
fi

if [ -d "$HOME/Downloads" ] && confirm "Delete everything in ~/Downloads?"; then
    rm -rf "$HOME/Downloads/"* "$HOME/Downloads/".[!.]* 2>/dev/null
    echo "Emptied ~/Downloads."
fi

# Empty trash: trash-cli's (the rm alias) and the Finder Trash
rm -rf "$HOME/.local/share/Trash/files/"* "$HOME/.local/share/Trash/info/"* 2>/dev/null
if ! osascript -e 'tell application "Finder" to empty trash' >/dev/null 2>&1; then
    rm -rf "$HOME/.Trash/"* 2>/dev/null
fi

echo "Caches and trash have been cleaned."
echo -e "${green}System cleaning complete!${nc}"
