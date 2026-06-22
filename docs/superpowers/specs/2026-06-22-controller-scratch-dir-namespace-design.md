# Controller scratch-dir namespacing — design

**Date:** 2026-06-22
**Plugin:** `tmux-claude` — bugfix release `0.7.1` → `0.7.2`
**Scope:** documentation/skill change to `controller/SKILL.md` + version bump.

## Problem

`plugins/tmux-claude/skills/controller/SKILL.md` instructs the controller to use a
single hardcoded scratch folder, `/tmp/controller-msgs/`, for the files it exchanges
with worker windows:

- `CONTROLLER-STATE.md` — the controller's durable pre-compaction state log (fixed name)
- `harvest.txt`, `answer.txt`, `to-<name>.txt` — per-message scratch files
- worker report files (e.g. `report-50.txt`)

If a user runs **more than one controller on the same machine**, both controllers
write the same paths and clobber each other. The most damaging collision is
`CONTROLLER-STATE.md`: two controllers overwrite each other's orchestration state,
so a post-compaction recovery reads the wrong controller's log.

## Fix

The controller derives a **per-instance scratch directory** once, at the top of the
control loop, keyed by its own tmux window id (with the `@` sigil stripped so the
folder name leads with the number):

```bash
CTL_DIR="/tmp/controller-msgs/$(tmux display-message -p '#{window_id}' | tr -d '@')"
mkdir -p "$CTL_DIR"      # e.g. /tmp/controller-msgs/7
```

Every scratch path in the skill is then expressed relative to `$CTL_DIR`:

```
$CTL_DIR/CONTROLLER-STATE.md
$CTL_DIR/to-<name>.txt
$CTL_DIR/harvest.txt
$CTL_DIR/answer.txt
$CTL_DIR/report-<worker-id>.txt
```

### Why the tmux window id

- **Unique per tmux server.** Window ids (`@N`) increment per server, so two live
  controllers on one machine never share one.
- **Stable across the controller's own `/compact` and claude relaunch.** The claude
  *process* may be restarted, but the tmux *window* it runs in keeps its id — so a
  recovering controller computes the same `$CTL_DIR` and still finds its
  `CONTROLLER-STATE.md`. A PID would change on relaunch and break this.
- **Leading number avoids ambiguity.** Worker ids appear mid/end of filenames
  (`to-renta.txt`, `report-50.txt`); making the controller's own id the leading path
  component keeps the two from being confused.

### Known limitation (accepted)

Window ids are unique per tmux **server**, not across multiple independent tmux
servers (separate sockets) on one machine — a rare setup. If that ever matters, the
key can be extended to include the session name. Out of scope for this bugfix.

## Changes

1. **`controller/SKILL.md`**
   - Add a short "Scratch directory" note near the top of the control loop that
     establishes `$CTL_DIR` (the snippet above) before any send/harvest.
   - Replace the four `/tmp/controller-msgs/...` references (harvest example, the
     scratch-dir tip, the `CONTROLLER-STATE.md` path, the launch-a-worker
     `to-<name>.txt` send) with `$CTL_DIR/...`.
   - Move the generic `/tmp/msg.txt` and `/tmp/answer.txt` examples under `$CTL_DIR`
     for consistency, and express worker report files as
     `$CTL_DIR/report-<worker-id>.txt`.

2. **`plugins/tmux-claude/.claude-plugin/plugin.json`** — `version`: `0.7.1` → `0.7.2`.

## Verification

Docs/skill-only change — no automated tests.

- Run the `CTL_DIR` snippet inside a tmux window and confirm it produces
  `/tmp/controller-msgs/<n>` and creates it.
- `grep -n '/tmp/controller-msgs' plugins/tmux-claude/skills/controller/SKILL.md`
  returns **only** the `$CTL_DIR` definition line — no surviving hardcoded scratch
  paths.
- Skill text is internally consistent: `$CTL_DIR` is defined and `mkdir -p`'d before
  its first use.

## Out of scope

- Multi-tmux-server uniqueness (see limitation above).
- Any change to `watch_windows.sh` — it does not touch the scratch folder.
- Automatic cleanup of stale `/tmp/controller-msgs/<n>` dirs.
