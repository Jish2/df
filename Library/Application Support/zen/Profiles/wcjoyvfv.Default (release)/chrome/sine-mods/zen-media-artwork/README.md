# Zen Media Artwork

Zen Media Artwork adds album artwork to the native sidebar media controller. It reads the artwork supplied by the page through the Media Session API, updates when the track changes, and leaves the native card unchanged when no artwork is available.

The behavior uses a privileged userChrome script because a regular web extension cannot access Zen's browser-chrome media controller.

## Install with Sine

Copy `zen-media-artwork.uc.js` and `chrome.css` into Sine's local mod directory:

```text
chrome/sine-mods/zen-media-artwork/
```

Merge the `zen-media-artwork` entry from `sine-mod.json` into `chrome/sine-mods/mods.json`. Keep the other entries in that file. The file should remain a JSON object keyed by mod ID.

Do not select `sine-mod.json` with Sine's `Import Mods` button. That importer expects a Sine export file whose top level is an array and whose entries point to hosted mod repositories. `sine-mod.json` is a local installation helper.

Enable `sine.allow-unsafe-js`, then restart Zen. Sine will load the script into new browser windows.

## Install without Sine

Enable Zen's legacy userChrome customization support and use a privileged userChrome script loader such as [fx-autoconfig](https://github.com/MrOtherGuy/fx-autoconfig). Copy `zen-media-artwork.uc.js` into the profile's `chrome/JS/` directory and load `chrome.css` through the profile's userChrome stylesheet.

Restart Zen after clearing the startup cache from `about:support`.

The mod does not add DRM support. Spotify artwork appears only when Spotify can play successfully and provides Media Session artwork to Zen.
