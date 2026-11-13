#!/usr/bin/env bash
# Tests for the TMUX_AGENT_* environment garbage collector (scripts/env-gc.sh and
# the hooks registered by agent-indicator.tmux). Runs on a private tmux server
# (-L test-w5tmuxenv-$$) with no config; never touches the user's tmux server.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../.." && pwd)"
SOCKET="test-w5tmuxenv-$$"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/env-gc-test.XXXXXX")"
SEED="${SEED_COUNT:-7000}"
fails=0

# Never inherit the caller's tmux server: every tmux call below names the socket,
# and TMUX_TMPDIR points the *default* socket at the scratch dir too, so even a
# call that forgets -L / $TMUX can never reach the user's live server.
unset TMUX TMUX_PANE
export TMUX_TMPDIR="$SCRATCH/tmuxtmp"
mkdir -p "$TMUX_TMPDIR"

t() { tmux -L "$SOCKET" "$@"; }
cleanup() { t kill-server 2>/dev/null || true; rm -rf "$SCRATCH"; }
trap cleanup EXIT

assert() {  # assert <description> <command...>
    local desc="$1"; shift
    if "$@"; then echo "ok   - $desc"; else echo "FAIL - $desc"; fails=$((fails + 1)); fi
}
# ACTIVE_PANE_<agent> is deliberately never touched (it is a pointer, not per-pane
# state), so it is excluded from the leak count and asserted separately.
count() { t show-environment -g | grep '^TMUX_AGENT_' | grep -vc '^TMUX_AGENT_ACTIVE_PANE_' || true; }
count_dead_ids() { t show-environment -g | grep -cE '^TMUX_AGENT_(PANE_%|WINDOW_@)[0-9]+_' || true; }
has_var() { t show-environment -g "$1" >/dev/null 2>&1; }
# wait_for <description> <command...>: poll up to ~5s (hooks run in the background).
wait_for() {
    local desc="$1"; shift
    local i
    for i in $(seq 1 50); do
        if "$@"; then echo "ok   - $desc"; return 0; fi
        sleep 0.1
    done
    echo "FAIL - $desc"; fails=$((fails + 1)); return 1
}
eq_count() { [ "$(count)" -eq "$1" ]; }
gone() { ! has_var "$@"; }                       # none of the named vars exist
gone_all() { local v; for v in "$@"; do has_var "$v" && return 1; done; return 0; }
few_dead_ids() { [ "$(count_dead_ids)" -le "$1" ]; }

# Run the indicator's state script as the agent in <pane> would (hook context).
agent_state() {  # agent_state <pane> <state>
    local sock pid
    sock="$(t display-message -p '#{socket_path}')"; pid="$(t display-message -p '#{pid}')"
    TMUX="$sock,$pid,0" TMUX_PANE="$1" bash "$PLUGIN/scripts/agent-state.sh" --agent claude --state "$2"
}
indicator_out() {  # indicator output for the active pane of the first window
    local sock pid
    sock="$(t display-message -p '#{socket_path}')"; pid="$(t display-message -p '#{pid}')"
    TMUX="$sock,$pid,0" bash "$PLUGIN/scripts/indicator.sh"
}
# Mean wall-clock ms of `bash -c true` spawned by the server (inherits the global env).
bash_startup_ms() {
    local out="$SCRATCH/ms.$1"
    t run-shell "s=\$(date +%s%N); i=0; while [ \$i -lt 20 ]; do bash -c true; i=\$((i+1)); done; e=\$(date +%s%N); echo \$(( (e-s)/20000000 )) > $out"
    cat "$out"
}

