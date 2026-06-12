---
name: fork-tmux
description: "Fork a new tmux window that runs a command with status tracking, log capture, and wait-for-completion polling. Use when the user requests 'fork tmux', 'fork a window', 'fork to run X', 'side task: <task>', 'fork session', 'fork this session', 'rewind session', 'rewind to', or wants to delegate a task to Claude, Gemini, or Codex (YOLO) in a new tmux window. Requires an active tmux session ($TMUX). Supports forking the current Claude session with full context preservation, and rewinding to a previous conversation state. Prefer the `tmux` skill's `window-new` for lightweight fire-and-forget window creation; use fork-tmux when you need a tracked session."
---

# Purpose

Fork a new **tmux window** that runs a command, with lifecycle management layered on top (session ID, status file, log capture for non-interactive commands, and polling helpers). Specialized for tmux — requires `$TMUX` to be set.

**When to use this skill vs. the `tmux` skill:**
- `tmux` skill's `window-new` → lightweight, fire-and-forget window creation
- `fork-tmux` (this skill) → tracked session: you get a `session_id` you can `status`/`wait`/`cleanup` on, plus automatic log files for non-interactive commands

Follow the `Instructions`, execute the `Workflow`, based on the `Cookbook`.

## Variables

ENABLE_RAW_CLI_COMMANDS: true
ENABLE_CLAUDE_CODE: true
ENABLE_GEMINI_CLI: true
ENABLE_CODEX: true
ENABLE_SESSION_FORK: true
WINDOW_MODE: ${user_config.window_mode}

### WINDOW_MODE — YOLO vs CHICKEN

`WINDOW_MODE` (plugin user config, set via `/plugin` → tmux-claude → configure) decides whether delegated agent windows auto-approve actions:

- **YOLO** — include the bypass flag in the agent command: `claude --dangerously-skip-permissions`, `codex --yolo`, `gemini -y`.
- **CHICKEN** — omit that flag so the window keeps its normal permission/approval prompts.

Resolution order: explicit request wording ("safe window", "with permissions" → CHICKEN; "yolo", "dangerously" → YOLO) **beats** WINDOW_MODE. If WINDOW_MODE is anything other than `CHICKEN` — including blank or an unsubstituted `${...}` placeholder — treat it as YOLO. Apply this when executing any agent cookbook below; the cookbook examples show the YOLO form.

## Requirements

- Must be running inside tmux (`$TMUX` must be set). The script exits with code 2 otherwise.

## Instructions

- Based on the user's request, follow the `Cookbook` to determine which recipe applies.
- Always invoke the script via `${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py` — never a bare relative path.

## Workflow

1. Understand the user's request and extract:
   - The command to run
   - The working directory (if specified, otherwise use current directory)
2. READ: `${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py` to understand the tooling.
3. **MANDATORY**: Follow the `Cookbook` section below to determine which recipe applies.
4. **MANDATORY**: Read the cookbook file specified in the matching recipe.
5. Execute `fork_tmux.py fork` using the syntax from the cookbook, adding `--cwd <path>` if a working directory was specified and `--name <name>` following the Window Naming rules below.

### Window Naming

**Always** pass `--name` when invoking `fork_tmux.py fork`. If the user specified a name, use it. Otherwise, generate a short, descriptive name from the task context:

- **2-4 words**, kebab-case (e.g., `style-review`, `quiz-gen`, `deploy-staging`)
- Describe the **task**, not the binary (e.g., `lecture-update` not `claude`, `build-images` not `npm`)
- Keep it under 20 characters so it fits in the tmux status bar

Examples:
| User request | `--name` |
|---|---|
| "fork tmux to run the tests" | `run-tests` |
| "fork with claude to review the PR" | `pr-review` |
| "fork to run npm install" | `npm-install` |
| "fork session to fix the style violations" | `fix-style` |
| "fork tmux with gemini to analyze the logs" | `log-analysis` |
| "open a yolo codex window to fix the tests" | `fix-tests` |

### Working Directory Detection

Extract the working directory from phrases like:
- "in /path/to/dir" → `--cwd /path/to/dir`
- "from /path/to/dir" → `--cwd /path/to/dir`
- "at /path/to/dir" → `--cwd /path/to/dir`
- "with cwd /path/to/dir" → `--cwd /path/to/dir`

If no working directory is specified, omit `--cwd` (defaults to current directory).

---

## ⚠️ GUARD: Cookbook Must Be Read Before Execution

**DO NOT** execute `fork_tmux.py` until you have:

1. ✅ Identified which cookbook recipe applies (Raw CLI Commands, Claude Code, Gemini CLI, Codex CLI, Fork Current Session, OR Fork and Rewind Session)
2. ✅ **Actually read** the corresponding cookbook file using the Read tool
3. ✅ Verified the correct command syntax from that cookbook

**NEVER** skip directly to `fork_tmux.py`. The cookbook contains critical syntax requirements that differ between raw CLI commands and Claude Code invocations.

**If you skip the cookbook**, you will likely use incorrect syntax (e.g., `claude code "..."` instead of `claude "..."`), causing the forked window to fail silently.

---

## Cookbook

### Raw CLI Commands

- IF: The user requests a raw CLI command to run in a new tmux window AND `ENABLE_RAW_CLI_COMMANDS` is true.
- THEN: Read and execute: `${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/cookbook/cli-command.md`
- EXAMPLES:
  - "fork tmux to run npm install"
  - "fork a window for python script.py"
  - "fork to launch htop"
  - "run in a forked tmux window: docker compose up"
  - "fork tmux in /home/user/project to run make build"

### Claude Code

