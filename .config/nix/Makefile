.PHONY: default apply extensions
default: apply extensions

.PHONY: apply
apply:
	@darwin-rebuild switch --flake ~/.config/nix

.PHONY: extensions
extensions:
	@sh vscode/install-extensions.sh