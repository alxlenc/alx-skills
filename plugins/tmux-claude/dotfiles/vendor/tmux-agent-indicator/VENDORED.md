# Vendored: tmux-agent-indicator

- Upstream: https://github.com/accessd/tmux-agent-indicator
- Commit: `553c3cca8bea6fe17e0709ec04f737417de42141` (main as of 2026-08-16)
- License: MIT (see `LICENSE`)

## Why vendored

The upstream installer downloads its payload from the `main` branch even when
the installer script itself is fetched at a pinned commit, so upstream
refactors (e.g. the removal of `adapters/`) broke `dotfiles/install.sh`
mid-run on every invocation. Vendoring pins the payload to a known-good commit
and removes the network dependency from the install path entirely.

## What is vendored

The subset upstream's `install.sh` copies at install time — `agent-indicator.tmux`,
`setup.sh`, `scripts/`, `hooks/`, `plugins/`, `licenses/`, `README.md`,
`LICENSE` — plus `install.sh` itself. Upstream's `docs/` and `tests/` are not
vendored.

## Local modifications

- `install.sh`: an `install_statusline = False` guard disables upstream's
  takeover of `statusLine` in `~/.claude/settings.json` (it would wrap the
  user's status-line command with its usage-limit renderer). This integration
  manages Claude *hooks* only; the unwrap path is kept so `--uninstall-claude`
  can still remove a wrapper installed by an unpatched upstream run.

## Updating

```bash
git clone https://github.com/accessd/tmux-agent-indicator /tmp/tai
# 1. Review the upstream diff since the commit above.
# 2. Re-copy the file set listed under "What is vendored".
# 3. Re-apply the local modification above.
# 4. Update the commit hash + date in this file, then re-run dotfiles/install.sh.
```
