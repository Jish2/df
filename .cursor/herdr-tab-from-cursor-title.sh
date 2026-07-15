#!/bin/sh
# Renames the Herdr tab to the Cursor Agent CLI session title when this
# pane is the only pane on the tab.
#
# Not managed by Herdr — safe to keep beside herdr-agent-state.sh.
# Wired from ~/.cursor/hooks.json (sessionStart, afterAgentResponse, stop).

set -eu

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_TAB_ID:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
command -v herdr >/dev/null 2>&1 || exit 0

hook_input_file="$(mktemp "${TMPDIR:-/tmp}/herdr-cursor-tab-title.XXXXXX")" || exit 0
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

HERDR_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY'
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

TAB_ID = os.environ.get("HERDR_TAB_ID", "").strip()
HOOK_INPUT_FILE = os.environ.get("HERDR_HOOK_INPUT_FILE", "")
CHATS_ROOT = Path.home() / ".cursor" / "chats"

# sessionStart often fires before Cursor writes meta.title — poll longer.
# later hooks usually already have a title.
POLL_SECONDS = {
    "sessionstart": 90.0,
    "afteragentresponse": 8.0,
    "stop": 8.0,
}
POLL_INTERVAL = 1.5


def load_hook_input() -> dict:
    if not HOOK_INPUT_FILE:
        return {}
    try:
        text = Path(HOOK_INPUT_FILE).read_text(encoding="utf-8")
        if not text.strip():
            return {}
        data = json.loads(text)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def first_text(data: dict, *keys: str) -> str | None:
    for key in keys:
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def herdr_json(args: list[str]) -> dict | None:
    try:
        completed = subprocess.run(
            ["herdr", *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception:
        return None
    if completed.returncode != 0 or not completed.stdout.strip():
        return None
    try:
        payload = json.loads(completed.stdout)
    except Exception:
        return None
    if not isinstance(payload, dict):
        return None
    result = payload.get("result")
    return result if isinstance(result, dict) else None


def tab_pane_count(tab_id: str) -> int | None:
    result = herdr_json(["tab", "get", tab_id])
    if not result:
        return None
    tab = result.get("tab")
    if not isinstance(tab, dict):
        return None
    count = tab.get("pane_count")
    return count if isinstance(count, int) else None


def tab_label(tab_id: str) -> str | None:
    result = herdr_json(["tab", "get", tab_id])
    if not result:
        return None
    tab = result.get("tab")
    if not isinstance(tab, dict):
        return None
    label = tab.get("label")
    return label if isinstance(label, str) else None


def find_session_title(conversation_id: str) -> str | None:
    if not conversation_id or not CHATS_ROOT.is_dir():
        return None
    matches = list(CHATS_ROOT.glob(f"*/{conversation_id}/meta.json"))
    if not matches:
        # Fallback: rare layouts / renamed trees
        matches = list(CHATS_ROOT.glob(f"**/{conversation_id}/meta.json"))
    for meta_path in matches:
        try:
            data = json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        title = data.get("title")
        if isinstance(title, str) and title.strip():
            return title.strip()
    return None


def rename_tab(tab_id: str, title: str) -> bool:
    try:
        completed = subprocess.run(
            ["herdr", "tab", "rename", tab_id, title],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception:
        return False
    return completed.returncode == 0


def sole_pane_on_tab(tab_id: str) -> bool:
    count = tab_pane_count(tab_id)
    return count == 1


def try_sync(conversation_id: str) -> bool:
    if not sole_pane_on_tab(TAB_ID):
        return False
    title = find_session_title(conversation_id)
    if not title:
        return False
    current = tab_label(TAB_ID)
    if current == title:
        return True
    # Re-check immediately before rename in case a split happened while polling.
    if not sole_pane_on_tab(TAB_ID):
        return False
    return rename_tab(TAB_ID, title)


def main() -> int:
    if not TAB_ID:
        return 0

    hook_input = load_hook_input()
    conversation_id = first_text(
        hook_input,
        "conversation_id",
        "conversationId",
        "session_id",
        "sessionId",
    )
    if not conversation_id:
        return 0

    event = (first_text(hook_input, "hook_event_name", "hookEventName") or "").lower()
    deadline = time.monotonic() + POLL_SECONDS.get(event, 8.0)

    while True:
        if try_sync(conversation_id):
            return 0
        # Bail early when the tab already has siblings — never overwrite those.
        if tab_pane_count(TAB_ID) not in (None, 1):
            return 0
        if time.monotonic() >= deadline:
            return 0
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    sys.exit(main())
PY
