# PR Merged Indicator (Sine mod)

Marks GitHub pull-request tabs whose PR has been **merged** with a purple
merge icon over the favicon, so you know the tab is safe to close.

![concept](https://img.shields.io/badge/merged-%E2%9C%94-8957e5)

## How it works

- A userChrome JS script watches every tab whose URL matches
  `github.com/<owner>/<repo>/pull/<n>` and injects a **frame script** into the
  content process (required under Fission — chrome JS cannot read remote page
  DOM via `browser.contentDocument`). Probes are keyed **per window**: under
  Fission every github.com tab shares one content process, so a single
  process-wide probe would read whichever tab loaded first and never mark
  the rest (the v1.4.2 bug).
- Merge state is read from the PR page itself — **no API calls, no tokens**:
  1. `"state":"MERGED"` inside GitHub's React app embedded JSON (`<script type="application/json">`)
  2. classic Primer badge `.State--merged` / `title="Status: Merged"`
  3. any State/Badge/Label-classed element whose text is exactly "Merged"
- On detection it sets `data-pr-merged="true"` on the `.tabbrowser-tab`
  element and **replaces the favicon** with a purple git-merge badge via
  `gBrowser.setIcon()` (survives browser restarts — session store persists
  the tab image; an attribute watcher re-asserts it if the favicon pipeline
  clobbers it).
- **Pending (session-restored, unloaded) tabs** are handled without loading
  them: the PR page is fetched from chrome with your github.com session
  cookies (same technique as Zen's GitHub live folder) and checked with the
  same layered detection, re-checked every 30 min so PRs merged elsewhere
  eventually mark tabs you never opened. Touching a lazy tab's message
  manager would defeat lazy session restore, hence the HTTP path. The
  SessionStore import tries `moz-src:///browser/components/sessionstore/…`
  first and falls back to `resource:///modules/sessionstore/…` — the module
  moved between builds (the wrong path silently disables this whole path).
- Checks run on tab navigation (tabs progress listener), on tab select
  (covers lazily restored sessions), and via a bounded ~9 s retry loop while
  GitHub's React header hydrates. Once marked, the flag is sticky until the
  tab navigates away or closes.

> ⚠️ GitHub's DOM is not a stable contract. The layered detection above makes
> this resilient, but a future GitHub redesign may require updating selectors.

## Requirements

- [Sine](https://github.com/CosmoCreeper/Sine) mod manager
- **JS from unofficial sources enabled**: Sine only runs JS from non-store mods
  when `sine.allow-unsafe-js` is true. In Sine settings enable
  *"Enable installing JS from unofficial sources"* (or set the pref in
  `about:config`). Without it, the CSS will load but detection won't run.

## Install

1. Push this folder to a GitHub repo (e.g. `Jish2/pr-merged-indicator`).
2. Open Sine settings → install a mod → enter the repo name
   (`Jish2/pr-merged-indicator`).
3. Enable the mod and restart the browser if prompted.

### Quick local test (no GitHub)

Mods are just folders under your profile's `chrome/sine-mods/`. To try it
immediately, symlink this folder there and register it in `mods.json`:

```bash
MODS="$HOME/.zen/*/chrome/sine-mods"   # adjust to your profile
ln -s "$(pwd)/pr-merged-indicator" $MODS/pr-merged-indicator
```

then add to `chrome/sine-mods/mods.json`:

```json
"pr-merged-indicator": {
  "id": "pr-merged-indicator",
  "enabled": true,
  "origin": "repo",
  "scripts": {
    "pr-merged-indicator.uc.js": {
      "include": ["chrome://browser/content/browser.xhtml"]
    }
  },
  "style": { "chrome": "userChrome.css" },
  "supportsUnload": true
}
```

(The `mods.json` shape can vary between Sine versions — if it doesn't pick up,
use the GitHub-repo install route above, which is the supported path.)

## Customizing

- **Color**: edit `--pr-merged-color` at the top of `userChrome.css`.
- **Icon size/placement**: `userChrome.css` covers the whole favicon by
  default; a snippet at the bottom shows how to shrink it to a corner badge.
- **Sensitivity**: `RETRY_MS` / `RETRY_MAX` constants at the top of
  `frame.js` control how long it waits for hydration.

## Files

| File | Purpose |
|---|---|
| `theme.json` | Sine manifest |
| `pr-merged-indicator.uc.js` | chrome-side: injects frame script, badges the favicon via gBrowser.setIcon |
| `frame.js` | content-side: per-window layered merge detection (injected via message manager) |
| `userChrome.css` | purple outline + favicon dot styling |
