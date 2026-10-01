# devspace — Coder VM (ephemeral root disk, persistent $HOME volume).
#
# facts confirmed 2026-09-30: Ubuntu 24.04, x86_64, user `coder`,
# $HOME /home/coder on its own EBS volume (survives workspace rebuilds);
# the EC2 instance (and /nix + nix profiles with it) is recreated from
# the AMI on rebuild — re-applied at boot by the devspace-nix-apply unit
# (scripts/devspace-apply.sh).
#
# hostname is jgoon-jgoon-box; `make here` maps it via the hostmap.
{ pkgs, ... }:
{
  # base CLI set comes from modules/tools.nix (nix column)
  home.packages = with pkgs; [ ];
}
