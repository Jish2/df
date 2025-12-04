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

# volta
export PATH="/Users/jgoon/.volta/bin:$PATH"

# kubectl krew
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# kubectl autocomplete
source <(kubectl completion zsh)
compdef kubecolor=kubectl

# fzf config
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# setup go + rbx
export GOPROXY=https://artifactory.rbx.com/api/go/go-all
export GONOSUMDB=github.rbx.com

export RBX_REGISTRY="--registry=https://artifactory.rbx.com/api/npm/npm-all/"

