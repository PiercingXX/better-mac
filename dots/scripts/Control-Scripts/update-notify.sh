#!/usr/bin/env bash
# GitHub.com/PiercingXX
# One-shot update availability notification (run once at login).
# macOS port (better-mac): counts come from update-count.sh (Homebrew
# formulae + casks, and macOS softwareupdate in place of the AUR). The
# update-system.sh lock is the lib's shlock PID file in $TMPDIR (no flock).

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

COUNTER="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/update-count.sh"
STATE_TIMEOUT=4000

# Stay quiet while update-system.sh is mid-upgrade (single_instance holds
# this lock with its PID inside)
update_lock="${TMPDIR:-/tmp}"
update_lock="${update_lock%/}/piercingxx-update-system.lock"
if [ -e "$update_lock" ] && kill -0 "$(cat "$update_lock" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi

[ -x "$COUNTER" ] || exit 0
read -r repo aur total < <("$COUNTER" --refresh)

[[ "$total" =~ ^[0-9]+$ ]] && (( total > 0 )) || exit 0

body="$total packages can be updated"
if (( aur > 0 )); then
    body="$repo from Homebrew, $aur macOS update(s)"
fi
notify_replace update-notify low "$STATE_TIMEOUT" software-update-available "Updates available" "$body"
