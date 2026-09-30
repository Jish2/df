FLAKE ?= $(HOME)/.config/nix

# fallback `nix run` covers first bootstraps where darwin-rebuild isn't on
# PATH yet. NIX resolves robustly: a first bootstrap can run right after
# /etc/zshrc was renamed aside for nix-darwin's /etc guard (the nix
# installer's PATH snippet lives in that file), which drops nix from new
# shells — so fall back to the multi-user daemon profile's absolute path.
NIX := $(shell command -v nix 2>/dev/null || echo /nix/var/nix/profiles/default/bin/nix)

# hostmap: this machine's name -> its flake attr. add hosts here as they
# land (personal until its hostname is known). this is the ONLY place
# host identity is mapped: `make here` dispatches from it, so a machine
# can only ever build its own config.
MACHINE := $(shell scutil --get LocalHostName 2>/dev/null || hostname -s)
ifeq ($(MACHINE),HQ-KP2HJMHQ7R)
  INFERRED := work
else ifeq ($(MACHINE),Joshuas-Mac-mini)
  INFERRED := mini
else
  INFERRED := unknown
endif

# linux hosts use standalone home-manager instead of darwin-rebuild
LINUX_HOSTS = pc devspace

HOST ?= $(INFERRED)
NIXFLAGS = --extra-experimental-features 'nix-command flakes'

.PHONY: plan here here-zap doctor extensions

# dry-run: builds the darwin generation WITHOUT activating, then reports
# homebrew drift both directions. nothing changes on the machine.
# iterate until 'would be REMOVED' is empty before running here-zap.
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

# switch THIS machine to its own config, inferred from its hostname.
#
# there are deliberately no per-host switch targets (`make work` etc.):
# they applied a named host's config to whatever machine ran the command —
# `make work` while ssh'd into mini rewires mini with work's hostname,
# brew lists, and defaults. `make here` reads this machine's actual
# LocalHostName, so cross-applying is impossible by construction.
here:
	@if [ "$(INFERRED)" = unknown ]; then \
	  echo "machine '$(MACHINE)' has no flake attr mapped — add it to the host map in this Makefile"; exit 1; \
	fi
	@if echo ' $(LINUX_HOSTS) ' | grep -q ' $(INFERRED) '; then \
	  home-manager switch -b bak --flake $(FLAKE)#$(INFERRED) || $(NIX) run $(NIXFLAGS) home-manager -- switch -b bak --flake $(FLAKE)#$(INFERRED); \
	else \
	  sudo darwin-rebuild switch --flake $(FLAKE)#$(INFERRED) || sudo $(NIX) run $(NIXFLAGS) nix-darwin -- switch --flake $(FLAKE)#$(INFERRED); \
	fi

# one explicit self-cleaning switch: same host config, but homebrew
# cleanup = "zap" for this activation only (the -zap flake attr). run
# `make plan` first — if anything ssh depends on (tailscale, cloudflared)
# shows under 'would be REMOVED', declare it in the host module BEFORE
# zapping, or the network path to this machine goes with it. see the
# fleet-ssh-safety skill / FLEET.md.
here-zap:
	@if [ "$(INFERRED)" = unknown ]; then \
	  echo "machine '$(MACHINE)' has no flake attr mapped — add it to the host map in this Makefile"; exit 1; \
	fi
	@if echo ' $(LINUX_HOSTS) ' | grep -q ' $(INFERRED) '; then \
	  echo "linux hosts have no zap variant (no brew)"; exit 1; \
	fi
	sudo darwin-rebuild switch --flake $(FLAKE)#$(INFERRED)-zap || sudo $(NIX) run $(NIXFLAGS) nix-darwin -- switch --flake $(FLAKE)#$(INFERRED)-zap

