## setup log

1. install nix
   `$ sh <(curl -L https://nixos.org/nix/install)`

2. create a flake
   `$ nix flake init -t nix-darwin/master`

3. update flake hostname
   `$ sed -i '' "s/simple/$(scutil --get LocalHostName)/" flake.nix`

4. install nix-darwin
   `$ nix run --extra-experimental-features 'nix-command flakes' nix-darwin -- switch --flake ~/.config/nix`

### updating nix

   `$ nix flake update`

### installing home-manager [^1]

### vscode syncing

1. `settings.json` and `keybindings.json` managed through yadm.
2. extensions managed through `Brewfile.vscode`
3. extension installation managed through `flake.nix`
4. disabled extensions managed through `flake.nix` sqlite injection script.

[^1]: <https://nix-community.github.io/home-manager/#sec-install-nix-darwin-module>
