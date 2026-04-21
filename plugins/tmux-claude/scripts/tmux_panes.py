#!/usr/bin/env python3
"""Tmux pane and window manager — split, close, send, read, resize, focus, list, and window operations."""

import argparse
import json
import os
import subprocess
import sys


def run_tmux(*args: str) -> str:
    """Run a tmux command and return stdout. Raise on failure."""
    result = subprocess.run(
        ["tmux", *args],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"tmux {args[0]} failed")
    return result.stdout.strip()


def _caller_pane() -> str | None:
    """Return the $TMUX_PANE of the calling process, or None."""
    return os.environ.get("TMUX_PANE") or None


def _caller_window() -> str | None:
    """Return the window id containing the caller's pane, or None."""
    pane = _caller_pane()
    if not pane:
        return None
    return run_tmux("display-message", "-p", "-t", pane, "#{window_id}")


def _pane_info(fmt: str = "#{pane_id}|#{pane_index}|#{pane_width}|#{pane_height}|#{pane_active}|#{pane_current_command}|#{pane_current_path}") -> list[dict]:
    """Return structured info for every pane in the caller's window."""
    list_args = ["list-panes", "-F", fmt]
    caller = _caller_pane()
    if caller:
        list_args.extend(["-t", caller])
    raw = run_tmux(*list_args)
    panes = []
    for line in raw.splitlines():
        parts = line.split("|", 6)
        panes.append({
            "id": parts[0],
            "index": int(parts[1]),
            "width": int(parts[2]),
            "height": int(parts[3]),
            "active": parts[4] == "1",
            "command": parts[5],
            "path": parts[6],
        })
    return panes


def _pane_command(target: str) -> str:
    """Return the current command running in the given pane/window target."""
    return run_tmux("display-message", "-p", "-t", target, "#{pane_current_command}")


def _resolve_target(target: str | None) -> str:
    """Resolve a target pane identifier.

    Accepts:
      - None          → caller's pane
      - %N            → pane id (passed through)
      - @N            → window id (targets active pane in that window)
      - integer       → pane index within caller's window
    """
    if target is None:
        return _caller_pane() or ""
    # If it's already a tmux pane id like %0, %1 ...
    if target.startswith("%"):
        return target
    # Window id like @0, @1 — target the active pane in that window
    if target.startswith("@"):
        return target
    # Try numeric index
    try:
        idx = int(target)
        panes = _pane_info()
        for p in panes:
            if p["index"] == idx:
                return p["id"]
        raise ValueError(f"No pane with index {idx}")
    except ValueError as e:
        if "No pane" in str(e):
            raise
        raise ValueError(f"Invalid pane target: {target}") from e


# ── Subcommands ──────────────────────────────────────────────────────────────


def cmd_list(args: argparse.Namespace) -> None:
    """List all panes in the current window."""
    panes = _pane_info()
    print(json.dumps(panes, indent=2))


def cmd_split(args: argparse.Namespace) -> None:
    """Split a pane horizontally or vertically."""
    flags = ["-h"] if args.direction == "horizontal" else ["-v"]
    target = _resolve_target(args.target) if args.target else _caller_pane()
    if target:
        flags.extend(["-t", target])
    if args.size:
        if args.size.endswith("%"):
            flags.extend(["-p", args.size.rstrip("%")])
        else:
            flags.extend(["-l", args.size])
    if args.cwd:
        flags.extend(["-c", args.cwd])
    shell_cmd = [args.command] if args.command else []
    output = run_tmux("split-window", *flags, "-P", "-F", "#{pane_id}|#{pane_index}", *shell_cmd)
    pane_id, pane_index = output.split("|", 1)
    print(json.dumps({"pane_id": pane_id, "pane_index": int(pane_index)}))


def cmd_close(args: argparse.Namespace) -> None:
    """Close a specific pane."""
    target = _resolve_target(args.target)
    if not target:
        raise RuntimeError("Specify a pane target to close (index or id)")
    run_tmux("kill-pane", "-t", target)
    print(json.dumps({"closed": target}))


