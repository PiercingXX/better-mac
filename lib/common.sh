# shellcheck shell=bash
# GitHub.com/PiercingXX
# Logging, dry-run plumbing, file installs and Homebrew helpers.
# Bash 3.2-safe: this runs under Apple's /bin/bash on a fresh Mac.

if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
    C_SAY=$'\033[1;37m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[1;33m'; C_MUTED=$'\033[2m'; NC=$'\033[0m'
else
    C_SAY=""; C_OK=""; C_WARN=""; C_MUTED=""; NC=""
fi

WARNINGS=()

say()  { printf '%s==>%s %s\n' "$C_SAY" "$NC" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_OK" "$NC" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_WARN" "$NC" "$*"; WARNINGS+=("$*"); }
dry()  { printf '%s  [dry-run]%s %s\n' "$C_MUTED" "$NC" "$*"; }

# run <cmd...>: execute, or just print it under --dry-run
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "$*"
        return 0
    fi
    "$@"
}

# wait_for_user <message>: print a step the user has to do by hand, then wait
wait_for_user() {
    printf '     %s\n' "$1"
    read -r -p "     Press Enter when done... " _
}

install_summary() {
    if [ ${#WARNINGS[@]} -eq 0 ]; then
        ok "No warnings."
        return 0
    fi
    say "Warnings:"
    local w
    for w in "${WARNINGS[@]}"; do
        printf '%s  !%s %s\n' "$C_WARN" "$NC" "$w"
    done
}

# ---------------------------------------------------------------------------
# Files: anything we replace is kept as <name>.bak.<timestamp>
# ---------------------------------------------------------------------------
install_file() {
    local src="$1" dest="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "install ${src#"$BETTER_MAC_ROOT"/} -> $dest"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
        cp -p "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
    fi
    cp "$src" "$dest"
}

install_dir() {
    local src="$1" dest="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "install ${src#"$BETTER_MAC_ROOT"/}/ -> $dest/"
        return 0
    fi
    if [ -e "$dest" ] && ! diff -rq "$src" "$dest" >/dev/null 2>&1; then
        mv "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
    fi
    mkdir -p "$dest"
    cp -R "$src/." "$dest/"
}

# overlay_dir <src> <dest>: copy files over what's there, no backup. For apps
# that rewrite their own config (htop, GIMP), like piercing-dots' cp -Rf.
overlay_dir() {
    local src="$1" dest="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "overlay ${src#"$BETTER_MAC_ROOT"/}/ -> $dest/"
        return 0
    fi
    mkdir -p "$dest"
    cp -R "$src/." "$dest/"
}

# ---------------------------------------------------------------------------
# piercing-dots: cloned once per run and shared by every module. Point
# PIERCING_DOTS_DIR at a local checkout to skip the clone.
# ---------------------------------------------------------------------------
PIERCING_DOTS_REPO="https://github.com/PiercingXX/piercing-dots.git"
PIERCING_DOTS_DIR="${PIERCING_DOTS_DIR:-}"
_PIERCING_DOTS_TMP=""

ensure_piercing_dots() {
    [ -n "$PIERCING_DOTS_DIR" ] && [ -d "$PIERCING_DOTS_DIR" ] && return 0
    _PIERCING_DOTS_TMP="$(mktemp -d)"
    if git clone --depth 1 -q "$PIERCING_DOTS_REPO" "$_PIERCING_DOTS_TMP/piercing-dots"; then
        PIERCING_DOTS_DIR="$_PIERCING_DOTS_TMP/piercing-dots"
        return 0
    fi
    warn "Could not clone piercing-dots."
    return 1
}

cleanup_piercing_dots() {
    [ -n "$_PIERCING_DOTS_TMP" ] && rm -rf "$_PIERCING_DOTS_TMP"
    _PIERCING_DOTS_TMP=""
}

# ---------------------------------------------------------------------------
# Homebrew
# ---------------------------------------------------------------------------
# Homebrew 7 asks y/N before every install; this is an unattended installer
export HOMEBREW_NO_ASK=1

_brew_shellenv() {
    local b
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then
            eval "$("$b" shellenv)"
            return 0
        fi
    done
    return 1
}

ensure_brew() {
    command -v brew >/dev/null 2>&1 || _brew_shellenv
    command -v brew >/dev/null 2>&1 && return 0
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "install Homebrew"
        return 0
    fi
    say "Installing Homebrew (this also installs the Xcode Command Line Tools)..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
    _brew_shellenv
}

# brew_formula / brew_cask <name...>: install what's missing, warn and keep
# going on failures (same rule as linux-mod's pi)
brew_formula() {
    local f
    for f in "$@"; do
        brew list --formula "${f##*/}" >/dev/null 2>&1 && continue
        run brew install "$f" || warn "brew install $f failed"
    done
}

brew_cask() {
    local c
    for c in "$@"; do
        brew list --cask "${c##*/}" >/dev/null 2>&1 && continue
        run brew install --cask "$c" || warn "brew install --cask $c failed"
    done
}

# login_item <app path>: open the app at every login (General > Login Items),
# added once through System Events
login_item() {
    local app="$1" name
    name="$(basename "$app" .app)"
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "login item: $name"
        return 0
    fi
    [ -d "$app" ] || return 0
    osascript -e 'tell application "System Events" to get name of every login item' 2>/dev/null \
        | tr ',' '\n' | sed 's/^ *//' | grep -qx "$name" && return 0
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$app\", hidden:true}" >/dev/null \
        || warn "Could not add $name as a login item; add it under General > Login Items."
}
