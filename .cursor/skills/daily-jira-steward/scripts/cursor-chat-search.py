#!/usr/bin/env python3
"""List, search, and render Cursor agent transcripts for daily steward runs."""

from __future__ import annotations

import argparse
import json
import os
import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlparse


DEFAULT_PROJECT_ROOT = Path("/Users/jgoon/github/ros")
DEFAULT_STATE_FILE = Path("/Users/jgoon/.cursor/skills/daily-jira-steward/state.json")
LOCAL_TZ = datetime.now().astimezone().tzinfo


@dataclass(frozen=True)
class TimeWindow:
    start: datetime | None
    end: datetime | None
    label: str


@dataclass(frozen=True)
class Chat:
    id: str
    path: Path
    mtime: datetime
    line_count: int
    title: str
    prompt: str
    citation: str
    is_subagent: bool


@dataclass(frozen=True)
class ChatEvent:
    role: str
    text: str


def parse_local_datetime(value: str) -> datetime:
    normalized = value.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", normalized):
        return datetime.combine(date.fromisoformat(normalized), time.min, tzinfo=LOCAL_TZ)
    if normalized.endswith("Z"):
        normalized = f"{normalized[:-1]}+00:00"
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=LOCAL_TZ)
    return parsed.astimezone(LOCAL_TZ)


def build_window(args: argparse.Namespace) -> TimeWindow:
    window_args = [
        bool(getattr(args, "state_window", False)),
        bool(args.date),
        bool(args.since),
        bool(args.start or args.end),
    ]
    if sum(window_args) > 1:
        raise SystemExit("Use only one window selector: --state-window, --date, --since, or --start/--end.")

    if getattr(args, "state_window", False):
        return build_state_window(Path(args.state_file).expanduser().resolve())

    if args.since:
        start = parse_local_datetime(args.since)
        return TimeWindow(start=start, end=None, label=f"since {start.isoformat()}")

    if args.date:
        start = datetime.combine(date.fromisoformat(args.date), time.min, tzinfo=LOCAL_TZ)
        return TimeWindow(start=start, end=start + timedelta(days=1), label=args.date)

    start = parse_local_datetime(args.start) if args.start else None
    end = parse_local_datetime(args.end) if args.end else None
    if start and end:
        label = f"{start.isoformat()} to {end.isoformat()}"
    elif start:
        label = f"after {start.isoformat()}"
    elif end:
        label = f"before {end.isoformat()}"
    else:
        label = "all time"
    return TimeWindow(start=start, end=end, label=label)


def build_state_window(state_file: Path) -> TimeWindow:
    if not state_file.exists():
        raise SystemExit(f"State file does not exist: {state_file}")
    with state_file.open("r", encoding="utf-8") as handle:
        state = json.load(handle)

    start_value = state.get("pending_since_at") or state.get("last_reviewed_through_at")
    end_value = state.get("last_started_at")
    if not start_value:
        raise SystemExit(f"State file has no pending_since_at or last_reviewed_through_at: {state_file}")

    start = parse_local_datetime(start_value)
    parsed_end = parse_local_datetime(end_value) if end_value else None
    end = parsed_end if parsed_end and parsed_end > start else datetime.now(tz=LOCAL_TZ)
    if end <= start:
        raise SystemExit(f"State window end must be after start: {start.isoformat()} to {end.isoformat()}")
    return TimeWindow(start=start, end=end, label=f"state window {start.isoformat()} to {end.isoformat()}")


def project_key(project_root: Path) -> str:
    return str(project_root.expanduser().resolve()).lstrip(os.sep).replace(os.sep, "-")


def transcript_root(args: argparse.Namespace) -> Path:
    if args.transcripts_root:
        return Path(args.transcripts_root).expanduser().resolve()
    project_root = Path(args.project_root).expanduser().resolve()
    return Path.home() / ".cursor" / "projects" / project_key(project_root) / "agent-transcripts"


def iter_transcript_paths(root: Path, include_subagents: bool) -> Iterable[Path]:
    if not root.exists():
        raise SystemExit(f"Transcript root does not exist: {root}")
    for path in root.glob("**/*.jsonl"):
        if not include_subagents and "subagents" in path.parts:
            continue
        yield path


def in_window(path: Path, window: TimeWindow) -> bool:
    mtime = datetime.fromtimestamp(path.stat().st_mtime, tz=LOCAL_TZ)
    if window.start and mtime < window.start:
        return False
    if window.end and mtime >= window.end:
        return False
    return True


def content_text(value: Any, *, include_tool_json: bool) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(part for item in value if (part := content_text(item, include_tool_json=include_tool_json)))
    if not isinstance(value, dict):
        return str(value)

    item_type = value.get("type")
    if item_type == "text":
        return str(value.get("text", ""))
    if item_type == "tool_use":
        name = value.get("name", "tool")
        if not include_tool_json:
            return f"[tool_use {name}]"
        payload = json.dumps(value.get("input", {}), ensure_ascii=False, sort_keys=True)
        return f"[tool_use {name}]\n{payload}"
    if item_type == "tool_result":
        result = content_text(value.get("content"), include_tool_json=include_tool_json)
        return f"[tool_result]\n{result}" if result else "[tool_result]"

    for key in ("text", "content", "message", "output", "error"):
        if key in value:
            return content_text(value[key], include_tool_json=include_tool_json)
    return ""


