# shared by all three macs (work / personal / mini).
# host-specific stuff belongs in hosts/<name>/default.nix.
{
  pkgs,
  config,
  self,
  user,
  ...
}:
{
  imports = [
    # bulk snapshot of this mac's non-default settings (regenerate with
    # scripts/export-defaults.py; rebuilds re-assert these values)
    ./imported-defaults.nix
  ];

  system.primaryUser = user;
  users.users.${user}.home = "/Users/${user}";

  # for smart open in neovim
  environment.variables = {
    LIBSQLITE = "${pkgs.sqlite.out}/lib/libsqlite3.dylib";
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # CLI tools for every mac. GUI apps come from homebrew casks instead.
  # (some of these duplicate brew formulae for now — the brew→nix port wave
  # in FLEET.md settles PATH precedence when entries move)
  environment.systemPackages = with pkgs; [
    neovim
    nixfmt-rfc-style
    defaultbrowser
    yarn
    gh
    yadm # TODO: remove once the yadm port completes
    zoxide
    pure-prompt
    mkalias
    sqlfluff
    ripgrep
    delta
    zsh-syntax-highlighting
    zsh-autosuggestions
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  nix.settings.experimental-features = "nix-command flakes";

  # imported from this machine's actual state (`defaults read`), see FLEET.md.
  # NOTE: previously this flake said autohide=false/tilesize=40 — that had
  # drifted; the machine is actually autohide=true/tilesize=47.
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      ApplePressAndHoldEnabled = false; # hold-to-repeat keys, no accent popup
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      "com.apple.mouse.scaling" = 0.6875; # mouse tracking speed (scroll speed is system default)
      # natural scrolling omitted on purpose — ON is the factory default
    };

    dock = {
      autohide = true; # (factory: false)
      tilesize = 47;
      show-recents = false; # (factory: true)
      # magnification omitted — off is the factory default
    };

    trackpad = {
      Clicking = true; # tap to click (factory: off)
      TrackpadThreeFingerDrag = true; # (factory: off)
      # FirstClickThreshold / SecondClickThreshold omitted — 1 is the factory default
    };

    # menuExtraClock omitted entirely — your clock (AM/PM, date when space
    # allows, no weekday) is the factory configuration

    CustomUserPreferences = {
      # menu bar: battery hidden, wifi/sound/nowplaying/focus shown.
      # keys written verbatim from a Tahoe dump — nix-darwin's first-class
      # controlcenter options predate Tahoe's VisibleCC rename.
      # (bento/cc item positions and analytics blobs deliberately not imported)
      "com.apple.controlcenter" = {
        "NSStatusItem Visible Battery" = 0;
        "NSStatusItem Visible BentoBox" = 1;
        "NSStatusItem Visible Shortcuts" = 0;
        "NSStatusItem VisibleCC Clock" = 1;
        "NSStatusItem VisibleCC FocusModes" = 1;
        "NSStatusItem VisibleCC NowPlaying" = 1;
        "NSStatusItem VisibleCC Sound" = 1;
        "NSStatusItem VisibleCC WiFi" = 1;
      };

      "com.apple.symbolichotkeys" = {
        AppleSymbolicHotKeys = {
          # keep spotlight (cmd+space), disable screenshot shortcuts
          "64" = {
            enabled = true;
            value = {
              parameters = [
                32
                49
                524288
              ];
              type = "standard";
            };
          };
          # Cmd+Shift+3 / Ctrl+Cmd+Shift+3
          "28" = {
            enabled = false;
            value = {
              parameters = [
                131
                3
                262144
              ];
              type = "standard";
            };
          };
          "29" = {
            enabled = false;
            value = {
              parameters = [
                131
                3
                786432
              ];
              type = "standard";
            };
          };
          # Cmd+Shift+4 / Ctrl+Cmd+Shift+4
          "30" = {
            enabled = false;
            value = {
              parameters = [
                131
                4
                262144
              ];
              type = "standard";
            };
          };
          "31" = {
            enabled = false;
            value = {
              parameters = [
                131
                4
                786432
              ];
              type = "standard";
            };
          };
          # Cmd+Shift+5
          "32" = {
            enabled = false;
            value = {
              parameters = [
                131
                5
                262144
              ];
              type = "standard";
            };
          };
        };
      };
    };
  };

  homebrew = {
    enable = true;
    # never delete by default: a rebuild only ever ADDS. after verifying the
    # import on a machine (`brew bundle cleanup` lists what zap would
    # remove), opt in per-host with "zap" so drift self-cleans.
    onActivation.cleanup = "none";
  };

  programs.zsh = {
    enable = true;
    enableSyntaxHighlighting = true;

    # effective /etc/zshrc
    shellInit = ''
      source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    '';
  };

  # touch id for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # pinned at 5 on purpose; read `darwin-rebuild changelog` before bumping
  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 5;

  system.activationScripts.postActivation.text = ''
    defaultbrowser chrome
  '';

  # copy apps into /Applications (as finder aliases) so spotlight indexes them
  system.activationScripts.applications.text =
    let
      env = pkgs.buildEnv {
        name = "system-applications";
        paths = config.environment.systemPackages;
        pathsToLink = "/Applications";
      };
    in
    pkgs.lib.mkForce ''
      echo "setting up /Applications..." >&2
      rm -rf /Applications/Nix\ Apps
      find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
      while read -r src; do
        app_name=$(basename "$src")
        echo "copying $src" >&2
        ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/$app_name"
      done
    '';
}
