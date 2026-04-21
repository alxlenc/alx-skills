#!/bin/sh
# Open file path from tmux buffer in a right split pane.
# Supports relative paths (resolved against pane CWD) and line numbers (file:42).

PANE_PATH="$1"

raw="$(tmux save-buffer - 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
if [ -z "$raw" ]; then
  tmux display-message "Buffer is empty"
  exit 0
fi

# Split path:line if present
path="${raw%%:*}"
line="${raw#*:}"
[ "$line" = "$raw" ] && line=""

# Resolve relative paths against pane CWD
if [ ! -f "$path" ] && [ -f "$PANE_PATH/$path" ]; then
  path="$PANE_PATH/$path"
fi

if [ ! -f "$path" ]; then
  tmux display-message "Not a file: $raw"
  exit 0
fi

editor="${EDITOR:-vim}"

# Use glow for markdown files
case "$path" in
  *.md|*.markdown|*.mkd)
    tmux split-window -h -c "$PANE_PATH" "glow -p '$path'"
    exit 0
    ;;
esac

# Open with line number if valid
if [ -n "$line" ] && expr "$line" : '[0-9][0-9]*$' >/dev/null 2>&1; then
  tmux split-window -h -c "$PANE_PATH" "$editor +$line '$path'"
else
  tmux split-window -h -c "$PANE_PATH" "$editor '$path'"
fi
