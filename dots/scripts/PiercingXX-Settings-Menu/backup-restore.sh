#!/usr/bin/env bash
# GitHub.com/PiercingXX

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

yellow='\033[1;33m'
green='\033[0;32m'
nc='\033[0m'

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# macOS ships openrsync (or an ancient rsync 2.6.9); use Homebrew's rsync so
# -h and --delete behave like on Linux
if [ ! -x /opt/homebrew/bin/rsync ] && [ ! -x /usr/local/bin/rsync ]; then
    echo -e "${yellow}Homebrew rsync not found – attempting install...${nc}"
    if command_exists brew; then
        brew install rsync
    fi
    if [ -x /opt/homebrew/bin/rsync ] || [ -x /usr/local/bin/rsync ]; then
        echo -e "${green}rsync installed successfully.${nc}"
    else
        echo -e "${yellow}Could not install Homebrew rsync; using the system rsync.${nc}"
    fi
fi
RSYNC_OPTS=(-avh --delete)
if ! rsync --version 2>/dev/null | grep -q 'version [3-9]'; then
    RSYNC_OPTS=(-av --delete)
fi

while true; do
    clear
    if ! command -v gum &>/dev/null; then
        if command_exists brew; then
            echo "gum not found. Installing gum with brew..."
            brew install gum
        fi
    fi
    if ! command -v gum &>/dev/null; then
        echo "gum is not installed and could not be installed automatically. Please install gum."
        exit 1
    fi
    action=$(gum choose --header="Backup & Restore" "Backup" "Restore" "Back")
    case "$action" in
        "Backup")
            src=$(gum input --placeholder="Enter source directory (to backup)")
            dest=$(gum input --placeholder="Enter backup destination directory")
            if [ -n "$src" ] && [ -n "$dest" ]; then
                if [ ! -d "$src" ]; then
                    echo "Source directory does not exist: $src"
                    echo "Press Enter to continue..."; read; continue
                fi
                mkdir -p "$dest"
                echo "Running: rsync ${RSYNC_OPTS[*]} '$src/' '$dest/'"
                if rsync "${RSYNC_OPTS[@]}" "$src/" "$dest/" 2>&1; then
                    echo "Backup complete. Press Enter to continue..."
                else
                    echo "Backup failed! See errors above. Press Enter to continue..."
                fi
                read
            fi
            ;;
        "Restore")
            src=$(gum input --placeholder="Enter backup source directory (to restore from)")
            dest=$(gum input --placeholder="Enter restore destination directory")
            if [ -n "$src" ] && [ -n "$dest" ]; then
                if [ ! -d "$src" ]; then
                    echo "Backup source directory does not exist: $src"
                    echo "Press Enter to continue..."; read; continue
                fi
                mkdir -p "$dest"
                echo "Running: rsync ${RSYNC_OPTS[*]} '$src/' '$dest/'"
                if rsync "${RSYNC_OPTS[@]}" "$src/" "$dest/" 2>&1; then
                    echo "Restore complete. Press Enter to continue..."
                else
                    echo "Restore failed! See errors above. Press Enter to continue..."
                fi
                read
            fi
            ;;
        "Back"|"")
            break
            ;;
    esac
    clear
    # Loop back to menu
    continue
    break
    done
