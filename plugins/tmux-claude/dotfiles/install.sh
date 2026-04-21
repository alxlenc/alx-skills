#!/usr/bin/env bash
# Install tmux-claude dotfiles: config, scripts, and third-party plugins.
#
# What it does:
#   - Symlinks tmux.conf to ~/.config/tmux/tmux.conf (backs up any existing file)
#   - Symlinks helper scripts into ~/.tmux/scripts/
#   - Installs tmux-agent-indicator (files + Claude hooks in ~/.claude/settings.json)
#   - Git-clones tmux-paste-image into ~/.tmux/plugins/
#   - Warns (without touching) if a legacy ~/.tmux.conf exists that tmux will now ignore
#
# Flags:
#   --no-hooks   Skip Claude hook installation (agent-indicator still installed).
#
# Re-running is safe: symlinks are refreshed, plugin checkouts are `git pull`-ed,
# existing real files are backed up to <path>.bak.<timestamp>, and hook merging
# is idempotent (deduplicates itself).

set -euo pipefail

BASE_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
STAMP="$(date +%Y%m%d-%H%M%S)"

INSTALL_HOOKS=true
for arg in "$@"; do
    case "$arg" in
        --no-hooks) INSTALL_HOOKS=false ;;
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

backup_if_regular() {
    local path="$1"
    if [ -e "$path" ] && [ ! -L "$path" ]; then
        local backup="${path}.bak.${STAMP}"
        echo "  backup: $path -> $backup"
        mv "$path" "$backup"
    elif [ -L "$path" ]; then
        rm "$path"
    fi
}

link() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    backup_if_regular "$dst"
    ln -s "$src" "$dst"
    echo "  linked: $dst -> $src"
}

clone_or_update() {
    local repo="$1" dst="$2"
    if [ -d "$dst/.git" ]; then
        echo "  update: $dst"
        git -C "$dst" pull --ff-only --quiet
    else
        echo "  clone:  $repo -> $dst"
        mkdir -p "$(dirname "$dst")"
        git clone --quiet --depth 1 "$repo" "$dst"
    fi
}

check_legacy_tmux_conf() {
    # tmux prefers ~/.config/tmux/tmux.conf over ~/.tmux.conf when both exist,
    # so a pre-existing legacy file becomes dead weight after this installer
    # writes to the XDG path. Warn so the user can clean up if they want.
    local legacy="$HOME/.tmux.conf"
    if [ -e "$legacy" ] && [ ! -L "$legacy" ]; then
        echo
        echo "  WARN: '$legacy' exists and is a regular file."
        echo "        tmux now loads '$HOME/.config/tmux/tmux.conf' instead — '$legacy' is no longer active."
        echo "        Rename or remove it to avoid confusion, e.g.:"
        echo "          mv '$legacy' '$legacy.bak.$STAMP'"
    fi
}

check_clipboard_tool() {
    # tmux-paste-image needs xclip (X11) or wl-paste (Wayland). Probe, and if
    # missing, print an actionable install hint for the current distro.
    local uname_s
    uname_s="$(uname -s 2>/dev/null || echo unknown)"

    if [ "$uname_s" = "Darwin" ]; then
        echo "  WARN: tmux-paste-image's image-paste workaround doesn't support macOS."
        echo "        Prefix + I binding will be installed but won't capture clipboard images."
        return 0
    fi
    if [ "$uname_s" != "Linux" ]; then
        echo "  WARN: unsupported OS ($uname_s) — tmux-paste-image needs X11 or Wayland."
        return 0
    fi

    local want=""
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        want="wl-paste"
    elif [ -n "${DISPLAY:-}" ]; then
        want="xclip"
    else
        # No display server detected (headless SSH, console, etc.). Warn and stop.
        echo "  WARN: no \$WAYLAND_DISPLAY or \$DISPLAY detected — tmux-paste-image needs"
        echo "        xclip (X11) or wl-clipboard (Wayland) to capture clipboard images."
        return 0
    fi

    if command -v "$want" >/dev/null 2>&1; then
        echo "  ok:   clipboard tool found ($want)"
        return 0
    fi

    # Missing — print a distro-aware install hint.
    local distro_id=""
    if [ -r /etc/os-release ]; then
        distro_id="$(. /etc/os-release && echo "${ID_LIKE:-$ID}" | awk '{print $1}')"
    fi

    local pkg_x11="xclip"
    local pkg_wayland="wl-clipboard"
    local pkg
    if [ "$want" = "wl-paste" ]; then pkg="$pkg_wayland"; else pkg="$pkg_x11"; fi

    local hint=""
    case "$distro_id" in
        fedora|rhel|centos)    hint="sudo dnf install $pkg" ;;
        debian|ubuntu)         hint="sudo apt install $pkg" ;;
        arch|manjaro)          hint="sudo pacman -S $pkg" ;;
        opensuse*|suse)        hint="sudo zypper install $pkg" ;;
        alpine)                hint="sudo apk add $pkg" ;;
        *)                     hint="install '$pkg' via your distro's package manager" ;;
    esac

    echo "  WARN: '$want' not found — prefix + I will not be able to read clipboard images."
    echo "        Install hint: $hint"
}

echo "==> tmux config"
link "$BASE_DIR/config/tmux.conf" "$HOME/.config/tmux/tmux.conf"

echo "==> tmux scripts"
for script in "$BASE_DIR"/scripts/*.sh; do
    link "$script" "$HOME/.tmux/scripts/$(basename "$script")"
done

echo "==> tmux-agent-indicator (plugin + Claude hooks)"
AGENT_INSTALLER_ARGS=(--no-codex --no-opencode)
if [ "$INSTALL_HOOKS" = false ]; then
    AGENT_INSTALLER_ARGS+=(--no-claude)
    echo "  --no-hooks: skipping Claude settings.json hook setup"
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "  ERROR: curl is required to install tmux-agent-indicator. Install curl and re-run." >&2
    exit 1
fi
curl -fsSL https://raw.githubusercontent.com/accessd/tmux-agent-indicator/main/install.sh \
    | bash -s -- "${AGENT_INSTALLER_ARGS[@]}"

echo "==> tmux-paste-image"
clone_or_update "https://github.com/jkhas8/tmux-paste-image.git" "$HOME/.tmux/plugins/tmux-paste-image"
check_clipboard_tool

check_legacy_tmux_conf

echo
echo "Done."
echo "  Reload tmux:          tmux source-file ~/.config/tmux/tmux.conf"
echo "  Or inside tmux:       <prefix> r"
if [ "$INSTALL_HOOKS" = true ]; then
    echo "  Claude hooks live at: ~/.claude/settings.json (UserPromptSubmit, PermissionRequest, Stop)"
    echo "  Agent states:         running / needs-input / done — shown in window title & pane border"
fi
