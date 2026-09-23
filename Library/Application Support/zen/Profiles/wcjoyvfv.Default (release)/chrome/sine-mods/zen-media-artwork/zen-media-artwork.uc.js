/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Add Media Session artwork to Zen's native media cards. This is kept as a
 * userChrome script because regular web extensions cannot access browser
 * chrome or the ChromeOnly MediaController API.
 */
(() => {
  "use strict";

  if (window.__zenMediaArtwork) {
    return;
  }

  const ARTWORK_CLASS = "zen-media-artwork-mod";
  const ARTWORK_VISIBLE_ATTRIBUTE = "zen-media-artwork-visible";

  let started = false;
  let refreshTimer = null;
  let startTimer = null;
  let mediaBar = null;
  let observer = null;
  const controllerListeners = new Map();

  function metadataFor(controller) {
    try {
      return controller.getMetadata();
    } catch {
      return null;
    }
  }

  function metadataKey(metadata) {
    return `${metadata?.title || ""}\u0000${metadata?.artist || ""}`;
  }

  function artworkSource(metadata) {
    const image = Array.from(metadata?.artwork || []).find(
      candidate => typeof candidate?.src === "string" && candidate.src,
    );
    return image?.src || "";
  }

  function untrackController(controller) {
    const listeners = controllerListeners.get(controller);
    if (!listeners) {
      return;
    }

    try {
      controller.removeEventListener("metadatachange", listeners.onMetadata);
      controller.removeEventListener("deactivated", listeners.onDeactivated);
    } catch {
      // The controller may already have been destroyed.
    }
    controllerListeners.delete(controller);
  }

  function trackController(controller) {
    if (!controller || controllerListeners.has(controller)) {
      return;
    }

    const onMetadata = () => scheduleRefresh();
    const onDeactivated = () => {
      untrackController(controller);
      scheduleRefresh();
    };

    try {
      controller.addEventListener("metadatachange", onMetadata);
      controller.addEventListener("deactivated", onDeactivated);
      controllerListeners.set(controller, { onMetadata, onDeactivated });
    } catch {
      // The controller can disappear between tab enumeration and setup.
    }
  }

  function activeControllers() {
    const controllers = new Set();

    for (const tab of window.gBrowser?.tabs || []) {
      try {
        const controller = tab.linkedBrowser?.browsingContext?.mediaController;
        if (controller?.isActive) {
          controllers.add(controller);
        }
      } catch {
        // Ignore tabs that are being closed or discarded.
      }
    }

    try {
      const frontController = window.gZenMediaController?.frontCard?.controller;
      if (frontController) {
        controllers.add(frontController);
      }
    } catch {
      // The media controller may not be initialized yet.
    }

    return controllers;
  }

  function ensureArtworkElement(card) {
    let image = card.querySelector(`.${ARTWORK_CLASS}`);
    if (image) {
      return image;
    }

    const main = Array.from(card.children).find(child =>
      child.classList.contains("zen-media-main-vbox"),
    );
    if (!main) {
      return null;
    }

    image = document.createXULElement("image");
    image.classList.add(ARTWORK_CLASS);
    image.setAttribute("hidden", "true");
    image.setAttribute("role", "presentation");
    image.addEventListener("error", () => {
      image.hidden = true;
      card.removeAttribute(ARTWORK_VISIBLE_ATTRIBUTE);
    });
    card.insertBefore(image, main);
    return image;
  }

  function clearArtwork(card, image) {
    image.hidden = true;
    image.removeAttribute("src");
    image.removeAttribute("tooltiptext");
    card.removeAttribute(ARTWORK_VISIBLE_ATTRIBUTE);
  }

  function updateArtwork(card, image, metadata) {
    const source = artworkSource(metadata);
    if (!source) {
      clearArtwork(card, image);
      return;
    }

    if (image.getAttribute("src") !== source) {
      image.hidden = true;
      image.setAttribute("src", source);
    }
    image.setAttribute(
      "tooltiptext",
      metadata?.album || "Album artwork",
    );
    image.hidden = false;
    card.setAttribute(ARTWORK_VISIBLE_ATTRIBUTE, "true");
  }

  function cardMetadataKey(card) {
    return metadataKey({
      title: card.querySelector(".zen-media-title")?.textContent,
      artist: card.querySelector(".zen-media-artist")?.textContent,
    });
  }

  function refreshCards() {
    refreshTimer = null;
    if (!mediaBar) {
      return;
    }

    const cards = Array.from(mediaBar.querySelectorAll(".zen-media-card"));
    const controllers = activeControllers();
    const entries = [];

    for (const controller of controllers) {
      trackController(controller);
      const metadata = metadataFor(controller);
      if (metadata) {
        entries.push({
          controller,
          key: metadataKey(metadata),
          metadata,
        });
      }
    }

    for (const controller of Array.from(controllerListeners.keys())) {
      if (!controllers.has(controller)) {
        untrackController(controller);
      }
    }

    const usedControllers = new Set();
    let frontCard = null;
    try {
      frontCard = window.gZenMediaController?.frontCard;
    } catch {
      // The media controller may be between tab-selection updates.
    }

    for (const card of cards) {
      const image = ensureArtworkElement(card);
      if (!image) {
        continue;
      }

      let entry = null;
      if (frontCard?.element === card && frontCard.controller) {
        entry = entries.find(
          candidate => candidate.controller === frontCard.controller,
        );
      }

      if (!entry) {
        entry = entries.find(
          candidate =>
            !usedControllers.has(candidate.controller) &&
            candidate.key === cardMetadataKey(card),
        );
      }

      if (!entry) {
        clearArtwork(card, image);
        continue;
      }

      usedControllers.add(entry.controller);
      updateArtwork(card, image, entry.metadata);
    }
  }

  function scheduleRefresh() {
    if (refreshTimer !== null) {
      return;
    }
    refreshTimer = setTimeout(refreshCards, 0);
  }

  function onTabAttrModified(event) {
    if (event.detail?.changed?.includes("soundplaying")) {
      scheduleRefresh();
    }
  }

  function stop() {
    clearTimeout(refreshTimer);
    clearTimeout(startTimer);
    refreshTimer = null;
    startTimer = null;

    if (!started) {
      delete window.__zenMediaArtwork;
      return;
    }

    started = false;
    observer?.disconnect();
    observer = null;

    window.removeEventListener("TabSelect", scheduleRefresh);
    window.removeEventListener("TabClose", scheduleRefresh);
    window.removeEventListener("TabAttrModified", onTabAttrModified);

    for (const controller of Array.from(controllerListeners.keys())) {
      untrackController(controller);
    }

    for (const card of mediaBar?.querySelectorAll(".zen-media-card") || []) {
      card.querySelector(`.${ARTWORK_CLASS}`)?.remove();
      card.removeAttribute(ARTWORK_VISIBLE_ATTRIBUTE);
    }

    mediaBar = null;
    delete window.__zenMediaArtwork;
  }

  function start() {
    if (started) {
      return;
    }

    mediaBar = document.getElementById("zen-media-controls-toolbar");
    if (!window.gBrowser || !window.gZenMediaController || !mediaBar) {
      startTimer = setTimeout(start, 100);
      return;
    }

    started = true;
    observer = new MutationObserver(scheduleRefresh);
    observer.observe(mediaBar, { childList: true, subtree: true });
    window.addEventListener("TabSelect", scheduleRefresh);
    window.addEventListener("TabClose", scheduleRefresh);
    window.addEventListener("TabAttrModified", onTabAttrModified);
    refreshCards();
  }

  window.__zenMediaArtwork = { refresh: scheduleRefresh };
  window.addEventListener("unload", stop, { once: true });

  if (document.readyState === "loading") {
    window.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
