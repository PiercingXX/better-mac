#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Toggle microphone mute and show the shared on-screen bubble.
# Bound to XF86AudioMicMute in the WM configs.
# macOS port (better-mac): CoreAudio has no scriptable input mute, so this
# sets the input volume to 0 and restores the saved level on unmute
# (osascript instead of wpctl/pactl). The bubble is a notification (osd).

# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"

STATE_FILE="$PX_STATE_DIR/mic-volume"

current=$(osascript -e 'input volume of (get volume settings)' 2>/dev/null)
if ! [[ "$current" =~ ^[0-9]+$ ]]; then
    notify_replace mic normal 3000 dialog-error "Microphone" "No input device found."
    exit 1
fi

if (( current > 0 )); then
    mkdir -p "$PX_STATE_DIR"
    echo "$current" > "$STATE_FILE"
    osascript -e 'set volume input volume 0'
    muted=yes
else
    restore=$(cat "$STATE_FILE" 2>/dev/null)
    [[ "$restore" =~ ^[0-9]+$ ]] && (( restore > 0 )) || restore=75
    osascript -e "set volume input volume $restore"
    muted=no
fi

if [ "$muted" = yes ]; then
    osd microphone-sensitivity-muted "Microphone muted" 0
else
    osd audio-input-microphone "Microphone on" "${restore:-100}"
fi
