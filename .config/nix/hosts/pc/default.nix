# pc — NixOS (x86_64-linux), dual-boots Windows for gaming.
# this file stays host-local HM additions; the system half lives in
# ./configuration.nix + ./hardware-configuration.nix.
{
  inputs,
  pkgs,
  lib,
  ...
}:
{
  # CLI env comes from modules/tools.nix (nix column) via the hm-linux shared
  # module; host-local additions go below.
  home.packages = with pkgs; [
    # make — the fleet Makefile (`make here`) is the only switch path, and
    # NixOS's minimal install doesn't ship gnumake
    gnumake
    # herdr — from the pinned herdrdev flake input, so CLI and server come
    # from one closure and pc's herdr is reproducible from this repo
    # (replacing the manual `nix profile install` that a rebuilt pc lost).
    # darwin boxes keep brew — see hosts/work brews + FLEET.md.
    inputs.herdr.packages.${pkgs.system}.herdr
    # claude-code — CLI on mini+pc only (darwin uses the brew cask so it
    # floats current; work/personal/devspace stay without it)
    claude-code
  ];

  # herdr server as a boot-persistent user service. shape mirrors hosts/
  # devspace (herdr is the fleet multiplexer — the only surface an agent
  # can drive and the human can attach to). resolution order below puts
  # ~/.local/bin first — a deliberate escape hatch: `herdr update` on pc
  # installs the self-updating binary there and the service follows it
  # without a rebuild — with the HM package as the reproducible floor.
  # linger (configuration.nix) runs the user manager at boot; NixOS has
  # no home-mount race, so no wait wrapper.
  systemd.user.services.herdr-server = {
    Unit.Description = "herdr: headless session server (persistent panes for pc)";
    Service = {
      Type = "simple";
      ExecStart =
        "${pkgs.writeShellScript "herdr-server-start" ''
          home="$1"
          H=""
          # resolution order: self-updating install first (escape hatch
          # — `herdr update` works without a rebuild), then the HM-managed
          # package (the reproducible floor), then the legacy manual nix
          # profile (removed at rollout; kept for the transition switch).
          for c in \
            "$home/.local/bin/herdr" \
            "/etc/profiles/per-user/jgoon/bin/herdr" \
            "$home/.nix-profile/bin/herdr"; do
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
