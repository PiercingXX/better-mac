#!/bin/bash
# GitHub.com/PiercingXX
# waybar clock format: {:%H:%M %a %b %d}

sketchybar --set "$NAME" label="$(date '+%H:%M %a %b %d')"
