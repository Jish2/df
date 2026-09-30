# compinit + bashcompinit run in nix-darwin's /etc/zshrc before this
# file lands; no need to duplicate them here anymore

# some configs are replicated in ~/.config/nix/flake.nix

# plugins: macs source zsh-autosuggestions + zsh-syntax-highlighting from
# nix-darwin's /etc/zshenv + /etc/zshrc (store paths); linux boxes source
# them from NIX_PROFILES below (shipped via HM home.packages). pure ships
# on fpath (prompt_pure_setup) in both worlds — see the prompt block below.

# zsh-autosuggestions, then zsh-syntax-highlighting (it wraps widgets, so
# it goes last). macs already load both via nix-darwin's /etc files — the
# guards skip (double-sourcing would wrap every widget twice); linux boxes
# find them in NIX_PROFILES (shipped via HM home.packages; layouts differ
# between nixpkgs versions, so the glob covers both, first match wins).
if (( ! ${+functions[_zsh_autosuggest_start]} )); then
  for _p in ${(s.:.)NIX_PROFILES}; do
    _m=("$_p"/share/**/zsh-autosuggestions/zsh-autosuggestions.zsh(N))
    (( ${#_m} )) && { source "${_m[1]}"; break }
  done
fi
if (( ! ${+functions[_zsh_highlight]} )); then
  for _p in ${(s.:.)NIX_PROFILES}; do
    _m=("$_p"/share/**/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh(N))
    (( ${#_m} )) && { source "${_m[1]}"; break }
  done
fi
unset _p _m

# syntax-highlighting-theme
source ~/.config/zsh/themes/catppuccin_mocha-zsh-syntax-highlighting.zsh

# aliases
source $HOME/.aliases

# custom functions
for f in ~/.config/zsh/functions/*.zsh(N); do
  source "$f"
done

# zoxide
eval "$(zoxide init zsh --cmd cd)"

# pure zsh prompt (macs: pure-prompt ships via nix-darwin systemPackages
# and /etc/zshenv fpath; linux: via HM home.packages — both land the plugin
# in NIX_PROFILES, which the platform zshenv adds to fpath)
autoload -U promptinit; promptinit
if (( ${+functions[prompt_pure_setup]} )); then
  prompt pure
fi

# A tree marks shells opened by `treehouse get` or `treehouse enter`.
# Keep it in Pure's preprompt (the path and Git information line), and put the
# command prompt itself on a separate line. Pure expands `prompt_newline` only
# once, so use its native psvar state rather than a nested command substitution.
treehouse_prompt_precmd() {
  psvar[21]=
  if [[ -n ${TREEHOUSE_DIR:-} ]] &&
     { [[ $PWD == "$TREEHOUSE_DIR" ]] || [[ $PWD == "$TREEHOUSE_DIR"/* ]]; }; then
    psvar[21]='🌳'
  fi
}
add-zsh-hook precmd treehouse_prompt_precmd
prompt_newline=' %(21V.%F{green}%21v%f.)'$'\n%{\r%}'

# terraform (bashcompinit already ran in /etc/zshrc; darwin path only)
command -v terraform >/dev/null && complete -o nospace -C "$(command -v terraform)" terraform

# pyenv (interactive shell function setup; PATH is set in .zprofile)
command -v pyenv >/dev/null && eval "$(pyenv init -)"

# volta (work box)
[ -d "$HOME/.volta/bin" ] && export PATH="$HOME/.volta/bin:$PATH"
export PATH="$HOME/bin:$PATH"

# kubectl krew
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# kubectl autocomplete (kubectl may be a kubecolor alias — guard on the
# unwrapped binary; kubecolor may not be installed on every machine)
if command -v kubectl >/dev/null 2>&1 && [[ $(whence -p kubectl 2>/dev/null) ]]; then
  source <("$(whence -p kubectl)" completion zsh)
fi
command -v kubecolor >/dev/null 2>&1 && compdef kubecolor=kubectl

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

# Auto-start or attach tmux on SSH login
# if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then
#   tmux attach -t main || tmux new -s main
# fi

# rustup (darwin)
command -v rustup >/dev/null || [ -d /opt/homebrew/opt/rustup/bin ] && export PATH="/opt/homebrew/opt/rustup/bin:$PATH"

# Vite+ bin (https://viteplus.dev) — optional, not installed on every machine
[ -r "$HOME/.config/vite-plus/env" ] && . "$HOME/.config/vite-plus/env"

# sessions: semantic search via local Ollama embeddings
export SESSIONS_OLLAMA_MODEL=qwen3-embedding:4b

# cd into ~/github repos from anywhere (e.g. `cd pi`)
cdpath=("$HOME/github" $cdpath)
