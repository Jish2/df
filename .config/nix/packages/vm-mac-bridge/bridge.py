#!/usr/bin/env python3
"""Send Bash requests from a VM to a Mac that connects over SSH."""

import argparse
import fcntl
import io
import json
import math
import os
from pathlib import Path
import shlex
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid


def write_json(path, value):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as f:
        temporary = Path(f.name)
        json.dump(value, f)
        f.write("\n")
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def read_json(path):
    return json.loads(path.read_text())


def directories(root):
    for name in ("pending", "running", "results"):
        (root / name).mkdir(parents=True, exist_ok=True, mode=0o700)


class RequestExpired(Exception):
    pass


def expired_result(request_id):
    return {"id": request_id, "status": "expired", "exit_code": 124,
            "stdout": "", "stderr": "Request expired before execution.\n"}


def is_expired(request):
    return request.get("expires_at") is not None and time.time() >= request["expires_at"]


def require_live(deadline):
    if time.monotonic() >= deadline:
        raise RequestExpired


def terminal_review(review_input, deadline):
    require_live(deadline)
    # In-memory streams are used by tests; real approval always uses /dev/tty.
    if not isinstance(review_input, io.StringIO):
        readable, _, _ = select.select([review_input], [], [],
                                       max(0, deadline - time.monotonic()))
        if not readable:
            raise RequestExpired
    answer = review_input.readline().strip() == "yes"
    require_live(deadline)
    return answer


def unknown_result(root, request_id):
    write_json(root / "results" / f"{request_id}.json", {
        "id": request_id,
        "status": "unknown",
        "exit_code": 125,
        "stdout": "",
        "stderr": "Mac disconnected before returning a result. The command may "
                  "have run; it will not be retried automatically.\n",
    })
    (root / "running" / f"{request_id}.json").unlink(missing_ok=True)


