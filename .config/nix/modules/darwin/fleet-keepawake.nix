# fleet.keepAwake — assert "prevent sleep on AC power" for docked always-on use.
#
# Why: when a laptop host is docked (external display + AC power + input
# devices), macOS clamshell mode keeps it running with the lid closed, but
# only while something holds a power assertion or `sleep 0` is in effect.
# T3 Code holds one while running, but that is an implementation detail —
# environment servers, tailscale serve mappings, and herdr panes should not
# depend on any particular GUI app staying open. `caffeinate -s` asserts
# "prevent system sleep while on AC power" and nothing more:
#
#   - docked + plugged in → never sleeps (lid closed included, clamshell)
#   - on battery / undocked → sleeps normally (assertion is a no-op on battery)
#
# This mirrors what pc does declaratively via systemd sleep AllowSuspend=false
# (hosts/pc/configuration.nix) — the mac equivalent, scoped to AC power.
# Run as a LaunchAgent, not a daemon: keep-awake only matters in a logged-in
# session; logout should stop holding the machine up.
{
  config,
  lib,
  ...
}:
{
  options.fleet.keepAwake = {
    enable = lib.mkEnableOption "caffeinate keep-awake while on AC power (docked)";

    includeDisplay = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also prevent display sleep (-d). Off by default: the display sleeping
        on a docked box is fine (and saves power); only the SYSTEM must stay
        up for remote clients (phone, tailnet, herdr).
      '';
    };
  };

  config = lib.mkIf config.fleet.keepAwake.enable {
    launchd.agents.docked-keepawake = {
      serviceConfig = {
        Label = "org.jgoon.docked-keepawake";
        ProgramArguments = [
          "/usr/bin/caffeinate"
          "-s"
        ] ++ (lib.optionals config.fleet.keepAwake.includeDisplay [ "-d" ]);
        RunAtLoad = true;
        # SuccessfulExit=false: restart if killed. caffeinate never exits on
        # its own; a deliberate kill is the only exit path, and launchd
        # bringing it back matches the declared state.
        KeepAlive.SuccessfulExit = false;
      };
    };
  };
}
