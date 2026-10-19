#!/usr/bin/env bash
# GitHub.com/PiercingXX

#########################################################
# Virus Scan with ClamAV
#
# Usage: virus-scan.sh                     interactive menu
#        virus-scan.sh --update-db         update signatures only (safe for other scripts)
#        virus-scan.sh --status            print ClamAV / signature / quarantine status
#        virus-scan.sh --preset NAME [PATH] [--no-tui] [--move] [--strict]
#              NAME: fast | downloads | quick | full | custom PATH
#        virus-scan.sh --help
#
# Exit codes (scans): 0 clean, 1 infected files found, 2 errors.
#########################################################
# macOS port (better-mac): Homebrew ClamAV (configs in $(brew --prefix)/etc/clamav,
# created from the .sample files; signatures in var/lib/clamav, updated by
# freshclam as you, no sudo). clamd is the "clamav" brew service and is never
# started from a background run. Scheduled scans are a launchd user agent.
# The integrity audit checks SIP/SSV/Gatekeeper/FileVault/firewall, launchd
# and background items, profiles, DYLD injection, netstat listeners and macOS
# browser profiles. Dropped: distro packages, the freshclam daemon,
# package-file verification, arch-audit, unhide, ld.so.preload, fangfrisch
# AUR setup.

set -o pipefail
umask 077

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
# shellcheck disable=SC1091
. "$(dirname "$SCRIPT_PATH")/../lib/common.sh"
detect_distro

# Tunables (override via env vars)
# MAX_* limits only apply to clamscan. clamdscan uses clamd.conf
# (MaxFileSize, MaxScanSize, ...), which defaults to 100M per file.
MAX_FILESIZE_MB=${MAX_FILESIZE_MB:-1024}
MAX_SCANSIZE_MB=${MAX_SCANSIZE_MB:-2048}
MAX_RECURSION=${MAX_RECURSION:-32}
MAX_FILES=${MAX_FILES:-20000}
USE_CLAMD=${USE_CLAMD:-1}                    # prefer the clamd daemon when reachable
DETECT_PUA=${DETECT_PUA:-1}                  # clamscan only; clamd uses DetectPUA in clamd.conf
STRICT=${STRICT:-0}                          # encrypted/broken/macro alerts (noisy)
FAST_RECENT_DAYS=${FAST_RECENT_DAYS:-60}
FAST_MAX_SIZE_MB=${FAST_MAX_SIZE_MB:-}
FAST_INCLUDE_EXTS=${FAST_INCLUDE_EXTS:-"exe dll so dylib bin run elf msi bat cmd com scr pif cpl ps1 vbs vbe wsf wsh hta lnk reg sh command scpt py pl rb js mjs ts go php jar war ear class apk deb rpm pkg mpkg dmg appimage flatpak snap desktop tar gz xz bz2 zst zip 7z rar iso pdf doc docm docx xls xlsm xlsx ppt pptm pptx rtf html htm svg"}
SKIP_FILE_EXTS=${SKIP_FILE_EXTS:-"qcow2 vdi vmdk vhd vhdx"}
EXCLUDE_NAMES=${EXCLUDE_NAMES:-"node_modules"}
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-30}

BREW_PREFIX="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null || echo /opt/homebrew)}"
CLAM_ETC="$BREW_PREFIX/etc/clamav"

CLAM_STATE="$PX_STATE_DIR/clamav"
LOG_DIR="$CLAM_STATE/logs"
HISTORY_FILE="$CLAM_STATE/history.log"
BASELINE_DIR="$CLAM_STATE/baseline"
QUARANTINE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/piercingxx/quarantine"

# Containers/Group Containers raise "access data from other apps" prompts
HOME_EXCLUDES=(
    "$HOME/.cache"
    "$HOME/Library/Caches"
    "$HOME/.Trash"
    "$HOME/Library/Containers"
    "$HOME/Library/Group Containers"
    "$HOME/Library/Application Support/MobileSync"
    "$HOME/Library/Developer/CoreSimulator"
    "$HOME/Library/Application Support/Steam"
    "$HOME/Parallels"
    "$HOME/VirtualBox VMs"
    "$HOME/.orbstack"
    "$HOME/.colima"
    "$HOME/.cargo/registry"
    "$HOME/.rustup"
    "$HOME/.npm"
    "$HOME/go/pkg"
    "$QUARANTINE_DIR"
    "$CLAM_STATE"
)
SYSTEM_EXCLUDES=(
    /dev /System/Volumes /private/tmp /private/var/tmp /private/var/folders
    "$BREW_PREFIX/var/lib/clamav"
    /.Spotlight-V100 /.fseventsd /.DocumentRevisions-V100 /.MobileBackups
)

NONINTERACTIVE=0
AUTO_MOVE=0
SCANNER_READY=0
SCAN_BIN=""
SCAN_OPTS=()
SCAN_PID=""
FIND_PID=""
LAST_LOG=""
WORK_DIR=""

HAS_GUM=0
command_exists gum && [ -t 1 ] && HAS_GUM=1

# taskpolicy -d throttle is macOS's idle I/O class (ionice -c3)
PRIO=(nice -n 19)
command_exists taskpolicy && PRIO+=(taskpolicy -d throttle)

# Homebrew's GNU find has -readable (skips files clamd can't be handed);
# BSD find doesn't, and spells "any of these bits" -perm +MODE
FIND="$(command -v gfind || command -v find)"
FIND_READABLE=()
"$FIND" / -maxdepth 0 -readable >/dev/null 2>&1 && FIND_READABLE=(-readable)
FIND_GNU=0
"$FIND" --version 2>/dev/null | grep -q GNU && FIND_GNU=1
PERM_ANY="+"
[ "$FIND_GNU" = 1 ] && PERM_ANY="/"

# GNU stat may be first on PATH; -f means something else there
STAT=/usr/bin/stat

# --alert-exceeds-max reports oversized files as FOUND; they are skips, not infections
LIMIT_RE='Heuristics\.Limits\.Exceeded'

