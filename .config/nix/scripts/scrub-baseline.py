#!/usr/bin/env python3
"""Scrub committed baseline plists of scanner/PII bait.

The baseline only exists for equality checks in export-defaults.py, and the
exporter already drops data-blob values on the capture side — so removing
them here loses nothing. Also drops emails, ipv4-ish strings, and long
opaque tokens (apple-bundled in the guest, but the repo is public and the
push scanner is happier without them).

usage: python3 scripts/scrub-baseline.py [baseline/tahoe]
"""

import plistlib
import re
import sys
from pathlib import Path

EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.\w+")
IPV4 = re.compile(r"\b\d{1,3}(\.\d{1,3}){2,3}\b")
TOKEN = re.compile(r"^[A-Za-z0-9+/=_-]{24,}$")


def scrub(v):
    if isinstance(v, bytes):
        return None
    if isinstance(v, str):
        if EMAIL.search(v) or IPV4.search(v) or TOKEN.match(v):
            return None
        return v
    if isinstance(v, dict):
        d = {k: c for k, c in ((k, scrub(x)) for k, x in v.items())
             if c is not None}
        return d
    if isinstance(v, list):
        return [c for c in (scrub(x) for x in v) if c is not None]
    return v


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "baseline/tahoe")
    n_files = n_dropped = 0
    for f in sorted(root.glob("*.plist")):
        try:
            pl = plistlib.loads(f.read_bytes())
        except Exception:
            continue
        if not isinstance(pl, dict):
            continue
        before = len(pl)
        cleaned = {k: c for k, c in ((k, scrub(x)) for k, x in pl.items())
                   if c is not None}
        n_dropped += before - len(cleaned)
        f.write_bytes(plistlib.dumps(cleaned, fmt=plistlib.FMT_XML))
        n_files += 1
    print(f"scrubbed {n_files} plists; dropped {n_dropped} top-level keys")


if __name__ == "__main__":
    main()
