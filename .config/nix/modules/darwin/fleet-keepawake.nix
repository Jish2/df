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

    batterySleepMinutes = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 10;
      description = ''
        Idle system-sleep timer (minutes) on BATTERY. null leaves whatever
        value the machine has (i.e. still undeclared).

        This exists because -s is AC-only: it keeps a docked box awake while
        plugged in and is a no-op on battery, so the battery timer is the only
        thing that makes an undocked machine sleep. Without it, a laptop left
        open and unplugged under any assertion (an audio/video context, a
        caffeinate, a browser) simply runs flat -- measured here 2026-11-22/23
        at ~15%/hr, three discharges to 1%, zero sleep events in 14h.

        Deliberately does NOT touch AC Power: sleep 0 there is the docked
        server profile, and -s is what keeps it up. Setting -a would fight
        that intent.
      '';
    };

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

  config = lib.mkMerge [
    (lib.mkIf (config.fleet.keepAwake.enable && config.fleet.keepAwake.batterySleepMinutes != null) {
      # nix-darwin has no pmset module, so this is an activation script (same
      # pattern as hosts/mini). postActivation.text is types.lines, so this
      # appends alongside the other definitions (work's defaultbrowser line,
      # remote-access's sshd/screensharing block) rather than replacing them.
      #
      # Caveat, stated plainly: this re-asserts on every switch and cannot
      # notice an imperative `pmset` afterwards. `make doctor` reports drift.
      system.activationScripts.postActivation.text = ''
        pmset -b sleep ${toString config.fleet.keepAwake.batterySleepMinutes}
      '';
    })

    (lib.mkIf config.fleet.keepAwake.enable {
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
    })
  ];
}
