# tmux-claude dotfiles

Opinionated tmux configuration that pairs with the `tmux` skill in this plugin.

## What's in here

- `config/tmux.conf` — single-file tmux config (gpakosz-style). Catppuccin Mocha theme, vi-style copy mode, cross-platform clipboard (Wayland/X11/macOS/WSL/tmate), intuitive splits, prefix + `o` to open file paths from the buffer, prefix + `U` for URL extraction, prefix + `F` for Facebook PathPicker, prefix + `e` to edit + reload config.
- `scripts/open-file-from-buffer.sh` — helper invoked by prefix + `o`.
- `scripts/paste-image.sh` — helper invoked by prefix + `I`; saves a clipboard image and types `/image <path>` into a Claude pane. Adapted from [`jkhas8/tmux-paste-image`](https://github.com/jkhas8/tmux-paste-image), extended with the `@paste-image-clip-command` seam (see "Remote / SSH clipboard" below).
- `install.sh` — symlinks config + scripts (backing up any pre-existing regular files to `<path>.bak.<timestamp>`), installs both tmux plugins, and wires Claude hooks so the agent-indicator reflects the Claude session's live state. Also warns if a legacy `~/.tmux.conf` exists that tmux would now ignore (not touched — just flagged so you can rename it yourself).

## Plugins installed

- [`accessd/tmux-agent-indicator`](https://github.com/accessd/tmux-agent-indicator) — visual feedback for AI agent states. `running` / `needs-input` / `done` are surfaced in pane border colour and window-title background. Claude hooks are installed automatically so the transitions are event-driven, not polled.
(Image paste — prefix + `I` — is no longer a cloned plugin; it ships as the vendored `scripts/paste-image.sh`, see above.)

## Remote / SSH clipboard (prefix + `I` over SSH)

`prefix + I` runs on the host where the **tmux server** lives. When you SSH into a
headless host and run tmux + Claude there, the clipboard image is on your *local*
machine, not the server — so local `wl-paste`/`xclip` find nothing.

Set `@paste-image-clip-command` to a command that emits PNG bytes on stdout, and
the script uses it instead of the local clipboard. Put it in a per-machine
`~/.config/tmux/local.conf` (sourced automatically, not version-controlled) so the
host-specific bits never ship in the repo:

```tmux
# ~/.config/tmux/local.conf on the headless server — pull the image from your desktop
set -g @paste-image-clip-command "ssh -o ConnectTimeout=6 user@desktop 'XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 wl-paste --type image/png'"
```

Requirements for this example: the server can SSH to the desktop non-interactively
(key/agent), and the desktop has `wl-paste` (Wayland) or `xclip` (X11). Any transport
works — it is just "a command that prints a PNG." There is no zero-config option:
OSC 52, the only config-free SSH clipboard channel, is text-only and cannot carry an
image.

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
- Optional (prefix + `I` image-paste into Claude Code): `xclip` on X11 or `wl-clipboard` (for `wl-paste`) on Wayland for the **local** clipboard. On a **headless/SSH** host, set `@paste-image-clip-command` instead (see "Remote / SSH clipboard"). `install.sh` probes for the local tool and prints a distro-specific install hint if missing.
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
curl -fsSL https://raw.githubusercontent.com/accessd/tmux-agent-indicator/566dda63be1f38efe40528c90c6076a589051df8/install.sh \
    | bash -s -- --uninstall-claude --no-codex --no-opencode

# Remove config + plugins
rm -f ~/.config/tmux/tmux.conf ~/.tmux/scripts/open-file-from-buffer.sh ~/.tmux/scripts/paste-image.sh
rm -rf ~/.tmux/plugins/tmux-agent-indicator
```
