# pc — Omarchy (Arch, x86_64-linux), dual-boots Windows for gaming.
# standalone home-manager on top of Omarchy; nix is deliberately NOT the
# system package manager here.
{ pkgs, lib, ... }:
{
  # CLI env comes from modules/tools.nix (nix column) via the hm-linux shared
  # module; host-local additions go below.
  home.packages = with pkgs; [
    # pc-specific: nothing yet
  ];

  # GUI apps (hyprland tweaks, browsers, discord, ...) stay on pacman/omarchy
  # where desktop integration is native.
  # TODO: confirm Omarchy's zsh setup doesn't fight ours when the yadm port
  # brings .zshrc under home-manager.
}
