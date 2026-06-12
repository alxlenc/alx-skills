# Codex CLI in a Forked tmux Window (YOLO)

Launch OpenAI Codex CLI in a new tmux window with a specific task, in YOLO mode (auto-approve everything, no sandbox).

## Variables

DEFAULT_MODEL: (unset — uses the model from the user's `~/.codex/config.toml`)
FAST_MODEL: gpt-5.3-codex-spark

## ⚠️ Critical: Correct CLI Syntax

**CORRECT:**
```bash
codex --yolo -- 'Your task here'         # interactive TUI — window stays open after the task
codex exec --yolo -- 'Your task here'    # headless — runs to completion and exits
```

**INCORRECT:**
```bash
codex --yolo 'task with --flag'   # ❌ without --, flag-like text in the prompt is parsed as CLI options
codex -y -- 'task'                # ❌ -y is a gemini flag, not codex
codex -i -- 'task'                # ❌ -i attaches an image file; it does not mean "interactive"
codex chat -- 'task'              # ❌ no such subcommand
```

**Why `--yolo`:** alias for `--dangerously-bypass-approvals-and-sandbox` — skips all approval prompts and disables sandboxing, which is what makes the window fully autonomous. For a safer window (writes confined to the workspace, still no prompts) use `--sandbox workspace-write --ask-for-approval never` instead.

**Why `--` is required:** the double-dash signals end-of-options. Without it, any `--word` inside the prompt is parsed as a codex CLI option and errors with `unexpected argument`.

## Instructions

1. Extract the task/prompt from the user's request.
2. Choose the mode:
   - **Default: interactive TUI** — `codex --yolo -- '<prompt>'`. The window stays open; the user can follow up inside it. No log file (TUI), but status tracking still works.
   - **Headless** (user says "headless", "exec", "fire and forget", or wants the output captured) — `codex exec --yolo -- '<prompt>'`. fork-tmux captures a log file and exit code in `/tmp/fork-tmux-status/`.
3. Model: leave `-m` unset (user's config default). If the user says "fast" or "spark", add `-m gpt-5.3-codex-spark`.
4. Prompt style: Codex works best with operator-style prompts — state the concrete task AND what "done" looks like (e.g., "Fix the failing tests; done when `pytest` exits 0").
5. Run `fork_tmux.py fork` with the codex command, passing `--name` per the Window Naming rules in SKILL.md.
6. **After forking, verify the window came up** — read the pane and accept the trust prompt if present (see below).

## Execution

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <task-slug> "codex --yolo -- '<prompt>'"

# Headless with log capture + exit code
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <task-slug> "codex exec --yolo -- '<prompt>'"

# With custom working directory
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --cwd /path/to/repo --name <task-slug> "codex --yolo -- '<prompt>'"

# Fast model
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <task-slug> "codex -m gpt-5.3-codex-spark --yolo -- '<prompt>'"
```

## First Run in a New Directory: Trust Prompt

In a directory codex hasn't seen before, it shows a one-time trust prompt ("Do you trust the contents of this directory?") **before** starting — even in YOLO mode, and `-c 'projects."<dir>".trust_level="trusted"'` overrides do NOT suppress it (verified v0.137.0; trust must already be recorded in `~/.codex/config.toml`). An unattended window stalls there, so always check after forking:

```bash
tmux capture-pane -t <window-name> -p | tail -5   # trust prompt showing?
tmux send-keys -t <window-name> Enter             # accept — "Yes, continue" is preselected
```

Directories the user already ran codex in skip the prompt.

## Examples

| User Request | Fork Command |
|--------------|--------------|
| "open a yolo codex window to fix the failing tests" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name fix-tests "codex --yolo -- 'Fix the failing tests; done when the test suite passes'"` |
| "delegate to codex: refactor the API for maintainability" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name api-refactor "codex --yolo -- 'Refactor the API for better maintainability'"` |
| "fork a headless codex window to update the changelog" | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name changelog "codex exec --yolo -- 'Update CHANGELOG.md from the unreleased commits'"` |

## Notes

- The prompt is wrapped in single quotes inside double quotes: `"codex --yolo -- 'prompt'"`.
- Codex expects a git repository. Interactive mode asks for confirmation in non-git directories; `codex exec` refuses unless you add `--skip-git-repo-check`.
- Codex inherits the working directory (use `--cwd` on `fork_tmux.py`; codex's own `-C` is not needed).
- Status tracking lives in `/tmp/fork-tmux-status/` either way; only `codex exec` also produces a log file (the TUI is auto-detected as interactive and not piped).
- YOLO mode executes whatever the model decides without asking — only delegate tasks you'd be comfortable running unattended in that directory.
- If the pane shows "Your access token could not be refreshed" or a 401 `token_expired` error, codex auth has lapsed — the task will not run. Tell the user to run `codex login` (interactive browser flow; cannot be done from inside the delegation window).
