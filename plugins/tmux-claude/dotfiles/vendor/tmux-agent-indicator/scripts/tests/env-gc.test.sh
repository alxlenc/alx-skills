#!/usr/bin/env bash
# Tests for the TMUX_AGENT_* environment garbage collector (scripts/env-gc.sh and
# the hooks registered by agent-indicator.tmux). Runs on a private tmux server
# with a scratch HOME and guarded sockets under a scratch TMUX_TMPDIR.
set -eu

# Re-exec with a clean environment before running any plugin or tmux command.
# The outer process owns removal; the inner process owns its private server.
if [ "${1:-}" != --isolated ]; then
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/env-gc-test.XXXXXX")
    trap 'rm -rf "$scratch"' EXIT
    mkdir -p "$scratch/home" "$scratch/tmuxtmp" "$scratch/bin"
    env -i PATH="$PATH" HOME="$scratch/home" TMPDIR="$scratch" \
        GC_TEST_SCRATCH="$scratch" TERM=screen LANG=C SEED_COUNT="${SEED_COUNT:-7000}" \
        bash "$0" --isolated
    exit $?
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../.." && pwd)"
SOCKET="test-w5tmuxenv-$$"
SCRATCH="${GC_TEST_SCRATCH:?}"
[ "$HOME" = "$SCRATCH/home" ] && [ "$TMPDIR" = "$SCRATCH" ] || exit 1
SEED="${SEED_COUNT:-7000}"
fails=0

# Never inherit the caller's tmux server: every tmux call below names the socket,
# and TMUX_TMPDIR points the *default* socket at the scratch dir too, so even a
# call that forgets -L / $TMUX can never reach the user's live server.
unset TMUX TMUX_PANE
export TMUX_TMPDIR="$SCRATCH/tmuxtmp"
export GC_TEST_REAL_TMUX="$(command -v tmux)" GC_TEST_SOCKET_NAME="$SOCKET"
export GC_TEST_SOCKET_PATH="$TMUX_TMPDIR/tmux-$(id -u)/$SOCKET"

# This wrapper is inherited by the server and every plugin subprocess. Refuse
# fallback to the real default socket even if a test/script forgets its target,
# changes TMUX_TMPDIR or supplies an explicit socket outside this scratch tree.
cat > "$SCRATCH/bin/tmux" <<'WRAPPER'
#!/usr/bin/env bash
set -eu
deny() { echo 'test guard: refused non-private tmux target' >&2; exit 125; }
[ "${TMUX_TMPDIR:-}" = "$GC_TEST_SCRATCH/tmuxtmp" ] || deny
selected=0
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
    case "${args[i]}" in
        -L) i=$((i+1)); [ "${args[i]:-}" = "$GC_TEST_SOCKET_NAME" ] || deny; selected=1 ;;
        -S) i=$((i+1)); [ "${args[i]:-}" = "$GC_TEST_SOCKET_PATH" ] || deny; selected=1 ;;
        -L*|-S*) deny ;;
    esac
done
if [ -n "${TMUX:-}" ]; then
    [ "${TMUX%%,*}" = "$GC_TEST_SOCKET_PATH" ] || deny
elif [ "$selected" -eq 0 ]; then
    deny
fi
# Observe client-side GC scheduling, including on tmux versions that tolerate
# an untargeted run-shell before any sessions exist. Hooks execute in-server.
for arg in "$@"; do
    [ "$arg" = run-shell ] || continue
    case " $* " in
        *'env-gc.sh sweep'*) printf '%s\n' "$*" >> "$GC_TEST_SCRATCH/gc-run-shell.calls" ;;
    esac
done
exec "$GC_TEST_REAL_TMUX" "$@"
WRAPPER
chmod +x "$SCRATCH/bin/tmux"
export PATH="$SCRATCH/bin:$PATH"

t() { tmux -L "$SOCKET" "$@"; }
cleanup() { t kill-server 2>/dev/null || true; }
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
var_is() { [ "$(t show-environment -g "$1" 2>/dev/null)" = "$1=$2" ]; }
gc() { TMUX="$GC_TEST_SOCKET_PATH,$(t display-message -p '#{pid}'),0" bash "$PLUGIN/scripts/env-gc.sh" "$@"; }
refused() {
    local rc=0
    "$@" >"$SCRATCH/refused.out" 2>&1 || rc=$?
    [ "$rc" -eq 125 ] && grep -q '^test guard: refused' "$SCRATCH/refused.out"
}
assert "untargeted tmux cannot reach the account default server" refused tmux show-environment -g
assert "foreign inherited TMUX is refused before connecting" refused \
    env TMUX="/tmp/tmux-$(id -u)/default,1,0" tmux show-environment -g
assert "explicit foreign socket is refused before connecting" refused \
    tmux -S /tmp/env-gc-forbidden-socket show-environment -g
