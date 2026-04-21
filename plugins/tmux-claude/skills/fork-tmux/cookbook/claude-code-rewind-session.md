# Fork and Rewind Session into a New tmux Window

Fork the current Claude session into a new tmux window, rewinding to a previous point in the conversation. The forked session gets the full conversation history but is instructed to disregard everything after the rewind point.

## How Rewind Works

There is no native `--rewind` CLI flag. Rewind is achieved by combining `--continue --fork-session` with a structured prompt that tells the forked Claude where to cut off context. The forked session sees the full conversation but follows the instruction to treat it as if it ended at the described point.

## Critical: Correct CLI Syntax

**CORRECT:**
```bash
claude --continue --fork-session -- 'REWIND: Go back to the point where <description>. Disregard everything in the conversation after that point. Then: <task>'
```

**INCORRECT:**
```bash
claude --continue -- 'rewind...'               # Missing --fork-session, modifies parent session
claude --fork-session -- 'rewind...'            # Missing --continue, starts fresh with no context
```

## Instructions

1. Extract from the user's request:
   - **Rewind target**: Where in the conversation to rewind to. The user may specify it as:
     - **Quoted message** (most precise): The user quotes text from a previous message. Determine whether the quoted text is from a **user message** or an **assistant message** — this affects the prompt wording.
     - A topic: "go back to when we were discussing the plan"
     - A milestone: "before we started the refactor"
     - A decision point: "before I asked you to change the approach"
     - A relative point: "undo the last 3 exchanges"
   - **Task** (optional): What the forked session should do from that point. If no task is given, the forked session should acknowledge the rewind point and wait for user input interactively.
2. Check if user requested skip-permissions mode.
3. Derive a slug (see **Naming** below) — auto-generate unless the user specified one. The same slug is used for both the tmux window and the Claude session.
4. Construct the claude command with `--continue --fork-session --name <slug>` and a REWIND prompt. Use the **quote-based** or **description-based** prompt structure depending on what the user provided. If no task was given, use the **open-ended** variant.
5. Run the fork_tmux.py script with `--name <slug>` (tmux window) and the claude command.

## Naming

Every rewind fork must pass the same slug twice — once to `fork_tmux.py --name` (tmux window) and once to `claude --name` (Claude session, visible in the prompt box, `/resume` picker, and terminal title). Keeping them identical makes the two identifiers trivially correlatable.

**If the user specified a name** (phrases like "name it X", "call it X", "as 'X'", "named <X>"): use their value verbatim (lowercase + hyphenated, non-alphanumeric stripped), prefixed with `rewind-` only if they didn't include a prefix.

**Otherwise, auto-derive** from the *new task* (not the rewind anchor — the anchor is where we rewind FROM, the task is what we do AFTER):
1. Pick 2–3 content words from the start of the task, skipping stopwords (`a an the to and or of for in on at with you we`).
2. Lowercase, replace whitespace/punctuation with `-`, collapse repeats.
3. Prefix with `rewind-`.
4. Cap total length at ~30 chars.

For open-ended variants (no task), derive from 2–3 words of the rewind anchor instead, prefixed with `rewind-at-`.

Examples:
| User Request | Window name |
|---|---|
| "rewind to '...' and use integration tests instead" | `rewind-use-integration-tests` |
| "rewind session to before the refactor and try TDD" | `rewind-try-tdd` |
| "rewind to 'Here is the updated auth flow'" (no task) | `rewind-at-updated-orchestrator-flow` |
| "undo the last few changes and redo with a different strategy" | `rewind-redo-different-strategy` |

**Note on Claude session naming:** the Claude session title shown in `/resume` is auto-derived from the first user message. Since the REWIND prompt is the first message in the forked session, the title will already reflect the rewind intent — no extra flag needed.

## Prompt Structure

