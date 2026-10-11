#!/usr/bin/env bash
# GitHub.com/PiercingXX

# User Management Script (macOS: sysadminctl / dscl / dseditgroup)

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Local accounts only (UID >= 500), not the _system ones
list_users() {
    dscl . -list /Users UniqueID | awk '$2 >= 500 && $1 !~ /^_/ { print $1 }'
}

is_admin() {
    dseditgroup -o checkmember -m "$1" admin >/dev/null 2>&1
}

while true; do
    clear
    action=$(gum choose --header="User Management" "List Users" "Add User" "Remove User" "Change Password" "Make Admin" "Remove Admin" "Back")
    case "$action" in
        "List Users")
            for u in $(list_users); do
                if is_admin "$u"; then
                    echo "  $u (admin)"
                else
                    echo "  $u"
                fi
            done
            ;;
        "Add User")
            read -p "Enter new username: " username
            read -p "Enter full name: " fullname
            admin_flag=()
            if gum confirm "Make $username an administrator?"; then
                admin_flag=(-admin)
            fi
            # "-" makes sysadminctl prompt for the new password
            sudo sysadminctl -addUser "$username" -fullName "${fullname:-$username}" -password - "${admin_flag[@]}" \
                && echo "User $username added."
            ;;
        "Remove User")
            read -p "Enter username to remove: " username
            if gum confirm "Delete $username and their home folder?"; then
                sudo sysadminctl -deleteUser "$username" && echo "User $username removed."
            fi
            ;;
        "Change Password")
            read -p "Enter username: " username
            if [ "$username" = "$(id -un)" ]; then
                # passwd keeps your login keychain in sync
                passwd
            else
                sudo sysadminctl -resetPasswordFor "$username" -newPassword -
            fi
            ;;
        "Make Admin")
            read -p "Enter username: " username
            sudo dseditgroup -o edit -a "$username" -t user admin && echo "$username is now an administrator."
            ;;
        "Remove Admin")
            read -p "Enter username: " username
            if [ "$username" = "$(id -un)" ] && ! gum confirm "Remove admin rights from yourself?"; then
                :
            else
                sudo dseditgroup -o edit -d "$username" -t user admin && echo "$username is no longer an administrator."
            fi
            ;;
        "Back"|"")
            break
            ;;
    esac
    echo "Press Enter to continue..."
    read
    clear
    # Loop back to menu
    continue
    break
    done