#########################################################
# Housekeeping
#########################################################
cleanup() {
    [ -n "$SCAN_PID" ] && kill "$SCAN_PID" 2>/dev/null
    [ -n "$FIND_PID" ] && kill "$FIND_PID" 2>/dev/null
    [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'echo; warn "Interrupted."; exit 130' INT TERM

init_dirs() {
    mkdir -p "$LOG_DIR" "$BASELINE_DIR" "$QUARANTINE_DIR"
    chmod 700 "$CLAM_STATE" "$QUARANTINE_DIR" 2>/dev/null
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/px-virus-scan.XXXXXX") || die "Could not create a temp dir."
    find "$LOG_DIR" -type f -name '*.log' -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null
}

#########################################################
# UI helpers (gum when present, plain text otherwise)
#########################################################
ui_title() {
    if [ "$HAS_GUM" = 1 ]; then
        gum style --border rounded --padding "0 2" --foreground 6 --bold "$*"
    else
        printf '\n== %s ==\n' "$*"
    fi
}
ui_ok() {
    if [ "$HAS_GUM" = 1 ]; then gum style --foreground 2 "✓ $*"; else ok "✓ $*"; fi
}
ui_warn() {
    if [ "$HAS_GUM" = 1 ]; then gum style --foreground 3 "⚠ $*"; else warn "⚠ $*"; fi
}
ui_err() {
    if [ "$HAS_GUM" = 1 ]; then gum style --foreground 1 --bold "✗ $*"; else err "✗ $*"; fi
}
ui_info() {
    if [ "$HAS_GUM" = 1 ]; then gum style --foreground 6 "$*"; else printf '%s\n' "$*"; fi
}
ui_choose() {
    local header="$1"; shift
    if [ "$HAS_GUM" = 1 ]; then
        gum choose --header "$header" "$@"
    else
        local PS3="$header> " opt
        select opt in "$@"; do
            [ -n "$opt" ] && { printf '%s\n' "$opt"; return 0; }
        done
        return 1
    fi
}
ui_pager() {
    if [ "$HAS_GUM" = 1 ]; then gum pager < "$1"; else "${PAGER:-less}" "$1"; fi
}

# need_sudo "why" : get credentials once, visibly, outside any spinner
need_sudo() {
    sudo -n true 2>/dev/null && return 0
    if [ "$NONINTERACTIVE" = 1 ] || [ ! -t 0 ]; then
        warn "sudo needs a password and there is no terminal; skipping: $1"
        return 1
    fi
    say "Administrator access needed to $1."
    sudo -v
}

#########################################################
# ClamAV install / signatures / daemon
#########################################################
# Homebrew's clamav formula ships clamd as its service
clamd_units() { echo "clamav"; }

first_unit() {
    local u
    for u in "$@"; do
        svc_exists "$u" && { echo "$u"; return 0; }
    done
    return 1
}

db_dir() {
    if [ -n "${CLAMAV_DB_DIR:-}" ]; then echo "$CLAMAV_DB_DIR"; return; fi
    local d
    if [ -r "$CLAM_ETC/freshclam.conf" ]; then
        d=$(awk '$1=="DatabaseDirectory"{print $2; exit}' "$CLAM_ETC/freshclam.conf")
        [ -n "$d" ] && { echo "$d"; return; }
    fi
    echo "$BREW_PREFIX/var/lib/clamav"
}

clamd_conf() {
    [ -r "$CLAM_ETC/clamd.conf" ] && { echo "$CLAM_ETC/clamd.conf"; return 0; }
    return 1
}

# Homebrew ships only .sample configs; freshclam and clamd need real ones
ensure_freshclam_conf() {
    local conf="$CLAM_ETC/freshclam.conf"
    mkdir -p "$(db_dir)"
    [ -f "$conf" ] && return 0
    [ -f "$conf.sample" ] || return 1
    sed -e 's/^Example/#Example/' "$conf.sample" > "$conf"
}

ensure_clamd_conf() {
    local conf="$CLAM_ETC/clamd.conf" sock_dir="$BREW_PREFIX/var/run/clamav"
    [ -f "$conf" ] && return 0
    [ -f "$conf.sample" ] || { ui_err "No $conf.sample to build clamd.conf from."; return 1; }
    mkdir -p "$sock_dir"
    {
        sed -e 's/^Example/#Example/' "$conf.sample"
        echo "LocalSocket $sock_dir/clamd.sock"
    } > "$conf"
}

db_present() {
    local d; d=$(db_dir)
    compgen -G "$d/main.c[vl]d" >/dev/null && compgen -G "$d/daily.c[vl]d" >/dev/null
}

# Hours since the daily database last changed (99999 if missing)
db_age_hours() {
    local d f newest=0 m
    d=$(db_dir)
    for f in "$d"/daily.cvd "$d"/daily.cld; do
        [ -f "$f" ] || continue
        m=$("$STAT" -f %m "$f" 2>/dev/null) || continue
        [ "$m" -gt "$newest" ] && newest=$m
    done
    if [ "$newest" -eq 0 ]; then echo 99999; else echo $(( ($(date +%s) - newest) / 3600 )); fi
}

install_clamav() {
    command_exists clamscan && { ensure_freshclam_conf; return 0; }
    if [ "$NONINTERACTIVE" = 1 ]; then
        err "ClamAV is not installed."
        return 1
    fi
    confirm "ClamAV is not installed. Install it now (brew install clamav)?" || return 1
    pkg_install clamav || { ui_err "ClamAV install failed."; return 1; }
    ensure_freshclam_conf
    ui_ok "ClamAV installed."
    offer_services
}

# After install: offer the daemon (never forced)
offer_services() {
    local cd
    cd=$(first_unit $(clamd_units)) || return 0
    clamdscan --ping=1 >/dev/null 2>&1 && return 0
    if confirm "Enable the clamd daemon (brew service $cd) for much faster scans? (keeps ~1 GB RAM in use)"; then
        db_present || update_definitions
        ensure_clamd_conf && svc_enable_now "$cd"
    fi
}

# update_definitions -> 0 ok, 2 failed
update_definitions() {
    command_exists freshclam || { err "freshclam is not installed."; return 2; }
    ensure_freshclam_conf || { ui_err "No freshclam.conf in $CLAM_ETC."; return 2; }
    say "Updating virus signatures..."

    local out="$WORK_DIR/freshclam.out"
    if freshclam 2>&1 | tee "$out"; then
        ui_ok "Virus signatures updated."
        return 0
    fi
    if grep -qi 'lock' "$out"; then
        ui_err "Another freshclam is holding the database lock. Try again in a minute."
    elif grep -qi 'permission denied' "$out"; then
        ui_err "Can't write $(db_dir); fix with: sudo chown -R $(id -un) $(db_dir)"
    else
        ui_err "freshclam failed; scanning will use the existing signatures."
    fi
    return 2
}

# Signatures must exist before clamd will even start
ensure_db() {
    if ! db_present; then
        ui_warn "No virus signature database yet; downloading it now (first run, ~300 MB)."
        update_definitions
        db_present || { ui_err "No signature database available. Run: freshclam"; return 1; }
    fi
    local age; age=$(db_age_hours)
    if [ "$age" -gt 72 ]; then
        ui_warn "Signatures are $((age / 24)) days old."
        if [ "$NONINTERACTIVE" = 1 ]; then
            update_definitions || true
        elif confirm "Update them before scanning?"; then
            update_definitions || true
        fi
    fi
    return 0
}

# Make sure clamd answers; start the brew service if the user agrees
ensure_clamd() {
    command_exists clamdscan || return 1
    clamdscan --ping=1 >/dev/null 2>&1 && return 0

    local unit; unit=$(first_unit $(clamd_units)) || return 1
    # Never leave a ~1 GB daemon running after a scheduled/background scan
    [ "$NONINTERACTIVE" = 1 ] && return 1
    confirm "clamd isn't running. Start it (brew service $unit) for faster scans? (keeps ~1 GB RAM in use)" || return 1
    ensure_clamd_conf || return 1
    svc_start "$unit" >/dev/null 2>&1 || return 1
    say "Waiting for clamd to load signatures (can take up to a minute)..."
    clamdscan --ping=90:1 >/dev/null 2>&1
}

select_scanner() {
    [ "$SCANNER_READY" = 1 ] && return 0
    if [ "$USE_CLAMD" = 1 ] && ensure_clamd; then
        SCAN_BIN="clamdscan"
        local pass="--fdpass" conf
        # --fdpass needs a LocalSocket; TCP-only setups have to stream
        if conf=$(clamd_conf) && ! grep -qE '^[[:space:]]*LocalSocket[[:space:]]' "$conf" \
            && grep -qE '^[[:space:]]*TCPSocket[[:space:]]' "$conf"; then
            pass="--stream"
        fi
        SCAN_OPTS=(--multiscan "$pass")
    else
        SCAN_BIN="clamscan"
        SCAN_OPTS=(
            --max-filesize="${MAX_FILESIZE_MB}M"
            --max-scansize="${MAX_SCANSIZE_MB}M"
            --max-recursion="$MAX_RECURSION"
            --max-files="$MAX_FILES"
            --alert-exceeds-max=yes
            --cross-fs=no
            --follow-dir-symlinks=0
            --follow-file-symlinks=0
        )
        [ "$DETECT_PUA" = 1 ] && SCAN_OPTS+=(--detect-pua=yes --exclude-pua=Packed --exclude-pua=PwTool)
        [ "$STRICT" = 1 ] && SCAN_OPTS+=(--alert-encrypted-archive=yes --alert-encrypted-doc=yes --alert-broken=yes --alert-macros=yes)
        [ "$USE_CLAMD" = 1 ] && ui_warn "clamd unavailable; using clamscan (slower, loads signatures each run)."
    fi
    SCANNER_READY=1
}

clamd_limit_note() {
    [ "$SCAN_BIN" = clamdscan ] || return 0
    local conf limit="100M"
    if conf=$(clamd_conf); then
        limit=$(awk '$1=="MaxFileSize"{print $2; exit}' "$conf")
        limit=${limit:-100M}
    fi
    ui_info "clamd skips files larger than $limit (MaxFileSize in clamd.conf; USE_CLAMD=0 uses clamscan limits)."
}

#########################################################
# File lists
#########################################################
# build_find_args MODE ROOT... -> FIND_ARGS. MODE: all | fast | recent
build_find_args() {
    local mode="$1"; shift
    local roots=("$@") prune=() p r skip ext

    for p in "${SYSTEM_EXCLUDES[@]}" "${HOME_EXCLUDES[@]}"; do
        # Never prune a root the user explicitly asked to scan
        skip=0
        for r in "${roots[@]}"; do
            [[ "$r" == "$p" || "$r" == "$p"/* ]] && skip=1
        done
        [ "$skip" = 0 ] && prune+=(-path "$p" -o)
    done
    for p in $EXCLUDE_NAMES; do
        prune+=(-name "$p" -o)
    done
    unset 'prune[${#prune[@]}-1]'

    FIND_ARGS=("${roots[@]}" -xdev '(' -type d '(' "${prune[@]}" ')' ')' -prune -o -type f "${FIND_READABLE[@]}")
    for ext in $SKIP_FILE_EXTS; do
        FIND_ARGS+=(! -iname "*.$ext")
    done
    case "$mode" in
        fast)
            local sel=(-perm "${PERM_ANY}111" -o -mtime "-$FAST_RECENT_DAYS")
            for ext in $FAST_INCLUDE_EXTS; do
                sel+=(-o -iname "*.${ext#.}")
            done
            FIND_ARGS+=('(' "${sel[@]}" ')')
            ;;
        recent)
            FIND_ARGS+=(-mtime "-$FAST_RECENT_DAYS")
            ;;
    esac
    # -size -NM rounds up to whole MiB, so compare in KiB
    [ "$mode" = fast ] && [ -n "$FAST_MAX_SIZE_MB" ] && FIND_ARGS+=(-size "-$((FAST_MAX_SIZE_MB * 1024 + 1))k")
    # --file-list is newline separated, so names containing a newline go to a
    # NUL-separated side list (GNU find) and are scanned separately
    if [ "$FIND_GNU" = 1 ]; then
        FIND_ARGS+=('(' '(' -name $'*\n*' -fprint0 "$NL_LIST" ')' -o -print ')')
    else
        FIND_ARGS+=(! -name $'*\n*' -print)
    fi
}

# gather_list LIST_FILE MODE ROOT... : run find in the background with a live count
gather_list() {
    local list="$1"; shift
    NL_LIST="$list.nl"
    : > "$NL_LIST"
    build_find_args "$@"
    "$FIND" "${FIND_ARGS[@]}" 2>/dev/null > "$list" &
    FIND_PID=$!
    while kill -0 "$FIND_PID" 2>/dev/null; do
        [ -t 1 ] && printf '\r  Gathering files... %s' "$(( $(wc -l < "$list") ))"
        sleep 1
    done
    wait "$FIND_PID" 2>/dev/null
    FIND_PID=""
    [ -t 1 ] && printf '\r\033[K'
}

# found_lines FILE : real detections only (no size-limit skips)
found_lines() {
    grep ' FOUND$' "$1" | grep -v "$LIMIT_RE"
}

#########################################################
# Scanning
#########################################################
# run_scan PRESET LIST_FILE -> 0 clean, 1 infected, 2 errors
# BSD wc pads its count with spaces, hence the $(( )) around each one
run_scan() {
    local preset="$1" list="$2"
    local total raw log start rc infected errors skipped scanned shown=0 elapsed nl_count=0

    total=$(( $(wc -l < "$list") ))
    [ -s "${NL_LIST:-}" ] && nl_count=$(( $(tr -cd '\0' < "$NL_LIST" | wc -c) ))
    total=$((total + nl_count))
    if [ "$total" -eq 0 ]; then
        ui_warn "No files to scan."
        return 0
    fi

    raw="$WORK_DIR/raw.out"
    log="$LOG_DIR/scan-$preset-$(date +%Y%m%d-%H%M%S).log"
    LAST_LOG="$log"
    : > "$raw"
    clamd_limit_note
    ui_info "Scanning $total files with $SCAN_BIN (Ctrl-C to stop)..."

    start=$(date +%s)
    "${PRIO[@]}" "$SCAN_BIN" "${SCAN_OPTS[@]}" --file-list="$list" > "$raw" 2>&1 &
    SCAN_PID=$!

    while kill -0 "$SCAN_PID" 2>/dev/null; do
        local found_now
        found_now=$(( $(found_lines "$raw" | wc -l) ))
        if [ "$found_now" -gt "$shown" ]; then
            [ -t 1 ] && printf '\r\033[K'
            found_lines "$raw" | sed -n "$((shown + 1)),${found_now}p" | while IFS= read -r line; do
                printf '%s\n' "${RED}${line}${NC}"
            done
            shown=$found_now
        fi
        if [ -t 1 ]; then
            scanned=$(( $(wc -l < "$raw") ))
            [ "$scanned" -gt "$total" ] && scanned=$total
            elapsed=$(( $(date +%s) - start ))
            printf '\r  Scanned %s/%s (%s%%) · FOUND %s · %ss ' \
                "$scanned" "$total" "$(( scanned * 100 / total ))" "$shown" "$elapsed"
        fi
        sleep 2
    done
    wait "$SCAN_PID"
    rc=$?
    SCAN_PID=""
    [ -t 1 ] && printf '\r\033[K'

    # Names with embedded newlines can't go through --file-list
    if [ "$nl_count" -gt 0 ]; then
        xargs -0 -r "${PRIO[@]}" "$SCAN_BIN" "${SCAN_OPTS[@]}" < "$NL_LIST" >> "$raw" 2>&1
        local nl_rc=$?
        [ "$nl_rc" -gt "$rc" ] && [ "$nl_rc" -lt 123 ] && rc=$nl_rc
    fi
    elapsed=$(( $(date +%s) - start ))

    infected=$(( $(found_lines "$raw" | wc -l) ))
    skipped=$(grep ' FOUND$' "$raw" | grep -c "$LIMIT_RE")
    errors=$(grep -cE ' ERROR$|^ERROR:|^LibClamAV Error' "$raw")
    {
        printf '# preset=%s scanner=%s files=%s date=%s duration=%ss exit=%s\n' \
            "$preset" "$SCAN_BIN" "$total" "$(date '+%F %T')" "$elapsed" "$rc"
        grep -vE ': (OK|Empty file)$' "$raw"
    } > "$log"

    # Leftover FOUND lines that arrived after the last poll
    if [ "$infected" -gt "$shown" ]; then
        found_lines "$raw" | sed -n "$((shown + 1)),\$p" | while IFS= read -r line; do
            printf '%s\n' "${RED}${line}${NC}"
        done
    fi

    local result=0
    if [ "$infected" -gt 0 ]; then
        result=1
    elif [ "$rc" -ge 2 ] || [ "$errors" -gt 0 ]; then
        result=2
    fi

    printf '%s|%s|%s|%s|%s|%s|%s|%ss|%s\n' "$(date '+%F %T')" "$preset" "$SCAN_BIN" \
        "$total" "$infected" "$errors" "$skipped" "$elapsed" "$log" >> "$HISTORY_FILE"

    echo
    printf '  %-10s %s\n' "Scanned" "$total" "Infected" "$infected" "Errors" "$errors" \
        "Too large" "$skipped (not scanned)" "Duration" "${elapsed}s" "Log" "$log"
    echo
    case "$result" in
        0) ui_ok "No threats found." ;;
        1) ui_err "$infected infected file(s) found!" ;;
        2) ui_warn "Scan finished with $errors error(s); see the log." ;;
    esac

    if [ "$result" = 1 ]; then
        notify_replace virus-scan critical 0 dialog-warning \
            "ClamAV: $infected infected file(s)" "Preset $preset · $log"
        offer_quarantine "$log"
    elif [ "$NONINTERACTIVE" = 1 ] || [ "$elapsed" -gt 120 ]; then
        notify_replace virus-scan low 6000 security-high \
            "ClamAV: $preset scan finished" "$total files · $errors errors"
    fi
    return "$result"
}

# scan_preset NAME [PATH] -> scan result code
scan_preset() {
    local preset="$1" path="${2:-}" list roots=() mode=all

    case "$preset" in
        fast)
            ui_title "Fast Targeted Scan - executables, scripts, archives, documents, recent files"
            roots=("$HOME"); mode=fast ;;
        downloads)
            ui_title "Recent Downloads Scan (last $FAST_RECENT_DAYS days)"
            [ -d "$HOME/Downloads" ] || { ui_warn "No Downloads directory found."; return 0; }
            roots=("$HOME/Downloads"); mode=recent ;;
        quick)
            ui_title "Quick Scan - common user, startup and temp directories"
            local d tmp
            # /tmp is a symlink find won't enter; $TMPDIR is the per-user temp
            tmp=$(cd "${TMPDIR:-/private/var/tmp}" 2>/dev/null && pwd -P)
            for d in "$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop" "$HOME/.local/share" \
                     "$HOME/.local/bin" "$HOME/bin" "$HOME/Library/LaunchAgents" \
                     /Library/LaunchAgents /Library/LaunchDaemons /Users/Shared \
                     /private/tmp /private/var/tmp "$tmp"; do
                [ -d "$d" ] && roots+=("$d")
            done ;;
        full)
            ui_title "Full Home Directory Scan"
            ui_info "Stays on the home volume; other drives and network mounts are skipped."
            roots=("$HOME") ;;
        custom)
            [ -n "$path" ] || { ui_err "custom needs a path."; return 2; }
            path=$(realpath -m "$path" 2>/dev/null || readlink -f "$path" 2>/dev/null || printf '%s' "$path")
            [ -e "$path" ] || { ui_err "Path does not exist: $path"; return 2; }
            ui_title "Scanning: $path"
            roots=("$path") ;;
        *)
            ui_err "Unknown preset: $preset (fast|downloads|quick|full|custom PATH)"
            return 2 ;;
    esac

    ensure_db || return 2
    select_scanner

    list="$WORK_DIR/files.list"
    if [ "$preset" = custom ] && [ -f "$path" ]; then
        NL_LIST=""
        printf '%s\n' "$path" > "$list"
    else
        gather_list "$list" "$mode" "${roots[@]}"
    fi
    run_scan "$preset" "$list"
}

#########################################################
# Quarantine
#########################################################
# Parse "path: Signature FOUND" lines from a log into path<TAB>sig
found_entries() {
    found_lines "$1" | while IFS= read -r line; do
        line="${line% FOUND}"
        printf '%s\t%s\n' "${line%: *}" "${line##*: }"
    done
}

quarantine_file() {
    local path="$1" sig="$2" id sha mode
    [ -f "$path" ] || { ui_warn "Already gone: $path"; return 1; }
    if [ ! -w "$(dirname "$path")" ]; then
        ui_warn "No permission to move $path (owner: $("$STAT" -f %Su "$path")). Remove it as that user."
        return 1
    fi
    id="$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
    sha=$(shasum -a 256 "$path" | cut -d' ' -f1)
    mode=$("$STAT" -f %Lp "$path")
    mv -- "$path" "$QUARANTINE_DIR/$id.quar" || return 1
    chmod 0400 "$QUARANTINE_DIR/$id.quar"
    printf 'path=%s\nsignature=%s\nsha256=%s\nmode=%s\ndate=%s\n' \
        "$path" "$sig" "$sha" "$mode" "$(date '+%F %T')" > "$QUARANTINE_DIR/$id.meta"
    ui_ok "Quarantined: $path"
}

# Report-only by default; moving needs a yes (or --move)
offer_quarantine() {
    local log="$1" entries
    entries="$WORK_DIR/found.tsv"
    found_entries "$log" > "$entries"
    [ -s "$entries" ] || return 0

    if [ "$AUTO_MOVE" != 1 ]; then
        [ "$NONINTERACTIVE" = 1 ] && return 0
        confirm "Move the infected file(s) to quarantine ($QUARANTINE_DIR)?" || return 0
    fi
    local path sig
    while IFS=$'\t' read -r path sig; do
        quarantine_file "$path" "$sig"
    done < "$entries"
}

meta_get() { sed -n "s/^$2=//p" "$1" | head -n 1; }

quarantine_menu() {
    while true; do
        clear
        ui_title "Quarantine ($QUARANTINE_DIR)"
        local metas=() labels=() m
        for m in "$QUARANTINE_DIR"/*.meta; do
            [ -f "$m" ] || continue
            metas+=("$m")
            labels+=("$(meta_get "$m" date) · $(meta_get "$m" signature) · $(meta_get "$m" path)")
        done
        if [ ${#metas[@]} -eq 0 ]; then
            ui_ok "Quarantine is empty."
            pause
            return
        fi
        local choice
        choice=$(ui_choose "Pick a file" "${labels[@]}" "Delete ALL quarantined files" "Back") || return
        case "$choice" in
            "Back"|"") return ;;
            "Delete ALL quarantined files")
                confirm "Permanently delete all ${#metas[@]} quarantined file(s)?" || continue
                rm -f "$QUARANTINE_DIR"/*.quar "$QUARANTINE_DIR"/*.meta
                ui_ok "Quarantine emptied."
                pause
                continue ;;
        esac
        local i sel=""
        for i in "${!labels[@]}"; do
            [ "${labels[$i]}" = "$choice" ] && sel="${metas[$i]}"
        done
        [ -n "$sel" ] && quarantine_item_menu "$sel"
    done
}

quarantine_item_menu() {
    local meta="$1" quar="${1%.meta}.quar"
    local path sig sha
    path=$(meta_get "$meta" path)
    sig=$(meta_get "$meta" signature)
    sha=$(meta_get "$meta" sha256)
    ui_info "File:      $path"
    ui_info "Signature: $sig"
    ui_info "SHA256:    $sha"
    local action
    action=$(ui_choose "Action" "Rescan" "Restore to original location" "Delete permanently" "Show VirusTotal link (hash only)" "Back") || return
    case "$action" in
        "Rescan")
            select_scanner
            chmod 0600 "$quar"
            "$SCAN_BIN" "${SCAN_OPTS[@]}" "$quar"
            chmod 0400 "$quar"
            pause ;;
        "Restore to original location")
            ui_warn "This file was detected as $sig."
            confirm "Restore it to $path anyway?" || return
            if [ -e "$path" ]; then
                confirm "$path exists. Overwrite it?" || return
            fi
            mkdir -p "$(dirname "$path")" &&
                mv -- "$quar" "$path" &&
                chmod "$(meta_get "$meta" mode)" "$path" &&
                rm -f "$meta" &&
                ui_ok "Restored $path"
            pause ;;
        "Delete permanently")
            confirm "Delete $path from quarantine for good?" || return
            rm -f "$quar" "$meta"
            ui_ok "Deleted."
            pause ;;
        "Show VirusTotal link (hash only)")
            ui_info "https://www.virustotal.com/gui/file/$sha"
            ui_info "(Nothing is uploaded; this only looks up the hash.)"
            pause ;;
    esac
}

#########################################################
# Status, logs, history
#########################################################
show_status() {
    ui_title "ClamAV Status"
    if ! command_exists clamscan; then
        ui_err "ClamAV is not installed."
        return
    fi
    local d age cd tmpdirs qcount last
    d=$(db_dir)
    age=$(db_age_hours)
    printf '  %-22s %s\n' "Engine / signatures" "$(clamscan --version 2>/dev/null)"
    if db_present; then
        printf '  %-22s %s\n' "Signature age" "${age}h ($d)"
        [ "$age" -gt 72 ] && ui_warn "Signatures are more than 3 days old."
    else
        ui_err "No signature database in $d (run Update Virus Definitions)."
    fi
    printf '  %-22s %s\n' "Auto updates" "manual (scans refresh signatures older than 3 days)"
    if command_exists clamdscan && clamdscan --ping=1 >/dev/null 2>&1; then
        printf '  %-22s %s\n' "clamd" "running (fast scans)"
    else
        cd=$(first_unit $(clamd_units)) || cd="none found"
        printf '  %-22s %s\n' "clamd" "not running (brew service: $cd)"
    fi
    tmpdirs=$(( $(find "$d" -maxdepth 1 -type d -name 'tmp.*' 2>/dev/null | wc -l) ))
    [ "$tmpdirs" -gt 0 ] && printf '  %-22s %s\n' "Stale freshclam temp" "$tmpdirs dir(s) in $d (from interrupted updates)"
    qcount=$(( $(find "$QUARANTINE_DIR" -maxdepth 1 -name '*.quar' 2>/dev/null | wc -l) ))
    printf '  %-22s %s\n' "Quarantined files" "$qcount"
    if [ -f "$HISTORY_FILE" ]; then
        last=$(tail -n 1 "$HISTORY_FILE" | awk -F'|' '{printf "%s  %s  %s files, %s infected, %s errors", $1, $2, $4, $5, $6}')
        printf '  %-22s %s\n' "Last scan" "$last"
    fi
    printf '  %-22s %s\n' "Scheduled scan" "$(timer_state)"
    printf '  %-22s %s\n' "Strict heuristics" "$([ "$STRICT" = 1 ] && echo on || echo off) (clamscan only)"
}

logs_menu() {
    local logs=() labels=() f choice
    while IFS= read -r f; do
        logs+=("$f")
        labels+=("$(basename "$f")")
    done < <(ls -1t "$LOG_DIR"/*.log 2>/dev/null | head -n 30)
    choice=$(ui_choose "Logs" "Scan history" "${labels[@]}" "Back") || return
    case "$choice" in
        "Back"|"") return ;;
        "Scan history")
            if [ ! -s "$HISTORY_FILE" ]; then
                ui_warn "No scans recorded yet."
                pause
                return
            fi
            {
                echo "date|preset|scanner|files|infected|errors|too-large|duration|log"
                tail -n 20 "$HISTORY_FILE"
            } | column -t -s '|' > "$WORK_DIR/history.txt"
            ui_pager "$WORK_DIR/history.txt" ;;
        *)
            ui_pager "$LOG_DIR/$choice" ;;
    esac
}

#########################################################
# System integrity audit
#########################################################
audit_tools_for_distro() {
    echo "rkhunter chkrootkit lynis"
}

install_audit_tools() {
    local missing=() t
    for t in $(audit_tools_for_distro); do
        command_exists "$t" || missing+=("$t")
    done
    [ ${#missing[@]} -eq 0 ] && return 0
    confirm "Install missing audit tools (Homebrew): ${missing[*]}?" || return 0
    for t in "${missing[@]}"; do
        pkg_install "$t" || warn "$t isn't available here; skipping."
    done
}

# baseline_diff NAME CURRENT_FILE : first run saves, later runs show changes
baseline_diff() {
    local base="$BASELINE_DIR/$1" since
    cp "$2" "$WORK_DIR/current-$1"
    if [ ! -f "$base" ]; then
        cp "$2" "$base"
        echo "Baseline saved; future audits will report changes."
        return 0
    fi
    since=$("$STAT" -f %Sm -t %F "$base")
    if diff "$base" "$2" > "$WORK_DIR/diff-$1"; then
        echo "No changes since baseline ($since)."
        return 0
    fi
    echo "CHANGES since baseline ($since):  < removed   > added"
    grep -E '^[<>]' "$WORK_DIR/diff-$1"
    echo "$1" >> "$WORK_DIR/audit-changed"
    return 1
}

integrity_audit() {
    ui_title "System Integrity Audit"
    install_audit_tools
    local have_sudo=0
    need_sudo "run root-level checks (rkhunter, chkrootkit, lynis, SUID scan)" && have_sudo=1

    local report="$LOG_DIR/audit-$(date +%Y%m%d-%H%M%S).log"
    : > "$WORK_DIR/audit-changed"
    LAST_LOG="$report"

    {
        echo "PiercingXX integrity audit · $(date '+%F %T') · macOS $(sw_vers -productVersion 2>/dev/null)"

        # The sealed system volume replaces per-package file verification
        echo; echo "== System protections =="
        csrutil status 2>&1
        csrutil authenticated-root status 2>&1
        echo "Gatekeeper: $(spctl --status 2>&1)"
        fdesetup status 2>&1
        /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1
        echo "XProtect: $(defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo unknown)"

        if command_exists rkhunter && [ "$have_sudo" = 1 ]; then
            echo; echo "== rkhunter =="
            if ! sudo test -s "$BREW_PREFIX/var/lib/rkhunter/db/rkhunter.dat"; then
                echo "Creating rkhunter file baseline (first run)..."
                sudo "$(command -v rkhunter)" --propupd --quiet 2>&1
            fi
            sudo "$(command -v rkhunter)" --check --sk --rwo --nocolors 2>&1
        fi

        if command_exists chkrootkit && [ "$have_sudo" = 1 ]; then
            echo; echo "== chkrootkit =="
            sudo "$(command -v chkrootkit)" -q 2>&1
        fi

        if command_exists lynis && [ "$have_sudo" = 1 ]; then
            echo; echo "== Lynis warnings and suggestions =="
            sudo "$(command -v lynis)" audit system --quick --quiet --no-colors >/dev/null 2>&1
            sudo grep -E '^(hardening_index|warning\[\]|suggestion\[\])=' /var/log/lynis-report.dat 2>/dev/null \
                | sed -e 's/^warning\[\]=/WARNING: /' -e 's/^suggestion\[\]=/suggestion: /'
        fi

        echo; echo "== Library injection (DYLD_INSERT_LIBRARIES) =="
        local dyld
        dyld=$(launchctl getenv DYLD_INSERT_LIBRARIES 2>/dev/null)
        if [ -n "$dyld" ]; then
            echo "WARNING: launchd environment sets DYLD_INSERT_LIBRARIES=$dyld"
        else
            echo "launchd environment: not set (good)."
        fi
        grep -rls 'DYLD_INSERT_LIBRARIES' "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons \
            /etc/launchd.conf "$HOME/.zshenv" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc" 2>/dev/null \
            || echo "No DYLD_INSERT_LIBRARIES in launchd plists or shell startup files."

        echo; echo "== Autostart and persistence =="
        echo "-- User LaunchAgents:"
        ls -1 "$HOME/Library/LaunchAgents/"*.plist 2>/dev/null || echo "(none)"
        echo "-- System LaunchAgents and LaunchDaemons (third-party):"
        ls -1 /Library/LaunchAgents/*.plist /Library/LaunchDaemons/*.plist 2>/dev/null || echo "(none)"
        ls -1 /Library/StartupItems 2>/dev/null | sed 's/^/StartupItem (legacy): /'
        echo "-- Login and background items:"
        sfltool dumpbtm 2>/dev/null | awk '
            /^ +#[0-9]+:$/ { if (n != "") print n (d != "" && d != "(null)" ? " (" d ")" : ""); n = ""; d = "" }
            /^ +Name: /           { sub(/^ +Name: /, "");           n = $0 }
            /^ +Developer Name: / { sub(/^ +Developer Name: /, ""); d = $0 }
            END { if (n != "") print n (d != "" && d != "(null)" ? " (" d ")" : "") }' \
            | sort -u > "$WORK_DIR/btm"
        if [ -s "$WORK_DIR/btm" ]; then
            baseline_diff background_items "$WORK_DIR/btm"
        else
            echo "(could not read background items)"
        fi
        echo "-- Configuration profiles:"
        if [ "$have_sudo" = 1 ]; then sudo profiles list -all 2>&1; else profiles list 2>&1; fi
        echo "-- Cron:"
        crontab -l 2>/dev/null || echo "(no user crontab)"
        echo "-- Suspicious lines in shell startup files:"
        grep -nHE '(curl|wget)[^|#]*\|[[:space:]]*(ba|z)?sh|base64[[:space:]]+(-d|--decode|-D)|/dev/tcp/|nc[[:space:]].*-e[[:space:]]|DYLD_INSERT_LIBRARIES' \
            "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshenv" "$HOME/.zshrc" "$HOME/.zprofile" 2>/dev/null \
            || echo "(none)"

        echo; echo "== SSH authorized_keys =="
        local k
        : > "$WORK_DIR/keys"
        for k in "$HOME/.ssh/authorized_keys" "$HOME/.ssh/authorized_keys2"; do
            [ -f "$k" ] && shasum -a 256 "$k" >> "$WORK_DIR/keys"
        done
        if [ "$have_sudo" = 1 ] && sudo test -f /var/root/.ssh/authorized_keys; then
            sudo shasum -a 256 /var/root/.ssh/authorized_keys >> "$WORK_DIR/keys"
        fi
        if [ -s "$WORK_DIR/keys" ]; then
            baseline_diff authorized_keys "$WORK_DIR/keys"
        else
            echo "No authorized_keys files."
        fi

        # Sealed system volume plus the Data volume; /Users is skipped since
        # walking other apps' data there raises privacy prompts
        echo; echo "== SUID/SGID binaries =="
        local suid=("$FIND" / /System/Volumes/Data -xdev -path /System/Volumes/Data/Users -prune \
            -o -type f -perm "${PERM_ANY}6000" -print)
        if [ "$have_sudo" = 1 ]; then
            sudo "${suid[@]}" 2>/dev/null | sort > "$WORK_DIR/suid"
        else
            "${suid[@]}" 2>/dev/null | sort > "$WORK_DIR/suid"
        fi
        baseline_diff suid "$WORK_DIR/suid"

        # UDP in the ephemeral range (49152+) is client sockets that churn
        echo; echo "== Listening sockets =="
        {
            netstat -an -p tcp 2>/dev/null | awk '$6 == "LISTEN" {print $1, $4}'
            netstat -an -p udp 2>/dev/null | awk '$1 ~ /^udp/ {
                n = split($4, a, "."); if (a[n] ~ /^[0-9]+$/ && a[n] < 49152) print $1, $4 }'
        } | sort -u > "$WORK_DIR/listen"
        baseline_diff listening "$WORK_DIR/listen"

        echo; echo "== Browser extensions =="
        local ext_found=0 p as="$HOME/Library/Application Support"
        if command_exists jq; then
            for p in "$as"/Firefox/Profiles/*/extensions.json "$as"/librewolf/Profiles/*/extensions.json \
                     "$as"/zen/Profiles/*/extensions.json "$as"/Floorp/Profiles/*/extensions.json; do
                [ -f "$p" ] || continue
                ext_found=1
                echo "-- $p"
                jq -r '.addons[] | select(.location=="app-profile") | "\(.id)  \(.defaultLocale.name // "")"' "$p" 2>/dev/null
            done
        fi
        for p in "$as"/{Google/Chrome,Chromium,BraveSoftware/Brave-Browser,Vivaldi,"Microsoft Edge"}/*/Extensions; do
            [ -d "$p" ] || continue
            ext_found=1
            echo "-- $p"
            local e
            for e in "$p"/*/*/manifest.json; do
                [ -f "$e" ] || continue
                printf '%s  %s\n' "$(basename "$(dirname "$(dirname "$e")")")" \
                    "$(grep -m1 -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$e" | sed 's/.*:[[:space:]]*"//; s/"$//')"
            done
        done
        if pluginkit -mA -p com.apple.Safari.web-extension 2>/dev/null | grep -q .; then
            ext_found=1
            echo "-- Safari web extensions"
            pluginkit -mA -p com.apple.Safari.web-extension 2>/dev/null | sed 's/^[[:space:]+-]*//'
        fi
        [ "$ext_found" = 0 ] && echo "No browser profiles found."
    } 2>&1 | tee "$report"

    echo
    ui_ok "Audit report: $report"
    notify_replace virus-scan normal 8000 security-high "Integrity audit finished" "$report"
    if [ -s "$WORK_DIR/audit-changed" ] && [ "$NONINTERACTIVE" != 1 ]; then
        ui_warn "Changed since baseline: $(tr '\n' ' ' < "$WORK_DIR/audit-changed")"
        if confirm "Accept the current state as the new baseline?"; then
            local n
            while IFS= read -r n; do
                cp "$WORK_DIR/current-$n" "$BASELINE_DIR/$n"
            done < "$WORK_DIR/audit-changed"
            ui_ok "Baseline updated."
        fi
    fi
}

#########################################################
# Scheduling (launchd user agent)
#########################################################
SCHED_LABEL="com.piercingxx.virus-scan"
SCHED_PLIST="$HOME/Library/LaunchAgents/$SCHED_LABEL.plist"

timer_state() {
    if launchctl print "gui/$(id -u)/$SCHED_LABEL" >/dev/null 2>&1; then echo enabled; else echo disabled; fi
}

schedule_menu() {
    ui_title "Scheduled Scans"
    local cmd="$SCRIPT_PATH" domain="gui/$(id -u)"
    [ -x "$HOME/.scripts/PiercingXX-Settings-Menu/virus-scan.sh" ] && cmd="$HOME/.scripts/PiercingXX-Settings-Menu/virus-scan.sh"

    local state
    state=$(timer_state)
    ui_info "Weekly fast scan agent: $state"
    local choice
    choice=$(ui_choose "Scheduled scans" "Enable weekly fast scan (Sun 03:00)" "Disable" "Show next run" "Back") || return
    case "$choice" in
        "Enable weekly fast scan (Sun 03:00)")
            mkdir -p "$(dirname "$SCHED_PLIST")"
            cat > "$SCHED_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$SCHED_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BREW_PREFIX/bin/bash</string>
        <string>$cmd</string>
        <string>--preset</string>
        <string>fast</string>
        <string>--no-tui</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>0</integer>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>ProcessType</key>
    <string>Background</string>
    <key>Nice</key>
    <integer>19</integer>
    <key>LowPriorityIO</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$CLAM_STATE/scheduled-scan.out</string>
    <key>StandardErrorPath</key>
    <string>$CLAM_STATE/scheduled-scan.out</string>
</dict>
</plist>
EOF
            launchctl bootout "$domain/$SCHED_LABEL" 2>/dev/null
            launchctl bootstrap "$domain" "$SCHED_PLIST" &&
                ui_ok "Weekly scan enabled. Results land in $LOG_DIR and as a notification."
            ui_info "Desktop, Documents and Downloads are skipped unless $BREW_PREFIX/bin/bash"
            ui_info "has Full Disk Access (System Settings > Privacy & Security)."
            ;;
        "Disable")
            launchctl bootout "$domain/$SCHED_LABEL" 2>/dev/null
            rm -f "$SCHED_PLIST"
            ui_ok "Weekly scan disabled."
            ;;
        "Show next run")
            if [ "$state" = enabled ]; then
                ui_info "Sundays at 03:00; a run missed while the Mac slept starts on wake."
                launchctl print "$domain/$SCHED_LABEL" 2>/dev/null | grep -E '^[[:space:]]+(state|runs|last exit code) ='
            else
                ui_info "Not scheduled."
            fi
            ;;
        *) return ;;
    esac
    pause
}

