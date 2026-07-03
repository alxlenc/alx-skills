#!/usr/bin/env bash
# ctl_dir.sh — resolve the per-controller state directory, keyed on the
# controller window's NAME (not its numeric id).
#
# Window ids (@N) are reassigned when the tmux server restarts (e.g. a
# reboot), so an id-keyed dir orphans the controller's CONTROLLER-STATE.md.
# A window NAME survives any restart the user (or tmux-resurrect) recreates
# the window under — so the dir is keyed on the name, and a window that was
# never explicitly named gets renamed here first, deterministically.
#
# Usage:  CTL_DIR="$(bash "$CLAUDE_PLUGIN_ROOT/scripts/ctl_dir.sh")"
#         Run it from inside the controller's own tmux window.
#
# Every tmux call below targets $TMUX_PANE explicitly. This is load-bearing:
# an UNTARGETED `tmux display-message`/`show-options -w` resolves to the
# attached client's ACTIVE pane, not the calling pane (verified on tmux
# 3.5a) — so a controller running in a non-active window would otherwise
# read, rename, and migrate SOME OTHER window's identity and state.
#
# What it does, in order:
#   1. Unnamed detection: `tmux show-options -wqv automatic-rename` reads the
#      WINDOW-level option, which tmux sets to "off" only when the window is
#      explicitly named (new-window -n, rename-window, or a title escape
#      sequence). Anything else — empty (unset) or "on" — means "never
#      explicitly named". Why not a format probe: `#{automatic_rename}` is
#      not a tmux format variable (expands empty on tmux 3.5a), and the
#      option lookup `#{automatic-rename}` reads the EFFECTIVE value, so a
#      global `automatic-rename off` would make fresh windows read as named.
#      The window-level read has neither problem.
#   2. Auto-rename: an unnamed window is renamed to `<cwd-basename>-controller`
#      (sanitized), with -2/-3… appended while another window in the session
#      holds that name. The rename itself flips automatic-rename off, making
#      the name explicit from then on.
#   3. CTL_DIR = ${XDG_STATE_HOME:-$HOME/.local/state}/controller-msgs/<key>
#      where <key> is the window name sanitized to lowercase [a-z0-9-]
#      (runs of anything else collapse to '-', no leading/trailing '-').
#   4. One-time migration: if the name-keyed dir has no CONTROLLER-STATE.md
#      and the pre-0.9.0 numeric-id dir for THIS window exists, that whole
#      dir (state log + scratch message files) moves to the name-keyed path
#      — a single atomic rename when the target doesn't exist yet — with a
#      note on stderr.
#
# Prints the resolved directory (created) on stdout; notes go to stderr.
# Caveat: window names are not unique across tmux sessions — the supported
# shape is a single user in a single session, one controller per name.

set -eu

[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || { echo "ctl_dir.sh: not inside a tmux pane" >&2; exit 1; }

sanitize() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//'
}

wid="$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' | tr -d '@')"

# 1–2. Never explicitly named → rename it now, before deriving the dir.
if [ "$(tmux show-options -wqv -t "$TMUX_PANE" automatic-rename)" != "off" ]; then
  base="$(sanitize "$(basename "$PWD")")-controller"
  taken="$(tmux list-windows -t "$TMUX_PANE" -F '#{window_id} #{window_name}' | grep -v "^@${wid} " | sed 's/^@[0-9]* //')"
  name="$base" n=1
  while printf '%s\n' "$taken" | grep -Fxq "$name"; do
    n=$((n + 1)); name="$base-$n"
  done
  tmux rename-window -t "$TMUX_PANE" "$name"
  echo "ctl_dir.sh: renamed window @$wid to '$name'" >&2
fi

# 3. Key the dir on the sanitized window name.
key="$(sanitize "$(tmux display-message -t "$TMUX_PANE" -p '#{window_name}')")"
[ -n "$key" ] || key="window-$wid"   # name sanitized to nothing
root="${XDG_STATE_HOME:-$HOME/.local/state}/controller-msgs"
CTL_DIR="$root/$key"

# 4. One-time migration from the pre-0.9.0 numeric-id dir of this window.
id_dir="$root/$wid"
if [ ! -f "$CTL_DIR/CONTROLLER-STATE.md" ] && [ -d "$id_dir" ] && [ "$id_dir" != "$CTL_DIR" ]; then
  if [ ! -e "$CTL_DIR" ]; then
    mv "$id_dir" "$CTL_DIR"
  else
    find "$id_dir" -mindepth 1 -maxdepth 1 -exec mv -t "$CTL_DIR" {} +
    rmdir "$id_dir"
  fi
  echo "ctl_dir.sh: migrated $id_dir -> $CTL_DIR" >&2
fi

mkdir -p "$CTL_DIR"
printf '%s\n' "$CTL_DIR"
