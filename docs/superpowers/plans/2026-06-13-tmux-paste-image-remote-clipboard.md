# tmux-paste-image Remote Clipboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `prefix + I` capture a clipboard image when tmux runs on a headless/remote host over SSH, by sourcing the clipboard from a user-supplied command — with zero setup-specific values in the published plugin.

**Architecture:** Vendor a generic `paste-image.sh` into the `tmux-claude` dotfiles (replacing the pinned third-party `jkhas8/tmux-paste-image` clone). The script reads a new `@paste-image-clip-command` tmux option: if set, its stdout is the PNG bytes; otherwise it autodetects the local clipboard (`wl-paste`/`xclip`) exactly as before. Cluster-specific wiring (the rzw→rzdesk reverse-SSH `wl-paste` command) lives only in a per-node, un-versioned `~/.config/tmux/local.conf`, enabled by a generic source hook in the shipped `tmux.conf`.

**Tech Stack:** POSIX/bash shell, tmux options & key bindings. Tests use a private `tmux -L` server (no new dependencies).

**Repo / branch:** `/home/alxlenc/code/alx-skills`, branch `feat/paste-image-remote-clipboard` (already created, rebased on `main`).

**Spec:** `docs/superpowers/specs/2026-06-13-tmux-paste-image-remote-clipboard-design.md`

---

## File Structure

- **Create** `plugins/tmux-claude/dotfiles/scripts/paste-image.sh` — vendored generic paste script (the only behavioral code).
- **Create** `plugins/tmux-claude/dotfiles/scripts/tests/paste-image.test.sh` — dependency-free tests via a private tmux server.
- **Modify** `plugins/tmux-claude/dotfiles/config/tmux.conf` — bind `@paste-image-key` to the vendored script (drop the upstream `run-shell …paste-image.tmux`), add a `local.conf` source hook.
- **Modify** `plugins/tmux-claude/dotfiles/install.sh` — drop the `jkhas8/tmux-paste-image` clone; reword `check_clipboard_tool` to point headless hosts at `@paste-image-clip-command`.
- **Modify** `plugins/tmux-claude/dotfiles/README.md` — document the option + `local.conf`, credit the vendored origin, fix uninstall.
- **Modify** `plugins/tmux-claude/.claude-plugin/plugin.json` — version bump `0.6.1` → `0.6.2`.
- **Per-node, NOT committed** `~/.config/tmux/local.conf` on rzw — the cluster-specific clip command.

---

## Task 1: Vendor the generic `paste-image.sh` (TDD)

**Files:**
- Create: `plugins/tmux-claude/dotfiles/scripts/paste-image.sh`
- Test: `plugins/tmux-claude/dotfiles/scripts/tests/paste-image.test.sh`

- [ ] **Step 1: Write the failing test**

Create `plugins/tmux-claude/dotfiles/scripts/tests/paste-image.test.sh`:

```bash
#!/usr/bin/env bash
# Tests for paste-image.sh — dependency-free, uses a private tmux server.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASTE="$HERE/../paste-image.sh"
SOCKET="paste-image-test-$$"
WORK="$(mktemp -d)"
fails=0

cleanup() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

assert() {  # assert <description> <command...>
    local desc="$1"; shift
    if "$@"; then echo "ok   - $desc"; else echo "FAIL - $desc"; fails=$((fails + 1)); fi
}

saved_png() { ls "$1"/image_*.png 2>/dev/null | head -1; }

# Test 1: @paste-image-clip-command is the clipboard source
printf 'FAKE-PNG-BYTES-0123456789' > "$WORK/fixture.bin"
out1="$WORK/out1"
env -u WAYLAND_DISPLAY -u DISPLAY tmux -L "$SOCKET" new-session -d -s s1 -x 80 -y 24
tmux -L "$SOCKET" set-option -g @paste-image-path "$out1"
tmux -L "$SOCKET" set-option -g @paste-image-clip-command "cat '$WORK/fixture.bin'"
tmux -L "$SOCKET" run-shell "bash '$PASTE'"
png1="$(saved_png "$out1")"
assert "clip-command produces a saved png" test -n "$png1"
assert "saved png matches clip-command output" cmp -s "$png1" "$WORK/fixture.bin"

# Test 2: no source available -> clean failure, no file left behind
out2="$WORK/out2"
tmux -L "$SOCKET" set-option -g @paste-image-path "$out2"
tmux -L "$SOCKET" set-option -gu @paste-image-clip-command
tmux -L "$SOCKET" run-shell "bash '$PASTE'" 2>/dev/null || true
assert "no source leaves no png behind" test -z "$(saved_png "$out2")"

if [ "$fails" -eq 0 ]; then echo "All tests passed."; exit 0
else echo "$fails test(s) failed."; exit 1; fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/tmux-claude/dotfiles/scripts/tests/paste-image.test.sh`
Expected: FAIL — `paste-image.sh` does not exist yet, so no png is saved (`FAIL - clip-command produces a saved png`).

