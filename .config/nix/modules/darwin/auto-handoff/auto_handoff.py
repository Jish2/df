#!/usr/bin/env python3
"""Ask idle T3 Claude threads to write a handoff before their prompt cache expires.

Run every few minutes by launchd. For each Claude session T3 started, it checks how
long the session has been idle and how big its context is. When a session is inside
the idle window (default 40-50 min; the cache lasts 60) and large enough to be worth
it, it POSTs a signed request to a T3 webhook task, whose agent sends the handoff
message into that thread. No model runs unless a thread qualifies.

  auto_handoff.py --dry-run -v   show what it would do, without sending anything
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import hmac
import json
import os
import sqlite3
import subprocess
import sys
import urllib.request
from pathlib import Path

# handoffs.py ships with the catch-up skill (Jish2/skills, synced by skills-sync).
sys.path.insert(0, str(Path.home() / ".claude" / "skills" / "catch-up" / "scripts"))
import handoffs  # noqa: E402

T3_DB = Path(os.environ.get("T3CODE_HOME", Path.home() / ".t3")) / "userdata" / "statev2.sqlite"
LEDGER = handoffs.HANDOFFS_DIR / ".auto-handoff-ledger.json"
KEYCHAIN_URL = "session-handoff-webhook-url"
KEYCHAIN_SECRET = "session-handoff-webhook-secret"


def log(msg: str) -> None:
    print(f"{dt.datetime.now():%Y-%m-%d %H:%M:%S} {msg}", flush=True)


def keychain(service: str) -> str | None:
    r = subprocess.run(["security", "find-generic-password", "-a", os.environ.get("USER", ""), "-s", service, "-w"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def t3_thread_for(session_id: str) -> str | None:
    """Map a Claude session id to its T3 thread id. Reads T3's private state DB read-only;
    if T3 changes its schema this returns None and the session is skipped."""
    try:
        con = sqlite3.connect(f"file:{T3_DB}?mode=ro", uri=True, timeout=5)
        row = con.execute(
            "select thread_id from orchestration_v2_projection_provider_threads "
            "where json_extract(payload_json, '$.nativeThreadRef.nativeId') = ? "
            "order by updated_at desc limit 1", (session_id,)).fetchone()
        con.close()
        return row[0] if row else None
    except sqlite3.Error as e:
        log(f"T3 db lookup failed: {e}")
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


def post(url: str, secret: str, payload: dict) -> None:
    body = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    sig = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Content-Type": "application/json",
        "X-Auto-Handoff-Signature": f"sha256={sig}",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        if r.status >= 300:
            raise RuntimeError(f"webhook returned {r.status}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--idle-min", type=float, default=40, help="minutes idle before handing off (default 40)")
    ap.add_argument("--idle-max", type=float, default=50,
                    help="give up after this many idle minutes; the cache lasts 60 (default 50)")
    ap.add_argument("--min-tokens", type=int, default=60_000, help="skip smaller contexts (default 60000)")
    ap.add_argument("--dry-run", action="store_true", help="decide but don't send")
    ap.add_argument("-v", "--verbose", action="store_true", help="also log skipped sessions")
    a = ap.parse_args()

    now = dt.datetime.now(dt.timezone.utc)
    ledger = prune(load_ledger(), now)
    url = os.environ.get("SESSION_HANDOFF_WEBHOOK_URL") or (None if a.dry_run else keychain(KEYCHAIN_URL))
    secret = os.environ.get("SESSION_HANDOFF_WEBHOOK_SECRET") or (None if a.dry_run else keychain(KEYCHAIN_SECRET))
    if not a.dry_run and not (url and secret):
        log(f"missing webhook url/secret in Keychain ({KEYCHAIN_URL}, {KEYCHAIN_SECRET}); see FLEET.md \"Auto-handoff\"")
        sys.exit(1)

    for path in handoffs.PROJECTS_DIR.glob("*/*.jsonl"):
        # Cheap prefilter on file mtime; the transcript is only parsed near the window.
        mtime_age = (now.timestamp() - path.stat().st_mtime) / 60
        if not (a.idle_min - 5 <= mtime_age <= a.idle_max + 5):
            continue
        s = handoffs.parse_session(path)
        sid = s["sessionId"]
        if not s["lastActivity"]:
            continue
        idle = (now - parse_ts(s["lastActivity"])).total_seconds() / 60
        label = f"{sid[:8]} {s['title'] or s['cwd']!r} idle={idle:.0f}m ctx={s['contextTokens']}"

        skip = None
        if s["entrypoint"] != "sdk-ts":
            skip = f"not a T3 session ({s['entrypoint']})"
        elif not (a.idle_min <= idle < a.idle_max):
            skip = "outside idle window"
        elif s["contextTokens"] < a.min_tokens:
            skip = "context below threshold"
        elif s["lastPromptIsAutoHandoff"]:
            skip = "already handed off"
        elif ledger.get(sid, {}).get("lastActivity") == s["lastActivity"]:
            skip = "already sent for this idle stretch"
        if skip:
            if a.verbose:
                log(f"skip {label}: {skip}")
            continue

        thread = t3_thread_for(sid)
        if not thread:
            log(f"skip {label}: no T3 thread found")
            continue
        payload = {"threadId": thread, "sessionId": sid, "idleMinutes": round(idle),
                   "contextTokens": s["contextTokens"]}
        if a.dry_run:
            log(f"would send {label} -> thread {thread}")
            continue
        try:
            post(url, secret, payload)
        except Exception as e:  # network/relay errors: log and retry next tick
            log(f"send failed {label}: {e}")
            continue
        ledger[sid] = {"lastActivity": s["lastActivity"], "sentAt": now.isoformat(), "threadId": thread}
        log(f"sent {label} -> thread {thread}")

    if not a.dry_run:
        LEDGER.parent.mkdir(parents=True, exist_ok=True)
        LEDGER.write_text(json.dumps(ledger, indent=2))


if __name__ == "__main__":
    main()
