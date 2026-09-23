#!/usr/bin/env python3
"""Report this mac's non-default `defaults` keys for hand-picking.

Usage:
    python3 export-defaults.py [output.nix]

Strategy: dump every Apple domain (NSGlobalDomain, .GlobalPreferences,
com.apple.*), strip volatile state (timestamps, caches, window rects,
analytics, per-machine ByHost domains...) and keys already first-class in
the flake, then emit the rest verbatim as system.defaults.CustomUserPreferences.

IMPORTANT: the output is a snapshot — every later `darwin-rebuild switch`
RE-ASSERTS these values. If you change a setting in macOS and want to keep
it, either re-run this script or delete that key from the generated file.

Re-run on personal/mini for their own reports
and wire it into that host's module instead of the shared one if the machines
should diverge.
"""

import os
import plistlib
import re
import socket
import subprocess
import sys
from datetime import datetime, timezone

ARGS = sys.argv[1:]

# state, not preferences — drop these keys anywhere they appear
# substring match against the lowercased key (camelCase defeats \b)
VOLATILE = re.compile(
    r"last|analytic|heartbeat|migrat|token|cache|recent|histor|uuid|guid|"
    r"position|rect|frame|geometr|bounds|origin|count|date|time|"
    r"seen|acknowledg|tooltip|state|selection|saved|session|sync|version",
    re.I,
)
# per-machine ByHost domains end in a hardware UUID
BYHOST = re.compile(r"[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}")
# whole domains that are state/service-owned, not user preferences
DENY_DOMAIN = re.compile(
    r"windowserver|authwarning|setupassistant|mediaanalysis|photoanalysis|"
    r"knowledge|suggestd|siri|coreduet|duetexpertd|inputanalytics|callhistory|"
    r"rapportd|sharingd|bird|cloudd|itunesstored|passd|apsd|identityservices|"
    r"\bids\b|madrid|classroom|photosuiprivate|amp\.|loginwindow|corespotlight|"
    r"proactive|intents|trial|exptital|differentialprivacy|feedback|"
    r"EmojiCache|wifi.removed-networks|photolibraryd|cloudpaird|remindd|"
    r"TelephonyUtilities|AMPLibraryAgent|configurator\.ui|donotdisturb|"
    r"MobileSMS|FamilyCircle|facetimemessagestored",
    re.I,
)
# PII / machine-junk guards: any key containing these in name or value is
# dropped (apple ids in imessage state, cache-path fingerprints, ...)
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.\w+")
CACHE_PATH = "/Library/Caches"
# fully managed elsewhere in the flake
SKIP_DOMAIN = {"com.apple.symbolichotkeys"}
# verified macOS factory defaults — re-capturing these adds noise, filter
# forever. add here when a captured key is confirmed default-valued.
FACTORY = {
    "NSGlobalDomain": {"com.apple.swipescrolldirection"},  # natural scroll on
    "com.apple.menuextra.clock": {"ShowAMPM", "ShowDate", "ShowDayOfWeek"},
    "com.apple.AppleMultitouchTrackpad": {"FirstClickThreshold", "SecondClickThreshold"},
    "com.apple.dock": {"magnification"},
}
# individual state keys that slip past VOLATILE (add as discovered)
SKIP_KEYS = {"com.apple.dock": {"trash-full"}}
# already first-class in modules/darwin/common.nix / hosts/work
DUP = {
    "NSGlobalDomain": {
        "AppleInterfaceStyle", "ApplePressAndHoldEnabled", "KeyRepeat",
        "InitialKeyRepeat", "com.apple.mouse.scaling",
    },
    "com.apple.dock": {
        "autohide", "tilesize", "show-recents", "persistent-apps",
    },
    "com.apple.AppleMultitouchTrackpad": {"Clicking", "TrackpadThreeFingerDrag"},
    "com.apple.controlcenter": {
        f"NSStatusItem {'Visible' if i < 3 else 'VisibleCC'} {n}"
        for i, n in enumerate(
            ["Battery", "BentoBox", "Shortcuts", "Clock", "FocusModes",
             "NowPlaying", "Sound", "WiFi"]
        )
    },
}


def bad_value(v):
    if isinstance(v, str):
        return bool(EMAIL.search(v)) or CACHE_PATH in v
    if isinstance(v, dict):
        return any(bad_value(k) or bad_value(x) for k, x in v.items())
    if isinstance(v, list):
        return any(bad_value(x) for x in v)
    return False


def volatile_key(k):
    # CloudKit persists boot/account state under CK* keys
    return (
        bool(VOLATILE.search(k))
        or bool(re.match(r"^CK[A-Z]", k))
        or bool(EMAIL.search(k))
    )


def clean(v):
    """Return nix-safe value, or None to drop."""
    if isinstance(v, (bytes, datetime)):
        return None
    if isinstance(v, dict):
        d = {k: c for k, c in ((k, clean(x)) for k, x in v.items())
             if c is not None and not volatile_key(k) and not bad_value(c)}
        return d or None
    if isinstance(v, list):
        l = [c for c in (clean(x) for x in v)
             if c is not None and not bad_value(c)]
        return l or None
    return v


