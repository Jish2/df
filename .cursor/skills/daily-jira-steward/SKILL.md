---
name: daily-jira-steward
description: Builds a comprehensive daily work report for performance-cycle recall and separately maintains Jira and PR tracking from recent work, branches, user-provided ideas, and stale tickets. Use when the user asks to run the daily Jira steward, write a daily work report, update Jira from recent work, create tracking tickets, reconcile Jira with PRs, call out neglected Jira issues, or close tickets after merges.
disable-model-invocation: true
---

# Daily Jira Steward

Use this skill as a morning routine to turn recent work into a saved daily work report and a separate draft set of Jira and GitHub PR updates.

## Rules

- Jira and GitHub PR writes are approval-gated. Draft proposed ticket creation, comments, field changes, transitions, and PR body/title updates first. Apply only the specific changes the user approves.
- Use the answers UI for approval when it is available. Convert each proposed write into a selectable option so the user can choose exactly which Jira or GitHub changes to apply.
- Never refer to a PR, Jira ticket, or GR ticket by number or key alone. Always include the readable title or summary next to it, such as `PR #123: Add status reconciliation` or `ROS-456: Track stale Jira review`.
- Do not create tickets for passing thoughts. Create tracking only when the user asks to track an idea or concrete evidence shows active work.
- Prefer updating existing tickets over creating duplicates.
- Triage the user's current Jira tickets every run. Look for stale status, missing progress comments, blockers, completed work, duplicate tracking, and tickets that should be linked to recent PRs or docs.
- Treat `[n/a]` in a PR title as missing tracking, not as a reason to skip tracking, when the PR contains concrete work. Draft a Jira ticket plan and a PR update that links the approved ticket.
- For related `[n/a]` PRs in the same workstream, prefer a parent ticket with useful immediate child tickets instead of unrelated standalone tickets. Reuse existing Jira tickets when they clearly cover the work.
- Never close or transition a ticket from local commits alone. Require merged PR evidence, explicit user instruction, or a clearly completed Jira workflow signal.
- Report repo writes are operational artifacts and do not need separate approval.
- The daily report and proposed Jira or PR updates have different jobs. The report is a comprehensive work log for later performance-cycle recall. Proposed updates are only the subset of work that needs Jira or GitHub tracking changes.

## Daily Work Report Scope

The saved daily report should reflect everything the user did during the review window that has evidence in the inspected sources. Do not limit the report to work that needs Jira updates.

Capture concrete work signals such as implementation, debugging, CI or release work, code review, planning, design review, research, stakeholder coordination, support, incident or on-call work, docs, follow-ups, decisions made, and meaningful context gathering. Include small items when they help reconstruct the day later, but group tiny fragments under the same workstream instead of creating noisy one-off bullets.

For each work item, include enough detail to be useful months later: the workstream or project, what changed or progressed, artifacts such as PRs, Jira tickets, docs, chats, or branches, relevant blockers or decisions, and the next step when one is visible. Prefer evidence-backed summaries over exhaustive transcript excerpts. Do not copy sensitive personal details or long private-message content into the report unless the user explicitly asks and it is necessary.

Jira and PR tracking remains separate. A work item can appear in the daily report even when the right proposed update is `Skip`, no Jira change, or no PR change.

## Access Gate

The steward is only effective when it can inspect the required systems. Before doing the full evidence pass, verify access to:

- Jira/Atlassian for current-ticket triage, stale-ticket searches, issue reads, and approved writes.
- GitHub for PR activity, PR reads, and approved PR updates.
- The daily reports repo for pull, report write, commit, and push.

If any required source or tool fails because of authentication, missing credentials, unavailable CLI/tooling, or missing permissions, stop and ask the user to authenticate or repair access. Do not continue with a degraded steward run unless the user explicitly approves a limited run after seeing which source is unavailable.

When stopping for access, report the exact source that failed, the command or tool category that failed, and the shortest next action for the user, such as refreshing `github.rbx.com` auth, completing Jira OAuth, running the host LCA helper, or reopening in the devcontainer. Do not write a clean daily report, advance `last_completed_at`, advance `last_reviewed_through_at`, or mark pending items reviewed until the required source is available or the user explicitly accepts a degraded run.

## Status Reconciliation

Every run should compare Jira status against the strongest available evidence and draft transitions when they are out of date.

Use these defaults unless a team workflow or user instruction says otherwise:

