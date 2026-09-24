// ==UserScript==
// @name           PR Merged Indicator
// @description    Marks GitHub pull-request tabs whose PR has been merged: replaces the favicon with GitHub's purple merged badge so you know the tab is safe to close.
// @version        1.5.0
// ==/UserScript==

/**
 * PR Merged Indicator (Sine / userChrome JS) — chrome side
 *
 * For every tab whose URL is a GitHub pull request
 * (https://github.com/<owner>/<repo>/pull/<n>), determine whether the PR was
 * merged and, if so, REPLACE the tab's favicon with a purple "merged" badge
 * (a purple circle with the white git-merge glyph, GitHub's own badge look)
 * via gBrowser.setIcon().
 *
 * Using the native tab-icon path means the badge is always aligned exactly
 * like a favicon would be, works on pending (unloaded) session-restore tabs,
 * and survives browser restarts (session store persists the icon attribute).
 * No CSS positioning is involved.
 *
 * Two detection paths:
 *
 * 1. Loaded tabs: inject frame.js into the content process (required under
 *    Fission — `browser.contentDocument` is null for remote pages) and wait
 *    for it to report the merge state over the message manager. Same pattern
 *    as zen-page-tint.
 *
 * 2. Pending (session-restored, unloaded) tabs: these never run a content
 *    process until selected, and force-loading them would defeat lazy session
 *    restore. Instead we fetch the PR page over HTTP from chrome with the
 *    profile's github.com cookies attached (same technique as Zen's GitHub
 *    live folder) and run string-level detection on the HTML. Re-checked on an
 *    interval so PRs merged elsewhere eventually mark their never-loaded tabs.
 *
 * A merged PR can never un-merge, so once detected the flag is sticky until
 * the tab navigates to a different document.
 */

