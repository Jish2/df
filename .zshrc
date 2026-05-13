autoload -Uz compinit
compinit
# some configs are replicated in ~/.config/nix/flake.nix

# zsh-syntax-highlighting
if command -v brew >/dev/null 2>&1; then
  _zsh_syntax="$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  [ -f "$_zsh_syntax" ] && source "$_zsh_syntax"
  unset _zsh_syntax
fi

# syntax-highlighting-theme
[ -f ~/.config/zsh/themes/catppuccin_mocha-zsh-syntax-highlighting.zsh ] && source ~/.config/zsh/themes/catppuccin_mocha-zsh-syntax-highlighting.zsh

# zsh-autosuggestions
if command -v brew >/dev/null 2>&1; then
  _zsh_autosuggest="$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  [ -f "$_zsh_autosuggest" ] && source "$_zsh_autosuggest"
  unset _zsh_autosuggest
fi

# aliases
[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"

# zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh --cmd cd)"
fi

# pure zsh prompt
# fpath+=("$(brew --prefix)/share/zsh/site-functions")
autoload -U promptinit; promptinit
if prompt -l | grep -qx pure; then
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

# volta
export PATH="/Users/jgoon/.volta/bin:$PATH"

# kubectl krew
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# kubectl autocomplete
if [ -n "$(whence -p kubectl)" ]; then
  source <(command kubectl completion zsh)
  command -v kubecolor >/dev/null 2>&1 && compdef kubecolor=kubectl
fi

# fzf config
if [ -f ~/.fzf.zsh ] && command -v fzf >/dev/null 2>&1 && fzf --zsh >/dev/null 2>&1; then
  source ~/.fzf.zsh
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

# machine-specific config, yadm will symlink the .zshrc.local##...
if [ -f ~/.zshrc.local ]; then
  source ~/.zshrc.local
else
  _zshrc_os="$(uname -s)"
  _zshrc_host="$(hostname -s 2>/dev/null || hostname)"
  _zshrc_local_variant="$HOME/.zshrc.local##o.${_zshrc_os},h.${_zshrc_host}"
  [ -f "$_zshrc_local_variant" ] && source "$_zshrc_local_variant"
  unset _zshrc_os _zshrc_host _zshrc_local_variant
fi

# bun completions
[ -s "/Users/jgoon/.bun/_bun" ] && source "/Users/jgoon/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export PATH="$HOME/.local/bin:$PATH"

# load secrets
[[ -f ~/.zshrc.secrets ]] && source ~/.zshrc.secrets
alias gpt='~/github/scripts/query-chat-gpt-through-codex.sh'
