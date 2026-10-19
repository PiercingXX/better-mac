#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Shared pending-update counter for bars and notifiers.
#
# Usage: update-count.sh            -> "repo aur total"
#        update-count.sh --total    -> "total"
#        update-count.sh --json     -> {"repo":N,"aur":N,"total":N,"packages":N,"updates":N,"text":"N","tooltip":"...","class":"..."}
#        update-count.sh --list     -> one pending package per line
#        add --refresh to bypass the cache
#
# macOS: "repo" = outdated Homebrew formulae + casks, "aur" = macOS
# updates from softwareupdate (minor ones only, like update-system.sh).
# --refresh also runs `brew update` (metadata only, like checkupdates'
# private db sync); a plain run uses Homebrew's last fetched index.
# Results are cached for PX_UPDATE_TTL seconds (default 300) so several
# bars polling at once share one check.
#
# macOS port (better-mac): pacman/apt/dnf/... and the AUR helpers are
# replaced by `brew outdated` and `softwareupdate --list` (the second column
# keeps the "aur" name so callers parse it unchanged). flock(1) doesn't
# exist, so the checker lock is a shlock(1) PID file with a wait loop;
# stat -c is BSD /usr/bin/stat -f (absolute: GNU stat may be first on PATH).

mode="plain"
refresh=0
for arg in "$@"; do
    case "$arg" in
        --json)    mode="json" ;;
        --total)   mode="total" ;;
        --list)    mode="list" ;;
        --refresh) refresh=1 ;;
        -h|--help) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    esac
done

# Bars and AeroSpace don't load ~/.bashrc
case ":$PATH:" in
    *:/opt/homebrew/bin:*) ;;
    *) PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" ;;
esac

command_exists() { command -v "$1" >/dev/null 2>&1; }

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/piercingxx"
cache_file="$cache_dir/updates"
list_file="$cache_dir/updates.list"
lock_file="$cache_dir/updates.lock"
ttl="${PX_UPDATE_TTL:-300}"
mkdir -p "$cache_dir"

cache_fresh() {
    [ "$refresh" -eq 0 ] || return 1
    [ -s "$cache_file" ] || return 1
    local now mtime
    now=$(date +%s)
    mtime=$(/usr/bin/stat -f %m "$cache_file" 2>/dev/null || echo 0)
    [ $((now - mtime)) -lt "$ttl" ]
}

# repo_updates / aur_updates print one package per line
repo_updates() {
    command_exists brew || return 0
    if [ "$refresh" -eq 1 ]; then
        brew update --quiet >/dev/null 2>&1
    fi
    # "name (installed) < latest"; never let outdated trigger its own update
    HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --verbose 2>/dev/null | sed '/^$/d'
}

aur_updates() {
    command_exists softwareupdate || return 0
    # One label per update; slow (network), hence the cache. A major macOS
    # upgrade is skipped like update-system.sh does (it won't install it).
    local major
    major=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
    softwareupdate --list 2>/dev/null | awk -v major="$major" '
        /^\* Label: / { sub(/^\* Label: /, ""); label = $0; next }
        label != "" && /Title:/ {
            v = ""; t = ""
            if (match($0, /Title: [^,]*/))   t = substr($0, RSTART + 7, RLENGTH - 7)
            if (match($0, /Version: [^,]*/)) v = substr($0, RSTART + 9, RLENGTH - 9)
            split(v, parts, ".")
            if (!(t ~ /^macOS/ && major != "" && parts[1] != major)) print label
            label = ""
        }'
}

installed_count() {
    if command_exists brew; then
        { brew list --formula -1 2>/dev/null; brew list --cask -1 2>/dev/null; } | wc -l | tr -d ' '
    else echo 0
    fi
}

refresh_cache() {
    local repo_list aur_list repo aur
    repo_list=$(repo_updates)
    aur_list=$(aur_updates)
    repo=$(printf '%s' "$repo_list" | grep -c . || true)
    aur=$(printf '%s' "$aur_list" | grep -c . || true)
    {
        [ -n "$repo_list" ] && printf '%s\n' "$repo_list"
        [ -n "$aur_list" ] && printf '%s\n' "$aur_list" | sed 's/^/[macos] /'
    } > "$list_file.tmp"
    mv -f "$list_file.tmp" "$list_file"
    printf '%s %s\n' "${repo:-0}" "${aur:-0}" > "$cache_file.tmp"
    mv -f "$cache_file.tmp" "$cache_file"
}

# One checker at a time; whoever waited re-reads the fresh cache.
# shlock refuses while the PID inside is alive and clears stale locks.
waited=0
while ! shlock -p $$ -f "$lock_file" 2>/dev/null && [ "$waited" -lt 120 ]; do
    sleep 1
    waited=$((waited + 1))
done
if [ "$waited" -lt 120 ]; then
    trap 'rm -f "$lock_file"' EXIT
    cache_fresh || refresh_cache
    rm -f "$lock_file"
    trap - EXIT
fi

read -r repo aur < "$cache_file" 2>/dev/null
repo=${repo:-0}
aur=${aur:-0}
total=$((repo + aur))

case "$mode" in
    total) echo "$total" ;;
    list)  cat "$list_file" 2>/dev/null ;;
    json)
        tooltip=$(head -n 40 "$list_file" 2>/dev/null \
            | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e $'s/\t/ /g' \
            | awk 'BEGIN{ORS=""} {if (NR>1) print "\\n"; print}')
        [ "$total" -gt 40 ] && tooltip="$tooltip\\n…"
        [ "$total" -eq 0 ] && tooltip="System is up to date"
        class="none"
        [ "$total" -gt 0 ] && class="pending"
        printf '{"repo":%d,"aur":%d,"total":%d,"packages":%d,"updates":%d,"text":"%d","tooltip":"%s","class":"%s"}\n' \
            "$repo" "$aur" "$total" "$(installed_count)" "$total" "$total" "$tooltip" "$class"
        ;;
    *) echo "$repo $aur $total" ;;
esac
