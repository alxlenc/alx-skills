#!/usr/bin/env bash
# paste-image.sh — save a clipboard image to a PNG and hand it to the focused pane.
#
# Clipboard source resolution:
#   1. If tmux option @paste-image-clip-command is set, run it; its STDOUT is the
#      PNG bytes. This is the seam that lets a headless/SSH host pull the image
#      from elsewhere, e.g.:
#        set -g @paste-image-clip-command \
#          "ssh desktop 'WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 wl-paste --type image/png'"
#   2. Otherwise autodetect locally: wl-paste (Wayland) or xclip (X11).
#
# In a Claude Code pane it types `/image <path>`; otherwise it pastes the bare
# path. Contains no host/display specifics — those live in user config.
set -u

get_opt() {  # get_opt <option> <default>
    local val
    val="$(tmux show-option -gqv "$1" 2>/dev/null)"
    if [ -z "$val" ]; then printf '%s' "$2"; else printf '%s' "$val"; fi
}

SAVE_DIR="${1:-$(get_opt "@paste-image-path" "$HOME/.cache/tmux-paste-image")}"
CLIP_COMMAND="$(get_opt "@paste-image-clip-command" "")"
PANE="${TMUX_PANE:-$(tmux display-message -p '#{pane_id}' 2>/dev/null)}"

mkdir -p "$SAVE_DIR"
FILE_PATH="$SAVE_DIR/image_$(date +%Y-%m-%d_%H-%M-%S)_$$.png"

fetch_clip() {  # writes PNG bytes to stdout; non-zero if no source available
    if [ -n "$CLIP_COMMAND" ]; then
        eval "$CLIP_COMMAND"
    elif [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-paste >/dev/null 2>&1; then
        wl-paste --type image/png
    elif [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard -t image/png -o
    else
        return 1
    fi
}

if ! fetch_clip > "$FILE_PATH" 2>/dev/null || [ ! -s "$FILE_PATH" ]; then
    rm -f "$FILE_PATH"
    if [ -z "$CLIP_COMMAND" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
        tmux display-message "[paste-image] No clipboard source. Set @paste-image-clip-command for headless/SSH hosts."
    else
        tmux display-message "[paste-image] No PNG image found in clipboard."
    fi
    exit 1
fi

# Heuristic: detect a Claude prompt to send `/image`. May false-positive on panes
# whose last lines start with "> " (e.g. shells); worst case is a stray /image line.
PANE_CONTENT="$(tmux capture-pane -t "$PANE" -p 2>/dev/null | tail -5)"
if printf '%s' "$PANE_CONTENT" | grep -qE "(^›|^>|claude.*›|Human:|Assistant:)"; then
    tmux send-keys -t "$PANE" "/image $FILE_PATH" Enter
    tmux display-message "[paste-image] Image sent to Claude: $(basename "$FILE_PATH")"
else
    tmux send-keys -t "$PANE" "$FILE_PATH"
    tmux display-message "[paste-image] Path pasted: $FILE_PATH"
fi
