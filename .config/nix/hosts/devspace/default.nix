# devspace — Coder VM (ephemeral root disk, persistent $HOME volume).
#
# facts confirmed 2026-09-30: Ubuntu 24.04, x86_64, user `coder`,
# $HOME /home/coder on its own EBS volume (survives workspace rebuilds);
# the EC2 instance (and /nix + nix profiles with it) is recreated from
# the AMI on rebuild — re-applied at boot by the devspace-nix-apply unit
# (scripts/devspace-apply.sh).
#
# hostname is jgoon-jgoon-box; `make here` maps it via the hostmap.
{ pkgs, ... }:
{
  # base CLI set comes from modules/tools.nix (nix column)
  home.packages = with pkgs; [ ];

  # herdr server as a boot-persistent user service.
  #
  # Why: devspace is reached only over ssh (machine API, herdr --remote),
  # and every workspace rebuild / reboot used to leave the server down —
  # breaking both access paths until someone noticed the TUI's Attention
  # badge. Linger is on (devspace-nix-apply.timer already relies on it),
  # so a user service starts with the boot.
  #
  # The binary is herdr's self-updating install in ~/.local/bin (on the
  # persistent home volume), deliberately NOT a nix store path: `herdr
  # update` swaps it in place and the unit keeps working across updates.
  # nix owns the lifecycle, not the version.
  #
  # User units cannot order against the system home-coder.mount, and the
  # boot-time user manager starts ~80s before the mount lands (measured
  # live, see scripts/devspace-apply.sh) — so the ExecStart wrapper waits
  # for the home volume with the same st_dev guard, then execs. Restart
  # covers whatever the wait can't (crash, binary missing mid-race).
  systemd.user.services.herdr-server = {
    Unit = {
      Description = "herdr: headless session server (persistent panes for devspace)";
      # a failing ExecStart would otherwise burn the default 5-starts/10s
      # burst before the mount arrives; RestartSec paces retries instead.
      StartLimitIntervalSec = 0;
    };
    Service = {
      Type = "simple";
      ExecStart =
        "${pkgs.writeShellScript "herdr-server-start" ''
          home="$1"
          for _ in $(seq 1 90); do
            [ "$(stat -c %d "$home")" != "$(stat -c %d /)" ] \
              && exec "$home/.local/bin/herdr" server
            sleep 2
          done
          # home volume never landed: fail so the paced restart retries,
          # instead of exec-ing into the bare root-disk $HOME
          echo "herdr-server: home volume not mounted, retrying" >&2
          exit 1
        ''} %h";
      Restart = "on-failure";
      RestartSec = 15;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
