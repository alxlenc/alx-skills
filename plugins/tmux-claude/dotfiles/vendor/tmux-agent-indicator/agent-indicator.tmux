#!/usr/bin/env bash
# tmux-agent-indicator bootstrap.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

do_interpolation() {
    local string="$1"
    string="${string//\#\{agent_indicator\}/#($CURRENT_DIR/scripts/indicator.sh)}"
    string="${string//\#\{agent_limits\}/#($CURRENT_DIR/scripts/agent-limits.sh)}"
    string="${string//\#\{agent_session_dots\}/#($CURRENT_DIR/scripts/session-dots.sh '#S')}"
    echo "$string"
}

update_tmux_option() {
    local option="$1"
    local option_value
    option_value=$(tmux show-option -gqv "$option")
    if [ -z "$option_value" ]; then
        return
    fi
    tmux set-option -gq "$option" "$(do_interpolation "$option_value")"
}

register_hook_once() {
    local hook_type="$1"
    local command="$2"
    local match="${3:-$CURRENT_DIR}"
    local existing_hooks
    existing_hooks=$(tmux show-hooks -g "$hook_type" 2>/dev/null || true)

    # Remove all previously registered plugin hooks to avoid duplicates.
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local existing_name
        existing_name="${line%% *}"
        tmux set-hook -gu "$existing_name" 2>/dev/null || true
    done < <(printf '%s\n' "$existing_hooks" | grep -F "$match" || true)

    tmux set-hook -ag "$hook_type" "$command"
}

register_focus_hooks() {
    local hook_script="$CURRENT_DIR/scripts/pane-focus-in.sh"
    local hook_command="run-shell \"$hook_script \\\"#{pane_id}\\\" \\\"#{window_id}\\\"\""
    register_hook_once "pane-focus-in" "$hook_command"
    register_hook_once "after-select-window" "$hook_command"
    register_hook_once "after-select-pane" "$hook_command"
}

# Local addition (see VENDORED.md): upstream never removed the per-pane /
# per-window TMUX_AGENT_* environment entries, so they leaked forever and bloated
# the environment of every process the server spawns.
register_gc_hooks() {
    local gc_script="$CURRENT_DIR/scripts/env-gc.sh"
    register_hook_once "pane-exited" "run-shell -b \"$gc_script pane \\\"#{hook_pane}\\\"\""
    # after-kill-pane does not know which pane it killed (hook_pane is empty and
    # pane_id is the surviving current pane), so it runs the dead-ids sweep.
    register_hook_once "after-kill-pane" "run-shell -b \"$gc_script sweep\""
    register_hook_once "window-unlinked" "run-shell -b \"$gc_script window \\\"#{hook_window}\\\"\""
    # Startup sweep so a server restart or crash also self-heals. Background so
    # it never delays tmux startup; it is a single tmux read plus a single write.
    tmux run-shell -b "$gc_script sweep"
}

main() {
    tmux set-environment -g TMUX_AGENT_INDICATOR_DIR "$CURRENT_DIR"
    update_tmux_option "status-right"
    update_tmux_option "status-left"
    update_tmux_option "@minimal-tmux-status-right"
    update_tmux_option "@minimal-tmux-status-left"
    update_tmux_option "@minimal-tmux-status-right-extra"
    update_tmux_option "@minimal-tmux-status-left-extra"
    register_focus_hooks
    register_gc_hooks
    local session_script="$CURRENT_DIR/scripts/session-changed.sh"
    register_hook_once "client-session-changed" "run-shell \"$session_script\""
}

main
