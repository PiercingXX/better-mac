#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Log Viewer: journal errors, kernel, desktop and package-manager logs.
# macOS port (better-mac): the journal is the unified log (log show/stream);
# "this boot" views are errors/faults, warnings have no macOS level. The
# Hyprland/Xorg logs become Homebrew service logs (SketchyBar, borders),
# app logs in ~/Library/Logs and crash reports. Package history is brew's
# Cellar/Caskroom install dates plus softwareupdate --history. Dropped:
# previous-boot errors (log show can't select a boot).

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"
detect_distro

command_exists gum || die "gum is required for this menu."

pager() { gum pager; }

# The unified log is huge; cap what reaches the pager
log_query() {
    local range="$1" predicate="$2"
    log show "$range" --style compact --predicate "$predicate" 2>&1 | tail -n 5000
}

brew_log_dir() {
    local d
    [ "$PKG" = brew ] || return 0
    d="$(brew --prefix)/var/log"
    [ -n "$(find "$d" -type f 2>/dev/null | head -n1)" ] && echo "$d"
}

# pick_log dir... : choose a file (newest first) and page its tail
pick_log() {
    local f
    f=$(find "$@" -type f \( -name '*.log' -o -name '*.ips' -o -name '*.diag' -o -name '*.crash' -o -name '*.txt' \) \
            -exec /usr/bin/stat -f '%m %N' {} + 2>/dev/null \
        | sort -rn | cut -d' ' -f2- | gum filter --placeholder "search logs") || return 0
    [ -n "$f" ] && tail -n 1000 "$f" 2>&1 | pager
}

package_log() {
    case "$PKG" in
        brew)
            echo "Homebrew installs and upgrades (newest first):"
            find "$(brew --cellar)" "$(brew --caskroom)" -mindepth 2 -maxdepth 2 -type d ! -name '.*' \
                    -exec /usr/bin/stat -f '%Sm  %N' -t '%F %T' {} + 2>/dev/null \
                | sed "s|$(brew --prefix)/||" | sort -r | head -n 200
            echo ;;
    esac
    echo "macOS updates:"
    softwareupdate --history 2>/dev/null
}

system_log() {
    local f=/var/log/system.log
    [ -r "$f" ] && { tail -n 500 "$f"; return; }
    [ -e "$f" ] && { sudo tail -n 500 "$f"; return; }
    echo "No system log found."
}

options=("Errors & faults (last hour)" "Faults this boot" "Follow log (Ctrl-C to stop)" "App logs (~/Library/Logs)" "System log")
options+=("Kernel messages" "Crash reports")
[ -n "$(brew_log_dir)" ] && options+=("Homebrew service logs")
options+=("Package manager history" "Back")

while true; do
    clear
    choice=$(printf '%s\n' "${options[@]}" | gum choose --header "Logs") || exit 0
    case "$choice" in
        "Errors & faults (last hour)") log_query --last=1h 'messageType == error OR messageType == fault' | pager ;;
        "Faults this boot")            log_query --last=boot 'messageType == fault' | pager ;;
        "Follow log (Ctrl-C to stop)")
            trap ':' INT
            log stream --style compact
            trap - INT ;;
        "App logs (~/Library/Logs)")   pick_log "$HOME/Library/Logs" ;;
        "System log")                  system_log | pager ;;
        "Kernel messages")             log_query --last=boot 'sender == "kernel" AND messageType >= error' | pager ;;
        "Crash reports")               pick_log "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports ;;
        "Homebrew service logs")       pick_log "$(brew_log_dir)" ;;
        "Package manager history")     package_log 2>&1 | pager ;;
        *) exit 0 ;;
    esac
done
