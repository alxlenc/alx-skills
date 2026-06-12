---
name: controller
description: Act as a controller (babysitter) window that supervises one or more OTHER Claude Code windows running in tmux — watching them for idle/questions/high-context, answering their questions with the best option, picking the highest-impact follow-up, managing their context with timely /compact, coordinating cross-window git merges, and surfacing genuinely-user decisions while flagging anything dangerous. This skill should be used when the user asks to "babysit", "supervise", "monitor", "coordinate", or "be the controller for" other tmux Claude windows, or to keep autonomous Claude windows productive and unblocked. Pairs with the `tmux` skill (pane/window primitives), `fork-tmux`/`window-new` (spawn the windows), and `handoff` (continue a long session). Requires an active tmux session ($TMUX).
---

# Controller

Supervise one or more **other Claude Code windows** running in tmux. The controller does not do the worker windows' tasks — it keeps them unblocked, productive, and safe: it watches each window for the moment it needs attention, answers its questions, chooses its next high-impact step, compacts it before it runs out of context, coordinates merges between windows, and escalates only the calls that are genuinely the user's.

This is the programmatic counterpart to the plugin's `tmux-agent-indicator` dotfile (which colours a window's border when it flips `running → needs-input → done`): the watcher reads that same transition from the pane text and wakes the controller on it.

## Requirements

- Must be running inside tmux (`$TMUX` set).
- Relies on the plugin's shared driver, `${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py` (the `tmux` skill), for `read` and `send`.
- Worker windows are addressed by tmux **window id** (`@N`) — stable across pane/index churn. Find them with `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py window-list`.

## The control loop

Run this loop per supervised window, indefinitely:

1. **Arm the watcher** (backgrounded) over the window ids. It exits — one notification — when any window needs attention.
2. On the notification, **read** the window that fired.
3. **Act** — answer a question, pick the next step, compact, coordinate a merge, or surface a decision (see the rubric below).
4. **Re-arm** the watcher and wait for the next event.

Never busy-poll from the foreground. The watcher is the only thing that should spin; the controller sleeps between events.

### Arm the watcher

```bash
# Backgrounded so the harness re-invokes the controller when it exits.
bash ${CLAUDE_PLUGIN_ROOT}/skills/controller/scripts/watch_windows.sh @50 @53
```

It prints one line and exits when a window needs attention:

```
ATTENTION renta-escritura (@50): IDLE          # at a clean stop — give it the next step
ATTENTION consultas-wiki  (@53): QUESTION      # waiting on a selector / y-n / AskUserQuestion
ATTENTION renta-escritura (@50): IDLE_HIGH:39  # idle AND ≥ threshold % — time to /compact
ATTENTION consultas-wiki  (@53): GONE          # window vanished / unreadable
```

`IDLE` is confirmed across several sweeps so a spinner caught mid-frame isn't read as a finished turn. `BUSY` (including `Compacting`) is checked before context %, so a working window — or one mid-compaction whose status line still shows a stale high % — never trips `IDLE_HIGH`; high-context only fires at a clean stop. The high-context threshold is **per-model**: the watcher reads the model name from the same status line and uses 38% for 1M-context models (literal `[1m]` in the model name) and 75% for standard ~200K models — 38% on a small window would trip compaction constantly. Tune with `CTX_THRESHOLD_1M` / `CTX_THRESHOLD_STD`, or set `CTX_THRESHOLD` to force one fixed % for all windows; also `POLL_SECS`, `IDLE_CONFIRM` (see the script header). To watch a single window, pass one id.

