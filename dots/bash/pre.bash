# shellcheck shell=bash
# GitHub.com/PiercingXX - better-mac
# Sourced at the top of ~/.bashrc, before the piercing-dots .bashrc, so its
# `command -v eza/starship/zoxide` checks can see Homebrew.

if [ -z "${HOMEBREW_PREFIX:-}" ]; then
    for _b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$_b" ]; then
            eval "$("$_b" shellenv)"
            break
        fi
    done
    unset _b
fi

# GNU tools ahead of the BSD ones, so Linux flags (ls -X, du --max-depth,
# sed -i, xargs -r, stat -c...) keep working. g-prefixed names still exist.
if [ -n "${HOMEBREW_PREFIX:-}" ]; then
    for _g in coreutils findutils gnu-sed grep gnu-tar make; do
        _d="$HOMEBREW_PREFIX/opt/$_g/libexec/gnubin"
        case ":$PATH:" in
            *":$_d:"*) ;;
            *) [ -d "$_d" ] && PATH="$_d:$PATH" ;;
        esac
    done
    unset _g _d
    export PATH
fi

export BASH_SILENCE_DEPRECATION_WARNING=1
