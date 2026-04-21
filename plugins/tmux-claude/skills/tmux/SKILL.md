---
name: tmux
description: Manage tmux panes and windows — split, close, send commands, read output, resize, focus, zoom, list, and create/close/switch windows. This skill should be used when the user asks to open a new pane, open a new window, run something in a side panel, read output from another pane, close a pane or window, maximize/zoom a pane, or manage tmux layout. Trigger patterns include "open a pane", "open a new window", "new window", "split pane", "close pane", "close window", "run X in a new pane", "read pane output", "resize pane", "zoom pane", "maximize pane", and "tmux split".
---

# Tmux Pane & Window Manager

Manage tmux panes (splits within a window) and windows (tabs). Requires an active tmux session (`$TMUX` must be set).

**Companion dotfiles:** This plugin ships an opinionated `tmux.conf` plus two plugins at `${CLAUDE_PLUGIN_ROOT}/dotfiles/` (Catppuccin theme, vi copy mode, prefix + `o` to open file paths, agent-indicator, clipboard-image paste). Install with `bash ${CLAUDE_PLUGIN_ROOT}/dotfiles/install.sh` — or run the `/tmux-claude-install-dotfiles` command from this plugin.

**Pane vs Window:** A *pane* is a split within the current view (side-by-side or stacked). A *window* is a separate full-screen tab. When the user says "new window", "new tab", or "open a window", use `window-new`. When they say "split", "side panel", or "new pane", use `split`.

## Script

All operations go through `${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py` — a plugin-level helper shared with the `handoff` skill. Always invoke it with the full `${CLAUDE_PLUGIN_ROOT}` prefix:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py <subcommand> [args]
```

## Subcommands

### list — Show all panes

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py list
```

Returns JSON array of panes with id, index, width, height, active status, running command, and working directory. Always run this first to discover pane indices and ids before targeting a specific pane.

### split — Open a new pane

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py split horizontal          # side-by-side
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py split vertical             # top-bottom
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py split horizontal -s 40%    # 40% width
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py split vertical -c /tmp     # with working dir
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py split horizontal "htop"    # run a command
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py split vertical -t 1        # split pane at index 1
```

Returns JSON with `pane_id` and `pane_index` of the new pane.

**Direction meanings:**
- `horizontal` = split left/right (side-by-side panes)
- `vertical` = split top/bottom (stacked panes)

### close — Close a pane

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py close 1       # by index
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py close %5      # by pane id
```

Never close pane index 0 (the Claude Code session) unless explicitly requested.

### send — Run a command in a pane

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py send "ls -la" -t 1
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py send "C-c" -t 1 --no-enter    # send Ctrl+C
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py send -f /tmp/prompt.txt -t @1  # read from file, target window
```

Use `--no-enter` for special keys (C-c, C-d, C-z) that should not be followed by Enter.

**`--file` / `-f`:** Read keys from a file. For single-line files, sends the content directly. For multi-line content (e.g., prompts for `claude`), combine with `--command-prefix` / `-p` to generate a launcher script automatically:

```bash
# Write prompt to file, then launch claude with it in window @1 (always pass --name — see Claude Code Launch Convention below)
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py send -f /tmp/prompt.txt -p "claude --name claude-<slug> --dangerously-skip-permissions --" -t @1
```

This generates a temp launcher script (`bash -c 'exec <prefix> "$(cat <file>)"'`) and sends it, avoiding all quoting issues.

**Cross-window targeting:** The `-t` flag accepts `@N` window IDs (e.g., `@1`, `@2`) to send commands to panes in other windows, not just the current one. Use `window-list` to find window IDs.

### read — Capture pane content

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py read -t 1              # visible content
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py read -t 1 --json        # as JSON
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py read -t 1 -S -100       # last 100 lines of scrollback
```

Use this to check command output, monitor long-running processes, or verify a pane's state.

### resize — Resize a pane

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py resize up 10 -t 1
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py resize left 20 -t 1
```

Directions: `up`, `down`, `left`, `right`. Amount defaults to 5 cells.

### focus — Switch to a pane

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py focus 1
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py focus %5
```

### zoom — Toggle maximize/restore a pane

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py zoom              # toggle zoom on caller's pane
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py zoom -t 1          # toggle zoom on pane at index 1
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py zoom -t %5         # toggle zoom on pane by id
```

Returns JSON with `pane` and `zoomed` (boolean) indicating the new state. When zoomed, the pane fills the entire window; running again restores the original layout.

## Window Subcommands

### window-list — Show all windows

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-list
```

Returns JSON array of windows with id, index, name, active status, and pane count.

