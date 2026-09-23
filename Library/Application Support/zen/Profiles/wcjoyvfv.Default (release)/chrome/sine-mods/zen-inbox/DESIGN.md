# Design: Workspace Inbox Tab Lane

Date: 2026-08-25
Status: APPROVED
Mode: Builder

## Problem statement

Zen separates persistent pinned tabs from ordinary tabs, but it does not provide a lightweight holding area for tabs that are still active work. Users often keep these tabs mixed into their regular tab list even though they represent a different state: not persistent reference material, and not finished work either.

The Inbox is a per-workspace lane for these temporary work items. It gives selected tabs a visible age and an age-based urgency color, while keeping them as ordinary browser tabs that can still load, unload, restore, and close normally.

## What makes this cool

The Inbox turns tab clutter into a visible queue. Oldest items rise to the top, and the color gradually communicates that a tab has been waiting without requiring a notification or task-management system.

The feature remains lightweight because it does not create a second kind of browser tab. A tab is either in the workspace Inbox or in the regular tab list. Moving a tab to the Inbox is explicit, resetting its timer is explicit, and finishing it means closing it.

Unloaded tabs remain first-class Inbox items. Their age continues while they are unloaded, so users can reduce memory usage without losing the queue or its sense of urgency.

## Constraints

The initial implementation should target a native Zen modification. The official Zen mod stylesheet mechanism is not sufficient by itself because timestamps, sorting, tab movement, and context-menu actions require browser-chrome JavaScript. The first version therefore needs a companion privileged userChrome script, with the visual layer supplied by the mod stylesheet.

Inbox must be scoped to the active workspace. An Inbox tab must not be duplicated in the regular list. Inbox membership must survive ordinary tab unloading and browser restart.

The feature should not automatically capture newly opened tabs. Users must opt in through an explicit context-menu action, keyboard command, or equivalent control.

## Premises

1. Inbox is a visual organization layer over ordinary tabs, not a new loading or persistence model.
2. A tab's initial age is based on its creation time, not its last visit.
3. Resetting the timer is an explicit exception to the initial age rule. The immutable tab creation time remains available for future diagnostics, while a separate age anchor controls the displayed Inbox age.
4. Age is the only urgency signal. A continuous color gradient communicates the exact age without adding a manual priority field.
5. Completing an Inbox item closes the tab. There is no separate completed archive.
6. Each tab belongs to exactly one visible lane: Inbox or regular.
7. A tab moved into Inbox keeps its existing creation age. An old tab can therefore enter Inbox already in an orange or red state.

## Approaches considered

### Approach A: Native Zen mod with a companion chrome script

The script tracks Inbox membership and age metadata, responds to tab and workspace events, updates the age label, and maintains the Inbox ordering. The stylesheet renders the Inbox section before Zen's pinned-tab divider, an inline age label, and urgency colors.

This is the recommended starting point. It provides the target native experience with a focused change and lets the behavior be validated before proposing a Zen core feature.

### Approach B: Firefox or Zen extension with an Inbox sidebar

An extension can track tabs and display a separate Inbox panel, but a standard extension cannot reliably insert a section between Zen's Essentials and regular tabs. Zen workspace isolation also makes cross-workspace tab discovery more complicated for an extension.

This is a reasonable fallback if privileged userChrome scripting proves too fragile, but it would not deliver the intended native location.

### Approach C: First-class upstream Zen feature

Zen would own the Inbox tab state, session restore, workspace behavior, keyboard commands, drag and drop, synchronization, and accessibility. This is the cleanest long-term solution, but it requires broader changes to the tab model and a public product decision.

The mod should provide usage evidence and implementation lessons before pursuing this path.

## Recommended approach

Implement Approach A as a narrow proof of concept. Keep all Inbox state attached to the existing tab and reuse Zen's workspace identifier. Store persistent values through the session store rather than relying only on live DOM attributes.

The initial proof of concept should include one workspace Inbox, explicit send/remove actions, timer reset, oldest-first ordering, single-unit age labels, a continuous urgency gradient, session restoration, and normal close behavior. It should exclude automatic capture, notifications, notes, manual priority, sync changes, and a completed archive.

## Interaction design

The Inbox section appears between Essentials and regular tabs. Its header uses an Inbox icon, shows the current item count, and toggles only the Inbox tabs. Collapsing the parent space must not hide the Inbox section. The header remains visible as an empty drop target by default, with a preference to hide it when the item count is zero.

Sending a tab to Inbox moves the existing tab into the Inbox lane. Users can send regular tabs from the context menu or by dropping them on the Inbox header or an existing Inbox tab. Dragging Inbox tabs back into the regular lane removes their Inbox membership before Zen completes its native reorder. Multi-tab drags apply the same transition to every eligible selected tab. Neither action opens a new tab or changes the page state.

