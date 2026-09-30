# HM extras for linux hosts (standalone HM on Omarchy / Coder)
#
# zsh prompt plugins mirror the darwin side (modules/darwin/common.nix):
# pure-prompt ships prompt_pure_setup on fpath via the HM profile in
# NIX_PROFILES, where yadm's ~/.zshrc promptinit guard picks it up.
# zsh-autosuggestions / zsh-syntax-highlighting ship the plugin files;
# ~/.zshrc sources them from NIX_PROFILES (darwin gets them from
# nix-darwin's /etc/zshenv instead, so the zshrc source is guarded).
{ pkgs, user, ... }:
let
  tools = import ../tools.nix;
  nameOrAttr = t: t.nix;
in
{
  home.packages =
    map (t: pkgs.${t.nix}) tools
    ++ [
      pkgs.pure-prompt
      pkgs.zsh-autosuggestions
      pkgs.zsh-syntax-highlighting
    ];

  home.homeDirectory = "/home/${user}";

  # non-NixOS glue: wires nix profile into XDG paths / session. If it ever
  # fights Omarchy's own config, flip this off here.
  targets.genericLinux.enable = true;
}
