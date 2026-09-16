FLAKE ?= ~/.config/nix

# fallback `nix run` covers first bootstraps where the CLI isn't installed yet

.PHONY: work personal mini pc devspace extensions

work personal mini:
	darwin-rebuild switch --flake $(FLAKE)#$@ || nix run nix-darwin -- switch --flake $(FLAKE)#$@
	# @$(MAKE) extensions   # disabled for now — vscode manages extensions itself

pc devspace:
	home-manager switch --flake $(FLAKE)#$@ || nix run home-manager -- switch --flake $(FLAKE)#$@

# not wired into the mac targets for now; run manually if wanted
extensions:
	@sh vscode/install-extensions.sh