# A new server copies the starting client's environment into its global
# environment. Start it from a scrubbed environment so TMUX_AGENT_* entries leaked
# from the caller's own (possibly bloated) tmux never pollute the baseline.
case "$SCRATCH" in "${TMPDIR:-/tmp}"/env-gc-test.*) ;; *) echo "bad scratch dir" >&2; exit 1 ;; esac
env -i PATH="$PATH" HOME="$SCRATCH" TMUX_TMPDIR="$TMUX_TMPDIR" TERM=screen LANG=C \
    tmux -L "$SOCKET" -f /dev/null new-session -d -s main -x 100 -y 30 "sleep 3600"
t set -g @agent-indicator-icons "claude=CLAUDE,default=DEFAULT"
t set -g remain-on-exit off

# Loading the plugin registers the hooks (and runs the startup sweep once).
t run-shell "$PLUGIN/agent-indicator.tmux"
sleep 0.5
assert "pane-exited hook registered"    grep -q "env-gc.sh pane" <<<"$(t show-hooks -g pane-exited)"
assert "after-kill-pane hook registered" grep -q "env-gc.sh sweep" <<<"$(t show-hooks -g after-kill-pane)"
assert "window-unlinked hook registered" grep -q "env-gc.sh window" <<<"$(t show-hooks -g window-unlinked)"
t run-shell "$PLUGIN/agent-indicator.tmux"
sleep 0.5
assert "reloading the plugin does not duplicate gc hooks" \
    test "$(for h in pane-exited after-kill-pane window-unlinked; do t show-hooks -g "$h"; done | grep -c 'env-gc.sh')" -eq 3

# --- indicator states still render for a live pane --------------------------
p0="$(t display-message -p -t main:0 '#{pane_id}')"
w0="$(t display-message -p -t main:0 '#{window_id}')"
for st in running needs-input done; do
    agent_state "$p0" "$st"
    assert "state $st recorded for live pane" \
        test "$(t show-environment -g "TMUX_AGENT_PANE_${p0}_STATE" | cut -d= -f2)" = "$st"
    assert "indicator renders for state $st" test "$(indicator_out)" = "CLAUDE"
done
# A needs-input window in the background gets the title/border styling.
t new-window -d -t main: "sleep 3600"
wbg="$(t list-windows -t main -F '#{window_id}' | tail -1)"
pbg="$(t list-panes -t "$wbg" -F '#{pane_id}')"
agent_state "$pbg" needs-input
assert "needs-input colours the background window title" \
    grep -q 'bg=yellow' <<<"$(t show-window-option -v -t "$wbg" window-status-style)"
assert "needs-input sets the border yellow" \
    grep -q 'yellow' <<<"$(t show-window-option -v -t "$wbg" pane-active-border-style)"
t kill-window -t "$wbg"
# Settle: drop the live pane's state too so the baseline is the bare plugin vars.
agent_state "$p0" off
wait_for "window and pane vars of the closed window are gone" \
    gone_all "TMUX_AGENT_PANE_${pbg}_STATE" "TMUX_AGENT_WINDOW_${wbg}_DONE" "TMUX_AGENT_WINDOW_${wbg}_ORIG_STATUS_STYLE"
base="$(count)"
echo "# baseline TMUX_AGENT_* count: $base"

# --- open/close cycle returns to baseline -----------------------------------
churn() {  # create state in a window with two panes, return their ids
    t new-window -d -t main: "sleep 3600"
    local w pa pb
    w="$(t list-windows -t main -F '#{window_id}' | tail -1)"
    t split-window -d -t "$w" "sleep 3600"
    pa="$(t list-panes -t "$w" -F '#{pane_id}' | sed -n 1p)"
    pb="$(t list-panes -t "$w" -F '#{pane_id}' | sed -n 2p)"
    agent_state "$pa" running
    agent_state "$pb" done          # done on a background window also sets WINDOW_* vars
    echo "$w $pa $pb"
}

read -r w pa pb <<<"$(churn)"
assert "state vars were created (count grew)" test "$(count)" -gt "$base"
assert "window vars were created" has_var "TMUX_AGENT_WINDOW_${w}_DONE"
t kill-pane -t "$pb"
wait_for "kill-pane removes that pane's vars" \
    gone_all "TMUX_AGENT_PANE_${pb}_STATE" "TMUX_AGENT_PANE_${pb}_DONE" "TMUX_AGENT_PANE_${pb}_AGENT"
