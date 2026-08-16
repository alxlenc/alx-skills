# Claude Code in a Forked tmux Window

Launch Claude Code in a new tmux window with a specific task. Whether the window runs in YOLO mode (`--dangerously-skip-permissions`) is governed by `WINDOW_MODE` in SKILL.md's Variables (plugin user config): YOLO — the default — includes the flag because delegated windows exist to work unattended; CHICKEN omits it. Explicit request wording overrides either way.

## ⚠️ Critical: Correct CLI Syntax

**CORRECT:**
```bash
claude --dangerously-skip-permissions -- 'Your prompt here'                        # WINDOW_MODE=YOLO (default)
claude -- 'Your prompt here'                                                       # WINDOW_MODE=CHICKEN, or user asks for a safe window
claude --dangerously-skip-permissions --name <session-name> -- 'Your prompt here'  # with session name
claude --name <session-name> -- 'Your prompt here'                                 # CHICKEN + session name
```

**INCORRECT:**
```bash
claude "prompt with --flag"  # ❌ --flag parsed as CLI option, causes "unknown option" error
claude code "..."            # ❌ 'code' is not a valid subcommand
claude --code "..."          # ❌ no such flag
claude -c "..."              # ❌ not the right flag
```

**Why `--` is required:** The double-dash signals end-of-options to the CLI parser. Without it, any `--flag` patterns inside the prompt are parsed as claude CLI options, causing `error: unknown option` failures.

`--name <session-name>` (equivalent to `-n <session-name>`) sets the Claude session display name shown in the prompt box, `/resume` picker, and terminal title. Place it before `--`, alongside other flags. This is the **Claude session name** — separate from `fork_tmux.py --name` which names the **tmux window**. Pass both to keep the two identifiers in sync.

## Instructions

1. Extract the task/prompt from the user's request.
2. If the request includes a session name (phrases like `--name <X>`, `claude --name <X>`, `named session <X>`), extract it. This is the Claude session name — pass it as `claude --name <session-name>` **and** as `fork_tmux.py fork --name <session-name>` so the tmux window and Claude session stay in sync.
3. Construct the claude command: `claude --dangerously-skip-permissions --name <session-name> -- '<prompt>'` (drop `--dangerously-skip-permissions` when WINDOW_MODE is CHICKEN; drop `--name` if no session name was specified).
4. Run `fork_tmux.py fork` with `--name <session-name>` (tmux window) and the claude command.

## Execution

```bash
# Standard (no session name)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude --dangerously-skip-permissions -- '<prompt>'"

# With session name (pass same name to both --name flags)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <session-name> "claude --dangerously-skip-permissions --name <session-name> -- '<prompt>'"

# With custom working directory
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --cwd /path/to/directory "claude --dangerously-skip-permissions -- '<prompt>'"

# CHICKEN mode / safe window (permission prompts stay on)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "claude -- '<prompt>'"

# CHICKEN mode with session name
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <session-name> "claude --name <session-name> -- '<prompt>'"
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
| "fork with claude --name lab-connect to run /lab-connect" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name lab-connect "claude --dangerously-skip-permissions --name lab-connect -- '/lab-connect'"` |

## Notes

- The prompt should be wrapped in single quotes inside double quotes: `"claude --dangerously-skip-permissions -- 'prompt'"`
- The `--` before the prompt is mandatory to prevent option parsing errors.
- When `--name` is specified, pass the same name to both `fork_tmux.py --name` (tmux window) and `claude --name` (Claude session) so the identifiers stay in sync.
- YOLO is the default because delegated windows are meant to run unattended (matching the gemini `-y` and codex `--yolo` recipes); a window that stalls on a permission prompt defeats the delegation. Drop the flag when WINDOW_MODE=CHICKEN or on explicit user request ("safe", "with permissions").
- Claude Code will inherit the current working directory.
- The forked tmux window will track execution status in `/tmp/fork-tmux-status/`.
