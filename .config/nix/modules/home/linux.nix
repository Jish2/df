# HM extras for linux hosts (standalone HM on Omarchy / Coder)
{ user, ... }:
{
  home.homeDirectory = "/home/${user}";

  # non-NixOS glue: wires nix profile into XDG paths / session. If it ever
  # fights Omarchy's own config, flip this off here.
  targets.genericLinux.enable = true;
}
