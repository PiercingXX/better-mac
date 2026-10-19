#!/bin/sh
# GitHub.com/PiercingXX
#
# Full system update: distro packages, AUR, firmware, flatpak, toolchains,
# editor/shell plugins, then a self-update of ~/.scripts and ~/.bashrc.
#
# Env knobs:
#   PX_NO_SELF_UPDATE=1   don't refresh ~/.scripts / ~/.bashrc
#   PX_NO_SNAPSHOT=1      skip the pre-update Time Machine local snapshot
#   PX_GITHUB_DIR=path    folder of git repos to fast-forward
#
# macOS port (better-mac): Homebrew (formulae + casks) is the system package
# step; softwareupdate replaces fwupd, mas (Mac App Store) is added, Time
# Machine local snapshots replace timeshift/snapper. ~/.scripts is an exact
# copy of better-mac's dots/scripts, so the self-update syncs it from the
# better-mac checkout (no GitHub API, jq or GITHUB_TOKEN); .bashrc still comes
# from piercing-dots, wrapped in better-mac's pre/post layers. Dropped (no
# macOS meaning): Arch news/mirrors/AUR/paru/pacnew/bootloader checks,
# apt/dnf/zypper/xbps/apk and Ubuntu Touch upgrades, flatpak, snap, Synology
# .deb, Hyprland builds and hyprpm, PX_AUR_NOCONFIRM.

# Bootstrap: AeroSpace/Sol launches may only find Apple's bash 3.2, so
# re-exec under Homebrew's bash 5.
if [ -z "${PX_BASH_REEXEC:-}" ]; then
    for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [ -x "$b" ]; then
            PX_BASH_REEXEC=1
            export PX_BASH_REEXEC
            exec "$b" "$0" "$@"
        fi
    done
    echo "This script requires Homebrew's bash (brew install bash)." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Everything below runs under bash. The body lives in main() and the last
# line is `main "$@"; exit $?`, so bash has parsed the whole file before any
# of it runs and the self-update can safely replace this file.
# ---------------------------------------------------------------------------

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
GITHUB_REPO="Piercingxx/piercing-dots"
GITHUB_BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH"

# Where better-mac.sh was last run from (it records this on every run)
BETTER_MAC_ROOT=""
if [ -f "$HOME/.config/better-mac/root" ]; then
    BETTER_MAC_ROOT=$(head -n 1 "$HOME/.config/better-mac/root")
    [ -d "$BETTER_MAC_ROOT/dots/scripts" ] || BETTER_MAC_ROOT=""
fi
SCRIPTS_SRC="${BETTER_MAC_ROOT:+$BETTER_MAC_ROOT/dots/scripts}"

# Shared helpers. ~/.scripts comes from better-mac, so restore the lib from
# the checkout (never piercing-dots' Linux one) if it's missing.
PX_LIB="$SCRIPT_DIR/../lib/common.sh"
if [ ! -r "$PX_LIB" ]; then
    if [ -n "$SCRIPTS_SRC" ] && [ -r "$SCRIPTS_SRC/lib/common.sh" ]; then
        mkdir -p "$(dirname "$PX_LIB")"
        cp "$SCRIPTS_SRC/lib/common.sh" "$PX_LIB"
    else
        echo "Missing $PX_LIB; rerun better-mac.sh to restore it." >&2
        exit 1
    fi
fi
# shellcheck disable=SC1090
. "$PX_LIB"

if [[ -d "$HOME/.cargo/bin" && ":$PATH:" != *":$HOME/.cargo/bin:"* ]]; then
    PATH="$HOME/.cargo/bin:$PATH"
fi
if [[ -d "$HOME/.local/bin" && ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    PATH="$HOME/.local/bin:$PATH"
fi

detect_distro

INTERACTIVE=0
[ -t 0 ] && INTERACTIVE=1

# Step results for the end-of-run table
STEP_NAMES=()
STEP_STATUS=()
REBOOT_REASONS=()
SKIP=3          # step return code: not applicable, don't list it
SKIPPED=4       # step return code: deliberately skipped, list it

PX_TMP_DIR=""
SUDO_KEEPALIVE_PID=""
LOG_FILE=""

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

record_step() {
    STEP_NAMES+=("$1")
    STEP_STATUS+=("$2")
}

# run_step "Label" func [args...]
run_step() {
    local label="$1" rc
    shift
    "$@"
    rc=$?
    case "$rc" in
        0)        record_step "$label" ok ;;
        "$SKIP")  ;;
        "$SKIPPED") record_step "$label" skipped ;;
        *)        record_step "$label" failed ;;
    esac
    return "$rc"
}