def read_events(path: Path, *, include_tool_json: bool = True) -> list[ChatEvent]:
    events: list[ChatEvent] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                events.append(ChatEvent(role="unknown", text=line.rstrip()))
                continue

            role = str(payload.get("role", "unknown"))
            message = payload.get("message", {})
            content = message.get("content") if isinstance(message, dict) else payload.get("content")
            text = content_text(content, include_tool_json=include_tool_json).strip()
            if text:
                events.append(ChatEvent(role=role, text=text))
    return events


def extract_user_query(text: str) -> str:
    text = re.sub(r"<manually_attached_skills>.*?</manually_attached_skills>", "", text, flags=re.S)
    query = re.search(r"<user_query>\s*(.*?)\s*</user_query>", text, flags=re.S)
    if query:
        return query.group(1)
    text = re.sub(r"<timestamp>.*?</timestamp>", "", text, flags=re.S)
    text = re.sub(r"<[^>]+>", " ", text)
    return text


def title_for_events(events: list[ChatEvent], fallback: str) -> str:
    prompt = first_prompt_for_events(events)
    if not prompt:
        return fallback
    cleaned = re.sub(r"https?://[^\s)>\]]+", lambda match: urlparse(match.group(0)).netloc or "link", prompt)
    words = re.findall(r"[\w#./:-]+", cleaned)
    title = " ".join(words[:6]) or fallback
    if len(title) > 80:
        title = f"{title[:77].rstrip()}..."
    return title


def first_prompt_for_events(events: list[ChatEvent]) -> str:
    first_user = next((event.text for event in events if event.role == "user"), "")
    return " ".join(extract_user_query(first_user).split())


def chat_from_path(path: Path) -> Chat:
    events = read_events(path, include_tool_json=False)
    chat_id = path.stem
    title = title_for_events(events, fallback=chat_id)
    prompt = first_prompt_for_events(events)
    mtime = datetime.fromtimestamp(path.stat().st_mtime, tz=LOCAL_TZ)
    is_subagent = "subagents" in path.parts
    citation = f"[{title}]({chat_id})" if not is_subagent else chat_id
    return Chat(
        id=chat_id,
        path=path,
        mtime=mtime,
        line_count=len(events),
        title=title,
        prompt=prompt,
        citation=citation,
        is_subagent=is_subagent,
    )


def selected_chats(args: argparse.Namespace) -> list[Chat]:
    root = transcript_root(args)
    window = build_window(args)
    chats = [
        chat_from_path(path)
        for path in iter_transcript_paths(root, args.include_subagents)
        if in_window(path, window)
    ]
    return sorted(chats, key=lambda chat: chat.mtime, reverse=True)


def resolve_chat_path(args: argparse.Namespace, chat_ref: str) -> Path:
    maybe_path = Path(chat_ref).expanduser()
    if maybe_path.exists():
        return maybe_path.resolve()

    root = transcript_root(args)
    matches = [
        path
        for path in iter_transcript_paths(root, include_subagents=True)
        if path.stem == chat_ref or path.stem.startswith(chat_ref)
    ]
    if not matches:
        raise SystemExit(f"No transcript matched {chat_ref!r} under {root}")
    if len(matches) > 1:
        choices = "\n".join(str(path) for path in matches[:10])
        raise SystemExit(f"Multiple transcripts matched {chat_ref!r}; use a longer id:\n{choices}")
    return matches[0]


def chat_to_dict(chat: Chat) -> dict[str, Any]:
    return {
        "id": chat.id,
        "title": chat.title,
        "prompt": chat.prompt,
        "citation": chat.citation,
        "updated_at": chat.mtime.isoformat(),
        "messages": chat.line_count,
        "path": str(chat.path),
        "is_subagent": chat.is_subagent,
    }


def render_chat(chat: Chat, *, include_tool_json: bool) -> str:
    events = read_events(chat.path, include_tool_json=include_tool_json)
    parts = [
        f"# {chat.title}",
        "",
        f"Chat ID: {chat.id}",
        f"Updated: {chat.mtime.isoformat()}",
        f"Citation: {chat.citation}",
        f"Path: {chat.path}",
        "",
    ]
    for index, event in enumerate(events, start=1):
        parts.append(f"## {index}. {event.role}")
        parts.append("")
        parts.append(event.text)
        parts.append("")
    return "\n".join(parts).rstrip()