def cmd_send(args: argparse.Namespace) -> None:
    """Send keys (a command) to a specific pane.

    When --file is used with --command-prefix, generates a launcher script that
    passes file content as an argument to the prefix command. This avoids shell
    quoting issues with complex multi-line content.

    When --file is used without --command-prefix, sends the file content as a
    single send-keys call (works for single-line files).
    """
    target = _resolve_target(args.target)
    if args.file:
        if args.command_prefix:
            # Check if the target pane is already running a matching process
            prefix_cmd = args.command_prefix.split()[0].split("/")[-1]
            already_running = False
            if target:
                try:
                    current_cmd = _pane_command(target)
                    if current_cmd and prefix_cmd in current_cmd:
                        already_running = True
                except RuntimeError:
                    pass  # target may not exist yet; proceed with launcher

            if already_running:
                print(
                    f"Warning: target pane already running '{current_cmd}', "
                    f"sending file content directly instead of launching new process",
                    file=sys.stderr,
                )
                with open(args.file) as f:
                    keys = f.read().rstrip("\n")
            else:
                # Generate a launcher script: <prefix> "$(cat <file>)"
                # NOTE: Do not use `exec` here — we want the shell to survive
                # after the command exits so the pane stays open for inspection.
                # WARNING: If the command prefix is `claude`, use `--` (not `-p`)
                # to pass the prompt as a positional arg. Claude's `-p` flag means
                # `--print` (non-interactive headless mode), which disables the TUI.
                # Correct:   claude --dangerously-skip-permissions -- "$(cat ...)"
                # Wrong:     claude --dangerously-skip-permissions -p "$(cat ...)"
                import tempfile
                launcher = tempfile.NamedTemporaryFile(
                    mode="w", prefix="tmux-launch-", suffix=".sh", delete=False
                )
                launcher.write("#!/bin/bash\n")
                launcher.write(f'{args.command_prefix} "$(cat {args.file})"\n')
                launcher.close()
                os.chmod(launcher.name, 0o755)
                keys = f"bash {launcher.name}"
        else:
            with open(args.file) as f:
                keys = f.read().rstrip("\n")
    else:
        keys = args.keys

    tmux_args = ["send-keys"]
    if target:
        tmux_args.extend(["-t", target])
    tmux_args.append(keys)
    if not args.no_enter:
        tmux_args.append("Enter")
    run_tmux(*tmux_args)
    label = keys[:80] + "..." if len(keys) > 80 else keys
    print(json.dumps({"sent_to": target or "(active)", "keys": label}))


def cmd_read(args: argparse.Namespace) -> None:
    """Capture visible content from a pane."""
    target = _resolve_target(args.target)
    tmux_args = ["capture-pane", "-p"]
    if target:
        tmux_args.extend(["-t", target])
    if args.start is not None:
        tmux_args.extend(["-S", str(args.start)])
    if args.end is not None:
        tmux_args.extend(["-E", str(args.end)])
    content = run_tmux(*tmux_args)
    if args.json:
        print(json.dumps({"pane": target or "(active)", "content": content}))
    else:
        print(content)


def cmd_resize(args: argparse.Namespace) -> None:
    """Resize a pane."""
    target = _resolve_target(args.target)
    direction_flag = {
        "up": "-U",
        "down": "-D",
        "left": "-L",
        "right": "-R",
    }[args.direction]
    tmux_args = ["resize-pane"]
    if target:
        tmux_args.extend(["-t", target])
    tmux_args.extend([direction_flag, str(args.amount)])
    run_tmux(*tmux_args)
    print(json.dumps({"resized": target or "(active)", "direction": args.direction, "amount": args.amount}))


def cmd_focus(args: argparse.Namespace) -> None:
    """Switch focus to a specific pane."""
    target = _resolve_target(args.target)
    if not target:
        raise RuntimeError("Specify a pane target to focus (index or id)")
    run_tmux("select-pane", "-t", target)
    print(json.dumps({"focused": target}))


