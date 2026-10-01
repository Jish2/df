# herdr is the fleet multiplexer — the only surface an agent can drive and
# the human can attach to (FLEET.md). Without a service definition the
# server only runs from whenever the TUI was last opened, so a rebooted box
# sits with a dead server (verified live 2026-10-01 on devspace; mini is
# always-on and headless, so a dead server there costs the most).
#
# Two modes:
#   daemon = true   LaunchDaemon running as the user from boot WITHOUT
#                   login (mini: headless, auto-login off — a LaunchAgent
#                   would never fire after a reboot)
#   daemon = false  LaunchAgent started at login (work/personal: daily
#                   laptops; the server existing only while logged in is
#                   the right lifecycle there)
#
# Binary: whatever herdr install the box already has, resolved at start —
# the self-updating ~/.local/bin/herdr (mini) or the brew formula (work).
# Deliberately not a nix store path: `herdr update` and `brew upgrade`
# keep working, and nix owns the lifecycle, not the version.
{
  config,
  lib,
  pkgs,
  user,
  ...
}:
let
  startScript = pkgs.writeShellScript "herdr-server-start" ''
    H=""
    for c in "$HOME/.local/bin/herdr" /opt/homebrew/bin/herdr; do
      if [ -x "$c" ]; then H="$c"; break; fi
    done
    if [ -z "$H" ]; then
      echo "herdr-server: no herdr binary found" >&2
      exit 1
    fi
    # a server may already be running (TUI-opened or hand-started before the
    # service existed). wait for it to exit, then take over — starting a
    # second instance would just crash-loop on the busy socket.
    while "$H" status 2>/dev/null | grep -q 'status: running'; do
      sleep 30
    done
    exec "$H" server
  '';
in
{
  options.fleet.herdr = {
    enable = lib.mkEnableOption "herdr server as a persistent launchd service";

    daemon = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run as a LaunchDaemon (starts at boot without login, as the user)
        instead of a LaunchAgent (starts at login). For headless always-on
        boxes that may reboot unattended.
      '';
    };
  };

  config = lib.mkIf config.fleet.herdr.enable {
    # SuccessfulExit=false: restart on crash or kill (non-zero exit), but a
    # deliberate `herdr server stop` (exit 0) is not fought by launchd.
    launchd.agents.herdr-server = lib.mkIf (!config.fleet.herdr.daemon) {
      serviceConfig = {
        Label = "org.jgoon.herdr-server";
        ProgramArguments = [ "${startScript}" ];
        EnvironmentVariables.PATH = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin";
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
      };
    };

    launchd.daemons.herdr-server = lib.mkIf config.fleet.herdr.daemon {
      serviceConfig = {
        Label = "org.jgoon.herdr-server";
        ProgramArguments = [ "${startScript}" ];
        UserName = user;
        # daemons do not inherit a user session environment
        EnvironmentVariables = {
          HOME = "/Users/${user}";
          PATH = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin";
        };
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
      };
    };
  };
}
