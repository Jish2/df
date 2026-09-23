# zen-duplicate-tabs

Highlights tabs that duplicate the selected tab's URL and shows a count badge
on the selected tab (top-left corner of the tab icon… corner of the tab).

- Only counts duplicates in the **same container** and **same workspace**.
- Essential tabs count in every workspace.
- Ignores glance/empty tabs; pending tabs resolve their URL from session state.
- URLs compare without the `#fragment`.

## Provenance

Ported 2026-09-16 from the fork's in-tree feature (branch
`feat/highlight-duplicate-tabs`, commits `22f69ae0b`, `e1c5e7249`,
`55018cb87` — retrievable from the fork's reflog/history). The in-tree
version also shipped a mochitest (`browser_duplicate_tabs.js`, 139 lines);
mods carry no test coverage, so behavioral regressions surface silently —
compare against upstream DOM changes if highlighting stops appearing.

## Files

- `zen-duplicate-tabs.uc.js` — DOM watcher; sets `zen-duplicate-tab` /
  `zen-duplicate-count` attributes on `#tabbrowser-tabs` children.
- `chrome.css` — outline highlight + count badge styles.