def cmd_zoom(args: argparse.Namespace) -> None:
    """Toggle zoom (maximize/restore) on a pane."""
    target = _resolve_target(args.target) if args.target else _caller_pane()
    tmux_args = ["resize-pane", "-Z"]
    if target:
        tmux_args.extend(["-t", target])
    run_tmux(*tmux_args)
    # Check if the pane is now zoomed
    zoomed = run_tmux("display-message", "-p", "-t", target or "", "#{window_zoomed_flag}")
    print(json.dumps({"pane": target or "(active)", "zoomed": zoomed == "1"}))


# ── Window Subcommands ───────────────────────────────────────────────────────


def _window_info() -> list[dict]:
    """Return structured info for every window in the current session."""
    fmt = "#{window_id}|#{window_index}|#{window_name}|#{window_active}|#{window_panes}"
    raw = run_tmux("list-windows", "-F", fmt)
    windows = []
    for line in raw.splitlines():
        parts = line.split("|", 4)
        windows.append({
            "id": parts[0],
            "index": int(parts[1]),
            "name": parts[2],
            "active": parts[3] == "1",
            "panes": int(parts[4]),
        })
    return windows


def cmd_window_list(args: argparse.Namespace) -> None:
    """List all windows in the current session."""
    print(json.dumps(_window_info(), indent=2))


def _derive_window_name(args: argparse.Namespace) -> str | None:
    """Derive a window name from the command or working directory."""
    if args.name:
        return args.name
    if args.command:
        return args.command.split()[0].split("/")[-1]
    if args.cwd:
        return os.path.basename(os.path.normpath(args.cwd))
    return None


def cmd_window_new(args: argparse.Namespace) -> None:
    """Create a new tmux window.

    Always creates detached (-d) by default to avoid stealing focus from the
    caller's window. Use --switch to focus the new window immediately.

    After creation, verifies the window still exists (catches cases where the
    shell or command exits immediately, e.g. Claude's session picker exit).
    """
    import time

    name = _derive_window_name(args)
    flags = []
    if not args.switch:
        flags.append("-d")
    if name:
        flags.extend(["-n", name])
    if args.cwd:
        flags.extend(["-c", args.cwd])
    shell_cmd = [args.command] if args.command else []
    output = run_tmux("new-window", *flags, "-P", "-F", "#{window_id}|#{window_index}|#{window_name}", *shell_cmd)
    window_id, window_index, window_name = output.split("|", 2)

    # Verify the window persists after a brief delay
    time.sleep(0.3)
    live_ids = run_tmux("list-windows", "-F", "#{window_id}")
    if window_id not in live_ids.splitlines():
        raise RuntimeError(
            f"Window {window_id} ({window_name}) was created but immediately "
            f"closed — the shell or command likely exited. Check the command "
            f"or working directory."
        )

    print(json.dumps({"window_id": window_id, "window_index": int(window_index), "window_name": window_name}))


def cmd_window_close(args: argparse.Namespace) -> None:
    """Close a tmux window by index or id."""
    run_tmux("kill-window", "-t", args.target)
    print(json.dumps({"closed": args.target}))


def cmd_window_select(args: argparse.Namespace) -> None:
    """Switch to a tmux window by index or id."""
    run_tmux("select-window", "-t", args.target)
    print(json.dumps({"selected": args.target}))


def cmd_window_rename(args: argparse.Namespace) -> None:
    """Rename a tmux window."""
    target = args.target or _caller_window()
    tmux_args = ["rename-window"]
    if target:
        tmux_args.extend(["-t", target])
    tmux_args.append(args.name)
    run_tmux(*tmux_args)
    print(json.dumps({"renamed": target or "(current)", "name": args.name}))


