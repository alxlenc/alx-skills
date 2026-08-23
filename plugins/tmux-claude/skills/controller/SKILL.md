---
name: controller
description: Act as a controller (babysitter) window that supervises one or more OTHER Claude Code windows running in tmux — watching them for idle/questions/high-context, answering their questions with the best option, picking the highest-impact follow-up, managing their context with timely /compact, coordinating cross-window git merges, and surfacing genuinely-user decisions while flagging anything dangerous. This skill should be used when the user asks to "babysit", "supervise", "monitor", "coordinate", or "be the controller for" other tmux Claude windows, or to keep autonomous Claude windows productive and unblocked. Pairs with the `tmux` skill (pane/window primitives), `fork-tmux`/`window-new` (spawn the windows), and `handoff` (continue a long session). Requires an active tmux session ($TMUX).
---

# Controller

Supervise one or more **other Claude Code windows** running in tmux. The controller does not do the worker windows' tasks — it keeps them unblocked, productive, and safe: it watches each window for the moment it needs attention, answers its questions, chooses its next high-impact step, compacts it before it runs out of context, coordinates merges between windows, and escalates only the calls that are genuinely the user's.

This is the programmatic counterpart to the plugin's `tmux-agent-indicator` dotfile (which colours a window's border when it flips `running → needs-input → done`): the watcher reads that same transition from the pane text and wakes the controller on it.

## Vocabulary

