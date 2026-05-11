---
name: daily-jira-steward
description: Maintains Jira tracking from recent work, PRs, branches, and user-provided ideas. Use when the user asks to run the daily Jira steward, update Jira from recent work, create tracking tickets, reconcile Jira with PRs, or close tickets after merges.
disable-model-invocation: true
---

# Daily Jira Steward

Use this skill as a morning routine to turn recent work into a saved daily report and a draft set of Jira updates.

## Rules

- Jira and GitHub PR writes are approval-gated. Draft proposed ticket creation, comments, field changes, transitions, and PR body/title updates first. Apply only the specific changes the user approves.
- Do not create tickets for passing thoughts. Create tracking only when the user asks to track an idea or concrete evidence shows active work.
- Prefer updating existing tickets over creating duplicates.
- Triage the user's current Jira tickets every run. Look for stale status, missing progress comments, blockers, completed work, duplicate tracking, and tickets that should be linked to recent PRs or docs.
- Treat `[n/a]` in a PR title as missing tracking, not as a reason to skip tracking, when the PR contains concrete work. Draft a Jira ticket plan and a PR update that links the approved ticket.
- For related `[n/a]` PRs in the same workstream, prefer a parent ticket with useful immediate child tickets instead of unrelated standalone tickets. Reuse existing Jira tickets when they clearly cover the work.
- Never close or transition a ticket from local commits alone. Require merged PR evidence, explicit user instruction, or a clearly completed Jira workflow signal.
- Report repo writes are operational artifacts and do not need separate approval.

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

## Sources

Use whatever relevant sources are available to reconstruct the review window: Cursor chat transcripts, current chat context, git branches, commits, GitHub PRs, Jira, Slack, Gmail, calendar, docs, Confluence, Google Drive, production signals, or other systems that identify work, blockers, decisions, or completion evidence.

For Cursor chats, include transcripts updated during the review window, even if the chat was created earlier. Use transcript file modification time to select candidate chats. When message timestamps are available, summarize only messages or events inside the review window. If timestamps are unclear, include the transcript and summarize only concrete work signals that appear relevant.

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

Save the draft to `~/.cursor/skills/daily-jira-steward/pending-draft.md`. If proposed Jira changes are not applied, keep `pending_since_at` and `pending_draft_path` set so the next run includes them. Clear both only after updates are applied, the user says to mark them reviewed, or there are no proposed Jira changes.

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
2. Read any pending draft first and show it as Pending Approval.
3. Inspect relevant sources, including Cursor chats updated during the window.
4. Triage the user's current Jira tickets and compare them against recent evidence.
5. List GitHub activity in the report, including PRs created, merged, or materially updated during the window. Include `[n/a]` PRs explicitly.
6. Draft exact Jira and GitHub PR updates: creates, comments, transitions, PR link updates, and skips. For related work, draft one parent ticket and only useful immediate child tickets.
7. Save the pending draft, write the daily report, commit and push the report repo.
8. Present the report and stop for approval.
9. If the user approves all or part of the draft, apply only that portion. Keep unapproved items pending. Do not show rejected items again unless new evidence appears or the user asks to revisit them.

## Daily Report Format

Use this structure when reporting back and when writing the daily report file:

```markdown
## Daily Jira Steward Report

Window: [start time] to [end time]
Report saved at: [repo path]

## Sources Checked

- [source and scope]

## Pending Approval

- [prior pending item if any]

## GitHub Activity

- [PR created, merged, or materially updated]

## Current Jira Triage

- [ticket key, observed state, proposed action or reason no action is needed]

## Proposed Jira Updates

- Create: [summary and reason]
- Update: [ticket key, comment or field change, reason]
- Transition: [ticket key, from state to state, evidence]
- Skip: [work item, reason no Jira change is needed]

## Proposed GitHub PR Updates

- Update: [PR number, body/title/comment change, reason]

## Questions

- [Only include blockers that require user judgment]
```

If there is nothing to change, say Jira already appears aligned and list the evidence checked.
