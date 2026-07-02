---
name: illbeback
description: User-invoked (/illbeback). Tell the controller the context window is running high — find a clean point to compact, write full recovery state to the controller log file, then ask the user to run /compact. Pairs with /imback for the post-compaction resume.
disable-model-invocation: true
---

# I'll be back

We have consumed a high percentage of the context window. Prepare to compact — safely, at the right moment.

## 1. Find a good time to compact

Do **not** compact mid-flight. Wait for a clean boundary, per the controller skill's compaction handshake: every supervised worker idle **and** committed (no uncommitted work that compaction would strand), and no half-finished gate or cross-window merge in progress. If something is in flight, get it to a clean stop first — have the worker commit a checkpoint and hold — before continuing.

## 2. Write your recovery status to the controller log file

The file is `$CTL_DIR/CONTROLLER-STATE.md`. Recompute `$CTL_DIR` from your own tmux window id — it is stable across your `/compact` and relaunch, so the post-compaction you derives the same path:

```bash
CTL_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/controller-msgs/$(tmux display-message -p '#{window_id}' | tr -d '@')"
mkdir -p "$CTL_DIR"
```

Capture everything the controller skill's **"Pre-compaction state log"** section lists — enough to resume with **zero** conversational memory:

- **Git / branch / merge state** — current branch + commit, what's been merged this session, uncommitted/working-tree changes, push state.
- **Each in-flight worker** — its window id (`@N`), branch/worktree, task, the file PATHS to its plan/report scratch files, and the invariant it must preserve.
- **Queued / next work**, with any merge-ordering or file-contention notes.
- **Open decisions that are the user's to make** — surfaced, not baked.
- **Key invariants / conventions in play** — e.g. an oracle value, the canonical test command.

## 3. Ask me to run `/compact`

Do **not** run it yourself — the human runs the compact command. Tell me you've written the state log and are ready to compact.

After compaction I'll use **/imback** to point you back at the state file and tell you what to do next.
