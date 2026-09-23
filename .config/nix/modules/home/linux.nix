# HM extras for linux hosts (standalone HM on Omarchy / Coder)
{ pkgs, user, ... }:
let
  tools = import ../tools.nix;
  nameOrAttr = t: t.nix;
in
{
  home.packages = map (t: pkgs.${t.nix}) tools;

  home.homeDirectory = "/home/${user}";

  # non-NixOS glue: wires nix profile into XDG paths / session. If it ever
  # fights Omarchy's own config, flip this off here.
  targets.genericLinux.enable = true;
}