def render_snippet(text: str, match: re.Match[str], context_chars: int) -> str:
    start = max(0, match.start() - context_chars)
    end = min(len(text), match.end() + context_chars)
    snippet = text[start:end].replace("\n", " ")
    prefix = "..." if start > 0 else ""
    suffix = "..." if end < len(text) else ""
    matched = text[match.start() : match.end()].replace("\n", " ")
    snippet_start = match.start() - start
    snippet_end = snippet_start + len(matched)
    return f"{prefix}{snippet[:snippet_start]}<<{snippet[snippet_start:snippet_end]}>>{snippet[snippet_end:]}{suffix}"


def command_list(args: argparse.Namespace) -> int:
    chats = selected_chats(args)
    if args.json:
        print(json.dumps([chat_to_dict(chat) for chat in chats], indent=2))
        return 0

    window = build_window(args)
    print(f"Cursor chats updated in {window.label}: {len(chats)}")
    for chat in chats:
        subagent = " subagent" if chat.is_subagent else ""
        print(
            f"{chat.mtime.strftime('%Y-%m-%d %H:%M:%S %Z')}  "
            f"{chat.citation}  messages={chat.line_count}{subagent}"
        )
        print(f"  id: {chat.id}")
        if chat.prompt:
            print(f"  prompt: {chat.prompt}")
    return 0


def command_search(args: argparse.Namespace) -> int:
    flags = 0 if args.case_sensitive else re.IGNORECASE
    pattern = args.query if args.regex else re.escape(args.query)
    regex = re.compile(pattern, flags)
    results: list[dict[str, Any]] = []

    for chat in selected_chats(args):
        events = read_events(chat.path, include_tool_json=True)
        haystack = "\n\n".join(f"{event.role}: {event.text}" for event in events)
        hits = []
        for match in regex.finditer(haystack):
            hits.append(
                {
                    "snippet": render_snippet(haystack, match, args.context_chars),
                    "start": match.start(),
                }
            )
            if len(hits) >= args.per_chat_limit:
                break
        if hits:
            results.append({"chat": chat_to_dict(chat), "hits": hits})
            if len(results) >= args.limit:
                break

    if args.json:
        print(json.dumps(results, indent=2))
        return 0

    print(f"Search: {args.query!r}")
    print(f"Chats with hits: {len(results)}")
    for result in results:
        chat = result["chat"]
        print(f"\n{chat['updated_at']}  {chat['citation']}")
        print(f"  id: {chat['id']}")
        for index, hit in enumerate(result["hits"], start=1):
            print(f"  hit {index}: {hit['snippet']}")
    return 0


def command_show(args: argparse.Namespace) -> int:
    path = resolve_chat_path(args, args.chat)
    chat = chat_from_path(path)
    print(render_chat(chat, include_tool_json=args.include_tool_json))
    return 0


def add_window_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--state-window", action="store_true", help="Use pending_since_at/last_reviewed_through_at through last_started_at from the steward state file.")
    parser.add_argument("--state-file", default=str(DEFAULT_STATE_FILE), help="Daily Jira Steward state file for --state-window.")
    parser.add_argument("--date", help="Local day to inspect, as YYYY-MM-DD.")
    parser.add_argument("--since", help="Inclusive local/ISO start timestamp with no end; use for from this date through now.")
    parser.add_argument("--start", help="Inclusive local/ISO start timestamp.")
    parser.add_argument("--end", help="Exclusive local/ISO end timestamp.")


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--project-root", default=str(DEFAULT_PROJECT_ROOT), help="Workspace root used to infer Cursor's project transcript folder.")
    parser.add_argument("--transcripts-root", help="Explicit agent-transcripts directory.")
    parser.add_argument("--include-subagents", action="store_true", help="Include subagent transcripts. Parent chats are used by default.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="List chat transcripts updated in a date window.")
    add_common_args(list_parser)
    add_window_args(list_parser)
    list_parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    list_parser.set_defaults(func=command_list)

    search_parser = subparsers.add_parser("search", help="Search transcript text in a date window.")
    add_common_args(search_parser)
    add_window_args(search_parser)
    search_parser.add_argument("query", help="Search string or regex pattern.")
    search_parser.add_argument("--regex", action="store_true", help="Treat query as a regular expression.")
    search_parser.add_argument("--case-sensitive", action="store_true", help="Use case-sensitive matching.")
    search_parser.add_argument("--context-chars", type=int, default=160, help="Characters of context around each hit.")
    search_parser.add_argument("--limit", type=int, default=20, help="Maximum chats to return.")
    search_parser.add_argument("--per-chat-limit", type=int, default=5, help="Maximum hits per chat.")
    search_parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    search_parser.set_defaults(func=command_search)

    show_parser = subparsers.add_parser("show", help="Render one full chat by id prefix or path.")
    add_common_args(show_parser)
    show_parser.add_argument("chat", help="Chat id, id prefix, or transcript path.")
    show_parser.add_argument("--include-tool-json", action="store_true", help="Include full tool call inputs and tool result content.")
    show_parser.set_defaults(func=command_show)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
