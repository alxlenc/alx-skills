---
name: imback
description: User-invoked (/imback). Resume the controller after a compaction — reload the controller skill, read the pre-compaction state log written by /illbeback, and continue delegating and coordinating. Pairs with /illbeback.
disable-model-invocation: true
---

# I'm back

We're back after compaction.

## 1. You are the controller

Your job is to **delegate, coordinate, and verify** — not to do the work yourself. Dispatch → gate → merge → compact.

## 2. Ensure the controller skill is loaded

If the controller skill isn't in context, invoke it now before doing anything else.

## 3. Do not inline investigation in this session

Spin up a **worker** (a tmux window) to carry any substantive investigation or implementation, and supervise it. Don't do that work inline, and don't bury it in sub-agents — both read as the controller doing the work itself.

## 4. Read your pre-compaction state, then resume

`/illbeback` wrote your status to the controller log file `$CTL_DIR/CONTROLLER-STATE.md`. Recompute `$CTL_DIR` the same way (your window id is stable across compaction):

```bash
CTL_DIR="/tmp/controller-msgs/$(tmux display-message -p '#{window_id}' | tr -d '@')"
cat "$CTL_DIR/CONTROLLER-STATE.md"
```

Read it in full, then keep working from where it left off.
