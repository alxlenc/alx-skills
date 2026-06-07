#!/usr/bin/env bash
# watch_windows.sh — the controller's attention watcher.
#
# Polls one or more tmux windows and EXITS (printing a single ATTENTION line)
# the moment any of them needs the controller. Designed to run backgrounded so
# the harness re-invokes the controller when it exits — one wake-up per event.
#
# Usage:   watch_windows.sh @50 @53 ...      # window ids (@N), one or more
#
# Env overrides:
#   CTX_THRESHOLD  high-context %, fires only at a clean stop   (default 38)
#   POLL_SECS      seconds between sweeps                        (default 6)
#   IDLE_CONFIRM   consecutive non-busy reads before IDLE fires (default 3)
#   TMUX_PANES_PY  explicit path to the plugin's tmux_panes.py
#
# Output (one line, then exit 0):
#   ATTENTION <window-name> (<@id>): IDLE | IDLE_HIGH:<pct> | QUESTION | GONE
#
# Why the ordering matters: BUSY (which includes "Compacting") is checked
# BEFORE the context %, so a working — or mid-compaction — window whose status
# line still shows a stale high % never trips HIGH. High-context only fires at a
# clean stop, the only moment a /compact can land cleanly. IDLE is confirmed
# across IDLE_CONFIRM sweeps so a spinner caught between frames isn't mistaken
# for a finished turn (false-IDLE just costs a re-check; false-BUSY would strand
# a stalled window, so BUSY detection stays specific).

set -u

if [ -n "${TMUX_PANES_PY:-}" ]; then
  PANES="$TMUX_PANES_PY"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PANES="$CLAUDE_PLUGIN_ROOT/scripts/tmux_panes.py"
else
  PANES="$(cd "$(dirname "$0")/../../.." && pwd)/scripts/tmux_panes.py"
fi
CTX_THRESHOLD="${CTX_THRESHOLD:-38}"
POLL_SECS="${POLL_SECS:-6}"
IDLE_CONFIRM="${IDLE_CONFIRM:-3}"

[ "$#" -ge 1 ] || { echo "usage: watch_windows.sh @ID [@ID ...]" >&2; exit 64; }

wname() { tmux display-message -p -t "$1" '#{window_name}' 2>/dev/null || echo "$1"; }

# Echoes one of: GONE | BUSY | QUESTION | IDLE_HIGH:<pct> | IDLE
classify() {
  local w="$1" txt pct
  txt=$(python3 "$PANES" read -t "$w" 2>/dev/null | tail -n 30)
  [ -z "$txt" ] && { echo GONE; return; }
  # 1) BUSY first — match ONLY unambiguous live-spinner signals: the interrupt
  #    hint, compaction, the spinner's "↓ <n> tokens" / "↑ <n> tokens" counter
  #    (a leading space + literal "tokens" distinguishes it from the idle status
  #    line's "[↓0k ↑0k]" totals), OR the active spinner's ellipsis-anchored elapsed
  #    "… (Ns)" / "… (Nm Ns)". The token counter is INTERMITTENT (absent early in a
  #    think phase), which stranded a thinking window as false-IDLE; the "… (Ns)" is
  #    present every frame the spinner runs. The ellipsis anchor is what keeps it
  #    safe: a FINISHED line reads "<Verb> for Xm Ys" (no parens) and the idle status
  #    elapsed lives inside "[…⏱4h7m]" brackets — neither has "… (". Deliberately
  #    still NOT a BARE "(Xs)" paren or the "ctrl+o to expand" collapsed-block hint:
  #    those linger on a finished screen and would re-introduce a false-BUSY strand.
  if printf '%s\n' "$txt" | grep -qE 'esc to interrupt|Compacting|[↓↑] [0-9][0-9.,kKmM]* tokens|…[ ]?\([0-9]+[ms]'; then
    echo BUSY; return
  fi
  # 2) A pending interactive question (numbered selector / y-n / AskUserQuestion).
  if printf '%s\n' "$txt" | grep -qE '❯ 1\.|Do you want|│ ❯|Choose an option|\(y/n\)|esc to skip|↑/↓ to navigate'; then
    echo QUESTION; return
  fi
  # 3) Idle — distinguish high-context (ready to compact) from normal idle.
  pct=$(printf '%s\n' "$txt" | grep -oE '\[[0-9]+\.[0-9]+%\]' | tail -1 | tr -dc '0-9.')
  if [ -n "$pct" ] && awk "BEGIN{exit !($pct>=$CTX_THRESHOLD)}"; then echo "IDLE_HIGH:$pct"; return; fi
  echo IDLE
}

declare -A streak
for w in "$@"; do streak["$w"]=0; done

while true; do
  for w in "$@"; do
    s=$(classify "$w")
    case "$s" in
      GONE)
        echo "ATTENTION $(wname "$w") ($w): GONE"; exit 0 ;;
      QUESTION)
        sleep 4
        [ "$(classify "$w")" = QUESTION ] && { echo "ATTENTION $(wname "$w") ($w): QUESTION"; exit 0; } ;;
      BUSY)
        streak["$w"]=0 ;;
      IDLE|IDLE_HIGH:*)
        streak["$w"]=$(( ${streak["$w"]} + 1 ))
        if [ "${streak["$w"]}" -ge "$IDLE_CONFIRM" ]; then
          echo "ATTENTION $(wname "$w") ($w): $s"; exit 0
        fi ;;
    esac
  done
  sleep "$POLL_SECS"
done