- Concrete work found but no PR yet: move the tracking ticket to `In Progress`.
- PR is open for the ticket: move the ticket to `In Review`.
- PR is merged and the ticket still needs rollout, observation, or follow-up validation: move the ticket to `In Testing`.
- PR is merged and the ticket's acceptance criteria are complete with no known follow-up: move the ticket to `Closed`.
- Parent workstream with any active child tickets: keep the parent at `In Progress`.
- Parent workstream with only review-state child tickets: use `In Review` if the parent is mainly waiting on review.
- Parent workstream with all child tickets closed or verified: draft closing the parent.

Draft status transitions with the evidence that supports them. Jira transitions are still approval-gated unless the user explicitly asks to apply them.

## Stale Ticket Callouts

Every run should include a small stale-ticket review so old work does not disappear. Treat staleness as a reminder signal, not proof that Jira needs a write.

Default searches:

```text
project in (ROS, ROSHELP) AND assignee = currentUser() AND statusCategory != Done AND updated <= -14d ORDER BY updated ASC
project in (ROS, ROSHELP) AND reporter = currentUser() AND statusCategory != Done AND updated <= -30d ORDER BY updated ASC
```

Use these thresholds unless the ticket, team workflow, or user instruction suggests a better bar:

- In Review with no update for 7+ days: call out as likely waiting on review, merge, or a status correction.
- In Testing with no update for 14+ days: call out as likely needing validation, rollout notes, or closure.
- In Progress with no update for 21+ days: call out as possibly blocked, forgotten, or missing a progress comment.
- To Do, Backlog, or unstarted work with no update for 30+ days: call out as stale if it still appears relevant; otherwise suggest closing, deprioritizing, or leaving alone with a reason.
- Any active assigned ticket with no update for 60+ days: always include it as long-stale, even if no action is obvious.

For each stale callout, include the age, current status, owner/relationship to the user, why it might matter, and the lightest useful next step. Prefer `needs a quick look`, `candidate to close`, `waiting on external signal`, `probably still fine`, or `needs user judgment` over inventing urgency. Do not draft Jira comments solely because a ticket is old; draft a comment, transition, or close action only when there is supporting evidence or the user asks to clean it up.

## Sources

Use whatever relevant sources are available to reconstruct the review window: Cursor chat transcripts, current chat context, git branches, commits, GitHub PRs, Jira, Slack, Gmail, calendar, docs, Confluence, Google Drive, production signals, or other systems that identify work, blockers, decisions, completion evidence, or day-to-day effort.

For Cursor chats, include transcripts updated during the review window, even if the chat was created earlier. Use transcript file modification time to select candidate chats. When message timestamps are available, summarize only messages or events inside the review window. If timestamps are unclear, include the transcript and summarize only concrete work signals that appear relevant. Include work even when it did not produce a PR, Jira change, or final shipped artifact.

For Jira in the ROS workspace, first read `.cursor/skills/ros-atlassian/SKILL.md` and follow its routing. Outside ROS, use the available Jira or Atlassian skill. For GitHub, prefer the `gh` CLI when available.

Prefer direct evidence over inference. Do not copy long chat excerpts or sensitive details into Jira unless they are necessary for tracking the work.

## State and Reports

Store skill state in `~/.cursor/skills/daily-jira-steward/state.json`:

```json
{
  "last_started_at": null,
  "last_completed_at": null,
  "last_reviewed_through_at": null,
  "pending_since_at": null,
  "pending_draft_path": null,
  "last_report_path": null
}
```

At run start, set `last_started_at` to the current time. If the user does not specify a window, choose the start time from `pending_since_at`, then `last_reviewed_through_at`, then the last 24 hours on weekdays or 72 hours after a weekend. Use `last_started_at` as the review-window end so work that happens during the run is picked up next time.

Save the draft to `~/.cursor/skills/daily-jira-steward/pending-draft.md`. If proposed Jira or GitHub changes are not applied, keep `pending_since_at` and `pending_draft_path` set so the next run includes them. Clear both only after updates are applied, the user says to mark them reviewed, or there are no proposed Jira or GitHub changes.

After a clean run, set `last_completed_at`, set `last_reviewed_through_at` to the review-window end, and record `last_report_path`.

Persist daily reports in `github.rbx.com/jgoon/daily-reports` using the local checkout at `/Users/jgoon/github/daily-reports`. If missing, clone `https://github.rbx.com/jgoon/daily-reports.git`. Pull with `--ff-only` before writing.

