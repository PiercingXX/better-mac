# better-mac

The macOS sibling of [linux-mod](https://github.com/PiercingXX/linux-mod).
One script turns a fresh Mac into the PiercingXX setup: bash 5 and GNU tools,
piercing-dots (bashrc, kitty, nvim, tmux, yazi), the arch-mini-mod apps,
Colemak + Piercing Num, and a Hyprland-style tiling desktop.

## How to use

### 1. Fresh Mac: get git

`git` on a new Mac is a stub. Open Terminal and install the Command Line Tools:

```bash
xcode-select --install
```

### 2. Clone and run

```bash
git clone https://github.com/PiercingXX/better-mac.git
cd better-mac
./better-mac.sh --dry-run    # optional: see every step, change nothing
./better-mac.sh
```

The repo is private, so `git clone` asks for a username and password: use
`PiercingXX` and a GitHub personal access token (Settings > Developer settings >
Tokens, `repo` scope) as the password. A fresh Mac has no `gh` to log in with yet.

Run it as your normal user. It asks for your password once (Homebrew,
login shell, power, firewall, Remote Login) and keeps sudo alive.
Homebrew is installed if it's missing. Expect 20-40 minutes, mostly downloads.

### 3. Click through the permission panes

macOS doesn't let scripts grant these. At the end the script opens each pane
and waits for you to press Enter:

| Pane | Turn on |
|---|---|
| Privacy > Accessibility | AeroSpace, Raycast |
| Privacy > Input Monitoring | karabiner_grabber, karabiner_observer |
| Karabiner-Elements window | its driver extension and login items |
| Raycast welcome window | hotkey **⌥ Space** (tapping left Option sends it) |
| Keyboard > Text Input > Edit | add **Colemak** and **Piercing Num** (under Others), remove U.S. |

### 4. Log out and back in

The menu bar auto-hide, Spaces, dark mode and trackpad settings apply after a
fresh login. AeroSpace, SketchyBar, borders and Karabiner start at login from
then on.

### 5. First launches

- `nvim`: plugins install on first launch (`vim.pack`).
- tmux plugins are already installed; `prefix + I` re-runs TPM.
- Press **⌥ /** for the keybind sheet.

### Re-running

Safe to rerun at any time; it's how you pull in piercing-dots changes.
Anything it replaces is kept as `<name>.bak.<timestamp>`, and a rerun with
no upstream changes touches nothing.

```bash
cd better-mac && git pull && ./better-mac.sh
```

| Flag | |
|---|---|
| `--dry-run` | print every action instead of running it (works on Linux too) |
| `--no-color` | plain output (`NO_COLOR` also works) |
| `-h`, `--help` | usage |

`PIERCING_DOTS_DIR=/path/to/piercing-dots` or
`PIERCING_KEYBOARD_DIR=/path/to/piercing-keyboard-layout` use a local
checkout instead of cloning.

## What it does

The modules run in this order.

### `modules/shell.sh`: bash and your .bashrc

- Homebrew bash 5 becomes the login shell. GNU coreutils, findutils, sed, grep,
  tar and make go ahead of the BSD tools in PATH, so Linux flags work.
- `~/.bashrc` = `dots/bash/pre.bash` (Homebrew, GNU PATH) + your piercing-dots
  `.bashrc` unchanged + `dots/bash/post.bash`, which replaces the Linux-only bits:
  `openports`, `logout`, `cpp`, `whatsmyip`, `logs`, `sd`, completion and fzf
  keybindings, and drops the Linux desktop launchers and `xx`.
- starship and fastfetch configs.

### `modules/dots.sh`: kitty, nvim, tmux, yazi

piercing-dots configs, with small macOS fixes applied to a copy:

| | macOS change |
|---|---|
| kitty | `include macos.conf`: font size 13 (macOS uses 72 dpi), background blur, right Option = Alt |
| nvim | none (Homebrew neovim is 0.12, so `vim.pack` works) |
| tmux | `wl-copy` -> `pbcopy`; TPM + plugins; `tmux-256color` terminfo compiled (macOS lacks it) |
| yazi | `xdg-open` -> `open`, first in each opener group; Ctrl-y copies paths (wl-clipboard is Wayland-only) |

### `modules/apps.sh`: apps from step-1.sh

- Waterfox, Discord, Obsidian, GIMP, VS Code, OpenCode, LibreOffice,
  qBittorrent, GitHub Desktop, ProtonVPN, Synology Drive, Synology Chat,
  Tailscale.
- htop, btop, lnav, mpv, ranger, and macmon (nvtop doesn't support Apple GPUs).
- piercing-dots configs for btop, htop, mpv, ranger, ncmpcpp, opencode, mpd
  (audio output `osx`) and GIMP 3.2 (`~/Library/Application Support/GIMP/3.2`).
- The piercing-dots commit-msg hook, pointed at GNU sed because git runs hooks
  from GUI apps without your shell's PATH.

### `modules/keyboard.sh`: Colemak + Piercing Num

- `piercing-num.keylayout` from
  [piercing-keyboard-layout](https://github.com/PiercingXX/piercing-keyboard-layout).
- Caps = Backspace (both layouts), and for Piercing Num only, Backspace =
  Delete and Right ⌥ + h/j/k/l = arrows. These are Karabiner rules keyed to the
  active layout, replacing the repo's `hidutil` agent, which can't tell
  layouts apart. An existing agent is removed.
- AeroSpace binds follow the letters of whichever layout is active, like
  Hyprland: SketchyBar's layout item (`CMK` / `PRC`) swaps AeroSpace's key map
  on every switch.

### `modules/system.sh`: gnome-customizations.sh as macOS settings

Dark mode, 24h clock with weekday, battery %, reduced animations, tap to
click, natural scroll, flat mouse acceleration, sleep 60 min on power / 30 on
battery with the screen off at 15, no dimming, Trash auto-empty (30 days, the
macOS minimum), hot corners off, Dock holds your GNOME favorites minus VS Code (Finder,
Waterfox, LibreOffice, Calculator, Obsidian, Synology Chat; it stays hidden,
see below), Night Shift 20:00-04:00 at its warmest,
firewall on, Remote Login (SSH) on.

### `modules/wm.sh`: the Hyprland desktop

| piercing-dots (Linux) | better-mac (macOS) |
|---|---|
| Hyprland | [AeroSpace](https://github.com/nikitabobko/AeroSpace): i3-style tiling, workspaces 1-10 |
| waybar | [SketchyBar](https://github.com/FelixKratz/SketchyBar), with the macOS menu bar auto-hidden |
| Dock | hidden for good (1000s reveal delay); launch from keybinds or Raycast, switch with ⌘Tab |
| Hyprland borders | [JankyBorders](https://github.com/FelixKratz/JankyBorders) |
| ulauncher / tap Super | Raycast, opened by tapping left Option |
| hyprpaper | wallpaper `~/Pictures/backgrounds/1346578.jpg` |
| `~/.scripts` | copied from piercing-dots, so the note/server/AI binds work |

Keybinds keep their Hyprland positions: **Super -> Option (⌥)**,
**Alt -> Cmd (⌘)**, **Ctrl -> Ctrl**, so ⌘C/⌘V/⌘Q still work normally. Full
list in [dots/aerospace/KEYBINDS.md](dots/aerospace/KEYBINDS.md).

## Layout

```
better-mac.sh            entry point (bash 3.2-safe: runs on a fresh Mac)
lib/common.sh            logging, --dry-run, backups, Homebrew + piercing-dots helpers
modules/
├── shell.sh             bash 5, GNU tools, .bashrc, starship, fastfetch
├── dots.sh              kitty, nvim, tmux, yazi
├── apps.sh              apps, their configs, git hook
├── keyboard.sh          Piercing Num layout
├── system.sh            macOS settings, firewall, SSH
└── wm.sh                AeroSpace desktop, permissions walkthrough
dots/
├── aerospace/           aerospace.toml (hyprland/*.lua translated) + KEYBINDS.md
├── sketchybar/          sketchybarrc + plugins (workspaces, app, clock, layout, volume, battery)
├── borders/bordersrc
├── karabiner/           Option-tap launcher, Caps/Backspace, Piercing arrows
├── bash/                pre.bash, post.bash, bash_profile
├── kitty/macos.conf
├── tmux/macos.sed
└── yazi/*.sed
```

## Not possible on macOS

Animations, blur between windows, inactive-window opacity, dwindle
auto-splitting, window swallowing, cursor and icon themes, Super+drag (use
**Ctrl ⌘ + drag**), and touchpad gestures for AeroSpace workspaces. Drivers,
kernels, PipeWire, NetworkManager, display managers and the other Linux WMs
have nothing to port.

## Notes

- `open_daily_note.sh`, `inventory.sh` and the nvim todo/daily-note config
  point at `/media/Archived-Storage/...`; on a Mac that share mounts under
  `/Volumes/...`.
- Reduce Motion and Remote Login need Full Disk Access for your terminal; if
  either is refused, the summary says where to turn it on by hand.
- The tmux-thumbs plugin compiles with Rust the first time you use it.
- Workspaces 1-3 go to the LG UltraWide and 4-5 to the LG SDQHD when they're
  connected, otherwise the main display.
- If windows sit too low or under the bar on the built-in screen, tune
  `gaps.outer.top` per monitor, e.g.
  `gaps.outer.top = [{ monitor.'built-in' = 10 }, 44]`.
- Not ported yet: the `xx` settings menu and the printer setup (Canon D530,
  Omezizy label printer).
