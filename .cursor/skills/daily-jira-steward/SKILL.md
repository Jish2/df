---
name: daily-jira-steward
description: Builds a comprehensive daily work report for performance-cycle recall, refreshes the work visibility doc (me.md) and synced Google Doc, and separately maintains Jira and PR tracking from recent work, branches, Slack context, user-provided ideas, and stale tickets. Use when the user asks to run the daily Jira steward, write a daily work report, update Jira from recent work, create tracking tickets, reconcile Jira with PRs, call out neglected Jira issues, or close tickets after merges.
disable-model-invocation: true
---

# Daily Jira Steward

Use this skill as a daily checkpoint routine. Its normal job is to capture what happened between the last steward run and this steward run, update the owned visibility artifacts, then draft approval-gated updates for Jira, GitHub, and other trackers.

## Non-Negotiables

- External writes are approval-gated. Draft Jira ticket creation, comments, field changes, transitions, PR body/title updates, and other tracker writes first. Apply only the specific changes the user approves.
- Owned artifact writes do not need separate approval: the daily report repo, `me.md`, Google Doc sync, pending draft, and steward state.
- Every `me.md` update must be followed by `python3 /Users/jgoon/github/daily-reports/scripts/sync-me-to-gdoc.py`. If sync fails, still commit the local `me.md` update and tell the user the Google Doc is stale.
- The daily report is a comprehensive work log. Pending updates are only the subset of work that needs an external tracker or PR update.
- Never refer to a PR, Jira ticket, or GR ticket by number or key alone. Include the readable title or summary, such as `PR #123: Add status reconciliation` or `ROS-456: Track stale Jira review`.
- Do not create tickets for passing thoughts. Create tracking only when the user asks to track an idea or concrete evidence shows active work.
- Prefer updating existing tickets over creating duplicates.
- Never close or transition a ticket from local commits alone. Require merged PR evidence, explicit user instruction, or a clear Jira workflow signal.
- Cursor chats and Slack are mandatory evidence sources for every normal run. Always inspect both for the checkpoint window before synthesizing what happened.
- Do not silently drop reviewed evidence. When a discovered chat, PR, Slack thread, Jira ticket, or stale item is intentionally left out of the work log, `me.md`, or proposed updates, record a short reason.

## Core Workflow

### 1. Source the Evidence

Establish the checkpoint review window. The normal window is from the last completed/reviewed steward checkpoint to this run's start. If the user does not specify a window, use `pending_since_at`, then `last_reviewed_through_at`, then the fallback lookback. Set `last_started_at` before the evidence pass so the run has a stable end.

Read any pending draft first and preserve its proposed-changes table and change IDs. Include pending items as prior context, but do not apply them until approved.

Run the access gate for Jira/Atlassian, GitHub, Slack, the daily reports repo, and `gws`. If a required source fails because of auth, missing credentials, unavailable CLI/tooling, or permissions, stop and ask the user to repair access unless they explicitly approve a degraded run.

When stopping for access, name the failed source, the failed command or tool category, and the shortest next action. Do not write a clean report, refresh `me.md`, sync the Google Doc, advance `last_completed_at`, advance `last_reviewed_through_at`, or mark pending items reviewed until access is repaired or the user explicitly approves a degraded run.

Start with Cursor chats and Slack for the same checkpoint window.

Cursor chat commands:

```bash
python3 /Users/jgoon/.cursor/skills/daily-jira-steward/scripts/cursor-chat-search.py list --state-window
python3 /Users/jgoon/.cursor/skills/daily-jira-steward/scripts/cursor-chat-search.py search --state-window "ROS-123"
python3 /Users/jgoon/.cursor/skills/daily-jira-steward/scripts/cursor-chat-search.py show <chat-id>
```

`list --state-window` selects parent transcripts by file modification time from `pending_since_at` or `last_reviewed_through_at` through `last_started_at`. It includes chats updated during the window even if they were created earlier. Treat every listed parent chat prompt as a candidate work signal. Use `show <chat-id>` only for chats that need deeper reconstruction; do not dump all full chats.

When transcript message timestamps are available, summarize only messages or events inside the review window. If timestamps are unclear, include the chat as candidate evidence and summarize only concrete work signals that appear relevant.

For Slack, first read `/Users/jgoon/.agents/skills/slack/SKILL.md` and follow its read-only workflow. Always run a broad outbound search for the current user across the checkpoint window before targeted Slack searches. Then search targeted terms from Cursor, GitHub, Jira, docs, branch names, PR titles, blocker words, and follow-up language. Expand only the highest-signal Slack threads or channel-history results.

