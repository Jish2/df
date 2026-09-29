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
// Detection (v1.6.0) reads ONLY the page's own PR state, never the state of
// other PRs referenced in the timeline. GitHub's PR conversation timeline
// cross-references related PRs with their own merged/open badges — a draft
// PR that cross-references a merged one (e.g. sibling PRs for the same
// ticket) renders a fully-styled merged badge on its page, which made every
// document-global "is there a merged badge anywhere?" check (v1.5.0 and
// earlier) false-positive. The layers, in order:
//   1. Embedded react-app JSON payload: the PR record whose number matches
//      the URL's PR number carries "state":"MERGED"/"OPEN"/"DRAFT". Number
//      matching is required because any document-global match can pick up
//      records for other PRs (cross-references).
//   2. Header StateLabel (React era, server-rendered): the PR's own badge is
//      a [data-component="StateLabel"] with data-status="pullMerged" (or
//      draft / pullOpened / pullClosed). Cross-referenced PR cards render
//      legacy .State spans, never StateLabel, and StateLabels inside
//      ref-pullrequest containers are excluded, so this can only be the
//      page's own state — any answer here is authoritative.
//   3. Legacy Primer badge fallback: a big (non-small) .State--merged /
//      title="Status: Merged" badge NOT inside a cross-reference container.
//      Cross-ref badges always carry State--small and sit next to
//      [id^="ref-pullrequest-"]; the page header's own badge does not.
//
// Each layer returns one of: 'merged', 'open' (authoritative NOT merged —
// also used to heal badges applied by an older false positive), or 'unknown'
// (give no answer; keep retrying while the budget lasts).

(() => {
  'use strict';

  const RESULT_MESSAGE_NAME = 'pr-merged-indicator:result';
  const PROBE_MESSAGE_NAME = 'pr-merged-indicator:probe';
  const TEARDOWN_MESSAGE_NAME = 'pr-merged-indicator:teardown';
  const RETRY_MS = 750;  // retry cadence while GitHub's React header hydrates
  const RETRY_MAX = 12;  // ~9s of bounded retries, then give up (stays unmarked)

  const PR_RE = /^https?:\/\/github\.com\/([^/\s]+)\/([^/\s]+)\/pull\/(\d+)/i;

  function isPrUrl(url) {
    return PR_RE.test(url || '');
  }

  function prNumber(url) {
    const m = PR_RE.exec(url || '');
    return m ? m[3] : null;
  }

  // The PR's own state from the react-app embedded JSON payload, matched by
  // PR number. data is a parsed <script type="application/json"> block.
  // Returns the state string ('MERGED'/'OPEN'/'DRAFT'/...) or null when this
  // block doesn't carry a number-matching PR record.
  function prStateFromPayload(data, number) {
    if (!data || typeof data !== 'object') return null;
    const root = (data && typeof data.payload === 'object' && data.payload) || data;

    // Canonical routes first — the page's own PR record.
    const routes = [
      'pullRequestsLayoutRoute',
      'pullRequestsChangesRoute',
      'pullRequestsConversationsRoute',
      'pullRequestsFilesRoute',
      'pullRequestsCommitsRoute',
    ];
    for (const r of routes) {
      const pr = root && root[r] && root[r].pullRequest;
      if (
        pr &&
        typeof pr === 'object' &&
        number !== null &&
        String(pr.number) === String(number) &&
        typeof pr.state === 'string'
      ) {
        return pr.state;
      }
    }

    // Fallback: any pullRequest record with a matching number (guards
    // against cross-referenced PR records, which carry other numbers).
    let found = null;
    (function walk(o) {
      if (found || !o || typeof o !== 'object') return;
      if (
        o.pullRequest &&
        typeof o.pullRequest === 'object' &&
        number !== null &&
        String(o.pullRequest.number) === String(number) &&
        typeof o.pullRequest.state === 'string'
      ) {
        found = o.pullRequest.state;
        return;
      }
      for (const k of Object.keys(o)) walk(o[k]);
    })(data);
    return found;
  }

  /**
   * Layered own-state detection against the PR page document.
   * Returns 'merged', 'open' (authoritative not-merged), or 'unknown'.
   */
  function detectState(doc, number) {
    // 1) Embedded react-app JSON payload, matched by PR number. The number
    //    match is the identity anchor: it can never speak for another PR.
    const jsonScripts = doc.querySelectorAll('script[type="application/json"]');
    for (const el of jsonScripts) {
      let data;
      try {
        data = JSON.parse(el.textContent || '');
      } catch (e) {
        continue;
      }
      const state = prStateFromPayload(data, number);
      if (state === 'MERGED') return 'merged';
      if (state) return 'open'; // DRAFT/OPEN/CLOSED...: authoritative
    }

    // 2) React-era header StateLabel (server-rendered). Cross-referenced PR
    //    cards in the timeline use legacy .State spans, never StateLabel, so
    //    a StateLabel is normally the page's own badge; one inside a
    //    ref-pullrequest container (if GitHub ever renders them there) is
    //    excluded so it can never speak for the page itself.
    for (const label of doc.querySelectorAll('[data-component="StateLabel"][data-status]')) {
      if (label.closest && label.closest('[id^="ref-pullrequest-"]')) continue;
      const status = label.getAttribute('data-status') || '';
      if (status === 'pullMerged' || status === 'merged') return 'merged';
      if (status === 'draft' || status === 'pullOpened' || status === 'pullClosed' || status === 'closed') {
        return 'open';
      }
      // Unknown status value: fall through to the legacy layer instead of
      // guessing.
    }

    // 3) Legacy Primer badge fallback — only the page header's own badge.
    //    Cross-referenced PR cards render their badges as siblings of the
    //    [id^="ref-pullrequest-"] container with the State--small modifier;
    //    either marker disqualifies a badge from being the page's own.
    const badge = doc.querySelector('.State--merged, [title="Status: Merged"]');
    if (badge) {
      if (badge.closest && badge.closest('[id^="ref-pullrequest-"]')) return 'unknown';
      if (badge.classList && badge.classList.contains('State--small')) return 'unknown';
      return 'merged';
    }

    return 'unknown';
  }

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

  function report(merged, authoritative, href) {
    try {
      sendAsyncMessage(RESULT_MESSAGE_NAME, {
        href,
        merged,
        authoritative: !!authoritative,
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
      if (doc.readyState === 'complete') {
        const state = detectState(doc, prNumber(url));
        if (state === 'merged') {
          report(true, true, url); // own state: authoritative merged
          return;
        }
        if (state === 'open') {
          // Authoritative not-merged: heals badges applied by the v1.5.0
          // cross-reference false positive (sticky marks only survive real
          // merges). Never sent for a state we merely failed to read.
          report(false, true, url);
          return;
        }
        // 'unknown': fall through to the bounded retry loop.
      }
    } catch (e) {
      // Dead wrapper (navigated away) or torn-down document: stop quietly.
      try { console.error('[pr-merged-indicator frame] probe failed:', e); } catch {}
      return;
    }

    // Still loading, or state not readable yet: retry (bounded).
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
