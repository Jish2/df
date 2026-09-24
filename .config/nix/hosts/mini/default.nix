# mini — M1 Mac Mini, always on (aarch64-darwin), server-ish profile
# package lists imported 2026-09-21 from a live pass over the machine
# (`brew tap` / `brew leaves` / `brew list --cask`), so they describe the
# status quo, including its quirks — triage comes later, with `make plan
# HOST=mini` on the machine; cleanup stays "none" until the 'would be
# REMOVED' list is empty.
{ pkgs, ... }:
{
  networking.hostName = "Joshuas-Mac-mini";
  networking.localHostName = "Joshuas-Mac-mini";
  networking.computerName = "Joshua’s Mac mini"; # (curly apostrophe, as shipped)

  # always-on server power settings (nix-darwin has no pmset module).
  # matches the machine's current `pmset -g`: never sleeps, wakes for
  # network, restarts after power loss.
  system.activationScripts.pmset.text = ''
    pmset -a sleep 0 displaysleep 0 disksleep 0 standby 0 powernap 1 womp 1 autorestart 1
  '';

  # extra nix-side CLI tools beyond modules/darwin/common.nix
  environment.systemPackages = with pkgs; [
    htop # keep an eye on the load averages this box racks up
  ];

  homebrew = {
    taps = [
      "aserto-dev/tap"
      "derailed/k9s"
      "hashicorp/tap"
      "hidetatz/tap"
      "nikolaeu/numi"
      "opcr-io/tap"
      "oven-sh/bun"
      "steipete/tap"
      "teamookla/speedtest"
      "xcodesorg/made"
    ];

    brews = [
      # --- k8s / infra -------------------------------------------------------
      "argocd"
      "helm"
      "krew"
      "awscli"
      "cloudflared" # several tunnels run as com.jgoon.cloudflared.* launchagents
      "grpcurl"
      # --- languages / toolchains -------------------------------------------
      "go"
      "php"
      "pyenv"
      "pnpm"
      "rustup"
      "swift" # non-xcode swift toolchain — verify it's still wanted
      "swiftformat"
      "uv"
      "volta"
      "xcbeautify"
      "xcode-build-server"
      "cocoapods"
      "zig@0.15"
      # --- cli ---------------------------------------------------------------
      "act"
      "ffmpeg"
      "fzf"
      "gh"
      "git"
      "git-delta"
      "git-lfs"
      "just"
      "lazygit"
      "markdownlint-cli"
      "mas"
      "neovim"
      "pandoc"
      "pure"
      "ripgrep"
      "tmux"
      "vercel"
      "wget"
      "yadm"
      "yarn"
      "yq"
      "zoxide"
      "zsh-autosuggestions"
      "zsh-syntax-highlighting"
      # --- home-infra / mini-specific ----------------------------------------
      "gcalcli"
      "steipete/tap/imsg" # pairs with the BlueBubbles install
      # --- services ----------------------------------------------------------
      {
        name = "postgresql@14";
        restart_service = "changed"; # actively running today (brew services)
      }
      # tailscaled runs out-of-band as a SYSTEM daemon
      # (/Library/LaunchDaemons/com.tailscale.tailscaled.plist, ssh access to
      # this box depends on it). install the CLI, but never let brew services
      # own a second, conflicting daemon.
      "tailscale"
      # --- tap formulae -------------------------------------------------------
      # topaz and policy moved formula→cask upstream (GoReleaser casks, the
      # old formulae were deleted from their taps) — declared in casks
      # below, same as work
    ];

    casks = [
      # --- terminals / editors ----------------------------------------------
      "iterm2"
      "cursor"
      "visual-studio-code"
      "codex"
      "xcodes-app"
      # --- window management / ui utils --------------------------------------
      "rectangle"
      "alt-tab"
      "alfred"
      "caffeine" # belt-and-suspenders with pmset displaysleep 0
      "hiddenbar"
      "homerow"
      "itsycal"
      "karabiner-elements"
      "numi"
      "shottr"
      # --- apps ---------------------------------------------------------------
      "aldente"
      "asset-catalog-tinkerer"
      "beekeeper-studio"
      "docker-desktop" # com.jgoon.docker.plist launchagent starts it at login
      "dotnet-sdk"
      "git-credential-manager"
      "obsidian"
      "postman"
      "session-manager-plugin"
      "spotify"
      # --- tap casks (moved formula→cask upstream) -----------------------------
      "aserto-dev/tap/topaz"
      "opcr-io/tap/policy"
    ];
  };

  # GUI apps installed OUTSIDE brew (don't declare, don't delete):
  #   BlueBubbles.app — iMessage relay, self-updates
  #   Hermes.app      — ai.hermes.gateway launchagent
  #   CuaDriver.app   — c/ua computer-use driver
  #   Xcode-16.2.0.app / Xcode-26.6.0.app — versioned, via Xcodes
  #
  # custom services NOT nix-managed yet (~/Library/LaunchAgents); porting any
  # of these into nix-darwin launchd.agents is a deliberate per-service job:
  #   com.jgoon.cloudflared.{t3code,sure,agent-device,webhooks*}  tunnels
  #   com.jgoon.{hub-mac-control,hub-mac-control-tunnel,t3code}   hobby services
  #   com.jgoon.agent-device.{proxy,proxy-watchdog}
  #   com.jgoon.openpoker-test-sim
  #   com.jgoon.tmux
  #   net.headscale.headscale (+ com.cloudflare.cloudflared.headscale)
  #   com.bluebubbles.server
  #
  # after verifying this import on the machine (`make plan HOST=mini`),
  # go self-cleaning:
  # homebrew.onActivation.cleanup = "zap";
}