Choose the prompt variant based on two factors:
1. **Anchor type**: Does the user quote a specific message (user or assistant), or describe the point?
2. **Task**: Does the user specify a task, or do they want to land at that point and interact freely?

### Variant A: Quote-based anchor with task

Use when the user quotes a specific message AND provides a task. Determine whether the quoted text comes from a **user message** or an **assistant (Claude) message** and use the appropriate wording.

```
REWIND: Find the <user|assistant> message that says: "<exact quoted text>".
Disregard all conversation and work done after that message — treat it as if it never happened.
Do not reference, continue, or build on anything after that message.
From that point, do the following: <task>
```

### Variant B: Quote-based anchor, open-ended (no task)

Use when the user quotes a specific message but does NOT provide a task. The forked session rewinds to that point and waits for the user to interact. This is the "redo from here" pattern — the user wants to take the conversation in a different direction.

```
REWIND: Find the <user|assistant> message that says: "<exact quoted text>".
Disregard all conversation and work done after that message — treat it as if it never happened.
Do not reference, continue, or build on anything after that message.
Acknowledge the rewind point briefly, then wait for the user to provide their next instruction.
```

### Variant C: Description-based anchor with task

Use when the user describes the rewind point by topic, milestone, or relative position.

```
REWIND: Go back to the point where <rewind target description>.
Disregard all conversation and work done after that point — treat it as if it never happened.
Do not reference, continue, or build on anything after the rewind point.
From that point, do the following: <task>
```

### Variant D: Description-based anchor, open-ended (no task)

Use when the user describes the rewind point but does NOT provide a task.

```
REWIND: Go back to the point where <rewind target description>.
Disregard all conversation and work done after that point — treat it as if it never happened.
Do not reference, continue, or build on anything after the rewind point.
Acknowledge the rewind point briefly, then wait for the user to provide their next instruction.
```

### Determining message role (user vs assistant)

When the user quotes a message, determine who said it:
- **User message**: The user quotes their own words. Clues: "where I said", "my message", "when I asked", "where I told you"
- **Assistant message**: The user quotes Claude's words. Clues: "where you said", "your message", "your response", "when you suggested", or the quoted text is clearly Claude's output (code explanations, suggestions, summaries)
- **Ambiguous**: If unclear, default to searching for the text in any message: use `Find the message that says:` (omit user/assistant)

### Why this structure works

- **"Find the message that says"** — tells Claude to scan conversation history for the exact anchor string
- **"Disregard all conversation and work done after"** — prevents bleed-through from later context
- **"Do not reference, continue, or build on"** — reinforces the boundary
- **"From that point, do the following:"** — starts the new work cleanly (task variants)
- **"Acknowledge the rewind point briefly, then wait"** — creates an interactive landing point (open-ended variants)

**Prefer quote-based anchors** whenever the user quotes or references a specific message. They give the forked Claude an exact string to match against the conversation, eliminating ambiguity.

## Execution

```bash
# Quote-based with task (Variant A)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <slug> "claude --continue --fork-session --name <slug> -- 'REWIND: Find the <user|assistant> message that says: \"<exact quoted text>\". Disregard all conversation and work done after that message — treat it as if it never happened. Do not reference, continue, or build on anything after that message. From that point, do the following: <task>'"

# Quote-based open-ended (Variant B) — no task, interactive
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <slug> "claude --continue --fork-session --name <slug> -- 'REWIND: Find the <user|assistant> message that says: \"<exact quoted text>\". Disregard all conversation and work done after that message — treat it as if it never happened. Do not reference, continue, or build on anything after that message. Acknowledge the rewind point briefly, then wait for the user to provide their next instruction.'"

# Description-based with task (Variant C)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <slug> "claude --continue --fork-session --name <slug> -- 'REWIND: Go back to the point where <description>. Disregard all conversation and work done after that point — treat it as if it never happened. Do not reference, continue, or build on anything after the rewind point. From that point, do the following: <task>'"

# Description-based open-ended (Variant D) — no task, interactive
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <slug> "claude --continue --fork-session --name <slug> -- 'REWIND: Go back to the point where <description>. Disregard all conversation and work done after that point — treat it as if it never happened. Do not reference, continue, or build on anything after the rewind point. Acknowledge the rewind point briefly, then wait for the user to provide their next instruction.'"

# Skip permissions mode (any variant)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <slug> "claude --continue --fork-session --name <slug> --dangerously-skip-permissions -- 'REWIND: ...'"

# With custom working directory (any variant)
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --name <slug> --cwd /path/to/directory "claude --continue --fork-session --name <slug> -- 'REWIND: ...'"
```

