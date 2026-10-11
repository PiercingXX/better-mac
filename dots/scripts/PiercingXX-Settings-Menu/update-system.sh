#!/usr/bin/env bash
# GitHub.com/PiercingXX
# macOS port (better-mac): Homebrew, Mac App Store (mas) and softwareupdate
# replace the distro upgrade paths, fwupd, flatpak and snap. The .bashrc and
# ~/.scripts sync keep better-mac's macOS layers instead of overwriting them.

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

# Define colors
yellow='\033[1;33m'
green='\033[0;32m'
blue='\033[0;34m'

nc='\033[0m'

if [[ -d "$HOME/.cargo/bin" && ":$PATH:" != *":$HOME/.cargo/bin:"* ]]; then
    PATH="$HOME/.cargo/bin:$PATH"
fi

if [[ -d "$HOME/.local/bin" && ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    PATH="$HOME/.local/bin:$PATH"
fi


# Add a safe clear that works even if TERM is unknown
safe_clear() {
    if command -v tput >/dev/null 2>&1 && [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ] && tput clear >/dev/null 2>&1; then
        clear
    else
        printf '\033c'
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Where better-mac.sh was last run from (it records this on every run)
better_mac_root() {
    local root=""
    [ -f "$HOME/.config/better-mac/root" ] && root="$(head -n 1 "$HOME/.config/better-mac/root")"
    [ -n "$root" ] && [ -d "$root/dots" ] && printf '%s\n' "$root"
}

# Reliable-ish internet check
check_internet() {
    local timeout=4
    local urls=(
        "https://connectivitycheck.gstatic.com/generate_204"
        "http://www.google.com/generate_204"
        "http://www.msftncsi.com/ncsi.txt"
        "http://www.msftconnecttest.com/connecttest.txt"
    )
    for url in "${urls[@]}"; do
        local code
        code=$(curl -4 -fsS --max-time "$timeout" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
        if [[ "$code" == "204" ]]; then
            return 0
        fi
        if [[ "$code" == "200" && "$url" == *"msft"* ]]; then
            local body
            body=$(curl -4 -fsS --max-time "$timeout" "$url" 2>/dev/null | tr -d '\r\n')
            if [[ "$body" == "Microsoft NCSI" || "$body" == "Microsoft Connect Test" ]]; then
                return 0
            fi
        fi
    done
    local hosts=(1.1.1.1 8.8.8.8 9.9.9.9)
    for host in "${hosts[@]}"; do
        # macOS ping: -t is the overall timeout in seconds
        if ping -c 1 -t 1 "$host" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# Require internet before continuing
if ! check_internet; then
    echo "Internet connectivity is required to continue."
    exit 1
fi

# jq drives the ~/.scripts sync; better-mac installs it, but be safe
ensure_jq() {
    command_exists jq && return 0
    if command_exists brew; then
        brew install jq
    fi
    command_exists jq || echo -e "${yellow}jq not available; skipping ~/.scripts sync.${nc}"
}

# Ask for sudo password up front and keep sudo alive
sudo -v
( while true; do sudo -n true; sleep 300; done ) &
sudo_keepalive_pid=$!
trap 'kill "$sudo_keepalive_pid" 2>/dev/null' EXIT


# Ensure user can force shutdown and reboot without password
# Drop-in under sudoers.d — never append raw lines to /etc/sudoers (easy to brick sudo).
if [ -d /etc/sudoers.d ]; then
    sudoers_dropin="/etc/sudoers.d/piercingxx-power"
    tmp_sudoers="$(mktemp)"
    {
        echo "# Managed by PiercingXX update-system.sh"
        for cmd in /sbin/shutdown /sbin/reboot /usr/sbin/shutdown /usr/sbin/reboot; do
            [ -x "$cmd" ] || continue
            echo "$USER ALL=NOPASSWD: $cmd"
        done
    } >"$tmp_sudoers"
    if sudo visudo -cf "$tmp_sudoers" >/dev/null 2>&1; then
        sudo install -m 0440 -o root -g wheel "$tmp_sudoers" "$sudoers_dropin"
    else
        echo "Warning: rejected invalid sudoers drop-in; left /etc/sudoers untouched." >&2
    fi
    rm -f "$tmp_sudoers"
fi

# Unified function to update all scripts in ~/.scripts from GitHub repo, recursively handling subfolders.
# Files better-mac ships a macOS port of are skipped upstream and refreshed from the port instead.
auto_update_scripts() {
    local GITHUB_REPO="Piercingxx/piercing-dots"
    local REMOTE_PATH="resources/.scripts"
    local LOCAL_DIR="$HOME/.scripts"
    local monitor_rel="${REMOTE_PATH}/Control-Scripts/launch-server-monitor.sh"
    local running_script
    running_script=$(readlink -f "${0}" 2>/dev/null || echo "${0}")
    local bm_root ports_dir="" dropped=""
    bm_root="$(better_mac_root)"
    [ -n "$bm_root" ] && [ -d "$bm_root/dots/scripts" ] && ports_dir="$bm_root/dots/scripts"
    # Scripts with no macOS meaning (better-mac's macos-drop.txt) are never fetched
    if [ -n "$ports_dir" ] && [ -f "$ports_dir/macos-drop.txt" ]; then
        dropped="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$ports_dir/macos-drop.txt" | grep -v '^$')"
    fi

    command_exists jq || return 0

    # Ensure local scripts directory exists
    mkdir -p "$LOCAL_DIR"

    # Recursively fetch all files and folders from the GitHub API
    fetch_and_sync() {
        local api_path="$1"
        local local_path="$2"
        local api_url="https://api.github.com/repos/$GITHUB_REPO/contents/$api_path"
        local items
        items=$(curl -s "$api_url")
        echo "$items" | jq -c '.[]' | while read -r item; do
            local type name path download_url
            type=$(echo "$item" | jq -r '.type')
            name=$(echo "$item" | jq -r '.name')
            path=$(echo "$item" | jq -r '.path')
            download_url=$(echo "$item" | jq -r '.download_url')
            if [[ "$type" == "dir" ]]; then
                mkdir -p "$local_path/$name"
                fetch_and_sync "$path" "$local_path/$name"
            elif [[ "$type" == "file" ]]; then
                # better-mac owns this file (macOS port, refreshed below) or drops it
                local rel_path="${path#"$REMOTE_PATH"/}"
                if [[ -n "$ports_dir" && -f "$ports_dir/$rel_path" ]]; then
                    continue
                fi
                if [[ -n "$dropped" ]] && printf '%s\n' "$dropped" | grep -qxF "$rel_path"; then
                    continue
                fi
                local tmp_file
                tmp_file=$(mktemp)
                if ! curl -fsSL "$download_url" -o "$tmp_file"; then
                    echo -e "${yellow}Failed to download $path from GitHub.${nc}"
                    rm -f "$tmp_file"
                    continue
                fi

                # Special handling for launch-server-monitor.sh to preserve user's REMOTE line
                local tmp_compare="$tmp_file"
                if [[ "$path" == "$monitor_rel" && -f "$local_path/$name" ]]; then
                    local saved_remote_line
                    saved_remote_line=$(grep -E '^REMOTE=' "$local_path/$name" || true)
                    if [[ -n "$saved_remote_line" ]]; then
                        # Apply the saved REMOTE line to the temp file for comparison
                        tmp_compare=$(mktemp)
                        awk -v saved="$saved_remote_line" 'BEGIN{replaced=0} {if(!replaced && $0 ~ /^REMOTE=/){print saved; replaced=1; next} {print}} END{if(!replaced && saved!="") print saved}' "$tmp_file" > "$tmp_compare"
                    fi
                fi

                # Compare using the potentially modified temp file
                if [ ! -f "$local_path/$name" ] || ! cmp -s "$local_path/$name" "$tmp_compare"; then
                    local target_file
                    target_file="$local_path/$name"
                    # Avoid overwriting the currently running script mid-execution.
                    if [[ "$(readlink -f "$target_file" 2>/dev/null || echo "$target_file")" == "$running_script" ]]; then
                        cp "$tmp_file" "${target_file}.upstream"
                        chmod +x "${target_file}.upstream" 2>/dev/null || true
                        echo -e "${yellow}Update available for running script; saved as:${nc} ${target_file}.upstream"
                        echo -e "${yellow}Restart the script to apply it (or replace the file manually).${nc}"
                        rm -f "$tmp_file"
                        if [[ "$tmp_compare" != "$tmp_file" ]]; then
                            rm -f "$tmp_compare"
                        fi
                        continue
                    fi

                    cp "$tmp_file" "$target_file"

                    # Re-apply the saved REMOTE line to the installed file
                    if [[ "$path" == "$monitor_rel" && -f "$local_path/$name" ]]; then
                        local saved_remote_line
                        saved_remote_line=$(grep -E '^REMOTE=' "$local_path/$name" 2>/dev/null || echo "REMOTE=\"dr3k@server-debian-ai\"")
                        local tmp_preserve
                        tmp_preserve=$(mktemp)
                        awk -v saved="$saved_remote_line" 'BEGIN{replaced=0} {if(!replaced && $0 ~ /^REMOTE=/){print saved; replaced=1; next} {print}} END{if(!replaced && saved!="") print saved}' "$local_path/$name" > "$tmp_preserve" && mv "$tmp_preserve" "$local_path/$name"
                    fi

                    chmod +x "$local_path/$name"
                    echo -e "${green}Updated $path${nc}"
                fi

                # Clean up temp files
                rm -f "$tmp_file"
                if [[ "$tmp_compare" != "$tmp_file" ]]; then
                    rm -f "$tmp_compare"
                fi
            fi
        done
    }

    fetch_and_sync "$REMOTE_PATH" "$LOCAL_DIR"

    # Refresh better-mac's macOS ports (git pull better-mac to update them)
    if [ -n "$ports_dir" ]; then
        local port rel target
        while IFS= read -r port; do
            rel="${port#"$ports_dir"/}"
            [ "$rel" = "macos-drop.txt" ] && continue
            target="$LOCAL_DIR/$rel"
            if [ ! -f "$target" ] || ! cmp -s "$port" "$target"; then
                if [[ "$(readlink -f "$target" 2>/dev/null || echo "$target")" == "$running_script" ]]; then
                    cp "$port" "${target}.upstream"
                    echo -e "${yellow}Update available for running script; saved as:${nc} ${target}.upstream"
                    continue
                fi
                mkdir -p "$(dirname "$target")"
                cp "$port" "$target"
                chmod +x "$target"
                echo -e "${green}Updated $rel (better-mac)${nc}"
            fi
        done < <(find "$ports_dir" -type f)
    fi
    echo -e "${green}All scripts checked and updated if needed!${nc}"
}


# Update .bashrc from GitHub, keeping better-mac's macOS layers around it
update_bashrc() {
    local REMOTE_URL="https://raw.githubusercontent.com/Piercingxx/piercing-dots/main/resources/bash/.bashrc"
    local TMP_FILE NEW_FILE
    TMP_FILE=$(mktemp)
    NEW_FILE=$(mktemp)
    if ! curl -fsSL "$REMOTE_URL" -o "$TMP_FILE"; then
        echo -e "${yellow}Failed to download .bashrc from GitHub.${nc}"
        rm -f "$TMP_FILE" "$NEW_FILE"
        return 1
    fi
    # Same layout better-mac's shell module writes: pre.bash + .bashrc + post.bash
    {
        printf '%s\n' '# better-mac: Homebrew and GNU tools first (see ~/.config/better-mac/pre.bash)'
        printf '%s\n\n' '[ -f "$HOME/.config/better-mac/pre.bash" ] && . "$HOME/.config/better-mac/pre.bash"'
        cat "$TMP_FILE"
        printf '\n%s\n' '# better-mac: macOS replacements for Linux-only bits (see ~/.config/better-mac/post.bash)'
        printf '%s\n' '[ -f "$HOME/.config/better-mac/post.bash" ] && . "$HOME/.config/better-mac/post.bash"'
    } >"$NEW_FILE"
    if ! cmp -s "$HOME/.bashrc" "$NEW_FILE"; then
        cp "$NEW_FILE" "$HOME/.bashrc"
        echo -e "${green}.bashrc has been updated.${nc}"
    fi
    rm -f "$TMP_FILE" "$NEW_FILE"
    return 0
}

# Homebrew formulae + casks, Mac App Store, macOS itself
macos_upgrade() {
    if command_exists brew; then
        echo -e "${yellow}Updating Homebrew (brew)...${nc}"
        brew update && brew upgrade || return 1
        brew autoremove || true
        brew cleanup || true
    else
        echo -e "${yellow}Homebrew not found; skipping package upgrades.${nc}"
    fi
    if command_exists mas; then
        echo -e "${yellow}Updating App Store apps (mas)...${nc}"
        mas upgrade || true
    fi
    # macOS and firmware updates (fwupd's job on Linux)
    echo -e "${yellow}Checking for macOS updates...${nc}"
    local su_list
    su_list=$(softwareupdate -l 2>&1 || true)
    printf '%s\n' "$su_list"
    if printf '%s\n' "$su_list" | grep -q '^\* Label:'; then
        if ! command_exists gum || gum confirm "Install macOS updates now? (some need a restart)"; then
            sudo softwareupdate -ia || true
        fi
    fi
}

# Universal update logic
universal_update() {
# Update Neovim plugins (vim.pack — not Lazy.nvim)
    if command_exists nvim; then
        nvim --headless "+lua pcall(vim.pack.update)" "+quitall!" 2>/dev/null || true
    fi
    echo -e "${yellow}Be Patient...${nc}"
# Update npm (Homebrew's node keeps globals in a user-writable prefix)
    if command_exists npm; then
        npm update -g --silent --no-progress || true
    fi
# Update cargo
    if command_exists cargo; then
        echo -e "${yellow}Updating cargo...${nc}"
        if cargo install-update --version >/dev/null 2>&1; then
            cargo install-update -a
        else
            cargo install cargo-update
            cargo install-update -a
        fi
    fi
# Update Docker images
    if command_exists docker && docker info >/dev/null 2>&1; then
        echo -e "${yellow}Updating Docker images...${nc}"
        # Images/containers only — never wipe volumes unless explicitly requested.
        docker system prune -af
        local images=() img
        while IFS= read -r img; do
            images+=("$img")
        done < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>')
        echo -e "${yellow}Updating ${#images[@]} Docker image(s)...${nc}"
        for img in "${images[@]}"; do
            echo -e "  • ${img}"
            docker pull "$img" 2>/dev/null
        done
    fi
# Update yazi && its plugins
    if command_exists yazi; then
        echo -e "${yellow}Updating yazi...${nc}"
        if command_exists ya; then
            YAZI_CONFIG_DIR="$HOME/.config/yazi"
            YAZI_CONFIG="$YAZI_CONFIG_DIR/package.toml"
            # Fix common package.toml issues before upgrade
            if [ -f "$YAZI_CONFIG" ]; then
                local yazi_tmp
                yazi_tmp=$(mktemp)
                sed -e 's/system-clipboard\.yazi/system-clipboard-yazi/g' "$YAZI_CONFIG" >"$yazi_tmp" \
                    && ! cmp -s "$yazi_tmp" "$YAZI_CONFIG" && cat "$yazi_tmp" >"$YAZI_CONFIG"
                rm -f "$yazi_tmp"
            fi
            # Skip upgrade if legacy header exists to avoid parse abort
            if [ -f "$YAZI_CONFIG" ] && grep -q '^\[\[plugin\.deps\]\]' "$YAZI_CONFIG"; then
                echo -e "${yellow}Yazi package.toml has legacy [[plugin.deps]]; skipping 'ya pkg upgrade'.${nc}"
            else
                ya pkg upgrade || true
            fi
            if [ -f "$YAZI_CONFIG" ]; then
                local installed_plugins plugin
                installed_plugins=$(ya pkg list 2>/dev/null | awk '{print $1}' | sort)
                while IFS= read -r plugin; do
                    [ -n "$plugin" ] || continue
                    if ! printf '%s\n' "$installed_plugins" | grep -qx "$plugin"; then
                        echo -e "${yellow}Adding missing yazi plugin: $plugin${nc}"
                        ya pkg add "$plugin" || true
                    fi
                done < <(grep '^use = ' "$YAZI_CONFIG" | sed -E "s/use = \"(.*)\"/\1/" | sort)
            fi
        fi
    fi
# Update ClamAV virus definitions
    if command_exists freshclam; then
        echo -e "${yellow}Updating ClamAV virus definitions...${nc}"
        # Skip if a freshclam service is already running (lock conflicts)
        if pgrep -x freshclam >/dev/null 2>&1; then
            echo -e "${yellow}freshclam is already running; skipping manual update.${nc}"
        else
            freshclam || true
        fi
    fi
}

# Function to git pull all repos in /media/Working-Storage/GitHub
git_pull_all_github_repos() {
    if ! command_exists git; then
        return
    fi
    # Allow override, then fall back to common locations
    local base_dir="${PX_GITHUB_DIR:-/media/Working-Storage/GitHub}"
    if [ ! -d "$base_dir" ]; then
        for alt in "$HOME/GitHub" "$HOME/Projects" "$HOME/Workspace" "$HOME/src"; do
            if [ -d "$alt" ]; then
                base_dir="$alt"
                break
            fi
        done
    fi
    if [ ! -d "$base_dir" ]; then
        # Only show warning if running interactively
        if [ -t 1 ]; then
            echo -e "${yellow}GitHub directory not found. Set PX_GITHUB_DIR to override.${nc}"
        fi
        return
    fi
    echo -e "${blue}Updating all GitHub repositories in $base_dir...${nc}"
    for repo in "$base_dir"/*; do
        if [ -d "$repo/.git" ]; then
            echo -e "${green}Updating $(basename "$repo")...${nc}"
            (cd "$repo" && git pull --ff-only)
        fi
    done
    echo -e "${green}All GitHub repositories updated!${nc}"
}


echo -e "${green}Starting system update...${nc}\n"
    ensure_jq
    update_bashrc
    auto_update_scripts
    git_pull_all_github_repos

if macos_upgrade; then
    universal_update
else
    echo -e "${yellow}Homebrew upgrade failed; skipping remaining update steps.${nc}"
    exit 1
fi

osascript -e 'display notification "System update completed successfully!" with title "System Update"' >/dev/null 2>&1 || true
echo -e "${green}System Updated Successfully!${nc}"
if [ -n "${sudo_keepalive_pid:-}" ]; then
    kill "$sudo_keepalive_pid" 2>/dev/null
fi
exit 0