### window-new — Create a new window

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-new                          # new window (detached)
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-new -n "server"              # explicit name
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-new -c /path/to/dir          # auto-named "dir"
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-new "tail -f app.log"        # auto-named "tail"
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-new -n "logs" "tail -f app.log"  # explicit overrides auto
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-new --switch                 # switch focus to new window
```

Returns JSON with `window_id`, `window_index`, and `window_name`.

**Detached by default:** Windows are created without stealing focus (`-d`). Use `--switch` to focus the new window immediately.

**Post-creation verification:** After creating the window, verifies it still exists (0.3s delay check). Raises an error if the window vanished — this catches cases where the shell or command exits immediately (e.g., invalid working directory, Claude session picker exit).

**Auto-naming:** When `-n` is omitted, the window name is derived automatically:
1. From the command basename (e.g., `"uv run serve"` → `uv`)
2. From the working directory basename (e.g., `-c ~/code/media-rag` → `media-rag`)
3. Falls back to tmux default if neither is provided

**Important — use `window_id` for subsequent operations:** Window names can collide when creating multiple windows. Always use the returned `window_id` (e.g., `@5`) with `send -t @5`, never the name.

### window-close — Close a window

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-close 2        # by index
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-close @1       # by window id
```

### window-select — Switch to a window

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-select 2
```

### window-rename — Rename a window

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-rename "new-name"           # current window
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-rename "new-name" -t 2      # specific window
```

## Claude Code Launch Convention

When launching `claude` in a new pane or window (via `split`, `window-new`, or `send -p`), **always** pass `--name <slug>` to the claude command so the Claude session is named — it appears in the prompt box, `/resume` picker, and terminal title. For `window-new`, use the **same slug** as the window name (`-n <slug>`) so the window and Claude session are correlatable.

**If the user specified a name** ("call it X", "name it X", "as 'X'"): use their value verbatim (lowercase + hyphenated, non-alphanumeric stripped).

**Otherwise, auto-derive** from the task prompt:
1. Pick 2–3 content words from the start of the task, skipping stopwords (`a an the to and or of for in on at with you we`).
2. Lowercase, replace whitespace/punctuation with `-`, collapse repeats.
3. Prefix with `claude-`.
4. Cap total length at ~30 chars.

Examples:

| User request | Slug | Invocation |
|---|---|---|
| "split pane with claude to run the migration" | `claude-run-migration` | `split horizontal "claude --name claude-run-migration -- 'Run the migration and verify rows'"` |
| "new window with claude to review PR 42" | `claude-review-pr` | `window-new -n claude-review-pr "claude --name claude-review-pr -- 'Review PR 42 and leave feedback'"` |
| "send a claude prompt to window @3 to fix the tests" | `claude-fix-tests` | `send -f /tmp/p.txt -p "claude --name claude-fix-tests --dangerously-skip-permissions --" -t @3` |

This convention mirrors the fork-tmux skill's fork-session recipe — the slug goes on both the tmux handle and the Claude CLI so the two identifiers stay in sync. See also the `fork-tmux` skill in this plugin (`skills/fork-tmux/cookbook/claude-code-fork-session.md`).

## Workflow

1. **Check environment**: Verify `$TMUX` is set before any operation.
2. **List first**: Run `list` or `window-list` to discover current layout before targeting panes/windows.
3. **Track ids, not names**: After `split` or `window-new`, save the returned `pane_id` / `window_id` for subsequent operations. Pane indices shift when panes are created/destroyed; names can collide across windows. IDs (e.g., `%5`, `@3`) are stable and unique.
4. **Read to verify**: After sending a command, use `read` to confirm execution and check output.
5. **Clean up**: Close panes/windows that are no longer needed to avoid clutter.

### Batch window creation pattern

When creating multiple windows (e.g., one per project), follow this two-phase approach:

1. **Create all windows first** — `window-new` creates detached by default, so the caller's focus stays put. Save each returned `window_id`.
2. **Send commands using `window_id`** — target each window by its `@N` id, never by name (names can collide).

```python
# Phase 1: create windows, collect IDs
ids = {}
for project in projects:
    result = window_new(name=project, cwd=f"/path/to/{project}")
    ids[project] = result["window_id"]  # e.g. "@5"

# Phase 2: send commands to each window by ID
for project, wid in ids.items():
    send(keys="some command", target=wid)
```

## Safety

- Never close the pane or window running the current Claude Code session unless the user explicitly asks.
- When sending commands, prefer quoting the full command string to avoid shell interpretation issues.
- Before closing a pane, consider reading it to check if it has unsaved work or running processes.
