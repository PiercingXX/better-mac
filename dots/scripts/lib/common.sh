# shellcheck shell=bash
# GitHub.com/PiercingXX
# Shared helpers for ~/.scripts. Source this file, do not execute it:
#   . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"
# macOS port (better-mac): same function names as piercing-dots
# resources/.scripts/lib/common.sh so the scripts call them unchanged.
#   DISTRO=macos  PKG=brew  INIT=launchd
# Packages come from Homebrew, services are launchd jobs, notifications go
# through osascript, the clipboard is pbcopy.

[ -n "${PX_COMMON_LOADED:-}" ] && return 0
PX_COMMON_LOADED=1

# Scripts run from Rift keybinds and Sol, which don't load ~/.bashrc
case ":$PATH:" in
    *:/opt/homebrew/bin:*) ;;
    *) PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH" ;;
esac
export PATH

# ---------------------------------------------------------------------------
# Colors (upper and lower case names; older scripts use both)
# ---------------------------------------------------------------------------
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi
red="$RED"; green="$GREEN"; yellow="$YELLOW"; blue="$BLUE"; nc="$NC"

say()  { printf '%s\n' "${YELLOW}$*${NC}"; }
ok()   { printf '%s\n' "${GREEN}$*${NC}"; }
warn() { printf '%s\n' "${YELLOW}$*${NC}" >&2; }
err()  { printf '%s\n' "${RED}$*${NC}" >&2; }
die()  { err "$*"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Per-user state/log dir and the external storage root (override via env).
# /media is a link to /Volumes (better-mac's /etc/synthetic.conf).
PX_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/piercingxx"
PX_WORK_ROOT="${PIERCINGXX_WORK_ROOT:-/media/Working-Storage}"
PX_ARCHIVE_ROOT="${PIERCINGXX_ARCHIVE_ROOT:-/media/Archived-Storage}"

refuse_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        die "Run this as your normal user, not root. It will ask for sudo when needed."
    fi
}

# ---------------------------------------------------------------------------
# Platform detection (Linux names kept so callers' checks still read right)
#   DISTRO     macos
#   DISTRO_ID  macos
#   PKG        brew (empty if Homebrew is missing)
#   INIT       launchd
# ---------------------------------------------------------------------------
detect_distro() {
    DISTRO="macos"
    DISTRO_ID="macos"
    if command_exists brew; then PKG="brew"; else PKG=""; fi
    INIT="launchd"
}

is_arch_like() { return 1; }
is_macos() { return 0; }

# No AUR on macOS
aur_helper() { :; }

