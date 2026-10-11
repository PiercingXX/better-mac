#!/usr/bin/env bash
# GitHub.com/PiercingXX
# One-shot update availability notification. macOS port:
# Homebrew formulae + casks, and macOS software updates.

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# notify <title> <body>
notify() {
    local title="${1//\\/\\\\}" body="${2//\\/\\\\}"
    title="${title//\"/\\\"}"
    body="${body//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\"" >/dev/null 2>&1
}

count_brew() {
    command -v brew &>/dev/null || { echo 0; return; }
    brew update --quiet >/dev/null 2>&1
    brew outdated --quiet 2>/dev/null | awk 'NF{c++} END{print c+0}'
}

count_macos() {
    softwareupdate --list 2>&1 | grep -c '^\* Label:'
}

brew_count=$(count_brew)
macos_count=$(count_macos)

body=""
if [[ "$brew_count" =~ ^[0-9]+$ ]] && (( brew_count > 0 )); then
    body="$brew_count packages can be updated"
fi
if [[ "$macos_count" =~ ^[0-9]+$ ]] && (( macos_count > 0 )); then
    body="${body:+$body, }$macos_count macOS update(s)"
fi

if [[ -n "$body" ]]; then
    notify "Updates available" "$body"
fi
