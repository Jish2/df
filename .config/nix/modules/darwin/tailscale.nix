# fleet tailnet base — make sure every mac HAS a tailscale daemon + CLI,
# and point at the join ceremony. This module deliberately does NOT join.
#
# Joining is the tailnet-join wizard's job (~/.agents/skills/tailnet-join,
# shipped to every box by yadm — see FLEET.md "Tailnet"). One join
# mechanism everywhere: any box, any CLI variant (App Store app,
# standalone pkg, brew formula, NixOS system), one command. State on disk
# survives everything afterwards, so the wizard runs exactly once per
# box — this module never needs to re-attempt it.
#
# What nix owns here (the only irreplaceable part): guaranteeing the
# daemon + CLI exist on a freshly bootstrapped mac, so the wizard has
# something to drive. That's the tailscale-app cask (standalone macsys
# pkg: system daemon + menu bar app + CLI at /usr/local/bin) — opt-out
# per host where a variant already runs out-of-band (mini) or can't
# install from this network (work, SNI-blocked: *.tailscale.com TLS-reset
# — App Store variant runs against headscale unchanged; flip when the
# block clears).
#
# join flags worth remembering: --accept-dns=false everywhere (company
# VPN DNS conflict, vault: "tailscale company vpn dns conflict").
{
  config,
  lib,
  ...
}:
let
  cfg = config.fleet.tailscale;
in
{
  options.fleet.tailscale = {
    enableCask = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the tailscale-app cask (system daemon + menu bar app +
        CLI) via homebrew. Leave off for hosts whose tailscaled is
        managed out-of-band (mini), or that use another variant (work,
        App Store).
      '';
    };
  };

  config = {
    homebrew.casks = lib.mkIf cfg.enableCask [ "tailscale-app" ];
  };
}
