{
  description = "josh's fleet — one flake, five machines (see FLEET.md)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
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

      # macs: nix-darwin + home-manager (HM as a darwin module, so one
      # `darwin-rebuild` rebuilds system and user together)
      mkDarwin =
        host:
        nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit inputs self;
            user = defaultUser;
          };
          modules = [
            ./modules/darwin/common.nix
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
              home-manager.extraSpecialArgs = { user = defaultUser; };
              home-manager.users.${defaultUser}.imports = [
                ./modules/home/common.nix
                ./modules/home/darwin.nix
              ];
            }
          ];
        };

      # linux: standalone home-manager (pc stays Omarchy; devspace is ephemeral)
      mkHome =
        { host, system }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = {
            inherit inputs;
            user = defaultUser;
          };
          modules = [
            ./modules/home/common.nix
            ./modules/home/linux.nix
            ./hosts/${host}
            { home-manager.backupFileExtension = "bak"; }
          ];
        };
    in
    {
      darwinConfigurations = {
        work = mkDarwin "work"; # MBP M4 Max
        personal = mkDarwin "personal"; # MBP M3 Pro
        mini = mkDarwin "mini"; # M1 Mac Mini, always on
      };

      homeConfigurations = {
        pc = mkHome { host = "pc"; system = "x86_64-linux"; };
        # TODO: confirm devspace arch (`uname -m` on the vm)
        devspace = mkHome { host = "devspace"; system = "x86_64-linux"; };
      };
    };
}
