#!/usr/bin/env bash
# GitHub.com/PiercingXX
#########################################################
# Software Manager: search, install and uninstall packages
# (distro repos, AUR on Arch, and Flathub).
#   terminal-software-manager.sh [install|uninstall]
#########################################################
# macOS port (better-mac): Homebrew formulae and casks instead of distro
# repos, AUR and Flathub. Protected list is the Homebrew tools these
# scripts run on (the system itself isn't managed by brew).

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"
detect_distro

command_exists fzf || { pkg_install fzf || true; }
command_exists fzf || die "fzf is required for the Software Manager."

# Homebrew packages ~/.scripts and the menu depend on; never removed from here
PROTECTED_PKGS=(
    bash coreutils gnu-sed grep findutils gawk fzf gum git
)

is_protected() {
    local p
    for p in "${PROTECTED_PKGS[@]}"; do
        [ "$1" = "$p" ] && return 0
    done
    return 1
}

clean_list() {
    grep -v '^$' | LC_ALL=C grep -v '[^[:print:]]' | sort -u
}

# ---------------------------------------------------------------------------
# Candidate list: "[source] name" lines
# ---------------------------------------------------------------------------
list_available() {
    brew formulae 2>/dev/null | clean_list | sed 's/^/[formula] /'
    brew casks 2>/dev/null | clean_list | sed 's/^/[cask] /'
}

list_installed() {
    brew list --formula -1 2>/dev/null | clean_list | sed 's/^/[formula] /'
    brew list --cask -1 2>/dev/null | clean_list | sed 's/^/[cask] /'
}

# Preview command for fzf ({} = "[source] name")
preview_cmd() {
    # shellcheck disable=SC2016
    printf '%s' 's={}; n=${s#* }; case "$s" in "[cask] "*) brew info --cask "$n" 2>/dev/null ;; *) brew info --formula "$n" 2>/dev/null ;; esac'
}

# Split fzf selections into formula / cask arrays
split_selection() {
    FORMULAE=(); CASKS=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            "[cask] "*) CASKS+=("${line#* }") ;;
            *)          FORMULAE+=("${line#* }") ;;
        esac
    done <<< "$1"
}

install_software() {
    local selection
    selection=$(list_available | fzf --multi --prompt="Install > " \
        --header="Tab to select several, Enter to install" \
        --preview="$(preview_cmd)" --preview-window=down:50%) || return 0
    [ -n "$selection" ] || return 0
    split_selection "$selection"

    if [ ${#FORMULAE[@]} -gt 0 ]; then
        say "Installing: ${FORMULAE[*]}"
        brew install --formula "${FORMULAE[@]}"
    fi
    if [ ${#CASKS[@]} -gt 0 ]; then
        say "Installing casks: ${CASKS[*]}"
        brew install --cask "${CASKS[@]}"
    fi
}

uninstall_software() {
    local selection p
    selection=$(list_installed | fzf --multi --prompt="Uninstall > " \
        --header="Tab to select several, Enter to review" \
        --preview="$(preview_cmd)" --preview-window=down:50%) || return 0
    [ -n "$selection" ] || return 0
    split_selection "$selection"

    local keep=()
    for p in "${FORMULAE[@]}"; do
        if is_protected "$p"; then
            warn "Skipping protected package: $p"
        else
            keep+=("$p")
        fi
    done
    FORMULAE=("${keep[@]}")
    [ ${#FORMULAE[@]} -gt 0 ] || [ ${#CASKS[@]} -gt 0 ] || return 0

    echo
    [ ${#FORMULAE[@]} -gt 0 ] && echo "Formulae: ${FORMULAE[*]}"
    [ ${#CASKS[@]} -gt 0 ] && echo "Casks: ${CASKS[*]}"
    # brew uninstall doesn't ask, so this is the only confirmation. It also
    # refuses to remove a formula another installed formula depends on.
    confirm "Remove these?" || return 0

    if [ ${#FORMULAE[@]} -gt 0 ]; then
        brew uninstall --formula "${FORMULAE[@]}"
    fi
    if [ ${#CASKS[@]} -gt 0 ]; then
        brew uninstall --cask "${CASKS[@]}"
    fi
}

choose_mode() {
    local i="📦 Install" u="🗑️ Uninstall" b="🚪 Back"
    if [[ "${PIERCINGXX_ASCII_MENU:-0}" == 1 ]]; then
        i="Install"; u="Uninstall"; b="Back"
    fi
    local pick
    if command_exists gum; then
        pick=$(gum choose --header="Software Manager" "$i" "$u" "$b")
    else
        select pick in "$i" "$u" "$b"; do break; done
    fi
    case "$pick" in
        "$i") echo install ;;
        "$u") echo uninstall ;;
        *)    echo back ;;
    esac
}

[ -n "$PKG" ] || die "Homebrew is not installed (https://brew.sh)."

# Direct mode: terminal-software-manager.sh install|uninstall
case "${1:-}" in
    install)   install_software; exit $? ;;
    uninstall) uninstall_software; exit $? ;;
    "") ;;
    *) echo "Usage: $0 [install|uninstall]"; exit 1 ;;
esac

while true; do
    clear
    case "$(choose_mode)" in
        install)   install_software ;;
        uninstall) uninstall_software ;;
        *)         exit 0 ;;
    esac
    echo
    pause
done
