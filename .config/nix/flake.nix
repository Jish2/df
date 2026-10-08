{
  description = "josh's fleet — one flake, five machines (see FLEET.md)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";

    # herdr on linux boxes comes from the herdrdev flake (pinned release
    # tag), not nixpkgs: nixpkgs-unstable's herdr lags releases, and pc's
    # CLI + server must come from the same closure (version skew between
    # a profile CLI and a flake server is exactly what this removes).
    # darwin keeps brew (floats fresh) — see hosts/work brews + FLEET.md.
    herdr.url = "github:herdrdev/herdr/v0.9.3";
    herdr.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      nix-homebrew,
      ...
    }:
    let
      defaultUser = "jgoon";

      # explicit-zap host variant: identical config, but the brew bundle run
      # during activation also removes undeclared formulae/casks
      # (--zap --force-cleanup). `make <host>-zap` opts in for one switch;
      # plain `make <host>` never removes anything.
      zapModule =
        { lib, ... }:
        { homebrew.onActivation.cleanup = lib.mkForce "zap"; };

      # macs: nix-darwin + home-manager (HM as a darwin module, so one
      # `darwin-rebuild` rebuilds system and user together)
      mkDarwin =
        host: extraModules:
        nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit inputs self;
            user = defaultUser;
          };
          modules = [
            ./modules/darwin/common.nix
            ./modules/darwin/tailscaled.nix
            ./modules/darwin/fleet-herdr.nix
            ./modules/darwin/fleet-keepawake.nix
            ./hosts/${host}
            home-manager.darwinModules.home-manager
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                enableRosetta = true;
                user = defaultUser;
                autoMigrate = true; # adopt the existing /opt/homebrew install
              };

              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.extraSpecialArgs = {
                user = defaultUser;
                selfAttr = host;
              };
              home-manager.users.${defaultUser}.imports = [
                ./modules/home/common.nix
                ./modules/home/darwin.nix
              ];
            }
          ] ++ extraModules;
        };

      mkHome =
        { host, system, user }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = {
            inherit inputs;
            user = user;
            selfAttr = host;
            hostKind = "standalone";
          };
          modules = [
            ./modules/home/common.nix
            ./modules/home/linux.nix
            ./hosts/${host}
            # backupFileExtension is darwin-integration-only; standalone
            # HM takes -b bak on the CLI (make devspace)
          ];
        };

      mkNixos =
        host:
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs self;
            user = defaultUser;
          };
          modules = [
            ./hosts/${host}/configuration.nix
            ./hosts/${host}/hardware-configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.extraSpecialArgs = {
                inherit inputs; # hosts/<linux-nixos>/default.nix builds herdr from inputs.herdr
                user = defaultUser;
                selfAttr = host;
                hostKind = "nixos";
              };
              home-manager.users.${defaultUser}.imports = [
                ./modules/home/common.nix
                ./modules/home/linux.nix
                ./hosts/${host}              ];
            }
          ];
        };
    in
    {
      darwinConfigurations = {
        work = mkDarwin "work" [ ]; # MBP M4 Max
        work-zap = mkDarwin "work" [ zapModule ];
        personal = mkDarwin "personal" [ ]; # MBP M3 Pro
        personal-zap = mkDarwin "personal" [ zapModule ];
        mini = mkDarwin "mini" [ ]; # M1 Mac Mini, always on
        mini-zap = mkDarwin "mini" [ zapModule ];
      };

      nixosConfigurations.pc = mkNixos "pc";

      homeConfigurations = {
        # pc's user env rides nixosConfigurations.pc (HM as a NixOS module);
        # devspace's attr runs on the Coder VM as user `coder` (hostname
        # jgoon-jgoon-box, stable EBS home, ephemeral root — re-applied per
        # rebuild by the box-side bootstrap in scripts/devspace-apply.sh)
        devspace = mkHome { host = "devspace"; system = "x86_64-linux"; user = "coder"; };
      };
    };
}
