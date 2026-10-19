#!/bin/bash
# GitHub.com/PiercingXX
# waybar clock format {:%H:%M %a %b %d}, split around the notch: the clock item
# shows the time and also refreshes the date item

sketchybar --set clock label="$(date '+%H:%M')" \
           --set date label="$(date '+%a %b %d')"
