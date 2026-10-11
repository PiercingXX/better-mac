#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Toggle microphone mute and show notification. macOS port: macOS has no
# input mute, so this sets the input volume to 0 and restores it after.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mic-toggle"
STATE_FILE="$STATE_DIR/volume"
mkdir -p "$STATE_DIR"

# notify <title> <body>
notify() {
    local title="${1//\\/\\\\}" body="${2//\\/\\\\}"
    title="${title//\"/\\\"}"
    body="${body//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\"" >/dev/null 2>&1
}

current="$(osascript -e 'input volume of (get volume settings)' 2>/dev/null)"
if ! [[ "$current" =~ ^[0-9]+$ ]]; then
    echo "mic-toggle-notify: no input device." >&2
    exit 1
fi

if (( current > 0 )); then
    echo "$current" >"$STATE_FILE"
    osascript -e 'set volume input volume 0'
    notify "Microphone muted" "Input disabled"
else
    restore="$(cat "$STATE_FILE" 2>/dev/null)"
    [[ "$restore" =~ ^[0-9]+$ ]] && (( restore > 0 )) || restore=75
    osascript -e "set volume input volume $restore"
    notify "Microphone unmuted" "Input enabled"
fi