- [ ] **Step 3: Write minimal implementation**

Create `plugins/tmux-claude/dotfiles/scripts/paste-image.sh`:

```bash
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
FILE_PATH="$SAVE_DIR/image_$(date +%Y-%m-%d_%H-%M-%S).png"

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

PANE_CONTENT="$(tmux capture-pane -t "$PANE" -p 2>/dev/null | tail -5)"
if printf '%s' "$PANE_CONTENT" | grep -qE "(^›|^>|claude.*›|Human:|Assistant:)"; then
    tmux send-keys -t "$PANE" "/image $FILE_PATH" Enter
    tmux display-message "[paste-image] Image sent to Claude: $(basename "$FILE_PATH")"
else
    tmux send-keys -t "$PANE" "$FILE_PATH"
    tmux display-message "[paste-image] Path pasted: $FILE_PATH"
fi
```

- [ ] **Step 4: Make it executable and run the test to verify it passes**

Run:
```bash
chmod +x plugins/tmux-claude/dotfiles/scripts/paste-image.sh
bash plugins/tmux-claude/dotfiles/scripts/tests/paste-image.test.sh
```
Expected: `ok` for all three assertions, then `All tests passed.` (exit 0).

- [ ] **Step 5: Commit**

```bash
git add plugins/tmux-claude/dotfiles/scripts/paste-image.sh \
        plugins/tmux-claude/dotfiles/scripts/tests/paste-image.test.sh
git commit -m "feat(tmux-claude): vendor generic paste-image.sh with @paste-image-clip-command seam"
```

---

## Task 2: Wire the binding in `tmux.conf` + add `local.conf` hook

**Files:**
- Modify: `plugins/tmux-claude/dotfiles/config/tmux.conf` (plugin section, currently lines ~240-242)

- [ ] **Step 1: Replace the upstream plugin load with a binding to the vendored script**

Find:
```
# Clipboard image paste (prefix + I saves clipboard image and pastes path)
set -g @paste-image-key "I"
run-shell ~/.tmux/plugins/tmux-paste-image/paste-image.tmux
```
Replace with:
```
# Clipboard image paste (prefix + I saves clipboard image, types /image into Claude).
# Source: @paste-image-clip-command (if set) else local wl-paste/xclip — see README.
set -g @paste-image-key "I"
run-shell 'tmux bind-key "$(tmux show-option -gqv @paste-image-key)" run-shell ~/.tmux/scripts/paste-image.sh'
```

- [ ] **Step 2: Add a per-machine override hook at the end of the file**

Append to `plugins/tmux-claude/dotfiles/config/tmux.conf`:
```

# --- Per-machine overrides (not version-controlled) --------------------------
# Drop host-specific settings (e.g. @paste-image-clip-command on a headless
# server) in ~/.config/tmux/local.conf — sourced last so it can override above.
if-shell '[ -f ~/.config/tmux/local.conf ]' 'source-file ~/.config/tmux/local.conf'
```

- [ ] **Step 3: Verify the config parses and binds the script (private server)**

Run:
```bash
SOCK="cfg-test-$$"
tmux -L "$SOCK" -f plugins/tmux-claude/dotfiles/config/tmux.conf new-session -d -s c -x 80 -y 24
tmux -L "$SOCK" list-keys -T prefix | grep -E '(^| )I ' | grep paste-image.sh && echo "BIND OK"
tmux -L "$SOCK" kill-server
```
Expected: a line showing prefix `I` bound to `run-shell …/paste-image.sh`, then `BIND OK`. (No config-parse errors printed.)

> Note: the config references plugins (`agent-indicator`) symlinked into `~/.tmux/`. If the private server prints unrelated warnings about missing `~/.tmux/...` paths, that is fine — only the bind-key assertion matters here.

- [ ] **Step 4: Commit**

```bash
git add plugins/tmux-claude/dotfiles/config/tmux.conf
git commit -m "feat(tmux-claude): bind prefix+I to vendored paste-image.sh; add local.conf hook"
```

---

## Task 3: Drop the upstream clone + reword the headless warning in `install.sh`

**Files:**
- Modify: `plugins/tmux-claude/dotfiles/install.sh`

- [ ] **Step 1: Remove the `tmux-paste-image` clone step**

