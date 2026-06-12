# Gemini CLI in a Forked tmux Window

Launch Gemini CLI in a new tmux window with a specific task.

## Variables

DEFAULT_MODEL: gemini-3-pro-preview
HEAVY_MODEL: gemini-3-pro-preview
FAST_MODEL: gemini-2.5-flash

## Critical: Correct CLI Syntax

**CORRECT:**
```bash
gemini --model gemini-3-pro-preview -y -i "Your prompt here"
gemini -m gemini-2.5-flash -y -i 'Your prompt here'
```

**INCORRECT:**
```bash
gemini "prompt"           # Missing -i flag for interactive mode
gemini -i "prompt" -y     # Flags in wrong order (-i must be last)
gemini --interactive      # Wrong flag name
```

**Why `-i` must be last:** The `-i` (or `--prompt-interactive`) flag expects the prompt immediately after it. Placing other flags after `-i` will cause parsing errors.

## Instructions

1. Extract the task/prompt from the user's request.
2. Determine the model:
   - Default: `gemini-3-pro-preview` (DEFAULT_MODEL)
   - If user says "fast" or speed is important: `gemini-2.5-flash` (FAST_MODEL)
   - If user says "heavy" or complex task: `gemini-3-pro-preview` (HEAVY_MODEL)
3. Construct the gemini command using **exactly** this syntax: `gemini --model <model> -y -i '<prompt>'`
4. Run `fork_tmux.py fork` with the gemini command.

## Execution

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "gemini --model gemini-3-pro-preview -y -i '<prompt>'"

# With custom working directory
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --cwd /path/to/directory "gemini --model gemini-3-pro-preview -y -i '<prompt>'"

# With fast model
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "gemini --model gemini-2.5-flash -y -i '<prompt>'"
```

**Notes:**
- The `fork` subcommand is required when using `fork_tmux.py` from CLI.
- Use `--cwd` to specify a different working directory (defaults to current directory).
- Include `-y` (yolo mode) to auto-accept tool actions — unless `WINDOW_MODE` is CHICKEN (see SKILL.md Variables) or the user asks for a safe window.
- Always use `-i` for interactive mode (continues after prompt execution).

## Examples

| User Request | Fork Command |
|--------------|--------------|
| "fork tmux with gemini to review this code" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "gemini --model gemini-3-pro-preview -y -i 'Review this code and provide feedback'"` |
| "fork a window with gemini fast to fix the tests" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "gemini --model gemini-2.5-flash -y -i 'Fix the failing tests'"` |
| "launch gemini in a forked tmux window to refactor the API" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "gemini --model gemini-3-pro-preview -y -i 'Refactor the API for better maintainability'"` |

## Notes

- The prompt should be wrapped in single quotes inside double quotes: `"gemini ... -i 'prompt'"`
- The `-i` flag must come last, immediately before the prompt.
- Include `-y` for yolo mode to auto-accept actions (omit when WINDOW_MODE=CHICKEN or a safe window was requested).
- Gemini CLI will inherit the current working directory.
- The forked tmux window will track execution status in `/tmp/fork-tmux-status/`.
