# iTerm2 injects LANG for shells it spawns, but launchd-started services
# (e.g. the herdr server and every pane under it) get a minimal environment
# with no locale — zsh then falls back to C and mangles UTF-8 prompt glyphs.
export LANG=en_US.UTF-8

export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
. "$HOME/.cargo/env"

# Vite+ bin (https://viteplus.dev)
. "$HOME/.config/vite-plus/env"