# verify the SSH-critical invariants. run before and after any switch,
# and from a fresh ssh session after switching a remote machine. zero
# sudo by design — it has to run over plain ssh without a TTY.
#
# what's load-bearing per machine:
#   mini — the always-on remote box: the nix launchd daemon
#          (org.jgoon.tailscaled, from fleet.tailscaled.enable in
#          hosts/mini) + sshd + shell init files.
#   work — App Store tailscale (Falcon SIGKILLs the nix daemon), so only
#          the shell/sshd checks apply.
doctor:
	@echo "== hostname =="
	@echo "attr: $(INFERRED)   LocalHostName: $(MACHINE)"
	@if [ "$(INFERRED)" = unknown ]; then \
	  echo "!! no flake attr mapped for this machine — add it to the host map (or you're on an unmapped box)"; \
	fi
	@echo "== tailscaled (the network path to remote machines) =="
	@if [ "$(INFERRED)" = mini ]; then \
	  if pgrep -x tailscaled >/dev/null 2>&1; then \
	    echo "ok: tailscaled is running"; \
	  else \
	    echo "!! tailscaled is not running — mini is unreachable over the network"; \
	  fi; \
	  if [ -f /Library/LaunchDaemons/org.jgoon.tailscaled.plist ]; then \
	    echo "ok: nix-managed tailscaled daemon plist present (org.jgoon.tailscaled)"; \
	  else \
	    echo "!! /Library/LaunchDaemons/org.jgoon.tailscaled.plist missing — the nix daemon hasn't landed yet; mini is on the legacy /Library/LaunchDaemons/com.tailscale.tailscaled.plist until the next `make here`"; \
	  fi; \
	  if grep -q 'fleet.tailscaled.enable = true' $(FLAKE)/hosts/mini/default.nix; then \
	    echo "ok: fleet.tailscaled.enable = true in hosts/mini/default.nix"; \
	  else \
	    echo "!! fleet.tailscaled.enable is not true in hosts/mini — the daemon (and mini's network path) is undeclared"; \
	  fi; \
	  if test -S /var/run/tailscaled.socket; then \
	    echo "ok: tailscaled socket present"; \
	  else \
	    echo "!! /var/run/tailscaled.socket missing — tailscale CLI can't reach the daemon"; \
	  fi; \
	else \
	  echo "n/a on this host: the nix tailscaled daemon runs on mini only (work uses the App Store variant — Falcon kills the nix one)"; \
	fi
	@echo "== sshd (Remote Login) =="
	@if nc -z 127.0.0.1 22 2>/dev/null; then \
	  echo "ok: listening on :22"; \
	else \
	  echo "!! nothing listening on :22 — Remote Login is off (only load-bearing on machines reached over ssh, e.g. mini)"; \
	fi
	@echo "== shell init files (every new ssh session parses these) =="
	@for f in /etc/zshenv /etc/zshrc /etc/zprofile; do \
	  if [ -f $$f ]; then \
	    if zsh -n $$f 2>/dev/null; then echo "ok: $$f parses"; else echo "!! $$f has a syntax error — every new ssh session dies"; fi; \
	  fi; \
	done
	@echo "== ssh config (fleet aliases) =="
	@if [ -f ~/.ssh/hosts-generated.conf ]; then \
	  hosts=$$(grep -c '^Host ' ~/.ssh/hosts-generated.conf 2>/dev/null); \
	  if [ "$$hosts" -gt 0 ]; then \
	    echo "ok: fleet ssh aliases present ($$hosts peers, self excluded)"; \
	  else \
	    echo "!! ~/.ssh/hosts-generated.conf exists but has no Host blocks — run make here to regenerate"; \
	  fi; \
	else \
	  echo "note: no ~/.ssh/hosts-generated.conf yet (run make here to generate)"; \
	fi
	@echo "== disk =="
	@df -h / | tail -1 | awk '{print "root: " $$5 " used, " $$4 " available"}'
	@free=$$(df -k / | tail -1 | awk '{print $$4}'); \
	if [ "$$free" -lt 10485760 ]; then \
	  echo "!! under 10GB free on / — a switch can fill the disk and abort mid-activation"; \
	else \
	  echo "ok: over 10GB free on /"; \
	fi
	@echo "== doctor done =="

# not wired into the mac targets for now; run manually if wanted
extensions:
	@sh vscode/install-extensions.sh
