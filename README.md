# alx-skills

Personal [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces).

## Plugins

| Plugin | What it does |
|---|---|
| [`tmux-claude`](plugins/tmux-claude/README.md) | Drive tmux from Claude Code: split panes, open windows, send commands, read output, fork tracked tmux windows, and hand off long conversations into fresh Claude sessions. Ships with an opinionated `tmux.conf` and Claude-aware agent-indicator hooks. |

More plugins will be added here over time. Each plugin lives under `plugins/<name>/` and is self-contained — see its own `README.md` for the skills it exposes, dependencies, and install notes.

## Install this marketplace

```bash
# From a local checkout
/plugin marketplace add <path-to-this-repo>

# Or from GitHub once published
/plugin marketplace add <github-user>/alx-skills
```

Then install individual plugins from the table above.

## Repository layout

```
alx-skills/
├── .claude-plugin/marketplace.json   # marketplace manifest
└── plugins/
    └── <plugin-name>/
        ├── .claude-plugin/plugin.json
        ├── README.md
        ├── skills/
        ├── commands/     # optional
        ├── scripts/      # optional, shared across the plugin's skills
        └── dotfiles/     # optional
```

## License

Licensed under the [MIT License](LICENSE). All currently vendored or referenced upstream dependencies (`tmux-agent-indicator`, `tmux-paste-image`, Oh My Tmux, Catppuccin) are also MIT — see the per-plugin `Credits` sections for upstream attribution.