Inbox tabs display only the largest age unit, such as `56m`, `5h`, `1d`, or `2mo`. The label updates at minute precision. A tooltip or accessible description should expose the full creation or timer-reset timestamp.

The timer color uses a continuous gradient calculated from the exact age. Its default color points are:

- Green at creation.
- Yellow at four hours.
- Orange at twenty-four hours.
- Red at seventy-two hours, followed by gradual darkening for older items.

The color is not rounded with the label. For example, a tab aged one hour and fifty-nine minutes still displays `1h`, but its timer is visibly further along the gradient than a tab aged one hour and five minutes.

Resetting the timer is available from the tab context menu and should update the displayed age and sort position immediately. The reset action should not change the tab URL, loading state, workspace, or regular tab history.

Closing an Inbox tab uses Zen's normal close behavior. Once closed, it is no longer an Inbox item. If Zen restores it through recently closed tabs, its persisted Inbox metadata should be restored as well. Zen's clear-unpinned-tabs action closes regular tabs only and leaves Inbox tabs in place.

## Data model

Each tab needs a persistent record with the following logical fields:

- `createdAt`: the original tab creation timestamp, retained for correctness and diagnostics.
- `ageStartedAt`: the timestamp used to calculate the current displayed age. It initially equals `createdAt` and changes only when the user resets the timer.
- `inInbox`: whether the tab belongs to the Inbox lane.
- `workspaceId`: the Zen workspace that owns the Inbox lane.

The implementation should use stable, namespaced session-store custom values or an equivalent Zen-supported persistence mechanism. Live DOM attributes can mirror the values for styling, but they should not be the source of truth.

Tabs that already exist when the script is first installed will not have a reliable original creation timestamp. The first version should initialize missing timestamps when it first sees those tabs and document that limitation.

## Sorting and layout

Only Inbox tabs are sorted by `ageStartedAt`, oldest first. Ties should use the current native tab order to avoid unnecessary movement.

Regular tabs retain their existing order when Inbox tabs are added, removed, reset, or resorted. The implementation must preserve a tab's identity and selected state while changing its lane.

The script should update ordering when a tab enters or leaves Inbox, when its timer is reset, when a workspace changes, and when a relevant tab is restored. A periodic timer should update labels and urgency attributes, but it should not reorder tabs unless a sort key has changed.

## Implementation outline

The privileged script should observe tab creation, tab close, tab restoration, tab attribute changes, workspace changes, and relevant drag or context-menu actions. It should maintain a per-window view of the active workspace while keeping persistent state on the tab.

The script should use existing Zen concepts such as `zen-workspace-id`, the browser's tab objects, session-store APIs, and existing tab context-menu patterns. It should avoid changing the tab's loading lifecycle or duplicating browser panels.

The stylesheet should target Inbox membership and use the exact color calculated by the script. It should provide age-label styling, colors that remain legible in light and dark themes, and reduced visual intensity for unloaded tabs without hiding their age.

## Open questions

When a tab is moved between workspaces, it is not yet decided whether Inbox membership travels with the tab or is removed because Inbox is workspace-local. The safer initial behavior may be to keep the tab's metadata but make the move explicit in the target workspace.

It is not yet decided whether tabs opened from an Inbox tab should remain regular by default or inherit Inbox membership. Explicit intake currently suggests that they should remain regular.

The design should later cover multi-window behavior, workspace synchronization, split views, folders, private windows, and what happens when the mod is disabled.

## Success criteria

The proof of concept succeeds if a user can send a tab into the active workspace's Inbox through either the context menu or drag and drop, see it appear in the correct position with a correct age label and color, unload it without losing its Inbox state, reset its timer, move it back to regular tabs, and close it normally.

The behavior must remain stable across workspace switching and browser restart. A tab must never appear simultaneously in Inbox and regular tabs, and regular tab order must not be unexpectedly reshuffled.

## Dependencies

The native prototype depends on privileged userChrome script loading, Zen's current browser-chrome DOM, session-store custom tab values, and the existing workspace and tab-management code.

The stylesheet should be kept isolated from the existing local changes in `src/zen/tabs/zen-tabs.css` until the prototype behavior is validated.

## Next steps

1. Confirm the default urgency thresholds and the behavior of tabs moved between workspaces.
2. Build a non-destructive UI spike that marks selected tabs as Inbox items and renders age labels without changing tab order.
3. Add persistent metadata and session restoration.
4. Add lane movement, oldest-first sorting, timer reset, and the final urgency styling.
5. Add browser tests for workspace isolation, reset behavior, unloading, restoration, ordering, and close behavior.

## Session notes

- The requested location is a separate lane between pinned tabs and regular tabs.
- Inbox membership is explicit and mutually exclusive with regular-tab membership.
- Age begins at tab creation, while an explicit reset can restart the displayed timer.
- Age color progresses from green through yellow and orange to red.
- Inbox is per-workspace, and closing an Inbox tab is the completion action.
