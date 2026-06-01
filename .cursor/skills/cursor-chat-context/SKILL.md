---
name: cursor-chat-context
description: Lists, searches, and renders local Cursor agent chat transcripts so prior sessions can be cited or summarized as evidence in a new chat. Use when resurfacing past Cursor work, finding decisions or implementation notes in transcripts, gathering chat evidence for daily reports or Jira tickets, or answering "what did we do in that chat".
---

# Cursor Chat Context

Use this skill whenever a task needs **prior Cursor sessions** as evidence: work recaps, ticket drafts, handoffs, debugging continuity, or "find the chat where we decided X."

Transcripts live under `~/.cursor/projects/<project-key>/agent-transcripts/` as `*.jsonl` files. By default the CLI infers the folder from `--project-root` (ROS: `/Users/jgoon/github/ros`). Override with `--transcripts-root` for other workspaces.

Script path (stable):

```text
/Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py
```

## Quick commands

List chats touched in a time window (by file mtime):

```bash
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py list --since 2026-05-28
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py list --date 2026-05-29
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py list --start 2026-05-28T09:00:00-07:00 --end 2026-05-29T18:00:00-07:00
```

Search transcript text:

```bash
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py search --since 2026-05-28 "ROS-123"
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py search --since 2026-05-28 --regex "frontend-slides|impact"
```

Render one chat (use only when list/search is not enough):

```bash
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py show <chat-id>
```

Add `--json` to `list` or `search` for machine-readable output.

## Window selection

Use **exactly one** window mode per command:

| Mode | Flags | Use when |
|------|-------|----------|
| Since | `--since <iso-or-date>` | Rolling lookback (work summary, ad hoc search) |
| Day | `--date YYYY-MM-DD` | Single local calendar day |
| Range | `--start` + optional `--end` | Explicit checkpoint (end is exclusive) |
| State file | `--state-window --state-file <path>` | Another skill owns checkpoint timestamps |

`list` and `search` filter by **transcript file mtime** inside the window. Chats created earlier but updated in the window are included.

### State-file windows

`--state-window` reads JSON start/end fields so checkpoint skills do not duplicate date math:

- **Start** (first non-null): `window_start_at`, `pending_since_at`, `last_reviewed_through_at`
- **End** (first non-null, else now): `window_end_at`, `last_started_at`

Example for Daily Jira Steward after setting `last_started_at`:

```bash
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py list \
  --state-window \
  --state-file /Users/jgoon/.cursor/skills/daily-jira-steward/state.json
```

## Workflow

1. **List** chats in the window. Treat every parent-chat first prompt as a candidate signal.
2. **Search** targeted terms (ticket keys, feature names, filenames, error strings) before opening full transcripts.
3. **Show** only high-signal chats. Prefer summaries over dumping entire transcripts into the current chat.
4. **Cite** parent chats as `[Short title](uuid)` using the citation from `list` output. Never cite subagent transcript IDs to the user.
5. **Respect privacy** — ask before summarizing content that may include PII, credentials, or HR-sensitive data. Do not paste long sensitive excerpts into Jira or public docs.

When message-level timestamps are available in the transcript, summarize only events inside the review window. If timestamps are unclear, include the chat as candidate evidence and summarize concrete work signals only.

## Integration

- **daily-jira-steward** — mandatory chat evidence for each checkpoint; uses `--state-window` with the steward `state.json`.
- **work-summary** — use `--since` for the recap window instead of manual `find`.
- **jira-tickets** — search transcripts for related implementation context before drafting tickets.

## Subagent handoff

When delegating read-only chat evidence collection, pass the exact window, project root, citation rules, and this script path. Return workstreams, artifacts, decisions, blockers, follow-ups, and parent chat IDs — not full transcript dumps.
