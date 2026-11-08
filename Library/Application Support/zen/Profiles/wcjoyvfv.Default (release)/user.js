// Enable custom userChrome.css/userContent.css in this profile.
// Default: off (not set in this build's defaults; Zen only forces it true when
// a userChrome.css is detected during UI migration). There is one here, so the
// Sine mods' stylesheets need this on.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Prevent the sidebar from being dragged/reordered.
// Default: true (defaults/preferences/firefox.js:1790)
user_pref("zen.view.draggable-sidebar", false);
