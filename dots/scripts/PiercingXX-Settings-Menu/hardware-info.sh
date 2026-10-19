#!/usr/bin/env bash
# GitHub.com/PiercingXX
# Hardware Info: quick read-only views of the machine, plus disk usage.
# macOS port (better-mac): lscpu/free/lsblk/lsusb/upower become sysctl,
# vm_stat, diskutil, system_profiler and pmset; sensors becomes macmon
# (Apple Silicon temps and power, no sudo). lspci -k becomes graphics &
# displays plus Thunderbolt/PCI, since Apple Silicon has few PCI devices.

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

command_exists gum || die "gum is required for this menu."

pager() { gum pager; }

battery_info() {
    pmset -g batt
    echo
    system_profiler SPPowerDataType 2>/dev/null | sed -n '/Battery Information:/,/System Power Settings:/p' | sed '$d'
}

cpu_info() {
    sysctl -n machdep.cpu.brand_string
    local i name n
    for i in 0 1 2; do
        name=$(sysctl -n "hw.perflevel$i.name" 2>/dev/null) || break
        n=$(sysctl -n "hw.perflevel$i.logicalcpu" 2>/dev/null)
        echo "  $name cores: $n"
    done
    echo "  Total: $(sysctl -n hw.ncpu) logical CPUs, $(uname -m)"
    echo
    system_profiler SPHardwareDataType 2>/dev/null | sed '1,4d'
}

memory_info() {
    echo "Installed: $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
    top -l 1 -n 0 | grep PhysMem
    sysctl vm.swapusage
    echo
    memory_pressure 2>/dev/null | tail -n 1
    echo
    vm_stat
}

# macmon pipe prints one JSON sample; pull out the temps and power
temperatures() {
    local j
    j=$(macmon pipe -s 1 2>/dev/null | head -n1)
    [ -n "$j" ] || { echo "macmon gave no sample."; return; }
    printf '%s\n' "$j" | tr ',{}' '\n\n\n' | tr -d '"' | awk -F: '
        $1 == "cpu_temp_avg" { printf "CPU temp:   %.1f°C\n", $2 }
        $1 == "gpu_temp_avg" { printf "GPU temp:   %.1f°C\n", $2 }
        $1 == "cpu_power"    { printf "CPU power:  %.2f W\n", $2 }
        $1 == "gpu_power"    { printf "GPU power:  %.2f W\n", $2 }
        $1 == "all_power"    { printf "SoC power:  %.2f W\n", $2 }'
    echo
    echo "Run 'macmon' for a live view."
}

disk_usage() {
    local path
    path=$(gum input --placeholder "folder to analyze" --value "$HOME") || return 0
    path="${path/#\~/$HOME}"
    [ -d "$path" ] || { err "No such folder: $path"; pause; return; }
    if command_exists dust; then
        dust -d 2 "$path" 2>/dev/null | pager
    elif command_exists ncdu; then
        ncdu "$path"
    else
        du -h -d 1 "$path" 2>/dev/null | sort -rh | head -n 40 | pager
    fi
}

options=("Summary" "CPU" "Memory" "Disks & partitions" "Graphics & displays" "Thunderbolt & PCI" "USB devices")
command_exists macmon && options+=("Temperatures")
pmset -g batt 2>/dev/null | grep -q InternalBattery && options+=("Battery")
options+=("Disk usage of a folder" "Back")

while true; do
    clear
    choice=$(printf '%s\n' "${options[@]}" | gum choose --header "Hardware Info") || exit 0
    case "$choice" in
        "Summary")
            if command_exists fastfetch; then
                fastfetch --pipe 2>/dev/null | pager
            else
                { uname -a; echo; sw_vers; } | pager
            fi ;;
        "CPU")                    cpu_info | pager ;;
        "Memory")                 memory_info | pager ;;
        "Disks & partitions")     { diskutil list; echo; /bin/df -h | awk 'NR==1 || $1 ~ "^/dev/"'; } | pager ;;
        "Graphics & displays")    system_profiler SPDisplaysDataType | pager ;;
        "Thunderbolt & PCI")      system_profiler SPThunderboltDataType SPPCIDataType | pager ;;
        "USB devices")            system_profiler SPUSBHostDataType | pager ;;
        "Temperatures")           temperatures | pager ;;
        "Battery")                battery_info | pager ;;
        "Disk usage of a folder") disk_usage ;;
        *) exit 0 ;;
    esac
done
