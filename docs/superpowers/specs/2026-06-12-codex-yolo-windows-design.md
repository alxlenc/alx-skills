# YOLO Codex Delegation Windows — Design

**Date:** 2026-06-12
**Status:** Implemented in tmux-claude 0.5.0

## Goal

Teach the tmux-claude plugin to delegate tasks to OpenAI Codex CLI by opening YOLO-mode codex sessions in a new tmux window or pane, the same way it already does for Claude Code and Gemini CLI.

## Approach

Extend the existing per-CLI cookbook architecture rather than adding a new skill or adopting the official codex-plugin-cc broker model (which runs codex headless behind an app-server — a different UX from visible, supervisable tmux windows).

## Components

- **`skills/fork-tmux/cookbook/codex.md`** (new) — recipe for tracked window forks. Interactive TUI by default (`codex --yolo -- '<prompt>'`); headless variant (`codex exec --yolo -- '<prompt>'`) when log capture / fire-and-forget is wanted. Model unset by default; `-m gpt-5.3-codex-spark` for "fast". `--` separator mandatory so flag-like prompt text isn't parsed as options.
- **`skills/fork-tmux/SKILL.md`** — `ENABLE_CODEX` variable, Codex routing recipe, guard list, naming example, interactive-detection note.
- **`skills/fork-tmux/scripts/fork_tmux.py`** — `is_interactive_command()` now classifies `codex` as interactive (TUI must not be piped) while `codex exec` / `codex e` stay non-interactive to keep log capture.
- **`skills/tmux/SKILL.md`** — Codex Launch Convention for panes/windows (`codex-` slug prefix; codex has no `--name` flag).
- Docs: README skills list, USAGE_PATTERNS pattern with context-flow diagram, plugin.json 0.5.0.

## Key findings (verified live, codex-cli 0.137.0)

- `--yolo` is a working hidden alias for `--dangerously-bypass-approvals-and-sandbox`.
- First run in a new directory shows a trust prompt **even in YOLO mode**, and `-c projects."<dir>".trust_level="trusted"` does not suppress it — trust must already be in `~/.codex/config.toml`. Recipes therefore mandate a post-launch pane check + Enter to accept.
- `codex exec` refuses non-git directories without `--skip-git-repo-check`.
- Expired codex auth (401 `token_expired`) renders the window inert; only `codex login` (interactive) fixes it.
