#!/usr/bin/env bash
# Garbage-collect TMUX_AGENT_* server-environment variables of dead panes/windows.
#
# The indicator keeps per-pane / per-window state in the tmux *global
# environment* (TMUX_AGENT_PANE_%N_*, TMUX_AGENT_WINDOW_@N_*). Nothing upstream
# ever removed those entries when a pane or window closed, so they grew without
# bound (7k+ entries seen) and every process the server spawns inherited the
# whole block, slowing shell startup.
#
# Usage:
#   env-gc.sh pane <%id>     sweep dead ids after a pane event
#                            (a bad/empty id falls back to sweep)
#   env-gc.sh window <@id>   unset that window's variables if it is gone, plus any other dead ids
#   env-gc.sh sweep          unset variables of every pane/window that no longer exists
#
# The "plus any other dead ids" half matters: tmux does not fire pane-exited for
# panes destroyed by kill-window / kill-session, so window-unlinked is the only
# hook that sees them go.
#
# Only TMUX_AGENT_PANE_<id>_* and TMUX_AGENT_WINDOW_<id>_* with alphanumeric /
# underscore suffixes are ever touched. Malformed names are left alone.
# SESSION_SEEN_*, LAST_SESSION, ACTIVE_PANE_*, INDICATOR_DIR, ANIMATION_* and the
# variables of live panes/windows are left alone.
#
# Everything runs in ONE tmux read (list-panes + list-windows + show-environment
# chained with `\;`) and ONE write (a generated file passed to source-file), so
# thousands of stale entries clear in well under a second instead of paying one
# tmux round trip per variable.

set -euo pipefail

# Only ever act on the server that invoked us (hooks and run-shell set $TMUX).
# Without it tmux would fall back to the default socket, i.e. some other server.
command -v tmux >/dev/null 2>&1 && [ -n "${TMUX:-}" ] || exit 0

mode="${1:-sweep}"
target="${2:-}"
case "$mode" in
    # A missing or malformed id (e.g. a hook format that expanded to nothing)
    # degrades to a dead-ids-only sweep, which is always safe.
    pane)   case "$target" in %[0-9]*) ;; *) mode=sweep; target="" ;; esac ;;
    window) case "$target" in @[0-9]*) ;; *) mode=sweep; target="" ;; esac ;;
    sweep)  target="" ;;
    *) echo "Usage: env-gc.sh pane <%id> | window <@id> | sweep" >&2; exit 1 ;;
esac

cmds="$(mktemp "${TMPDIR:-/tmp}/tmux-agent-gc.XXXXXX")"
trap 'rm -f "$cmds"' EXIT

# Live ids are tagged "P %n" / "W @n"; environment lines are NAME=value. The
# three reads run back to back inside the server, so the live set and the
# variable list are a consistent snapshot.
# No sessions yet, or the invoking server has gone away: do nothing. In
# particular, never interpret an incomplete/failed read as an empty live set.
snapshot=$(tmux list-panes -a -F 'P #{pane_id}' \; \
     list-windows -a -F 'W #{window_id}' \; \
     show-environment -g 2>/dev/null) || exit 0
printf '%s\n' "$snapshot" |
awk '
    $1 == "P" && NF == 2 { livep[$2] = 1; next }
    $1 == "W" && NF == 2 { livew[$2] = 1; next }
    { envl[++n] = $0 }
    END {
        for (i = 1; i <= n; i++) {
            name = envl[i]
            sub(/=.*/, "", name)
            # This allowlist also makes the generated tmux command literal:
            # no quotes, backslashes, formats, substitutions or separators.
            if (name !~ /^TMUX_AGENT_(PANE_%|WINDOW_@)[0-9]+_[A-Za-z0-9_]+$/) continue
            id = name
            sub(/^TMUX_AGENT_(PANE|WINDOW)_/, "", id)
            sub(/_.*/, "", id)
            kind = substr(id, 1, 1)
            dead = (kind == "%") ? !(id in livep) : !(id in livew)
            # Hooks are hints to sweep, never proof that their target is gone.
            # remain-on-exit fires pane-died and keeps the pane listed; retain
            # its state until it is removed. Likewise, window-unlinked can
            # refer to a window that is still linked into another session.
            if (dead) print "set-environment -gu \"" name "\""
        }
    }' > "$cmds"

[ -s "$cmds" ] || exit 0
tmux source-file "$cmds"
