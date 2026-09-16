# devspace — Coder VM (ephemeral linux dev box)
# TODO: confirm arch (`uname -m`) and whether $HOME persists across rebuilds;
# if not, the Coder startup script re-runs `nix run home-manager -- switch`.
{ pkgs, ... }:
{
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
    eza
  ];
}
