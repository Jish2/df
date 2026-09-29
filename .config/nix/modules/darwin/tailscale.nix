# auto-join every mac in the fleet to the personal headscale control plane.
#
# model: the `tailscale-app` cask is the standalone "macsys" pkg — the same
# variant mini has been running out-of-band since April — and it brings:
#   - a system tailscaled LaunchDaemon (root, /Library/LaunchDaemons,
#     socket /var/run/tailscaled.socket; NOT a brew service, so it never
#     fights brew services)
#   - the CLI at /usr/local/bin/tailscale
#   - the menu bar app (same icon as the App Store variant)
# The cask is opt-in per host (`fleet.tailscale.enableCask`) because mini's
# daemon is deliberately out-of-band (ssh access to that box depends on it;
# upgrading it mid-switch via brew is a deliberate, separate job).
#
# the joiner: appended to postActivation (which nix-darwin runs AFTER the
# homebrew bundle step), idempotent:
#   - daemon socket not up yet → wait up to 30s, then skip (next switch retries)
#   - BackendState == Running → no-op (already joined)
#   - key file present → tailscale up --login-server ... --auth-key <KEY>
#   - no key file → skip (fresh box just runs without joining)
#
# key policy: ONE reusable pre-auth key (365d), minted with `make hs-mint`
# (SSM to the headscale instance) and written straight to
# ~/.config/nix/secrets/tailscale-authkey (mode 600, gitignored — see
# .gitignore; this repo is public, keys are never committed, per the vault
# note "headscale cloudflare tunnel").
#
# --accept-dns=false everywhere: the company VPN DNS conflict (vault:
# "tailscale company vpn dns conflict") — and until headscale advertises
# scoped split DNS instead of global nameservers, accepting DNS would
# hijack non-tailnet resolution anyway. Revisit after the server-side
# split_dns change.
#
# NOTE: custom names under system.activationScripts.<name> are silently
# never run — nix-darwin only executes its fixed script list (see
# modules/system/activation-scripts.nix upstream). Custom work must go
# through preActivation / extraActivation / postActivation. (This is also
# why mini's old `pmset` script did nothing — fixed in hosts/mini.)
{
  config,
  lib,
  user,
  ...
}:
let
  cfg = config.fleet.tailscale;
  loginServer = "https://headscale.jgoon.com";
  keyFile = "/Users/${user}/.config/nix/secrets/tailscale-authkey";
in
{
  options.fleet.tailscale = {
    enableCask = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the tailscale-app cask (GUI + system daemon + CLI) via
        homebrew. Leave off for hosts whose tailscaled is managed
        out-of-band (mini), or that use another variant.
      '';
    };
  };

  config = {
    homebrew.casks = lib.mkIf cfg.enableCask [ "tailscale-app" ];

    system.activationScripts.postActivation.text = lib.mkAfter ''
      # --- fleet headscale auto-join (modules/darwin/tailscale.nix) ---
      TS=/usr/local/bin/tailscale

      # fresh box: the cask pkg may still be settling — wait for the socket
      i=0
      while [ "$i" -lt 30 ] && [ ! -S /var/run/tailscaled.socket ]; do
        sleep 1
        i=$((i+1))
      done
      if [ ! -S /var/run/tailscaled.socket ]; then
        echo "tailscale: daemon socket missing, skipping join (next switch retries)" >&2
      elif [ ! -x "$TS" ]; then
        echo "tailscale: CLI missing (cask off?), skipping join" >&2
      else
        # jq is NOT on the activation PATH — parse the JSON with sed
        state=$("$TS" status --json 2>/dev/null | sed -n 's/.*"BackendState": *"\([A-Za-z]*\)".*/\1/p')
        if [ "$state" = "Running" ]; then
          : # already joined — every rebuild is a no-op
        elif [ -f "${keyFile}" ]; then
          if "$TS" up --login-server ${loginServer} \
              --auth-key "$(cat ${keyFile})" \
              --accept-dns=false >/dev/null 2>&1; then
            echo "tailscale: joined ${loginServer}" >&2
          else
            echo "tailscale: join FAILED (key expired? run: make hs-mint, then re-switch)" >&2
          fi
        else
          echo "tailscale: no key at ${keyFile} — run: make hs-mint, then re-switch" >&2
        fi
      fi
      # --- end headscale auto-join ---
    '';
  };
}
