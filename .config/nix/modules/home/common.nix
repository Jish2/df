# HM baseline for all five machines.
{
  user,
  ...
}:
{
  home.username = user;
  home.stateVersion = "25.05";
  programs.home-manager.enable = true;

  # tailnet ssh aliases for every fleet peer (fleet.nix is the source of
  # truth). self is set per host in hosts/<attr>/default.nix.
  imports = [ ./ssh-aliases.nix ];

  # NOTE: backupFileExtension ("bak") is declared by the flake itself in the
  # darwin HM block (system-level) — can't live here; this file is a user
  # module on the darwin path. standalone HM sets it in mkHome.

  # NOTE 2: nothing else here yet — per-host HM settings land in
  # hosts/<attr>/default.nix; shared darwin/linux extras live in
  # modules/home/{darwin,linux}.nix.
}
