# `tmux-claude`

Drive tmux from Claude Code — split panes, open windows, run commands, read output, resize, zoom, rename — all through natural language.

## Skills

- **tmux** — manage panes and windows (`split`, `close`, `send`, `read`, `resize`, `focus`, `zoom`, `window-new`, `window-close`, `window-select`, `window-list`, `window-rename`).
- **fork-tmux** — fork a tracked tmux window with lifecycle management, session forking, and rewind support.
- **handoff** — continue a long conversation in a fresh Claude session with full context preservation.
- **controller** — put one Claude in charge of several others so a fleet of windows keeps moving unattended: it watches each worker for idle / a pending question / high context, answers the routine ones, hands over the next step, `/compact`s a window before it runs out, and coordinates cross-window git merges.

All skills require an active tmux session (`$TMUX`). See [`USAGE_PATTERNS.md`](USAGE_PATTERNS.md) for composed workflows.

## Install

```bash
/plugin marketplace add alxlenc/alx-skills
/plugin install tmux-claude@alx-skills
```

## Dotfiles (optional)

> **Warning:** This is an opinionated setup. It replaces your `tmux.conf` with a Catppuccin Mocha theme, vi copy mode, and custom keybindings. It also installs two third-party tmux plugins: [tmux-paste-image](https://github.com/jkhas8/tmux-paste-image) (paste clipboard images into Claude Code with prefix + `I`) and [tmux-agent-indicator](https://github.com/accessd/tmux-agent-indicator) (visual alerts when a tmux window needs attention — pane borders and window titles change colour as Claude transitions `running` → `needs-input` → `done`). Existing files are backed up to `<path>.bak.<timestamp>`.

```bash
# From inside Claude Code:
bash $CLAUDE_PLUGIN_ROOT/dotfiles/install.sh

# Or directly:
bash ~/.claude/plugins/cache/alx-skills/tmux-claude/*/dotfiles/install.sh

# Skip Claude hook installation:
bash $CLAUDE_PLUGIN_ROOT/dotfiles/install.sh --no-hooks
```

See [`dotfiles/README.md`](dotfiles/README.md) for the full keybinding reference and uninstall instructions.

## Tooling dependencies

**Required (for the skills)**
- [`tmux`](https://github.com/tmux/tmux) ≥ 3.0 — every skill requires an active session (`$TMUX` set).
- `python3` — `tmux_panes.py` and `fork_tmux.py` helpers.

**Pulled in by the dotfiles installer**
- `git`, `curl` — to clone/fetch the upstream plugins (see [Credits](#credits)).
- `xclip` (X11) or `wl-clipboard` (Wayland) — needed by `tmux-paste-image` for prefix + `I`. The installer probes and prints a distro-specific hint if missing.

**Optional — each unlocks one keybinding**
- [`glow`](https://github.com/charmbracelet/glow) — renders markdown inside a right-split pane when you press prefix + `o` on a `.md`/`.markdown`/`.mkd` path. Non-markdown files fall back to `$EDITOR`.
- [`urlscan`](https://github.com/firecat53/urlscan) or [`urlview`](https://github.com/sigpipe/urlview) — picker for URLs captured from the current pane (prefix + `U`). `urlscan` is preferred when both are available.
- [`fpp`](https://github.com/facebook/PathPicker) (Facebook PathPicker) — picker for file paths captured from the current pane (prefix + `F`).
- `wl-copy` / `xsel` / `xclip` / `pbcopy` / `clip.exe` — any one enables tmux's `y` binding to yank the selection to the system clipboard (Wayland / X11 / macOS / WSL respectively).
- `wl-paste` / `xsel` / `xclip` / `pbpaste` / `powershell.exe` — any one enables prefix + `Ctrl-p` to paste the system clipboard into the pane.

## Credits

- **[tmux-agent-indicator](https://github.com/accessd/tmux-agent-indicator)** by [@accessd](https://github.com/accessd) — AI agent state signalling + Claude hooks.
- **[tmux-paste-image](https://github.com/jkhas8/tmux-paste-image)** by [@jkhas8](https://github.com/jkhas8) — clipboard image paste (Linux only).
