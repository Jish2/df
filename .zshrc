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
