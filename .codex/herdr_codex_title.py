#!/usr/bin/env python3
"""Generate and apply a concise Codex CLI title to a one-pane Herdr tab."""

from __future__ import annotations

import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

TAB_ID = os.environ.get("HERDR_TAB_ID", "").strip()
CODEX_DATA_DIR = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
TITLE_MODEL = os.environ.get("HERDR_CODEX_TITLE_MODEL", "gpt-5.4-mini")
TITLE_PROMPT_PATH = CODEX_DATA_DIR / "herdr-codex-title-prompt.txt"
TITLE_CACHE_DIR = CODEX_DATA_DIR / "herdr-chat-titles"
GENERATION_TIMEOUT_SECONDS = 120
STALE_ATTEMPT_SECONDS = 300


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def write_json_atomic(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def first_text(data: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def herdr_json(args: list[str]) -> dict[str, Any] | None:
    try:
        completed = subprocess.run(
            ["herdr", *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if completed.returncode != 0 or not completed.stdout.strip():
        return None
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    result = payload.get("result")
    return result if isinstance(result, dict) else None


def tab_details() -> dict[str, Any] | None:
    result = herdr_json(["tab", "get", TAB_ID])
    if not result:
        return None
    tab = result.get("tab")
    return tab if isinstance(tab, dict) else None


def sole_pane_label() -> str | None:
    tab = tab_details()
    if not tab or tab.get("pane_count") != 1:
        return None
    label = tab.get("label")
    return label if isinstance(label, str) else ""


def rename_if_unchanged(expected_label: str, title: str) -> bool:
    current_label = sole_pane_label()
    if current_label is None or current_label != expected_label:
        return False
    try:
        completed = subprocess.run(
            ["herdr", "tab", "rename", TAB_ID, title],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return completed.returncode == 0


def state_databases() -> list[Path]:
    try:
        return sorted(
            CODEX_DATA_DIR.glob("state_*.sqlite"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
    except OSError:
        return []


def thread_record(session_id: str) -> dict[str, Any] | None:
    for database in state_databases():
        try:
            connection = sqlite3.connect(
                f"file:{database}?mode=ro", uri=True, timeout=2.0
            )
            try:
                row = connection.execute(
                    """
                    SELECT title, first_user_message, rollout_path,
                           EXISTS(
                               SELECT 1 FROM thread_spawn_edges
                               WHERE child_thread_id = threads.id
                           )
                    FROM threads WHERE id = ?
                    """,
                    (session_id,),
                ).fetchone()
            finally:
                connection.close()
        except (OSError, sqlite3.Error):
            continue
        if not row:
            continue
        return {
            "title": row[0] if isinstance(row[0], str) else "",
            "first_user_message": row[1] if isinstance(row[1], str) else "",
            "rollout_path": row[2] if isinstance(row[2], str) else "",
            "is_child": bool(row[3]),
        }
    return None


def real_user_message_count(transcript_path: Path) -> int | None:
    try:
        lines = transcript_path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    count = 0
    for line in lines:
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(item, dict) or item.get("type") != "event_msg":
            continue
        payload = item.get("payload")
        if not isinstance(payload, dict) or payload.get("type") != "user_message":
            continue
        message = payload.get("message")
        if isinstance(message, str) and message.strip():
            count += 1
    return count


def clean_title(text: str) -> str | None:
    without_thinking = re.sub(r"<think>[\s\S]*?</think>\s*", "", text)
    title = next(
        (line.strip() for line in without_thinking.splitlines() if line.strip()),
        "",
    )
    if not title:
        return None
    return title if len(title) <= 100 else title[:97] + "..."


def generate_title(first_user_message: str) -> str | None:
    codex = shutil.which("codex")
    if not codex:
        return None
    try:
        TITLE_PROMPT_PATH.read_text(encoding="utf-8")
    except OSError:
        return None

    request = (
        "Generate a title for this conversation:\n\n"
        f"<conversation>\n{first_user_message}\n</conversation>\n"
    )
    with tempfile.TemporaryDirectory(prefix="herdr-codex-title-") as temp_dir:
        output_path = Path(temp_dir) / "title.txt"
        command = [
            codex,
            "-a",
            "never",
            "exec",
            "--ignore-user-config",
            "--disable",
            "hooks",
            "--ephemeral",
            "--skip-git-repo-check",
            "--ignore-rules",
            "--sandbox",
            "read-only",
            "--color",
            "never",
            "--model",
            TITLE_MODEL,
            "-c",
            'model_reasoning_effort="low"',
            "-c",
            f'model_instructions_file="{TITLE_PROMPT_PATH}"',
            "-C",
            temp_dir,
            "--output-last-message",
            str(output_path),
            "-",
        ]
        try:
            completed = subprocess.run(
                command,
                input=request,
                check=False,
                capture_output=True,
                text=True,
                timeout=GENERATION_TIMEOUT_SECONDS,
            )
        except (OSError, subprocess.SubprocessError):
            return None
        if completed.returncode != 0:
            return None
        try:
            return clean_title(output_path.read_text(encoding="utf-8"))
        except OSError:
            return None


def completed_cache(cache_path: Path) -> dict[str, Any] | None:
    cached = read_json(cache_path)
    if not cached or cached.get("status") != "complete":
        return None
    title = cached.get("title")
    return cached if isinstance(title, str) and title.strip() else None


def claim_generation(cache_path: Path) -> bool:
    cached = read_json(cache_path)
    if cached:
        updated_at = cached.get("updated_at")
        if cached.get("status") in {"complete", "failed", "skipped"}:
            return False
        if isinstance(updated_at, (int, float)):
            if time.time() - float(updated_at) < STALE_ATTEMPT_SECONDS:
                return False
    write_json_atomic(cache_path, {"status": "generating", "updated_at": time.time()})
    return True


def main(input_path: Path) -> int:
    try:
        hook_input = read_json(input_path) or {}
    finally:
        try:
            input_path.unlink()
        except OSError:
            pass

    if not TAB_ID:
        return 0
    session_id = first_text(hook_input, "session_id", "sessionId")
    if not session_id:
        return 0
    event = (first_text(hook_input, "hook_event_name", "hookEventName") or "").lower()
    if event not in {"sessionstart", "stop"}:
        return 0

    initial_label = sole_pane_label()
    if initial_label is None:
        return 0

    record = thread_record(session_id)
    if not record or record["is_child"]:
        return 0

    cache_path = TITLE_CACHE_DIR / f"{session_id}.json"
    codex_title = str(record["title"]).strip()
    first_message = str(record["first_user_message"]).strip()
    if codex_title and first_message and codex_title != first_message:
        write_json_atomic(
            cache_path,
            {
                "status": "complete",
                "title": codex_title,
                "previous_label": initial_label,
                "source": "codex",
                "updated_at": time.time(),
            },
        )
        rename_if_unchanged(initial_label, codex_title)
        return 0

    cached = completed_cache(cache_path)
    if cached:
        generated = str(cached["title"]).strip()
        previous_label = cached.get("previous_label")
        # A resumed tab should recover its chat title. During the same session,
        # retry only if the label is still the one seen before generation;
        # otherwise preserve a manual Herdr rename.
        should_apply = (
            event == "sessionstart"
            or initial_label == generated
            or (isinstance(previous_label, str) and initial_label == previous_label)
        )
        if should_apply:
            rename_if_unchanged(initial_label, generated)
        return 0

    if event != "stop" or not first_message or not claim_generation(cache_path):
        return 0

    transcript = first_text(hook_input, "transcript_path", "transcriptPath")
    transcript_path = Path(transcript) if transcript else Path(str(record["rollout_path"]))
    count = real_user_message_count(transcript_path)
    allow_existing = os.environ.get("HERDR_CODEX_TITLE_ALLOW_EXISTING") == "1"
    if count != 1 and not allow_existing:
        write_json_atomic(
            cache_path,
            {"status": "skipped", "reason": "not-first-turn", "updated_at": time.time()},
        )
        return 0

    title = generate_title(first_message)
    if not title:
        write_json_atomic(
            cache_path,
            {"status": "failed", "reason": "codex-exec", "updated_at": time.time()},
        )
        return 0


    write_json_atomic(
        cache_path,
        {
            "status": "complete",
            "title": title,
            "previous_label": initial_label,
            "source": "codex-exec",
            "model": TITLE_MODEL,
            "updated_at": time.time(),
        },
    )
    rename_if_unchanged(initial_label, title)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(0)
    raise SystemExit(main(Path(sys.argv[1])))