# pkg_install pkg... : Homebrew formulae (never sudo), skipping what's present
pkg_install() {
    [ $# -gt 0 ] || return 0
    [ -n "${PKG:-}" ] || detect_distro
    [ "$PKG" = brew ] || { err "Homebrew not found (https://brew.sh)."; return 1; }
    local p missing=()
    for p in "$@"; do
        brew list --formula "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    [ ${#missing[@]} -eq 0 ] && return 0
    HOMEBREW_NO_ASK=1 brew install "${missing[@]}"
}

# ---------------------------------------------------------------------------
# Services (launchd). A name is matched as a launchd label in the user
# domain first (gui/<uid>), then the system domain. Homebrew services are
# labelled sh.brew.<formula> (homebrew.mxcl.<formula> before Homebrew 5), so
# a bare formula name works too.
# ---------------------------------------------------------------------------
_px_svc_label() {
    local name="$1" uid
    uid=$(id -u)
    if launchctl print "gui/$uid/$name" >/dev/null 2>&1; then
        echo "gui/$uid/$name"
    elif launchctl print "gui/$uid/sh.brew.$name" >/dev/null 2>&1; then
        echo "gui/$uid/sh.brew.$name"
    elif launchctl print "gui/$uid/homebrew.mxcl.$name" >/dev/null 2>&1; then
        echo "gui/$uid/homebrew.mxcl.$name"
    elif launchctl print "system/$name" >/dev/null 2>&1; then
        echo "system/$name"
    else
        return 1
    fi
}

svc_is_active() {
    local target
    target=$(_px_svc_label "$1") || { pgrep -x "$1" >/dev/null 2>&1; return; }
    launchctl print "$target" 2>/dev/null | grep -q 'state = running'
}

svc_exists() {
    _px_svc_label "$1" >/dev/null 2>&1 && return 0
    command_exists brew && brew services list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$1"
}

_px_sudo_for() { case "$1" in system/*) echo sudo ;; esac; }

svc_start() {
    local target
    if target=$(_px_svc_label "$1"); then
        $(_px_sudo_for "$target") launchctl kickstart "$target"
    elif command_exists brew; then
        brew services start "$1"
    else
        return 1
    fi
}

svc_stop() {
    local target
    if command_exists brew && brew services list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$1"; then
        brew services stop "$1"
    elif target=$(_px_svc_label "$1"); then
        $(_px_sudo_for "$target") launchctl kill SIGTERM "$target"
    else
        return 1
    fi
}

svc_enable_now() {
    local target
    if command_exists brew && brew services list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$1"; then
        brew services start "$1"
    elif target=$(_px_svc_label "$1"); then
        $(_px_sudo_for "$target") launchctl enable "$target" \
            && $(_px_sudo_for "$target") launchctl kickstart "$target"
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Interaction (gum when present, plain read otherwise)
# ---------------------------------------------------------------------------
pause() {
    local msg="${1:-Press Enter to continue...}"
    [ -t 0 ] || return 0
    read -r -p "$msg" _
}

# confirm "Question?" -> 0 yes / 1 no. PX_ASSUME_YES=1 answers yes.
confirm() {
    [ "${PX_ASSUME_YES:-0}" = 1 ] && return 0
    [ -t 0 ] || return 1
    if command_exists gum; then
        gum confirm "$1"
    else
        local a
        read -r -p "$1 [y/N] " a
        [[ "$a" =~ ^[Yy]$ ]]
    fi
}

# ---------------------------------------------------------------------------
# Single instance lock for long-running daemons.
#   single_instance battery-notify || exit 0
# macOS has no flock(1); shlock writes our PID and refuses while that PID
# is alive, so a crashed daemon doesn't leave a stale lock.
# ---------------------------------------------------------------------------
single_instance() {
    local dir="${TMPDIR:-/tmp}"
    shlock -p $$ -f "${dir%/}/piercingxx-$1.lock"
}

# ---------------------------------------------------------------------------
# Notifications
#   notify_replace KEY URGENCY TIMEOUT_MS ICON SUMMARY [BODY]
# Shown by piercing-notify (better-mac dots/notify): mako-style popups that
# replace by KEY and honour URGENCY and TIMEOUT. ICON is ignored. Without it,
# Notification Center through osascript (Script Editor must be allowed under
# Notifications), which can't replace or time out.
# ---------------------------------------------------------------------------
_px_osa_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

notify_replace() {
    local key="$1" urgency="$2" timeout="$3" summary="$5" body="${6:-}"
    if [ -x "$HOME/.local/bin/piercing-notify" ]; then
        "$HOME/.local/bin/piercing-notify" --key "$key" --urgency "$urgency" --timeout "$timeout" \
            "$summary" "$body" >/dev/null 2>&1 &
        return 0
    fi
    osascript -e "display notification \"$(_px_osa_escape "$body")\" with title \"$(_px_osa_escape "$summary")\"" \
        >/dev/null 2>&1 || true
}

# osd ICON SUMMARY VALUE(0-100): macOS draws its own volume/brightness HUD;
# this posts a plain notification for the cases that have none (mic).
osd() {
    notify_replace osd low 1500 "$1" "$2" "$3%"
}

# ---------------------------------------------------------------------------
# Session / window manager detection
#   detect_wm -> rift|aerospace|macos|tty
# ---------------------------------------------------------------------------
detect_wm() {
    if pgrep -x rift >/dev/null 2>&1; then echo rift
    elif pgrep -x AeroSpace >/dev/null 2>&1; then echo aerospace
    elif [ -n "${TERM_PROGRAM:-}" ] || pgrep -x WindowServer >/dev/null 2>&1; then echo macos
    else echo tty
    fi
}

is_wayland() { return 1; }

# clip_copy : stdin -> clipboard
clip_copy() { pbcopy; }

# menu_select "Prompt" : stdin lines -> chosen line. gum in a terminal,
# otherwise an AppleScript list picker (no rofi/fuzzel on macOS).
menu_select() {
    local prompt="${1:-Select}"
    if [ -t 0 ] && [ -t 1 ] && command_exists gum; then
        gum filter --placeholder "$prompt"
        return
    fi
    local items list
    items=$(cat)
    [ -n "$items" ] || return 1
    list=$(printf '%s\n' "$items" | while IFS= read -r l; do printf '"%s",' "$(_px_osa_escape "$l")"; done)
    list="{${list%,}}"
    osascript -e "set r to choose from list $list with prompt \"$(_px_osa_escape "$prompt")\"" \
              -e 'if r is false then return ""' -e 'return item 1 of r' 2>/dev/null | grep .
}
