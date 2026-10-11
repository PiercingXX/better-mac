#!/bin/bash
# GitHub.com/PiercingXX
#
# better-mac - the macOS sibling of linux-mod.
#
# Usage:  ./better-mac.sh              everything: shell, dots, apps, keyboard, settings, desktop
#         ./better-mac.sh --dry-run    print actions instead of executing
#         ./better-mac.sh --no-color   plain output (NO_COLOR env also works)
#
# A fresh Mac only has Apple's bash 3.2, so this script, lib/ and modules/
# must not use bash 4+ syntax.

BETTER_MAC_ROOT="$(cd "$(dirname "$0")" && pwd)"
export BETTER_MAC_ROOT

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=1 ;;
        --no-color) NO_COLOR=1 ;;
        -h|--help)
            sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unknown option: $arg (try --help)"
            exit 1 ;;
    esac
done
export DRY_RUN NO_COLOR

# shellcheck disable=SC1091
. "$BETTER_MAC_ROOT/lib/common.sh"

if [ "$(uname -s)" != "Darwin" ] && [ "$DRY_RUN" -eq 0 ]; then
    echo "better-mac only runs on macOS (--dry-run works anywhere)."
    exit 1
fi
if [ "$EUID" -eq 0 ]; then
    echo "Run this as your normal user, not root."
    exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    say "DRY RUN — nothing will be installed or changed."
else
    # Ask for sudo once (shells, pmset, firewall, Remote Login) and keep it alive
    sudo -v || exit 1
    (while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &)
fi

ensure_brew || { warn "Homebrew install failed."; install_summary; exit 1; }
trap cleanup_piercing_dots EXIT

# The settings menu's update-piercingXX.sh pulls and reruns this checkout
if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$HOME/.config/better-mac"
    printf '%s\n' "$BETTER_MAC_ROOT" >"$HOME/.config/better-mac/root"
fi

for module in "$BETTER_MAC_ROOT"/modules/*.sh; do
    # shellcheck disable=SC1090
    . "$module"
done

shell_install
dots_install
apps_install
scripts_install
keyboard_install
system_install
wm_install

install_summary
say "Reboot when ready (the /media link and login settings need it)."
