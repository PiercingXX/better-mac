#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Service Manager: start/stop/restart/enable/disable services and read their logs.
# macOS port (better-mac): launchd instead of systemd. User agents are the
# gui/<uid> domain (systemd --user), system daemons the system domain (sudo
# to change), plus Homebrew services (brew services). Logs come from the
# job's stdout/stderr files, else the unified log for its program. Failed
# jobs are listed but launchd has no failed state, so no reset-failed.
# runit/OpenRC/dinit/s6 dropped.

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"
detect_distro

command_exists gum || die "gum is required for this menu."

pager() { gum pager; }

UID_GUI="gui/$(id -u)"

# ---------------------------------------------------------------------------
# launchd
# ---------------------------------------------------------------------------
job_field() { launchctl print "$1" 2>/dev/null | awk -F' = ' -v k="$2" '$1 ~ "^\t" k "$" {print $2; exit}'; }

job_logs() {
    local target="$1" out errf prog
    out=$(job_field "$target" "stdout path")
    errf=$(job_field "$target" "stderr path")
    if [ -n "$out$errf" ]; then
        local f
        for f in $(printf '%s\n' "$out" "$errf" | sort -u); do
            [ -f "$f" ] || continue
            echo "==> $f"
            tail -n 300 "$f"
            echo
        done
    else
        prog=$(job_field "$target" program)
        prog=$(basename "${prog:-${target##*/}}")
        echo "No log files; unified log for '$prog' (last hour):"
        log show --last 1h --style compact --predicate "process == \"$prog\"" 2>&1 | tail -n 300
    fi
}

launchd_job_actions() {
    local scope="$1" label="$2" action target sudo=()
    if [ "$scope" = user ]; then
        target="$UID_GUI/$label"
    else
        target="system/$label"; sudo=(sudo)
    fi
    while true; do
        clear
        launchctl print "$target" 2>&1 | grep -E $'^\t(state|pid|program|path|last exit code|runs) =' | head -n 12
        echo
        action=$(gum choose --header "$label" "Status" "Logs (last 300)" "Restart" "Start" "Stop" "Enable" "Disable" "Back") || return 0
        case "$action" in
            "Status")          launchctl print "$target" 2>&1 | pager; continue ;;
            "Logs (last 300)") job_logs "$target" 2>&1 | pager; continue ;;
            "Restart")         "${sudo[@]}" launchctl kickstart -k "$target" ;;
            "Start")           "${sudo[@]}" launchctl kickstart "$target" ;;
            "Stop")            gum confirm "Stop $label? (KeepAlive jobs come straight back)" && "${sudo[@]}" launchctl kill SIGTERM "$target" ;;
            "Enable")          "${sudo[@]}" launchctl enable "$target" ;;
            "Disable")         gum confirm "Disable $label from loading at next login/boot?" --default=false && "${sudo[@]}" launchctl disable "$target" ;;
            *) return 0 ;;
        esac
        sleep 0.5
    done
}

# "label state last-exit" for a domain
list_jobs() {
    if [ "$1" = user ]; then
        launchctl list 2>/dev/null | awk 'NR>1 {printf "%-60s %-8s %s\n", $3, ($1=="-" ? "stopped" : "running"), $2}'
    else
        launchctl print system 2>/dev/null | sed -n '/^\tservices = {/,/^\t}/p' \
            | awk 'NF==3 {printf "%-60s %-8s %s\n", $3, ($1==0 ? "stopped" : "running"), $2}'
    fi
}

failed_jobs() {
    echo "User agents (last exit non-zero, not running):"
    launchctl list 2>/dev/null | awk 'NR>1 && $1=="-" && $2!=0 {printf "  %-60s exit %s\n", $3, $2}'
    if [ "$PKG" = brew ]; then
        echo
        echo "Homebrew services in error:"
        brew services list 2>/dev/null | awk 'NR>1 && $2=="error" {print "  " $1}'
    fi
}

# ---------------------------------------------------------------------------
# Homebrew services
# ---------------------------------------------------------------------------
brew_service_actions() {
    local svc="$1" action logs
    while true; do
        clear
        brew services info "$svc" 2>&1 | head -n 12
        echo
        action=$(gum choose --header "$svc (brew)" "Status" "Logs (last 300)" "Restart" "Start" "Stop" "Enable" "Disable" "Back") || return 0
        case "$action" in
            "Status")          brew services info "$svc" 2>&1 | pager; continue ;;
            "Logs (last 300)")
                logs=$(brew services info "$svc" --json 2>/dev/null | sed -n 's/.*"\(error_\)\{0,1\}log_path": "\(.*\)".*/\2/p' | sort -u)
                if [ -n "$logs" ]; then
                    for f in $logs; do [ -f "$f" ] && { echo "==> $f"; tail -n 300 "$f"; echo; }; done | pager
                else
                    echo "$svc has no log files." | pager
                fi
                continue ;;
            "Restart")         brew services restart "$svc" ;;
            "Start")           brew services run "$svc" ;;
            "Stop")            gum confirm "Stop $svc?" && brew services kill "$svc" ;;
            "Enable")          brew services start "$svc" ;;
            "Disable")         gum confirm "Stop $svc and remove it from login?" --default=false && brew services stop "$svc" ;;
            *) return 0 ;;
        esac
        sleep 0.5
    done
}

launchd_menu() {
    local choice scope label svc
    local -a menu=("User agents" "System daemons")
    [ "$PKG" = brew ] && menu+=("Homebrew services")
    menu+=("Failed jobs" "Back")
    while true; do
        clear
        choice=$(gum choose --header "Services (launchd)" "${menu[@]}") || return 0
        case "$choice" in
            "User agents")    scope="user" ;;
            "System daemons") scope="system" ;;
            "Homebrew services")
                svc=$(brew services list 2>/dev/null | awk 'NR>1 {printf "%-30s %s\n", $1, $2}' \
                    | gum filter --placeholder "search Homebrew services" | awk '{print $1}') || continue
                [ -n "$svc" ] && brew_service_actions "$svc"
                continue ;;
            "Failed jobs")
                failed_jobs | pager
                continue ;;
            *) return 0 ;;
        esac
        label=$(list_jobs "$scope" | sort \
            | gum filter --placeholder "search $scope jobs" | awk '{print $1}') || continue
        [ -n "$label" ] && launchd_job_actions "$scope" "$label"
    done
}

case "$INIT" in
    launchd) launchd_menu ;;
    *) die "Unknown init system; can't manage services from here." ;;
esac
