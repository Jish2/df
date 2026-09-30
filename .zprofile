# brew (darwin; nix-darwin boxes also get brew via nix-homebrew — both live in /opt/homebrew)
command -v /opt/homebrew/bin/brew >/dev/null 2>&1 && eval "$(/opt/homebrew/bin/brew shellenv)"

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

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
