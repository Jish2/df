autoload -Uz compinit
compinit
# some configs are replicated in ~/.config/nix/flake.nix

# zsh-syntax-highlighting
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# syntax-highlighting-theme
source ~/.config/zsh/themes/catppuccin_mocha-zsh-syntax-highlighting.zsh

# zsh-autosuggestions
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# aliases
source $HOME/.aliases

# zoxide
eval "$(zoxide init zsh --cmd cd)"

# pure zsh prompt
# fpath+=("$(brew --prefix)/share/zsh/site-functions")
autoload -U promptinit; promptinit
prompt pure
prompt_newline=$(echo -n "\u00A0")

# terraform
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform

# pyenv (interactive shell function setup; PATH is set in .zprofile)
command -v pyenv >/dev/null && eval "$(pyenv init -)"

# volta
export PATH="/Users/jgoon/.volta/bin:$PATH"

# kubectl krew
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# kubectl autocomplete
source <(kubectl completion zsh)
compdef kubecolor=kubectl

# fzf config
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

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
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# bun completions
[ -s "/Users/jgoon/.bun/_bun" ] && source "/Users/jgoon/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export PATH="$HOME/.local/bin:$PATH"

# load secrets
[[ -f ~/.zshrc.secrets ]] && source ~/.zshrc.secrets
alias gpt='~/github/scripts/query-chat-gpt-through-codex.sh'