### Read a window

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py read -t @50 -S -50   # last ~50 scrollback lines
```

The status line carries the live signals the controller needs: `[28.0%]` context used, the model, and the spinner/elapsed timer when busy.

## Sending a message to a worker window — do it reliably

Typing into another Claude window from a script is fiddly. Follow this exact sequence or messages silently fail to submit:

1. **Clear any stray/ghost input first** — `send "C-u" --no-enter`. Claude Code shows faint **auto-suggestions** (history ghosts) that look identical to queued input but are not; `C-u` clears the line so the suggestion can't get concatenated with the message. (Diagnose a ghost by typing one character: if the line is replaced rather than appended-to, it was a ghost.)
2. **Send the message from a file** — `send -f /path/to/msg.txt -t @50`. File mode sidesteps all shell-quoting of special characters (`→`, `€`, quotes, parens).
3. **Submit with an explicit Enter** — `send "" -t @50`. A multi-line or long message lands as a bracketed-paste placeholder (`[Pasted text #1]`) that does **not** auto-submit; a separate empty send presses Enter. Read the pane back to confirm the spinner started.

```bash
PANES="${CLAUDE_PLUGIN_ROOT}/scripts/tmux_panes.py"
python3 "$PANES" send "C-u" -t @50 --no-enter        # clear ghost
python3 "$PANES" send -f /tmp/msg.txt -t @50         # type the message
python3 "$PANES" send "" -t @50                      # press Enter to submit
sleep 3; python3 "$PANES" read -t @50 -S -6          # verify it submitted
```

Sending while a window is **busy** queues the message (it runs after the current turn) — fine for handing a worker its next instruction early.

### Answering a worker's question (selectors)

When a window shows an interactive selector (numbered options, a y/n box, an AskUserQuestion), the most reliable move is **not** to drive the keys. Press `Escape` to cancel the selector (Claude treats it as "answered via free text"), then send a normal free-text message stating the choice and the reasoning:

```bash
python3 "$PANES" send "Escape" -t @53 --no-enter
python3 "$PANES" send "C-u" -t @53 --no-enter
python3 "$PANES" send -f /tmp/answer.txt -t @53
python3 "$PANES" send "" -t @53
```

For an already-highlighted single option a bare `Enter` also works, but free-text is more robust and lets the controller add rationale and adjacent guidance in one shot.

## Decision rubric — how to act

- **Answer questions with the recommended/best option.** Resolve them yourself; do not bounce a worker's routine question to the user.
- **Pick the highest-impact or must-be-first follow-up.** When a window offers several next steps, choose the one that unblocks the most or has to happen first (e.g. commit a checkpoint before a risky refactor; ship a clean increment before piling on more).
- **Dispatch with tight scope.** Give a worker a crisp objective, the constraints (TDD, don't touch the validated modules, no real data in git), and a STOP-and-report condition for the one risky part. Confirm the recommended decision *and* its rationale so the worker doesn't re-litigate it.
- **Use the cross-window vantage.** The controller can see what a single window cannot — e.g. that "merge now, it's conflict-free" is unsafe because another window holds that branch dirty. Apply that knowledge.
- **Surface — do not bake — genuinely-user calls.** Real-money decisions, anything needing real personal data the user must supply, or work the user explicitly owns: present it with a recommendation and let the user decide. Keep the worker holding (not guessing) meanwhile.
- **Flag danger, then stop.** If a window has derailed into something destructive, irreversible, or out of scope, tell it to stop and escalate to the user — do not let it proceed.

## Managing context — the compaction handshake

A worker that runs out of context mid-task loses its working state. Pre-empt it at a clean stop:

1. The watcher fires `IDLE_HIGH:<pct>` when a window is idle and at/above its model's threshold (38% for 1M-context models — just under the 40% line; 75% for standard ~200K models).
2. **Get it to a clean stop first** — if it has uncommitted work, instruct it to commit a checkpoint and hold. Compacting with uncommitted work strands files the post-compaction window won't "remember" writing.
3. Once committed and holding, **send `/compact`** (`send "/compact"` then verify `Compacting…` appears). Forewarn the window in the instruction so it's already prepared.
4. After compaction (context drops to ~0%), hand it the next directive — which must be **self-contained**, since its conversational context was just reset.

Sequence: **commit checkpoint → /compact → resume with a fresh, self-contained directive.** This also gives a risky refactor full context headroom.

## Coordinating a cross-window git merge

When one window finishes work on a branch/worktree that another window owns the main checkout of:

1. **Wait for a clean boundary** — the owning window idle with a clean tree, between phases.
2. **Verify the footprint is disjoint** — `git diff --name-only main...<branch>` must not overlap the other window's working files. Disjoint file-sets merge conflict-free regardless of how far the branches diverged.
3. **One writer per worktree.** Have the window that owns the main checkout run the merge (`git merge --no-ff <branch>`); don't reach into its working directory from the controller.
4. **Verify after** — the merge auto-commit can bypass pre-commit, so run the full suite + any promoted-to-error linters explicitly; confirm the owning window's own work survived. STOP on any conflict or hook failure.
5. **Local only** unless the user asks — no push/pull.

## Notes

- The controller's messages arrive at a worker as ordinary user input. Be explicit that you are the controller so the worker frames its replies for you.
- Keep small per-window scratch files for the messages you send (`/tmp` or a scratch dir) — it makes the file-mode sends above clean and auditable.
- If the user starts driving a worker window directly, step back from it to avoid two-writer collisions; keep supervising the others and stay on call.