Search GitHub, Slack, Jira, local branches/commits, docs, Confluence, Google Drive, Gmail, calendar, production signals, or other relevant systems when they identify work, blockers, decisions, or completion evidence.

### 2. Determine What Happened and Publish Owned Artifacts

Synthesize one comprehensive work log from the evidence before deciding what needs external updates. Capture implementation, debugging, CI or release work, code review, planning, design review, research, stakeholder coordination, support, incident or on-call work, docs, decisions, follow-ups, blockers, and meaningful context gathering.

For each work item, include enough detail to be useful months later: workstream, what changed or progressed, artifacts, relevant blockers or decisions, and the visible next step. Group tiny fragments under the same workstream instead of creating noisy one-off bullets.

Keep an `Intentional Omissions / No Action` list for reviewed evidence that was excluded from the work log, `me.md`, or proposed updates. Reasons can be duplicate, low signal, personal/no work signal, already tracked, no action needed, or outside the review window.

Refresh `/Users/jgoon/github/daily-reports/me.md` from the synthesized work log. `me.md` is a short-lived visibility dashboard for other people, not a transcript. It should show current focus, status, blockers, next steps, and useful shareable links. Always run the Google Doc sync script after changing `me.md`.

Write or append the daily report at `/Users/jgoon/github/daily-reports/reports/YYYY-MM-DD.md` using the review-window end date in local time. Commit and push the report repo changes, then sync `me.md` to Google Docs:

```bash
git -C /Users/jgoon/github/daily-reports pull --ff-only
git -C /Users/jgoon/github/daily-reports add reports/YYYY-MM-DD.md me.md
git -C /Users/jgoon/github/daily-reports commit -m "docs: add daily report for YYYY-MM-DD"
git -C /Users/jgoon/github/daily-reports push
python3 /Users/jgoon/github/daily-reports/scripts/sync-me-to-gdoc.py
```

When only `me.md` changes, commit with `docs: refresh work visibility for YYYY-MM-DD` and still run the Google Doc sync script.

If `/Users/jgoon/github/daily-reports` is missing, clone `https://github.rbx.com/jgoon/daily-reports.git` before writing. Do not put approval-gated pending Jira/GitHub writes into `me.md` unless they are already part of the user's committed plan.

### 3. Draft Pending External Updates

From the synthesized work log, draft exact pending updates for Jira, GitHub, and any other trackers. Draft creates, comments, status transitions, field changes, PR body/title updates, PR comments, and explicit skips.

Triage current assigned/reported Jira tickets every run. Look for stale status, missing progress comments, blockers, completed work, duplicate tracking, and tickets that should be linked to recent PRs or docs.

Treat `[n/a]` in a PR title as missing tracking when the PR contains concrete work. Draft a Jira ticket plan and a PR update that links the approved ticket. For related `[n/a]` PRs in the same workstream, prefer a parent ticket with useful immediate child tickets instead of unrelated standalone tickets. Reuse existing Jira tickets when they clearly cover the work.

Use these default Jira status recommendations unless a team workflow or user instruction says otherwise:

- Concrete work found but no PR yet: move the tracking ticket to `In Progress`.
- PR is open for the ticket: move the ticket to `In Review`.
- PR is merged and still needs rollout, observation, or validation: move the ticket to `In Testing`.
- PR is merged and acceptance criteria are complete with no known follow-up: move the ticket to `Closed`.
- Parent workstream with active child tickets: keep the parent at `In Progress`.
- Parent workstream with only review-state child tickets: use `In Review` if the parent is mainly waiting on review.
- Parent workstream with all child tickets closed or verified: draft closing the parent.

Run stale-ticket searches every run:

```text
project in (ROS, ROSHELP) AND assignee = currentUser() AND statusCategory != Done AND updated <= -14d ORDER BY updated ASC
project in (ROS, ROSHELP) AND reporter = currentUser() AND statusCategory != Done AND updated <= -30d ORDER BY updated ASC
```

Stale tickets are reminder signals, not automatic writes. Include stale callouts in the report, but draft comments or transitions only when evidence supports action.

Use these stale-ticket thresholds unless the ticket, team workflow, or user instruction suggests a better bar: In Review 7+ days, In Testing 14+ days, In Progress 21+ days, To Do/Backlog/unstarted 30+ days, and any active assigned ticket 60+ days. For each stale callout, include age, current status, relationship to the user, why it may matter, and the lightest useful next step. Prefer `needs a quick look`, `candidate to close`, `waiting on external signal`, `probably still fine`, or `needs user judgment` over inventing urgency.

Save the pending draft to `~/.cursor/skills/daily-jira-steward/pending-draft.md` with the proposed-changes table before detailed notes.

