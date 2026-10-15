"""Open the approval helper in Terminal and reconnect its SSH transport."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


def lock_file(home):
    directory = home / "Library/Application Support/vm-mac-bridge"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = (directory / "helper.lock").open("a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock.close()
        return None
    return lock


def running(home):
    lock = lock_file(home)
    if lock is None:
        return True
    lock.close()
    return False


def start(config, home):
    if not running(home):
        subprocess.run(["/usr/bin/open", "-a", "Terminal", config["terminal_command"]], check=True)
    return 0


def source_cache(config, home):
    identity = json.dumps({"repository": config["repository"], "branch": config["branch"]}, sort_keys=True)
    key = hashlib.sha256(identity.encode()).hexdigest()[:16]
    return home / "Library/Application Support/vm-mac-bridge/sources" / key


def refresh_bridge(config, home):
    cache = source_cache(config, home)
    owner = {"repository": config["repository"], "branch": config["branch"]}

    def git(*arguments, cwd=None):
        return subprocess.run(
            [config["git"], *arguments], cwd=cwd, check=True,
            stdin=subprocess.DEVNULL, capture_output=True, text=True,
            timeout=config["update_timeout"],
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        )

    def entrypoint(checkout):
        path = checkout / "bridge.py"
        if not path.is_file() or path.is_symlink():
            raise RuntimeError("Latest bridge checkout has no regular bridge.py entrypoint")
        return path

    if cache.is_symlink():
        raise RuntimeError(f"Refusing to update a linked source cache at {cache}")
    if not cache.exists():
        cache.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.TemporaryDirectory(prefix=".updating-", dir=cache.parent) as temporary:
            staging = Path(temporary)
            git("clone", "--single-branch", "--depth", "1",
                "--branch", config["branch"], "--", config["repository"], str(staging / "checkout"))
            entrypoint(staging / "checkout")
            (staging / "owner.json").write_text(json.dumps(owner) + "\n")
            staging.rename(cache)
    else:
        marker = cache / "owner.json"
        if not marker.is_file() or json.loads(marker.read_text()) != owner:
            raise RuntimeError(f"Refusing to update an unmanaged source cache at {cache}")
        checkout = cache / "checkout"
        if checkout.is_symlink():
            raise RuntimeError(f"Refusing to update a linked checkout at {checkout}")
        if git("status", "--porcelain", "--untracked-files=all", cwd=checkout).stdout.strip():
            raise RuntimeError(f"Bridge checkout has local changes; move or restore them at {checkout}")
        git("fetch", "--no-tags", "--depth", "1", "--", config["repository"],
            "refs/heads/" + config["branch"], cwd=checkout)
        git("checkout", "--detach", "FETCH_HEAD", cwd=checkout)
    checkout = cache / "checkout"
    path = entrypoint(checkout)
    revision = git("rev-parse", "HEAD", cwd=checkout).stdout.strip()
    print(f"Using latest vm-mac-bridge {config['branch']} at {revision[:12]}.", flush=True)
    return path


def helper_arguments(config, bridge):
    args = [config["python"], str(bridge), "mac", config["host"],
            "--remote-script", config["remote_script"], "--notify",
            "--notifier-path", config["notifier"], "--max-timeout", str(config["max_timeout"])]
    if config["notification_timeout"] is not None:
        args += ["--notification-timeout", str(config["notification_timeout"])]
    return args


def run(config, home):
    if not sys.stdin.isatty():
        raise RuntimeError("Run the helper in an interactive terminal, or use vm-mac-bridge start")
    lock = lock_file(home)
    if lock is None:
        print("VM–Mac bridge is already running.")
        return 0
    with lock:
        print("VM–Mac bridge: approve requests here or in notifications. Ctrl-C stops the helper.", flush=True)
        while True:
            try:
                bridge = refresh_bridge(config, home)
                with subprocess.Popen(helper_arguments(config, bridge),
                                      env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}) as child:
                    try:
                        result = child.wait()
                    except KeyboardInterrupt:
                        if child.poll() is None:
                            child.send_signal(signal.SIGINT)
                            try:
                                child.wait(timeout=5)
                            except subprocess.TimeoutExpired:
                                child.kill()
                                child.wait()
                        return 0
                if result in (130, -signal.SIGINT):
                    return 0
                print(f"Bridge disconnected (exit {result}); reconnecting in {config['reconnect_seconds']} seconds.", flush=True)
                time.sleep(config["reconnect_seconds"])
            except KeyboardInterrupt:
                return 0
            except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError,
                    subprocess.TimeoutExpired) as error:
                print(f"Bridge update/start failed: {error}. No cached helper will be started.",
                      file=sys.stderr, flush=True)
                try:
                    time.sleep(config["reconnect_seconds"])
                except KeyboardInterrupt:
                    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=("start", "run", "status"), default="start")
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    home = Path.home()
    try:
        if args.command == "status":
            active = running(home)
            print("running" if active else "stopped")
            sys.exit(0 if active else 1)
        sys.exit(start(config, home) if args.command == "start" else run(config, home))
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
