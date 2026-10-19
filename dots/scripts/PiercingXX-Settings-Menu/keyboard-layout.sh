#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Keyboard Layout: switch the running session's layout (Hyprland, Sway, X11),
# optionally save it to the Hyprland config, and set the system default
# (TTY + X11) with localectl. install.sh defaults everything to us/colemak.
#
# Piercing Num / Piercing Sym come from github.com/PiercingXX/piercing-keyboard-layout:
# picking one installs it to ~/.config/xkb first if needed. Their system-wide
# route is keyd, since localectl and the TTY only know the stock keymaps.
# PIERCING_KEYBOARD_DIR=/path/to/clone uses a local checkout instead of cloning.
#
# macOS port (better-mac): layouts are input sources. Picking one enables it
# if needed and selects it (Text Input Source API via JXA); if macOS won't,
# Keyboard settings opens to add it by hand. Piercing layouts install only
# the repo's macos/<layout>.keylayout to ~/Library/Keyboard Layouts (not its
# hidutil agent: Karabiner owns Caps=Backspace and the Piercing-only remaps,
# and SketchyBar's keyboard plugin keeps AeroSpace's keys in sync). A fresh
# .keylayout may need a log out/in before macOS lists it. "Custom..." picks
# from every installed layout. Dropped: Hyprland config, localectl/TTY,
# keyd and the login-screen default (macOS has no equivalent we can set).

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"
detect_distro

command_exists gum || die "gum is required for this menu."

LAYOUT_DIR="$HOME/Library/Keyboard Layouts"
KEYBOARD_SETTINGS="x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
PIERCING_REPO="https://github.com/PiercingXX/piercing-keyboard-layout.git"
PIERCING_TMP=""
PIERCING_SRC=""
trap '[ -n "$PIERCING_TMP" ] && command rm -rf "$PIERCING_TMP"' EXIT

# label|input source id|piercing layout (repo dir; empty for built-in layouts)
PRESETS=(
    "Piercing Num|org.unknown.keylayout.PiercingNum|piercing-num"
    "Piercing Sym|org.unknown.keylayout.PiercingSym|piercing-sym"
    "US Colemak|com.apple.keylayout.Colemak|"
    "US QWERTY|com.apple.keylayout.US|"
    "US Dvorak|com.apple.keylayout.Dvorak|"
    "UK QWERTY|com.apple.keylayout.British|"
    "German QWERTZ|com.apple.keylayout.German|"
)

is_piercing() { [[ "$1" == piercing* ]]; }

# tis current | list [all] | select ID  (Carbon Text Input Sources through JXA)
tis() {
    osascript -l JavaScript - "$@" 2>/dev/null <<'JS'
ObjC.import('Carbon');
function prop(s, k) { return ObjC.castRefToObject($.TISGetInputSourceProperty(s, k)).js; }
function layouts(all) {
    var l = ObjC.castRefToObject($.TISCreateInputSourceList($(), all)), out = [];
    var type = ObjC.castRefToObject($.kTISTypeKeyboardLayout).js;
    for (var i = 0; i < l.count; i++) {
        var s = l.objectAtIndex(i);
        if (prop(s, $.kTISPropertyInputSourceType) == type && prop(s, $.kTISPropertyInputSourceIsSelectCapable)) out.push(s);
    }
    return out;
}
function current() { return prop($.TISCopyCurrentKeyboardLayoutInputSource(), $.kTISPropertyInputSourceID); }
function run(argv) {
    var seen = {}, out = [];
    if (argv[0] == 'current') return current();
    if (argv[0] == 'list') {
        layouts(argv[1] == 'all').forEach(function (s) {
            var id = prop(s, $.kTISPropertyInputSourceID);
            if (!seen[id]) { seen[id] = 1; out.push(id + '\t' + prop(s, $.kTISPropertyLocalizedName)); }
        });
        return out.join('\n');
    }
    if (argv[0] == 'select') {
        var s = layouts(true).filter(function (x) { return prop(x, $.kTISPropertyInputSourceID) == argv[1]; })[0];
        if (!s) return '';
        if (!prop(s, $.kTISPropertyInputSourceIsEnabled)) $.TISEnableInputSource(s);
        $.TISSelectInputSource(s);
        return current();
    }
}
JS
}

