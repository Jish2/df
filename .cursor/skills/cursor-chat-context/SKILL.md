---
name: cursor-chat-context
description: Lists, searches, and renders local Cursor agent chat transcripts so prior sessions can be cited or summarized as evidence in a new chat. Use when resurfacing past Cursor work, finding decisions or implementation notes in transcripts, gathering chat evidence for daily reports or Jira tickets, or answering "what did we do in that chat".
---

# Cursor Chat Context

Use this skill whenever a task needs **prior Cursor sessions** as evidence: work recaps, ticket drafts, handoffs, debugging continuity, or "find the chat where we decided X."

Transcripts live under `~/.cursor/projects/<project-key>/agent-transcripts/` as `*.jsonl` files. **By default** `list` and `search` scan **all** projects under `~/.cursor/projects/`. Pass `--project-root` to limit to one workspace (e.g. `/Users/jgoon/github/ros`), or `--transcripts-root` for a single explicit folder.

Script path (stable):

```text
/Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py
```

## Quick commands

List chats touched in a time window (by file mtime):

```bash
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py list --since 2026-05-28
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py list --since 2026-05-28 --project-root /Users/jgoon/github/ros
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py list --date 2026-05-29
```

Search transcript text:

```bash
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py search --since 2026-05-28 "ROS-123"
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py search --since 2026-05-28 --regex 'frontend-slides|impact'
```

Render one chat (use only when list/search is not enough):

```bash
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py show <chat-id>
```

Add `--json` to `list` or `search` for machine-readable output.

## Scope

| Flag | Behavior |
|------|----------|
| *(none)* | All `~/.cursor/projects/*/agent-transcripts` (default) |
| `--project-root <path>` | Single workspace only |
| `--transcripts-root <path>` | One explicit transcripts directory |

Multi-project `list`/`search` output includes `project=<key>` on each row.

## Search matching

**Default (no `--regex`):** the query is a **literal substring**. Special characters are not regex syntax — they match themselves:

| You type | Matches |
|----------|---------|
| `ROS-123` | the text `ROS-123` |
| `eks.*1.31|staging` | that exact string, including `.`, `*`, and `|` |
| `foo|bar` | the characters `foo|bar`, not `foo` OR `bar` |

Use this for ticket keys, filenames, error strings, and fixed phrases.

**With `--regex`:** the query is a **Python regular expression** (case-insensitive unless `--case-sensitive`). Then `|`, `.*`, `\\d+`, groups, etc. work as regex:

```bash
# OR across phrases; .* = any characters between parts
python3 /Users/jgoon/.cursor/skills/cursor-chat-context/scripts/cursor-chat-search.py search \
  --since 2026-05-01 --project-root /Users/jgoon/github/ros --regex \
  'eks.*1\.31|staging.*eks|dev.*eks.*upgrade'
```

Prefer **single-quoted** queries for regex so the shell does not expand `*` or interpret `|`. Escape dots in version numbers (`1\.31`) when you mean a literal dot.

If a regex search returns almost nothing but you expected many hits, you probably omitted `--regex` and searched for literal `|` or `.*`.

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

Pass `--state-file` with the path to the owning skill's checkpoint state JSON.

## Workflow

1. **List** chats in the window. Treat every parent-chat first prompt as a candidate signal.
2. **Search** targeted terms before opening full transcripts. Use plain queries for literals; add `--regex` when you need OR (`|`), wildcards (`.*`), or other pattern syntax.
3. **Show** only high-signal chats. Prefer summaries over dumping entire transcripts into the current chat.
4. **Cite** parent chats as `[Short title](uuid)` using the citation from `list` output. Never cite subagent transcript IDs to the user.
5. **Respect privacy** — ask before summarizing content that may include PII, credentials, or HR-sensitive data. Do not paste long sensitive excerpts into Jira or public docs.

When message-level timestamps are available in the transcript, summarize only events inside the review window. If timestamps are unclear, include the chat as candidate evidence and summarize concrete work signals only.
