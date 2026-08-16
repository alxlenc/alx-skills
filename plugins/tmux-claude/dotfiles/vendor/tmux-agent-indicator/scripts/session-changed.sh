#!/usr/bin/env bash
# Mark the session we just LEFT as seen so session dots stop showing attention for it.
# Pane-level indicators (borders, titles, bg) are NOT touched here.

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
    exit 0
fi

# The session we just arrived at
current=$(tmux display-message -p '#{session_name}' 2>/dev/null || true)
[ -n "$current" ] || exit 0

# The session we just left (stored from previous switch)
prev=$(tmux show-environment -g TMUX_AGENT_LAST_SESSION 2>/dev/null | sed 's/^[^=]*=//' || true)
if [ -n "$prev" ] && [ "$prev" != "$current" ]; then
    tmux set-environment -g "TMUX_AGENT_SESSION_SEEN_${prev}" "1"
fi

# Track current for next switch
tmux set-environment -g TMUX_AGENT_LAST_SESSION "$current"
tmux refresh-client -S >/dev/null 2>&1 || true