#########################################################
# Extra (third-party) signatures
#########################################################
extra_signatures() {
    ui_title "Extra Signatures (optional)"
    ui_info "SaneSecurity, URLhaus and similar feeds add phishing, macro and Linux malware coverage."
    ui_info "Install fangfrisch with 'pipx install fangfrisch',"
    ui_info "then follow https://rseichter.github.io/fangfrisch/ to point it at $(db_dir)."
    pause
}

#########################################################
# Interactive pieces
#########################################################
custom_scan() {
    local how scan_path
    how=$(ui_choose "Custom scan" "Type a path" "Browse for a folder" "Back") || return
    case "$how" in
        "Type a path")
            if [ "$HAS_GUM" = 1 ]; then
                scan_path=$(gum input --placeholder "Path to scan (e.g. ~/Documents or /Volumes/usb)")
            else
                read -r -e -p "Path to scan: " scan_path
            fi ;;
        "Browse for a folder")
            if [ "$HAS_GUM" = 1 ]; then
                scan_path=$(gum file --directory --all "$HOME")
            else
                read -r -e -p "Path to scan: " scan_path
            fi ;;
        *) return ;;
    esac
    [ -n "$scan_path" ] || { ui_err "No path provided."; return; }
    # Expand a leading ~ the way a shell would
    case "$scan_path" in
        "~")   scan_path="$HOME" ;;
        "~/"*) scan_path="$HOME/${scan_path#\~/}" ;;
    esac
    scan_preset custom "$scan_path"
}

