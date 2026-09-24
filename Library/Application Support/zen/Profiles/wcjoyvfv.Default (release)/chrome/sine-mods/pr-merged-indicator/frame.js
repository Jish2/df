// PR Merged Indicator — frame script
// Loaded into the content process via mm.loadFrameScript.
// Runs layered merge detection against the PR page DOM (which is where GitHub
// reports the state) and pushes the result to the chrome process via
// sendAsyncMessage.
//
// Lifecycle:
//   - chrome re-injects this script on every navigation and tab select. Every
//     execution runs in the scope of the browser it was loaded into:
//     `content`, `sendAsyncMessage` and `addMessageListener` resolve through
//     THAT browser's message manager, so an execution can only ever probe and
//     report its own browser's documents.
//   - Probe timers/attempts are keyed per window in a process-wide WeakMap.
//     Frame-script globals are shared by every browser in this content
//     process (under Fission, all github.com tabs share one), so v1.4.2's
//     single probe on the process global read whichever tab happened to load
//     first: every other PR tab in the process reported the first tab's href
//     and was silently dropped by the chrome side's identity guard. Keying by
//     window also makes a navigation start fresh (a new window = a new slot)
//     and lets re-execution for the same window (tab select without
//     navigation) converge on one retry loop.
//   - The probe-request path reads `content` dynamically, so a PROBE message
//     that arrives before the document exists (the documented Sine/Gecko
//     first-load race) still targets whatever document is current when it
//     lands. Message listeners can outlive their document, so each listener
//     drops itself once the window it was wired for is gone — this is what
//     keeps the listener lists from accumulating across navigations.
//
// Detection is deliberately layered (GitHub's React DOM is not a contract):
//   1. Embedded JSON payload of GitHub's React app: look for the PR record and
//      "state":"MERGED" inside <script type="application/json"> blocks.
//   2. Classic Primer state badge: .State--merged.
//   3. Badge elements whose title or exact text is "Merged" (State/Badge/Label
//      classes, title="Status: Merged").

