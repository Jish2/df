---
name: work-summary
description: Build weekly or biweekly work recaps by combining Cursor chat transcripts and GitHub PR activity. Use when the user asks for "summarize my work", "weekly recap", "what did I do", "last week", "past 2 weeks", or asks to include both chats and PRs.
---

# Work Summary

Generate a concise, evidence-based recap of recent work using:
- Cursor chat transcripts
- GitHub PR history

Default window is 7 days unless the user asks for a different range (for example "past 2 weeks").

## Inputs

- `time_window_days`: default `7`
- `include_week_over_week_split`: default `false` (set `true` for 14+ day requests)

If the user asks "add last week too", treat it as a 14-day summary with:
- Last 7 days
- Days 8-14

## Data sources

1. Cursor transcripts
   - Path: `/Users/jgoon/.cursor/projects/Users-jgoon-github-ros/agent-transcripts`
   - Files: `*/<uuid>.jsonl`
2. GitHub PRs for current repo
   - Use `gh pr list --author @me --state all ...`

## Workflow

1. Confirm GitHub context
   - Run `gh auth status`
   - Run `git remote get-url origin`

2. Collect transcript activity for the window
   - Filter transcript files by file mtime within N days
   - For each transcript, extract the first user message
   - Build topic clusters from prompts (migration linter, CI tests, infra, etc.)
   - Keep representative transcript links in format `[Short title](uuid-without-.jsonl)`

3. Collect PR activity for the window
   - Query PRs with fields:
     - `number,title,state,createdAt,updatedAt,mergedAt,closedAt,url,headRefName,baseRefName`
   - Filter by `createdAt` inside window
   - Report totals + merged/open breakdown

4. Compose recap
   - Include totals:
     - transcript count
     - PR count
     - merged/open counts
   - Summarize major themes from chats
   - List PRs grouped as merged/open with links
   - If 14 days, add a week-over-week section

## Output template

Use this structure:

```markdown
## <Range> Summary (Cursor + PRs)

- <N> Cursor chats
- <M> PRs opened
- <A> merged / <B> open

## Week 1 (last 7 days)
- Theme bullets
- Representative chats: [Title](uuid), ...

## Week 2 (days 8-14 ago)   # only when applicable
- Theme bullets
- Representative chats: [Title](uuid), ...

## PR Activity (<range>)
### Merged
- [#123](url) title
### Open
- [#124](url) title

## Overall Narrative
- 2-4 bullets: impact, momentum, and carry-over work
```

## Style constraints

- Keep it concise and scannable.
- Prioritize outcomes and shipped changes over raw activity.
- Do not mention internal tooling paths in user-facing text.
- Do not cite subagent IDs; only use transcript parent UUID links.
