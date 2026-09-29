FLAKE ?= $(HOME)/.config/nix

# fallback `nix run` covers first bootstraps where darwin-rebuild isn't on
# PATH yet. NIX resolves robustly: a first bootstrap can run right after
# /etc/zshrc was renamed aside for nix-darwin's /etc guard (the nix
# installer's PATH snippet lives in that file), which drops nix from new
# shells — so fall back to the multi-user daemon profile's absolute path.
NIX := $(shell command -v nix 2>/dev/null || echo /nix/var/nix/profiles/default/bin/nix)

# infer the flake attr from this machine's name so `make here`, `make here-zap`,
# and plain `make plan` work on any machine in the fleet. macs use
# LocalHostName; the linux fallback is the short hostname. add new hosts to
# this map as they land (personal is TODO until its hostname is known).
MACHINE := $(shell scutil --get LocalHostName 2>/dev/null || hostname -s)
ifeq ($(MACHINE),HQ-KP2HJMHQ7R)
  INFERRED := work
else ifeq ($(MACHINE),Joshuas-Mac-mini)
  INFERRED := mini
else
  INFERRED := unknown
endif

HOST ?= $(INFERRED)

.PHONY: work personal mini work-zap personal-zap mini-zap pc devspace extensions plan here here-zap hs-mint hs-nodes

# dry-run: builds the darwin generation WITHOUT activating, then reports
# homebrew drift both directions. nothing changes on the machine.
# iterate until 'remove' is empty before switching a host to zap.
plan:
	@darwin-rebuild build --flake $(FLAKE)#$(HOST) || \
	  $(NIX) run $(NIXFLAGS) nix-darwin -- build --flake $(FLAKE)#$(HOST)
	@echo "build ok (eval+build only, nothing activated)"
	@nix eval --extra-experimental-features 'nix-command flakes' --json --apply 'x: map (b: if builtins.isAttrs b then b.name else b) x' \
	  '$(FLAKE)#darwinConfigurations.$(HOST).config.homebrew.brews' | jq -r '.[]' | sed 's|.*/||' | sort -u > /tmp/plan-decl-brews
	@nix eval --extra-experimental-features 'nix-command flakes' --json --apply 'x: map (b: if builtins.isAttrs b then b.name else b) x' \
	  '$(FLAKE)#darwinConfigurations.$(HOST).config.homebrew.casks' | jq -r '.[]' | sed 's|.*/||' | sort -u > /tmp/plan-decl-casks
	@brew list --formula | sed 's|.*/||' | sort -u > /tmp/plan-inst-brews
	@brew leaves | sed 's|.*/||' | sort -u > /tmp/plan-inst-leaves
	@brew list --cask | sed 's|.*/||' | sort -u > /tmp/plan-inst-casks
	@# install side uses `brew list` (the same check `brew bundle` makes — a
	@# formula present as a dependency is not "missing"); the remove side uses
	@# leaves, because zap only takes top-level formulae. modern brew's `leaves`
	@# also lists casks, so strip the cask set out of it first.
	@comm -23 /tmp/plan-inst-leaves /tmp/plan-inst-casks > /tmp/plan-inst-leaf-brews
	@echo; echo '== will be INSTALLED (declared, missing) =='
	@comm -23 /tmp/plan-decl-brews /tmp/plan-inst-brews; comm -23 /tmp/plan-decl-casks /tmp/plan-inst-casks
	@echo '== would be REMOVED by zap (installed, undeclared) =='
	@comm -13 /tmp/plan-decl-brews /tmp/plan-inst-leaf-brews; comm -13 /tmp/plan-decl-casks /tmp/plan-inst-casks
	@echo '== ok: present and declared =='
	@comm -12 /tmp/plan-decl-brews /tmp/plan-inst-brews | wc -l | tr -d ' '; comm -12 /tmp/plan-decl-casks /tmp/plan-inst-casks | wc -l | tr -d ' '

NIXFLAGS = --extra-experimental-features 'nix-command flakes'

# plain targets install only. `-zap` variants switch the same host with
# homebrew.onActivation.cleanup = "zap" for one explicit cleanup activation —
# run the plain target afterwards to be back on the non-cleaning generation.
work personal mini work-zap personal-zap mini-zap:
	sudo darwin-rebuild switch --flake $(FLAKE)#$@ || sudo $(NIX) run $(NIXFLAGS) nix-darwin -- switch --flake $(FLAKE)#$@
	# @$(MAKE) extensions   # disabled for now — vscode manages extensions itself

pc devspace:
	home-manager switch --flake $(FLAKE)#$@ || nix run $(NIXFLAGS) home-manager -- switch --flake $(FLAKE)#$@

# not wired into the mac targets for now; run manually if wanted
extensions:
	@sh vscode/install-extensions.sh

# Mint a reusable (365d) headscale pre-auth key via SSM on the control
# plane instance and write it to the local gitignored key file. Run this
# once per machine you're onboarding (or once when the key expires).
# Requires: aws cli with the dev-admin profile.
HS_INSTANCE := i-04013ad3adc217213
HS_REGION := us-west-1
HS_USER_ID := 1

hs-mint:
	@if [ ! -d "$(FLAKE)/secrets" ]; then mkdir -m 700 -p "$(FLAKE)/secrets"; fi
	@CID=$$(aws ssm send-command --profile dev-admin --region $(HS_REGION) \
	  --instance-ids $(HS_INSTANCE) \
	  --document-name "AWS-RunShellScript" \
	  --comment "mint fleet join key" \
	  --parameters 'commands=["docker exec headscale headscale preauthkeys create -u $(HS_USER_ID) --reusable --expiration 365d"]' \
	  --output text --query "Command.CommandId"); \
	sleep 6; \
	KEY=$$(aws ssm get-command-invocation --profile dev-admin --region $(HS_REGION) \
	  --command-id "$$CID" --instance-id $(HS_INSTANCE) \
	  --query StandardOutputContent --output text | tail -1); \
	if [ -z "$$KEY" ]; then echo "no key returned — check AWS profile/permissions"; exit 1; fi; \
	printf '%s\n' "$$KEY" > "$(FLAKE)/secrets/tailscale-authkey"; \
	chmod 600 "$(FLAKE)/secrets/tailscale-authkey"; \
	echo "key written to $(FLAKE)/secrets/tailscale-authkey (gitignored, 365d, reusable)"; \
	echo "re-run 'make here' to join this machine"

# Standing of the tailnet: nodes registered on the control plane
hs-nodes:
	@CID=$$(aws ssm send-command --profile dev-admin --region $(HS_REGION) \
	  --instance-ids $(HS_INSTANCE) \
	  --document-name "AWS-RunShellScript" \
	  --comment "list headscale nodes" \
	  --parameters 'commands=["docker exec headscale headscale nodes list"]' \
	  --output text --query "Command.CommandId"); \
	sleep 6; \
	aws ssm get-command-invocation --profile dev-admin --region $(HS_REGION) \
	  --command-id "$$CID" --instance-id $(HS_INSTANCE) \
	  --query StandardOutputContent --output text

# switch whatever machine you're on — the host map above picks the attr
here:
	@if [ "$(INFERRED)" = unknown ]; then \
	  echo "machine '$(MACHINE)' has no flake attr mapped — add it to the host map in this Makefile"; exit 1; \
	fi
	$(MAKE) $(INFERRED)

here-zap:
	@if [ "$(INFERRED)" = unknown ]; then \
	  echo "machine '$(MACHINE)' has no flake attr mapped — add it to the host map in this Makefile"; exit 1; \
	fi
	$(MAKE) $(INFERRED)-zap
