# HM extras for linux hosts (standalone HM on Omarchy / Coder)
#
# pure-prompt mirrors the darwin side (modules/darwin/common.nix): the
# package ships prompt_pure_setup on fpath via the HM profile in
# NIX_PROFILES, where yadm's ~/.zshrc promptinit guard picks it up.
{ pkgs, user, ... }:
let
  tools = import ../tools.nix;
  nameOrAttr = t: t.nix;
in
{
  home.packages = map (t: pkgs.${t.nix}) tools ++ [ pkgs.pure-prompt ];

  home.homeDirectory = "/home/${user}";

  # non-NixOS glue: wires nix profile into XDG paths / session. If it ever
  # fights Omarchy's own config, flip this off here.
  targets.genericLinux.enable = true;
}
