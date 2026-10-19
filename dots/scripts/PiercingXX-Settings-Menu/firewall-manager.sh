#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Firewall Manager: ufw (preferred, linux-mod enables it) or firewalld.
#
# macOS port (better-mac): the built-in Application Firewall (socketfilterfw).
# It filters incoming connections per app, not per port, and never blocks
# outgoing, so the presets and allow/deny entries are apps; changes ask for
# sudo, reading state doesn't. Added: stealth mode. Dropped: firewalld and
# installing ufw (the firewall ships with macOS).

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"
detect_distro

command_exists gum || die "gum is required for this menu."

FW=/usr/libexec/ApplicationFirewall/socketfilterfw
[ -x "$FW" ] || die "$FW not found."

# name|app paths (first one present is used, ; separated)
PRESETS=(
    "SSH|/usr/libexec/sshd-keygen-wrapper"
    "KDE Connect / GSConnect|/Applications/KDE Connect.app;/Applications/kdeconnect-app.app"
    "LocalSend|/Applications/LocalSend.app"
    "Syncthing|/Applications/Syncthing.app;/opt/homebrew/bin/syncthing"
)

pager() {
    if command_exists gum; then gum pager; else less -R; fi
}

# fw_rules -> "path<TAB>Allow|Block" per app rule
fw_rules() {
    "$FW" --listapps 2>/dev/null | awk '
        /^[0-9]+ : / { sub(/^[0-9]+ : /, ""); sub(/[[:space:]]+$/, ""); path = $0; next }
        path != "" && /\((Allow|Block) incoming/ { match($0, /(Allow|Block)/); print path "\t" substr($0, RSTART, RLENGTH); path = "" }'
}

# fw_allow|fw_block PATH: add the app if it has no rule yet, then set it
fw_allow() { sudo "$FW" --add "$1" >/dev/null && sudo "$FW" --unblockapp "$1"; }
fw_block() { sudo "$FW" --add "$1" >/dev/null && sudo "$FW" --blockapp "$1"; }

# pick_app -> path of an app in /Applications or a path typed in
pick_app() {
    local pick
    pick=$( { printf '%s\n' "Enter a path..."; find /Applications "$HOME/Applications" -maxdepth 2 -name '*.app' 2>/dev/null | sort; } \
        | gum filter --placeholder "app to allow or block") || return 1
    if [ "$pick" = "Enter a path..." ]; then
        pick=$(gum input --placeholder "/path/to/App.app or /path/to/binary") || return 1
    fi
    [ -e "$pick" ] || { err "Not found: $pick"; return 1; }
    printf '%s\n' "$pick"
}

fw_status() {
    "$FW" --getglobalstate
    "$FW" --getstealthmode
    "$FW" --getblockall
    "$FW" --getallowsigned
    echo
    echo "App rules:"
    fw_rules | awk -F '\t' '{ printf "  %-6s %s\n", $2, $1 }'
}

fw_menu() {
    local action
    while true; do
        clear
        "$FW" --getglobalstate
        action=$(gum choose --header "Firewall (macOS Application Firewall)" \
            "Status (verbose)" "Enable" "Disable" "Stealth mode on" "Stealth mode off" \
            "Allow a preset" "Allow an app" "Block an app" "Delete a rule" "Back") || return 0
        case "$action" in
            "Status (verbose)") fw_status | pager; continue ;;
            "Enable")
                # Keep a remote session's sshd reachable
                if [ -n "${SSH_CONNECTION:-}" ]; then
                    fw_allow /usr/libexec/sshd-keygen-wrapper >/dev/null
                fi
                sudo "$FW" --setglobalstate on ;;
            "Disable")
                if [ -n "${SSH_CONNECTION:-}" ] || gum confirm "Disable the firewall?" --default=false; then
                    sudo "$FW" --setglobalstate off
                fi ;;
            "Stealth mode on")  sudo "$FW" --setstealthmode on ;;
            "Stealth mode off") sudo "$FW" --setstealthmode off ;;
            "Allow a preset")
                local names=() row name paths p found
                for row in "${PRESETS[@]}"; do names+=("${row%%|*}"); done
                name=$(printf '%s\n' "${names[@]}" | gum choose --header "Allow which preset?") || continue
                for row in "${PRESETS[@]}"; do
                    [ "${row%%|*}" = "$name" ] || continue
                    found=""
                    IFS=';' read -ra paths <<< "${row#*|}"
                    for p in "${paths[@]}"; do
                        [ -e "$p" ] && { found="$p"; break; }
                    done
                    if [ -n "$found" ]; then
                        fw_allow "$found"
                    else
                        err "$name isn't installed (looked for: ${paths[*]})."
                    fi
                done ;;
            "Allow an app"|"Block an app")
                local app
                app=$(pick_app) || { pause; continue; }
                if [ "$action" = "Block an app" ]; then fw_block "$app"; else fw_allow "$app"; fi ;;
            "Delete a rule")
                local rule path
                rule=$(fw_rules | awk -F '\t' '{ printf "%-6s %s\n", $2, $1 }' | gum choose --header "Delete which rule?") || continue
                [ -n "$rule" ] || continue
                path="${rule#* }"; path="${path#"${path%%[! ]*}"}"
                gum confirm "Delete: $rule ?" --default=false && sudo "$FW" --remove "$path" ;;
            *) return 0 ;;
        esac
        pause
    done
}

fw_menu
