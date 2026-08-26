# Zen Inbox

Zen Inbox is a prototype mod that adds a per-workspace lane for temporary tabs. An Inbox tab remains an ordinary Zen tab, so it can be loaded, unloaded, restored, moved, or closed normally.

Inbox membership is explicit. Drag a regular tab onto the Inbox header or an existing Inbox tab, or right-click it and choose `Send to Inbox`. Drag an Inbox tab back into the regular tab lane to remove it, or use `Remove from Inbox` in its context menu. Inbox tabs appear above Zen's pinned-tab divider, sorted from oldest to newest, and display their age. The Inbox header has an icon, item count, and its own collapse toggle. It remains visible as an empty drop target by default; `Show Inbox when empty` controls that behavior. Collapsing the parent space does not hide the Inbox. `Reset Inbox Timer` starts the displayed age over without changing the original tab creation timestamp. Closing the tab completes the item.

The visual layer is a regular Zen mod stylesheet. The behavior requires the companion `zen-inbox.uc.js` userChrome script because the official mod stylesheet system cannot track tab state or run tab-management logic. Zen's clear-unpinned-tabs action leaves Inbox tabs untouched.

## Install for local testing

### With Sine

If Sine is installed, use its local mod structure. Copy `zen-inbox.uc.js`, `chrome.css`, and `preferences.json` into `chrome/sine-mods/zen-inbox/`, then merge `sine-mod.json` into `chrome/sine-mods/mods.json`. Preserve the other entries in that file.

Sine must have `sine.allow-unsafe-js` enabled for local scripts. Restart Zen after copying the files. Sine will rebuild the stylesheet and load the script into new browser windows.

### Without Sine

Enable Zen's legacy userChrome customization support and configure a privileged userChrome script loader such as [fx-autoconfig](https://github.com/MrOtherGuy/fx-autoconfig). Copy `zen-inbox.uc.js` into the profile's `chrome/JS/` directory, copy `chrome.css` and `preferences.json` into the profile's `chrome/zen-themes/zen-inbox/` directory, and add the following entry to the profile's `zen-themes.json`:

```json
{
  "zen-inbox": {
    "id": "zen-inbox",
    "name": "Zen Inbox",
    "description": "A per-workspace, age-sorted lane for temporary tabs.",
    "author": "local",
    "version": "0.1.0",
    "tags": ["tabs", "productivity", "workflow"],
    "enabled": true,
    "style": "chrome.css",
    "preferences": "preferences.json",
    "readme": "README.md"
  }
}
```

Restart Zen after clearing the startup cache from `about:support`.

The prototype currently supports context-menu and drag-and-drop intake, timer reset, single-unit age labels, continuous age-based urgency colors, workspace-local presentation, independent Inbox collapsing, session-store persistence, and unloading. It does not yet support automatic intake, notifications, sync, split-view groups, or folders.

## Age display and color

The timer shows only its largest unit, such as `59m`, `5h`, `1d`, or `2mo`. Its color is calculated from the exact age, so two tabs that both display `1h` still look different when one is nearly two hours old. The default gradient reaches yellow at four hours, orange at twenty-four hours, and red at three days. Those color points can be changed in the Zen Mods preferences.
