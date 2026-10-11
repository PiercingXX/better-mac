# shellcheck shell=bash
# GitHub.com/PiercingXX - better-mac
# Sourced at the end of ~/.bashrc: macOS replacements for the Linux-only
# parts of the piercing-dots .bashrc. Everything else there works as-is.

# Completion and fzf keybindings live under Homebrew, not /usr/share
if [[ ${iatest:-0} -gt 0 ]]; then
    if [[ -r "${HOMEBREW_PREFIX:-}/etc/profile.d/bash_completion.sh" ]]; then
        . "$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh"
    fi
    if command -v fzf >/dev/null 2>&1; then
        eval "$(fzf --bash)"
    fi
fi

# Use Homebrew's GNU grep instead of the pinned /usr/bin/grep (BSD)
alias grep='grep --color=auto'

# /bin/rm is BSD; `command` skips the rm -> trash alias
alias rmd='command rm --recursive --force --verbose'

alias openports='lsof -nP -iTCP -sTCP:LISTEN'
alias logs='log stream --style compact'
alias logout='osascript -e "tell application \"System Events\" to log out"'
alias sd='open -a "Synology Drive Client"'

# Linux desktop launchers and the settings menu have no macOS equivalent
unalias xx gnome hypr sway i3 bspwm herb awesome dwm qtile qtilex 2>/dev/null

# cp with progress (strace isn't available on macOS)
cpp() {
    rsync -ah --progress "$1" "$2"
}

whatsmyip() {
    local dev
    dev=$(route -n get 1.1.1.1 2>/dev/null | awk '/interface:/ {print $2}')
    echo -n "Internal IP: "
    ipconfig getifaddr "${dev:-en0}" || echo "unavailable"
    echo -n "External IP: "
    curl -fsS4 ifconfig.me || curl -fsS ipinfo.io/ip || echo "unavailable"
    echo
}

install_bashrc_support() {
    brew install multitail tree zoxide trash-cli fzf bash-completion@2 fastfetch \
        bat eza chafa w3m jump starship
}

distribution() {
    echo "macos"
}