assert "changing TMUX_TMPDIR cannot escape isolation" refused \
    env TMUX_TMPDIR=/tmp tmux -L "$SOCKET" show-environment -g

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
t -f /dev/null new-session -d -s main -x 100 -y 30 "sleep 3600"
assert "server socket is inside scratch TMUX_TMPDIR" \
    test "$(t display-message -p '#{socket_path}')" = "$GC_TEST_SOCKET_PATH"
t set -g @agent-indicator-icons "claude=CLAUDE,default=DEFAULT"
t set -g remain-on-exit off

# Loading the plugin registers the hooks (and runs the startup sweep once).
t run-shell "$PLUGIN/agent-indicator.tmux"
sleep 0.5
assert "pane-exited hook registered"    grep -q "env-gc.sh pane" <<<"$(t show-hooks -g pane-exited)"
assert "after-kill-pane hook registered" grep -q "env-gc.sh sweep" <<<"$(t show-hooks -g after-kill-pane)"
assert "window-unlinked hook registered" grep -q "env-gc.sh window" <<<"$(t show-hooks -g window-unlinked)"
assert "session-created hook registered" grep -q "env-gc.sh sweep" <<<"$(t show-hooks -g session-created)"
t run-shell "$PLUGIN/agent-indicator.tmux"
sleep 0.5
assert "reloading the plugin does not duplicate gc hooks" \
    test "$(for h in pane-exited after-kill-pane window-unlinked session-created; do t show-hooks -g "$h"; done | grep -c 'env-gc.sh')" -eq 4

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
pb="$(t list-panes -t "$w" -F '#{pane_id}' | tail -1)"
agent_state "$pa" running
agent_state "$pb" done
assert "pane vars created for the exiting pane" has_var "TMUX_AGENT_PANE_${pa}_STATE"
assert "sibling state seeded before natural exit" var_is "TMUX_AGENT_PANE_${pb}_STATE" done
assert "window state seeded before natural exit" var_is "TMUX_AGENT_WINDOW_${w}_DONE" 1
wait_for "natural pane exit removes its vars" gone_all "TMUX_AGENT_PANE_${pa}_STATE"
assert "natural exit preserves sibling state" var_is "TMUX_AGENT_PANE_${pb}_STATE" done
assert "natural exit preserves live window state" var_is "TMUX_AGENT_WINDOW_${w}_DONE" 1
t kill-window -t "$w"
wait_for "count back at baseline after exit test" eq_count "$base"

# remain-on-exit fires pane-died, not pane-exited. A still-listed pane and a
# stale/misdirected pane event must both keep the pane's state until removal.
t new-window -d -t main: "sleep 2"
w="$(t list-windows -t main -F '#{window_id}' | tail -1)"
pa="$(t list-panes -t "$w" -F '#{pane_id}')"
t set-window-option -t "$w" remain-on-exit on
agent_state "$pa" running
assert "retained pane state seeded before event" var_is "TMUX_AGENT_PANE_${pa}_STATE" running
assert "pane event with a live target exits successfully" gc pane "$pa"
assert "pane event cannot delete a listed live pane" var_is "TMUX_AGENT_PANE_${pa}_STATE" running
pane_is_dead() { [ "$(t display-message -p -t "$pa" '#{pane_dead}')" = 1 ]; }
wait_for "remain-on-exit pane is dead but still listed" pane_is_dead
assert "sweep of retained dead pane exits successfully" gc sweep
assert "retained dead pane keeps its state" var_is "TMUX_AGENT_PANE_${pa}_STATE" running
t kill-window -t "$w"
wait_for "removing retained pane clears its state" eq_count "$base"

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
# running does not normally set window DONE; explicitly seed window state so
# this test detects a collector that deletes all WINDOW entries on unlink.
t set-environment -g "TMUX_AGENT_WINDOW_${wl}_DONE" 1
assert "linked window state seeded before unlink" var_is "TMUX_AGENT_WINDOW_${wl}_DONE" 1
t link-window -d -s "$wl" -t other:
t unlink-window -t "other:$(t list-windows -t other -F '#{window_index} #{window_id}' | awk -v w="$wl" '$2==w{print $1}')"
sleep 1
assert "unlinking one of two links keeps the live window's pane vars" has_var "TMUX_AGENT_PANE_${pl}_STATE"
assert "unlinking one of two links keeps live window vars" var_is "TMUX_AGENT_WINDOW_${wl}_DONE" 1
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
assert "live window vars still present after the load sweep" var_is "TMUX_AGENT_WINDOW_${wlive}_DONE" 1

