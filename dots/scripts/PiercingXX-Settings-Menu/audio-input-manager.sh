#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Audio Input/Output Manager for macOS (SwitchAudioSource)

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

set -e

notify() {
    local title="$1" body="$2"
    body="${body//\"/\\\"}"
    title="${title//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\"" >/dev/null 2>&1 || true
}

notify_error() {
    local body="$1"
    if command -v osascript &>/dev/null; then
        notify "Audio Output Toggle Failed" "$body"
    fi
    echo "$body" >&2
}

play_switch_chime() {
    local chime="/System/Library/Sounds/Pop.aiff"
    if command -v afplay &>/dev/null && [[ -f "$chime" ]]; then
        afplay "$chime" >/dev/null 2>&1 &
    fi
}

# Detect if SwitchAudioSource is available
if ! command -v SwitchAudioSource &>/dev/null; then
    notify_error "SwitchAudioSource not found. Install it with: brew install switchaudio-osx"
    exit 1
fi

# list_devices <output|input>: one device name per line
list_devices() {
    SwitchAudioSource -a -t "$1" 2>/dev/null | sed '/^[[:space:]]*$/d'
}

current_device() {
    SwitchAudioSource -c -t "$1" 2>/dev/null
}

# Handle --toggle-output flag for keybinds
if [[ "$1" == "--toggle-output" ]]; then
    sinks=()
    while IFS= read -r line; do
        sinks+=("$line")
    done < <(list_devices output)

    if [[ ${#sinks[@]} -eq 0 ]]; then
        notify_error "No audio output devices found."
        exit 1
    fi

    current="$(current_device output)"
    current_idx=-1
    for i in "${!sinks[@]}"; do
        if [[ "${sinks[$i]}" == "$current" ]]; then
            current_idx=$i
        fi
    done

    # Calculate next index
    if [[ $current_idx -eq -1 ]]; then
        next_idx=0
    else
        next_idx=$(( (current_idx + 1) % ${#sinks[@]} ))
    fi

    next_sink="${sinks[$next_idx]}"
    SwitchAudioSource -t output -s "$next_sink" >/dev/null
    # Alerts and system sounds follow the new output too
    SwitchAudioSource -t system -s "$next_sink" >/dev/null 2>&1 || true

    notify "Audio Output Switched" "$next_sink"
    echo "Switched to: $next_sink"

    play_switch_chime
    exit 0
fi

# Interactive menu mode
if ! command -v gum &>/dev/null; then
    echo "Error: gum is required for interactive mode. Install it (brew install gum) or use --toggle-output flag." >&2
    exit 1
fi

# pick_device <output|input> <label>
pick_device() {
    local type="$1" label="$2" current num
    local names=()

    while IFS= read -r line; do
        names+=("$line")
    done < <(list_devices "$type")

    if [[ ${#names[@]} -eq 0 ]]; then
        echo "No audio $label devices found."
        exit 1
    fi

    current="$(current_device "$type")"

    # Display devices
    for i in "${!names[@]}"; do
        local mark=""
        if [[ "${names[$i]}" == "$current" ]]; then
            mark="[CURRENT] "
        fi
        printf "  %2d. %s%s\n" $((i+1)) "$mark" "${names[$i]}"
    done

    echo ""
    read -p "Enter the number of the $label device to set as default: " num

    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#names[@]} ]; then
        SwitchAudioSource -t "$type" -s "${names[$((num-1))]}" >/dev/null
        if [[ "$type" == "output" ]]; then
            SwitchAudioSource -t system -s "${names[$((num-1))]}" >/dev/null 2>&1 || true
        fi
        echo "✓ Set default $label to: ${names[$((num-1))]}"
    else
        echo "✗ Invalid selection."
        exit 1
    fi
}

clear

choice=$(printf "🔈 Output (Speakers/Headset)\n🎤 Microphone (Input)" | gum choose --header="Select device type to manage:")

if [[ "$choice" == "🎤 Microphone (Input)" ]]; then
    clear
    echo "🎤 Available audio input devices:"
    echo ""
    pick_device input input
elif [[ "$choice" == "🔈 Output (Speakers/Headset)" ]]; then
    clear
    echo "🔈 Available audio output devices:"
    echo ""
    pick_device output output
fi