file_scan() {
    local f
    if [ "$HAS_GUM" = 1 ]; then
        f=$(gum file --all "$HOME")
    else
        read -r -e -p "File to scan: " f
    fi
    [ -n "$f" ] || { ui_err "No file selected."; return; }
    [ -f "$f" ] || { ui_err "Not a file: $f"; return; }
    scan_preset custom "$f"
}

main_menu() {
    install_clamav || { pause; exit 1; }

    while true; do
        clear
        if [ "$HAS_GUM" = 1 ]; then
            gum style --border double --padding "1 2" --foreground 6 --bold "🦠 ClamAV Virus Scanner"
        else
            printf '\n== ClamAV Virus Scanner ==\n'
        fi

        local strict_label="⚙️  Strict Heuristics: off"
        [ "$STRICT" = 1 ] && strict_label="⚙️  Strict Heuristics: on"
        local choice
        choice=$(ui_choose "What now" \
            "🔄 Update Virus Definitions" \
            "⚡ Quick Scan" \
            "🚀 Fast Targeted Scan" \
            "📥 Recent Downloads Scan" \
            "🔍 Full Home Directory Scan" \
            "📁 Scan Custom Path" \
            "📄 Scan Specific File" \
            "🧪 System Integrity Audit" \
            "🗄️  Quarantine" \
            "📊 Status" \
            "⏰ Scheduled Scans" \
            "🧩 Extra Signatures" \
            "$strict_label" \
            "📋 Logs & History" \
            "🚪 Back to Main Menu") || choice=""

        case "$choice" in
            "🔄 Update Virus Definitions") update_definitions; pause ;;
            "⚡ Quick Scan")               scan_preset quick; pause ;;
            "🚀 Fast Targeted Scan")       scan_preset fast; pause ;;
            "📥 Recent Downloads Scan")    scan_preset downloads; pause ;;
            "🔍 Full Home Directory Scan")
                confirm "Scan your entire home directory? This can take a long time." || continue
                scan_preset full; pause ;;
            "📁 Scan Custom Path")         custom_scan; pause ;;
            "📄 Scan Specific File")       file_scan; pause ;;
            "🧪 System Integrity Audit")   integrity_audit; pause ;;
            "🗄️  Quarantine")              quarantine_menu ;;
            "📊 Status")                   show_status; pause ;;
            "⏰ Scheduled Scans")           schedule_menu ;;
            "🧩 Extra Signatures")         extra_signatures ;;
            "⚙️  Strict Heuristics:"*)
                if [ "$STRICT" = 1 ]; then STRICT=0; else STRICT=1; fi
                SCANNER_READY=0
                [ "$STRICT" = 1 ] && ui_info "Strict mode alerts on encrypted archives, broken executables and macros (clamscan only)."
                pause ;;
            "📋 Logs & History")           logs_menu ;;
            "🚪 Back to Main Menu"|"")     clear; exit 0 ;;
        esac
    done
}

usage() {
    sed -n '7,14p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
}

#########################################################
# Entry point
#########################################################
ACTION="menu"
PRESET=""
PRESET_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)   usage; exit 0 ;;
        --update-db) ACTION="update-db" ;;
        --status)    ACTION="status" ;;
        --preset)
            ACTION="preset"
            PRESET="${2:-}"; shift
            if [ "$PRESET" = custom ]; then
                PRESET_PATH="${2:-}"; shift
            fi ;;
        --no-tui)    NONINTERACTIVE=1; HAS_GUM=0 ;;
        --move)      AUTO_MOVE=1 ;;
        --strict)    STRICT=1 ;;
        *) err "Unknown option: $1"; usage; exit 2 ;;
    esac
    shift
done
# Non-terminal callers (launchd, other scripts) never get prompts
[ -t 0 ] || NONINTERACTIVE=1

init_dirs

case "$ACTION" in
    update-db)
        command_exists clamscan || { err "ClamAV is not installed."; exit 2; }
        update_definitions
        exit $? ;;
    status)
        show_status
        exit 0 ;;
    preset)
        install_clamav || exit 2
        scan_preset "$PRESET" "$PRESET_PATH"
        exit $? ;;
    *)
        main_menu ;;
esac
