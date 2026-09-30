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
      serviceConfig = {
        Label = "org.jgoon.tailscaled";
        ProgramArguments = [
          "${pkgs.tailscale}/bin/tailscaled"
          "--state=/var/lib/tailscale/tailscaled.state"
          "--socket=/var/run/tailscaled.socket"
        ];
        RunAtLoad = true;
        KeepAlive = true;
      };
    };
  };
}
