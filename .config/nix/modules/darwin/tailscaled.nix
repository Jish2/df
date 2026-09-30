# Headless mesh client for every mac in the fleet (nix-built daemon + CLI;
# no GUI app, no network extension — the same headless pair mini ran
# out-of-band via brew since April).
#
# What runs: a root launchd daemon tailscaled (state at
# /var/lib/tailscale/tailscaled.state, unix socket /var/run/tailscaled.socket)
# and the CLI on PATH via the system profile.
#
# Node identity: the state file. Migrate a box's existing state once and it
# keeps its mesh IP; without one, the daemon starts unjoined and the
# tailnet-join wizard (~/.agents/skills/tailnet-join) joins it.
#
# --accept-dns=false fleet-wide: the company VPN DNS conflict (vault:
# "tailscale company vpn dns conflict"); headscale also currently
# advertises global nameservers, which would hijack non-tailnet DNS.
#
# Per-variant migration (do once, before/at first switch):
#   App Store variant (HQ): quit the app; copy the state file out of
#     ~/Library/Containers/io.tailscale.ipn.macos/Data/Library/Application
#     Support/Tailscale/tailscaled.state to /var/lib/tailscale/
#   brew daemon (mini): the wizard stops the brew daemon; the state file
#     is already at /var/lib/tailscale if brew's daemon used it —
#     otherwise copy from brew's statedir. Then switch.
# After first switch: `tailscale status` must show the pre-migration IP.
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
