#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Server monitor layout (nvtop/htop/lnav). Old -monitor/-remote/-log flags
# still work. Host: SERVER_HOST in ~/.config/piercingxx/remotes.conf.
# macOS port (better-mac): unchanged; AeroSpace ⌥M/⌥⇧M pass -monitor/-remote.
exec bash "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/remote-session.sh" --host server "$@"