## Examples

### Quote-based with task (Variant A)

| User Request | Role | Quoted Text | Fork Command |
|---|---|---|---|
| "rewind to where I said 'let's try the cache layer refactor' and use integration tests" | user | `let's try the cache layer refactor` | `...-- 'REWIND: Find the user message that says: "let'\''s try the cache layer refactor". ...From that point, do the following: Use integration tests instead of unit tests'` |
| "go back to my message 'add TDD tests' and skip the mocks this time" | user | `add TDD tests` | `...-- 'REWIND: Find the user message that says: "add TDD tests". ...From that point, do the following: Write the tests without mocks, hit the real database'` |

### Quote-based open-ended (Variant B) — "redo from here"

Use this when the user quotes a message but gives no task. The forked session lands at that point and waits for the user to type a new direction.

| User Request | Role | Quoted Text | Fork Command |
|---|---|---|---|
| "rewind to 'Here is the updated auth flow'" | assistant | `Here is the updated auth flow` | `...-- 'REWIND: Find the assistant message that says: "Here is the updated auth flow". ...Acknowledge the rewind point briefly, then wait for the user to provide their next instruction.'` |
| "fork and rewind to 'I suggest splitting this into two services'" | assistant | `I suggest splitting this into two services` | `...-- 'REWIND: Find the assistant message that says: "I suggest splitting this into two services". ...Acknowledge the rewind point briefly, then wait for the user to provide their next instruction.'` |
| "rewind to 'let's start with the schema layer'" | user | `let's start with the schema layer` | `...-- 'REWIND: Find the user message that says: "let'\''s start with the schema layer". ...Acknowledge the rewind point briefly, then wait for the user to provide their next instruction.'` |

### Description-based with task (Variant C)

| User Request | Rewind Target | Fork Command |
|---|---|---|
| "rewind session to before the refactor and try a different approach" | "we started the refactor" | `...-- 'REWIND: Go back to the point where we started the refactor. ...From that point, do the following: Try a different refactoring approach that preserves the existing API'` |
| "undo the last few changes and redo with TDD" | "before the last implementation changes" | `...-- 'REWIND: Go back to the point before the last implementation changes were made. ...From that point, do the following: Redo the implementation using TDD'` |

## Limitations

- **Prompt-based, not structural**: The rewind is an instruction, not a technical truncation of conversation history. The forked Claude can still "see" the post-rewind context in its history — it is instructed to ignore it. This works well in practice but is not a hard boundary.
- **File system state is current**: Even though the conversation rewinds, the file system reflects the current state. If post-rewind work modified files, those modifications are still present on disk. The forked Claude should be told to check file state or restore from git if needed.
- **Vague rewind targets may miss**: The more specific the user's description of the rewind point, the better. "Go back to before the refactor" is better than "go back a bit."

## Behavior

- **Parent session**: After launching the fork, stop working on the rewound task. The parent session is free to continue other work.
- **Forked session**: Opens in a new tmux window with the full conversation but behavioral context boundary at the rewind point. It will attempt to work as if the conversation ended at that point.
- **Git as safety net**: If the user's post-rewind work included file edits or commits, the forked session can use `git diff` or `git stash` to understand or undo those changes. Suggest this in the prompt when file state matters.