# ask_yes "Question?" Y|N  -> non-interactive runs take the default
ask_yes() {
    local q="$1" def="${2:-N}" reply hint="[y/N]"
    [ "$def" = Y ] && hint="[Y/n]"
    if [ "$INTERACTIVE" -ne 1 ]; then
        [ "$def" = Y ]
        return
    fi
    read -r -p "$q $hint " reply </dev/tty
    reply=${reply:-$def}
    [[ "$reply" =~ ^[Yy] ]]
}

cleanup() {
    [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    [ -n "$PX_TMP_DIR" ] && rm -rf "$PX_TMP_DIR"
}

# Reliable-ish internet check
check_internet() {
    local timeout=4 url code body host
    local urls=(
        "https://connectivitycheck.gstatic.com/generate_204"
        "http://www.google.com/generate_204"
        "http://www.msftncsi.com/ncsi.txt"
        "http://www.msftconnecttest.com/connecttest.txt"
    )
    for url in "${urls[@]}"; do
        code=$(curl -4 -fsS --max-time "$timeout" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
        if [[ "$code" == "204" ]]; then
            return 0
        fi
        if [[ "$code" == "200" && "$url" == *"msft"* ]]; then
            body=$(curl -4 -fsS --max-time "$timeout" "$url" 2>/dev/null | tr -d '\r\n')
            if [[ "$body" == "Microsoft NCSI" || "$body" == "Microsoft Connect Test" ]]; then
                return 0
            fi
        fi
    done
    for host in 1.1.1.1 8.8.8.8 9.9.9.9; do
        # macOS ping: -t is the overall timeout in seconds
        if ping -c 1 -t 1 "$host" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Self-update: ~/.scripts from the better-mac checkout, ~/.bashrc from
# GitHub (runs last; the git step has already pulled better-mac)
# ---------------------------------------------------------------------------

prune_backups() {
    local pattern="$1" keep="${2:-5}" d
    for d in "$PX_STATE_DIR"/backups/$pattern/; do
        [ -d "$d" ] && basename "$d"
    done | sort -r | tail -n +$((keep + 1)) \
        | while read -r old; do rm -rf "${PX_STATE_DIR:?}/backups/$old"; done
}

# Older launch-*.sh kept the host in a REMOTE= line; hosts now live in
# ~/.config/piercingxx/remotes.conf. Carry a customized value over once.
migrate_remote_line() {
    local rel="$1" saved="$2" key value conf
    [ -n "$saved" ] || return 0
    case "$rel" in
        Control-Scripts/launch-skippy-remote.sh) key="SKIPPY_HOST" ;;
        Control-Scripts/launch-server-monitor.sh|Control-Scripts/launch-ollama-remote.sh) key="SERVER_HOST" ;;
        *) return 0 ;;
    esac
    value=$(printf '%s' "${saved#REMOTE=}" | tr -d '"'"'")
    [ -n "$value" ] || return 0
    conf="${XDG_CONFIG_HOME:-$HOME/.config}/piercingxx/remotes.conf"
    if [ -f "$conf" ] && grep -q "^$key=" "$conf"; then
        return 0
    fi
    mkdir -p "$(dirname "$conf")"
    printf '%s="%s"\n' "$key" "$value" >> "$conf"
    say "Moved $key=$value from $rel into $conf"
}

