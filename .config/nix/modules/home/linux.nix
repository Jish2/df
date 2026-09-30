# HM extras for linux hosts (NixOS pc via nixos-rebuild; standalone HM on
# Coder/devspace).
#
# zsh prompt plugins mirror the darwin side (modules/darwin/common.nix):
# pure-prompt ships prompt_pure_setup on fpath via the HM profile in
# NIX_PROFILES, where yadm's ~/.zshrc promptinit guard picks it up.
# zsh-autosuggestions / zsh-syntax-highlighting ship the plugin files;
# ~/.zshrc sources them from NIX_PROFILES (darwin gets them from
# nix-darwin's /etc/zshenv instead, so the zshrc source is guarded).
{ pkgs, user, hostKind ? "standalone", ... }:
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

  # non-NixOS glue for standalone-HM hosts (devspace): wires the nix profile
  # into XDG paths / session. on NixOS (pc) the system already does this and
  # the option would fight it — the flake passes hostKind per build path.
  targets.genericLinux.enable = hostKind == "standalone";
}
