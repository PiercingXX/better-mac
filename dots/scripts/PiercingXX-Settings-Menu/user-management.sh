#!/usr/bin/env bash
# GitHub.com/PiercingXX
# User Management: add/remove users, passwords, and group membership.
# macOS port (better-mac): accounts come from Directory Services (dscl) and
# are changed with sysadminctl and dseditgroup; "admin" is the sudo group.
# New users get a Secure Token (FileVault unlock) when you have one.

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"
detect_distro

command_exists gum || die "gum is required for this menu."

me="$(id -un)"

# Human accounts: UID 500-59999, not the _service ones, with a real shell
human_users() {
    local u
    dscl . -list /Users UniqueID | awk '$2 >= 500 && $2 < 60000 && $1 !~ /^_/ {print $1}' \
        | while IFS= read -r u; do
            dscl . -read "/Users/$u" UserShell 2>/dev/null | grep -qE '(nologin|false)$' || echo "$u"
        done
}

# Admin group used for sudo on macOS
admin_group() {
    echo admin
}

user_exists() {
    dscl . -read "/Users/$1" UniqueID >/dev/null 2>&1
}

valid_username() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

pick_user() {
    local header="$1" include_self="${2:-1}" list
    list=$(human_users)
    [ "$include_self" = 1 ] || list=$(printf '%s\n' "$list" | grep -vx "$me")
    [ -n "$list" ] || { warn "No matching users."; return 1; }
    printf '%s\n' "$list" | gum choose --header "$header"
}

add_user() {
    local name fullname shell admin
    name=$(gum input --placeholder "new username (lowercase, a-z 0-9 _ -)")
    [ -n "$name" ] || return 0
    valid_username "$name" || { err "Invalid username: $name"; return 1; }
    user_exists "$name" && { err "User $name already exists."; return 1; }
    fullname=$(gum input --placeholder "full name (shown at login)" --value "$name") || return 0

    shell=$(grep -E '^/' /etc/shells 2>/dev/null | grep -vE 'nologin|false' | sort -u \
        | gum choose --header "Login shell for $name" --selected /bin/zsh) || return 0
    [ -n "$shell" ] || shell=/bin/zsh

    admin=$(admin_group)
    local opts=()
    if gum confirm "Give $name admin rights (add to $admin)?" --default=false; then
        opts+=(-admin)
    fi
    # Authenticating as a Secure Token holder passes a token on, so the new
    # user can unlock FileVault
    if sysadminctl -secureTokenStatus "$me" 2>&1 | grep -q ENABLED; then
        say "You'll be asked for your own password (for the Secure Token), then $name's."
        opts+=(-adminUser "$me" -adminPassword -)
    fi

    # "-" makes sysadminctl prompt for the password instead of taking it as an argument
    sudo sysadminctl -addUser "$name" -fullName "${fullname:-$name}" -shell "$shell" \
        -password - "${opts[@]}" || return 1
    user_exists "$name" || { err "User $name was not created."; return 1; }
    ok "User $name created."
}

remove_user() {
    local name uid
    name=$(pick_user "Remove which user?" 0) || return 0
    [ -n "$name" ] || return 0
    uid=$(id -u "$name" 2>/dev/null)
    if [ "$name" = root ] || [ "$name" = "$me" ] || [ -z "$uid" ] || [ "$uid" -lt 500 ]; then
        err "Refusing to remove $name."
        return 1
    fi
    dscl . -read "/Users/$name" RealName UniqueID NFSHomeDirectory UserShell 2>/dev/null \
        | awk '/^[A-Za-z]+:$/ {key = $1; next} key != "" {sub(/^ +/, ""); print key, $0; key = ""; next} {print}' \
        | sed \
        -e 's/^RealName:/Name:/' -e 's/^UniqueID:/UID:/' -e 's/^NFSHomeDirectory:/Home:/' -e 's/^UserShell:/Shell:/'
    echo "Groups: $(id -nG "$name" 2>/dev/null)"
    echo

    local mode
    mode=$(gum choose --header "Remove $name how?" "Keep home folder" "Delete home folder too" "Cancel") || return 0
    [ "$mode" = "Cancel" ] || [ -z "$mode" ] && return 0

    local typed
    typed=$(gum input --placeholder "type '$name' to confirm")
    [ "$typed" = "$name" ] || { warn "Names didn't match; nothing removed."; return 0; }

    local flag=()
    [ "$mode" = "Keep home folder" ] && flag=(-keepHome)
    sudo sysadminctl -deleteUser "$name" "${flag[@]}" && ok "User $name removed."
}

change_password() {
    local name
    name=$(pick_user "Change password for?") || return 0
    [ -n "$name" ] || return 0
    if [ "$name" = "$me" ]; then
        # passwd keeps your login keychain in sync
        passwd
    else
        warn "$name's login keychain keeps the old password; they'll be asked to update it."
        sudo sysadminctl -resetPasswordFor "$name" -newPassword -
    fi
}

manage_groups() {
    local name action group
    name=$(pick_user "Manage groups for?") || return 0
    [ -n "$name" ] || return 0
    while true; do
        clear
        echo "User: $name"
        echo "Groups: $(id -nG "$name" 2>/dev/null)"
        echo
        action=$(gum choose --header "Groups for $name" "Add to group" "Remove from group" "Back") || return 0
        case "$action" in
            "Add to group")
                group=$(dscl . -list /Groups | sort | gum filter --placeholder "group to add $name to") || continue
                [ -n "$group" ] || continue
                sudo dseditgroup -o edit -a "$name" -t user "$group"
                ;;
            "Remove from group")
                # everyone/localaccounts are computed, not real memberships
                group=$(id -nG "$name" | tr ' ' '\n' | grep -vxE "$(id -gn "$name")|everyone|localaccounts" \
                    | gum choose --header "Remove $name from") || continue
                [ -n "$group" ] || continue
                if [ "$name" = "$me" ] && [ "$group" = "$(admin_group)" ]; then
                    gum confirm "Remove yourself from $group? You will lose admin rights and sudo." --default=false || continue
                fi
                sudo dseditgroup -o edit -d "$name" -t user "$group"
                ;;
            *) return 0 ;;
        esac
        pause
    done
}

while true; do
    clear
    action=$(gum choose --header="User Management" "Add User" "Remove User" "Change Password" "Manage Groups" "Back")
    case "$action" in
        "Add User")        add_user ;;
        "Remove User")     remove_user ;;
        "Change Password") change_password ;;
        "Manage Groups")   manage_groups; continue ;;
        "Back"|"")         break ;;
    esac
    pause
done
