# HM extras for macOS hosts (loaded as a nix-darwin module)
{ user, ... }:
{
  home.homeDirectory = "/Users/${user}";
}
