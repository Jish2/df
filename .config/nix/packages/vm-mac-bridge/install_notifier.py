"""Install and sign the Nix-built notifier in the user's Applications folder."""

import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


BUNDLE_ID = "fr.julienxx.oss.terminal-notifier.vm-mac-bridge"
REGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


def bundle_id(app):
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"]


def install(source, target):
    if bundle_id(source) != BUNDLE_ID:
        raise RuntimeError("Unexpected source app identity")
    if target.is_symlink() or (target.exists() and bundle_id(target) != BUNDLE_ID):
        raise RuntimeError(f"Refusing to replace another app at {target}")
    marker = target / "Contents/.nix-source"
    if marker.exists() and marker.read_text().strip() == str(source):
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".vm-mac-bridge-", dir=target.parent) as temporary:
        staging = Path(temporary)
        replacement = staging / target.name
        shutil.copytree(source, replacement)
        # Store files are read-only. Only the new user-owned copy is writable.
        for path in [replacement, *replacement.rglob("*")]:
            path.chmod(path.stat().st_mode | 0o200)
        (replacement / "Contents/.nix-source").write_text(str(source) + "\n")
        # Sign the complete bundle after Nix fixups, in its user-owned copy.
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(replacement)], check=True)
        backup = staging / "previous.app"
        if target.exists():
            target.rename(backup)
        try:
            replacement.rename(target)
            subprocess.run([REGISTER, "-f", str(target)], check=True)
        except BaseException:
            if target.exists():
                target.rename(staging / "failed.app")
            if backup.exists():
                backup.rename(target)
            raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    args = parser.parse_args()
    install(args.source, args.target)
