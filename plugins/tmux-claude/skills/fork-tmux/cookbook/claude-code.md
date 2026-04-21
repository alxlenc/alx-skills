# Claude Code in a Forked tmux Window

Launch Claude Code in a new tmux window with a specific task.

## ⚠️ Critical: Correct CLI Syntax

**CORRECT:**
```bash
claude -- "Your prompt here"
claude -- 'Your prompt here'
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
2. Construct the claude command using **exactly** this syntax: `claude -- '<prompt>'`
3. Run `fork_tmux.py fork` with the claude command.

## Execution

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude -- '<prompt>'"

# With custom working directory
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --cwd /path/to/directory "claude -- '<prompt>'"
```

**Notes:**
- The `fork` subcommand is required when using `fork_tmux.py` from CLI.
- Use `--cwd` to specify a different working directory (defaults to current directory).

## Examples

| User Request | Fork Command |
|--------------|--------------|
| "fork tmux with claude to review this PR" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude -- 'Review this PR and provide feedback'"` |
| "fork a window with claude to fix the tests" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude -- 'Fix the failing tests'"` |
| "launch claude in a forked tmux window to refactor the API" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude -- 'Refactor the API for better maintainability'"` |

## Notes

- The prompt should be wrapped in single quotes inside double quotes: `"claude -- 'prompt'"`
- The `--` before the prompt is mandatory to prevent option parsing errors.
- Claude Code will inherit the current working directory.
- The forked tmux window will track execution status in `/tmp/fork-tmux-status/`.
