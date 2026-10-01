# pc — NixOS (x86_64-linux), dual-boots Windows for gaming.
# this file stays host-local HM additions; the system half lives in
# ./configuration.nix + ./hardware-configuration.nix.
{ pkgs, lib, ... }:
{
  # CLI env comes from modules/tools.nix (nix column) via the hm-linux shared
  # module; host-local additions go below.
  home.packages = with pkgs; [
    # make — the fleet Makefile (`make here`) is the only switch path, and
    # NixOS's minimal install doesn't ship gnumake
    gnumake
  ];

  # herdr server as a boot-persistent user service. shape mirrors hosts/
  # devspace (herdr is the fleet multiplexer — the only surface an agent
  # can drive and the human can attach to). the binary is resolved at
  # start — the nix-profile install today, or ~/.local/bin if `herdr
  # update` ever relocates it — not ${pkgs.herdr}: that would pin the
  # flake's older nixpkgs copy next to the profile's herdrdev-flake
  # install (version skew between server and CLI). nix owns the
  # lifecycle, not the version. linger (configuration.nix) runs the user
  # manager at boot; NixOS has no home-mount race, so no wait wrapper.
  # If a server is already running at start (pre-service TUI/hand-start),
  # the wrapper waits for it to exit and takes over.
  systemd.user.services.herdr-server = {
    Unit.Description = "herdr: headless session server (persistent panes for pc)";
    Service = {
      Type = "simple";
      ExecStart =
        "${pkgs.writeShellScript "herdr-server-start" ''
          home="$1"
          H=""
          for c in "$home/.local/bin/herdr" "$home/.nix-profile/bin/herdr"; do
            [ -x "$c" ] && H="$c" && break
          done
          if [ -z "$H" ]; then
            echo "herdr-server: no herdr binary found" >&2
            exit 1
          fi
          # wait out any pre-service server (TUI-opened or hand-started
          # before this service existed), then take over — a second
          # instance would just crash-loop on the busy socket
          while "$H" status 2>/dev/null | grep -q 'status: running'; do
            sleep 30
          done
          exec "$H" server
        ''} %h";
      Restart = "on-failure";
      RestartSec = 15;
      StartLimitIntervalSec = 0;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