# ~/.scripts is an exact copy of better-mac's dots/scripts
sync_scripts() {
    local backup="$1"
    local local_root="$HOME/.scripts"
    local src="$SCRIPTS_SRC"

    if [ -L "$local_root" ]; then
        say "~/.scripts is a symlink (dev checkout); not overwriting it."
        return "$SKIPPED"
    fi
    if [ -z "$src" ]; then
        warn "better-mac checkout not found (~/.config/better-mac/root); skipping the scripts self-update."
        return "$SKIPPED"
    fi

    mkdir -p "$local_root"
    local updated=0 removed=0 rel target new saved_remote
    while IFS= read -r rel; do
        target="$local_root/$rel"
        [ -L "$target" ] && continue
        [ -f "$target" ] && cmp -s "$src/$rel" "$target" && continue

        saved_remote=""
        if [[ "$rel" == Control-Scripts/launch-*.sh && -f "$target" ]]; then
            saved_remote=$(grep -m1 -E '^REMOTE=' "$target" || true)
        fi
        migrate_remote_line "$rel" "$saved_remote"

        mkdir -p "$(dirname "$target")"
        if [ -f "$target" ]; then
            mkdir -p "$backup/scripts/$(dirname "$rel")"
            cp -a "$target" "$backup/scripts/$rel"
        fi
        new="$target.px-new"
        if ! cp "$src/$rel" "$new"; then
            warn "Failed to copy $rel"
            rm -f "$new"
            return 1
        fi
        if [ -x "$src/$rel" ] || [ "$(head -c2 "$new")" = '#!' ]; then
            chmod 755 "$new"
        else
            chmod 644 "$new"
        fi
        # rename() is atomic and leaves the running copy's inode alone
        mv -f "$new" "$target"
        rm -f "$target.upstream"
        echo -e "${green}Updated ~/.scripts/$rel${nc}"
        updated=$((updated + 1))
    done < <(cd "$src" && find . -type f ! -name '.DS_Store' | sed 's|^\./||' | sort)

    # Files better-mac no longer ships (kept in the backup)
    while IFS= read -r rel; do
        [ -e "$src/$rel" ] && continue
        mkdir -p "$backup/scripts/$(dirname "$rel")"
        mv -f "$local_root/$rel" "$backup/scripts/$rel"
        echo -e "${yellow}Removed ~/.scripts/$rel${nc}"
        removed=$((removed + 1))
    done < <(cd "$local_root" && find . -type f ! -name '.DS_Store' ! -name '*.px-new' | sed 's|^\./||' | sort)

    if [ $((updated + removed)) -gt 0 ]; then
        ok "Updated $updated and removed $removed script(s) from $BETTER_MAC_ROOT. Previous versions: $backup/scripts"
    else
        ok "~/.scripts is already up to date."
    fi
}

update_bashrc() {
    local backup="$1" new raw
    if [ -L "$HOME/.bashrc" ]; then
        say "~/.bashrc is a symlink; not overwriting it."
        return "$SKIPPED"
    fi
    raw="$PX_TMP_DIR/bashrc"
    if ! curl -fsSL --max-time 30 "$RAW_BASE/resources/bash/.bashrc" -o "$raw"; then
        warn "Failed to download .bashrc from GitHub."
        return 1
    fi
    # Same layout better-mac's shell module writes: pre.bash + .bashrc + post.bash
    new="$HOME/.bashrc.px-new"
    # shellcheck disable=SC2016
    {
        printf '%s\n' '# better-mac: Homebrew and GNU tools first (see ~/.config/better-mac/pre.bash)'
        printf '%s\n\n' '[ -f "$HOME/.config/better-mac/pre.bash" ] && . "$HOME/.config/better-mac/pre.bash"'
        cat "$raw"
        printf '\n%s\n' '# better-mac: macOS replacements for Linux-only bits (see ~/.config/better-mac/post.bash)'
        printf '%s\n' '[ -f "$HOME/.config/better-mac/post.bash" ] && . "$HOME/.config/better-mac/post.bash"'
    } >"$new"
    if [ -f "$HOME/.bashrc" ] && cmp -s "$HOME/.bashrc" "$new"; then
        rm -f "$new"
        return 0
    fi
    if [ -f "$HOME/.bashrc" ]; then
        mkdir -p "$backup"
        cp -a "$HOME/.bashrc" "$backup/.bashrc"
    fi
    chmod 644 "$new"
    mv -f "$new" "$HOME/.bashrc"
    ok ".bashrc has been updated. Previous version: $backup/.bashrc"
}

self_update() {
    if [ "${PX_NO_SELF_UPDATE:-0}" = 1 ]; then
        say "PX_NO_SELF_UPDATE=1: leaving ~/.scripts and ~/.bashrc alone."
        return "$SKIP"
    fi
    local backup
    backup="$PX_STATE_DIR/backups/scripts-$(date +%Y%m%d-%H%M%S)"
    run_step "Scripts self-update" sync_scripts "$backup"
    run_step ".bashrc update" update_bashrc "$backup"
    prune_backups 'scripts-*' 5
}

# ---------------------------------------------------------------------------
# Snapshots (Time Machine) and macOS updates
# ---------------------------------------------------------------------------

# Local APFS snapshot; only useful when Time Machine is set up
pre_update_snapshot() {
    [ "${PX_NO_SNAPSHOT:-0}" = 1 ] && return "$SKIP"
    tmutil destinationinfo >/dev/null 2>&1 || return "$SKIP"
    say "Creating a Time Machine local snapshot before updating..."
    tmutil localsnapshot
}

