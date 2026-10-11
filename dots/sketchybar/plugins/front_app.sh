#!/bin/bash
# GitHub.com/PiercingXX
# front_app_switched passes the app name in $INFO

if [ "$SENDER" = "front_app_switched" ]; then
    sketchybar --set "$NAME" label="$INFO"
fi