- **Worker** = a **YOLO tmux window**: a separate Claude Code (or codex) instance launched with `claude --dangerously-skip-permissions` (or `codex --dangerously-bypass-approvals-and-sandbox`) in its own tmux window, addressed by **window id `@N`**. It is a real window the user can see and drive. A worker is **NOT** an ephemeral `Agent`/sub-agent tool call. When the user says "use a worker" / "drive this from a worker," they mean *spawn a tmux window*, not a hidden sub-agent.
- **The controller does not do the work.** Its job is dispatch → gate → merge → compact. For any substantive implementation or investigation, spawn a worker and supervise it; don't code/investigate inline, and don't bury that work in sub-agents (which are invisible to the user and return straight into the controller's context — that reads as the controller doing the work itself).
- **Fast `↯` vs effort `◉` — don't conflate them.** The `↯` lightning glyph in a window's status divider = **FAST mode** (the `/fast` toggle). The `◉ xhigh · /effort` indicator = **reasoning effort**. They're orthogonal. Fresh `claude` launches default **non-fast** (verified by A/B test); fast only appears via an in-session `/fast` toggle. So the controller normally needs to do nothing — but as a cheap habit, glance for `↯` after launch and `/fast off` if it's there.

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

### Scratch directory — namespace it per controller

Every scratch file below (messages to workers, harvested reports, the state log) lives in a **per-controller** directory so two controllers on one machine never clobber each other's files. Derive it **once**, at the start of the loop, with the plugin's shared resolver — it keys the directory on the controller window's **name**:

```bash
CTL_DIR="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/ctl_dir.sh")"   # e.g. ~/.local/state/controller-msgs/tax-service-controller
```

The resolver does three things. If the window was never explicitly named, it **renames it first** — deterministic default `<cwd-basename>-controller`, with `-2`/`-3` appended if another window in the session holds that name; you may pick a more descriptive kebab-case name yourself with `tmux rename-window` before running it, but the window **must** end up explicitly named before `$CTL_DIR` is derived. It then keys the dir on the sanitized name (lowercase `[a-z0-9-]`, everything else collapsed to `-`). And it migrates a pre-0.9.0 numeric-id dir for this window into the name-keyed path, one time.

Why the name and not the window id: ids (`@N`) are reassigned when the tmux server restarts (e.g. a reboot), which orphans an id-keyed state dir; the name is stable across the controller's own `/compact`/claude relaunch **and** across server restarts — a controller relaunched in a same-named window recomputes the same `$CTL_DIR` and still finds its `CONTROLLER-STATE.md`. The XDG state dir also survives reboots, unlike `/tmp`. Caveat: window names are **not unique across tmux sessions** — the supported shape is a single user in a single session, one controller per name. Use `$CTL_DIR/...` for every scratch path from here on.

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

**`IDLE` means "looks stopped," not "is done."** High-effort (e.g. `xhigh`) workers pause between thinking phases and can **false-fire IDLE** even though they're still working. Never treat IDLE as proof of completion — ground-truth done-ness before acting on it: a commit on the worker's branch (`git -C <worktree> log <base>..HEAD`), a clean tree (`git status --porcelain`), a written report file, or a rising OUTPUT-token counter / `N new messages ↓` (= still working). If a worker keeps false-firing, **re-arm the watcher more tolerantly** (`IDLE_CONFIRM=5 POLL_SECS=10 bash …/watch_windows.sh @N`).

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
python3 "$PANES" send -f $CTL_DIR/msg.txt -t @50     # type the message
python3 "$PANES" send "" -t @50                      # press Enter to submit
sleep 3; python3 "$PANES" read -t @50 -S -6          # verify it submitted
```

Sending while a window is **busy** queues the message (it runs after the current turn) — fine for handing a worker its next instruction early.

### Harvesting a worker's long report

A worker's final report often renders **below the TUI viewport**: `read` shows only the scrolled-up top, and a `N new messages ↓` indicator appears. Don't fight the scroll. Ask the worker to **write its full report to a scratch file**, then `Read` that file:

```bash
python3 "$PANES" send -f $CTL_DIR/harvest.txt -t @50   # "Write your full report to $CTL_DIR/report-50.txt"
python3 "$PANES" send "" -t @50
# …then read the file directly, not the pane.
```

This is the same trick in reverse from the file-mode send: files sidestep both shell quoting *and* the viewport. Keep per-window scratch files under `$CTL_DIR` (e.g. `$CTL_DIR/to-<id>-*.txt`) — clean and auditable.

### Answering a worker's question (selectors)

When a window shows an interactive selector (numbered options, a y/n box, an AskUserQuestion), the most reliable move is **not** to drive the keys. Press `Escape` to cancel the selector (Claude treats it as "answered via free text"), then send a normal free-text message stating the choice and the reasoning:

```bash
python3 "$PANES" send "Escape" -t @53 --no-enter
python3 "$PANES" send "C-u" -t @53 --no-enter
python3 "$PANES" send -f $CTL_DIR/answer.txt -t @53
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

### Pre-compaction state log — the controller compacts itself

The handshake above pre-empts a *worker* running out of context. The controller has the same problem, but worse: compaction summarizes and blurs exactly the conversational context the controller runs on — the live orchestration state. Before the controller compacts (or recommends the user compact it) at high context, **write a durable pre-compaction state log first.** An external file preserves the in-flight orchestration precisely so the post-compaction controller resumes without loss.

Write it to a durable scratch file — `$CTL_DIR/CONTROLLER-STATE.md` — capturing:

- **Git / branch / merge state** — current branch + commit, what's been merged this session, uncommitted/working-tree changes, push state.
- **Each in-flight worker** — its window id (`@N`), branch/worktree, task, the file PATHS to its plan/report scratch files, and the invariant it must preserve — so a half-finished gate can be resumed.
- **Queued / next work**, with any merge-ordering or file-contention notes.
- **Open decisions that are the user's to make** — surface them, don't bake them.
- **Key invariants / conventions in play** — e.g. a project's oracle value, the canonical test command.

This is compaction-safe by design: the watcher stays armed across compaction and re-invokes the controller when a worker next needs attention; worker reports persist in their scratch files; durable memory holds the cross-session facts. **The post-compaction controller's first move is to read the state log.**

## Coordinating a cross-window git merge

When one window finishes work on a branch/worktree that another window owns the main checkout of:

1. **Wait for a clean boundary** — the owning window idle with a clean tree, between phases.
2. **Gate the branch before merging** (the controller's job — workers don't self-merge):
   - Scan the **commit message** for AI attribution and reject it (`co-authored`, `claude`, `codex`, `anthropic`, `openai`, `gpt`, `generated-with`, `🤖`).
   - Confirm the **footprint is in-scope and disjoint** — `git diff --name-only main...<branch>` shouldn't overstep the brief or overlap another window's working files. (A worker reaching "linter clean" can do so by *deleting* a note and its references — diff to catch scope-creep, not just to check for conflicts.)
   - Scan **added diff lines** for sensitive/personal data — `git diff main...<branch> | grep '^+'`. Workers copy real values into "synthetic" fixtures; catch it here.
   - Run linters + the **full test suite**, and the **ground-truth/oracle check** read-only (delta 0, or a consciously-accepted change).
3. **One writer per worktree.** Have the window that owns the main checkout run the merge (`git merge --no-ff <branch>`); don't reach into its working directory from the controller.
4. **Verify after** — the merge auto-commit can bypass pre-commit, so re-run the full suite + any promoted-to-error linters + the oracle on the merged tree; confirm the owning window's own work survived. STOP on any conflict or hook failure.
5. **Local only** unless the user asks — no push/pull. Then clean up the worktree (`cd` to the **main repo first**, then `git worktree remove <path>` — removing it while CWD is inside breaks every later command).

## Field-tested tricks

### Launching a worker

```bash
git worktree add -b <branch> <worktree-path> <base>          # isolate the worker
WID=$(tmux new-window -d -n <name> -c <worktree-path> -P -F '#{window_id}')   # capture @N
# launch the YOLO command in that window:
python3 "$PANES" send 'claude --dangerously-skip-permissions' -t "$WID"
# first run shows "Do you trust the files in this folder?" — Enter on "Yes, I trust"
python3 "$PANES" send "" -t "$WID"
# then brief it: clear ghost → send the file → Enter → read back to confirm the spinner started
python3 "$PANES" send "C-u" -t "$WID" --no-enter
python3 "$PANES" send -f $CTL_DIR/to-<name>.txt -t "$WID"
python3 "$PANES" send "" -t "$WID"
```

### Self-contained briefs — workers share NO context

Every brief is standalone (a compacted or fresh worker has no memory of prior turns; codex has no memory at all). Write the brief to a scratch file and send it with `send -f`. A good brief carries, inline:

- **Role:** "You are a WORKER reporting to a controller; your final message IS the report" (and "write your full report to `<path>` when done").
- **The task**, with **precise `file:line` pointers**.
- **Constraints:** behaviour-preserving; a ground-truth/oracle check + how to run it read-only; synthetic test data only (no real personal data); commit to the branch; no push; no AI-attribution in the commit message.
- **Explicit STOP-and-report conditions** for the risky/design parts — and forbid destructive/value-judgment actions (deletions, "consolidations") outside the named change. Open-ended phrasing invites overreach.

### codex vs claude workers

- **codex** for well-scoped coding — prefer it over a claude worker for pure-backend tasks, and launch it with the model from the plugin's `codex_model` user config (`codex -m <model> --yolo -- '…'`; omit `-m` when that config is blank). No memory → briefs must be fully self-contained. Its composer often **won't submit a long multi-line paste** (it inserts newlines) — so write the brief to a file and send a **short single-line** pointer: "Read `<path>` in full and execute it, honoring every constraint." (`Ctrl+C` clears a stuck composer without quitting codex.)
- **claude** for judgment, investigation, and ambiguous work.

### Verify empirically, don't assert

When any source — including a sub-agent or a docs lookup — claims a config knob or fact, **test it with an A/B control** before relying on it. Never present an unverified claim as a guarantee. (Example: a proposed "disable fast mode" setting turned out unverifiable and unnecessary once an A/B test showed fresh launches default non-fast.)

### Nudge through transient errors

If a worker stalls on a **transient API error** (e.g. `529 Overloaded`) and its turn ends, that's not a real stop — nudge it to resume from where it left off ("Resume the task from where you left off after the transient 529"). Distinguish this from a genuine clean stop before handing it a *new* directive.

## Notes

- The controller's messages arrive at a worker as ordinary user input. Be explicit that you are the controller so the worker frames its replies for you.
- Keep small per-window scratch files for the messages you send (under the per-controller `$CTL_DIR`) — it makes the file-mode sends above clean and auditable.
- **Two-writer rule.** If the user starts driving a worker window directly, step back from it to avoid collisions — **offer**, don't reach in; keep supervising the others and stay on call. Likewise never run two workers against the same working tree (give each its own worktree).
- **`pkill -f` self-match footgun.** If the controller restarts a service, never `pkill -f "<pattern>"` when the controller's own command line contains `<pattern>` — `-f` matches full command lines, so it SIGKILLs the controller's own shell mid-command and the relaunch never runs. Kill by exact PID (`ss -ltnp` → `kill <pid>`) or a bracket-trick (`pgrep -af '[u]vicorn'`); verify the port is free with `ss`/`curl` before and after.
- **Stay the controller.** Don't commission new analysis rounds while the previous round's remediation is unfinished — finish executing first. The controller's energy goes to dispatch, gating/merging, the compaction handshake, and worker context-health.
