#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Clean System: pick what to clean, see sizes first, confirm, get a
# before/after report. Only touches Homebrew's cache (via brew itself) and
# known cache/log/trash paths in your own $HOME. Never touches Downloads,
# other users' homes, /tmp or anything SIP protects.
#
# Usage: clean-system.sh                     interactive picker
#        clean-system.sh --categories a,b    run these categories (see --list)
#        clean-system.sh --yes               no prompts (safe defaults, or --categories;
#                                            orphans only when named in --categories)
#        clean-system.sh --dry-run           show what would run, change nothing
#        clean-system.sh --summary           reclaimable sizes only (no sudo, for bars)
#        clean-system.sh --setup             check automatic maintenance (read only)
#        clean-system.sh --list              list category ids
# Env:   PX_NO_PAUSE=1 skips the final "Press Enter" when run from a menu
#        that pauses on its own.
#
# macOS port (better-mac): pkgcache/orphans are brew cleanup/autoremove;
# journal is old files in ~/Library/Logs (incl. crash reports); thumbnails is
# the QuickLook cache; trash is ~/.Trash (via Finder), trash-cli and volume
# .Trashes; failed_units reports errored brew services and LaunchAgents;
# browsers/devcaches use ~/Library/Caches paths; appcaches (new, never
# unattended) empties ~/Library/Caches and ~/.cache. Nothing needs sudo.
# Dropped (no macOS meaning): aur, tmpfiles, flatpak, snap, pacman_lock,
# config_files, kernel_modules, and the fstrim/paccache/reflector timers
# (macOS trims and brew prunes on their own; --setup only reports).

set -uo pipefail

# shellcheck source=../lib/common.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

DRY_RUN=0
ASSUME_YES=0
CATEGORIES=""
MODE="menu"

usage() { sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run)   DRY_RUN=1 ;;
        -y|--yes)       ASSUME_YES=1 ;;
        --categories)   CATEGORIES="${2:-}"; shift ;;
        --categories=*) CATEGORIES="${1#--categories=}" ;;
        --summary)      MODE="summary" ;;
        --setup)        MODE="setup" ;;
        --list)         MODE="list" ;;
        -h|--help)      usage; exit 0 ;;
        *)              err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

refuse_root
detect_distro

LOG_FILE="$PX_STATE_DIR/clean.log"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
LIB_CACHES="$HOME/Library/Caches"
LIB_LOGS="$HOME/Library/Logs"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    mkdir -p "$PX_STATE_DIR"
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

# run cmd... : print in dry-run, otherwise execute and log
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  %s[dry-run]%s %s\n' "$BLUE" "$NC" "$*"
        return 0
    fi
    log "run: $*"
    "$@"
    local rc=$?
    [ "$rc" -ne 0 ] && log "  exit $rc"
    return "$rc"
}

# ask "Question?" : yes under --yes or --dry-run, otherwise confirm
ask() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ "$DRY_RUN" -eq 1 ] && return 0
    confirm "$1"
}

# ask_manual "Question?" : for steps that should never run unattended.
# --yes only reports; --dry-run shows the command.
ask_manual() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    [ "$ASSUME_YES" -eq 1 ] && return 1
    confirm "$1"
}

# No timeout(1) on stock macOS; coreutils has it as gtimeout
px_timeout() {
    if command_exists timeout; then timeout "$@"
    elif command_exists gtimeout; then gtimeout "$@"
    else shift; "$@"
    fi
}

