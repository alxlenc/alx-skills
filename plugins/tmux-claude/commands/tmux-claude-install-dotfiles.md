---
description: Install the tmux-claude dotfiles (tmux.conf + scripts + plugins) and wire Claude hooks so the agent-indicator can show when the current Claude session is running / needs input / done.
argument-hint: "[--no-hooks]"
---

Run the tmux-claude dotfiles installer.

What it does:

- Symlinks the opinionated `tmux.conf` and helper scripts into `~/.config/tmux/` and `~/.tmux/scripts/`.
- Installs the **tmux-agent-indicator** plugin *and* merges its Claude hooks (UserPromptSubmit, PermissionRequest, Stop) into `~/.claude/settings.json` so pane borders and window titles change colour as the agent moves through `running` / `needs-input` / `done`.
- Git-clones **tmux-paste-image** into `~/.tmux/plugins/`.

Existing real files are backed up to `<path>.bak.<timestamp>`. Re-running is safe — symlinks refresh, plugin checkouts `git pull`, and hook merging is idempotent (dedupes itself).

Steps:

1. If the user passed `--no-hooks` in `$ARGUMENTS`, invoke with that flag; otherwise invoke the installer with default flags:
   - Default: `bash ${CLAUDE_PLUGIN_ROOT}/dotfiles/install.sh`
   - With flag: `bash ${CLAUDE_PLUGIN_ROOT}/dotfiles/install.sh --no-hooks`
2. Relay the installer's output to the user.
3. If `$TMUX` is set (a tmux session is running), offer to reload immediately with `tmux source-file ~/.config/tmux/tmux.conf`. Otherwise tell the user to run that when they next start tmux.
4. If hooks were installed, mention that the current Claude session needs to **restart** for the hooks in `~/.claude/settings.json` to take effect (hooks are loaded at session start).
5. Summarise what was installed (config + scripts + two tmux plugins) and list any backup paths the installer reported.