# Names are input to a generated tmux source file. Only producer-shaped suffixes
# may be emitted; hostile names must remain literal and cannot run commands.
hostile='TMUX_AGENT_PANE_%999999_X"; set-environment -g GC_INJECTED yes; #'
hostile_window='TMUX_AGENT_WINDOW_@999999_X"; set-environment -g GC_INJECTED_WINDOW yes; #'
odd='TMUX_AGENT_PANE_%999999_${HOME}\\quote'
t set-environment -g "$hostile" sentinel
t set-environment -g "$hostile_window" sentinel
t set-environment -g "$odd" sentinel
t set-environment -g TMUX_AGENT_PANE_%999999_STATE stale
assert "hostile pane name seeded literally" var_is "$hostile" sentinel
assert "hostile window name seeded literally" var_is "$hostile_window" sentinel
assert "hostile-name sweep succeeds" gc sweep
assert "normal stale name beside hostile names is removed" gone TMUX_AGENT_PANE_%999999_STATE
assert "hostile pane name remains literal" var_is "$hostile" sentinel
assert "hostile window name remains literal" var_is "$hostile_window" sentinel
assert "substitution and backslash name remains literal" var_is "$odd" sentinel
assert "hostile pane name cannot inject a tmux command" gone GC_INJECTED
assert "hostile window name cannot inject a tmux command" gone GC_INJECTED_WINDOW
t set-environment -gu "$hostile"
t set-environment -gu "$hostile_window"
t set-environment -gu "$odd"

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

# Exercise the actual startup ordering: config loads in a server with no
# sessions. Inherited stale and future-live ids exist before the first session.
# Use the SAME private socket after shutting down the earlier test server.
t kill-server
# tmux leaves a dead socket pathname on some versions; wait for connection
# refusal instead of relying on removal of that pathname.
server_gone() { ! t show-environment -g >/dev/null 2>&1; }
wait_for "previous private server has stopped" server_gone
startup_conf="$SCRATCH/startup.conf"
: > "$SCRATCH/gc-run-shell.calls"
{
    echo 'set -g exit-empty off'
    echo "run-shell '$PLUGIN/agent-indicator.tmux >$SCRATCH/bootstrap.out 2>$SCRATCH/bootstrap.err'"
} > "$startup_conf"
env 'TMUX_AGENT_PANE_%999999_STATE=stale-pane' 'TMUX_AGENT_WINDOW_@999999_DONE=stale-window' \
    'TMUX_AGENT_PANE_%0_STATE=live-pane' 'TMUX_AGENT_WINDOW_@0_DONE=live-window' \
    tmux -L "$SOCKET" -f "$startup_conf" start-server 2>"$SCRATCH/startup.err"
assert "config startup reports no missing current target" test ! -s "$SCRATCH/startup.err"
assert "bootstrap before first session has no job error" test ! -s "$SCRATCH/bootstrap.err"
assert "no GC run-shell scheduled before first session" test ! -s "$SCRATCH/gc-run-shell.calls"
assert "startup import contains stale pane state before first session" var_is TMUX_AGENT_PANE_%999999_STATE stale-pane
assert "startup import contains stale window state before first session" var_is TMUX_AGENT_WINDOW_@999999_DONE stale-window
assert "empty-server gc succeeds without stderr" \
    env TMUX="$GC_TEST_SOCKET_PATH,$(t display-message -p '#{pid}'),0" \
    bash "$PLUGIN/scripts/env-gc.sh" sweep 2>"$SCRATCH/empty.err"
assert "empty-server gc is quiet" test ! -s "$SCRATCH/empty.err"
assert "empty-server gc preserves imported future-live state" var_is TMUX_AGENT_PANE_%0_STATE live-pane
t new-session -d -s imported "sleep 3600"
assert "first pane uses the imported live id" test "$(t list-panes -a -F '#{pane_id}')" = %0
assert "first window uses the imported live id" test "$(t list-windows -a -F '#{window_id}')" = @0
wait_for "first session sweeps imported stale pane and window state" \
    gone_all TMUX_AGENT_PANE_%999999_STATE TMUX_AGENT_WINDOW_@999999_DONE
assert "first-session sweep preserves live pane import" var_is TMUX_AGENT_PANE_%0_STATE live-pane
assert "first-session sweep preserves live window import" var_is TMUX_AGENT_WINDOW_@0_DONE live-window
assert "first-session sweep produces no startup job error" test ! -s "$SCRATCH/startup.err"
assert "bootstrap stays quiet after first-session sweep" test ! -s "$SCRATCH/bootstrap.err"

last_tmux="$GC_TEST_SOCKET_PATH,$(t display-message -p '#{pid}'),0"
t kill-session -t imported
assert "same server remains alive with no sessions" t show-environment -g TMUX_AGENT_INDICATOR_DIR
assert "same-server empty gc exits successfully" env TMUX="$last_tmux" bash "$PLUGIN/scripts/env-gc.sh" sweep 2>"$SCRATCH/empty.err"
assert "same-server empty gc is quiet" test ! -s "$SCRATCH/empty.err"
t kill-server
wait_for "same private server has stopped" server_gone
assert "dead-socket gc exits successfully" env TMUX="$last_tmux" bash "$PLUGIN/scripts/env-gc.sh" sweep 2>"$SCRATCH/dead.err"
assert "dead-socket gc is quiet" test ! -s "$SCRATCH/dead.err"

if [ "$fails" -eq 0 ]; then echo "All tests passed."; exit 0; fi
echo "$fails test(s) failed."; exit 1
