# iTerm2 injects LANG for shells it spawns, but launchd-started services
# (e.g. the herdr server and every pane under it) get a minimal environment
# with no locale — zsh then falls back to C and mangles UTF-8 prompt glyphs.
export LANG=en_US.UTF-8

export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
# guarded: .zshenv runs for every zsh on every box (incl. new ssh sessions),
# but rustup / Vite+ only exist where they were installed. one-liners keep the
# installers' exact `. "..."` line intact so they don't re-append it
# (`if` not `&&`: a missing last file must not leave $? = 1 for the shell).
if [ -f "$HOME/.cargo/env" ]; then . "$HOME/.cargo/env"; fi

# Vite+ bin (https://viteplus.dev)
if [ -f "$HOME/.config/vite-plus/env" ]; then . "$HOME/.config/vite-plus/env"; fi