# bytes_of path... : total bytes of the paths that exist (du -b is GNU only)
bytes_of() {
    local p existing=() k
    for p in "$@"; do [ -e "$p" ] && existing+=("$p"); done
    [ ${#existing[@]} -gt 0 ] || { echo 0; return; }
    k=$(du -sck "${existing[@]}" 2>/dev/null | tail -n1 | cut -f1)
    echo $(( ${k:-0} * 1024 ))
}

human() {
    awk -v b="${1:-0}" 'BEGIN { split("B KB MB GB TB", u); i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i == 1 ? "%d%s\n" : "%.1f%s\n"), b, u[i] }'
}

# empty_dir dir : delete the contents (dotfiles too), keep the dir
empty_dir() {
    [ -d "$1" ] || return 0
    run find "$1" -mindepth 1 -delete
}

# Free space per volume ("dev bytes mountpoint"), deduplicated by device.
# Everything cleaned here lives on the Data volume; / is the sealed system.
fs_avail() {
    df -k "$HOME" /opt/homebrew 2>/dev/null | awk 'NR>1 && !seen[$1]++ {print $1, $4 * 1024, $NF}'
}

section() { printf '\n%s== %s ==%s\n' "$BLUE" "$*" "$NC"; }

# ---------------------------------------------------------------------------
# Category registry
# ---------------------------------------------------------------------------
ALL_CATEGORIES=(pkgcache orphans journal containers thumbnails
                devcaches browsers appcaches trash
                failed_units broken_symlinks)
DEFAULT_CATEGORIES=(pkgcache orphans journal thumbnails failed_units)
# --yes without --categories: never removes packages unattended
YES_DEFAULT_CATEGORIES=(pkgcache journal thumbnails failed_units)
SUDO_CATEGORIES=" "

declare -A LABEL=(
    [pkgcache]="Homebrew cache & old versions"
    [orphans]="Orphaned formulae (brew autoremove)"
    [journal]="Old user logs & crash reports (2+ weeks)"
    [containers]="Docker / Podman leftovers"
    [thumbnails]="QuickLook thumbnail cache"
    [devcaches]="Developer caches (uv/pip/npm/cargo/go/Xcode...)"
    [browsers]="Browser caches (closed browsers only)"
    [appcaches]="All app caches (~/Library/Caches; asks)"
    [trash]="Empty trash"
    [failed_units]="Failed services & LaunchAgents (report only)"
    [broken_symlinks]="Broken symlinks in \$HOME (report only)"
    [setup]="Maintenance check (TRIM, brew auto-cleanup)"
)

# ---------------------------------------------------------------------------
# pkgcache
# ---------------------------------------------------------------------------
pkgcache_dirs() {
    [ "$PKG" = brew ] && brew --cache 2>/dev/null
}

cat_pkgcache_available() { [ "$PKG" = brew ]; }

cat_pkgcache_size() {
    local dirs total saved
    mapfile -t dirs < <(pkgcache_dirs)
    total=$(bytes_of "${dirs[@]}")
    saved=$(brew cleanup -n --prune=all -s 2>/dev/null | sed -n 's/.*free approximately \([^ ]*\) .*/\1/p')
    echo "$(human "$total") cache; cleanup frees ${saved:-0B}"
}

cat_pkgcache_run() {
    say "Removing old formula/cask versions and every cached download..."
    run brew cleanup --prune=all -s
}

# ---------------------------------------------------------------------------
# orphans
# ---------------------------------------------------------------------------
cat_orphans_available() { [ "$PKG" = brew ]; }

orphan_list() {
    brew autoremove --dry-run 2>/dev/null | awk '/^==>/ {f = 1; next} f && NF {print $1}'
}

cat_orphans_size() {
    local n
    n=$(orphan_list | grep -c .)
    echo "$n formula(e)"
}

cat_orphans_run() {
    local list
    mapfile -t list < <(orphan_list)
    if [ ${#list[@]} -eq 0 ]; then
        ok "No orphaned formulae."
        return 0
    fi
    say "Formulae installed only as dependencies and no longer needed:"
    printf '  %s\n' "${list[@]}"
    ask "Remove these ${#list[@]} formula(e) with brew autoremove?" || return 0
    # autoremove repeats on its own until nothing is left
    run brew autoremove
}

# ---------------------------------------------------------------------------
# journal : macOS's unified log manages itself; this is the per-app log
# files and crash reports under ~/Library/Logs, kept for 2 weeks.
# ---------------------------------------------------------------------------
old_log_files() { find "$LIB_LOGS" -type f -mtime +14 2>/dev/null; }

cat_journal_available() { [ -d "$LIB_LOGS" ]; }

cat_journal_size() {
    local n bytes
    n=$(old_log_files | grep -c .)
    bytes=$(old_log_files | tr '\n' '\0' | xargs -0 /usr/bin/stat -f %z 2>/dev/null | awk '{s += $1} END {print s + 0}')
    echo "$n file(s), $(human "$bytes")"
}

cat_journal_run() {
    say "Deleting files in ~/Library/Logs older than 2 weeks..."
    run find "$LIB_LOGS" -type f -mtime +14 -delete 2>/dev/null
    return 0   # some app log folders are sandboxed; skipping them is fine
}

# ---------------------------------------------------------------------------
# containers : dangling images, build cache and unused networks only.
# Stopped containers need a separate yes and are never removed under --yes.
# Volumes are never touched.
# ---------------------------------------------------------------------------
container_engines() {
    local e
    for e in docker podman; do
        command_exists "$e" && px_timeout 10 "$e" info >/dev/null 2>&1 && echo "$e"
    done
}

cat_containers_available() { command_exists docker || command_exists podman; }

cat_containers_size() {
    local e out=() r
    while read -r e; do
        r=$(px_timeout 15 "$e" system df --format '{{.Type}} {{.Reclaimable}}' 2>/dev/null \
            | awk '{t=$1; $1=""; sub(/^ /,""); printf "%s%s %s", (n++?", ":""), t, $0}' | tr ',' ';')
        out+=("$e: ${r:-?}")
    done < <(container_engines)
    [ ${#out[@]} -gt 0 ] || { echo "engine not running"; return; }
    local IFS='|'
    echo "${out[*]}"
}

cat_containers_run() {
    local e engines
    mapfile -t engines < <(container_engines)
    if [ ${#engines[@]} -eq 0 ]; then
        warn "Docker/Podman isn't running (start Docker Desktop, OrbStack, colima or 'podman machine start')."
        return 0
    fi
    for e in "${engines[@]}"; do
        say "$e disk usage:"
        "$e" system df 2>/dev/null
        if ask "Prune $e dangling images, build cache and unused networks? (volumes are kept)"; then
            run "$e" image prune -f
            [ "$e" = docker ] && run docker builder prune -f
            run "$e" network prune -f
        fi
        local stopped
        stopped=$("$e" ps -a --filter status=exited --filter status=created -q 2>/dev/null | grep -c .)
        if [ "$stopped" -gt 0 ]; then
            "$e" ps -a --filter status=exited --filter status=created --format '  {{.Names}}  ({{.Image}}, {{.Status}})' 2>/dev/null
            if ask_manual "Also remove these $stopped stopped $e container(s)?"; then
                run "$e" container prune -f
            fi
        fi
    done
}

# ---------------------------------------------------------------------------
# thumbnails : QuickLook keeps them in the per-user cache dir under /var/folders
# ---------------------------------------------------------------------------
thumbnail_dir() { echo "$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)com.apple.QuickLook.thumbnailcache"; }

cat_thumbnails_available() { command_exists qlmanage; }
cat_thumbnails_size() { human "$(bytes_of "$(thumbnail_dir)")"; }
cat_thumbnails_run() {
    run qlmanage -r cache
}

# ---------------------------------------------------------------------------
# devcaches : one line per tool "id|path|label"; cleaned with the tool's own
# command when it has one.
# ---------------------------------------------------------------------------
PIP=$(command -v pip || command -v pip3)

devcache_entries() {
    local p
    if command_exists uv; then p=$(uv cache dir 2>/dev/null); [ -d "$p" ] && echo "uv|$p|uv"; fi
    if [ -n "$PIP" ]; then p=$("$PIP" cache dir 2>/dev/null); [ -d "$p" ] && echo "pip|$p|pip"; fi
    if command_exists npm; then p="$HOME/.npm/_cacache"; [ -d "$p" ] && echo "npm|$p|npm"; fi
    if command_exists pnpm; then p=$(pnpm store path 2>/dev/null); [ -d "$p" ] && echo "pnpm|$p|pnpm store"; fi
    if command_exists yarn; then p=$(yarn cache dir 2>/dev/null); [ -d "$p" ] && echo "yarn|$p|yarn"; fi
    p="${CARGO_HOME:-$HOME/.cargo}/registry/cache"; [ -d "$p" ] && echo "cargo|$p|cargo registry"
    if command_exists go; then p=$(go env GOCACHE 2>/dev/null); [ -d "$p" ] && echo "go|$p|go build cache"; fi
    if command_exists go; then p=$(go env GOMODCACHE 2>/dev/null); [ -d "$p" ] && echo "gomod|$p|go module cache"; fi
    p="${SCCACHE_DIR:-$LIB_CACHES/Mozilla.sccache}"; [ -d "$p" ] && echo "sccache|$p|sccache"
    p="${PLAYWRIGHT_BROWSERS_PATH:-$LIB_CACHES/ms-playwright}"; [ -d "$p" ] && echo "playwright|$p|playwright browsers"
    p="$HOME/Library/Developer/Xcode/DerivedData"; [ -d "$p" ] && echo "xcode|$p|Xcode DerivedData"
}

cat_devcaches_available() { [ -n "$(devcache_entries)" ]; }

cat_devcaches_size() {
    local id path lbl paths=()
    while IFS='|' read -r id path lbl; do paths+=("$path"); done < <(devcache_entries)
    human "$(bytes_of "${paths[@]}")"
}

devcache_clean() {
    local id="$1" path="$2"
    case "$id" in
        uv)         run uv cache clean ;;
        pip)        run "$PIP" cache purge ;;
        npm)        run npm cache clean --force ;;
        pnpm)       run pnpm store prune ;;
        yarn)       run yarn cache clean ;;
        go)         run go clean -cache ;;
        gomod)      run go clean -modcache ;;
        sccache)    command_exists sccache && run sccache --stop-server >/dev/null 2>&1; empty_dir "$path" ;;
        *)          empty_dir "$path" ;;
    esac
}

