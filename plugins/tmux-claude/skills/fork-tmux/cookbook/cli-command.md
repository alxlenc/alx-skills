# Raw CLI Command

Execute a raw CLI command in a new tmux window.

## Instructions

1. Extract the command from the user's request.
2. Run `fork_tmux.py fork` with the command.

## Execution

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork "<command>"

# With custom working directory
python3 ${CLAUDE_PLUGIN_ROOT}/skills/fork-tmux/scripts/fork_tmux.py fork --cwd /path/to/directory "<command>"
```

**Note:** Use `--cwd` to specify a different working directory (defaults to current directory).

## Examples

- User: "fork tmux to run npm install"
  - Command: `npm install`
- User: "fork a window for docker compose up -d"
  - Command: `docker compose up -d`
- User: "fork to launch htop"
  - Command: `htop`