def nix(v, ind=0):
    pad = "  " * ind
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        s = repr(v)
        return s if ("." in s or "e" in s) else s + ".0"
    if isinstance(v, str):
        e = (v.replace("\\", "\\\\").replace('"', '\\"')
               .replace("${", "\\${").replace("\n", "\\n").replace("\t", "\\t"))
        return f'"{e}"'
    if isinstance(v, list):
        if all(not isinstance(x, (dict, list)) for x in v):
            return "[ " + " ".join(nix(x) for x in v) + " ]"
        body = "\n".join(pad + "  " + nix(x, ind + 1) for x in v)
        return "[\n" + body + "\n" + pad + "]"
    if isinstance(v, dict):
        body = "\n".join(f'{pad}  "{k}" = {nix(val, ind + 1)};'
                         for k, val in sorted(v.items(), key=lambda i: i[0].casefold()))
        return "{\n" + body + "\n" + pad + "}"
    raise TypeError(type(v))


def load_factory_db():
    """known factory values from scripts/factory-db.json
    (uv run scripts/pull-factory-db.py to refresh)"""
    import json
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "factory-db.json")
    try:
        with open(p) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def eq(a, b):
    """plist/JSON value equality with bool/int/float/str coercion."""
    if isinstance(a, (bool, int)) and isinstance(b, (bool, int)):
        return int(a) == int(b)  # True == 1 in plist land
    try:
        return float(a) == float(b)
    except (TypeError, ValueError):
        return str(a) == str(b)


def load_baseline(path):
    """Load a directory of <domain>.plist dumps from a pristine macOS install
    (e.g. a fresh tart VM). Keys whose cleaned value matches the baseline are
    dropped — they are aligned with the factory default by construction."""
    b = {}
    if not path:
        return b
    from pathlib import Path
    if not any(Path(path).glob("*.plist")):
        print(f"warning: no baseline plists in {path} — "
              f"run scripts/fetch-baseline.sh first", file=sys.stderr)
        return b
    for f in Path(path).glob("*.plist"):
        dom = f.stem
        if dom == ".GlobalPreferences":
            dom = "NSGlobalDomain"
        try:
            pl = plistlib.loads(f.read_bytes())
        except Exception:
            continue
        if isinstance(pl, dict):
            b[dom] = pl
    return b


def main():
    baseline_dir = None
    if "--baseline" in ARGS:
        i = ARGS.index("--baseline")
        baseline_dir = ARGS[i + 1]
        del ARGS[i : i + 2]
    out_path = ARGS[0] if ARGS else "/tmp/imported-defaults.current.nix"
    baseline = load_baseline(baseline_dir)
    factory_db = load_factory_db()
    out = subprocess.run(["defaults", "domains"], capture_output=True, text=True)
    domains = [d.strip() for d in out.stdout.split(",")]
    apple = [d for d in domains
             if d in ("NSGlobalDomain", ".GlobalPreferences")
             or d.startswith("com.apple.")]

    captured, n_keys = {}, 0
    for d in sorted(apple, key=str.casefold):
        if BYHOST.search(d) or DENY_DOMAIN.search(d) or d in SKIP_DOMAIN:
            continue
        r = subprocess.run(["defaults", "export", d, "-"], capture_output=True)
        if r.returncode != 0:
            continue
        try:
            pl = plistlib.loads(r.stdout)
        except Exception:
            continue
        if not isinstance(pl, dict):
            continue
        skip = DUP.get(d, set()) | SKIP_KEYS.get(d, set()) | FACTORY.get(d, set())
        c = {}
        base = baseline.get(d, {})
        for k, x in pl.items():
            v = clean(x)
            if v is None or k in skip or volatile_key(k) or bad_value(v):
                continue
            if k in base and base[k] == v:
                continue  # matches pristine-install value = factory default
            fdb = factory_db.get(d, {})
            if k in fdb and eq(v, fdb[k]):
                continue  # documented factory value (scripts/factory-db.json)
            c[k] = v
        if c:
            captured[d] = c
            n_keys += len(c)

    when = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    host = socket.gethostname()
    with open(out_path, "w") as f:
        f.write("# discovery report — scripts/export-defaults.py. NOT imported by the flake;\n")
        f.write(f"# captured {when} on {host}. diff vs a fresh mac to see drift;\n")
        f.write("# hand-pick keys into modules/darwin/common.nix, then discard this file.\n")
        f.write("{ ... }:\n{\n  system.defaults.CustomUserPreferences = {\n")
        for d, kv in captured.items():
            f.write(f'    "{d}" = {nix(kv, 2)};\n')
        f.write("  };\n}\n")
    print(f"wrote {out_path}: {len(captured)} domains, {n_keys} keys", file=sys.stderr)


if __name__ == "__main__":
    main()
