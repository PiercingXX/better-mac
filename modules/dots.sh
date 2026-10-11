# shellcheck shell=bash
# GitHub.com/PiercingXX
# kitty, nvim, tmux and yazi from piercing-dots. Each config is copied as-is
# and macOS fixes from dots/<app>/ are applied to a staged copy first, so a
# rerun with no upstream changes leaves everything untouched.

dots_install() {
    say "Installing kitty, nvim, tmux and yazi configs..."
    _dots_packages
    if [ "$DRY_RUN" -eq 1 ]; then
        dry "kitty.conf + include macos.conf -> ~/.config/kitty/"
        dry "nvim config -> ~/.config/nvim/ (plugins install on first launch via vim.pack)"
        dry ".tmux.conf with pbcopy -> ~/.tmux.conf, TPM + plugins, tmux-256color terminfo"
        dry "yazi config with macOS openers -> ~/.config/yazi/"
        return 0
    fi
    ensure_piercing_dots || return 0
    _dots_kitty
    _dots_nvim
    _dots_tmux
    _dots_yazi
    ok "kitty, nvim, tmux and yazi configured."
}

_dots_packages() {
    brew_cask kitty font-fira-code-nerd-font
    # nvim: telescope, LSPs, formatters, glow/img-clip helpers
    brew_formula neovim ripgrep fd node chafa glow imagemagick tree-sitter-cli \
        bash-language-server shfmt
    brew_formula tmux ncurses
    # yazi previewers (ffmpeg, 7z, jq, pdf, svg) and rich-preview
    brew_formula yazi ffmpeg sevenzip jq poppler resvg rich-cli
}

_dots_kitty() {
    local stage
    stage="$(mktemp -d)"
    cp -R "$PIERCING_DOTS_DIR/dots/kitty/." "$stage/"
    cp "$BETTER_MAC_ROOT/dots/kitty/macos.conf" "$stage/macos.conf"
    printf '\n# better-mac: macOS overrides\ninclude macos.conf\n' >>"$stage/kitty.conf"
    install_dir "$stage" "$HOME/.config/kitty"
    rm -rf "$stage"
}

_dots_nvim() {
    install_dir "$PIERCING_DOTS_DIR/dots/nvim" "$HOME/.config/nvim"
}

_dots_tmux() {
    local stage
    stage="$(mktemp)"
    sed -f "$BETTER_MAC_ROOT/dots/tmux/macos.sed" "$PIERCING_DOTS_DIR/resources/tmux/.tmux.conf" >"$stage"
    install_file "$stage" "$HOME/.tmux.conf"
    rm -f "$stage"

    # macOS's ncurses is too old to know tmux-256color (default-terminal)
    if ! /usr/bin/infocmp tmux-256color >/dev/null 2>&1; then
        stage="$(mktemp)"
        if "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/ncurses/bin/infocmp" -x tmux-256color >"$stage" 2>/dev/null \
            && /usr/bin/tic -x -o "$HOME/.terminfo" "$stage" 2>/dev/null; then
            ok "tmux-256color terminfo compiled into ~/.terminfo."
        else
            warn "Could not install the tmux-256color terminfo; colors inside tmux may be off."
        fi
        rm -f "$stage"
    fi

    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        git clone -q --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" \
            || { warn "Could not clone TPM; tmux plugins not installed."; return 0; }
    fi
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null 2>&1 \
        || warn "TPM plugin install failed; press prefix + I inside tmux."
}

_dots_yazi() {
    local stage
    stage="$(mktemp -d)"
    cp -R "$PIERCING_DOTS_DIR/dots/yazi/." "$stage/"
    sed -E -f "$BETTER_MAC_ROOT/dots/yazi/macos.sed" "$PIERCING_DOTS_DIR/dots/yazi/yazi.toml" >"$stage/yazi.toml"
    sed -f "$BETTER_MAC_ROOT/dots/yazi/macos-keymap.sed" "$PIERCING_DOTS_DIR/dots/yazi/keymap.toml" >"$stage/keymap.toml"
    install_dir "$stage" "$HOME/.config/yazi"
    rm -rf "$stage"
}