cat_devcaches_run() {
    local id path lbl size entries=() options=() chosen=()
    local -A by_option=()
    while IFS='|' read -r id path lbl; do
        size=$(human "$(bytes_of "$path")")
        entries+=("$id|$path")
        options+=("$lbl ($size)")
        by_option["$lbl ($size)"]="$id|$path"
    done < <(devcache_entries)

    if [ "$ASSUME_YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
        chosen=("${options[@]}")
    elif command_exists gum; then
        mapfile -t chosen < <(printf '%s\n' "${options[@]}" | gum choose --no-limit --header "Which developer caches? (space to pick, enter to confirm)")
    else
        local o
        for o in "${options[@]}"; do
            confirm "Clear $o?" && chosen+=("$o")
        done
    fi

    local o
    for o in "${chosen[@]}"; do
        [ -n "${by_option[$o]:-}" ] || continue
        IFS='|' read -r id path <<<"${by_option[$o]}"
        say "Clearing $o"
        devcache_clean "$id" "$path"
    done
}

# ---------------------------------------------------------------------------
# browsers : cache dirs only, and only when that browser is closed
# "name|cache dir|process names (comma separated; macOS names have spaces)"
# Safari's cache is SIP/TCC protected; leave it to Safari.
# ---------------------------------------------------------------------------
browser_entries() {
    local line name dir procs
    for line in \
        "Waterfox|$LIB_CACHES/Waterfox|waterfox" \
        "Firefox|$LIB_CACHES/Firefox|firefox" \
        "LibreWolf|$LIB_CACHES/librewolf|librewolf" \
        "Zen|$LIB_CACHES/zen|zen" \
        "Chromium|$LIB_CACHES/Chromium|Chromium" \
        "Chrome|$LIB_CACHES/Google/Chrome|Google Chrome" \
        "Brave|$LIB_CACHES/BraveSoftware|Brave Browser" \
        "Vivaldi|$LIB_CACHES/Vivaldi|Vivaldi"; do
        IFS='|' read -r name dir procs <<<"$line"
        [ -d "$dir" ] && echo "$name|$dir|$procs"
    done
}

browser_running() {
    local p list
    IFS=',' read -ra list <<<"$1"
    for p in "${list[@]}"; do pgrep -x "$p" >/dev/null 2>&1 && return 0; done
    return 1
}

cat_browsers_available() { [ -n "$(browser_entries)" ]; }

cat_browsers_size() {
    local name dir procs paths=()
    while IFS='|' read -r name dir procs; do paths+=("$dir"); done < <(browser_entries)
    human "$(bytes_of "${paths[@]}")"
}

cat_browsers_run() {
    local name dir procs
    while IFS='|' read -r name dir procs; do
        if browser_running "$procs"; then
            warn "  $name is running; quit it to clear its cache."
            continue
        fi
        say "Clearing $name cache ($(human "$(bytes_of "$dir")"))"
        empty_dir "$dir"
    done < <(browser_entries)
}

# ---------------------------------------------------------------------------
# appcaches : every app's cache folder (apps rebuild them, but some are big
# and slow to refill). com.apple.* belong to always-running system daemons
# and are often protected, so they're skipped.
# ---------------------------------------------------------------------------
appcache_dirs() {
    local d
    for d in "$LIB_CACHES"/*/ "$CACHE_HOME"/*/; do
        d="${d%/}"
        [ -d "$d" ] || continue
        case "$(basename "$d")" in com.apple.*) continue ;; esac
        echo "$d"
    done
}

