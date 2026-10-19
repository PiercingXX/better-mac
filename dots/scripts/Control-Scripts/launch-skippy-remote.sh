#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Monitor layout on the Skippy box. Not skippy-desk.sh (local desk app).
# Host: SKIPPY_HOST in ~/.config/piercingxx/remotes.conf.
# macOS port (better-mac): unchanged; remote-session.sh does the work.
exec bash "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/remote-session.sh" --host skippy "$@"