# Homebrew formulae and casks (the system package step on macOS)
brew_upgrade() {
    [ "$PKG" = brew ] || { err "Homebrew not found (https://brew.sh)."; return 1; }
    say "Updating Homebrew..."
    # Unused dependencies and old versions are removed by Clean System, not here
    HOMEBREW_NO_ASK=1 brew update && HOMEBREW_NO_ASK=1 brew upgrade
}

update_mas() {
    command_exists mas || return "$SKIP"
    say "Updating App Store apps (mas)..."
    mas upgrade
}

# macOS and firmware updates (fwupd's job on Linux)
update_macos() {
    local list
    say "Checking for macOS updates..."
    list=$(softwareupdate -l 2>&1)
    if ! printf '%s\n' "$list" | grep -q '^\* Label:'; then
        ok "No macOS updates."
        return 0
    fi
    printf '%s\n' "$list" | grep -E '^\* Label:|Title:'
    # Only updates within the running major version; `-ia` would also
    # start a major macOS upgrade
    local major labels=() restart=0 label ver act title
    major=$(sw_vers -productVersion | cut -d. -f1)
    while IFS=$'\t' read -r label ver act title; do
        if [[ "$title" == macOS* && "${ver%%.*}" != "$major" ]]; then
            continue
        fi
        labels+=("$label")
        [ "$act" = restart ] && restart=1
    done < <(printf '%s\n' "$list" | awk '
        /^\* Label: / { sub(/^\* Label: /, ""); label = $0; next }
        label != "" && /Title:/ {
            v = ""; a = ""; t = ""
            if (match($0, /Title: [^,]*/))   t = substr($0, RSTART + 7, RLENGTH - 7)
            if (match($0, /Version: [^,]*/)) v = substr($0, RSTART + 9, RLENGTH - 9)
            if (match($0, /Action: [^,]*/))  a = substr($0, RSTART + 8, RLENGTH - 8)
            print label "\t" v "\t" a "\t" t; label = ""
        }')
    if [ ${#labels[@]} -eq 0 ]; then
        say "Only a major macOS upgrade is available; start it from System Settings > General > Software Update."
        return "$SKIPPED"
    fi
    if ! ask_yes "Install ${#labels[@]} macOS update(s) now? (some need a restart)" N; then
        say "Install later from System Settings > General > Software Update."
        return "$SKIPPED"
    fi
    sudo softwareupdate -i "${labels[@]}" || return 1
    [ "$restart" -eq 1 ] && REBOOT_REASONS+=("macOS updates were installed")
    return 0
}

# ---------------------------------------------------------------------------
# Universal steps (each gated on the tool existing)
# ---------------------------------------------------------------------------

update_npm_globals() {
    command_exists npm || return "$SKIP"
    local prefix
    prefix=$(npm config get prefix 2>/dev/null || true)
    case "$prefix" in
        /usr|""|undefined)
            say "Skipping global npm update: npm prefix is $prefix."
            return "$SKIP" ;;
        *)
            # Homebrew's node keeps globals in a user-writable prefix
            say "Updating global npm packages ($prefix)..."
            npm update -g --silent --no-progress ;;
    esac
}

update_cargo() {
    command_exists cargo || return "$SKIP"
    [ -n "$(cargo install --list 2>/dev/null)" ] || return "$SKIP"
    say "Updating cargo-installed binaries..."
    if ! cargo install-update --version >/dev/null 2>&1; then
        cargo install cargo-update || return 1
    fi
    cargo install-update -a
}

update_rustup() {
    command_exists rustup || return "$SKIP"
    rustup toolchain list 2>/dev/null | grep -qv 'no installed toolchains' || return "$SKIP"
    say "Updating Rust toolchains (rustup)..."
    rustup update
}

update_pipx() {
    command_exists pipx || return "$SKIP"
    [ -n "$(pipx list --short 2>/dev/null)" ] || return "$SKIP"
    say "Updating pipx apps..."
    pipx upgrade-all
}

update_uv_tools() {
    command_exists uv || return "$SKIP"
    uv tool list 2>/dev/null | grep -q . || return "$SKIP"
    uv tool list 2>/dev/null | grep -q 'No tools installed' && return "$SKIP"
    say "Updating uv tools..."
    uv tool upgrade --all
}

update_gh_extensions() {
    command_exists gh || return "$SKIP"
    [ -n "$(gh extension list 2>/dev/null)" ] || return "$SKIP"
    say "Updating gh extensions..."
    gh extension upgrade --all
}

update_docker_images() {
    command_exists docker || return "$SKIP"
    docker info >/dev/null 2>&1 || return "$SKIP"
    local -a images
    mapfile -t images < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | sort -u)
    [ ${#images[@]} -gt 0 ] || return "$SKIP"
    say "Pulling ${#images[@]} Docker image(s)..."
    local img
    for img in "${images[@]}"; do
        echo "  • ${img}"
        # Locally built images have no registry copy; that's fine
        docker pull --quiet "$img" >/dev/null 2>&1 || echo "    (not pulled)"
    done
    say "Unused images and stopped containers are cleaned from Clean System."
    return 0
}

update_yazi() {
    command_exists ya || return "$SKIP"
    local cfg="$HOME/.config/yazi/package.toml" rc=0 tmp
    say "Updating yazi plugins..."
    if [ -f "$cfg" ]; then
        # BSD sed -i needs a suffix argument; edit through a temp file instead
        tmp="$PX_TMP_DIR/package.toml"
        sed -e 's/system-clipboard\.yazi/system-clipboard-yazi/g' "$cfg" >"$tmp" \
            && ! cmp -s "$tmp" "$cfg" && cat "$tmp" >"$cfg"
    fi
    ya pkg upgrade || rc=1
    if [ -f "$cfg" ]; then
        local -a desired installed
        local plugin
        mapfile -t desired < <(grep '^use = ' "$cfg" | sed -E 's/use = "(.*)"/\1/' | sort)
        mapfile -t installed < <(ya pkg list 2>/dev/null | awk '{print $1}' | sort)
        for plugin in "${desired[@]}"; do
            if ! printf '%s\n' "${installed[@]}" | grep -qx "$plugin"; then
                say "Adding missing yazi plugin: $plugin"
                ya pkg add "$plugin" || rc=1
            fi
        done
    fi
    return "$rc"
}

update_nvim_plugins() {
    command_exists nvim || return "$SKIP"
    [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/nvim" ] || return "$SKIP"
    say "Updating Neovim plugins (vim.pack)..."
    # force=true applies updates directly instead of opening the review buffer
    nvim --headless \
        "+lua if vim.pack and vim.pack.update then local ok, e = pcall(vim.pack.update, nil, { force = true }); if not ok then io.stderr:write(tostring(e) .. '\n'); vim.cmd('cquit 1') end end" \
        "+qa" 2>&1
}

update_clamav() {
    command_exists freshclam || return "$SKIP"
    local vs="$SCRIPT_DIR/virus-scan.sh"
    if [ -f "$vs" ] && grep -q -- '--update-db' "$vs"; then
        bash "$vs" --update-db
        return
    fi
    if svc_is_active clamav; then
        say "The ClamAV service keeps definitions current; skipping."
        return 0
    fi
    # Homebrew's ClamAV database is user-owned; no sudo
    say "Updating ClamAV virus definitions..."
    freshclam
}

# Fast-forward every clean repo in the GitHub folder
git_pull_all_github_repos() {
    command_exists git || return "$SKIP"
    local base_dir="${PX_GITHUB_DIR:-$PX_WORK_ROOT/GitHub}" alt repo name
    if [ ! -d "$base_dir" ]; then
        # The folder holding the better-mac checkout is the usual one on the Mac
        for alt in ${BETTER_MAC_ROOT:+"$(dirname "$BETTER_MAC_ROOT")"} \
            "$HOME/GitHub" "$HOME/Projects" "$HOME/Workspace" "$HOME/src"; do
            if [ -d "$alt" ]; then
                base_dir="$alt"
                break
            fi
        done
    fi
    [ -d "$base_dir" ] || return "$SKIP"

    say "Updating git repositories in $base_dir..."
    local -a updated=() dirty=() failed=() noupstream=()
    for repo in "$base_dir"/*; do
        [ -d "$repo/.git" ] || continue
        name=$(basename "$repo")
        if ! git -C "$repo" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
            noupstream+=("$name")
            continue
        fi
        if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
            dirty+=("$name")
            continue
        fi
        if GIT_TERMINAL_PROMPT=0 git -C "$repo" pull --ff-only --quiet 2>/dev/null; then
            updated+=("$name")
        else
            failed+=("$name")
        fi
    done
    ok "  ${#updated[@]} repo(s) up to date."
    [ ${#dirty[@]} -gt 0 ] && warn "  Skipped (local changes): ${dirty[*]}"
    [ ${#noupstream[@]} -gt 0 ] && say "  No upstream branch: ${noupstream[*]}"
    [ ${#failed[@]} -gt 0 ] && warn "  Could not fast-forward: ${failed[*]}"
    [ ${#failed[@]} -eq 0 ]
}

universal_steps() {
    run_step "macOS (softwareupdate)" update_macos
    run_step "App Store (mas)" update_mas
    run_step "npm globals" update_npm_globals
    run_step "Cargo binaries" update_cargo
    run_step "Rust toolchains" update_rustup
    run_step "pipx apps" update_pipx
    run_step "uv tools" update_uv_tools
    run_step "gh extensions" update_gh_extensions
    run_step "Docker images" update_docker_images
    run_step "Yazi plugins" update_yazi
    run_step "Neovim plugins" update_nvim_plugins
    run_step "ClamAV definitions" update_clamav
    run_step "Git repositories" git_pull_all_github_repos
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_summary() {
    local i mark failures=0
    echo
    echo -e "${blue}Update summary${nc}"
    for i in "${!STEP_NAMES[@]}"; do
        case "${STEP_STATUS[$i]}" in
            ok)      mark="${green}ok${nc}" ;;
            skipped) mark="${yellow}skipped${nc}" ;;
            *)       mark="${red}FAILED${nc}"; failures=$((failures + 1)) ;;
        esac
        printf '  %-28s %b\n' "${STEP_NAMES[$i]}" "$mark"
    done
    if [ ${#REBOOT_REASONS[@]} -gt 0 ]; then
        echo
        warn "Reboot recommended:"
        printf '  - %s\n' "${REBOOT_REASONS[@]}" | sort -u
    fi
    echo
    say "Full log: $LOG_FILE"
    return "$failures"
}

notify_result() {
    local core_rc="$1" failures="$2" summary body urgency=normal
    if [ "$core_rc" -ne 0 ]; then
        summary="System update failed"
        body="The package upgrade did not complete. Log: $LOG_FILE"
        urgency=critical
    elif [ "$failures" -gt 0 ]; then
        summary="System update finished with problems"
        body="$failures step(s) failed. Log: $LOG_FILE"
    else
        summary="System update complete"
        body="Everything is up to date."
    fi
    if [ ${#REBOOT_REASONS[@]} -gt 0 ]; then
        body="$body Reboot recommended."
    fi
    notify_replace system-update "$urgency" 10000 software-update-available "$summary" "$body"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    PX_TMP_DIR=$(mktemp -d)
    trap cleanup EXIT
    trap 'exit 130' INT TERM

    # Persistent log (ANSI colors stripped in the file; BSD sed has no \x1b)
    mkdir -p "$PX_STATE_DIR/logs"
    LOG_FILE="$PX_STATE_DIR/logs/update-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee >(sed -u $'s/\033\\[[0-9;?]*[A-Za-z]//g' >> "$LOG_FILE")) 2>&1
    find "$PX_STATE_DIR/logs" -name 'update-*.log' -mtime +30 -delete 2>/dev/null

    # One update at a time (update-notify.sh also checks this lock)
    if ! single_instance update-system; then
        err "Another system update is already running."
        exit 1
    fi

    if ! check_internet; then
        err "Internet connectivity is required to continue."
        exit 1
    fi

    # softwareupdate and Docker/ClamAV helpers may need sudo
    sudo -v || { err "sudo authentication failed."; exit 1; }
    # Drop the log pipe so a lingering sleep can't hold it after we exit
    ( exec >/dev/null 2>&1
      while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!

    echo -e "${green}Starting system update (macOS $(sw_vers -productVersion 2>/dev/null))...${nc}\n"

    local core_rc=0
    run_step "Pre-update snapshot" pre_update_snapshot
    run_step "System packages (Homebrew)" brew_upgrade || core_rc=1

    if [ "$core_rc" -eq 0 ]; then
        universal_steps
        self_update
    else
        warn "Skipping the remaining steps because the package upgrade failed."
    fi

    local failures
    print_summary
    failures=$?
    notify_result "$core_rc" "$failures"

    if [ "$core_rc" -ne 0 ]; then
        return 1
    fi
    ok "System update finished."
    return 0
}

main "$@"; exit $?