# Set PIERCING_SRC to a piercing-keyboard-layout checkout, cloned once per run.
# Not called in $(...): the clone's temp dir has to reach the EXIT trap.
piercing_src() {
    [ -n "$PIERCING_SRC" ] && return 0
    if [ -n "${PIERCING_KEYBOARD_DIR:-}" ]; then
        PIERCING_SRC="$PIERCING_KEYBOARD_DIR"
        return 0
    fi
    command_exists git || { err "git is needed to fetch the Piercing layouts."; return 1; }
    PIERCING_TMP=$(mktemp -d)
    git clone --depth 1 -q "$PIERCING_REPO" "$PIERCING_TMP/kb" \
        || { err "Could not clone $PIERCING_REPO."; return 1; }
    PIERCING_SRC="$PIERCING_TMP/kb"
}

piercing_installed() {
    [ -f "$LAYOUT_DIR/$1.keylayout" ]
}

# Install (or refresh) a Piercing variant's .keylayout
install_piercing() {
    local layout="$1" file
    piercing_src || return 1
    file="$PIERCING_SRC/$layout/macos/$layout.keylayout"
    [ -f "$file" ] || { err "No macOS layout for $layout in $PIERCING_SRC."; return 1; }
    mkdir -p "$LAYOUT_DIR"
    if cmp -s "$file" "$LAYOUT_DIR/$layout.keylayout"; then
        echo "Already up to date: $LAYOUT_DIR/$layout.keylayout"
    else
        install -m 644 "$file" "$LAYOUT_DIR/" && echo "Installed $LAYOUT_DIR/$layout.keylayout"
    fi
}

ensure_piercing() {
    piercing_installed "$1" && return 0
    say "Installing $1 from piercing-keyboard-layout..."
    install_piercing "$1" && piercing_installed "$1"
}

show_current() {
    local cur
    cur=$(tis current)
    echo "Current: $(tis list all | awk -F '\t' -v id="$cur" '$1 == id { print $2; exit }') ($cur)"
    echo "Enabled: $(tis list | cut -f2 | paste -sd ',' - | sed 's/,/, /g')"
    local l
    for l in piercing-num piercing-sym; do
        piercing_installed "$l" && echo "Installed: $l"
    done
    [ -f "$HOME/.config/karabiner/karabiner.json" ] && echo "Karabiner: Caps=Backspace and Piercing-only remaps"
    echo
}

# apply_session INPUT_SOURCE_ID
apply_session() {
    local id="$1" now
    now=$(tis select "$id")
    if [ "$now" = "$id" ]; then
        ok "Layout: $id"
        return 0
    fi
    if [ -z "$now" ]; then
        warn "macOS doesn't list $id yet (a new layout can need a log out/in)."
    else
        warn "macOS didn't switch to $id."
    fi
    say "Opening Keyboard settings: Text Input > Input Sources > Edit > + to add it."
    open "$KEYBOARD_SETTINGS"
    return 1
}

while true; do
    clear
    show_current
    labels=()
    for row in "${PRESETS[@]}"; do labels+=("${row%%|*}"); done
    pick=$(printf '%s\n' "${labels[@]}" "Custom..." "Update Piercing layouts" "Keyboard settings" "Back" \
        | gum choose --header "Keyboard layout") || exit 0
    piercing=""
    case "$pick" in
        "Back"|"") exit 0 ;;
        "Update Piercing layouts")
            for l in piercing-num piercing-sym; do
                piercing_installed "$l" || continue
                say "Updating $l..."
                install_piercing "$l"
            done
            pause
            continue ;;
        "Keyboard settings")
            open "$KEYBOARD_SETTINGS"
            continue ;;
        "Custom...")
            pick=$(tis list all | sort -t $'\t' -k2 | awk -F '\t' '{ printf "%s  #%s\n", $2, $1 }' \
                | gum filter --placeholder "Any installed layout") || continue
            [ -n "$pick" ] || continue
            id="${pick##*#}" ;;
        *)
            for row in "${PRESETS[@]}"; do
                [ "${row%%|*}" = "$pick" ] || continue
                IFS='|' read -r _ id piercing <<< "$row"
            done ;;
    esac

    if is_piercing "$piercing" && ! ensure_piercing "$piercing"; then
        err "$piercing isn't installed; nothing changed."
        pause
        continue
    fi
    apply_session "$id"
    pause
done
