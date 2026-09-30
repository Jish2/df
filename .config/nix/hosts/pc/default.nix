# pc — NixOS (x86_64-linux), dual-boots Windows for gaming.
# full fleet member since the system-config fold: nixosConfigurations.pc
# drives BOTH system and user env (HM as a NixOS module — one rebuild).
# this file stays host-local HM additions; the system half lives in
# ./configuration.nix + ./hardware-configuration.nix.
{ pkgs, lib, ... }:
{
  # CLI env comes from modules/tools.nix (nix column) via the hm-linux shared
  # module; host-local additions go below.
  home.packages = with pkgs; [
    # make — the fleet Makefile (`make here`) is the only switch path, and
    # NixOS's minimal install doesn't ship gnumake
    gnumake
  ];

  # GUI apps (browsers, discord, ...) beyond firefox stay flatpak/pacman
  # where desktop integration is native — GNOME via configuration.nix.
}
