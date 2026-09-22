# work — MBP M4 Max (aarch64-darwin)
# package lists imported from `brew bundle dump` on 2026-01; see the PR
# description for the kept/dropped triage.
{ pkgs, ... }:
{
  networking.hostName = "HQ-KP2HJMHQ7R";
  networking.localHostName = "HQ-KP2HJMHQ7R";
  networking.computerName = "HQ-KP2HJMHQ7R";

  # set the default browser (bundle id com.jgoon.satori; the defaultbrowser
  # cli wants the lowercased last component, i.e. "satori")
  system.activationScripts.postActivation.text = ''
    defaultbrowser satori 2>/dev/null || true # no-op on macs without satori yet
  '';

  # actual dock contents (`defaults read com.apple.dock persistent-apps`).
  # note: this makes the dock fully declarative — drag a new app in and the
  # next rebuild removes it again.
  system.defaults.dock.persistent-apps = [
    "/Applications/Google Chrome.app"
    "/Applications/Satori.app"
    "/Applications/Slack.app"
    "/System/Applications/System Settings.app"
    "/Applications/RobloxStudio.app"
  ];

  # ported from the brew bundle go:/cargo: directives
  environment.systemPackages = with pkgs; [
    gopls
    go-tools # honnef.co/go/tools, provides staticcheck
    delve
    protoc-gen-go
    protoc-gen-go-grpc
    cargo-audit
    cargo-nextest
  ];

  homebrew = {
    taps = [
      "ankitpokhrel/jira-cli"
      "ariga/tap"
      "aserto-dev/tap"
      "cloudflare/cloudflare"
      "opcr-io/tap"
      "steipete/tap"
      "supabase/tap"
      "vanchonlee/tap"
    ];

    brews = [
      # --- k8s / infra -------------------------------------------------------
      "argocd"
      "helm"
      "krew"
      "popeye"
      "awscli"
      "cloudflared"
      "grpcurl"
      # --- languages / toolchains -------------------------------------------
      "go"
      "php"
      "pyenv"
      "uv"
      "volta"
      "zig"
      "zig@0.15"
      "swiftformat"
      "xcbeautify"
      "xcode-build-server"
      "cocoapods"
      # --- cli ---------------------------------------------------------------
      "act"
      "atlas"
      "ffmpeg"
      "git-filter-repo"
      "git-lfs"
      "gnu-tar"
      "googleworkspace-cli"
      "herdr"
      "jira-cli"
      "lcov"
      "markdownlint-cli"
      "md-tui"
      "pandoc"
      "pipx"
      "sshpass"
      "terminal-notifier"
      "tree-sitter-cli"
      "vercel"
      # --- services ----------------------------------------------------------
      {
        name = "ollama";
        restart_service = "changed";
      }
      {
        name = "postgresql@14";
        restart_service = "changed";
      }
      "container"
      # --- tap formulae -------------------------------------------------------
      "aserto-dev/tap/topaz"
      # tart: NOT declared via brew — the cirruslabs tap formula is broken on
      # modern brew; capture-baseline.sh installs the signed release binary
      # to ~/.local/bin as a workaround
      "opcr-io/tap/policy"
      "steipete/tap/remindctl"
      "supabase/tap/supabase"
      {
        name = "tfenv";
        link = false;
      }
    ];

    casks = [
      # --- terminals / editors ----------------------------------------------
      "iterm2"
      "cursor"
      "visual-studio-code"
      "datagrip"
      # --- window management / ui utils --------------------------------------
      "rectangle"
      "alt-tab"
      "jordanbaird-ice"
      "hiddenbar"
      "homerow"
      "karabiner-elements"
      "monitorcontrol"
      "itsycal"
      # --- k8s / cloud --------------------------------------------------------
      "docker-desktop"
      "gcloud-cli"
      "headlamp"
      "session-manager-plugin"
      "vanchonlee/tap/krust"
      # --- apps ---------------------------------------------------------------
      "1password-cli"
      "aldente"
      "alfred"
      "asset-catalog-tinkerer"
      "beekeeper-studio"
      "chromium"
      "daisydisk"
      "dotnet-sdk"
      "git-credential-manager"
      "github"
      "handy"
      "mactex"
      "numi"
      "obsidian"
      "postman"
      "postman-cli"
      "shottr"
      "skills-manager"
      "spotify"
      "temurin"
      "temurin@17"
    ];
  };

  # after verifying this import on the machine, go self-cleaning:
  # homebrew.onActivation.cleanup = "zap";

  # not ported (imperative package managers, left as-is for now):
  #   krew plugins: modify-secret, resource-capacity, view-utilization
  #   npm globals:  corepack, pi-acp (volta/corepack manage these)
  #   go tools:     bbolt, boltdbweb — dropped, etcd debugging relics
  #
  # dropped brew formulae that were in the old Brewfile but are no longer
  # installed: acli, coder, k9s, kubecolor, nomad, terraform, vault, bun,
  # numi-cli, speedtest
  #
  # per-host home-manager settings land here after the yadm port, e.g.
  # home-manager.users.jgoon = { ... };
}
