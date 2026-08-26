/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Zen Inbox behavior layer.
 *
 * This file is intentionally separate from the Zen stylesheet mod. It needs
 * privileged browser-chrome access to observe tabs, persist metadata, and
 * update the tab context menu.
 */
(() => {
  "use strict";

  if (window.__zenInbox) {
    return;
  }

  const { SessionStore } = ChromeUtils.importESModule(
    "resource:///modules/sessionstore/SessionStore.sys.mjs",
  );

  const TAB_STATE_KEY = "zen-inbox-state";
  const INBOX_ATTRIBUTE = "zen-inbox";
  const URGENCY_ATTRIBUTE = "zen-inbox-urgency";
  const AGE_ATTRIBUTE = "zen-inbox-age";
  const ORDER_PROPERTY = "--zen-inbox-order";
  const AGE_COLOR_PROPERTY = "--zen-inbox-age-color";
  const HEADER_CLASS = "zen-inbox-header";
  const AGE_CLASS = "zen-inbox-age";
  const PINNED_SECTION_CLASS = "zen-workspace-pinned-tabs-section";
  const NORMAL_SECTION_CLASS = "zen-workspace-normal-tabs-section";
  const SEPARATOR_CLASS = "pinned-tabs-container-separator";
  const COLLAPSED_ATTRIBUTE = "zen-inbox-collapsed";
  const ANIMATING_ATTRIBUTE = "zen-inbox-animating";
  const PRESERVE_COLLAPSE_ATTRIBUTE = "zen-inbox-preserve-collapse";
  const EXPOSES_PINNED_STATE_ATTRIBUTE = "zen-inbox-exposes-pinned-state";
  const HEADER_READY_ATTRIBUTE = "zen-inbox-header-ready";
  const DRAGOVER_ATTRIBUTE = "zen-inbox-dragover";

  const ENABLED_PREF = "zen.inbox.enabled";
  const GREEN_HOURS_PREF = "zen.inbox.green-hours";
  const YELLOW_HOURS_PREF = "zen.inbox.yellow-hours";
  const ORANGE_HOURS_PREF = "zen.inbox.orange-hours";

  const CONTEXT_SEPARATOR_ID = "context_zen-inbox-separator";
  const CONTEXT_SEND_ID = "context_zen-send-to-inbox";
  const CONTEXT_REMOVE_ID = "context_zen-remove-from-inbox";
  const CONTEXT_RESET_ID = "context_zen-reset-inbox-timer";

  const HOUR_MS = 60 * 60 * 1000;
  const MINUTE_MS = 60 * 1000;
  const EVENT_HANDLERS = [
    ["TabOpen", onTabOpen],
    ["SSTabRestored", onTabRestored],
    ["TabClose", onWorkspaceEvent],
    ["TabMove", onWorkspaceEvent],
    ["TabPinned", onWorkspaceEvent],
    ["TabUnpinned", onWorkspaceEvent],
    ["TabSelect", onWorkspaceEvent],
    ["ZenWorkspacesUIUpdate", onWorkspaceEvent],
    ["ZenWorkspaceDataChanged", onWorkspaceEvent],
    ["AfterWorkspacesSessionRestore", onWorkspaceEvent],
  ];

  let started = false;
  let refreshTimer = null;
  let refreshSoonTimer = null;
  let contextMenu = null;
  let preferenceObserver = null;
  let collapseObserver = null;
  let inboxDragOverHeader = null;

  function isTab(tab) {
    return Boolean(tab && window.gBrowser?.isTab(tab));
  }

  function isInboxCandidate(tab) {
    return (
      isTab(tab) &&
      !tab.pinned &&
      !tab.hasAttribute("zen-essential") &&
      !tab.hasAttribute("zen-empty-tab") &&
      !tab.hasAttribute("zen-glance-tab") &&
      !tab.group
    );
  }

  function getWorkspaceId(tab) {
    return (
      tab.getAttribute("zen-workspace-id") ||
      window.gZenWorkspaces?.activeWorkspace ||
      ""
    );
  }

  function readState(tab) {
    try {
      const value = SessionStore.getCustomTabValue(tab, TAB_STATE_KEY);
      return value ? JSON.parse(value) : null;
    } catch (error) {
      console.warn("Zen Inbox: Could not read tab state", error);
      return null;
    }
  }

  function writeState(tab, state) {
    try {
      SessionStore.setCustomTabValue(tab, TAB_STATE_KEY, JSON.stringify(state));
    } catch (error) {
      console.warn("Zen Inbox: Could not write tab state", error);
    }
  }

  function ensureState(tab) {
    if (!isTab(tab)) {
      return null;
    }

    const now = Date.now();
    const existing = readState(tab);
    const state = existing && typeof existing === "object" ? existing : {};
    let changed = !existing;

    if (!Number.isFinite(state.createdAt)) {
      state.createdAt = now;
      changed = true;
    }

    if (!Number.isFinite(state.ageStartedAt)) {
      state.ageStartedAt = state.createdAt;
      changed = true;
    }

    if (typeof state.inInbox !== "boolean") {
      state.inInbox = false;
      changed = true;
    }

    if (state.inInbox) {
      const workspaceId = getWorkspaceId(tab);
      if (workspaceId && state.workspaceId !== workspaceId) {
        state.workspaceId = workspaceId;
        changed = true;
      }
    }

    if (changed) {
      writeState(tab, state);
    }

    return state;
  }

  function getThreshold(pref, fallback) {
    let raw;
    try {
      raw = Services.prefs.getStringPref(pref, String(fallback));
    } catch {
      raw = Services.prefs.getIntPref(pref, fallback);
    }
    const value = Number.parseFloat(raw);
    return Number.isFinite(value) ? Math.max(0, value) : fallback;
  }

  function mixColor(from, to, progress) {
    const amount = Math.max(0, Math.min(1, progress));
    const channels = from.map((channel, index) =>
      Math.round(channel + (to[index] - channel) * amount),
    );
    return `rgb(${channels.join(" ")})`;
  }

  function getUrgency(timestamp) {
    const ageHours = Math.max(0, Date.now() - timestamp) / HOUR_MS;
    const greenHours = getThreshold(GREEN_HOURS_PREF, 4);
    const yellowHours = Math.max(
      greenHours,
      getThreshold(YELLOW_HOURS_PREF, 24),
    );
    const orangeHours = Math.max(
      yellowHours,
      getThreshold(ORANGE_HOURS_PREF, 72),
    );
    const colors = {
      green: {
        light: [24, 128, 56],
        dark: [126, 231, 135],
      },
      yellow: {
        light: [135, 85, 0],
        dark: [214, 178, 60],
      },
      orange: {
        light: [145, 65, 5],
        dark: [230, 122, 55],
      },
      red: {
        light: [175, 30, 30],
        dark: [225, 75, 75],
      },
      stale: {
        light: [150, 25, 30],
        dark: [205, 55, 65],
      },
    };

    let name;
    let from;
    let to;
    let progress;

    if (ageHours < greenHours) {
      name = "green";
      from = colors.green;
      to = colors.yellow;
      progress = greenHours ? ageHours / greenHours : 1;
    } else if (ageHours < yellowHours) {
      name = "yellow";
      from = colors.yellow;
      to = colors.orange;
      progress =
        yellowHours === greenHours
          ? 1
          : (ageHours - greenHours) / (yellowHours - greenHours);
    } else if (ageHours < orangeHours) {
      name = "orange";
      from = colors.orange;
      to = colors.red;
      progress =
        orangeHours === yellowHours
          ? 1
          : (ageHours - yellowHours) / (orangeHours - yellowHours);
    } else {
      name = "red";
      from = colors.red;
      to = colors.stale;
      const darkeningWindow = Math.max(1, orangeHours);
      progress = 1 - Math.exp(-(ageHours - orangeHours) / darkeningWindow);
    }

    const light = mixColor(from.light, to.light, progress);
    const dark = mixColor(from.dark, to.dark, progress);
    return {
      color: `light-dark(${light}, ${dark})`,
      name,
    };
  }

  function formatAge(timestamp) {
    const minutes = Math.max(
      0,
      Math.floor((Date.now() - timestamp) / MINUTE_MS),
    );

    if (minutes < 60) {
      return `${minutes}m`;
    }

    const hours = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours}h`;
    }

    const days = Math.floor(hours / 24);
    if (days < 30) {
      return `${days}d`;
    }

    const months = Math.floor(days / 30);
    return `${months}mo`;
  }

  function formatTimestamp(timestamp) {
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(timestamp));
  }

  function inboxTabsInSection(section) {
    return Array.from(section?.children || []).filter((child) =>
      child.matches?.(`.tabbrowser-tab[${INBOX_ATTRIBUTE}="true"]`),
    );
  }

  function cleanupInboxAnimation(tabs) {
    for (const tab of tabs) {
      tab.style.removeProperty("height");
      tab.style.removeProperty("opacity");
    }
  }

  async function setInboxCollapsed(section, collapsed) {
    if (
      !section ||
      section.hasAttribute(ANIMATING_ATTRIBUTE) ||
      section.hasAttribute(COLLAPSED_ATTRIBUTE) === collapsed
    ) {
      return;
    }

    const header = section.querySelector(`.${HEADER_CLASS}`);
    if (header) {
      header.setAttribute("aria-expanded", String(!collapsed));
    }

    const tabs = inboxTabsInSection(section);
    const shouldAnimate =
      tabs.length > 0 &&
      !window.matchMedia("(prefers-reduced-motion: reduce)").matches &&
      typeof window.gZenUIManager?.motion?.animate === "function";

    section.setAttribute(
      ANIMATING_ATTRIBUTE,
      collapsed ? "collapsing" : "expanding",
    );

    if (!collapsed) {
      section.removeAttribute(COLLAPSED_ATTRIBUTE);
    }

    gBrowser.tabContainer._invalidateCachedVisibleTabs();

    try {
      if (shouldAnimate) {
        if (!collapsed) {
          for (const tab of tabs) {
            tab.style.height = "0px";
            tab.style.opacity = "0";
          }
        }

        await Promise.allSettled(
          tabs.map((tab) =>
            window.gZenUIManager.motion.animate(
              tab,
              collapsed
                ? { opacity: [1, 0], height: ["auto", 0] }
                : { opacity: "", height: "" },
              { duration: 0.12, ease: "easeInOut" },
            ),
          ),
        );
      }

      section.toggleAttribute(COLLAPSED_ATTRIBUTE, collapsed);
    } finally {
      cleanupInboxAnimation(tabs);
      section.removeAttribute(ANIMATING_ATTRIBUTE);
      gBrowser.tabContainer._invalidateCachedVisibleTabs();
    }
  }

  function onInboxHeaderClick(event) {
    if (event.button !== 0) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    const section = event.currentTarget.closest(`.${PINNED_SECTION_CLASS}`);
    setInboxCollapsed(section, !section?.hasAttribute(COLLAPSED_ATTRIBUTE));
  }

  function onInboxHeaderKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    const section = event.currentTarget.closest(`.${PINNED_SECTION_CLASS}`);
    setInboxCollapsed(section, !section?.hasAttribute(COLLAPSED_ATTRIBUTE));
  }

  function getTabDropType() {
    return typeof TAB_DROP_TYPE === "string"
      ? TAB_DROP_TYPE
      : "application/x-moz-tabbrowser-tab";
  }

  function draggedTabsFromEvent(event) {
    const dataTransfer = event.dataTransfer;
    if (!dataTransfer?.mozGetDataAt) {
      return [];
    }

    const dropType = getTabDropType();
    try {
      const types = Array.from(dataTransfer.mozTypesAt?.(0) || []);
      if (!types.includes(dropType)) {
        return [];
      }

      const draggedTab = dataTransfer.mozGetDataAt(dropType, 0);
      if (!isTab(draggedTab) || draggedTab.documentGlobal !== window) {
        return [];
      }

      const movingTabs =
        draggedTab._dragData?.movingTabs ||
        (draggedTab.multiselected
          ? window.gBrowser.selectedTabs
          : [draggedTab]);
      return [...new Set(movingTabs)].filter(
        (tab) => isTab(tab) && tab.documentGlobal === window,
      );
    } catch (error) {
      console.warn("Zen Inbox: Could not inspect dragged tabs", error);
      return [];
    }
  }

  function inboxDropHeader(event) {
    const target = event.target?.closest?.(
      `.${HEADER_CLASS}, .tabbrowser-tab[${INBOX_ATTRIBUTE}="true"]`,
    );
    const section = target?.closest?.(`.${PINNED_SECTION_CLASS}`);
    return section?.querySelector(`.${HEADER_CLASS}`) || null;
  }

  function normalDropSection(event) {
    const target = event.target;
    const normalSection = target?.closest?.(`.${NORMAL_SECTION_CLASS}`);
    if (normalSection) {
      return normalSection;
    }

    const tabsWrapper = target?.closest?.("#zen-tabs-wrapper");
    if (
      !tabsWrapper ||
      target.closest?.(
        `.${PINNED_SECTION_CLASS}, .zen-essentials-container`,
      )
    ) {
      return null;
    }
    return tabsWrapper.querySelector(`.${NORMAL_SECTION_CLASS}`);
  }

  function setInboxDragOverHeader(header) {
    if (inboxDragOverHeader === header) {
      return;
    }
    inboxDragOverHeader?.removeAttribute(DRAGOVER_ATTRIBUTE);
    inboxDragOverHeader = header;
    inboxDragOverHeader?.setAttribute(DRAGOVER_ATTRIBUTE, "true");
  }

  function clearInboxDragOver() {
    setInboxDragOverHeader(null);
  }

  function clearNativeDragOverVisuals() {
    window.gBrowser?.tabContainer?.tabDragAndDrop?.clearDragOverVisuals?.();
    window.gZenPinnedTabManager?.removeTabContainersDragoverClass?.();
  }

  function onInboxDragOver(event) {
    const header = inboxDropHeader(event);
    if (!header) {
      clearInboxDragOver();
      return;
    }

    const draggedTabs = draggedTabsFromEvent(event);
    if (!draggedTabs.length) {
      clearInboxDragOver();
      return;
    }

    const candidates = draggedTabs.filter(
      (tab) => isInboxCandidate(tab) && !ensureState(tab)?.inInbox,
    );
    event.preventDefault();
    event.stopImmediatePropagation();
    clearNativeDragOverVisuals();

    try {
      event.dataTransfer.dropEffect = candidates.length ? "move" : "none";
    } catch {}
    setInboxDragOverHeader(candidates.length ? header : null);
  }

  function onInboxDrop(event) {
    const header = inboxDropHeader(event);
    const draggedTabs = draggedTabsFromEvent(event);
    if (!draggedTabs.length) {
      return;
    }

    if (!header) {
      if (!normalDropSection(event)) {
        return;
      }

      const inboxTabs = draggedTabs.filter(
        (tab) => isInboxCandidate(tab) && ensureState(tab)?.inInbox,
      );
      if (inboxTabs.length) {
        clearInboxDragOver();
        setInbox(inboxTabs, false);
      }
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();
    clearNativeDragOverVisuals();
    clearInboxDragOver();

    const candidates = draggedTabs.filter(
      (tab) => isInboxCandidate(tab) && !ensureState(tab)?.inInbox,
    );
    if (!candidates.length) {
      return;
    }

    const section = header.closest(`.${PINNED_SECTION_CLASS}`);
    if (section?.hasAttribute(COLLAPSED_ATTRIBUTE)) {
      setInboxCollapsed(section, false);
    }
    setInbox(candidates, true);
  }

  function onInboxDragEnd() {
    clearInboxDragOver();
  }

  function prepareHeader(header) {
    header.classList.add("tab-group-label-container", "zen-drop-target");
    header.setAttribute("role", "button");
    header.setAttribute("tabindex", "0");
    header.setAttribute("pack", "center");

    if (!header.querySelector(".zen-inbox-header-icon-stack")) {
      const iconStack = document.createXULElement("stack");
      iconStack.classList.add(
        "zen-inbox-header-icon-stack",
        "zen-current-workspace-indicator-stack",
        "tab-group-folder-icon",
      );

      const chevron = document.createXULElement("image");
      chevron.classList.add(
        "zen-inbox-header-chevron",
        "zen-current-workspace-indicator-chevron",
      );

      const icon = document.createXULElement("image");
      icon.classList.add(
        "zen-inbox-header-icon",
        "zen-current-workspace-indicator-icon",
      );

      iconStack.append(chevron, icon);
      header.prepend(iconStack);
    }

    if (!header.querySelector(".zen-inbox-header-label")) {
      const label = document.createXULElement("label");
      label.classList.add("zen-inbox-header-label", "tab-group-label");
      label.setAttribute("role", "button");
      label.setAttribute("value", "Inbox");
      header.appendChild(label);
    }

    if (!header.querySelector(".zen-inbox-header-count")) {
      const count = document.createXULElement("label");
      count.classList.add("zen-inbox-header-count");
      count.setAttribute("value", "0");
      header.appendChild(count);
    }

    if (!header.hasAttribute(HEADER_READY_ATTRIBUTE)) {
      header.addEventListener("click", onInboxHeaderClick);
      header.addEventListener("keydown", onInboxHeaderKeyDown);
      header.setAttribute(HEADER_READY_ATTRIBUTE, "true");
    }
  }

  function ensureHeader(section) {
    let header = Array.from(section.children).find((child) =>
      child.classList.contains(HEADER_CLASS),
    );
    if (!header) {
      header = section.parentElement?.querySelector(`.${HEADER_CLASS}`);
    }
    if (header) {
      prepareHeader(header);
      const separator = section.querySelector(`.${SEPARATOR_CLASS}`);
      const firstInboxTab = Array.from(section.children).find((child) =>
        child.matches?.(`.tabbrowser-tab[${INBOX_ATTRIBUTE}="true"]`),
      );
      const insertionPoint = firstInboxTab || separator;
      if (insertionPoint && header !== insertionPoint.previousElementSibling) {
        section.insertBefore(header, insertionPoint);
      }
      return header;
    }

    header = document.createXULElement("hbox");
    header.classList.add(HEADER_CLASS);
    header.setAttribute("align", "center");
    header.setAttribute("aria-label", "Inbox");
    prepareHeader(header);
    const separator = section.querySelector(`.${SEPARATOR_CLASS}`);
    const firstInboxTab = Array.from(section.children).find((child) =>
      child.matches?.(`.tabbrowser-tab[${INBOX_ATTRIBUTE}="true"]`),
    );
    const insertionPoint = firstInboxTab || separator;
    if (insertionPoint) {
      section.insertBefore(header, insertionPoint);
    } else {
      section.appendChild(header);
    }
    return header;
  }

  function updateHeader(section, count) {
    const header = ensureHeader(section);
    header.hidden = count === 0;
    header.setAttribute(
      "aria-label",
      `Inbox, ${count} tab${count === 1 ? "" : "s"}`,
    );
    header.setAttribute(
      "aria-expanded",
      String(
        section.getAttribute(ANIMATING_ATTRIBUTE) !== "collapsing" &&
          !section.hasAttribute(COLLAPSED_ATTRIBUTE),
      ),
    );
    header
      .querySelector(".zen-inbox-header-count")
      .setAttribute("value", String(count));
  }

  function ensureAgeLabel(tab) {
    const labelContainer = tab.querySelector(".tab-label-container");
    const tabContent = tab.querySelector(".tab-content");
    if (!labelContainer || !tabContent) {
      return null;
    }

    let label = tab.querySelector(`.${AGE_CLASS}`);
    if (!label) {
      label = document.createXULElement("label");
      label.classList.add(AGE_CLASS);
      label.setAttribute("aria-hidden", "true");
    }

    if (
      label.parentElement !== tabContent ||
      label.previousElementSibling !== labelContainer
    ) {
      tabContent.insertBefore(label, labelContainer.nextElementSibling);
    }
    return label;
  }

  function clearTabPresentation(tab) {
    tab.removeAttribute(INBOX_ATTRIBUTE);
    tab.removeAttribute(URGENCY_ATTRIBUTE);
    tab.removeAttribute(AGE_ATTRIBUTE);
    tab.style.removeProperty(ORDER_PROPERTY);
    tab.style.removeProperty(AGE_COLOR_PROPERTY);
    tab.querySelector(`.${AGE_CLASS}`)?.remove();
  }

  function updateTabPresentation(tab, state) {
    if (!state?.inInbox || !isInboxCandidate(tab)) {
      clearTabPresentation(tab);
      return;
    }

    const age = formatAge(state.ageStartedAt);
    const urgency = getUrgency(state.ageStartedAt);
    const label = ensureAgeLabel(tab);

    tab.setAttribute(INBOX_ATTRIBUTE, "true");
    tab.setAttribute(URGENCY_ATTRIBUTE, urgency.name);
    tab.setAttribute(AGE_ATTRIBUTE, age);
    tab.style.removeProperty(ORDER_PROPERTY);
    tab.style.setProperty(AGE_COLOR_PROPERTY, urgency.color);

    if (label) {
      label.setAttribute("value", age);
      label.setAttribute(
        "tooltiptext",
        `In Inbox for ${age}, since ${formatTimestamp(state.ageStartedAt)}`,
      );
    }
  }

  function workspaceSections() {
    if (!window.gZenWorkspaces?.getWorkspaces) {
      return [];
    }

    return window.gZenWorkspaces
      .getWorkspaces()
      .map((workspace) =>
        window.gZenWorkspaces.workspaceElement(workspace.uuid),
      )
      .filter(Boolean);
  }

  function getPinnedSection(workspace) {
    return workspace.querySelector(`.${PINNED_SECTION_CLASS}`);
  }

  function getNormalSection(workspace) {
    return workspace.querySelector(`.${NORMAL_SECTION_CLASS}`);
  }

  function workspaceHasInboxTabs(workspaceId) {
    return gBrowser.tabs.some(
      (tab) =>
        tab.getAttribute("zen-workspace-id") === workspaceId &&
        isInboxCandidate(tab) &&
        ensureState(tab)?.inInbox,
    );
  }

  function syncWorkspaceCollapse(workspace) {
    const pinnedSection = getPinnedSection(workspace);
    if (!pinnedSection) {
      return;
    }

    const hasInbox =
      Services.prefs.getBoolPref(ENABLED_PREF, true) &&
      workspaceHasInboxTabs(workspace.id);
    const exposesPinnedState = workspace.hasAttribute(
      EXPOSES_PINNED_STATE_ATTRIBUTE,
    );

    if (hasInbox) {
      // Zen only enables the parent space's collapse affordance when it sees
      // native pinned tabs. Inbox tabs stay unpinned, so expose the same state
      // while Inbox has items without changing their tab model.
      workspace.setAttribute("haspinnedtabs", "true");
      workspace.setAttribute(EXPOSES_PINNED_STATE_ATTRIBUTE, "true");
    } else if (exposesPinnedState) {
      workspace.removeAttribute(EXPOSES_PINNED_STATE_ATTRIBUTE);
      if (
        !Array.from(pinnedSection.children).some(
          (child) => isTab(child) && child.pinned,
        )
      ) {
        workspace.removeAttribute("haspinnedtabs");
        workspace.collapsiblePins.collapsed = false;
      }
    }

    const collapsed = workspace.hasAttribute("collapsedpinnedtabs");
    if (collapsed && hasInbox) {
      workspace.setAttribute(PRESERVE_COLLAPSE_ATTRIBUTE, "true");
      pinnedSection.removeAttribute("hidden");
    } else {
      workspace.removeAttribute(PRESERVE_COLLAPSE_ATTRIBUTE);
      if (collapsed) {
        pinnedSection.setAttribute("hidden", "true");
      }
    }
  }

  function observeWorkspaceCollapse() {
    collapseObserver?.disconnect();
    collapseObserver = new MutationObserver((records) => {
      const workspaces = new Set();
      for (const record of records) {
        const workspace =
          record.target.closest?.("zen-workspace") ||
          record.target.parentElement?.closest("zen-workspace");
        if (workspace) {
          workspaces.add(workspace);
        }
      }
      for (const workspace of workspaces) {
        syncWorkspaceCollapse(workspace);
      }
    });

    for (const workspace of workspaceSections()) {
      const pinnedSection = getPinnedSection(workspace);
      collapseObserver.observe(workspace, {
        attributeFilter: ["collapsedpinnedtabs"],
        attributes: true,
      });
      if (pinnedSection) {
        collapseObserver.observe(pinnedSection, {
          attributeFilter: ["hidden"],
          attributes: true,
        });
      }
      syncWorkspaceCollapse(workspace);
    }
  }

  function moveTabToNormal(tab, workspace) {
    const pinnedSection = getPinnedSection(workspace);
    const normalSection = getNormalSection(workspace);
    if (
      !pinnedSection ||
      !normalSection ||
      tab.parentElement !== pinnedSection
    ) {
      return;
    }

    const periphery = normalSection.querySelector(
      "#tabbrowser-arrowscrollbox-periphery",
    );
    normalSection.insertBefore(tab, periphery || normalSection.lastChild);
  }

  function refreshWorkspace(workspace) {
    const pinnedSection = getPinnedSection(workspace);
    const normalSection = getNormalSection(workspace);
    if (!pinnedSection || !normalSection) {
      return;
    }

    ensureHeader(pinnedSection);
    const separator = pinnedSection.querySelector(`.${SEPARATOR_CLASS}`);
    const workspaceId = workspace.id;
    const inboxTabs = gBrowser.tabs.filter(
      (tab) =>
        tab.getAttribute("zen-workspace-id") === workspaceId &&
        isInboxCandidate(tab) &&
        ensureState(tab)?.inInbox,
    );

    inboxTabs.sort((first, second) => {
      const firstState = ensureState(first);
      const secondState = ensureState(second);
      const ageDifference = firstState.ageStartedAt - secondState.ageStartedAt;
      return ageDifference || first._tPos - second._tPos;
    });

    const inboxSet = new Set(inboxTabs);
    inboxTabs.forEach((tab) => {
      updateTabPresentation(tab, ensureState(tab));
      pinnedSection.insertBefore(tab, separator);
    });

    for (const tab of gBrowser.tabs) {
      if (
        tab.getAttribute("zen-workspace-id") !== workspaceId ||
        !isInboxCandidate(tab)
      ) {
        continue;
      }

      if (inboxSet.has(tab)) {
        continue;
      }

      updateTabPresentation(tab, ensureState(tab));
      moveTabToNormal(tab, workspace);
    }

    updateHeader(pinnedSection, inboxTabs.length);
    syncWorkspaceCollapse(workspace);
  }

  function clearPresentation() {
    for (const tab of gBrowser.tabs) {
      const workspace = tab.parentElement?.closest("zen-workspace");
      const wasInbox = tab.hasAttribute(INBOX_ATTRIBUTE);
      clearTabPresentation(tab);
      if (wasInbox && workspace) {
        moveTabToNormal(tab, workspace);
      }
    }

    for (const workspace of workspaceSections()) {
      const section = getPinnedSection(workspace);
      const header = section?.querySelector(`.${HEADER_CLASS}`);
      if (header) {
        updateHeader(section, 0);
      }
      workspace.removeAttribute(PRESERVE_COLLAPSE_ATTRIBUTE);
      if (workspace.hasAttribute(EXPOSES_PINNED_STATE_ATTRIBUTE)) {
        workspace.removeAttribute(EXPOSES_PINNED_STATE_ATTRIBUTE);
        if (
          !Array.from(section?.children || []).some(
            (child) => isTab(child) && child.pinned,
          )
        ) {
          workspace.removeAttribute("haspinnedtabs");
          workspace.collapsiblePins.collapsed = false;
        }
      }
      if (section && workspace.hasAttribute("collapsedpinnedtabs")) {
        section.setAttribute("hidden", "true");
      }
    }
  }

  function refresh() {
    refreshTimer = null;

    if (!Services.prefs.getBoolPref(ENABLED_PREF, true)) {
      clearPresentation();
      scheduleRefresh();
      return;
    }

    for (const tab of gBrowser.tabs) {
      const state = ensureState(tab);
      if (state?.inInbox && !isInboxCandidate(tab)) {
        state.inInbox = false;
        delete state.workspaceId;
        writeState(tab, state);
        clearTabPresentation(tab);
      }
    }

    for (const workspace of workspaceSections()) {
      refreshWorkspace(workspace);
    }

    observeWorkspaceCollapse();
    gBrowser.tabContainer._invalidateCachedTabs();
    scheduleRefresh();
  }

  function scheduleRefresh() {
    clearTimeout(refreshTimer);
    const delay = MINUTE_MS - (Date.now() % MINUTE_MS) + 100;
    refreshTimer = setTimeout(refresh, delay);
  }

  function refreshSoon() {
    if (refreshSoonTimer) {
      return;
    }
    refreshSoonTimer = setTimeout(() => {
      refreshSoonTimer = null;
      refresh();
    }, 0);
  }

  function contextTabs() {
    const contextTab = window.TabContextMenu?.contextTab;
    if (!isTab(contextTab)) {
      return [];
    }

    const tabs = contextTab.multiselected
      ? [contextTab, ...gBrowser.selectedTabs]
      : [contextTab];
    return [...new Set(tabs)].filter(isTab);
  }

  function createContextMenu() {
    contextMenu = document.getElementById("tabContextMenu");
    if (!contextMenu || contextMenu.querySelector(`#${CONTEXT_SEND_ID}`)) {
      return;
    }

    const separator = document.createXULElement("menuseparator");
    separator.id = CONTEXT_SEPARATOR_ID;

    const send = document.createXULElement("menuitem");
    send.id = CONTEXT_SEND_ID;
    send.setAttribute("label", "Send to Inbox");
    send.addEventListener("command", () => {
      setInbox(contextTabs(), true);
    });

    const remove = document.createXULElement("menuitem");
    remove.id = CONTEXT_REMOVE_ID;
    remove.setAttribute("label", "Remove from Inbox");
    remove.addEventListener("command", () => {
      setInbox(contextTabs(), false);
    });

    const reset = document.createXULElement("menuitem");
    reset.id = CONTEXT_RESET_ID;
    reset.setAttribute("label", "Reset Inbox Timer");
    reset.addEventListener("command", () => {
      resetTimers(contextTabs());
    });

    contextMenu.append(separator, send, remove, reset);
    contextMenu.addEventListener("popupshowing", updateContextMenu);
  }

  function updateContextMenu(event) {
    if (event.target !== contextMenu) {
      return;
    }

    const enabled = Services.prefs.getBoolPref(ENABLED_PREF, true);
    const tabs = contextTabs();
    const candidates = tabs.filter(isInboxCandidate);
    const inboxTabs = candidates.filter((tab) => ensureState(tab)?.inInbox);
    const hasRegularTabs = candidates.some((tab) => !ensureState(tab)?.inInbox);

    const separator = document.getElementById(CONTEXT_SEPARATOR_ID);
    const send = document.getElementById(CONTEXT_SEND_ID);
    const remove = document.getElementById(CONTEXT_REMOVE_ID);
    const reset = document.getElementById(CONTEXT_RESET_ID);

    separator.hidden = !enabled || candidates.length === 0;
    send.hidden = !enabled || !hasRegularTabs;
    remove.hidden = !enabled || inboxTabs.length === 0;
    reset.hidden = !enabled || inboxTabs.length === 0;
  }

  function setInbox(tabs, inInbox) {
    if (!Services.prefs.getBoolPref(ENABLED_PREF, true)) {
      return;
    }

    for (const tab of tabs) {
      if (!isInboxCandidate(tab)) {
        continue;
      }

      const state = ensureState(tab);
      if (!state) {
        continue;
      }

      state.inInbox = inInbox;
      if (inInbox) {
        state.workspaceId = getWorkspaceId(tab);
      } else {
        delete state.workspaceId;
      }
      writeState(tab, state);
    }

    refreshSoon();
  }

  function resetTimers(tabs) {
    if (!Services.prefs.getBoolPref(ENABLED_PREF, true)) {
      return;
    }

    const now = Date.now();
    for (const tab of tabs) {
      const state = ensureState(tab);
      if (!state?.inInbox) {
        continue;
      }
      state.ageStartedAt = now;
      writeState(tab, state);
    }
    refreshSoon();
  }

  function getClearableRegularTabs(workspaceId) {
    const tabs = Array.from(
      window.gZenWorkspaces.allStoredTabs || gBrowser.tabs,
    ).filter(
      (tab) =>
        isTab(tab) &&
        tab.getAttribute("zen-workspace-id") === workspaceId &&
        tab.visible &&
        !tab.pinned &&
        !ensureState(tab)?.inInbox,
    );

    const remainingTabs = tabs.filter((tab) => {
      const attributes = [
        "selected",
        "multiselected",
        "pictureinpicture",
        "soundplaying",
      ];
      if (attributes.some((attribute) => tab.hasAttribute(attribute))) {
        return false;
      }

      const browser = tab.linkedBrowser;
      if (
        window.webrtcUI.browserHasStreams(browser) ||
        browser?.browsingContext?.currentWindowGlobal?.hasActivePeerConnections()
      ) {
        return false;
      }
      return true;
    });

    return remainingTabs.length ? remainingTabs : tabs;
  }

  function clearRegularTabs() {
    const workspaceId = window.gZenWorkspaces.activeWorkspace;
    const tabs = getClearableRegularTabs(workspaceId);
    if (!tabs.length) {
      return;
    }

    gBrowser.removeTabs(tabs, {
      closeWindowWithLastTab: false,
    });

    const shortcut =
      window.gZenKeyboardShortcutsManager?.getShortcutDisplayFromCommand?.(
        "History:RestoreLastClosedTabOrWindowOrSession",
      );
    window.gZenUIManager?.showToast?.(
      "zen-workspaces-close-all-unpinned-tabs-toast",
      {
        l10nArgs: {
          shortcut,
        },
      },
    );
  }

  function onCommand(event) {
    const commandId =
      event.target?.id || event.target?.getAttribute?.("command");
    if (commandId !== "cmd_zenCloseUnpinnedTabs") {
      return;
    }

    const workspaceId = window.gZenWorkspaces.activeWorkspace;
    const hasInboxTabs = gBrowser.tabs.some(
      (tab) =>
        tab.getAttribute("zen-workspace-id") === workspaceId &&
        ensureState(tab)?.inInbox,
    );
    if (!hasInboxTabs) {
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();
    clearRegularTabs();
  }

  function onTabOpen(event) {
    ensureState(event.target);
    refreshSoon();
  }

  function onTabRestored(event) {
    ensureState(event.target);
    refreshSoon();
  }

  function onWorkspaceEvent() {
    refreshSoon();
  }

  function initialize() {
    if (started) {
      return;
    }
    started = true;

    createContextMenu();
    preferenceObserver = {
      observe() {
        refreshSoon();
      },
    };
    Services.prefs.addObserver("zen.inbox.", preferenceObserver);
    document.addEventListener("command", onCommand, true);

    window.addEventListener("TabOpen", onTabOpen);
    window.addEventListener("SSTabRestored", onTabRestored);
    window.addEventListener("TabClose", onWorkspaceEvent);
    window.addEventListener("TabMove", onWorkspaceEvent);
    window.addEventListener("TabPinned", onWorkspaceEvent);
    window.addEventListener("TabUnpinned", onWorkspaceEvent);
    window.addEventListener("TabSelect", onWorkspaceEvent);
    window.addEventListener("ZenWorkspacesUIUpdate", onWorkspaceEvent);
    window.addEventListener("ZenWorkspaceDataChanged", onWorkspaceEvent);
    window.addEventListener("AfterWorkspacesSessionRestore", onWorkspaceEvent);
    window.addEventListener("dragover", onInboxDragOver, true);
    window.addEventListener("drop", onInboxDrop, true);
    window.addEventListener("dragend", onInboxDragEnd, true);

    refresh();
  }

  function startWhenReady() {
    if (!window.gBrowser || !window.gZenWorkspaces) {
      setTimeout(startWhenReady, 100);
      return;
    }

    const initialized = window.gZenWorkspaces.promiseInitialized;
    if (initialized?.then) {
      initialized.then(initialize);
    } else {
      initialize();
    }
  }

  function uninitialize() {
    clearTimeout(refreshTimer);
    clearTimeout(refreshSoonTimer);

    if (started) {
      for (const [eventName, handler] of EVENT_HANDLERS) {
        window.removeEventListener(eventName, handler);
      }
    }

    if (preferenceObserver) {
      Services.prefs.removeObserver("zen.inbox.", preferenceObserver);
      preferenceObserver = null;
    }
    collapseObserver?.disconnect();
    collapseObserver = null;
    document.removeEventListener("command", onCommand, true);
    window.removeEventListener("dragover", onInboxDragOver, true);
    window.removeEventListener("drop", onInboxDrop, true);
    window.removeEventListener("dragend", onInboxDragEnd, true);
    clearInboxDragOver();

    if (contextMenu) {
      contextMenu.removeEventListener("popupshowing", updateContextMenu);
      for (const id of [
        CONTEXT_SEPARATOR_ID,
        CONTEXT_SEND_ID,
        CONTEXT_REMOVE_ID,
        CONTEXT_RESET_ID,
      ]) {
        document.getElementById(id)?.remove();
      }
    }

    for (const tab of window.gBrowser?.tabs || []) {
      const workspace = tab.parentElement?.closest("zen-workspace");
      const wasInbox = tab.hasAttribute(INBOX_ATTRIBUTE);
      clearTabPresentation(tab);
      if (wasInbox && workspace) {
        moveTabToNormal(tab, workspace);
      }
    }
    for (const workspace of workspaceSections()) {
      const pinnedSection = getPinnedSection(workspace);
      workspace.removeAttribute(PRESERVE_COLLAPSE_ATTRIBUTE);
      if (workspace.hasAttribute(EXPOSES_PINNED_STATE_ATTRIBUTE)) {
        workspace.removeAttribute(EXPOSES_PINNED_STATE_ATTRIBUTE);
        if (
          !Array.from(pinnedSection?.children || []).some(
            (child) => isTab(child) && child.pinned,
          )
        ) {
          workspace.removeAttribute("haspinnedtabs");
          workspace.collapsiblePins.collapsed = false;
        }
      }
      if (pinnedSection && workspace.hasAttribute("collapsedpinnedtabs")) {
        pinnedSection.setAttribute("hidden", "true");
      }
      workspace.querySelector(`.${HEADER_CLASS}`)?.remove();
    }

    started = false;
    delete window.__zenInbox;
  }

  if (typeof window.addUnloadListener === "function") {
    window.addUnloadListener(uninitialize);
  }

  if (document.readyState === "loading") {
    window.addEventListener("DOMContentLoaded", startWhenReady, { once: true });
  } else {
    startWhenReady();
  }
  window.addEventListener("unload", uninitialize, { once: true });
  window.__zenInbox = { refresh, setInbox, resetTimers };
})();
