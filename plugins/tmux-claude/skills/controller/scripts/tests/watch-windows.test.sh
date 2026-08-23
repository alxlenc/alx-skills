#!/usr/bin/env bash
# Tests for watch_windows.sh — dependency-free, no tmux server needed.
#
# The watcher reads panes through the script named by TMUX_PANES_PY, so a stub
# that prints canned pane text exercises the REAL classifier end to end rather
# than a copy of it. `wname` shells out to tmux and falls back to the window id
# when that fails, so no tmux is required either.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH="$HERE/../watch_windows.sh"
WORK="$(mktemp -d)"
fails=0
trap 'rm -rf "$WORK"' EXIT

# Stub standing in for tmux_panes.py: prints whatever fixture is pointed at.
cat > "$WORK/panes_stub.py" <<'STUB'
import os, sys
sys.stdout.write(open(os.environ["FIXTURE"]).read())
STUB

# One line of realistic status bar. The watcher reads the LAST 30 lines, so the
# fixture only needs the parts the classifier actually greps for.
fixture() {  # fixture <model-label> <pct>
    printf '%s\n' \
      "● Done." \
      "" \
      "❯ " \
      "  ➜ repo git:(main) [$1] [$2%] [↓448k ↑0k] [5h:9%⏱1h48m]"
}

run_watch() {  # run_watch <fixture-file> [env...]  -> prints "(@9): <STATE>"
    # The window NAME is dropped deliberately. `wname` asks the live tmux server
    # for @9, which the stub only pretends exists, so the name it returns depends
    # on the environment the tests happen to run in. What is under test is the
    # CLASSIFICATION, so assert on that and let the name be whatever it is.
    env FIXTURE="$1" TMUX_PANES_PY="$WORK/panes_stub.py" \
        IDLE_CONFIRM=1 POLL_SECS=1 "${@:2}" \
        timeout 10 bash "$WATCH" @9 2>/dev/null | sed -n 's/.*\((@9): .*\)/\1/p'
}

assert_eq() {  # assert_eq <desc> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "ok   - $1"
    else
        echo "FAIL - $1"; echo "         expected: $2"; echo "         actual:   $3"
        fails=$((fails + 1))
    fi
}

# --- the regression this file exists for --------------------------------------
# A 1M-context window above 38% must report IDLE_HIGH. Before the fix the model
# was detected only as a literal "[1m]", so the current "(1M context)" spelling
# fell through to the 200K threshold of 75 and this returned a bare IDLE — a
# high-context window that never asks to be compacted, silently.
fixture "Opus 5 (1M context)" "45.0" > "$WORK/f_1m_high"
assert_eq "1M model at 45% fires IDLE_HIGH" \
    "(@9): IDLE_HIGH:45.0" "$(run_watch "$WORK/f_1m_high")"

# The older spelling must keep working — the fix adds a spelling, never replaces.
fixture "Sonnet 4.6 [1m]" "45.0" > "$WORK/f_1m_old"
assert_eq "legacy [1m] spelling still fires IDLE_HIGH" \
    "(@9): IDLE_HIGH:45.0" "$(run_watch "$WORK/f_1m_old")"

# --- the other side: the fix must not make the match too broad ----------------
# A standard ~200K model at the same 45% is NOT high — tripping here would mean
# compacting constantly, which is the reason the two thresholds exist at all.
fixture "Opus 5" "45.0" > "$WORK/f_std_mid"
assert_eq "standard model at 45% stays plain IDLE" \
    "(@9): IDLE" "$(run_watch "$WORK/f_std_mid")"

fixture "Opus 5" "80.0" > "$WORK/f_std_high"
assert_eq "standard model at 80% fires IDLE_HIGH" \
    "(@9): IDLE_HIGH:80.0" "$(run_watch "$WORK/f_std_high")"

fixture "Opus 5 (1M context)" "20.0" > "$WORK/f_1m_low"
assert_eq "1M model below threshold stays plain IDLE" \
    "(@9): IDLE" "$(run_watch "$WORK/f_1m_low")"

# --- explicit override still wins over model detection ------------------------
assert_eq "CTX_THRESHOLD overrides the per-model pick" \
    "(@9): IDLE_HIGH:20.0" "$(run_watch "$WORK/f_1m_low" CTX_THRESHOLD=10)"

# --- BUSY is checked before context, so a working window never trips HIGH -----
{ fixture "Opus 5 (1M context)" "45.0"; printf '%s\n' "✻ Working… (32s · esc to interrupt)"; } > "$WORK/f_busy"
assert_eq "a busy 1M window at 45% reports nothing (times out)" \
    "" "$(run_watch "$WORK/f_busy")"

echo
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails test(s) failed"; fi
exit "$fails"
