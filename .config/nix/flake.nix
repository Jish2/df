{
  description = "Example nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      nix-homebrew,
    }:
    let
      configuration =
        { pkgs, config, ... }:
        {
          # for smart open in neovim
          environment.variables = {
            LIBSQLITE = "${pkgs.sqlite.out}/lib/libsqlite3.dylib";
          };

          nixpkgs.config.allowUnfree = true;

          # List packages installed in system profile. To search by name, run:
          # $ nix-env -qaP | grep wget
          environment.systemPackages = with pkgs; [
            neovim
            vim
            nixfmt-rfc-style
            defaultbrowser
            yarn
            gh
            pyenv
            iterm2
            yadm
            zsh-syntax-highlighting
            zsh-autosuggestions
            zoxide
            pure-prompt
            mkalias
            rectangle
            # vscode
            postman
            hidden-bar
            sqlfluff
            # ghostty # we install this with cask for now...
            ripgrep
            delta
          ];

          fonts.packages = with pkgs; [
            nerd-fonts.jetbrains-mono
          ];

          # Necessary for using flakes on this system.
          nix.settings.experimental-features = "nix-command flakes";

          # Enable alternative shell support in nix-darwin.
          # programs.fish.enable = true;

          # Set Git commit hash for darwin-version.
          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Used for backwards compatibility, please read the changelog before changing.
          # $ darwin-rebuild changelog
          system.stateVersion = 5;

          system.defaults = {
            dock = {
              autohide = false;
              tilesize = 40;
              show-recents = false;
            };

            # max speed key repeat
            # NSGlobalDomain.KeyRepeat = 15;
            # NSGlobalDomain.InitialKeyRepeat = 2;

            CustomUserPreferences = {
              "com.apple.symbolichotkeys" = {
                AppleSymbolicHotKeys = {
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

                  # Cmd+Shift+3
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
                  # Ctrl+Cmd+Shift+3
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
                  # Cmd+Shift+4
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
                  # Ctrl+Cmd+Shift+4
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
            brews = [
              "nvm"
              "openssl@3"
              "pango" # for dimensional team
            ];
            casks = [
              "docker"
              "datagrip"
              "alfred"
              "aldente"
              "karabiner-elements"
              "shottr"
              "ghostty"
              "obsidian"
              "visual-studio-code"
              "alt-tab"
              "mactex"
            ];
            onActivation.cleanup = "zap";
          };

          programs.zsh = {
            enable = true;
            enableSyntaxHighlighting = true;

            # effective .zshrc
            shellInit = ''
              source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
            '';
          };

          # use touch id instead of entering password when calling sudo
          security.pam.services.sudo_local.touchIdAuth = true;

          # The platform the configuration will be used on.
          nixpkgs.hostPlatform = "aarch64-darwin";

          # Activation script
          system.activationScripts.postActivation.text = ''
            # set the default browser
            defaultbrowser chrome
          '';

          # fix spotlight indexing
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
              # mkdir -p /Applications/Nix\ Apps
              find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
              while read -r src; do
                app_name=$(basename "$src")
                echo "copying $src" >&2
                ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/$app_name"
              done
            '';
        };
    in
    {
      # Build darwin flake using:
      # $ darwin-rebuild build --flake .#LUSH5G9XY3GHR
      darwinConfigurations."LUSH5G9XY3GHR" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = true;
              user = "jgoon";
              autoMigrate = true;
            };
          }
        ];
      };
    };
}