cat_appcaches_available() { [ -n "$(appcache_dirs)" ]; }

cat_appcaches_size() {
    local dirs
    mapfile -t dirs < <(appcache_dirs)
    human "$(bytes_of "${dirs[@]}")"
}

cat_appcaches_run() {
    local dirs d
    mapfile -t dirs < <(appcache_dirs)
    say "Largest app caches:"
    du -sk "${dirs[@]}" 2>/dev/null | sort -rn | head -n 15 \
        | while read -r k d; do printf '  %-60s %s\n' "${d/#$HOME/\~}" "$(human $(( k * 1024 )))"; done
    say "Running apps may need a restart to notice."
    ask_manual "Empty all ${#dirs[@]} app cache folders?" || return 0
    for d in "${dirs[@]}"; do
        empty_dir "$d" 2>/dev/null
    done
    return 0
}

# ---------------------------------------------------------------------------
# trash : Finder Trash (all volumes), trash-cli's (the rm alias), and
# per-volume .Trashes/$UID
# ---------------------------------------------------------------------------
trash_dirs() {
    local uid d
    uid=$(id -u)
    [ -d "$HOME/.Trash" ] && echo "$HOME/.Trash"
    [ -d "$DATA_HOME/Trash" ] && echo "$DATA_HOME/Trash"
    for d in /Volumes/*/.Trashes/"$uid"; do
        [ -d "$d" ] && echo "$d"
    done
}

cat_trash_available() { [ -n "$(trash_dirs)" ]; }

cat_trash_size() {
    local dirs
    mapfile -t dirs < <(trash_dirs)
    # ~/.Trash reads as 0 unless the terminal has Full Disk Access
    human "$(bytes_of "${dirs[@]}")"
}

cat_trash_run() {
    local dirs d
    mapfile -t dirs < <(trash_dirs)
    say "Trash locations:"
    for d in "${dirs[@]}"; do printf '  %s (%s)\n' "$d" "$(human "$(bytes_of "$d")")"; done
    ask "Permanently delete everything in the trash?" || return 0
    run osascript -e 'tell application "Finder" to empty trash' 2>/dev/null
    # Anything Finder couldn't reach (trash-cli, Finder not allowed to be scripted)
    for d in "${dirs[@]}"; do
        if [ "$d" = "$DATA_HOME/Trash" ]; then
            empty_dir "$d/files"
            empty_dir "$d/info"
            empty_dir "$d/expunged"
        else
            empty_dir "$d" 2>/dev/null
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# failed_units : launchd has no failed state to reset; report brew services
# in error and your own LaunchAgents whose last run exited non-zero.
# ---------------------------------------------------------------------------
cat_failed_units_available() { return 0; }

failed_units() {
    local f label
    [ "$PKG" = brew ] && brew services list 2>/dev/null | awk 'NR>1 && $2=="error" {print "brew:   " $1}'
    for f in "$HOME"/Library/LaunchAgents/*.plist; do
        [ -f "$f" ] || continue
        label=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$f" 2>/dev/null) || continue
        case "$label" in homebrew.mxcl.*|sh.brew.*) continue ;; esac
        launchctl list 2>/dev/null | awk -v l="$label" '$3==l && $1=="-" && $2!=0 {print "agent:  " l " (exit " $2 ")"}'
    done
}

cat_failed_units_size() { echo "$(failed_units | grep -c .) job(s)"; }

cat_failed_units_run() {
    local units
    mapfile -t units < <(failed_units)
    if [ ${#units[@]} -eq 0 ]; then
        ok "No failed services or LaunchAgents."
        return 0
    fi
    say "Failed jobs (check with 'brew services info NAME' or the Service Manager):"
    printf '  %s\n' "${units[@]}"
}

# ---------------------------------------------------------------------------
# broken_symlinks : report only, never deleted (many are intentional)
# ---------------------------------------------------------------------------
cat_broken_symlinks_available() { return 0; }
cat_broken_symlinks_size() { echo "report only"; }

cat_broken_symlinks_run() {
    local links out="$PX_STATE_DIR/broken-symlinks.txt"
    say "Scanning \$HOME for broken symlinks (skipping Library, caches, .git, node_modules)..."
    # BSD find has no -xtype; test each link instead
    mapfile -t links < <(px_timeout 120 find "$HOME" -xdev \
        \( -path "$HOME/Library" -o -path "$HOME/.Trash" -o -path "$CACHE_HOME" -o -name .git -o -name node_modules -o -path "$DATA_HOME/Trash" \) -prune \
        -o -type l -print 2>/dev/null | while IFS= read -r l; do [ -e "$l" ] || printf '%s\n' "$l"; done)
    if [ ${#links[@]} -eq 0 ]; then
        ok "No broken symlinks found."
        return 0
    fi
    printf '  %s\n' "${links[@]:0:50}"
    [ ${#links[@]} -gt 50 ] && say "  ... and $(( ${#links[@]} - 50 )) more"
    if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "$PX_STATE_DIR"
        printf '%s\n' "${links[@]}" >"$out"
        say "Full list saved to $out. Nothing was deleted."
    fi
}

# ---------------------------------------------------------------------------
# Maintenance check: macOS and Homebrew already do what the Linux timers do
# ---------------------------------------------------------------------------
run_setup() {
    section "${LABEL[setup]}"
    local trim
    trim=$(system_profiler SPNVMeDataType 2>/dev/null | awk -F': ' '/TRIM Support/ {print $2; exit}')
    case "$trim" in
        Yes) ok "SSD TRIM: on (macOS trims the internal SSD itself)." ;;
        "")  say "SSD TRIM: no NVMe info (macOS trims Apple SSDs itself; 'sudo trimforce enable' is for third-party SSDs)." ;;
        *)   warn "SSD TRIM: $trim. For a third-party SSD see 'man trimforce'." ;;
    esac

    [ "$PKG" = brew ] || { say "Homebrew not found; nothing more to check."; return 0; }
    if [ -n "${HOMEBREW_NO_INSTALL_CLEANUP:-}" ]; then
        warn "HOMEBREW_NO_INSTALL_CLEANUP is set: brew won't prune old versions on its own."
    else
        ok "brew cleanup: runs on its own every ${HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS:-30} days after installs/upgrades."
    fi
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
available_categories() {
    local c
    for c in "${ALL_CATEGORIES[@]}"; do
        "cat_${c}_available" 2>/dev/null && echo "$c"
    done
}

if [ "$MODE" = list ]; then
    for c in "${ALL_CATEGORIES[@]}" setup; do
        if [ "$c" = setup ] || "cat_${c}_available" 2>/dev/null; then state="available"; else state="n/a here"; fi
        printf '%-16s %-48s %s\n' "$c" "${LABEL[$c]}" "$state"
    done
    exit 0
fi

if [ "$MODE" = summary ]; then
    # Cheap estimates only: no sudo, no network, no container engines
    for c in pkgcache journal thumbnails devcaches browsers trash; do
        "cat_${c}_available" 2>/dev/null || continue
        if [ "$c" = pkgcache ]; then
            mapfile -t dirs < <(pkgcache_dirs)
            size=$(human "$(bytes_of "${dirs[@]}")")
        else
            size=$("cat_${c}_size")
        fi
        printf '%s\t%s\n' "${LABEL[$c]}" "$size"
    done
    if cat_orphans_available; then
        printf '%s\t%s\n' "${LABEL[orphans]}" "$(cat_orphans_size)"
    fi
    exit 0
fi

if [ "$MODE" = setup ]; then
    run_setup
    exit 0
fi

# --- menu / --categories / --yes ------------------------------------------
mapfile -t AVAILABLE < <(available_categories)
SELECTED=()

if [ -n "$CATEGORIES" ]; then
    IFS=',' read -ra wanted <<<"${CATEGORIES//-/_}"
    for c in "${wanted[@]}"; do
        c="${c// /}"
        [ -n "$c" ] || continue
        if [ "$c" = setup ]; then SELECTED+=(setup); continue; fi
        if [[ " ${ALL_CATEGORIES[*]} " != *" $c "* ]]; then
            warn "Unknown category: $c (see --list)"
        elif [[ " ${AVAILABLE[*]} " != *" $c "* ]]; then
            warn "Skipping $c: not available on this system."
        else
            SELECTED+=("$c")
        fi
    done
elif [ "$ASSUME_YES" -eq 1 ]; then
    for c in "${YES_DEFAULT_CATEGORIES[@]}"; do
        [[ " ${AVAILABLE[*]} " == *" $c "* ]] && SELECTED+=("$c")
    done
else
    [ -t 0 ] || die "No terminal for the picker; pass --categories or --yes (see --help)."
    clear 2>/dev/null
    say "Measuring what can be cleaned..."
    declare -A ID_OF=()
    OPTIONS=()
    PRESELECT=()
    for c in "${AVAILABLE[@]}" setup; do
        if [ "$c" = setup ]; then
            line="${LABEL[setup]}"
        else
            line="${LABEL[$c]}  ($("cat_${c}_size" 2>/dev/null))"
        fi
        line="${line//,/;}"   # gum --selected is comma-separated
        ID_OF["$line"]="$c"
        OPTIONS+=("$line")
        [[ " ${DEFAULT_CATEGORIES[*]} " == *" $c "* ]] && PRESELECT+=("$line")
    done

    if command_exists gum; then
        preselect_csv=$(IFS=','; echo "${PRESELECT[*]}")
        mapfile -t picked < <(printf '%s\n' "${OPTIONS[@]}" | gum choose --no-limit \
            --height $(( ${#OPTIONS[@]} + 2 )) \
            --header "Clean System: space toggles, enter confirms (pre-checked = safe defaults)" \
            --selected "$preselect_csv")
    else
        i=1
        for line in "${OPTIONS[@]}"; do
            mark=" "
            [[ " ${PRESELECT[*]} " == *" $line "* ]] && mark="x"
            printf '%2d) [%s] %s\n' "$i" "$mark" "$line"
            i=$((i + 1))
        done
        read -r -p "Numbers to run (e.g. 1 3 7), Enter = [x] defaults, q = quit: " answer
        [[ "$answer" =~ ^[Qq] ]] && exit 0
        picked=()
        if [ -z "$answer" ]; then
            picked=("${PRESELECT[@]}")
        else
            for n in $answer; do
                [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#OPTIONS[@]} ] && picked+=("${OPTIONS[$((n - 1))]}")
            done
        fi
    fi
    for line in "${picked[@]}"; do
        [ -n "${ID_OF[$line]:-}" ] && SELECTED+=("${ID_OF[$line]}")
    done
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
    say "Nothing selected."
    exit 0
fi

# sudo once up front (and keep it alive) if anything selected needs it
needs_sudo=0
for c in "${SELECTED[@]}"; do
    [[ "$SUDO_CATEGORIES" == *" $c "* ]] && needs_sudo=1
done
if [ "$needs_sudo" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    sudo -v || die "sudo is required for the selected categories."
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
    KEEPALIVE_PID=$!
    trap 'kill "$KEEPALIVE_PID" 2>/dev/null' EXIT
fi

[ "$DRY_RUN" -eq 1 ] && say "DRY RUN: nothing will be changed."
log "=== clean-system: ${SELECTED[*]}"
mapfile -t BEFORE < <(fs_avail)

declare -A RESULT=()
for c in "${SELECTED[@]}"; do
    if [ "$c" = setup ]; then
        run_setup
        RESULT[$c]="done"
        continue
    fi
    section "${LABEL[$c]}"
    if "cat_${c}_run"; then RESULT[$c]="done"; else RESULT[$c]="errors"; fi
done

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
section "Summary"
for c in "${SELECTED[@]}"; do
    printf '  %-48s %s\n' "${LABEL[$c]}" "${RESULT[$c]:-skipped}"
done

if [ "$DRY_RUN" -eq 0 ]; then
    total=0
    for line in "${BEFORE[@]}"; do
        read -r dev before mnt <<<"$line"
        after=$(fs_avail | awk -v d="$dev" '$1==d {print $2}')
        [ -n "$after" ] || continue
        delta=$(( after - before ))
        total=$(( total + delta ))
        if [ "$delta" -ge 0 ]; then
            printf '  %-48s +%s free\n' "${mnt:-$dev}" "$(human "$delta")"
        else
            printf '  %-48s -%s free\n' "${mnt:-$dev}" "$(human $(( -delta )))"
        fi
    done
    if [ "$total" -ge 0 ]; then
        ok "Reclaimed about $(human "$total")."
        log "reclaimed $total bytes"
    fi
    say "Log: $LOG_FILE"
    notify_replace clean-system low 5000 edit-clear "Clean System" "Reclaimed about $(human "$(( total > 0 ? total : 0 ))")" 2>/dev/null
fi

if [ -t 0 ] && [ "$ASSUME_YES" -eq 0 ] && [ -z "$CATEGORIES" ] && [ "${PX_NO_PAUSE:-0}" != 1 ]; then
    pause "Press Enter to return..."
fi
exit 0
