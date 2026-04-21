# tmux-claude dotfiles

Opinionated tmux configuration that pairs with the `tmux` skill in this plugin.

## What's in here

- `config/tmux.conf` — single-file tmux config (gpakosz-style). Catppuccin Mocha theme, vi-style copy mode, cross-platform clipboard (Wayland/X11/macOS/WSL/tmate), intuitive splits, prefix + `o` to open file paths from the buffer, prefix + `U` for URL extraction, prefix + `F` for Facebook PathPicker, prefix + `e` to edit + reload config.
- `scripts/open-file-from-buffer.sh` — helper invoked by prefix + `o`.
- `install.sh` — symlinks config + scripts (backing up any pre-existing regular files to `<path>.bak.<timestamp>`), installs both tmux plugins, and wires Claude hooks so the agent-indicator reflects the Claude session's live state. Also warns if a legacy `~/.tmux.conf` exists that tmux would now ignore (not touched — just flagged so you can rename it yourself).

## Plugins installed

- [`accessd/tmux-agent-indicator`](https://github.com/accessd/tmux-agent-indicator) — visual feedback for AI agent states. `running` / `needs-input` / `done` are surfaced in pane border colour and window-title background. Claude hooks are installed automatically so the transitions are event-driven, not polled.
- [`jkhas8/tmux-paste-image`](https://github.com/jkhas8/tmux-paste-image) — prefix + `I` pastes clipboard image as a file path.

## Claude hooks added

`install.sh` delegates to `tmux-agent-indicator`'s own installer, which merges these into `~/.claude/settings.json`:

| Event | Action |
|---|---|
| `UserPromptSubmit` | agent → `running` |
| `PermissionRequest` | agent → `needs-input` (yellow pane border + window title) |
| `Stop` | agent → `done` (green pane border, red window-title background) |

Merging is idempotent — re-running the installer dedupes itself, leaves unrelated hooks untouched, and creates `~/.claude/settings.json` if it doesn't exist.

Hooks are loaded when a Claude session starts, so **restart Claude** after running `install.sh` for them to take effect.

## Dependencies

- `tmux` ≥ 3.0
- `bash` ≥ 4
- `curl` and `git` (for plugin install)
- `python3` (used by the agent-indicator installer to merge hooks into settings.json)
- Optional (general clipboard yank/paste in tmux): one of `wl-copy` / `xsel` / `xclip` / `pbcopy` / `clip.exe`
- Optional (prefix + `I` image-paste into Claude Code): `xclip` on X11, `wl-clipboard` (for `wl-paste`) on Wayland. Linux-only — not supported on macOS/WSL by the upstream plugin. `install.sh` probes for this and prints a distro-specific install hint (`sudo dnf install ...`, `sudo apt install ...`, etc.) if missing.
- Optional (prefix + `U`): `urlscan` or `urlview`
- Optional (prefix + `F`): `fpp` (Facebook PathPicker)

## Install

```bash
bash dotfiles/install.sh              # full turnkey: config + scripts + plugins + Claude hooks
bash dotfiles/install.sh --no-hooks   # skip the Claude settings.json hook setup
```

## Uninstall

Remove the hooks and files:

```bash
# Remove Claude hooks
curl -fsSL https://raw.githubusercontent.com/accessd/tmux-agent-indicator/main/install.sh \
    | bash -s -- --uninstall-claude --no-codex --no-opencode

# Remove config + plugins
rm -f ~/.config/tmux/tmux.conf ~/.tmux/scripts/open-file-from-buffer.sh
rm -rf ~/.tmux/plugins/tmux-agent-indicator ~/.tmux/plugins/tmux-paste-image
```
