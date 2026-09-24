// PR Merged Indicator — frame script
// Loaded into the content process via mm.loadFrameScript.
// Runs layered merge detection against the PR page DOM (which is where GitHub
// reports the state) and pushes the result to the chrome process via sendAsyncMessage.
//
// Lifecycle:
//   - The persistent singleton (message listeners, retry state) is stored on the
//     frame-script global `globalThis`, installed ONCE per content process. It
//     survives loadFrameScript re-execution, which chrome triggers on every
//     navigation and tab select.
//   - A per-document probe (retry state) is rebuilt on each (re)load and torn
//     down cleanly first. Anchoring the install guard on `globalThis` (process
//     lifetime) instead of `content` (per-document) is what prevents listener
//     accumulation — `content` is a fresh window object after every cross-document
//     navigation.
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

  // Already installed in this frame-script scope? A re-load means chrome wants a
  // fresh probe for the (possibly new) document — rebuild per-document state and
  // return. The heavy persistent listeners below are NOT re-registered.
  if (globalThis.__prMergedIndicatorFrame) {
    try { globalThis.__prMergedIndicatorFrame.reload(); }
    catch (e) { try { console.error('[pr-merged-indicator frame] reload failed:', e); } catch {} }
    return;
  }

  const PR_RE = /^https?:\/\/github\.com\/([^/\s]+)\/([^/\s]+)\/pull\/(\d+)/i;

  function isPrUrl(url) {
    return PR_RE.test(url || '');
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

  // Per-document probe state, rebuilt on each (re)load.
  let probeTimer = null;
  let attempts = 0;

  function clearProbeTimer() {
    if (probeTimer !== null) {
      try { content.clearTimeout(probeTimer); } catch (e) {}
      probeTimer = null;
    }
  }

  function report(merged) {
    try {
      sendAsyncMessage(RESULT_MESSAGE_NAME, {
        href: content.location.href,
        merged,
      });
    } catch (e) {
      try { console.error('[pr-merged-indicator frame] report failed:', e); } catch {}
    }
  }

  function probe() {
    clearProbeTimer();
    try {
      const doc = content.document;
      if (!doc) return;

      const url = content.location.href;
      if (!isPrUrl(url)) return;

      if (doc.readyState === 'complete' && isMerged(doc)) {
        report(true);
        return; // merged is sticky; stop probing
      }
    } catch (e) {
      try { console.error('[pr-merged-indicator frame] probe failed:', e); } catch {}
      return;
    }

    // Still loading, or header not hydrated yet: retry (bounded).
    attempts += 1;
    if (attempts > RETRY_MAX) {
      clearProbeTimer();
      return;
    }
    clearProbeTimer();
    probeTimer = content.setTimeout(probe, RETRY_MS);
  }

  // Per-document probe state, rebuilt on each (re)load.
  function resetPerDocument() {
    clearProbeTimer();
    attempts = 0;
  }

  globalThis.__prMergedIndicatorFrame = {
    probe,
    reload() {
      resetPerDocument();
      probe();
    },
  };

  function onDocEvent() {
    resetPerDocument();
    probe();
  }

  function onProbe() {
    resetPerDocument();
    probe();
  }

  function onTeardown() {
    clearProbeTimer();
    try { content.removeEventListener('DOMContentLoaded', onDocEvent); } catch {}
    try { content.removeEventListener('load', onDocEvent); } catch {}
    try { removeMessageListener(PROBE_MESSAGE_NAME, onProbe); } catch {}
    try { removeMessageListener(TEARDOWN_MESSAGE_NAME, onTeardown); } catch {}
    try { delete globalThis.__prMergedIndicatorFrame; } catch {}
  }

  addMessageListener(PROBE_MESSAGE_NAME, onProbe);
  addMessageListener(TEARDOWN_MESSAGE_NAME, onTeardown);

  // Probe again when the page finishes loading or is restored from bfcache —
  // the frame script may run before the page has finished loading.
  content.addEventListener('DOMContentLoaded', onDocEvent, true);
  content.addEventListener('load', onDocEvent, true);
  content.addEventListener('pageshow', onDocEvent, true);

  // Initial probe for the document already present at load time.
  probe();
})();
