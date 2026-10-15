"""Open the approval helper in Terminal and reconnect its SSH transport."""

import argparse
import fcntl
import json
from pathlib import Path
import signal
import subprocess
import sys
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


def helper_arguments(config):
    args = [config["python"], config["bridge"], "mac", config["host"],
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
                with subprocess.Popen(helper_arguments(config)) as child:
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
