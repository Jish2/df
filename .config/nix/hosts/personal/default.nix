# personal — MBP M3 Pro (aarch64-darwin)
# TODO on first touch of that machine: fill hostname/user, then run the
# FLEET.md import (brew bundle dump + defaults dump) to build its lists.
{ ... }:
{
  # daily laptop: herdr server as a LaunchAgent, alive while logged in
  fleet.herdr.enable = true;

  # networking.hostName = "...";
  # networking.localHostName = "...";

  # intentionally lean: inherits modules/darwin/common.nix only.
  homebrew.brews = [ ];
  homebrew.casks = [ ];
}