def serve(root, protocol_version=1):
    directories(root)
    with (root / "worker.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("A Mac helper is already connected to this queue.")
        for stale in (root / "running").glob("*.json"):
            unknown_result(root, stale.stem)
        active_id = None
        capabilities = root / "worker-protocol.json"
        write_json(capabilities, {"version": protocol_version})
        try:
            while True:
                pending = sorted((root / "pending").glob("*.json"),
                                 key=lambda p: (p.stat().st_mtime_ns, p.name))
                if not pending:
                    readable, _, _ = select.select([sys.stdin], [], [], 0.1)
                    if readable:
                        if not sys.stdin.readline():
                            return
                        raise RuntimeError("Received a result with no active request.")
                    continue
                path = pending[0]
                active_id = path.stem
                path.rename(root / "running" / path.name)
                path = root / "running" / path.name
                request = read_json(path)
                if is_expired(request):
                    write_json(root / "results" / path.name, expired_result(active_id))
                    path.unlink()
                    active_id = None
                    continue
                if request.get("expires_at") is not None and protocol_version < 2:
                    write_json(root / "results" / path.name, {
                        "id": active_id, "status": "failed", "exit_code": 125,
                        "stdout": "", "stderr": "Update and restart the Mac helper "
                        "to support requests with an expiry.\n",
                    })
                    path.unlink()
                    active_id = None
                    continue
                request["phase"] = "awaiting_approval"
                if request.get("expires_at") is not None:
                    request["approval_seconds"] = max(0, request["expires_at"] - time.time())
                write_json(path, request)
                print(json.dumps(request), flush=True)
                line = sys.stdin.readline()
                if not line:
                    return
                result = json.loads(line)
                if result.get("id") != active_id:
                    raise RuntimeError("The Mac returned a mismatched request ID.")
                authorized = False
                if protocol_version >= 2 and result.get("type") == "approval":
                    authorized = not is_expired(request)
                    if authorized:
                        request.update(phase="executing", started_at=time.time())
                        write_json(path, request)
                    print(json.dumps({"id": active_id, "type": "execute",
                                      "allowed": authorized}), flush=True)
                    line = sys.stdin.readline()
                    if not line:
                        return
                    result = json.loads(line)
                    if result.get("id") != active_id:
                        raise RuntimeError("The Mac returned a mismatched request ID.")
                if (protocol_version >= 2 and not authorized
                        and result.get("status") in ("completed", "timed_out")):
                    raise RuntimeError("The Mac returned execution without authorization.")
                if (result.get("status") not in ("completed", "timed_out", "failed", "rejected", "expired")
                        or type(result.get("exit_code")) is not int
                        or not isinstance(result.get("stdout"), str)
                        or not isinstance(result.get("stderr"), str)):
                    raise RuntimeError("The Mac returned an invalid result.")
                write_json(root / "results" / path.name, result)
                path.unlink()
                active_id = None
        finally:
            try:
                if active_id:
                    unknown_result(root, active_id)
            finally:
                capabilities.unlink(missing_ok=True)


def prepare_request(request, default_cwd, max_timeout):
    command = request["command"]
    if not isinstance(command, str) or not command:
        raise ValueError("command must be a nonempty string")
    requested_timeout = float(request["timeout"])
    if not math.isfinite(requested_timeout) or requested_timeout <= 0:
        raise ValueError("timeout must be finite and positive")
    timeout = min(requested_timeout, max_timeout)
    cwd = os.path.abspath(os.path.expanduser(request.get("cwd") or default_cwd))
    prepared = {"id": request["id"], "command": command, "cwd": cwd, "timeout": timeout}
    for field in ("expires_at", "approval_seconds"):
        if request.get(field) is not None:
            value = float(request[field])
            if not math.isfinite(value) or value < 0:
                raise ValueError(f"{field} must be finite and nonnegative")
            prepared[field] = value
    return prepared


def find_notifier(notifier_path=None):
    executable = (str(Path(notifier_path).expanduser().resolve()) if notifier_path
                  else shutil.which("terminal-notifier"))
    if not executable:
        raise RuntimeError("Install terminal-notifier on the Mac with "
                           "'brew install terminal-notifier' before using --notify.")
    if not os.path.isfile(executable) or not os.access(executable, os.X_OK):
        raise RuntimeError(f"Notifier executable not found or not executable: {executable}")
    help_result = subprocess.run([executable, "-help"], capture_output=True,
                                 text=True, timeout=10)
    help_text = help_result.stdout + help_result.stderr
    actions = any(word == "-action" for word in help_text.split())
    return executable, actions


def notification_review(request, notifier, review_input, review_output,
                        wait_timeout, terminal_bundle_id, group, deadline=None):
    if deadline is None:
        deadline = time.monotonic() + wait_timeout
    require_live(deadline)
    executable, supports_actions = notifier
    command = json.dumps(request["command"], ensure_ascii=True)
    cwd = json.dumps(request["cwd"], ensure_ascii=True)
    # Longer requests need the full terminal preview rather than a short banner.
    direct_approval = len(command) <= 80 and len(cwd) <= 80 and "\n" not in request["command"]
    message = f"Command: {command}\nDirectory: {cwd}"
    if not direct_approval:
        message = "A command needs your approval. Review its full text in the Mac helper terminal."
    arguments = [executable, "-title", "VM command request", "-message", message,
                 "-sound", "default", "-group", group,
                 "-activate", terminal_bundle_id]
    if supports_actions:
        arguments += ["-action", "Approve,Reject" if direct_approval else "Review,Reject",
                      "-timeout", str(wait_timeout)]
    process = None
    try:
        process = subprocess.Popen(arguments, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        if not supports_actions:
            stdout, stderr = process.communicate(timeout=min(10, max(0, deadline - time.monotonic())))
            if process.returncode:
                print(f"Notification failed: {stderr.strip()}. Use terminal approval.",
                      file=review_output, flush=True)
            else:
                print("This terminal-notifier version has no action buttons. "
                      "Click the notification to bring the terminal forward, "
                      "then approve here.", file=review_output, flush=True)
            return None
        while time.monotonic() < deadline:
            readable, _, _ = select.select([review_input], [], [], 0.1)
            if readable:
                return terminal_review(review_input, deadline)
            if process.poll() is not None:
                stdout, stderr = process.communicate()
                answer = stdout.strip()
                require_live(deadline)
                if process.returncode == 0 and direct_approval and answer == "Approve":
                    return True
                if answer == "@TIMEOUT":
                    raise RequestExpired
                if answer in ("Reject", "@CLOSED"):
                    return False
                if answer in ("Review", "@ACTIONCLICKED") and process.returncode == 0:
                    print("Review the full command above and approve in this terminal.",
                          file=review_output, flush=True)
                else:
                    print("Notification did not return an approval. Use terminal approval. "
                          f"{stderr.strip()}", file=review_output, flush=True)
                return None
        raise RequestExpired
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"Notification unavailable: {error}. Use terminal approval.",
              file=review_output, flush=True)
        return None
    finally:
        if process:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            process.stdout.close()
            process.stderr.close()


def remove_notification(notifier, group):
    try:
        subprocess.run([notifier[0], "-remove", group], capture_output=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        pass


def approve_and_execute(request, default_cwd, max_timeout, review_input, review_output,
                        notifier=None, notification_timeout=None,
                        terminal_bundle_id="com.apple.Terminal", authorize=None):
    try:
        reviewed = prepare_request(request, default_cwd, max_timeout)
    except (OSError, ValueError, KeyError, TypeError) as error:
        return {"id": request.get("id"), "status": "failed", "exit_code": 125,
                "stdout": "", "stderr": f"{error}\n"}
    remaining = reviewed.get("approval_seconds")
    if remaining is None:
        remaining = (reviewed["expires_at"] - time.time()
                     if "expires_at" in reviewed else 600)
    if notification_timeout is not None:
        remaining = min(remaining, notification_timeout)
    deadline = time.monotonic() + remaining
    if remaining <= 0:
        return expired_result(reviewed["id"])
    # JSON quoting makes control characters visible in the approval display.
    print("\nVM requests a Bash command on this Mac:", file=review_output)
    for label, value in (("Request", reviewed["id"]), ("Directory", reviewed["cwd"]),
                         ("Command (JSON quoted)", reviewed["command"])):
        print(f"{label}: {json.dumps(value, ensure_ascii=True)}", file=review_output)
    print(f"Execution limit: {reviewed['timeout']:g} seconds", file=review_output)
    print(f"Approval window remaining: {remaining:g} seconds", file=review_output)
    print("Type 'yes' to run this command; anything else rejects: ",
          end="", file=review_output, flush=True)
    approved = None
    group = "vm-mac-bridge-" + str(uuid.uuid4())
    try:
        try:
            if notifier:
                approved = notification_review(reviewed, notifier, review_input, review_output,
                                               remaining, terminal_bundle_id, group, deadline)
            if approved is None:
                approved = terminal_review(review_input, deadline)
        finally:
            if notifier:
                remove_notification(notifier, group)
        if approved:
            require_live(deadline)
            if authorize is not None and not authorize(reviewed["id"]):
                raise RequestExpired
            require_live(deadline)
    except RequestExpired:
        return expired_result(reviewed["id"])
    if not approved:
        return {"id": reviewed["id"], "status": "rejected", "exit_code": 126,
                "stdout": "", "stderr": "Command rejected on the Mac.\n"}
    return execute(reviewed, reviewed["cwd"], reviewed["timeout"], deadline=deadline)


def execute(request, default_cwd, max_timeout, deadline=None):
    result = {"id": request["id"], "status": "completed", "exit_code": 0,
              "stdout": "", "stderr": ""}
    process = None
    try:
        prepared = prepare_request(request, default_cwd, max_timeout)
        command, timeout, cwd = prepared["command"], prepared["timeout"], prepared["cwd"]
        if deadline is not None:
            require_live(deadline)
        elif is_expired(prepared):
            raise RequestExpired
        process = subprocess.Popen(
            ["/bin/bash", "-c", command], cwd=cwd,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, errors="replace",
            start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
            result.update(status="timed_out", exit_code=124)
            stderr += f"\nCommand exceeded {timeout:g} seconds.\n"
        else:
            result["exit_code"] = process.returncode
        result.update(stdout=stdout, stderr=stderr)
    except RequestExpired:
        return expired_result(request["id"])
    except (OSError, ValueError, KeyError, TypeError) as error:
        result.update(status="failed", exit_code=125, stderr=f"{error}\n")
    finally:
        if process and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
    return result


def run_mac(args):
    if args.host.startswith("-"):
        raise ValueError("Use an SSH hostname or configured host alias.")
    remote = [args.remote_python, args.remote_script]
    if args.remote_state_dir:
        remote += ["--state-dir", args.remote_state_dir]
    remote += ["serve", "--protocol-version", "2"]
    notifier = find_notifier(args.notifier_path) if args.notify else None
    # Read approval from the Mac's terminal, separate from SSH's request stream.
    try:
        review_input = open("/dev/tty", "r", encoding="utf-8")
        try:
            review_output = open("/dev/tty", "w", encoding="utf-8")
        except OSError:
            review_input.close()
            raise
    except OSError as error:
        raise RuntimeError("Start the Mac helper in an interactive terminal; "
                           "local approval is required for every command.") from error
    with review_input, review_output, subprocess.Popen(["ssh", "-T", args.host, shlex.join(remote)],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          text=True, encoding="utf-8") as connection:
        try:
            print(f"Connecting to {args.host}. Every Bash command requires "
                  "local Mac approval. "
                  f"Default directory: {json.dumps(args.cwd, ensure_ascii=True)}",
                  file=review_output, flush=True)
            if notifier:
                print(f"Notifier: {notifier[0]} (action buttons: "
                      f"{'yes' if notifier[1] else 'no'})", file=review_output, flush=True)
            def authorize(request_id):
                connection.stdin.write(json.dumps({"id": request_id, "type": "approval"}) + "\n")
                connection.stdin.flush()
                reply = json.loads(connection.stdout.readline())
                if (reply.get("id") != request_id or reply.get("type") != "execute"
                        or type(reply.get("allowed")) is not bool):
                    raise RuntimeError("VM returned an invalid execution authorization.")
                return reply["allowed"]

            for line in connection.stdout:
                request = json.loads(line)
                result = approve_and_execute(request, args.cwd, args.max_timeout,
                                             review_input, review_output, notifier,
                                             args.notification_timeout, args.terminal_bundle_id,
                                             authorize=authorize)
                connection.stdin.write(json.dumps(result) + "\n")
                connection.stdin.flush()
                print(f"[{json.dumps(request['id'], ensure_ascii=True)}] "
                      f"{result['status']}, exit {result['exit_code']}",
                      file=review_output, flush=True)
            return connection.wait()
        finally:
            if connection.poll() is None:
                connection.terminate()


def output_result(result, as_json=False):
    if as_json:
        print(json.dumps(result))
    else:
        sys.stdout.write(result["stdout"])
        sys.stderr.write(result["stderr"])
    code = result["exit_code"]
    return code if code >= 0 else 128 - code


def request_status(root, request_id):
    # A worker may move a file while a poll is reading it. Retry that transition.
    for _ in range(3):
        result_path = root / "results" / f"{request_id}.json"
        try:
            return read_json(result_path)
        except FileNotFoundError:
            pass
        for state in ("running", "pending"):
            try:
                request = read_json(root / state / f"{request_id}.json")
            except FileNotFoundError:
                continue
            if state == "pending" and is_expired(request):
                return expired_result(request_id)
            snapshot = {"id": request_id,
                        "status": request.get("phase", state)}
            for field in ("created_at", "expires_at", "started_at"):
                if field in request:
                    snapshot[field] = request[field]
            return snapshot
    raise ValueError("Request ID not found.")


def status(root, request_id, as_json=False, wait=False, wait_timeout=150, poll_interval=1):
    deadline = time.monotonic() + wait_timeout
    while True:
        snapshot = request_status(root, request_id)
        if "exit_code" in snapshot:
            return output_result(snapshot, as_json)
        if not wait:
            print(json.dumps(snapshot))
            return 0
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            if as_json:
                print(json.dumps({**snapshot, "wait_timed_out": True}))
            print(f"Stopped waiting for {request_id}; this does not cancel the request.\n"
                  f"Read its status with: {shlex.quote(sys.executable)} "
                  f"{shlex.quote(str(Path(__file__).resolve()))} --state-dir "
                  f"{shlex.quote(str(root))} status {request_id} --json", file=sys.stderr)
            return 124
        time.sleep(min(poll_interval, remaining))


def send(root, args):
    directories(root)
    # A helper connected before this upgrade still runs the previous VM code.
    # Do not hand it requests whose expiry it would silently ignore.
    with (root / "worker.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            try:
                version = read_json(root / "worker-protocol.json").get("version", 1)
            except FileNotFoundError:
                version = 1
            if version < 2:
                raise RuntimeError("Update and restart the connected Mac helper "
                                   "before submitting expiring requests.")
    request_id = str(uuid.uuid4())
    created_at = time.time()
    request = {"id": request_id, "command": args.command, "cwd": args.cwd,
               "timeout": args.timeout, "created_at": created_at,
               "expires_at": created_at + args.expires_in}
    write_json(root / "pending" / f"{request_id}.json", request)
    if not args.wait:
        print(json.dumps({"id": request_id, "status": "pending",
                          "created_at": created_at, "expires_at": request["expires_at"]})
              if args.json else request_id)
        return 0
    print(f"Request {request_id}", file=sys.stderr)
    wait_timeout = (args.wait_timeout if args.wait_timeout is not None
                    else args.expires_in + args.timeout + 30)
    return status(root, request_id, args.json, True, wait_timeout, args.poll_interval)


def positive_number(value):
    number = float(value)
    if not 0 < number < float("inf"):
        raise argparse.ArgumentTypeError("must be a finite positive number")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path,
                        default=Path.home() / ".local/state/vm-mac-bridge")
    commands = parser.add_subparsers(dest="action", required=True)
    sender = commands.add_parser("send", help="Queue a Bash command on the VM")
    sender.add_argument("command")
    sender.add_argument("--cwd", help="Working directory on the Mac (supports ~)")
    sender.add_argument("--timeout", type=positive_number, default=120,
                        help="Execution timeout after approval (default: 120 seconds)")
    sender.add_argument("--expires-in", type=positive_number, default=600,
                        help="Latest start time, in seconds from submission (default: 600)")
    mode = sender.add_mutually_exclusive_group()
    mode.add_argument("--async", "--no-wait", dest="wait", action="store_false",
                      help="Return a request ID immediately (default)")
    mode.add_argument("--wait", dest="wait", action="store_true",
                      help="Poll until a final result instead of returning immediately")
    sender.set_defaults(wait=False)
    sender.add_argument("--wait-timeout", type=positive_number,
                        help="Limit caller waiting; default: expiry + execution timeout + 30")
    sender.add_argument("--poll-interval", type=positive_number, default=1)
    sender.add_argument("--json", action="store_true")
    reader = commands.add_parser("status", help="Read or wait for a request's status on the VM")
    reader.add_argument("id")
    reader.add_argument("--json", action="store_true")
    reader.add_argument("--wait", action="store_true")
    reader.add_argument("--wait-timeout", type=positive_number, default=150)
    reader.add_argument("--poll-interval", type=positive_number, default=1)
    server = commands.add_parser("serve", help="SSH transport endpoint on the VM")
    server.add_argument("--protocol-version", type=int, choices=(1, 2), default=1)
    mac = commands.add_parser("mac", help="Run on the Mac to consume VM requests")
    mac.add_argument("host", help="The same SSH host/alias you use for this VM")
    mac.add_argument("--remote-script", required=True,
                     help="Absolute path to bridge.py on the VM")
    mac.add_argument("--remote-python", default="python3")
    mac.add_argument("--remote-state-dir")
    mac.add_argument("--cwd", default=str(Path.home()))
    mac.add_argument("--max-timeout", type=positive_number, default=120)
    mac.add_argument("--notify", action="store_true",
                     help="Notify using terminal-notifier; use action buttons when supported")
    mac.add_argument("--notifier-path",
                     help="Notifier executable in a dedicated Mac app bundle (with --notify)")
    mac.add_argument("--notification-timeout", type=positive_number,
                     help="Optional shorter approval window; default: request expiry")
    mac.add_argument("--terminal-bundle-id", default="com.apple.Terminal",
                     help="Mac terminal app to bring forward when a notification is clicked")
    args = parser.parse_args()
    root = args.state_dir.expanduser().resolve()
    if args.action == "mac":
        return run_mac(args)
    if args.action == "serve":
        serve(root, args.protocol_version)
        return 0
    if args.action == "send":
        return send(root, args)
    request_id = str(uuid.UUID(args.id))
    return status(root, request_id, args.json, args.wait, args.wait_timeout, args.poll_interval)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except (OSError, ValueError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(125)
