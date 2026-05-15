#!/usr/bin/env python3
"""Fork a new tmux window with a command.

Requires an active tmux session (`$TMUX` must be set). Provides status
tracking, log capture for non-interactive commands, and wait-for-completion
polling.
"""

import json
import os
import re
import shlex
import subprocess
import sys
import time
import uuid
from pathlib import Path

STATUS_DIR = Path("/tmp/fork-tmux-status")


def require_tmux() -> None:
    """Exit loudly if not running inside a tmux session."""
    if not os.environ.get("TMUX"):
        sys.stderr.write(
            "fork-tmux: $TMUX is not set — this skill only works inside a tmux session.\n"
            "Start tmux first (e.g. `tmux new -s work`) and re-run.\n"
        )
        sys.exit(2)


def get_status_file(session_id: str) -> Path:
    return STATUS_DIR / f"{session_id}.json"


def get_log_file(session_id: str) -> Path:
    return STATUS_DIR / f"{session_id}.log"


def _get_script_file(session_id: str) -> Path:
    return STATUS_DIR / f"{session_id}.sh"


_CLAUDE_PREFIXES = ("claude ", "claude'", 'claude"')


def is_interactive_command(command: str) -> bool:
    """Detect interactive TUI commands that shouldn't have stdout piped."""
    cmd_lower = command.strip().lower()
    interactive_prefixes = (
        *_CLAUDE_PREFIXES,
        "gemini ", "gemini'", 'gemini"',
        "vim ", "nvim ", "nano ", "htop", "top",
    )
    return any(cmd_lower.startswith(p) for p in interactive_prefixes)


def _is_claude_command(command: str) -> bool:
    cmd_lower = command.strip().lower()
    return any(cmd_lower.startswith(p) for p in _CLAUDE_PREFIXES)


def _inject_claude_session_id(
    command: str, cwd: str,
) -> tuple[str, str | None, str | None]:
    """Inject or extract --session-id for Claude commands.

    Returns (command, claude_session_id, claude_session_file).
    """
    if not _is_claude_command(command):
        return (command, None, None)

    match = re.search(
        r"--session-id\s+([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})",
        command,
    )
    if match:
        session_id = match.group(1)
    else:
        session_id = str(uuid.uuid4())
        parts = command.split(" ", 1)
        rest = parts[1] if len(parts) > 1 else ""
        command = f"{parts[0]} --session-id {session_id} {rest}".rstrip()

    project_dir = "-" + cwd.strip("/").replace("/", "-")
    home = os.path.expanduser("~")
    session_file = str(
        Path(home) / ".claude" / "projects" / project_dir / f"{session_id}.jsonl"
    )

    return (command, session_id, session_file)


def _build_wrapped_command(
    command: str, cwd: str, session_id: str, track_status: bool, is_interactive: bool,
    window_name: str = None,
    claude_session_id: str = None, claude_session_file: str = None,
) -> str:
    """Write a wrapper shell script and return its path.

    Using a file avoids shell-metacharacter issues from embedding commands
    into `bash -c` strings. Also writes the initial status file if tracking.
    """
    STATUS_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    script_file = _get_script_file(session_id)

    if track_status:
        status_file = get_status_file(session_id)
        log_file = get_log_file(session_id)

        with open(status_file, "w") as f:
            json.dump(
                {
                    "status": "running",
                    "command": command,
                    "cwd": cwd,
                    "started_at": time.time(),
                    "log_file": str(log_file) if not is_interactive else None,
                    "interactive": is_interactive,
                    "window_name": window_name,
                    "claude_session_id": claude_session_id,
                    "claude_session_file": claude_session_file,
                },
                f,
            )

        claude_fields = ""
        if claude_session_id:
            claude_fields = (
                f', "claude_session_id": "{claude_session_id}"'
                f', "claude_session_file": "{claude_session_file}"'
            )

        unset_claude = "unset CLAUDECODE\n" if claude_session_id else ""

        if is_interactive:
            script_content = (
                f"#!/bin/bash\n"
                f"cd {shlex.quote(cwd)}\n"
                f"{unset_claude}"
                f"{command}\n"
                f"EXIT_CODE=$?\n"
                f"printf '{{\"status\": \"completed\", \"exit_code\": %d, "
                f"\"completed_at\": %s{claude_fields}}}' \"$EXIT_CODE\" \"$(date +%s.%N)\" "
                f"> '{status_file}'\n"
            )
        else:
            script_content = (
                f"#!/bin/bash\n"
                f"cd {shlex.quote(cwd)}\n"
                f"{unset_claude}"
                f"{{ {command}; }} 2>&1 | tee '{log_file}'\n"
                f"EXIT_CODE=${{PIPESTATUS[0]}}\n"
                f"printf '{{\"status\": \"completed\", \"exit_code\": %d, "
                f"\"completed_at\": %s{claude_fields}}}' \"$EXIT_CODE\" \"$(date +%s.%N)\" "
                f"> '{status_file}'\n"
            )
    else:
        script_content = (
            f"#!/bin/bash\n"
            f"cd {shlex.quote(cwd)}\n"
            f"{command}\n"
        )

    with open(script_file, "w") as f:
        f.write(script_content)
    os.chmod(script_file, 0o755)

    return str(script_file)


