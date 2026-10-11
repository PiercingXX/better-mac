# shellcheck shell=bash
# GitHub.com/PiercingXX
# Bash 5 as the login shell, GNU userland ahead of BSD, and the piercing-dots
# .bashrc (aliases, functions, starship, zoxide, fzf) with macOS fixes layered
# on: ~/.bashrc = dots/bash/pre.bash + piercing-dots .bashrc + dots/bash/post.bash

shell_install() {
    say "Setting up bash, GNU tools and your .bashrc..."
    _shell_packages
    _shell_login
    _shell_dots
}

_shell_packages() {
    brew_formula bash bash-completion@2 \
        coreutils findutils gnu-sed grep gnu-tar make \
        starship zoxide eza bat fzf fd ripgrep fastfetch tree trash-cli jump \
        multitail w3m chafa wget
}

_shell_login() {
    local bash5="${HOMEBREW_PREFIX:-/opt/homebrew}/bin/bash"
    if ! grep -qx "$bash5" /etc/shells 2>/dev/null; then
        run sudo sh -c "echo '$bash5' >> /etc/shells" || warn "Could not add $bash5 to /etc/shells."
    fi
    if [ "${SHELL:-}" != "$bash5" ]; then
        run chsh -s "$bash5" || warn "chsh failed; run: chsh -s $bash5"
    fi
}

_shell_dots() {
    local dots="$BETTER_MAC_ROOT/dots/bash" stage
    install_file "$dots/pre.bash"  "$HOME/.config/better-mac/pre.bash"
    install_file "$dots/post.bash" "$HOME/.config/better-mac/post.bash"
    install_file "$dots/bash_profile" "$HOME/.bash_profile"

    if [ "$DRY_RUN" -eq 1 ]; then
        dry "build ~/.bashrc = pre.bash + piercing-dots .bashrc + post.bash"
        dry "install piercing-dots starship.toml and fastfetch config"
        return 0
    fi
    ensure_piercing_dots || return 0

    stage="$(mktemp)"
    {
        printf '%s\n' '# better-mac: Homebrew and GNU tools first (see ~/.config/better-mac/pre.bash)'
        printf '%s\n\n' '[ -f "$HOME/.config/better-mac/pre.bash" ] && . "$HOME/.config/better-mac/pre.bash"'
        cat "$PIERCING_DOTS_DIR/resources/bash/.bashrc"
        printf '\n%s\n' '# better-mac: macOS replacements for Linux-only bits (see ~/.config/better-mac/post.bash)'
        printf '%s\n' '[ -f "$HOME/.config/better-mac/post.bash" ] && . "$HOME/.config/better-mac/post.bash"'
    } >"$stage"
    install_file "$stage" "$HOME/.bashrc"
    rm -f "$stage"

    install_file "$PIERCING_DOTS_DIR/dots/starship.toml" "$HOME/.config/starship.toml"
    install_file "$PIERCING_DOTS_DIR/dots/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
    ok "bash 5 login shell, GNU tools and the piercing-dots .bashrc in place."
}
