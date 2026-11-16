#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Shut down now, like systemctl poweroff, without macOS reopening the apps
# at the next login.
# `shutdown -h now` alone kills apps without letting loginwindow see them
# quit, so it treats the next login like a crash recovery and relaunches
# them, whatever "Reopen windows" (TALLogoutSavesState) says. So first:
#   1. quit every regular (Dock) app with SIGTERM and give them a few seconds
#   2. delete loginwindow's saved app list (protected app data: the WM running
#      this needs "access data from other apps", otherwise this step is skipped)
# then power off. Unsaved work is lost, same as before.

list="$HOME/Library/Group Containers/group.com.apple.loginwindow.persistent-apps/persistantApps"

# pids of Foreground apps (the ones with a Dock icon); Finder always comes
# back anyway, so leave it
mapfile -t pids < <(lsappinfo list 2>/dev/null | awk '
    /^ *[0-9]+\) "/ { name = $0; sub(/^ *[0-9]+\) "/, "", name); sub(/".*/, "", name) }
    /pid = [0-9]+ type="Foreground"/ && name != "Finder" {
        for (i = 1; i <= NF; i++) if ($i == "pid") { print $(i + 2); break }
    }')

if [ "${#pids[@]}" -gt 0 ]; then
    kill -TERM "${pids[@]}" 2>/dev/null
    # up to 5s for them to exit
    for _ in $(seq 1 25); do
        alive=0
        for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1 && break; done
        [ "$alive" -eq 0 ] && break
        sleep 0.2
    done
fi

rm -f "$list" 2>/dev/null

exec sudo -n /sbin/shutdown -h now
