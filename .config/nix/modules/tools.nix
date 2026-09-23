# single manifest of user-facing CLI tools.
#
# darwin → brew column (declared via homebrew.brews; nix handles apps/casks)
# linux  → nix column (home-manager home.packages)
#
# entries where the names coincide still get spelled out twice on purpose —
# the columns are the contract. name mismatches (delta, kubectl…) live here
# and nowhere else.
#
# NOT here: darwin system plumbing that must come from nixpkgs because a
# module references its store path (mkalias, zsh plugins, pure-prompt,
# sqlite for LIBSQLITE) — that stays in modules/darwin/common.nix.

[
  { brew = "neovim"; nix = "neovim"; }
  { brew = "fzf"; nix = "fzf"; }
  { brew = "ripgrep"; nix = "ripgrep"; }
  { brew = "fd"; nix = "fd"; }
  { brew = "zoxide"; nix = "zoxide"; }
  { brew = "jq"; nix = "jq"; }
  { brew = "yq"; nix = "yq"; }
  { brew = "gh"; nix = "gh"; }
  { brew = "git"; nix = "git"; }
  { brew = "git-delta"; nix = "delta"; }
  { brew = "lazygit"; nix = "lazygit"; }
  { brew = "tmux"; nix = "tmux"; }
  { brew = "just"; nix = "just"; }
  { brew = "btop"; nix = "btop"; }
  { brew = "eza"; nix = "eza"; }
  { brew = "mosh"; nix = "mosh"; }
  { brew = "yadm"; nix = "yadm"; } # TODO: remove once the yadm port completes
  { brew = "kubernetes-cli"; nix = "kubectl"; }
  { brew = "sqlfluff"; nix = "sqlfluff"; }
  { brew = "watch"; nix = "watch"; }
  { brew = "wget"; nix = "wget"; }
]
