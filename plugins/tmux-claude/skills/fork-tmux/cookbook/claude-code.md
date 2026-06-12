# Claude Code in a Forked tmux Window

Launch Claude Code in a new tmux window with a specific task. Whether the window runs in YOLO mode (`--dangerously-skip-permissions`) is governed by `WINDOW_MODE` in SKILL.md's Variables (plugin user config): YOLO — the default — includes the flag because delegated windows exist to work unattended; CHICKEN omits it. Explicit request wording overrides either way.

## ⚠️ Critical: Correct CLI Syntax

**CORRECT:**
```bash
claude --dangerously-skip-permissions -- 'Your prompt here'   # WINDOW_MODE=YOLO (default)
claude -- 'Your prompt here'                                  # WINDOW_MODE=CHICKEN, or user asks for a safe window
```

**INCORRECT:**
```bash
claude "prompt with --flag"  # ❌ --flag parsed as CLI option, causes "unknown option" error
claude code "..."            # ❌ 'code' is not a valid subcommand
claude --code "..."          # ❌ no such flag
claude -c "..."              # ❌ not the right flag
```

**Why `--` is required:** The double-dash signals end-of-options to the CLI parser. Without it, any `--flag` patterns inside the prompt are parsed as claude CLI options, causing `error: unknown option` failures.

## Instructions

1. Extract the task/prompt from the user's request.
2. Construct the claude command using **exactly** this syntax: `claude --dangerously-skip-permissions -- '<prompt>'` (drop the flag when WINDOW_MODE is CHICKEN or the user asks for a safe window).
3. Run `fork_tmux.py fork` with the claude command.

## Execution

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude --dangerously-skip-permissions -- '<prompt>'"

# With custom working directory
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --cwd /path/to/directory "claude --dangerously-skip-permissions -- '<prompt>'"

# CHICKEN mode / safe window (permission prompts stay on)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude -- '<prompt>'"
```

**Notes:**
- The `fork` subcommand is required when using `fork_tmux.py` from CLI.
- Use `--cwd` to specify a different working directory (defaults to current directory).

## Examples

| User Request | Fork Command |
|--------------|--------------|
| "fork tmux with claude to review this PR" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude --dangerously-skip-permissions -- 'Review this PR and provide feedback'"` |
| "fork a window with claude to fix the tests" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude --dangerously-skip-permissions -- 'Fix the failing tests'"` |
| "fork a safe claude window to refactor the API" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude -- 'Refactor the API for better maintainability'"` |

## Notes

- The prompt should be wrapped in single quotes inside double quotes: `"claude --dangerously-skip-permissions -- 'prompt'"`
- The `--` before the prompt is mandatory to prevent option parsing errors.
- YOLO is the default because delegated windows are meant to run unattended (matching the gemini `-y` and codex `--yolo` recipes); a window that stalls on a permission prompt defeats the delegation. Drop the flag when WINDOW_MODE=CHICKEN or on explicit user request ("safe", "with permissions").
- Claude Code will inherit the current working directory.
- The forked tmux window will track execution status in `/tmp/fork-tmux-status/`.