### 4. Approval Gate and Apply Approved Writes

Present the daily report summary, `me.md`/Google Doc status, and pending proposed changes. Use the answers UI when available, with one selectable option per proposed write. Each option label must include the action, target identifier, and target title or summary. Add `Apply all proposed changes` only when every row is low-risk and fully evidenced. Add `Skip all for now` when there are pending writes.

Apply only rows the user explicitly approves. Keep unapproved rows pending. Do not show rejected rows again unless new evidence appears or the user asks to revisit them.

After a clean run, set `last_completed_at`, set `last_reviewed_through_at` to the review-window end, and record `last_report_path`. If proposed Jira/GitHub changes remain unapproved, keep `pending_since_at` and `pending_draft_path` set so the next run includes them.

Clear `pending_since_at` and `pending_draft_path` only after updates are applied, the user says to mark them reviewed, or there are no proposed external changes.

## Subagents

The parent agent owns the review window, state file, access gate, synthesis, report-repo writes, Google Doc sync, pending draft, answers UI, and approved external writes.

Use read-only subagents after the access gate when available. Give every subagent the exact review-window start and end, the citation rules, and a clear instruction to return concise evidence. Subagents must not mutate Jira, GitHub, Google Docs, the daily reports repo, or the steward state.

Recommended split:

- Cursor chat evidence: run `cursor-chat-search.py list --state-window`, inspect every prompt, selectively `search` and `show <chat-id>`, then return workstreams, artifacts, decisions, blockers, follow-ups, and chat IDs.
- GitHub evidence: list PRs, commits, branches, reviews, and materially updated PRs during the window across relevant repos. Call out `[n/a]` gaps, merged PRs that may close tickets, and open PRs that imply status changes.
- Slack evidence: search outbound activity first across the checkpoint window, then targeted terms from Cursor/GitHub/Jira. Return high-signal coordination, decisions, support asks, blockers, important misses, and only the highest-signal expanded threads.
- Jira triage evidence: read current assigned/reported tickets, tickets linked from evidence, and stale-ticket searches. Return status mismatches, likely duplicates, needed comments, no-action tickets, and stale callouts.

Ask each subagent to return:

```markdown
## Source Checked
[tooling, queries, window]

## Work Signals
- [workstream]: [what happened, evidence, artifact links or local chat IDs, next step/blocker]

## Tracking Implications
- [Jira/PR candidate update, skip reason, or stale callout]

## Intentional Omissions
- [reviewed evidence intentionally left out and why]

## Important Misses or Blockers
- [searches that found nothing useful, auth/rate-limit gaps, uncertainty]
```

If sources disagree, prefer direct artifact evidence and note uncertainty in the report or Questions section instead of inventing a conclusion.

## Source Notes

For Jira in the ROS workspace, first read `.cursor/skills/ros-atlassian/SKILL.md` and follow its routing. Outside ROS, use the available Jira or Atlassian skill. For GitHub, prefer `gh`.

For Slack, first read `/Users/jgoon/.agents/skills/slack/SKILL.md` and follow its read-only workflow. Always run a Slack pass for the checkpoint window between the previous reviewed point and this run's `last_started_at`. Treat Slack as work-signal evidence, not transcript material. Capture decisions, requests, coordination, blockers, rollout notes, support triage, follow-ups, and stakeholder confirmations. Ignore standalone acknowledgements such as `thanks`, `no problem`, or emoji-only messages unless they anchor useful context.

Expand only the highest-signal Slack threads or channel-history results. If a Slack `thread` or `history` command hits rate limits, fails repeatedly, or appears stuck, stop after one failed expansion attempt for that item. Record the snippet, channel/thread link, and that expansion was skipped.

Record both useful Slack hits and important Slack misses. Expand outside the window only when needed for context, such as reading a thread that started earlier or following a referenced decision.

Prefer direct evidence over inference. Do not copy long chat excerpts or sensitive details into Jira unless necessary for tracking the work.

## State

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

State file: `~/.cursor/skills/daily-jira-steward/state.json`.

Pending draft: `~/.cursor/skills/daily-jira-steward/pending-draft.md`.

Daily reports repo: `/Users/jgoon/github/daily-reports`.

`me.md` Google Doc mirror: `https://docs.google.com/document/d/1YB1z9XYfCdxXiVbDSy_Fl8DorysXuZzqtbVn8nHx1vA/edit`.

## Artifact Templates

When writing or refreshing `me.md`, the daily report, or the pending draft, read `templates.md` in this skill directory and follow the relevant template. Keep the main workflow in this file as the source of truth for when each artifact is written.