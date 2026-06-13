#!/usr/bin/env bash
# Tests for paste-image.sh — dependency-free, uses a private tmux server.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASTE="$HERE/../paste-image.sh"
SOCKET="paste-image-test-$$"
WORK="$(mktemp -d)"
fails=0

cleanup() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

assert() {  # assert <description> <command...>
    local desc="$1"; shift
    if "$@"; then echo "ok   - $desc"; else echo "FAIL - $desc"; fails=$((fails + 1)); fi
}

saved_png() { ls "$1"/image_*.png 2>/dev/null | head -1; }

tmux -L "$SOCKET" new-session -d -s s -x 80 -y 24

# Test 1: @paste-image-clip-command output is saved as the PNG (byte-exact)
printf 'FAKE-PNG-BYTES-0123456789' > "$WORK/fixture.bin"
out1="$WORK/out1"
tmux -L "$SOCKET" set-option -g @paste-image-path "$out1"
tmux -L "$SOCKET" set-option -g @paste-image-clip-command "cat '$WORK/fixture.bin'"
tmux -L "$SOCKET" run-shell "bash '$PASTE'"
png1="$(saved_png "$out1")"
assert "clip-command produces a saved png" test -n "$png1"
assert "saved png matches clip-command output" cmp -s "$png1" "$WORK/fixture.bin"

# Test 2: a clip-command that yields no bytes -> no png left behind. Deterministic:
# an explicit clip-command short-circuits local wl-paste/xclip autodetection, so this
# does not depend on the desktop clipboard or display env at all.
out2="$WORK/out2"
tmux -L "$SOCKET" set-option -g @paste-image-path "$out2"
tmux -L "$SOCKET" set-option -g @paste-image-clip-command "true"
tmux -L "$SOCKET" run-shell "bash '$PASTE'" 2>/dev/null || true
assert "empty clip-command leaves no png behind" test -z "$(saved_png "$out2")"

if [ "$fails" -eq 0 ]; then echo "All tests passed."; exit 0
else echo "$fails test(s) failed."; exit 1; fi
