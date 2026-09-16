// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/*
 * zen-duplicate-tabs — highlight tabs that duplicate the selected tab's URL
 * (same container, same workspace; Essentials count in every workspace).
 *
 * Ported from the fork's in-tree ZenDuplicateTabsManager.mjs (dropped branch
 * feat/highlight-duplicate-tabs, fork commits 22f69ae0b..55018cb87) into a
 * Sine mod so this lives with the profile config instead of the source tree.
 */
(() => {
  "use strict";

  if (window.__zenDuplicateTabs) {
    return;
  }
  window.__zenDuplicateTabs = true;

  const lazy = {};
  ChromeUtils.defineESModuleGetters(lazy, {
    SessionStore: "resource:///modules/sessionstore/SessionStore.sys.mjs",
  });

  const TAB_CHANGE_EVENTS = [
    "TabSelect",
    "TabOpen",
    "TabClose",
    "TabMove",
    "TabPinned",
    "TabUnpinned",
    "TabAddedToEssentials",
    "TabRemovedFromEssentials",
    "ZenWorkspacesUIUpdate",
  ];

  const manager = {
    _onTabChange() {
      this.updateDuplicateTabs();
    },

    init() {
      this._boundOnTabChange = this._onTabChange.bind(this);
      gZenWorkspaces.promiseInitialized.then(() => {
        for (const event of TAB_CHANGE_EVENTS) {
          window.addEventListener(event, this._boundOnTabChange);
        }
        gBrowser.addTabsProgressListener(this);
        this.updateDuplicateTabs();

        window.addEventListener(
          "unload",
          () => {
            for (const event of TAB_CHANGE_EVENTS) {
              window.removeEventListener(event, this._boundOnTabChange);
            }
            gBrowser.removeTabsProgressListener(this);
          },
          { once: true }
        );
      });
    },

    onLocationChange(_aBrowser, aWebProgress) {
      if (aWebProgress.isTopLevel) {
        this.updateDuplicateTabs();
      }
    },

    updateDuplicateTabs() {
      const tabs = gZenWorkspaces.allStoredTabs;
      for (const tab of tabs) {
        tab.removeAttribute("zen-duplicate-tab");
        tab.removeAttribute("zen-duplicate-count");
      }

      const selectedTab = gBrowser.selectedTab;
      if (!this._isEligibleTab(selectedTab)) {
        return;
      }

      const selectedURL = this._getComparableURL(selectedTab);
      if (!selectedURL) {
        return;
      }

      const selectedContextId = selectedTab.userContextId;
      const selectedWorkspaceId =
        selectedTab.getAttribute("zen-workspace-id") ??
        gZenWorkspaces.activeWorkspace;
      const matchingTabs = tabs.filter(
        tab =>
          this._isEligibleTab(tab) &&
          tab.userContextId === selectedContextId &&
          this._isInSelectedWorkspace(tab, selectedWorkspaceId) &&
          this._getComparableURL(tab) === selectedURL
      );

      if (matchingTabs.length < 2) {
        return;
      }

      for (const tab of matchingTabs) {
        tab.setAttribute("zen-duplicate-tab", "true");
      }
      const duplicateCount = matchingTabs.length.toString();
      selectedTab.setAttribute("zen-duplicate-count", duplicateCount);
    },

    _isEligibleTab(tab) {
      return Boolean(
        tab &&
        !tab.closing &&
        !tab.hasAttribute("zen-empty-tab") &&
        !tab.hasAttribute("zen-glance-tab")
      );
    },

    _isInSelectedWorkspace(tab, selectedWorkspaceId) {
      return (
        tab.hasAttribute("zen-essential") ||
        !selectedWorkspaceId ||
        tab.getAttribute("zen-workspace-id") === selectedWorkspaceId
      );
    },

    _getComparableURL(tab) {
      const browser = tab.linkedBrowser;
      let url = browser?.registeredOpenURI?.spec ?? browser?.currentURI?.spec;

      if (tab.hasAttribute("pending") && (!url || url === "about:blank")) {
        url = this._getPendingTabURL(tab);
      }

      return url?.split("#", 1)[0] || null;
    },

    _getPendingTabURL(tab) {
      try {
        const state = JSON.parse(lazy.SessionStore.getTabState(tab));
        const entries = state.entries ?? [];
        const index = Math.max(0, (state.index || entries.length) - 1);
        return entries[index]?.url ?? null;
      } catch {
        return null;
      }
    },
  };

  if (document.readyState === "complete") {
    manager.init();
  } else {
    window.addEventListener("load", () => manager.init(), { once: true });
  }
})();