Write reports to `reports/YYYY-MM-DD.md` using the review-window end date in local time. Append a new run section if the file already exists. Commit and push after writing:

```bash
git -C /Users/jgoon/github/daily-reports pull --ff-only
git -C /Users/jgoon/github/daily-reports add reports/YYYY-MM-DD.md
git -C /Users/jgoon/github/daily-reports commit -m "docs: add daily report for YYYY-MM-DD"
git -C /Users/jgoon/github/daily-reports push
```

## Workflow

1. Establish the review window from checkpoint tracking unless the user specifies a window.
2. Read any pending draft first and show it as Pending Approval, preserving its proposed-changes table and change IDs.
3. Run the access gate for Jira/Atlassian, GitHub, and the daily reports repo. Stop and ask for auth if any required source is unavailable.
4. Inspect relevant sources, including Cursor chats updated during the window.
5. Build a comprehensive work log from the evidence before deciding which items need Jira or PR updates.
6. Triage the user's current Jira tickets and compare them against recent evidence.
7. Run the stale-ticket review and call out long-stale tickets separately from evidence-backed proposed updates.
8. List GitHub activity in the report, including PRs created, merged, reviewed, or materially updated during the window. Include `[n/a]` PRs explicitly.
9. Draft exact Jira and GitHub PR updates: creates, comments, transitions, PR link updates, and skips. For related work, draft one parent ticket and only useful immediate child tickets.
10. Save the pending draft, write the daily report, commit and push the report repo.
11. Present the report and use the answers UI, when available, to ask which proposed changes to apply.
12. If the user approves all or part of the draft, apply only the selected rows from the proposed-changes table. Keep unapproved items pending. Do not show rejected items again unless new evidence appears or the user asks to revisit them.

## Approval Answers UI

When there are proposed Jira or GitHub writes, use the answers UI before applying them. Offer one selectable option per proposed change, keyed by the table's change ID. Add `Apply all proposed changes` only when every row is low-risk and fully evidenced. Add `Skip all for now` when there are pending writes.

Each option label must include the action, the target identifier, and the target title or summary. Do not use labels like `ROS-123` or `PR #456` by themselves.

If the answers UI is not available, ask for approval in chat using the same change IDs. Apply only rows the user explicitly approves.

## Pending Draft Format

Every pending draft must include a proposed-changes table before any detailed notes. Keep one row per write action so it can be converted directly into answers UI options.

```markdown
| Change ID | System | Action     | Target  | Title or summary          | Proposed change                                         | Evidence                            | Approval status |
| --------- | ------ | ---------- | ------- | ------------------------- | ------------------------------------------------------- | ----------------------------------- | --------------- |
| JIRA-1    | Jira   | Transition | ROS-123 | Add status reconciliation | Move from `In Progress` to `In Review`                  | PR #456: Add reconciliation is open | Pending         |
| GH-1      | GitHub | Update PR  | PR #456 | Add reconciliation        | Replace `[n/a]` with ROS-123: Add status reconciliation | PR implements tracked Jira work     | Pending         |
```

For new ticket creation, put `New ticket` in the Target column and the proposed ticket summary in `Title or summary`. For existing tickets and PRs, Target contains the key or number while `Title or summary` contains the readable title.

## Daily Report Format

Use this structure when reporting back and when writing the daily report file:

```markdown
## Daily Work Report

Window: [start time] to [end time]
Report saved at: [repo path]

## Sources Checked

- [source and scope]

## Work Log

- [workstream or project]: [what the user did, evidence or artifacts, outcome or progress, blockers or next step if visible]

## Artifact Summary

- PR: [PR number and title, created/merged/reviewed/materially updated, why it mattered]
- Jira: [ticket key and title, work performed or status observed]
- Doc/Chat/Other: [artifact title or source, work performed or decision made]

## Pending Approval

| Change ID                 | System           | Action                                              | Target                                 | Title or summary     | Proposed change           | Evidence              | Approval status                                    |
| ------------------------- | ---------------- | --------------------------------------------------- | -------------------------------------- | -------------------- | ------------------------- | --------------------- | -------------------------------------------------- |
| [prior pending change ID] | [Jira or GitHub] | [Create, update, transition, comment, or PR update] | [ticket key, PR number, or New ticket] | [ticket or PR title] | [specific proposed write] | [supporting evidence] | [Pending, Approved, Applied, Skipped, or Rejected] |

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

If there is no Jira or PR tracking change to make, still write the full daily work report and say Jira and GitHub tracking already appear aligned.
