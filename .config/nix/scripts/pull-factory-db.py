#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""Build scripts/factory-db.json: known macOS factory-default values.

Sole source: github.com/yannbertrand/macos-defaults — community-verified,
per-OS-version docs that mark the default inline
("## Set to `false` (default value)"), parsed for domain/key/type/value from
the embedded `defaults write` command.

NOTE: Apple's device-management MDM profile yamls were considered and
REJECTED — their `default:` field describes payload-omission semantics, not
the OS factory value (counterexamples: show-recents, show-process-indicators
are marked default:false there but a fresh macOS install shows both).

Used by export-defaults.py: a captured key whose value equals the factory
value is skipped. Coverage is partial by nature (~hundreds of documented
keys); everything else stays captured until the pristine-VM baseline exists
(see --baseline in export-defaults.py).

Re-run to refresh:  uv run scripts/pull-factory-db.py
"""

import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "factory-db.json"
CLONE = Path("/tmp/macos-defaults-src")

SECTION = re.compile(r"## Set to `([^`]+)` \(default value\)")
WRITE = re.compile(
    r'defaults write\s+(-g\s+|"(?P<gdomain>[^"]+)"\s+|(?P<domain>\S+)\s+)'
    r'"(?P<key>[^"]+)"\s+-(?P<type>bool|int|float|string)\s+"?(?P<value>[^"\n]*)"?'
)


def main():
    if not CLONE.exists():
        subprocess.run(
            ["git", "clone", "--depth", "1", "--filter=blob:none",
             "--no-checkout", "https://github.com/yannbertrand/macos-defaults",
             str(CLONE)],
            check=True,
        )
        subprocess.run(["git", "-C", str(CLONE), "sparse-checkout", "init",
                        "--no-cone"], check=True)
        (CLONE / ".git/info/sparse-checkout").write_text("docs/**/*.md\n")
        subprocess.run(["git", "-C", str(CLONE), "checkout"], check=True)

    db, marked = {}, 0
    for md in sorted(CLONE.glob("docs/**/*.md")):
        text = md.read_text(errors="ignore")
        for m in SECTION.finditer(text):
            tail = text[m.end():m.end() + 600]
            w = WRITE.search(tail) or WRITE.search(text)
            if not w:
                continue
            marked += 1
            domain = w.group("gdomain") or w.group("domain") or "NSGlobalDomain"
            t, v = w.group("type"), w.group("value")
            val = (v.lower() == "true") if t == "bool" else (
                int(v) if t == "int" else (float(v) if t == "float" else v))
            db.setdefault(domain, {})[w.group("key")] = val

    total = sum(len(v) for v in db.values())
    OUT.write_text(json.dumps(db, indent=2, sort_keys=True) + "\n")
    print(f"wrote {OUT}: {len(db)} domains, {total} keys "
          f"({marked} default markers found)")


if __name__ == "__main__":
    main()