def fork_tmux(command: str, track_status: bool = True, cwd: str = None,
              name: str = None) -> dict:
    """Open a new tmux window and run the specified command.

    Args:
        command: The command to run in the new window.
        track_status: If True, track command completion via a status file.
        cwd: Working directory for the command. If None, uses current directory.
        name: Custom tmux window name. If None, derived from the command.

    Returns:
        A dict with session info including session_id for status tracking.
    """
    require_tmux()

    if cwd is None:
        cwd = os.getcwd()
    session_id = str(uuid.uuid4())[:8]

    command, claude_session_id, claude_session_file = _inject_claude_session_id(
        command, cwd,
    )

    is_interactive = is_interactive_command(command)
    window_name = name if name else (command.split()[0] if command.strip() else "fork")

    try:
        script_path = _build_wrapped_command(
            command, cwd, session_id, track_status, is_interactive,
            window_name=window_name,
            claude_session_id=claude_session_id,
            claude_session_file=claude_session_file,
        )

        subprocess.Popen(
            ["tmux", "new-window", "-n", window_name, "bash", script_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        status_file = get_status_file(session_id) if track_status else None
        log_file = get_log_file(session_id) if track_status and not is_interactive else None

        result = {
            "success": True,
            "session_id": session_id,
            "window_name": window_name,
            "command": command,
            "status_file": str(status_file) if status_file else None,
            "log_file": str(log_file) if log_file else None,
            "claude_session_id": claude_session_id,
            "claude_session_file": claude_session_file,
        }
        if is_interactive:
            result["interactive"] = True
        return result
    except Exception as e:
        return {"success": False, "error": str(e)}


def _tmux_window_exists(window_name: str) -> bool:
    """Check if a tmux window with the given name still exists."""
    try:
        result = subprocess.run(
            ["tmux", "list-windows", "-F", "#{window_name}"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0:
            return False
        return window_name in result.stdout.strip().split("\n")
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def check_status(session_id: str) -> dict:
    """Check the status of a forked tmux session."""
    status_file = get_status_file(session_id)
    log_file = get_log_file(session_id)

    if not status_file.exists():
        return {"status": "not_found", "session_id": session_id}

    try:
        with open(status_file) as f:
            data = json.load(f)
        data["session_id"] = session_id
        if log_file.exists():
            data["log_file"] = str(log_file)

        # Fallback: if status says "running" but the tmux window is gone,
        # the process exited without updating the status file.
        if data.get("status") == "running":
            window_name = data.get("window_name")
            if window_name and not _tmux_window_exists(window_name):
                data["status"] = "completed"
                data["exit_code"] = None
                data["completed_at"] = time.time()
                data["detection"] = "tmux_window_gone"
                with open(status_file, "w") as f:
                    json.dump(data, f)

        return data
    except json.JSONDecodeError:
        return {
            "status": "error",
            "session_id": session_id,
            "error": "Invalid status file",
        }


def wait_for_completion(
    session_id: str, timeout: float = None, poll_interval: float = 0.5
) -> dict:
    """Wait for a forked tmux session to complete."""
    start_time = time.time()

    while True:
        status = check_status(session_id)

        if status.get("status") == "completed":
            return status

        if status.get("status") == "not_found":
            return status

        if timeout and (time.time() - start_time) >= timeout:
            return {
                "status": "timeout",
                "session_id": session_id,
                "elapsed": time.time() - start_time,
            }

        time.sleep(poll_interval)


def cleanup_status(session_id: str) -> dict:
    """Remove the status, log, and wrapper script files for a session."""
    status_file = get_status_file(session_id)
    log_file = get_log_file(session_id)
    script_file = _get_script_file(session_id)

    result = {"status_removed": False, "log_removed": False, "script_removed": False}

    if status_file.exists():
        status_file.unlink()
        result["status_removed"] = True

    if log_file.exists():
        log_file.unlink()
        result["log_removed"] = True

    if script_file.exists():
        script_file.unlink()
        result["script_removed"] = True

    return result


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Fork a new tmux window with a command."
    )
    subparsers = parser.add_subparsers(dest="action", help="Action to perform")

    fork_parser = subparsers.add_parser("fork", help="Fork a new tmux window")
    fork_parser.add_argument("command", nargs="+", help="Command to run")
    fork_parser.add_argument("--no-track", action="store_true", help="Disable status tracking")
    fork_parser.add_argument("--cwd", help="Working directory for the command (defaults to current directory)")
    fork_parser.add_argument("--name", help="Custom name for the tmux window (defaults to command name)")

    status_parser = subparsers.add_parser("status", help="Check session status")
    status_parser.add_argument("session_id", help="Session ID to check")

    wait_parser = subparsers.add_parser("wait", help="Wait for session to complete")
    wait_parser.add_argument("session_id", help="Session ID to wait for")
    wait_parser.add_argument("--timeout", type=float, help="Timeout in seconds")

    cleanup_parser = subparsers.add_parser("cleanup", help="Remove status, log, and wrapper-script files")
    cleanup_parser.add_argument("session_id", help="Session ID to clean up")

    args = parser.parse_args()

    if args.action == "fork":
        result = fork_tmux(
            " ".join(args.command),
            track_status=not args.no_track,
            cwd=args.cwd,
            name=args.name,
        )
        print(json.dumps(result, indent=2))

    elif args.action == "status":
        result = check_status(args.session_id)
        print(json.dumps(result, indent=2))

    elif args.action == "wait":
        result = wait_for_completion(args.session_id, timeout=args.timeout)
        print(json.dumps(result, indent=2))

    elif args.action == "cleanup":
        result = cleanup_status(args.session_id)
        result["session_id"] = args.session_id
        print(json.dumps(result))

    else:
        parser.print_help()
