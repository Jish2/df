# fleet.nix — the fleet map, single source of truth.
#
# Each attribute: attr name = the fleet-wide SSH alias (matches the
# flake attrs and FLEET.md). Value = the node's stable tailscale IP,
# assigned by headscale at registration (stable until a node is deleted
# and re-registered).
#
# Used by modules/home/ssh-aliases.nix to generate SSH aliases for every
# machine on every machine. Self is excluded by hostname match.
#
# Keep in sync with: FLEET.md, headscale (docker exec headscale headscale
# nodes list), and ~/.ssh/ts-host-overrides on machines not yet on the
# flake (bootstrap-only; the script is retired once a box switches).
{
  work = "100.64.0.2"; # MBP M4 Max (hq-kp2hjmhq7r)
  mini = "100.64.0.3"; # M1 Mac mini (joshuas-mac-mini)
  pc = "100.64.0.6"; # desktop, NixOS
  personal = "100.64.0.5"; # MBP M3 Pro (mac-1764) — offline
}
