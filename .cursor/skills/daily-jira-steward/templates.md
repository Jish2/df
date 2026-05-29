# Daily Jira Steward Templates

Use these templates when writing or refreshing the steward artifacts.

## `me.md`

Every link in `me.md` must work for someone reading the Google Doc. Never use local filesystem paths, `file://` URLs, `localhost` URLs, or machine-specific links. If an artifact only exists locally, describe it without linking until it has a shareable remote URL.

```markdown
# Josh Goon Work Visibility

Last updated: YYYY-MM-DD

## Now
- **Focus:** ...
- **Goal:** ...
- **Status:** ...
- **Needs attention:** ...
- **Links:** [latest daily report](https://github.rbx.com/jgoon/daily-reports/blob/main/reports/YYYY-MM-DD.md), ...

## Next
- [concrete next actions with PR/Jira links]

## Backlog
- [lower-priority or stale follow-ups with links]

## Done Recently
- [3-6 bullets for work completed or materially advanced in the last ~2 weeks; drop items older than that]

## Useful Links
- Daily reports: [YYYY-MM-DD](https://github.rbx.com/jgoon/daily-reports/blob/main/reports/YYYY-MM-DD.md), ...
- Jira: [active ROS work](...)
- GitHub: [ROS PRs by Josh](...), [ros-infra PRs by Josh](...)
- Docs: ...
```

Guidelines:

- `Now` reflects current focus, goal, status, blockers, and 3-5 high-signal links.
- `Next` is ordered, actionable, and uses readable `PR #N: title` / `ROS-N: title` style.
- `Backlog` holds tickets or themes not actively being worked this week.
- `Done Recently` rotates forward; remove bullets that are no longer useful for standups or manager visibility.
- Prefer markdown links over bare URLs. Use full remote URLs, not relative paths, because Google Docs readers need links that work outside the local checkout.
- Do not include approval-gated Jira or GitHub writes that are still pending unless they are already part of the user's committed plan.

## Daily Report

Use this structure when writing the report file:

```markdown
## Daily Work Report

Window: [start time] to [end time]
Report saved at: [repo path]

## Sources Checked

- [source and scope]

## Work Log

- [workstream or project]: [what the user did, evidence or artifacts, outcome or progress, blockers or next step if visible]

## Slack Evidence

- Broad search: [time window, query shape, high-signal hits, and important misses]
- Targeted search: [Jira keys, PRs, workstream terms searched, high-signal hits, and important misses]
- Threads expanded: [channel/thread context, what decision/blocker/coordination was found, or rate-limit skip]

## Artifact Summary

- PR: [PR number and title, created/merged/reviewed/materially updated, why it mattered]
- Jira: [ticket key and title, work performed or status observed]
- Doc/Chat/Other: [artifact title or source, work performed or decision made]

## Intentional Omissions / No Action

- [reviewed evidence intentionally left out of the work log, `me.md`, or proposed updates, with the reason]

## Pending Approval

| Change ID                 | Write                                            | Details                                          | Status                                             |
| ------------------------- | ------------------------------------------------ | ------------------------------------------------ | -------------------------------------------------- |
| [prior pending change ID] | [system, action, target, and readable title]     | [specific proposed write plus supporting evidence] | [Pending, Approved, Applied, Skipped, or Rejected] |

## GitHub Activity

- [PR created, merged, reviewed, or materially updated, always including PR number and title]

## Current Jira Triage

- [ticket key and title, observed state, proposed action or reason no action is needed]

## Stale Ticket Callouts

- [ticket key and title, age since last update, status, why it may need attention, lightest useful next step]

## Proposed Jira Updates

- Create: [ticket summary and reason]
- Update: [ticket key and title, comment or field change, reason]
- Transition: [ticket key and title, from state to state, evidence]
- Skip: [work item, reason no Jira change is needed]

## Proposed GitHub PR Updates

- Update: [PR number and title, body/title/comment change, reason]

## Questions

- [Only include blockers that require user judgment]
```

If there is no tracker or PR change to make, still write the full daily report and say external tracking appears aligned.

## Pending Draft

Every pending draft must include a proposed-changes table before detailed notes. Keep one row per write action so it can be converted directly into answers UI options.

Use only these columns:

- `Change ID`: stable identifier such as `JIRA-1` or `GH-1`.
- `Write`: system, action, target, and readable title or summary.
- `Details`: proposed change plus supporting evidence.
- `Status`: `Pending`, `Approved`, `Applied`, `Skipped`, or `Rejected`, with a short reason when helpful.

```markdown
| Change ID | Write | Details | Status |
| --------- | ----- | ------- | ------ |
| JIRA-1 | Jira transition for `ROS-123: Add status reconciliation` | Move from `In Progress` to `In Review`. Evidence: `PR #456: Add reconciliation` is open. | Pending |
| GH-1 | GitHub PR update for `PR #456: Add reconciliation` | Replace `[n/a]` with `ROS-123: Add status reconciliation`. Evidence: PR implements tracked Jira work. | Pending |
```

For new ticket creation, start the `Write` cell with `Jira create: [ticket summary]`. For existing tickets and PRs, include both the target identifier and readable title in the `Write` cell.
