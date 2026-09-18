FLAKE ?= ~/.config/nix

# fallback `nix run` covers first bootstraps where the CLI isn't installed yet

HOST ?= work

.PHONY: work personal mini pc devspace extensions plan

# dry-run: builds the darwin generation WITHOUT activating, then reports
# homebrew drift both directions. nothing changes on the machine.
# iterate until 'remove' is empty before switching a host to zap.
plan:
	@darwin-rebuild build --flake $(FLAKE)#$(HOST) -o /tmp/nix-plan-$(HOST) && echo "build ok (eval+build only, nothing activated)"
	@nix eval --json --apply 'x: map (b: if builtins.isAttrs b then b.name else b) x' \
	  '$(FLAKE)#darwinConfigurations.$(HOST).config.homebrew.brews' | jq -r '.[]' | sed 's|.*/||' | sort -u > /tmp/plan-decl-brews
	@nix eval --json '$(FLAKE)#darwinConfigurations.$(HOST).config.homebrew.casks' | jq -r '.[]' | sed 's|.*/||' | sort -u > /tmp/plan-decl-casks
	@brew leaves | sort -u > /tmp/plan-inst-brews
	@brew list --cask | sort -u > /tmp/plan-inst-casks
	@echo; echo '== will be INSTALLED (declared, missing) =='
	@comm -23 /tmp/plan-decl-brews /tmp/plan-inst-brews; comm -23 /tmp/plan-decl-casks /tmp/plan-inst-casks
	@echo '== would be REMOVED by zap (installed, undeclared) =='
	@comm -13 /tmp/plan-decl-brews /tmp/plan-inst-brews; comm -13 /tmp/plan-decl-casks /tmp/plan-inst-casks
	@echo '== ok: present and declared =='
	@comm -12 /tmp/plan-decl-brews /tmp/plan-inst-brews | wc -l | tr -d ' '; comm -12 /tmp/plan-decl-casks /tmp/plan-inst-casks | wc -l | tr -d ' '

work personal mini:
	darwin-rebuild switch --flake $(FLAKE)#$@ || nix run nix-darwin -- switch --flake $(FLAKE)#$@
	# @$(MAKE) extensions   # disabled for now — vscode manages extensions itself

pc devspace:
	home-manager switch --flake $(FLAKE)#$@ || nix run home-manager -- switch --flake $(FLAKE)#$@

# not wired into the mac targets for now; run manually if wanted
extensions:
	@sh vscode/install-extensions.sh
