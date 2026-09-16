# pc — Omarchy (Arch, x86_64-linux), dual-boots Windows for gaming.
# standalone home-manager on top of Omarchy; nix is deliberately NOT the
# system package manager here.
{ pkgs, ... }:
{
  # CLI env mirrors the macs' one. GUI apps (hyprland tweaks, browsers,
  # discord, ...) stay on pacman/omarchy where desktop integration is native.
  home.packages = with pkgs; [
    neovim
    tmux
    git
    lazygit
    delta
    fzf
    ripgrep
    fd
    zoxide
    jq
    yq
    gh
    just
    btop
    mosh
    eza
  ];

  # TODO: confirm Omarchy's zsh setup doesn't fight ours when the yadm port
  # brings .zshrc under home-manager.
}
