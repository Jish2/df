# pc — NixOS (x86_64-linux), dual-boots Windows for gaming.
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
}
