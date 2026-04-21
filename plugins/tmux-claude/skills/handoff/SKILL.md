---
name: handoff
description: Hand off the current conversation to a new Claude session when context is getting long. Opens a side-by-side tmux split, crafts a continuation prompt with full context (plan, tasks, progress, working directory), and launches Claude in yolo mode to continue the work automatically. This skill should be used when the user says the conversation is too long, asks to continue in a new session, or invokes /handoff.
---

# Handoff

Continue work in a fresh Claude session when the current conversation is getting long. Opens a side-by-side tmux split, generates a continuation prompt capturing all current context, and launches Claude in yolo mode to pick up where this session left off.

## Requirements

- Must be running inside tmux (`$TMUX` must be set)
- Relies on the `tmux` skill that ships with this plugin (`tmux_panes.py`)

## Workflow

### Step 1: Gather Context

Collect everything the new session needs to continue the work:

1. **Working directory** — `pwd`
2. **Active plan** — If a plan exists in the conversation, capture it in full
3. **Task list** — Use TaskList/TaskGet to retrieve all tasks and their statuses (completed, in-progress, pending)
4. **Progress summary** — What has been done so far and what remains
5. **Key decisions and constraints** — Any non-obvious choices, gotchas, or user preferences discovered during the session
6. **Current branch and git state** — `git branch --show-current`, `git status --short` (if in a git repo)
7. **Relevant file paths** — Files actively being worked on

### Step 2: Determine the Session Name

Derive a continuation name from the current tmux window:

```bash
tmux display-message -p '#{window_name}'
```

Append an incrementing number suffix:
- If the current name has no suffix (e.g., `market-data`), the new name is `market-data-2`
- If the current name already has a suffix (e.g., `market-data-2`), increment it to `market-data-3`
- Rename the current window to add `-1` if it doesn't already have a numeric suffix, so both sessions are clearly numbered

### Step 3: Write the Continuation Prompt

Write a detailed continuation prompt to `/tmp/handoff_prompt_<timestamp>.txt`. The prompt must be self-contained — the new session has zero prior context. Structure:

```
Continue the following work in <working_directory>.

## Session
This is a continuation of a previous session. The previous session was <session_name> and this is <new_session_name>.

## Plan
<full plan if one exists, otherwise omit this section>

## Progress
### Completed
<list of completed tasks/work with brief descriptions>

### In Progress
<any task that was in progress when handoff occurred>

### Remaining
<list of remaining tasks/work>

## Key Context
<decisions made, constraints discovered, user preferences, gotchas — anything non-obvious>

## Git State
Branch: <branch>
Status: <clean/dirty, uncommitted changes if any>

## Active Files
<list of files currently being worked on>

## Instructions
Pick up from where the previous session left off. Start with the next incomplete task.
```

### Step 4: Open the New Pane and Launch

Use the tmux skill's script (co-located in this plugin) to execute the handoff:

1. **Split side-by-side** (tmux `horizontal` = vertical split line):
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py" split horizontal -c <working_directory>
   ```

2. **Send the prompt** to the new pane using file mode with command prefix:
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py" send \
     -f /tmp/handoff_prompt_<timestamp>.txt \
     -p "claude --dangerously-skip-permissions --" \
     -t <new_pane_id>
   ```

3. **Rename the current window** if it doesn't already have a numeric suffix — append `-1`.

4. **Confirm** to the user that the handoff is complete, showing the new session name and a brief summary of what was handed off.

### Step 5: Clean Exit

After confirming the handoff, inform the user that they can close this pane when ready. Do not close it automatically — the user may want to reference the conversation history.