# ── CLI ──────────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(description="Tmux pane manager")
    sub = parser.add_subparsers(dest="subcommand", required=True)

    # list
    sub.add_parser("list", help="List panes in current window")

    # split
    p_split = sub.add_parser("split", help="Split a pane")
    p_split.add_argument("direction", choices=["horizontal", "vertical"], help="Split direction (horizontal=side-by-side, vertical=top-bottom)")
    p_split.add_argument("-t", "--target", help="Target pane (index or %%id)")
    p_split.add_argument("-s", "--size", help="Size: lines, or 'N%%' for percentage")
    p_split.add_argument("-c", "--cwd", help="Working directory for new pane")
    p_split.add_argument("command", nargs="?", help="Command to run in new pane")

    # close
    p_close = sub.add_parser("close", help="Close a pane")
    p_close.add_argument("target", help="Pane to close (index or %%id)")

    # send
    p_send = sub.add_parser("send", help="Send keys to a pane")
    p_send.add_argument("keys", nargs="?", default="", help="Keys/command to send")
    p_send.add_argument("-t", "--target", help="Target pane (index, %%id, or @window_id)")
    p_send.add_argument("-f", "--file", help="Read keys from file (avoids shell quoting issues)")
    p_send.add_argument("-p", "--command-prefix", help="When used with --file, generates a launcher script: <prefix> \"$(cat <file>)\"")
    p_send.add_argument("--no-enter", action="store_true", help="Don't append Enter key")

    # read
    p_read = sub.add_parser("read", help="Capture pane content")
    p_read.add_argument("-t", "--target", help="Target pane (index or %%id)")
    p_read.add_argument("-S", "--start", type=int, help="Start line (negative = scrollback)")
    p_read.add_argument("-E", "--end", type=int, help="End line")
    p_read.add_argument("--json", action="store_true", help="Output as JSON")

    # resize
    p_resize = sub.add_parser("resize", help="Resize a pane")
    p_resize.add_argument("direction", choices=["up", "down", "left", "right"])
    p_resize.add_argument("amount", type=int, nargs="?", default=5, help="Cells to resize by (default: 5)")
    p_resize.add_argument("-t", "--target", help="Target pane (index or %%id)")

    # focus
    p_focus = sub.add_parser("focus", help="Focus a pane")
    p_focus.add_argument("target", help="Pane to focus (index or %%id)")

    # zoom
    p_zoom = sub.add_parser("zoom", help="Toggle zoom (maximize/restore) a pane")
    p_zoom.add_argument("-t", "--target", help="Target pane (index or %%id)")

    # window-list
    sub.add_parser("window-list", help="List all windows in current session")

    # window-new
    p_wnew = sub.add_parser("window-new", help="Create a new window")
    p_wnew.add_argument("-n", "--name", help="Window name")
    p_wnew.add_argument("-c", "--cwd", help="Working directory")
    p_wnew.add_argument("--switch", action="store_true", help="Switch to the new window immediately (default: create detached)")
    p_wnew.add_argument("command", nargs="?", help="Command to run")

    # window-close
    p_wclose = sub.add_parser("window-close", help="Close a window")
    p_wclose.add_argument("target", help="Window index or id to close")

    # window-select
    p_wselect = sub.add_parser("window-select", help="Switch to a window")
    p_wselect.add_argument("target", help="Window index or id to select")

    # window-rename
    p_wrename = sub.add_parser("window-rename", help="Rename a window")
    p_wrename.add_argument("name", help="New window name")
    p_wrename.add_argument("-t", "--target", help="Window index or id (default: current)")

    args = parser.parse_args()

    dispatch = {
        "list": cmd_list,
        "split": cmd_split,
        "close": cmd_close,
        "send": cmd_send,
        "read": cmd_read,
        "resize": cmd_resize,
        "focus": cmd_focus,
        "zoom": cmd_zoom,
        "window-list": cmd_window_list,
        "window-new": cmd_window_new,
        "window-close": cmd_window_close,
        "window-select": cmd_window_select,
        "window-rename": cmd_window_rename,
    }

    try:
        dispatch[args.subcommand](args)
    except (RuntimeError, ValueError) as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
