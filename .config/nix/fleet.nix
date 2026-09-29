# fleet.nix — the fleet map, single source of truth.
#
# Each attribute: attr name = the fleet-wide SSH alias (matches the
# flake attrs and FLEET.md). Value = the node's stable tailscale IP,
# assigned by headscale at registration (stable until a node is deleted
# and re-registered).
{
  work = "100.64.0.2"; # MBP M4 Max (hq-kp2hjmhq7r)
  mini = "100.64.0.3"; # M1 Mac mini (joshuas-mac-mini)
  pc = "100.64.0.6"; # desktop, NixOS
  personal = "100.64.0.5"; # MBP M3 Pro (mac-1764)
}
