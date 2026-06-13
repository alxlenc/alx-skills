# tmux-paste-image: remote clipboard over SSH — design

**Date:** 2026-06-13
**Status:** approved (design), pending implementation plan
**Affects:** `plugins/tmux-claude/dotfiles/` (config, scripts, installer, README)

## Problem

The `tmux-claude` dotfiles ship a clipboard image-paste binding (`prefix + I`): it
grabs an image from the system clipboard, saves it to a PNG, and types
`/image <path>` into the focused Claude Code pane.

It works when tmux runs on the same machine as the clipboard. It silently fails
("No PNG image found in clipboard") when the user runs tmux + Claude on a **headless
remote host over SSH**, because the image lives on the SSH *client's* clipboard while
the paste script runs on the SSH *server*.

Concrete case: user sits at **rzdesk** (KDE/Wayland desktop, holds the clipboard),
SSHes into **rzw** (headless server, 10.0.0.1:10101), and runs tmux + Claude there.
`prefix + I` on rzw runs the script on rzw, which has no display and no clipboard.

## Root cause

The shipped binding delegates to the upstream plugin
`jkhas8/tmux-paste-image` (git-cloned + commit-pinned by `install.sh`). Its
`paster.sh` reads the clipboard with a **hardcoded local** `wl-paste`/`xclip`. There
is no seam to source the clipboard from anywhere else. The upstream script is also
*not* part of this repo, so editing it is neither durable (a reinstall re-checks-out
the pinned commit) nor publishable.

## Genericity analysis (why the design is shaped this way)

There is **no universal zero-config fix** for *images* over SSH. The only
config-free SSH clipboard channel is **OSC 52**, which is text-only and size-capped —
it cannot carry a PNG. Every image-over-SSH path therefore requires an
environment-specific transport (reverse SSH reachability, or a forwarded socket plus a
client-side daemon). That is a property of the problem.

What *can* be generic: the plugin should not hardcode *a* transport. It should expose
a **seam** — a user-supplied command that emits PNG bytes on stdout — and keep all
setup-specific values (hosts, keys, display vars) out of the published plugin and in
per-machine config.

**Decisions (confirmed with user 2026-06-13):**

- **Vendor** a generic paste script into this repo (own it; drop the pinned
  third-party clone). Rejected: editing the upstream clone (not durable, not ours);
  forking/PR upstream (slower, carries a fork — may revisit later).
- **Explicit command only** for the remote source (a `@paste-image-clip-command`
  tmux option). Rejected for now: auto-detecting the SSH client from `SSH_CONNECTION`
  (more magic, more failure modes) — can be layered on later as an override-able
  convenience.
- **Keybinding unchanged:** `prefix + I`.
- **Deploy loop:** changes are committed and pushed to the git remote; the installed
  plugin updates from there, then `install.sh` re-runs on each node.

## Design

### 1. Vendored script — `dotfiles/scripts/paste-image.sh`

A generic superset of upstream `paster.sh`. Behavior:

1. Resolve save dir from `@paste-image-path` (default `~/.cache/tmux-paste-image`).
2. **Resolve clipboard source:**
   - If `@paste-image-clip-command` is set and non-empty → run it; its **stdout is
     the PNG bytes** (redirect to the output file; binary-safe).
   - Else → local autodetect, unchanged from today: `wl-paste --type image/png` when
     `$WAYLAND_DISPLAY` is set; `xclip -selection clipboard -t image/png -o` when
     `$DISPLAY` is set; otherwise error.
3. If the saved file is non-empty: keep the existing Claude-prompt heuristic →
   `send-keys "/image <path>" Enter`; otherwise paste the bare path. Display a tmux
   status message.
4. If empty: display the existing "No PNG image found" error and remove the empty file.

Contains **no** host/key/display specifics. The transport is entirely whatever
`@paste-image-clip-command` runs.

### 2. `dotfiles/config/tmux.conf`

- Bind `@paste-image-key` (default `I`) to the vendored script instead of loading the
  upstream `paste-image.tmux`.
- Add a generic per-machine override hook near the end (broadly useful, not specific
  to this feature):
  ```
  if-shell '[ -f ~/.config/tmux/local.conf ]' 'source-file ~/.config/tmux/local.conf'
  ```

### 3. `dotfiles/install.sh`

- Remove the `clone_or_update jkhas8/tmux-paste-image` step and its run-shell load.
  The vendored script deploys via the existing `scripts/*.sh` symlink loop.
- Reword `check_clipboard_tool`: on a headless node (no `$WAYLAND_DISPLAY`/`$DISPLAY`),
  point the user at `@paste-image-clip-command` rather than warning that paste "won't
  work."

### 4. `dotfiles/README.md`

Document `@paste-image-clip-command` and the `local.conf` override. Show the
reverse-SSH `wl-paste` recipe as an **example**, not a default.

### 5. Per-node, NOT committed — `~/.config/tmux/local.conf` on rzw only

```
set -g @paste-image-clip-command "ssh -o ConnectTimeout=6 -i ~/.ssh/id_cluster alxlenc@10.0.0.2 'XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 wl-paste --type image/png'"
```

This is the cluster-specific transport (reverse pull rzw → rzdesk over the existing
passwordless `id_cluster` key). It lives only on rzw and is never published or synced
to rzdesk.

## Data flow

- **On rzw (remote):** `prefix + I` → `paste-image.sh` → runs
  `@paste-image-clip-command` (set in rzw's `local.conf`) → SSHes back to rzdesk,
  reads the live Wayland clipboard → PNG saved under rzw's
  `~/.cache/tmux-paste-image/` (where Claude reads it) → `/image <path>` into the pane.
- **On rzdesk (local):** `@paste-image-clip-command` unset → local autodetect path →
  behavior unchanged.

## Deploy / sequencing

1. Branch in `~/code/alx-skills`; implement items 1–4; commit; push to the remote.
2. Update the installed plugin from the remote on **both** nodes; re-run `install.sh`
   (re-symlinks the new script, refreshes `tmux.conf`, drops the upstream clone).
3. Create rzw-only `~/.config/tmux/local.conf` (item 5).
4. Reload tmux on rzw (`tmux source-file ~/.config/tmux/tmux.conf`); test `prefix + I`
   in a Claude pane.

## Testing

- **rzdesk regression:** with no `@paste-image-clip-command`, copy an image and
  confirm `prefix + I` still saves + types `/image …` (local path unchanged).
- **rzw transport unit:** copy an image on rzdesk, then on rzw run the configured
  clip command and confirm a valid non-empty PNG lands.
- **rzw end-to-end:** in a real Claude pane on rzw, copy an image on rzdesk, press
  `prefix + I`, confirm `/image <rzw-path>` is typed and the file is a valid PNG.
- **Failure paths:** rzdesk unreachable → fast `ConnectTimeout` failure with the
  existing error message; empty remote clipboard → existing "No PNG image found".

## Out of scope

- SSH-client auto-detection (explicit command only for now).
- macOS / X11-remote transports (documented seam supports them; not wired here).
- Upstreaming the seam to `jkhas8/tmux-paste-image`.
