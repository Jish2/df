# ssh into the fleet from off the tailnet (work, once its tailscale client
# goes — FLEET.md "Off-tailnet access"). A remotely managed Cloudflare
# Tunnel publishes this box's sshd at ssh.jgoon.com behind Cloudflare Access;
# the tunnel, ingress, DNS and Access app live in ~/github/terraform
# (envs/cloudflare/mini-ssh-tunnel.tf). This module only runs the connector.
#
# LaunchDaemon as the user, not a LaunchAgent: mini is headless with
# auto-login off, so an agent would never start after a reboot (same reason
# as fleet.herdr.daemon). That also rules out the login Keychain the other
# tunnels read — it stays locked until someone logs in — so the connector
# token is a 0600 file outside the repo, installed once by hand:
#   terraform output -raw mini_ssh_tunnel_token > ~/.cloudflared/mini-ssh.token
#   chmod 600 ~/.cloudflared/mini-ssh.token
#
# Binary: the nix package, not brew — this is an ssh lifeline, so it must
# not depend on brew state (same stance as the nix tailscaled daemon).
{
  config,
  lib,
  pkgs,
  user,
  ...
}:
let
  home = "/Users/${user}";
  tokenFile = "${home}/.cloudflared/mini-ssh.token";

  startScript = pkgs.writeShellScript "cloudflared-ssh-start" ''
    if [ ! -r "${tokenFile}" ]; then
      echo "cloudflared-ssh: missing ${tokenFile} (see modules/darwin/cloudflared-ssh.nix)" >&2
      exit 1
    fi
    exec ${pkgs.cloudflared}/bin/cloudflared tunnel \
      --no-autoupdate \
      run \
      --token-file "${tokenFile}"
  '';
in
{
  options.fleet.cloudflaredSsh = {
    enable = lib.mkEnableOption "Cloudflare Tunnel connector publishing sshd at ssh.jgoon.com";
  };

  config = lib.mkIf config.fleet.cloudflaredSsh.enable {
    launchd.daemons.cloudflared-ssh = {
      serviceConfig = {
        Label = "org.jgoon.cloudflared-ssh";
        ProgramArguments = [ "${startScript}" ];
        UserName = user;
        # daemons do not inherit a user session environment
        EnvironmentVariables.HOME = home;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30; # a missing token file retries slowly, not hot
        StandardErrorPath = "${home}/Library/Logs/cloudflared-ssh.err.log";
        StandardOutPath = "${home}/Library/Logs/cloudflared-ssh.out.log";
      };
    };
  };
}
