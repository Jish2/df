// Enable custom userChrome.css/userContent.css in this profile.
// Default: off (not set in this build's defaults; Zen only forces it true when
// a userChrome.css is detected during UI migration). There is one here, so the
// Sine mods' stylesheets need this on.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Prevent the sidebar from being dragged/reordered.
// Default: true (defaults/preferences/firefox.js:1790)
user_pref("zen.view.draggable-sidebar", false);

// Keep Sine mods out of the command palette.
// Default in the mod's source: true (zen-command-palette.uc.js, DYNAMIC_SINE_MODS).
// When on, generateSineCommands() turns every Sine marketplace entry that is
// not installed into an "Install Sine Mod: <name>" palette result, and
// selecting one installs it immediately with no confirmation. Typing a
// partial match and pressing Enter is how stray mods got installed.
// Off removes both the install and uninstall Sine entries.
user_pref("zen-command-palette.dynamic.sine-mods", false);