- IF: The user requests Claude Code to run in a new tmux window AND `ENABLE_CLAUDE_CODE` is true.
- THEN: Read and execute: `${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/cookbook/claude-code.md`
- EXAMPLES:
  - "fork tmux with claude to review this PR"
  - "fork a window with claude to fix the tests"
  - "launch claude in a forked tmux window to refactor the API"
  - "fork tmux in /home/user/course with claude to run the setup phase"

### Gemini CLI

- IF: The user requests Gemini CLI to run in a new tmux window AND `ENABLE_GEMINI_CLI` is true.
- THEN: Read and execute: `${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/cookbook/gemini-cli.md`
- EXAMPLES:
  - "fork tmux with gemini to review this code"
  - "fork a window with gemini to analyze the project"
  - "launch gemini in a forked tmux window to refactor the API"
  - "fork tmux with gemini fast to fix the tests"
  - "fork tmux in /home/user/project with gemini to run the setup"

### Codex CLI

- IF: The user requests Codex (OpenAI Codex CLI) to run in a new tmux window AND `ENABLE_CODEX` is true.
- THEN: Read and execute: `${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/cookbook/codex.md`
- EXAMPLES:
  - "open a yolo codex window to fix the failing tests"
  - "fork tmux with codex to review this code"
  - "delegate to codex: refactor the API"
  - "fork a headless codex window to update the changelog"
  - "fork tmux in /home/user/project with codex to run the setup"

### Fork Current Session

- IF: The user wants to fork the **current Claude session** into a new tmux window (preserving conversation context) AND `ENABLE_SESSION_FORK` is true.
- THEN: Read and execute: `${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/cookbook/claude-code-fork-session.md`
- TRIGGER PHRASES: "fork session", "fork this session", "side task:", "fork the session to", "fork with context"
- EXAMPLES:
  - "fork session to review the plan"
  - "fork this session to run the style checks"
  - "side task: fix the style violations we discussed"
  - "fork the session to handle the integration tests while I keep working"
  - "fork session dangerously to run all the tests"

### Fork and Rewind Session

- IF: The user wants to fork the current session AND **rewind to a previous point** in the conversation before doing a task AND `ENABLE_SESSION_FORK` is true.
- THEN: Read and execute: `${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/cookbook/claude-code-rewind-session.md`
- TRIGGER PHRASES: "rewind session", "rewind to", "fork and rewind", "undo and redo", "go back to when", "go back to before", "rewind to where I said", "rewind to where you said", "go back to my message", "go back to your message"
- EXAMPLES (quote + task):
  - "rewind to where I said 'let's try the cache layer refactor' and use integration tests"
  - "go back to my message 'add TDD tests' and skip the mocks this time"
- EXAMPLES (quote + open-ended — "redo from here"):
  - "rewind to 'Here is the updated auth flow'" (quotes Claude's message, lands there interactively)
  - "fork and rewind to 'I suggest splitting this into two services'" (quotes Claude's message, waits for new direction)
  - "rewind to where I said 'let's start with the schema layer'" (quotes own message, waits for new input)
- EXAMPLES (description-based):
  - "rewind session to before the refactor and try a different approach"
  - "go back to before I asked you to change the approach and try TDD instead"
  - "undo the last few changes and redo with a different strategy"

---

## Troubleshooting

### Status and Log Files

Forked tmux sessions create files in `/tmp/fork-tmux-status/`:

| File | Purpose |
|------|---------|
| `<session_id>.json` | Status tracking (running/completed, exit code, timestamps, window name) |
| `<session_id>.log` | Full stdout/stderr output (non-interactive commands only) |
| `<session_id>.sh`  | Wrapper script that ran inside the tmux window |

**Note**: Interactive commands (Claude, Gemini, Codex, vim, nvim, nano, htop, top) are auto-detected and run without stdout piping to preserve their TUI interfaces. `codex exec` is the exception — it is headless, so it keeps log capture. Status tracking (exit code) still works, but no log file is created.

For Claude commands, the status file also includes `claude_session_id` and `claude_session_file` (path to the JSONL conversation history). These fields are `null` for non-Claude commands.

### Checking Session Status

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py status <session_id>

# Example output:
# {
#   "status": "completed",
#   "exit_code": 1,
#   "completed_at": "1234567890.123",
#   "session_id": "abc12345",
#   "log_file": "/tmp/fork-tmux-status/abc12345.log",
#   "claude_session_id": "a1b2c3d4-...",
#   "claude_session_file": "/home/user/.claude/projects/-home-user-project/a1b2c3d4-....jsonl"
# }
```

If the tmux window is closed without the wrapper script updating the status file, `status` detects the missing window and reports `"status": "completed"` with `"detection": "tmux_window_gone"` and `exit_code: null`.

### Viewing Error Logs

```bash
# View the full command output
cat /tmp/fork-tmux-status/<session_id>.log

# Or resolve the path via status output
cat "$(python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py status <session_id> | jq -r .log_file)"
```

### Understanding Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| `0` | Command succeeded |
| `1` | General error |
| `127` | Command not found |
| `130` | Terminated by Ctrl+C |

### Debugging Failed Commands

1. **Check exit code**: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py status <session_id>`
2. **View logs**: `cat /tmp/fork-tmux-status/<session_id>.log`
3. **tmux window**: Output is also visible in the forked window while it's open.
4. **Re-run manually**: Copy the command from the status file and run it directly to reproduce.

### Cleanup

Remove status, log, and wrapper-script files when no longer needed:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py cleanup <session_id>

# Output: {"status_removed": true, "log_removed": true, "script_removed": true, "session_id": "abc12345"}
```
