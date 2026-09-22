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
    jq # used by `make plan`
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

  # hand-curated from this machine's actual state (`defaults read` +
  # scripts/export-defaults.py report), see FLEET.md.
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      ApplePressAndHoldEnabled = false; # hold-to-repeat keys, no accent popup
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
    };

    dock = {
      autohide = true;
      tilesize = 47;
      show-recents = false;
      largesize = 16; # magnification size, if ever enabled
      mru-spaces = false; # don't reorder spaces by recency
      wvous-br-corner = 4; # bottom-right hot corner → Desktop
    };

    trackpad = {
      Clicking = true; # tap to click
      TrackpadThreeFingerDrag = true;
    };

    CustomUserPreferences = {
      "NSGlobalDomain" = { "com.apple.mouse.scaling" = "0.6875"; };
      # menu bar: battery hidden, wifi/sound/nowplaying/focus shown.
      # keys written verbatim from a Tahoe dump — nix-darwin's first-class
      # controlcenter options predate Tahoe's VisibleCC rename.
      # (bento/cc item positions and analytics blobs deliberately not imported)
      "com.apple.controlcenter" = {
        "RemoteLiveActivitiesEnabled" = 1;
        "NSStatusItem Visible Battery" = 0;
        "NSStatusItem Visible BentoBox" = 1;
        "NSStatusItem Visible Shortcuts" = 0;
        "NSStatusItem VisibleCC Clock" = 1;
        "NSStatusItem VisibleCC FocusModes" = 1;
        "NSStatusItem VisibleCC NowPlaying" = 1;
        "NSStatusItem VisibleCC Sound" = 1;
        "NSStatusItem VisibleCC WiFi" = 1;
      };

      # --- round-2 promotions from the report (deliberate prefs) -----
      "com.apple.WindowManager" = {
        GloballyEnabled = 0;
        EnableTiledWindowMargins = 0;
        EnableTilingByEdgeDrag = 0;
        EnableTopTilingByEdgeDrag = 0;
        EnableTilingOptionAccelerator = 0;
        AppWindowGroupingBehavior = 1;
        AutoHide = 0;
        HideDesktop = 1;
        StageManagerHideWidgets = 0;
        StandardHideWidgets = 0;
        EnableStageManagerStrip = 0;
      };
      "com.apple.dt.Xcode" = {
        DVTTextShowMinimap = 1;
        DVTTextEnablePredictiveCompletion = 1;
      };
      "com.apple.Safari" = {
        ShowDevelopMenu = 1;
        EnableNarrowTabs = 1;
        AllowJavaScriptFromAppleEvents = 1;
      };
      "com.apple.Preview" = {
        "com.apple.AnnotationKit.arrowHeadStyle" = 2;
        "com.apple.AnnotationKit.strokeWidth" = 5.0;
        "com.apple.AnnotationKit.strokeIsDashed" = 0;
        "com.apple.AnnotationKit.hasShadow" = 0;
      };
      "com.apple.screencapture" = {
        style = "selection";
        video = 1;
      };
      "com.apple.pipagent" = {
        Corner = 1;
        Size = "{0.25, 0.21754700089525514}";
      };
      "com.apple.messages.nicknames" = {
        MeCardSharingAudience = 2;
        MeCardSharingEnabled = 1;
      };
      "com.apple.onetimepasscodes" = { DeleteVerificationCodes = 1; };
      "com.apple.Passwords" = { PMSortOption = 2; showMenuBarExtra = 0; };
      "com.apple.DeskCam" = {
        DCAUserDefaultsAlwaysShowSetup = 1;
        DCAUserDefaultsAutoZoomOnLaunch = 1;
      };
      "com.apple.speech.recognition.AppleSpeechRecognition.prefs" = {
        DictationIMUseOnlyOfflineDictation = 0;
      };
      "com.apple.SpeechRecognitionCore" = { AllowAudioDucking = 0; };
      "com.apple.TextInputMenu" = { visible = 1; };
      "com.apple.CharacterPaletteIM" = { CVStartAsLargeWindow = 0; };
      "com.apple.widgets" = { ShowAddSheetOnboardingBanner = 0; };
      "com.apple.FontBook" = {
        showComputerFonts = 0;
        showUserFonts = 1;
        sidebarMinWidth = 150;
      };
      "com.apple.photos.shareddefaults" = {
        IPXDefaultViewFullHDR = 1;
        IPXDefaultEnhancedVisualSearchEnabled = 1;
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
    # import on a machine (diff fresh `brew bundle dump` output vs
    # the host's declared lists), opt in per-host with "zap" so drift self-cleans.
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