Find (lines ~169-171):
```
echo "==> tmux-paste-image"
clone_or_update "https://github.com/jkhas8/tmux-paste-image.git" "$HOME/.tmux/plugins/tmux-paste-image" \
    "be6ae115fb85347d2d5b986c789fe28604f448e6"
check_clipboard_tool
```
Replace with:
```
echo "==> clipboard image paste"
check_clipboard_tool
```

- [ ] **Step 2: Update the header comment line referring to the clone**

Find (line ~8):
```
#   - Git-clones tmux-paste-image into ~/.tmux/plugins/
```
Replace with:
```
#   - Image paste (prefix + I) ships as ~/.tmux/scripts/paste-image.sh (symlinked above)
```

- [ ] **Step 3: Reword `check_clipboard_tool` headless branch to point at the option**

Find (lines ~111-116):
```
    else
        # No display server detected (headless SSH, console, etc.). Warn and stop.
        echo "  WARN: no \$WAYLAND_DISPLAY or \$DISPLAY detected — tmux-paste-image needs"
        echo "        xclip (X11) or wl-clipboard (Wayland) to capture clipboard images."
        return 0
    fi
```
Replace with:
```
    else
        # No local display (headless SSH / console). Image paste still works via a
        # remote source — point the user at the seam instead of warning it's broken.
        echo "  note: no \$WAYLAND_DISPLAY or \$DISPLAY (headless). For prefix + I here,"
        echo "        set @paste-image-clip-command in ~/.config/tmux/local.conf to a"
        echo "        command that emits PNG bytes, e.g. an ssh-back to your desktop's wl-paste."
        return 0
    fi
```

- [ ] **Step 4: Verify the script still parses**

Run: `bash -n plugins/tmux-claude/dotfiles/install.sh && echo "SYNTAX OK"`
Expected: `SYNTAX OK`. Also confirm the clone is gone: `! grep -q jkhas8 plugins/tmux-claude/dotfiles/install.sh && echo "CLONE REMOVED"` → `CLONE REMOVED`.

- [ ] **Step 5: Commit**

```bash
git add plugins/tmux-claude/dotfiles/install.sh
git commit -m "feat(tmux-claude): drop upstream tmux-paste-image clone; headless note points at @paste-image-clip-command"
```

---

## Task 4: Document the option + `local.conf` in the README

**Files:**
- Modify: `plugins/tmux-claude/dotfiles/README.md`

- [ ] **Step 1: Update the scripts bullet (line ~8)**

Find:
```
- `scripts/open-file-from-buffer.sh` — helper invoked by prefix + `o`.
```
Replace with:
```
- `scripts/open-file-from-buffer.sh` — helper invoked by prefix + `o`.
- `scripts/paste-image.sh` — helper invoked by prefix + `I`; saves a clipboard image and types `/image <path>` into a Claude pane. Adapted from [`jkhas8/tmux-paste-image`](https://github.com/jkhas8/tmux-paste-image), extended with the `@paste-image-clip-command` seam (see "Remote / SSH clipboard" below).
```

- [ ] **Step 2: Replace the upstream plugin bullet under "Plugins installed" (line ~14)**

Find:
```
- [`jkhas8/tmux-paste-image`](https://github.com/jkhas8/tmux-paste-image) — prefix + `I` pastes clipboard image as a file path.
```
Replace with:
```
(Image paste — prefix + `I` — is no longer a cloned plugin; it ships as the vendored `scripts/paste-image.sh`, see above.)
```

- [ ] **Step 3: Add a "Remote / SSH clipboard" section before "Claude hooks added" (before line ~16)**

Insert:
```

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
```

- [ ] **Step 4: Update the dependency note (line ~37)**

Find:
```
- Optional (prefix + `I` image-paste into Claude Code): `xclip` on X11, `wl-clipboard` (for `wl-paste`) on Wayland. Linux-only — not supported on macOS/WSL by the upstream plugin. `install.sh` probes for this and prints a distro-specific install hint (`sudo dnf install ...`, `sudo apt install ...`, etc.) if missing.
```
Replace with:
```
- Optional (prefix + `I` image-paste into Claude Code): `xclip` on X11 or `wl-clipboard` (for `wl-paste`) on Wayland for the **local** clipboard. On a **headless/SSH** host, set `@paste-image-clip-command` instead (see "Remote / SSH clipboard"). `install.sh` probes for the local tool and prints a distro-specific install hint if missing.
```

- [ ] **Step 5: Fix the uninstall block (lines ~57-59)**

