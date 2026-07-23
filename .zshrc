# This file is zsh-specific; no-op when sourced from other shells (e.g. bash).
[ -n "${ZSH_VERSION-}" ] || return 0 2>/dev/null || exit 0

autoload -Uz compinit
compinit
# some configs are replicated in ~/.config/nix/flake.nix

# Lightweight helpers for loading optional config/plugins across platforms.
source_if_exists() {
  [ -f "$1" ] && source "$1"
}

source_first_existing() {
  local _candidate
  for _candidate in "$@"; do
    [ -f "$_candidate" ] && source "$_candidate" && return 0
  done
  return 1
}

_brew_prefix=""
if command -v brew >/dev/null 2>&1; then
  _brew_prefix="$(brew --prefix 2>/dev/null)"
fi

# zsh-syntax-highlighting
source_first_existing \
  "${_brew_prefix}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
  "/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
  "/home/linuxbrew/.linuxbrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
  "/usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
  "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# syntax-highlighting-theme
source_if_exists ~/.config/zsh/themes/catppuccin_mocha-zsh-syntax-highlighting.zsh

# zsh-autosuggestions
source_first_existing \
  "${_brew_prefix}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
  "/opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
  "/home/linuxbrew/.linuxbrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
  "/usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
  "/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# aliases
source_if_exists "$HOME/.aliases"

# zoxide
if command -v zoxide >/dev/null 2>&1; then
  # apt zoxide 0.4.3: _z_cd calls cd instead of builtin cd → infinite recursion on zsh
  eval "$(zoxide init zsh --cmd cd | sed 's/^    cd "\$@"/    builtin cd "$@"/')"
fi

# pure zsh prompt
# Pure prompt can live in different local paths across machines.
[ -d "$HOME/github/pure" ] && fpath=("$HOME/github/pure" $fpath)
[ -d "$HOME/.zsh/pure" ] && fpath=("$HOME/.zsh/pure" $fpath)
autoload -U promptinit; promptinit
if whence -w prompt_pure_setup >/dev/null 2>&1; then
  prompt pure
  prompt_newline=$'\u00A0'
fi

# terraform
autoload -U +X bashcompinit && bashcompinit
if command -v terraform >/dev/null 2>&1; then
  complete -o nospace -C "$(command -v terraform)" terraform
fi

# pyenv (interactive shell function setup; PATH is set in .zprofile)
command -v pyenv >/dev/null && eval "$(pyenv init -)"

# nvm (interactive shell function setup; NVM_DIR is set in .zprofile)
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if ! whence -w nvm >/dev/null 2>&1; then
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
fi

# kubectl krew
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# kubectl autocomplete
if command -v kubectl >/dev/null 2>&1; then
  source <(command kubectl completion zsh)
  command -v kubecolor >/dev/null 2>&1 && compdef kubecolor=kubectl
fi

# fzf config
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh 2>/dev/null)"
fi

# persist history to disk on every command, but keep arrow-key recall
# scoped to the current session (see widget override below)
setopt APPEND_HISTORY        # append instead of overwrite on exit
setopt INC_APPEND_HISTORY    # write each command to $HISTFILE immediately
unsetopt SHARE_HISTORY       # don't pull in commands from other live sessions

# retain much more shell history for Ctrl-R
HISTFILE="$HOME/.zsh_history"  # on-disk file where history is persisted
HISTSIZE=100000                # max commands kept in memory (searchable via Ctrl-R)
SAVEHIST=100000                # max commands written to HISTFILE across sessions

# (nice-to-have noise reduction)
setopt HIST_IGNORE_DUPS      # drop exact duplicates
setopt HIST_IGNORE_SPACE     # ignore commands starting with a space
setopt HIST_EXPIRE_DUPS_FIRST  # when trimming history, drop duplicate entries first
setopt HIST_FIND_NO_DUPS       # Ctrl-R skips repeating duplicate matches

# Up/Down arrows only walk this session's history (Ctrl-R still sees everything).
typeset -g __session_hist_start=$HISTCMD
_session-up-line-or-history() {
  (( HISTNO > __session_hist_start )) && zle .up-line-or-history
}
_session-down-line-or-history() {
  zle .down-line-or-history
}
zle -N up-line-or-history _session-up-line-or-history
zle -N down-line-or-history _session-down-line-or-history

# machine/OS-specific config (yadm alternate files)
if [ -f ~/.zshrc.local ]; then
  source ~/.zshrc.local
else
  _zshrc_os="$(uname -s)"
  _zshrc_host="$(hostname -s 2>/dev/null || hostname)"
  _zshrc_local_os="$HOME/.zshrc.local##o.${_zshrc_os}"
  _zshrc_local_variant="$HOME/.zshrc.local##o.${_zshrc_os},h.${_zshrc_host}"
  if [ -f "$_zshrc_local_variant" ]; then
    source "$_zshrc_local_variant"
  elif [ -f "$_zshrc_local_os" ]; then
    source "$_zshrc_local_os"
  fi
  unset _zshrc_os _zshrc_host _zshrc_local_os _zshrc_local_variant
fi

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export PATH="$HOME/.local/bin:$PATH"

# load secrets
[[ -f ~/.zshrc.secrets ]] && source ~/.zshrc.secrets
alias gpt='~/github/scripts/query-chat-gpt-through-codex.sh'

unset _brew_prefix
