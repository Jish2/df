# devspace — Coder VM (ephemeral linux dev box)
# TODO: confirm arch (`uname -m`) and whether $HOME persists across rebuilds;
# if not, the Coder startup script re-runs `nix run home-manager -- switch`.
{ pkgs, ... }:
{
  # base CLI set comes from modules/tools.nix (nix column)
  home.packages = with pkgs; [ ];
}
