# Fork Current Claude Session into a New tmux Window

Launch a new tmux window that continues the current Claude Code session with full conversation context. The forked session can work on a side task independently while the parent session continues.

## Key Flags

| Flag | Purpose |
|------|---------|
| `--continue` | Resume the current conversation (preserves full context) |
| `--fork-session` | Fork into an independent session (changes don't affect parent) |

## Critical: Correct CLI Syntax

**CORRECT:**
```bash
claude --continue --fork-session --name <slug> -- 'Your side task prompt here'
claude --continue --fork-session --name <slug> --dangerously-skip-permissions -- 'Your side task prompt here'
```

**INCORRECT:**
```bash
claude --fork-session -- 'prompt'           # Missing --continue, starts fresh
claude --continue -- 'prompt'               # Missing --fork-session, modifies parent session
claude --continue --fork-session 'prompt'   # Missing --, prompt parsed as option
```

`--name <slug>` (equivalent to `-n <slug>`) sets the Claude session display name shown in the prompt box, `/resume` picker, and terminal title. Pass the same slug used for the tmux window so the two identifiers stay in sync.

## Instructions

1. Extract the side task / prompt from the user's request.
2. Check if user requested skip-permissions mode.
3. Derive a slug (see **Naming** below) — auto-generate unless the user specified one. The same slug is used for both the tmux window and the Claude session.
4. Construct the claude command with `--continue`, `--fork-session`, and `--name <slug>`.
5. Run the fork_tmux.py script with `--name <slug>` (tmux window) and the claude command.

## Naming

Every fork must pass the same slug twice — once to `fork_tmux.py --name` (tmux window) and once to `claude --name` (Claude session, visible in the prompt box, `/resume` picker, and terminal title). Keeping them identical makes the two identifiers trivially correlatable.

**If the user specified a name** (phrases like "name it X", "call it X", "as 'X'", "named <X>"): use their value verbatim (lowercase + hyphenated, non-alphanumeric stripped), prefixed with `fork-` only if they didn't include a prefix.

**Otherwise, auto-derive** from the task prompt:
1. Pick 2–3 content words from the start of the task, skipping stopwords (`a an the to and or of for in on at with you we`).
2. Lowercase, replace whitespace/punctuation with `-`, collapse repeats.
3. Prefix with `fork-`.
4. Cap total length at ~30 chars.

Examples:
| Task prompt | Slug (tmux + claude session) |
|---|---|
| "run the integration tests and fix failures" | `fork-run-integration-tests` |
| "check the CI pipeline status" | `fork-check-ci-pipeline` |
| "review the new cookbook files" | `fork-review-cookbook-files` |
| "confirm conversation context" | `fork-confirm-context` |

## Execution

```bash
# Standard mode - fork session with context (pass the same <slug> to both --name flags)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <slug> "claude --continue --fork-session --name <slug> -- '<prompt>'"

# Skip permissions mode
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <slug> "claude --continue --fork-session --name <slug> --dangerously-skip-permissions -- '<prompt>'"

# With custom working directory
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <slug> --cwd /path/to/directory "claude --continue --fork-session --name <slug> -- '<prompt>'"
```

**Notes:**
- The `fork` subcommand is required when using fork_tmux.py from CLI.
- Use `--cwd` to specify a different working directory (defaults to current directory).
- The forked session has the full conversation history but is independent — changes in the fork don't affect the parent session.
- The parent session should **STOP** after forking. Its work for the side task is done.

## Examples

| User Request | Slug | Fork Command |
|--------------|------|--------------|
| "fork session to review the plan" | `fork-review-plan` | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name fork-review-plan "claude --continue --fork-session --name fork-review-plan -- 'Review the plan we discussed and provide feedback'"` |
| "fork this session to run the tests" | `fork-run-tests` | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name fork-run-tests "claude --continue --fork-session --name fork-run-tests -- 'Run the test suite and fix any failures'"` |
| "side task: check the CI pipeline" | `fork-check-ci` | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name fork-check-ci "claude --continue --fork-session --name fork-check-ci -- 'Check the CI pipeline status and report back'"` |
| "fork session dangerously to fix style issues" | `fork-fix-style` | `python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name fork-fix-style "claude --continue --fork-session --name fork-fix-style --dangerously-skip-permissions -- 'Fix all style guide violations'"` |

## Behavior

- **Parent session**: After launching the fork, stop working on the side task. The parent session is free to continue other work or wait.
- **Forked session**: Opens in a new tmux window with the full conversation context. It operates independently — file edits, git commits, etc. in the fork do not appear in the parent.
- **Context preservation**: The forked session sees everything from the conversation up to the fork point. It can reference files discussed, decisions made, and instructions given.
