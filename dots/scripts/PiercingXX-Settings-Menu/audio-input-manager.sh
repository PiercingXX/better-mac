#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Audio Input/Output Manager for PipeWire (WirePlumber).
#   audio-input-manager.sh                 interactive menu
#   audio-input-manager.sh --toggle-output cycle the default output (keybind)
#
# macOS port (better-mac): CoreAudio through SwitchAudioSource (switchaudio-osx)
# instead of wpctl/pw-dump; the system alert device follows the output, the
# chime is afplay. No stream moving needed (CoreAudio moves them itself).
# env bash: AeroSpace runs this directly and /bin/bash is 3.2 (no mapfile).
# Outputs whose name matches PIERCINGXX_AUDIO_SKIP (extended regex) are
# hidden; the default hides the virtual devices meeting apps install. Set
# PIERCINGXX_AUDIO_SKIP="" to show everything.

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

AUDIO_SKIP="${PIERCINGXX_AUDIO_SKIP-ZoomAudioDevice|Microsoft Teams Audio}"

notify_error() {
    notify_replace audio-error normal 3000 audio "Audio" "$1"
    echo "$1" >&2
}

play_switch_chime() {
    local f=/System/Library/Sounds/Pop.aiff
    [ -f "$f" ] && command_exists afplay && { afplay "$f" >/dev/null 2>&1 & }
}

command_exists SwitchAudioSource || { notify_error "SwitchAudioSource not found. Install it with: brew install switchaudio-osx"; exit 1; }

# list_nodes output|input -> "id<TAB>name" lines
# cli format is "name,type,id,uid"; names may contain commas, so cut from the right
list_nodes() {
    local type="$1"
    SwitchAudioSource -a -t "$type" -f cli 2>/dev/null | awk -F, 'NF >= 4 {
            id = $(NF-1); name = $1
            for (i = 2; i <= NF-3; i++) name = name "," $i
            print id "\t" name }' \
    | { if [ -n "$AUDIO_SKIP" ] && [ "$type" = output ]; then grep -Ev "$AUDIO_SKIP"; else cat; fi; }
}

# default_id output|input
default_id() {
    SwitchAudioSource -c -t "$1" -f cli 2>/dev/null | awk -F, '{print $(NF-1)}'
}

# set_default output|input ID NAME: alerts and system sounds follow the output too
set_default() {
    SwitchAudioSource -t "$1" -i "$2" >/dev/null || return 1
    if [ "$1" = output ]; then
        SwitchAudioSource -t system -s "$3" >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
# Keybind mode: cycle outputs
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--toggle-output" ]]; then
    mapfile -t sinks < <(list_nodes output)
    [ ${#sinks[@]} -gt 0 ] || { notify_error "No audio output devices found."; exit 1; }

    current=$(default_id output)
    next_idx=0
    for i in "${!sinks[@]}"; do
        if [ "${sinks[$i]%%$'\t'*}" = "$current" ]; then
            next_idx=$(( (i + 1) % ${#sinks[@]} ))
            break
        fi
    done
    next_id="${sinks[$next_idx]%%$'\t'*}"
    next_name="${sinks[$next_idx]#*$'\t'}"

    set_default output "$next_id" "$next_name" || { notify_error "Could not switch to $next_name."; exit 1; }
    notify_replace audio-output low 2000 audio-speakers "Audio Output Switched" "$next_name"
    echo "Switched to: $next_name"
    play_switch_chime
    exit 0
fi

# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------
command_exists gum || { echo "gum is required for interactive mode (or use --toggle-output)." >&2; exit 1; }

if [[ "${PIERCINGXX_ASCII_MENU:-0}" == 1 ]]; then
    out_label="Output (Speakers/Headset)"; in_label="Microphone (Input)"
else
    out_label="🔈 Output (Speakers/Headset)"; in_label="🎤 Microphone (Input)"
fi

# choose_device output|input
choose_device() {
    local kind="$1" current line id name pick
    local -a nodes labels
    mapfile -t nodes < <(list_nodes "$kind")
    [ ${#nodes[@]} -gt 0 ] || { err "No audio $kind devices found."; return 1; }
    current=$(default_id "$kind")

    for line in "${nodes[@]}"; do
        id="${line%%$'\t'*}"; name="${line#*$'\t'}"
        if [ "$id" = "$current" ]; then
            labels+=("$name  [current]  #$id")
        else
            labels+=("$name  #$id")
        fi
    done

    pick=$(printf '%s\n' "${labels[@]}" | gum choose --header "Set default $kind device") || return 0
    [ -n "$pick" ] || return 0
    id="${pick##*#}"
    if set_default "$kind" "$id" "${pick%%  *}"; then
        ok "Default $kind set to: ${pick%%  *}"
    else
        err "Could not set default $kind."
        return 1
    fi
}

while true; do
    clear
    choice=$(printf '%s\n' "$out_label" "$in_label" "Back" | gum choose --header="Select device type to manage:")
    case "$choice" in
        "$out_label") choose_device output ;;
        "$in_label")  choose_device input ;;
        *) exit 0 ;;
    esac
    pause
done
