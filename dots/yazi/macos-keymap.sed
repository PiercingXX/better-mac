# GitHub.com/PiercingXX - better-mac
# keymap.toml on macOS: wl-clipboard needs Wayland, so Ctrl-y copies the
# selected paths with yazi's built-in clipboard instead.
s/run = \["plugin wl-clipboard"\]/run = "copy path"/
s/Copy to [Ss]ystem [Cc]lipboard/Copy path(s) to clipboard/