assert "kill-pane leaves the sibling pane's vars alone" has_var "TMUX_AGENT_PANE_${pa}_STATE"
assert "kill-pane leaves the live window's vars alone" has_var "TMUX_AGENT_WINDOW_${w}_DONE"
t kill-window -t "$w"
wait_for "kill-window returns the count to baseline" eq_count "$base"
assert "no pane/window ids linger after kill-window" test "$(count_dead_ids)" -eq 0

# pane whose process exits on its own (pane-exited)
t new-window -d -t main: "sleep 2"
w="$(t list-windows -t main -F '#{window_id}' | tail -1)"; pa="$(t list-panes -t "$w" -F '#{pane_id}')"
t split-window -d -t "$w" "sleep 3600"      # keep the window alive after pa exits
agent_state "$pa" running
assert "pane vars created for the exiting pane" has_var "TMUX_AGENT_PANE_${pa}_STATE"
wait_for "natural pane exit removes its vars" gone_all "TMUX_AGENT_PANE_${pa}_STATE"
t kill-window -t "$w"
wait_for "count back at baseline after exit test" eq_count "$base"

# whole session killed
t new-session -d -s extra "sleep 3600"
pe="$(t list-panes -t extra -F '#{pane_id}')"; we="$(t list-windows -t extra -F '#{window_id}')"
agent_state "$pe" done
t kill-session -t extra
wait_for "kill-session returns the count to baseline" eq_count "$base"

# a window linked into two sessions keeps its vars when only one link goes
t new-session -d -s other "sleep 3600"
t new-window -d -t main: "sleep 3600"
wl="$(t list-windows -t main -F '#{window_id}' | tail -1)"; pl="$(t list-panes -t "$wl" -F '#{pane_id}')"
agent_state "$pl" running
t link-window -d -s "$wl" -t other:
t unlink-window -t "other:$(t list-windows -t other -F '#{window_index} #{window_id}' | awk -v w="$wl" '$2==w{print $1}')"
sleep 1
assert "unlinking one of two links keeps the live window's pane vars" has_var "TMUX_AGENT_PANE_${pl}_STATE"
t kill-window -t "$wl"; t kill-session -t other
wait_for "count back at baseline after link test" eq_count "$base"

# --- startup sweep with seeded stale vars -----------------------------------
t new-window -d -t main: "sleep 3600"
wlive="$(t list-windows -t main -F '#{window_id}' | tail -1)"; plive="$(t list-panes -t "$wlive" -F '#{pane_id}')"
agent_state "$plive" done
live_before="$(count)"
live_ids="$(count_dead_ids)"   # id-keyed vars that belong to live panes/windows
seedf="$SCRATCH/seed.conf"
{
    i=0
    while [ "$i" -lt "$SEED" ]; do
        id=$((5000 + i / 5))
        case $((i % 5)) in
            0) echo "set-environment -g TMUX_AGENT_PANE_%${id}_STATE done" ;;
            1) echo "set-environment -g TMUX_AGENT_PANE_%${id}_AGENT claude" ;;
            2) echo "set-environment -g TMUX_AGENT_PANE_%${id}_DONE_WINDOW @${id}" ;;
            3) echo "set-environment -g TMUX_AGENT_WINDOW_@${id}_ORIG_STATUS_STYLE bg=default,fg=default" ;;
            4) echo "set-environment -g TMUX_AGENT_WINDOW_@${id}_DONE 1" ;;
        esac
        i=$((i + 1))
    done
    # Variables the sweep must never touch.
    echo "set-environment -g TMUX_AGENT_SESSION_SEEN_ghost 1"
    echo "set-environment -g TMUX_AGENT_LAST_SESSION main"
    echo "set-environment -g TMUX_AGENT_ACTIVE_PANE_claude %9999"
    echo "set-environment -g TMUX_AGENT_ANIMATION_PID 1"
    echo "set-environment -g UNRELATED_VAR keepme"
} > "$seedf"
t source-file "$seedf"
seeded="$(count)"
assert "seeded $SEED stale vars" test "$((seeded - live_before))" -ge "$SEED"

