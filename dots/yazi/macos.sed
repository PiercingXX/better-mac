# GitHub.com/PiercingXX - better-mac
# yazi.toml on macOS (run with sed -E). xdg-open becomes `open`, and `open`
# goes first in each media/document group, since imv, zathura, totem,
# file-roller... aren't on macOS. The Linux viewers stay in "open with".
/xdg-open/d
/code -w/d
/^(open|play|image|pdf|office|archive) = \[$/a\
{ run = 'open "$@"', desc = "macOS default app" },
