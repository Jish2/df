---
name: work-summary
description: Build weekly or biweekly work recaps by combining Cursor chat transcripts, GitHub PR activity, and Slack activity. Use when the user asks for "summarize my work", "weekly recap", "what did I do", "last week", "past 2 weeks", or asks to include chats, PRs, and/or Slack.
---

# Work Summary

Generate a concise, evidence-based recap of recent work using:
- Cursor chat transcripts
- GitHub PR history
- Slack activity (messages sent + mentions)

Default window is 7 days unless the user asks for a different range (for example "past 2 weeks").

## Inputs

- `time_window_days`: default `7`
- `include_week_over_week_split`: default `false` (set `true` for 14+ day requests)
- `include_slack`: default `true`. Set `false` if the user opts out, Slack auth is unavailable, or the request is explicitly "just chats and PRs".

If the user asks "add last week too", treat it as a 14-day summary with:
- Last 7 days
- Days 8-14

## Data sources

1. Cursor transcripts
   - Path: `/Users/jgoon/.cursor/projects/Users-jgoon-github-ros/agent-transcripts`
   - Files: `*/<uuid>.jsonl`
2. GitHub PRs for current repo
   - Use `gh pr list --author @me --state all ...`
3. Slack activity (via the `slack` skill at `~/github/skills/skills/slack/`)
   - Sent messages: `from:@<handle>` search
   - Mentions / threads the user was pulled into
   - Optional: recent activity in a small set of channels the user names

## Workflow

1. Confirm GitHub context
   - Run `gh auth status`
   - Run `git remote get-url origin`

2. Confirm Slack availability (only if `include_slack`)
   - Resolve the user's Slack handle and user id once via:
     - `uv run ~/github/skills/skills/slack/scripts/slack_cli.py user-by-email <user_email>`
   - If the CLI exits 2 (OAuth not connected) or fails with a credential broker error, fall back to skipping Slack and note it in the output. On a Mac host (not a devspace), the `rbx-skills-host-auth` skill may be required first — read it and follow the auth steps before retrying.
   - Cache the Slack handle (e.g. `jgoon`) and user id (`U…`) for subsequent calls.

3. Collect transcript activity for the window
   - Read `/Users/jgoon/.cursor/skills/cursor-chat-context/SKILL.md` and use `cursor-chat-search.py` instead of ad hoc `find`.
   - For a 7-day window: `list --since <start-date>` (or `--start` / `--end` for 14-day splits).
   - Include any transcript **active (updated) within the window**, not just created in the window.
   - Build topic clusters from list prompts; search with targeted terms when needed.
   - Keep representative transcript links as `[Short title](uuid)` from list output.
   - For 14-day requests, bucket each transcript into Week 1 vs Week 2 by its mtime, not by when it was first created.

4. Collect PR activity for the window
   - Query PRs with fields:
     - `number,title,state,createdAt,updatedAt,mergedAt,closedAt,url,headRefName,baseRefName`
   - Filter by `createdAt` inside window
   - Report totals + merged/open breakdown

5. Collect Slack activity for the window (only if `include_slack`)
   - Sent messages by the user (primary signal):
     - `uv run ~/github/skills/skills/slack/scripts/slack_cli.py search "from:@<handle>" --after <YYYY-MM-DD> --sort timestamp --sort-dir desc --limit 20`
   - Mentions of the user:
     - `uv run ~/github/skills/skills/slack/scripts/slack_cli.py search "<@U…>" --after <YYYY-MM-DD> --sort timestamp --sort-dir desc --limit 20`
   - For 14-day requests, run each search twice with `--after`/`--before` to split the two weeks.
   - From results, extract: channel name, brief topic / first line, permalink (when present), and timestamp. Group by channel and by theme.
   - Cross-reference Slack themes with chat/PR themes — call out where a Slack thread drove or unblocked a PR.
   - Skip noisy channels (bots, deploys, channel-join notices) when summarizing.

6. Compose recap
   - Include totals:
     - transcript count
     - PR count
     - merged/open counts
     - Slack: sent message count + mention count (omit cleanly if Slack was skipped)
   - Summarize major themes from chats, then weave in Slack/PR evidence under each theme rather than listing Slack separately when possible.
   - List PRs grouped as merged/open with links.
   - Include a small "Slack highlights" section with up to ~5 notable threads (incidents, decisions, cross-team asks).
   - If 14 days, add a week-over-week section.

## Output template

Use this structure (drop the Slack lines/section if Slack was skipped):

```markdown
## <Range> Summary (Cursor + PRs + Slack)

- <N> Cursor chats
- <M> PRs opened
- <A> merged / <B> open
- <S> Slack messages sent / <T> mentions

## Week 1 (last 7 days)
- Theme bullets (weave in chat + PR + Slack evidence)
- Representative chats: [Title](uuid), ...

## Week 2 (days 8-14 ago)   # only when applicable
- Theme bullets
- Representative chats: [Title](uuid), ...

## PR Activity (<range>)
### Merged
- [#123](url) title
### Open
- [#124](url) title

## Slack Highlights (<range>)
- `#channel` — short topic line ([link](permalink))
- `#channel` — short topic line ([link](permalink))

## Overall Narrative
- 2-4 bullets: impact, momentum, and carry-over work
```

## Style constraints

- Keep it concise and scannable.
- Prioritize outcomes and shipped changes over raw activity.
- Do not mention internal tooling paths in user-facing text.
- Do not cite subagent IDs; only use transcript parent UUID links.
- For Slack, never quote private DMs verbatim; summarize the topic and link to the message instead.
- If Slack auth fails, proceed with Cursor + PRs and add a one-line note that Slack was skipped (and why).