(() => {
  'use strict';

  const RESULT_MESSAGE_NAME = 'pr-merged-indicator:result';
  const PROBE_MESSAGE_NAME = 'pr-merged-indicator:probe';
  const TEARDOWN_MESSAGE_NAME = 'pr-merged-indicator:teardown';
  const RETRY_MS = 750;  // retry cadence while GitHub's React header hydrates
  const RETRY_MAX = 12;  // ~9s of bounded retries, then give up (stays unmarked)

  // This execution's bindings. `win` is the browser's current document at
  // execution time; `content` (read dynamically below) follows the browser's
  // current document across navigations. Both always belong to the browser
  // this script was loaded into — never to a sibling tab sharing this content
  // process.
  const win = content;

  // Process-wide registry: window -> { timer, attempts }. Weak so a destroyed
  // document (navigation) releases its state without waiting for teardown.
  const registry =
    globalThis.__prMergedIndicatorRegistry ||
    (globalThis.__prMergedIndicatorRegistry = new WeakMap());

  function isPrUrl(url) {
    return /^https?:\/\/github\.com\/([^/\s]+)\/([^/\s]+)\/pull\/(\d+)/i.test(url || '');
  }

  /**
   * Layered merge detection against the PR page document. Best effort: GitHub
   * may restructure its markup at any time, so multiple independent signals are
   * probed before giving up.
   */
  function isMerged(doc) {
    // 1) Embedded JSON payload of GitHub's React app. The PR record carries
    //    "state": "MERGED". Requiring a pullRequest-ish key in the same script
    //    avoids matching unrelated JSON blobs.
    const jsonScripts = doc.querySelectorAll('script[type="application/json"]');
    for (const el of jsonScripts) {
      const text = el.textContent || '';
      if (
        (text.indexOf('"pullRequest"') !== -1 ||
          text.indexOf('"pull_request"') !== -1) &&
        /"state"\s*:\s*"MERGED"/.test(text)
      ) {
        return true;
      }
    }

    // 2) Classic Primer state badge.
    if (doc.querySelector('.State--merged')) {
      return true;
    }

    // 3) Badge elements whose title or exact text is "Merged".
    if (doc.querySelector('[title="Status: Merged"]')) {
      return true;
    }

    const badges = doc.querySelectorAll(
      '[class*="State" i],[class*="Badge" i],[class*="Label" i]'
    );
    for (const el of badges) {
      if ((el.textContent || '').trim() === 'Merged') {
        return true;
      }
    }

    return false;
  }

  // False once this execution's window has been destroyed — a cross-document
  // navigation turns it into a dead wrapper, and property access throws.
  function windowAlive() {
    try {
      if (win.closed) return false;
      return !!win.location;
    } catch (e) {
      return false;
    }
  }

  // Per-window probe state. Shared by every execution targeting the same
  // window, so their retry loops converge instead of stacking.
  function stateFor(w) {
    let s = registry.get(w);
    if (!s) {
      s = { timer: null, attempts: 0 };
      registry.set(w, s);
    }
    return s;
  }

  function clearWindowState(w) {
    const s = registry.get(w);
    if (s && s.timer !== null) {
      try { w.clearTimeout(s.timer); } catch (e) {}
      s.timer = null;
    }
    try { registry.delete(w); } catch (e) {}
  }

  function report(merged, href) {
    try {
      sendAsyncMessage(RESULT_MESSAGE_NAME, {
        href,
        merged,
      });
    } catch (e) {
      try { console.error('[pr-merged-indicator frame] report failed:', e); } catch {}
    }
  }

  // Probe one window of this browser: detect now if the document is complete,
  // otherwise schedule a bounded retry loop keyed on that window.
  // freshBudget=true resets the retry counter (document event, probe request).
  function probeWindow(w, freshBudget) {
    const s = stateFor(w);
    if (s.timer !== null) {
      try { w.clearTimeout(s.timer); } catch (e) {}
      s.timer = null;
    }
    if (freshBudget) s.attempts = 0;

    let url;
    try {
      const doc = w.document;
      if (!doc) return;
      url = w.location.href;
      if (!isPrUrl(url)) return; // not (yet) a PR document — e.g. about:blank
      if (doc.readyState === 'complete' && isMerged(doc)) {
        report(true, url); // merged is sticky; stop probing
        return;
      }
    } catch (e) {
      // Dead wrapper (navigated away) or torn-down document: stop quietly.
      try { console.error('[pr-merged-indicator frame] probe failed:', e); } catch {}
      return;
    }

    // Still loading, or header not hydrated yet: retry (bounded).
    s.attempts += 1;
    if (s.attempts > RETRY_MAX) return;
    try {
      s.timer = w.setTimeout(() => probeWindow(w, false), RETRY_MS);
    } catch (e) {}
  }

  // --- wiring (per execution; the closures below die with their document or
  // self-unregister, never accumulate process-wide) ---

  function onDocEvent() {
    // DOMContentLoaded/load/pageshow for the window this execution wired:
    probeWindow(win, true);
  }

  function onProbe() {
    if (!windowAlive()) {
      // This execution's document is gone (a newer execution serves the
      // current one): stop occupying the listener lists.
      unregister();
      return;
    }
    // Read `content` dynamically — the document may differ from the one this
    // execution was wired for if this is the first-load race window.
    probeWindow(content, true);
  }

  function onTeardown() {
    unregister();
  }

  function unregister() {
    clearWindowState(win);
    try { clearWindowState(content); } catch (e) {}
    try { removeMessageListener(PROBE_MESSAGE_NAME, onProbe); } catch (e) {}
    try { removeMessageListener(TEARDOWN_MESSAGE_NAME, onTeardown); } catch (e) {}
    try { win.removeEventListener('DOMContentLoaded', onDocEvent, true); } catch (e) {}
    try { win.removeEventListener('load', onDocEvent, true); } catch (e) {}
    try { win.removeEventListener('pageshow', onDocEvent, true); } catch (e) {}
  }

  addMessageListener(PROBE_MESSAGE_NAME, onProbe);
  addMessageListener(TEARDOWN_MESSAGE_NAME, onTeardown);

  // Probe again when the page finishes loading or is restored from bfcache —
  // the frame script may run before the page has finished loading.
  win.addEventListener('DOMContentLoaded', onDocEvent, true);
  win.addEventListener('load', onDocEvent, true);
  win.addEventListener('pageshow', onDocEvent, true);

  // Initial probe for the document already present at load time. `content` is
  // read dynamically: if the browser's load hasn't created the PR document
  // yet (about:blank), this gives up quietly and the probe request / next
  // injection re-arms on the real document.
  probeWindow(content, true);
})();
