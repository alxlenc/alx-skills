# `tmux-claude`

Drive tmux from Claude Code. Ask Claude to split a pane, open a new window, run a command in another pane, read output from a long-running process, resize, zoom, rename — all via a single Python helper script. Ships with an opinionated `tmux.conf`, a pair of third-party tmux plugins you can install with one command, and Claude-aware agent-indicator hooks that change pane-border colour as the session transitions `running` → `needs-input` → `done`.

## Skills

- **tmux** — manage panes and windows: `split`, `close`, `send`, `read`, `resize`, `focus`, `zoom`, `window-new`, `window-close`, `window-select`, `window-list`, `window-rename`. Requires an active tmux session (`$TMUX`).
- **fork-tmux** — fork a new tmux window that runs a command, with lifecycle management (session ID, status file, log capture for non-interactive commands, wait-for-completion polling). Supports forking the current Claude session with full context preservation, and rewinding to a previous conversation point. Requires an active tmux session (`$TMUX`). Prefer the `tmux` skill's `window-new` for lightweight fire-and-forget windows.
- **handoff** — continue a long conversation in a fresh Claude session: opens a side-by-side tmux split, writes a self-contained continuation prompt (plan, tasks, progress, git state, active files, key context), and launches Claude in yolo mode. Requires an active tmux session (`$TMUX`).

## Usage patterns

See [`USAGE_PATTERNS.md`](USAGE_PATTERNS.md) for composed workflows across these three skills — parallel jobs, forked sub-agents, multi-service layouts, rewind, handoff, and more.

## Dotfiles (optional)

Installed by `/tmux-claude-install-dotfiles`:

- `tmux.conf` — Catppuccin Mocha, vi copy mode, cross-platform clipboard (Wayland/X11/macOS/WSL/tmate), intuitive splits, prefix + `o` to open file paths from buffer, prefix + `U` for URL extraction, prefix + `F` for PathPicker, prefix + `e` to edit + reload config.
- Bundled third-party tmux plugins (see [Credits](#credits) for full attribution): [`accessd/tmux-agent-indicator`](https://github.com/accessd/tmux-agent-indicator) for AI-agent status signalling, [`jkhas8/tmux-paste-image`](https://github.com/jkhas8/tmux-paste-image) for clipboard-image paste (prefix + `I`).

See [`dotfiles/README.md`](dotfiles/README.md) for the full keybinding reference.

## Command

- **/tmux-claude-install-dotfiles** — turnkey install: symlink the tmux.conf + scripts, install both tmux plugins, and wire Claude hooks (`UserPromptSubmit`, `PermissionRequest`, `Stop`) into `~/.claude/settings.json` so pane borders and window titles change colour as the Claude session transitions `running` → `needs-input` → `done`. Safe to re-run: pre-existing regular files at any target path are backed up to `<path>.bak.<timestamp>` before being replaced, hook merging is idempotent, and a pre-existing legacy `~/.tmux.conf` (which tmux would now ignore in favour of the XDG path) is flagged with a warning rather than touched. Pass `--no-hooks` to skip the hook setup.

## Install

From the [`alx-skills`](../../README.md) marketplace:

```bash
/plugin marketplace add <path-or-github>/alx-skills
/plugin install tmux-claude@alx-skills

# (Optional) install the tmux dotfiles into your home
/tmux-claude-install-dotfiles
```

## Tooling dependencies

The skills themselves only need `tmux` + `python3`. Everything else unlocks specific features in the dotfiles (or is pulled in by `/tmux-claude-install-dotfiles`). All optional tools are runtime-probed — missing ones print a message instead of breaking.

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

The `/tmux-claude-install-dotfiles` command installs two third-party tmux plugins from their upstream repositories. All credit for them goes to their original authors — this plugin only wires them into a Claude-aware config.

- **[tmux-agent-indicator](https://github.com/accessd/tmux-agent-indicator)** by [@accessd](https://github.com/accessd) — the signalling layer this plugin relies on to show when a Claude session is running, waiting for input, or done. The installer also wires matching `UserPromptSubmit` / `PermissionRequest` / `Stop` hooks into `~/.claude/settings.json` so pane borders and window titles change colour in sync with the Claude session state. Installed via its upstream installer script.
- **[tmux-paste-image](https://github.com/jkhas8/tmux-paste-image)** by [@jkhas8](https://github.com/jkhas8) — enables pasting clipboard images directly into the terminal with prefix + `I` (needs `xclip` on X11 or `wl-paste` on Wayland; macOS is not supported by the upstream plugin). Installed via `git clone` into `~/.tmux/plugins/`.

Please star/support the upstream projects if you use them.
