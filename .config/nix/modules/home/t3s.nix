# t3s sidecar indexing for Linux HM hosts (devspace standalone HM, pc NixOS).
#
# Same job as modules/darwin/fleet-t3s.nix: keep this machine's
# ~/.local/share/t3s/index.db fresh so `t3s sync` on another box can pull
# it. Systemd user timer, every 30 minutes. The t3s binary ships via
# private-skills (common/t3-history/bin) — resolved at start, nix owns
# the schedule, not the version.
{
  pkgs,
  ...
}:
let
  t3sIndex = pkgs.writeShellScript "t3s-index" ''
    T3S=""
    for c in \
      "$HOME/private-skills/common/t3-history/bin/t3s" \
      "$HOME/.local/bin/t3s"; do
      if [ -x "$c" ]; then T3S="$c"; break; fi
    done
    [ -n "$T3S" ] || { echo "t3s-index: no t3s binary found" >&2; exit 0; }
    exec "$T3S" index
  '';

  t3sOnPath = pkgs.writeShellScriptBin "t3s" ''
    exec "$HOME/private-skills/common/t3-history/bin/t3s" "$@"
  '';
in
{
  home.packages = [ t3sOnPath ];

  systemd.user.services.t3s-index = {
    Unit.Description = "t3s: refresh the local T3 thread sidecar";
    Service = {
      Type = "oneshot";
      ExecStart = "${t3sIndex}";
      # misses while the box is off don't matter; next timer tick catches up
      Nice = 10;
    };
  };

  systemd.user.timers.t3s-index = {
    Unit.Description = "t3s sidecar refresh (every 30 min)";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      # don't stack runs if a refresh hangs
      Persistent = false;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
