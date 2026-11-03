#!/usr/bin/env python3
"""Send /compact to idle T3 Claude threads before their prompt cache expires.

Run every few minutes by launchd. For each Claude session T3 started, it checks how
long the session has been idle and how big its context is. When a session is inside
the idle window (default 40-50 min; the cache lasts 60) and large enough to be worth
it, it sends `/compact` to that thread with the `t3` CLI. No model runs except the
compaction itself.

  auto_compact.py --dry-run -v   show what it would do, without sending anything
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path

# handoffs.py ships with the catch-up skill (Jish2/skills, synced by skills-sync).
sys.path.insert(0, str(Path.home() / ".claude" / "skills" / "catch-up" / "scripts"))
import handoffs  # noqa: E402

T3_HOME = Path(os.environ.get("T3CODE_HOME", Path.home() / ".t3"))
T3_DB = T3_HOME / "userdata" / "statev2.sqlite"
T3_RUNTIME = T3_HOME / "userdata" / "server-runtime.json"
LEDGER = Path.home() / ".local" / "state" / "auto-compact" / "ledger.json"
# the thread is mid-turn or about to be; the relay this replaced skipped the same set
BUSY = {"running", "waiting", "queued", "starting", "preparing"}
SEND_TIMEOUT = 600
# Claude Code entrypoints of sessions T3 started (it switched to "t3-code" in 0.1.7)
T3_ENTRYPOINTS = {"sdk-ts", "t3-code"}


def log(msg: str) -> None:
    print(f"{dt.datetime.now():%Y-%m-%d %H:%M:%S} {msg}", flush=True)


def t3_cli() -> Path | None:
    """The CLI that matches the running server. ~/.local/bin/t3 can lag behind it, and
    only newer versions have `t3 thread`."""
    try:
        version = json.loads(T3_RUNTIME.read_text())["serverVersion"]
    except (OSError, ValueError, KeyError) as e:
        log(f"can't read T3 server version from {T3_RUNTIME}: {e}")
        return None
    cli = T3_HOME / "runtime" / "versions" / version / "t3"
    if not cli.exists():
        log(f"no t3 CLI for server {version} at {cli}")
        return None
    return cli


def t3_thread_for(session_id: str) -> tuple[str, str] | None:
    """Map a Claude session id to its T3 thread id and provider instance. Reads T3's private
    state DB read-only, since the CLI doesn't expose session ids; if T3 changes its schema
    this returns None and the session is skipped."""
    try:
        con = sqlite3.connect(f"file:{T3_DB}?mode=ro", uri=True, timeout=5)
        row = con.execute(
            "select thread_id, json_extract(payload_json, '$.providerInstanceId') "
            "from orchestration_v2_projection_provider_threads "
            "where json_extract(payload_json, '$.nativeThreadRef.nativeId') = ? "
            "order by updated_at desc limit 1", (session_id,)).fetchone()
        con.close()
        return (row[0], row[1]) if row else None
    except sqlite3.Error as e:
        log(f"T3 db lookup failed: {e}")
        return None


def thread_skip_reason(cli: Path, thread: str, provider: str) -> str | None:
    try:
        r = subprocess.run([str(cli), "thread", "show", "--json", "--messages", "0", thread],
                           capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            return f"t3 thread show failed: {(r.stderr or r.stdout).strip()}"
        t = json.loads(r.stdout)["thread"]
    except (subprocess.TimeoutExpired, ValueError, KeyError) as e:
        return f"t3 thread show failed: {e!r}"
    if t["status"] in BUSY:
        return f"thread is {t['status']}"
    if t["settled"] or t["archived"]:
        return "thread is settled or archived"
    if t["parentThreadId"]:
        return "thread is a subagent"
    if t["providerInstanceId"] != provider:
        return f"thread moved to {t['providerInstanceId']}"
    return None


def send_compact(cli: Path, thread: str) -> str | None:
    """Send /compact and wait for it to finish. Returns an error, or None on success."""
    try:
        r = subprocess.run([str(cli), "thread", "send", "--wait", "--json", thread, "/compact"],
                           capture_output=True, text=True, timeout=SEND_TIMEOUT)
    except subprocess.TimeoutExpired:
        # it was sent and is still running; the next run sees the compact and skips it
        return f"no result after {SEND_TIMEOUT}s"
    if r.returncode != 0:
        return (r.stderr or r.stdout).strip() or f"exit {r.returncode}"
    return None


def parse_ts(ts: str) -> dt.datetime:
    return dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))


def load_ledger() -> dict:
    try:
        return json.loads(LEDGER.read_text())
    except (OSError, ValueError):
        return {}


def prune(ledger: dict, now: dt.datetime) -> dict:
    keep = now - dt.timedelta(days=7)
    return {k: v for k, v in ledger.items() if parse_ts(v["sentAt"]) > keep}


def compacted_since_last_turn(path: Path) -> bool:
    """A compacted session still logs its old, large context until the model's next reply,
    and /compact itself restarts the idle clock, so without this it would be compacted again
    every idle stretch (even after local commands like /context)."""
    pending = False
    for e in handoffs.iter_entries(path):
        if e.get("type") == "assistant" and not e.get("isSidechain") and (e.get("message") or {}).get("usage"):
            pending = False
        elif e.get("type") == "system" and e.get("subtype") == "compact_boundary":
            pending = True
        elif "<command-name>/compact</command-name>" in (handoffs.prompt_text(e) or ""):
            pending = True
    return pending


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--idle-min", type=float, default=40, help="minutes idle before compacting (default 40)")
    ap.add_argument("--idle-max", type=float, default=50,
                    help="give up after this many idle minutes; the cache lasts 60 (default 50)")
    ap.add_argument("--min-tokens", type=int, default=60_000, help="skip smaller contexts (default 60000)")
    ap.add_argument("--dry-run", action="store_true", help="decide but don't send")
    ap.add_argument("-v", "--verbose", action="store_true", help="also log skipped sessions")
    a = ap.parse_args()

    now = dt.datetime.now(dt.timezone.utc)
    ledger = prune(load_ledger(), now)
    cli = None

    for path in handoffs.PROJECTS_DIR.glob("*/*.jsonl"):
        # Cheap prefilter on file mtime. It only bounds idle time from below: Claude Code
        # appends untimestamped records (last-prompt, cost-state) ~30 min after a session
        # goes quiet, so a recently touched file can still be inside the window.
        mtime_age = (now.timestamp() - path.stat().st_mtime) / 60
        if mtime_age > a.idle_max + 5:
            continue
        s = handoffs.parse_session(path)
        sid = s["sessionId"]
        if not s["lastActivity"]:
            continue
        idle = (now - parse_ts(s["lastActivity"])).total_seconds() / 60
        label = f"{sid[:8]} {s['title'] or s['cwd']!r} idle={idle:.0f}m ctx={s['contextTokens']}"

        skip = None
        if s["entrypoint"] not in T3_ENTRYPOINTS:
            skip = f"not a T3 session ({s['entrypoint']})"
        elif not (a.idle_min <= idle < a.idle_max):
            skip = "outside idle window"
        elif s["contextTokens"] < a.min_tokens:
            skip = "context below threshold"
        elif ledger.get(sid, {}).get("lastActivity") == s["lastActivity"]:
            skip = "already compacted this idle stretch"
        elif compacted_since_last_turn(path):
            skip = "already compacted"
        if skip:
            if a.verbose:
                log(f"skip {label}: {skip}")
            continue

        found = t3_thread_for(sid)
        if not found:
            log(f"skip {label}: no T3 thread found")
            continue
        thread, provider = found
        cli = cli or t3_cli()
        if not cli:
            return
        skip = thread_skip_reason(cli, thread, provider)
        if skip:
            log(f"skip {label}: {skip}")
            continue
        if a.dry_run:
            log(f"would compact {label} -> thread {thread}")
            continue
        err = send_compact(cli, thread)
        if err:
            log(f"compact failed {label} -> thread {thread}: {err}")
            continue
        ledger[sid] = {"lastActivity": s["lastActivity"], "sentAt": now.isoformat(), "threadId": thread}
        log(f"compacted {label} -> thread {thread}")

    if not a.dry_run:
        LEDGER.parent.mkdir(parents=True, exist_ok=True)
        LEDGER.write_text(json.dumps(ledger, indent=2))


if __name__ == "__main__":
    main()