(() => {
  "use strict";

  // Idempotency guard: never double-install listeners in the same window.
  if (window.__prMergedIndicator) {
    return;
  }
  window.__prMergedIndicator = true;

  const PR_RE = /^https?:\/\/github\.com\/([^/\s]+)\/([^/\s]+)\/pull\/(\d+)/i;
  const ATTR = "data-pr-merged";
  const FRAME_SCRIPT_URL = "chrome://sine/content/pr-merged-indicator/frame.js";
  const RESULT_MESSAGE_NAME = "pr-merged-indicator:result";
  const PROBE_MESSAGE_NAME = "pr-merged-indicator:probe";
  const TEARDOWN_MESSAGE_NAME = "pr-merged-indicator:teardown";

  // The merged badge: 16x16 SVG — purple disc + white git-merge glyph (GitHub
  // octicon), light/dark aware via a media query inside the SVG. The engine
  // rasterizes base64 SVG icons at the right DPR and re-renders on color
  // scheme changes (browser.tabs.remoteSVGIconDecoding). Delivered as a
  // data: URI, which gBrowser.setIcon() accepts without a loading principal.
  const BADGE_URI = (() => {
    const svg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">' +
      "<style>circle{fill:#8250df}@media(prefers-color-scheme:dark){circle{fill:#a371f7}}</style>" +
      '<circle cx="8" cy="8" r="8"/>' +
      '<g transform="translate(2.4 2.4) scale(0.7)"><path fill="#fff" d="M5.45 5.154A4.25 4.25 0 0 0 9.25 7.5h1.378a2.251 2.251 0 1 1 0 1.5H9.25A5.734 5.734 0 0 1 5 7.123v3.505a2.25 2.25 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.95-.218ZM4.25 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm8.5-4.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM5 3.25a.75.75 0 1 0 0 .005V3.25Z"/></g>' +
      "</svg>";
    return "data:image/svg+xml;base64," + btoa(svg);
  })();

  // A long alphanumeric slice of the badge's base64 payload. The engine may
  // rewrite SVG data-URI icons into moz-remote-image://?url=<encoded> form
  // (browser.tabs.remoteSVGIconDecoding), so "did our icon land?" must match
  // either form — matching only the raw data URI caused an infinite re-apply
  // loop in the icon watcher (v1.4.1) that froze the UI.
  const BADGE_MARK = (() => {
    const b64 = BADGE_URI.slice(BADGE_URI.indexOf(",") + 1);
    const runs = b64.match(/[A-Za-z0-9]{12,}/g) || [];
    return runs.reduce((a, b) => (b.length > a.length ? b : a), "");
  })();

  // True when the tab's image attribute is our badge — raw data: URI or the
  // engine's moz-remote-image:// wrapped form of it.
  function isBadgeImageAttr(img) {
    if (!img) return false;
    if (img === BADGE_URI) return true;
    return !!BADGE_MARK && img.includes(BADGE_MARK);
  }

  // Pending-tab (HTTP) check configuration.
  const HTTP_STAGGER_MS = 3000; // spacing between per-tab fetches (no burst)
  const HTTP_START_DELAY_MS = 15000; // let startup settle before fetching
  const RECHECK_INTERVAL_MS = 30 * 60 * 1000; // re-check unmarked pending PRs
  const HTTP_MAX_CONTENT = 2 * 1024 * 1024; // 2 MB cap per fetch

  // Optional modules; HTTP checking silently degrades if unavailable.
  let NetUtil = null;
  let SessionStore = null;
  try {
    NetUtil = ChromeUtils.importESModule(
      "resource://gre/modules/NetUtil.sys.mjs"
    ).NetUtil;
  } catch (e) {}
  // SessionStore's module URL moved between builds: current mozilla-central
  // (and Satori) exposes it under moz-src:///, older stock Zen under
  // resource:///modules/sessionstore/. Try both in order — v1.4.2 imported
  // only the old path, which silently killed the pending-tab HTTP path on
  // Satori builds (merged PR tabs sat unbadged for hours while pending).
  for (const url of [
    "moz-src:///browser/components/sessionstore/SessionStore.sys.mjs",
    "resource:///modules/sessionstore/SessionStore.sys.mjs",
  ]) {
    try {
      SessionStore = ChromeUtils.importESModule(url).SessionStore;
      if (SessionStore) {
        break;
      }
    } catch (e) {}
  }

  // browser -> { mm, listeners: [fn], loaded }. The mm identity is tracked
  // because a remoteness change or tab restore recreates the message manager;
  // the stale record is discarded and everything re-attached to the live one.
  const browserState = new WeakMap();

  // Pending PR tabs awaiting/served by the HTTP path, plus its timers.
  const pendingChecks = new Set();
  const httpTimers = new Set(); // setTimeout ids
  let recheckTimer = null;

  function isPrUrl(url) {
    return PR_RE.test(url || "");
  }

  function prIdentity(url) {
    const m = PR_RE.exec(url || "");
    return m ? `${m[1]}/${m[2]}/pull/${m[3]}` : null;
  }

  function currentUrl(browser) {
    try {
      return (browser.currentURI && browser.currentURI.spec) || "";
    } catch (e) {
      return "";
    }
  }

  function tabFor(browser) {
    try {
      return window.gBrowser ? window.gBrowser.getTabForBrowser(browser) : null;
    } catch (e) {
      return null;
    }
  }

  function setMerged(tab, on) {
    if (!tab) return;
    try {
      if (on) {
        tab.setAttribute(ATTR, "true");
        // Replace the favicon with the merged badge. gBrowser.setIcon() is
        // safe on pending tabs (plain property write + attribute set — the
        // same call SessionStore uses to give lazy tabs their icons) and the
        // badge survives restarts because session store persists the image.
        window.gBrowser.setIcon(tab, BADGE_URI);
      } else if (tab.hasAttribute(ATTR)) {
        tab.removeAttribute(ATTR);
        // Drop our icon override so the (new) document's own favicon takes
        // over again through the normal favicon pipeline.
        window.gBrowser.setIcon(tab, "");
      }
    } catch (e) {
      // dead tab object / setIcon unavailable; ignore
    }
  }

  // --------------------------------------------------------------------------
  // Path 1: loaded tabs — frame script injection + message manager
  // --------------------------------------------------------------------------

  // The listener closes over its browser (zen-page-tint's approach), so no
  // message.target -> browser resolution is needed. Stale results from a
  // document the tab already left are ignored by comparing PR identities.
  function makeResultListener(browser) {
    return (message) => {
      try {
        const data = message.data || {};
        const reported = prIdentity(data.href || "");
        const current = prIdentity(currentUrl(browser));
        if (!reported || reported !== current) {
          return;
        }
        // Only mark on merged:true. Never unmark from a negative probe — a
        // merged PR can't un-merge; an unmarked tab just stays unmarked.
        if (data.merged) {
          const tab = tabFor(browser);
          setMerged(tab, true);
          if (tab) pendingChecks.delete(tab);
        }
      } catch (e) {
        // ignore malformed messages
      }
    };
  }

  function sendTeardown(browser) {
    try {
      const rec = browserState.get(browser);
      if (rec && rec.loaded && rec.mm === browser.messageManager) {
        rec.mm.sendAsyncMessage(TEARDOWN_MESSAGE_NAME, {});
      }
    } catch (e) {}
  }

  function detachBrowser(browser) {
    try {
      const rec = browserState.get(browser);
      if (!rec) return;
      // Only remove listeners from the live mm; a recreated mm means the old
      // listeners already died with it.
      if (rec.mm === browser.messageManager) {
        for (const l of rec.listeners) {
          try {
            rec.mm.removeMessageListener(RESULT_MESSAGE_NAME, l);
          } catch (e) {}
        }
      }
      browserState.delete(browser);
    } catch (e) {}
  }

  function loadFrameScript(browser) {
    try {
      if (!isPrUrl(currentUrl(browser))) return;

      const mm = browser.messageManager;
      if (!mm || !mm.loadFrameScript) return;

      let rec = browserState.get(browser);
      if (rec && rec.mm !== mm) {
        detachBrowser(browser);
        rec = null;
      }
      if (!rec) {
        rec = { mm, listeners: [], loaded: false };
        browserState.set(browser, rec);
      }

      if (!rec.loaded) {
        const listener = makeResultListener(browser);
        mm.addMessageListener(RESULT_MESSAGE_NAME, listener);
        rec.listeners.push(listener);
        rec.loaded = true;
      }

      // (Re-)inject on every navigation. Each execution runs frame.js in the
      // scope of THIS browser's message manager and probes that browser's
      // own documents (under Fission all github.com tabs share one content
      // process, so a process-wide probe would read whichever tab loaded
      // first — the v1.4.2 bug). Stale listeners from previous documents
      // self-unregister once their window is gone.
      mm.loadFrameScript(FRAME_SCRIPT_URL, false);

      // Ask for a fresh probe of the current document. On the content
      // process's FIRST load this message can arrive before the frame's
      // listeners are registered and be dropped (documented Sine/Gecko race) —
      // harmless, because the frame script probes on execution and again on
      // the document's load event.
      mm.sendAsyncMessage(PROBE_MESSAGE_NAME, {});
    } catch (e) {
      // ignore transient errors during teardown
    }
  }

  // --------------------------------------------------------------------------
  // Path 2: pending (unloaded) tabs — HTTP check with session cookies
  // --------------------------------------------------------------------------

  // Whether the tab is a lazily-restored one that has never been loaded.
  function isPendingTab(tab) {
    try {
      return !tab.linkedPanel || tab.hasAttribute("pending");
    } catch (e) {
      return false;
    }
  }

  // Pull the tab's current URL out of session state WITHOUT touching
  // linkedBrowser (touching it would instantiate the lazy browser).
  function pendingTabUrl(tab) {
    if (!SessionStore) return null;
    try {
      const state = JSON.parse(SessionStore.getTabState(tab));
      const entries = state.entries || [];
      const index = Math.min(state.index || 1, entries.length) - 1;
      const url = entries[index] && entries[index].url;
      return isPrUrl(url) ? url : null;
    } catch (e) {
      return null;
    }
  }

  // Fetch a URL from chrome with the profile's cookies attached. Channel
  // recipe mirrors Zen's GitHub live folder: TYPE_SAVEAS_DOWNLOAD + a content
  // principal for the target URI + SEC_COOKIES_INCLUDE is what makes the
  // cookie jar apply (fetch() from chrome would send no cookies).
  function httpFetch(url) {
    return new Promise((resolve, reject) => {
      try {
        const uri = NetUtil.newURI(url);
        const principal = Services.scriptSecurityManager.createContentPrincipal(
          uri,
          {}
        );
        const channel = NetUtil.newChannel({
          uri,
          contentPolicyType: Ci.nsIContentPolicy.TYPE_SAVEAS_DOWNLOAD,
          loadingPrincipal: principal,
          securityFlags:
            Ci.nsILoadInfo.SEC_ALLOW_CROSS_ORIGIN_SEC_CONTEXT_IS_NULL |
            Ci.nsILoadInfo.SEC_COOKIES_INCLUDE,
          triggeringPrincipal: principal,
        }).QueryInterface(Ci.nsIHttpChannel);

        let status = null;
        const chunks = [];
        let total = 0;

        channel.asyncOpen({
          onStartRequest(request) {
            try {
              status = request.QueryInterface(Ci.nsIHttpChannel).responseStatus;
            } catch (e) {}
          },
          onDataAvailable(request, stream, offset, count) {
            total += count;
            if (total > HTTP_MAX_CONTENT) {
              request.cancel(Cr.NS_ERROR_FILE_TOO_BIG);
              return;
            }
            chunks.push(NetUtil.readInputStream(stream, count));
          },
          onStopRequest(request, statusCode) {
            if (!Components.isSuccessCode(statusCode)) {
              reject(new Error("fetch failed: " + statusCode));
              return;
            }
            const bytes = new Uint8Array(total);
            let off = 0;
            for (const chunk of chunks) {
              bytes.set(new Uint8Array(chunk), off);
              off += chunk.byteLength;
            }
            // GitHub serves UTF-8.
            resolve({ status, text: new TextDecoder("utf-8").decode(bytes) });
          },
        });
      } catch (e) {
        reject(e);
      }
    });
  }

  // String-level version of frame.js's layered detection, applied to raw HTML.
  function isMergedHtml(html) {
    return (
      html.indexOf("State--merged") !== -1 ||
      html.indexOf("Status: Merged") !== -1 ||
      /"state"\s*:\s*"MERGED"/.test(html)
    );
  }

  async function httpCheckTab(tab, url) {
    try {
      const { status, text } = await httpFetch(url);
      if (status === 200 && isMergedHtml(text)) {
        setMerged(tab, true);
        pendingChecks.delete(tab);
      }
      // Not merged (or fetch failed): leave in pendingChecks for the next
      // re-check interval — the PR may merge later.
    } catch (e) {
      // Network error; retried on the next interval.
    }
  }

  // Staggered sweep over pending PR tabs, re-armed on an interval for the
  // still-unmarked ones (PRs can be merged while the browser is closed).
  function runPendingChecks() {
    const work = [];
    for (const tab of Array.from(pendingChecks)) {
      const url = pendingTabUrl(tab);
      if (!url) {
        // Not (or no longer) a PR tab, or tab vanished.
        pendingChecks.delete(tab);
        continue;
      }
      work.push({ tab, url });
    }
    work.forEach(({ tab, url }, i) => {
      const id = window.setTimeout(() => {
        httpTimers.delete(id);
        // Tab may have been closed or selected (frame path takes over).
        if (!pendingChecks.has(tab)) return;
        httpCheckTab(tab, url);
      }, HTTP_STAGGER_MS * i);
      httpTimers.add(id);
    });
  }

  function startHttpPath() {
    if (!NetUtil || !SessionStore) return;
    const kickoff = window.setTimeout(() => {
      httpTimers.delete(kickoff);
      runPendingChecks();
      recheckTimer = window.setInterval(runPendingChecks, RECHECK_INTERVAL_MS);
    }, HTTP_START_DELAY_MS);
    httpTimers.add(kickoff);
  }

  // --------------------------------------------------------------------------
  // Wiring
  // --------------------------------------------------------------------------

  const progressListener = {
    onLocationChange(aBrowser, aWebProgress, aRequest, aLocation, aFlags) {
      // Anchor-only changes keep the same document; the marker is still valid.
      try {
        if (
          aFlags & Ci.nsIWebProgressListener.LOCATION_CHANGE_SAME_DOCUMENT
        ) {
          return;
        }
      } catch (e) {
        // Ci unavailable — treat as a full navigation and continue
      }
      try {
        const tab = tabFor(aBrowser);
        if (!tab) return;

        // The tab is really loading now — the frame path owns it; stop the
        // HTTP re-checks for it.
        pendingChecks.delete(tab);

        const url = currentUrl(aBrowser);
        if (!isPrUrl(url)) {
          // Navigated away from a PR: drop the marker.
          setMerged(tab, false);
          return;
        }

        // New PR document: reset the marker (re-armed only if the frame
        // reports merged again) and (re)inject the frame script.
        setMerged(tab, false);
        loadFrameScript(aBrowser);
      } catch (e) {
        // ignore transient errors during teardown
      }
    },
  };

  // Lazily restored / background-loaded tabs get their real load when first
  // selected; make sure the selected PR tab gets probed at least once per select.
  const onTabSelect = () => {
    try {
      const b = window.gBrowser.selectedBrowser;
      if (!b) return;
      if (isPrUrl(currentUrl(b))) {
        loadFrameScript(b);
      }
    } catch (e) {}
  };

  const onTabClose = (event) => {
    try {
      const tab = event.target;
      pendingChecks.delete(tab);
      const b = window.gBrowser.getBrowserForTab(tab);
      if (b) detachBrowser(b);
    } catch (e) {}
  };

  // Initial sweep over tabs already open in this window. Live tabs take the
  // frame path; pending PR tabs are queued for the HTTP path (touching
  // .messageManager on a lazy browser instantiates it, which defeats lazy
  // session restore). Tabs restored with our badge icon (session store
  // persists it) get their sticky marker re-armed without a re-check.
  try {
    for (const tab of window.gBrowser.tabs) {
      try {
        if (isBadgeImageAttr(tab.getAttribute("image"))) {
          // Restored with our badge from a previous session: re-arm the
          // sticky marker (merged PRs never un-merge).
          tab.setAttribute(ATTR, "true");
        } else if (tab.hasAttribute(ATTR) && !tab.zenStaticIcon) {
          // Marked earlier this session but the icon was clobbered while this
          // script wasn't watching: repair it. (zenStaticIcon tabs always win
          // over setIcon — don't fight them.)
          window.gBrowser.setIcon(tab, BADGE_URI);
        }
      } catch (e) {}

      if (isPendingTab(tab)) {
        if (pendingTabUrl(tab)) {
          pendingChecks.add(tab);
        }
      } else {
        const b = tab.linkedBrowser;
        if (b && isPrUrl(currentUrl(b))) {
          loadFrameScript(b);
        }
      }
    }
  } catch (e) {}

  startHttpPath();

  window.gBrowser.addTabsProgressListener(progressListener);
  window.gBrowser.tabContainer.addEventListener("TabSelect", onTabSelect);
  window.gBrowser.tabContainer.addEventListener("TabClose", onTabClose);

  // The favicon pipeline (page loads, LinkHandler, session-restore icon
  // replays) can overwrite our badge at unpredictable times AFTER we set it
  // — observed as "the badge appeared for a second, then vanished". Watch
  // the tab image attribute and re-assert the badge on any marked tab whose
  // icon changes to something else. Convergence is guarded twice over: our
  // own writes are recognized via isBadgeImageAttr (raw or wrapped form),
  // and a circuit breaker stops re-asserting after a few losing fights, so
  // no unexpected writer can ever freeze the UI — the v1.4.1 freeze was an
  // infinite re-apply loop in exactly this callback.
  const iconReasserts = new WeakMap();
  const iconObserver = new MutationObserver((records) => {
    const seen = new Set();
    for (const record of records) {
      try {
        const tab = record.target;
        if (!tab.hasAttribute || seen.has(tab)) continue;
        seen.add(tab);
        if (!tab.hasAttribute(ATTR)) continue;
        if (isBadgeImageAttr(tab.getAttribute("image"))) {
          // Our own write landed; the tab is in its correct state.
          iconReasserts.delete(tab);
          continue;
        }
        // Something else overwrote the badge: re-assert it.
        const count = (iconReasserts.get(tab) || 0) + 1;
        iconReasserts.set(tab, count);
        if (count > 5) {
          if (count === 6) {
            console.warn(
              "[pr-merged-indicator] a tab's icon is being pinned by another writer; no longer re-asserting"
            );
          }
          continue;
        }
        // A zenStaticIcon tab always wins over setIcon — don't fight it.
        if (tab.zenStaticIcon) continue;
        window.gBrowser.setIcon(tab, BADGE_URI);
      } catch (e) {}
    }
  });
  iconObserver.observe(window.gBrowser.tabContainer, {
    attributes: true,
    attributeFilter: ["image"],
    subtree: true,
  });

  // Sine unload hook: remove everything this script installed in the window.
  // Sine's addUnloadListener survives hot-reload; fall back to one-shot unload.
  const cleanup = () => {
    try {
      iconObserver.disconnect();
    } catch (e) {}
    try {
      window.gBrowser.removeTabsProgressListener(progressListener);
    } catch (e) {}
    try {
      window.gBrowser.tabContainer.removeEventListener(
        "TabSelect",
        onTabSelect
      );
      window.gBrowser.tabContainer.removeEventListener(
        "TabClose",
        onTabClose
      );
    } catch (e) {}
    try {
      if (recheckTimer !== null) {
        window.clearInterval(recheckTimer);
        recheckTimer = null;
      }
      for (const id of Array.from(httpTimers)) {
        window.clearTimeout(id);
      }
      httpTimers.clear();
      pendingChecks.clear();
    } catch (e) {}
    try {
      for (const tab of window.gBrowser.tabs) {
        if (!tab.linkedPanel) continue;
        const browser = tab.linkedBrowser;
        if (!browser) continue;
        sendTeardown(browser);
        detachBrowser(browser);
      }
    } catch (e) {}
    try {
      for (const tab of window.gBrowser.tabs) {
        if (tab.hasAttribute(ATTR)) tab.removeAttribute(ATTR);
        // Restore the favicon on unload so the mod leaves no trace.
        if (tab.getAttribute("image") === BADGE_URI) {
          window.gBrowser.setIcon(tab, "");
        }
      }
    } catch (e) {}
    try {
      delete window.__prMergedIndicator;
    } catch (e) {}
  };
  if (typeof window.addUnloadListener === "function") {
    window.addUnloadListener(cleanup);
  } else {
    window.addEventListener("unload", cleanup, { once: true });
  }
})();