Find:
```
# Remove config + plugins
rm -f ~/.config/tmux/tmux.conf ~/.tmux/scripts/open-file-from-buffer.sh
rm -rf ~/.tmux/plugins/tmux-agent-indicator ~/.tmux/plugins/tmux-paste-image
```
Replace with:
```
# Remove config + plugins
rm -f ~/.config/tmux/tmux.conf ~/.tmux/scripts/open-file-from-buffer.sh ~/.tmux/scripts/paste-image.sh
rm -rf ~/.tmux/plugins/tmux-agent-indicator
```

- [ ] **Step 6: Commit**

```bash
git add plugins/tmux-claude/dotfiles/README.md
git commit -m "docs(tmux-claude): document @paste-image-clip-command + local.conf; vendored paste-image.sh"
```

---

## Task 5: Bump the plugin version

**Files:**
- Modify: `plugins/tmux-claude/.claude-plugin/plugin.json`

- [ ] **Step 1: Bump version**

Change `"version": "0.6.1"` → `"version": "0.6.2"`.

- [ ] **Step 2: Verify JSON is valid**

Run: `python3 -m json.tool plugins/tmux-claude/.claude-plugin/plugin.json >/dev/null && echo "JSON OK"`
Expected: `JSON OK`.

- [ ] **Step 3: Commit**

```bash
git add plugins/tmux-claude/.claude-plugin/plugin.json
git commit -m "chore(tmux-claude): bump to 0.6.2"
```

---

## Task 6: Deploy + per-node config + end-to-end verification (runbook)

> This task crosses machines and the publish boundary. Steps marked **(user)** are
> the user's call (merge, the physical keypress). The rzw steps use the watchable
> isolated `claude-clip` ssh pane (per the visible-remote-ops convention), never the
> live work sessions.

- [ ] **Step 1: Push the branch and open a PR**

```bash
git push -u origin feat/paste-image-remote-clipboard
gh pr create --fill --title "tmux-claude: remote clipboard image paste over SSH"
```

- [ ] **Step 2: (user) Review + merge the PR** so `origin/main` carries 0.6.2.

- [ ] **Step 3: Update the installed plugin on BOTH nodes**, then re-run the installer so symlinks/config refresh and the obsolete upstream clone can be removed:

On rzdesk (local) and on rzw (via the `claude-clip` pane):
```bash
cd ~/code/alx-skills && git checkout main && git pull --ff-only
# refresh the Claude Code plugin install from the remote (per your normal plugin-update flow)
bash plugins/tmux-claude/dotfiles/install.sh
rm -rf ~/.tmux/plugins/tmux-paste-image   # remove the now-unused upstream clone
```

- [ ] **Step 4: Create the rzw-only `local.conf`** (NOT committed, NOT synced to rzdesk), via the `claude-clip` pane on rzw:

```bash
cat > ~/.config/tmux/local.conf <<'EOF'
# rzw only — pull the clipboard image from rzdesk over the cluster SSH key
set -g @paste-image-clip-command "ssh -o ConnectTimeout=6 -i ~/.ssh/id_cluster alxlenc@10.0.0.2 'XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 wl-paste --type image/png'"
EOF
```

- [ ] **Step 5: Reload tmux on rzw and confirm the option + binding are live**

In the `claude-clip` pane on rzw:
```bash
tmux source-file ~/.config/tmux/tmux.conf
tmux show-option -gv @paste-image-clip-command   # should print the ssh command
tmux list-keys -T prefix | grep paste-image.sh   # prefix I -> paste-image.sh
```

- [ ] **Step 6: Transport unit-check from rzw** (proves the reverse pull yields a real PNG): copy an image on rzdesk first, then in the `claude-clip` pane:
```bash
eval "$(tmux show-option -gv @paste-image-clip-command)" > /tmp/clip-test.png
file /tmp/clip-test.png   # expect: PNG image data
```
Expected: `/tmp/clip-test.png` is a non-empty `PNG image data`.

- [ ] **Step 7: (user) End-to-end:** in a real Claude pane on rzw, copy an image on rzdesk, press `prefix + I`. Expect `/image <rzw-path>` typed into the prompt and the saved file under `~/.cache/tmux-paste-image/` to be a valid PNG.

- [ ] **Step 8: rzdesk regression (user or agent):** on rzdesk (no `local.conf`), copy an image and press `prefix + I` in a Claude pane — local capture must still type `/image …` as before.

---

## Notes / decisions captured
- Keybinding unchanged: `prefix + I`.
- Detection: explicit `@paste-image-clip-command` only (no SSH auto-detect) — see spec "Out of scope".
- `local.conf` is the one deliberate exception to the sync-both-nodes rule: rzw-only, since rzdesk uses the local clipboard.
- Upstreaming the seam to `jkhas8/tmux-paste-image` is out of scope (possible follow-up).