ms_before="$(bash_startup_ms before)"
sweep_start="$(date +%s%N)"
TMUX="$(t display-message -p '#{socket_path},#{pid},0')" bash "$PLUGIN/scripts/env-gc.sh" sweep
sweep_ms=$(( ($(date +%s%N) - sweep_start) / 1000000 ))
echo "# sweep of ~$SEED stale vars took ${sweep_ms} ms"
assert "sweep took well under a second" test "$sweep_ms" -lt 1000
stale_left="$(t show-environment -g | grep -E '^TMUX_AGENT_(PANE|WINDOW)_[%@][0-9]+_' | grep -cvE "^TMUX_AGENT_(PANE_${plive}|WINDOW_${wlive})_" || true)"
assert "sweep removed every dead pane/window var" test "$stale_left" -eq 0
assert "live pane vars survive the sweep" has_var "TMUX_AGENT_PANE_${plive}_STATE"
assert "live window vars survive the sweep" has_var "TMUX_AGENT_WINDOW_${wlive}_DONE"
assert "SESSION_SEEN survives"   has_var TMUX_AGENT_SESSION_SEEN_ghost
assert "LAST_SESSION survives"   has_var TMUX_AGENT_LAST_SESSION
assert "ACTIVE_PANE survives"    has_var TMUX_AGENT_ACTIVE_PANE_claude
assert "ANIMATION_PID survives"  has_var TMUX_AGENT_ANIMATION_PID
assert "INDICATOR_DIR survives"  has_var TMUX_AGENT_INDICATOR_DIR
assert "non-agent vars survive"  has_var UNRELATED_VAR
ms_after="$(bash_startup_ms after)"
echo "# bash -c true startup inside the server: before=${ms_before} ms after=${ms_after} ms"
assert "bash startup is faster after the sweep" test "$((ms_after * 2))" -lt "$ms_before"

# Startup sweep fires on plugin load too (server restart / crash recovery).
t source-file "$seedf"
assert "re-seeded stale vars" test "$(count_dead_ids)" -gt 1000
t run-shell "$PLUGIN/agent-indicator.tmux"
wait_for "plugin load sweeps stale vars in the background" few_dead_ids "$live_ids"
assert "live vars still present after the load sweep" has_var "TMUX_AGENT_PANE_${plive}_STATE"

# Indicator still renders for live panes after all of the above.
t select-window -t "$wlive"
agent_state "$plive" running
assert "indicator still renders after sweeps" test "$(indicator_out)" = "CLAUDE"

# Bad arguments are rejected / ignored, never destructive.
before_bad="$(count)"
TMUX="$(t display-message -p '#{socket_path},#{pid},0')" bash "$PLUGIN/scripts/env-gc.sh" pane '' || true
TMUX="$(t display-message -p '#{socket_path},#{pid},0')" bash "$PLUGIN/scripts/env-gc.sh" pane 'x;y' || true
assert "malformed ids change nothing" test "$(count)" -eq "$before_bad"

# Without $TMUX the script must not guess a server (it would hit the default one).
t source-file "$seedf"
before_notmux="$(count)"
assert "no \$TMUX: exits 0" bash "$PLUGIN/scripts/env-gc.sh" sweep
assert "no \$TMUX: leaves every var alone" test "$(count)" -eq "$before_notmux"

if [ "$fails" -eq 0 ]; then echo "All tests passed."; exit 0; fi
echo "$fails test(s) failed."; exit 1
