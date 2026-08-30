#!/usr/bin/env bash
# Tests for tmux.conf bindings — dependency-free, uses a private tmux server.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/../tmux.conf"
SOCKET="tmux-conf-test-$$"
fails=0

cleanup() { tmux -L "$SOCKET" kill-server 2>/dev/null || true; }
trap cleanup EXIT

assert() {  # assert <description> <command...>
    local desc="$1"; shift
    if "$@"; then echo "ok   - $desc"; else echo "FAIL - $desc"; fails=$((fails + 1)); fi
}

# The config sources host-specific plugins that may be absent here; config errors
# are non-fatal to the server, and none of them touch the bindings under test.
tmux -L "$SOCKET" -f "$CONF" new-session -d -s s -x 80 -y 24 2>/dev/null

binding() {  # binding <table> <key> -> the bound command
    tmux -L "$SOCKET" list-keys -T "$1" 2>/dev/null \
        | awk -v key="$2" '$4 == key { $1=""; $2=""; $3=""; $4=""; sub(/^ +/, ""); print }'
}

# Left-clicking status-left (the session-name pill) opens the window picker.
# tmux leaves MouseDown1StatusLeft unbound by default and already wraps
# status-left in `range=left`, so the pill is a click target for free.
click="$(binding root MouseDown1StatusLeft)"
assert "MouseDown1StatusLeft is bound" test -n "$click"
assert "click opens the zoomed window picker" \
    grep -q 'choose-tree -Zw' <<<"$click"

# prefix + w keeps working and shows the same tree as the click.
prefix_w="$(binding prefix w)"
assert "prefix w still opens the window picker" \
    grep -q 'choose-tree -Zw' <<<"$prefix_w"
assert "click and prefix w share one tree format" test "$click" = "$prefix_w"

# The shared format lives in a user option, expanded per tree item via #{E:}.
fmt="$(tmux -L "$SOCKET" show -gv @window_tree_format 2>/dev/null)"
assert "@window_tree_format is set" test -n "$fmt"
assert "bindings reference the shared option" \
    grep -q '#{E:@window_tree_format}' <<<"$click"
# #{E:} must re-expand the option as a format, not print it literally.
expanded="$(tmux -L "$SOCKET" display-message -p '#{E:@window_tree_format}' 2>/dev/null)"
assert "the option expands as a format" test -n "$expanded"
assert "the expansion is not the literal format string" test "$expanded" != "$fmt"
assert "the expansion leaves no unresolved format markers" \
    grep -qv '#{' <<<"$expanded"

# In a window-list context the format must still label each line with its
# window id (@N) — the reason this config overrides choose-tree's default -F.
tmux -L "$SOCKET" new-window -d
window_line="$(tmux -L "$SOCKET" display-message -p '#{W:#{E:@window_tree_format},}' 2>/dev/null)"
assert "window lines still carry the window id" grep -q '^@[0-9]' <<<"$window_line"

if [ "$fails" -eq 0 ]; then echo "All tests passed."; exit 0; fi
echo "$fails test(s) failed."; exit 1
