# Node identity lives in the state file: a box with an existing
# /var/lib/tailscale/tailscaled.state keeps its mesh IP; without one the
# daemon starts unjoined and the tailnet-join wizard
# (~/.agents/skills/tailnet-join) joins it. Joins are wizard-only —
# this module never ships a key.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.fleet.tailscaled = {
    enable = lib.mkEnableOption "headless mesh client (tailscaled + CLI)";
  };

  config = lib.mkIf config.fleet.tailscaled.enable {
    environment.systemPackages = [ pkgs.tailscale ];

    launchd.daemons.tailscaled = {
      # `command`, not ProgramArguments: nix-darwin wraps it in
      # `/bin/wait4path /nix/store`. At boot launchd can start this before
      # the nix volume is mounted; the exec then fails with EX_CONFIG and
      # launchd never retries it, KeepAlive or not (mini, 2026-10-28).
      command = "${pkgs.tailscale}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscaled.socket";
      serviceConfig = {
        Label = "org.jgoon.tailscaled";
        RunAtLoad = true;
        KeepAlive = true;
      };
    };
  };
}
