"""Use the same app identity as terminal-notifier's custom-app build."""

import plistlib
from pathlib import Path
import sys


def prepare(source, target):
    info = plistlib.loads(Path(source).read_bytes())
    info.update(
        CFBundleIdentifier="fr.julienxx.oss.terminal-notifier.vm-mac-bridge",
        CFBundleName="vm-mac-bridge",
        CFBundleExecutable="terminal-notifier",
        CFBundleIconFile="icon",
    )
    Path(target).write_bytes(plistlib.dumps(info))


if __name__ == "__main__":
    prepare(*sys.argv[1:])
