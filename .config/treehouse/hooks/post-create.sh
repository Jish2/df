#!/usr/bin/env bash
# Treehouse post_create hook: warm package installs when a worktree is new/empty.
# Opt-in: uncomment in ~/.config/treehouse/config.toml (repo treehouse.toml hooks
# are ignored). Runs with cwd set to the acquired worktree.
#
#   [hooks]
#   post_create = ["bash \"$HOME/.config/treehouse/hooks/post-create.sh\""]
#
set -euo pipefail

if [[ -f package-lock.json && -f package.json && ! -d node_modules ]]; then
  echo "🌳 post_create: npm install (node_modules missing)" >&2
  npm install
  exit 0
fi

if [[ -f pnpm-lock.yaml && -f package.json && ! -d node_modules ]]; then
  echo "🌳 post_create: pnpm install (node_modules missing)" >&2
  pnpm install
  exit 0
fi

if [[ -f yarn.lock && -f package.json && ! -d node_modules ]]; then
  echo "🌳 post_create: yarn install (node_modules missing)" >&2
  yarn install
  exit 0
fi

if [[ -f requirements.txt && ! -d .venv && ! -d venv ]]; then
  echo "🌳 post_create: python venv + pip install (venv missing)" >&2
  python3 -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install -r requirements.txt
  exit 0
fi

echo "🌳 post_create: nothing to warm" >&2
