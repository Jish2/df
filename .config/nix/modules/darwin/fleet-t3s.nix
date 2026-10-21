# fleet.t3s — per-machine T3 Code thread indexing for the `t3s` CLI.
#
# t3s (common/t3-history skill) indexes this machine's T3 store
# (~/.t3/userdata/statev2.sqlite) into a small FTS5 sidecar
# (~/.local/share/t3s/index.db). `t3s sync` then pulls other machines'
# sidecars over ssh, so a search on one box sees the whole fleet.
#
# This module only keeps the LOCAL sidecar fresh: a periodic launchd
# agent (macs) runs `t3s index`. Sync is deliberately on-demand (the
# skill tells agents to run it when a remote sidecar is stale) rather
# than a second timer — pulling from five hosts on every box would be
# five timers doing network I/O for one query surface.
#
# The t3s script itself ships via private-skills (common/t3-history/bin),
# symlinked into each harness's skill dir by skills-sync. The nix side
# puts it on PATH and owns the schedule. Like fleet-herdr, the binary
# is resolved at start (skills-sync re-links on every make here), not
# a nix store path — nix owns the lifecycle, not the version.
{
  config,
  lib,
  pkgs,
  user,
  ...
}:
let
  t3sStart = pkgs.writeShellScript "t3s-index" ''
    T3S=""
    for c in \
      "$HOME/private-skills/common/t3-history/bin/t3s" \
      "$HOME/.local/bin/t3s"; do
      if [ -x "$c" ]; then T3S="$c"; break; fi
    done
    [ -n "$T3S" ] || { echo "t3s-index: no t3s binary found" >&2; exit 0; }
    exec "$T3S" index
  '';
in
{
  options.fleet.t3s = {
    enable = lib.mkEnableOption "periodic local t3s sidecar indexing";
  };

  config = lib.mkIf config.fleet.t3s.enable {
    # t3s on PATH for interactive shells and agents
    home-manager.users.${user}.home.packages = [
      (pkgs.writeShellScriptBin "t3s" ''
        exec "$HOME/private-skills/common/t3-history/bin/t3s" "$@"
      '')
    ];

    launchd.agents.t3s-index = {
      serviceConfig = {
        Label = "org.jgoon.t3s-index";
        ProgramArguments = [ (lib.getExe pkgs.bash) "${t3sStart}" ];
        RunAtLoad = true;
        # every 30 minutes; StartCalendarInterval would miss catch-up
        StartInterval = 1800;
        # missed runs while asleep fire once on wake (machines sleep a lot)
        Nice = 10;
      };
    };
  };
}
