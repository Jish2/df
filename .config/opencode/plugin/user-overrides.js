// User overrides for settings declawd overwrites.
//
// declawd regenerates ~/.config/opencode/opencode.json from a hardcoded
// template on every launch (and rewrites it every ~3 min for token refresh),
// wiping any edits. It never removes foreign files under plugin/, and
// opencode auto-discovers *.js here, which makes this the last stable seam.
//
// The config hook receives the live merged config at opencode startup and
// may mutate it; these values win regardless of what the file on disk says.
export const UserOverrides = async () => ({
  config: async (cfg) => {
    // Default model (template pins llm-gateway/claude-sonnet-5)
    cfg.model = "llm-gateway/kimi-k3"

    // Yolo: auto-approve everything NOT explicitly denied. Unlike declawd's
    // own --yolo (which replaces the whole permission block with bare "allow"
    // and drops the .env/ssh-key deny lists), this prepends the "allow"
    // wildcard while keeping the template's deny rules underneath it.
    if (typeof cfg.permission !== "object" || cfg.permission === null) {
      cfg.permission = {}
    }
    cfg.permission = { "*": "allow", ...cfg.permission }
  },
})
