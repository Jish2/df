# brew
if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
fi

# nvm
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
elif [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
  . "/opt/homebrew/opt/nvm/nvm.sh"
fi
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && . "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
# Clear stale rehash temp file that can block startup for ~60s if a previous
# `pyenv rehash` was killed mid-write.
[ -e "$PYENV_ROOT/shims/.pyenv-shim" ] && rm -f "$PYENV_ROOT/shims/.pyenv-shim"
# `--path` only sets PATH (fast, login-shell only). The interactive shell
# function setup is done in .zshrc with `pyenv init -`.
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init --path)"
fi

# go
if command -v go >/dev/null 2>&1; then
  PATH="${PATH}:$(go env GOPATH)/bin"
fi

# ruby gems
export PATH="/opt/homebrew/lib/ruby/gems/3.3.0/bin:$PATH"

# console ninja
PATH=~/.console-ninja/.bin:$PATH

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
