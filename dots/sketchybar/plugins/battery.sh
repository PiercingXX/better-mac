#!/bin/bash
# GitHub.com/PiercingXX
# Hidden on Macs without a battery.

batt="$(pmset -g batt)"
percent="$(printf '%s' "$batt" | grep -Eo '[0-9]+%' | head -n1 | tr -d '%')"

if [ -z "$percent" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

case "$percent" in
    9[0-9]|100) icon="" ;;
    [6-8][0-9]) icon="" ;;
    [3-5][0-9]) icon="" ;;
    [1-2][0-9]) icon="" ;;
    *)          icon="" ;;
esac
case "$batt" in
    *"AC Power"*) icon="" ;;
esac

sketchybar --set "$NAME" drawing=on icon="$icon" label="${percent}%"
