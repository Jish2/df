# brew (darwin; nix-darwin boxes also get brew via nix-homebrew — both live in /opt/homebrew)
command -v /opt/homebrew/bin/brew >/dev/null 2>&1 && eval "$(/opt/homebrew/bin/brew shellenv)"

# nvm: lazy-loaded. nvm isn't installed right now (node comes from volta /
# vite-plus), so the old unconditional source attempt was two dead `-s` tests
# every shell. Defining the function costs nothing at startup, and if nvm comes
# back it wires itself up on first use. Startup cost matters: T3 Code only
# gives login shells 5s to report PATH before falling back to a stripped one.
# Note: with pure lazy loading, `nvm use` (not sourcing) puts node on PATH, so
# run `nvm use default` per shell or add it where a default node is wanted.
export NVM_DIR="$HOME/.nvm"
nvm() {
  local nvm_sh
  for nvm_sh in "$NVM_DIR/nvm.sh" "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/nvm.sh" /usr/local/opt/nvm/nvm.sh; do
    [ -s "$nvm_sh" ] && break
  done
  if [ ! -s "$nvm_sh" ]; then
    echo "nvm is not installed (brew install nvm); node comes from volta/vite-plus." >&2
    return 127
  fi
  unset -f nvm
  . "$nvm_sh"
  [ -s "${nvm_sh%/*}/etc/bash_completion.d/nvm" ] && . "${nvm_sh%/*}/etc/bash_completion.d/nvm"
  nvm "$@"
}

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
# Clear stale rehash temp file that can block startup for ~60s if a previous
# `pyenv rehash` was killed mid-write.
[ -e "$PYENV_ROOT/shims/.pyenv-shim" ] && rm -f "$PYENV_ROOT/shims/.pyenv-shim"
# `--path` only sets PATH (fast, login-shell only). The interactive shell
# function setup is done in .zshrc with `pyenv init -`.
command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init --path)"

# go
command -v go >/dev/null 2>&1 && PATH=${PATH}:`go env GOPATH`/bin

# ruby gems (darwin)
command -v /opt/homebrew/opt/ruby >/dev/null 2>&1 && export PATH="/opt/homebrew/lib/ruby/gems/3.3.0/bin:$PATH"

# console ninja
[ -d "$HOME/.console-ninja/.bin" ] && PATH="$HOME/.console-ninja/.bin:$PATH"

# fc command
FCEDIT=nvim

# pnpm
export PNPM_HOME="/Users/jgoon/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

export PATH=/opt/rbx/infosec/safe-git-push:$PATH
