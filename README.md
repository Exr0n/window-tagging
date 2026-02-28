# window-tagging

Writable window tagging.

The thesis: **windows are the atom**. Not spaces, not apps, not splits. I stopped living in tmux and vim splits because the GUI was obviously the future. This repo makes windows the unit of focus and organization.

What I want from this:
1. Direct window jumping (not spaces, not apps, not positional).
2. Window tagging.
3. Sessions.
4. Auto-sessions, time tracking, auto-reopen by path/URL/etc.

## What it does

Tag a focused window with a key, then jump to that window from anywhere. If the window is gone, you fall back to a workspace with the same key. Tags are stored as files, so the system is durable and easy to inspect.

## Repo layout

- `src/window-tagging.sh` Core library. WM-agnostic.
- `src/set_window_tag.sh` Tag the focused window.
- `src/switch_to_window_or_workspace.sh` Jump to a tagged window or fallback workspace.
- `src/yabai-skhd/backend.sh` Yabai backend (requires `yabai` + `jq`).
- `src/yabai-skhd/install-yabai.sh` Installer for skhd bindings.
- `src/yabai-skhd/install-app-binds.sh` Installer for app launcher bindings in skhd.
- `src/aerospace/backend.sh` AeroSpace backend.
- `src/aerospace/install-aerospace.sh` Installer for AeroSpace bindings.
- `src/aerospace/install-app-binds.sh` Installer for app launcher bindings in AeroSpace.
- `config/window-tagging-binds.toml` Default bind config.

## Install

Clone:

```bash
git clone git@github.com:Exr0n/window-tagging.git ~/.config/window-tagging
```

Or submodule:

```bash
git submodule add git@github.com:Exr0n/window-tagging.git ~/.config/window-tagging
```

### Quick installers

These append bindings if there are no conflicts. If a keybind already exists, the installer aborts and tells you which keys are conflicting.
If the repo is not present at `WINDOW_TAGGING_ROOT`, the installer will clone it.
Installers prompt for which keys/binds to add; the default set is `1-7` and `q w e r`.

Yabai + skhd:

```bash
curl -fsSL https://raw.githubusercontent.com/Exr0n/window-tagging/main/src/yabai-skhd/install-yabai.sh | bash
```

AeroSpace:

```bash
curl -fsSL https://raw.githubusercontent.com/Exr0n/window-tagging/main/src/aerospace/install-aerospace.sh | bash
```

App launcher bindings (from the same config):

```bash
curl -fsSL https://raw.githubusercontent.com/Exr0n/window-tagging/main/src/yabai-skhd/install-app-binds.sh | bash
```

```bash
curl -fsSL https://raw.githubusercontent.com/Exr0n/window-tagging/main/src/aerospace/install-app-binds.sh | bash
```

Installer env vars:

- `WINDOW_TAGGING_ROOT` (default `~/.config/window-tagging`)
- `WINDOW_TAGGING_REPO` (default `https://github.com/Exr0n/window-tagging.git`)
- `SKHD_CONFIG` (default `~/.config/skhd/skhdrc`)
- `AEROSPACE_CONFIG` (defaults to `~/.aerospace.toml` or `~/.config/aerospace/aerospace.toml`)
- `WINDOW_TAGGING_BINDS_CONFIG` (default `~/.config/window-tagging/window-tagging-binds.toml`)
- `WINDOW_TAGGING_USE_GUM` (set to `0` to disable gum prompts if installed)
- `WINDOW_TAGGING_KEYS` (space-separated keys to install, skips prompt)
- `WINDOW_TAGGING_APP_SELECTION` (`all` or space-separated indices, skips prompt)

## Config

Defaults:

- Data dir: `~/.caches/window-tagging`
- Session: `default`
- Session file: `~/.caches/window-tagging/session_name`
- Notifications: on

Override with env vars:

- `WINDOW_TAGGING_DATA_DIR`
- `WINDOW_TAGGING_SESSION`
- `WINDOW_TAGGING_SESSION_FILE`
- `WINDOW_TAGGING_NOTIFICATIONS` (`1` or `0`)
- `WINDOW_TAGGING_BACKEND` (required, path to backend script)

Example:

```bash
export WINDOW_TAGGING_DATA_DIR="$HOME/.caches/window-tagging"
export WINDOW_TAGGING_SESSION="deep-work"
```

## Yabai + skhd integration

Dependencies: `yabai`, `jq`, `skhd`.

Example bindings in `~/.config/skhd/skhdrc`:

```conf
lalt - 1 : WINDOW_TAGGING_BACKEND="$HOME/.config/window-tagging/src/yabai-skhd/backend.sh" $HOME/.config/window-tagging/src/switch_to_window_or_workspace.sh 1
lalt + shift - 1 : WINDOW_TAGGING_BACKEND="$HOME/.config/window-tagging/src/yabai-skhd/backend.sh" $HOME/.config/window-tagging/src/set_window_tag.sh 1
```

Repeat for `2`, `3`, etc.

## AeroSpace integration

Dependency: `aerospace`.

Example bindings in `~/.aerospace.toml`:

```toml
[mode.main.binding]
alt-1 = 'exec-and-forget WINDOW_TAGGING_BACKEND="$HOME/.config/window-tagging/src/aerospace/backend.sh" ~/.config/window-tagging/src/switch_to_window_or_workspace.sh 1'
alt-shift-1 = 'exec-and-forget WINDOW_TAGGING_BACKEND="$HOME/.config/window-tagging/src/aerospace/backend.sh" ~/.config/window-tagging/src/set_window_tag.sh 1'
```

Repeat for `2`, `3`, etc.

If you want AeroSpace to bring a workspace to the current monitor, edit `src/aerospace/backend.sh` and replace `workspace` with `summon-workspace`.

## Binds config

The installers read a single config file for window-tagging keys and app launcher binds:

`~/.config/window-tagging/window-tagging-binds.toml`

If the file doesn’t exist, installers copy `config/window-tagging-binds.toml` into place. Edit it to add/remove keys or app bindings.

This file is intentionally small and hand-editable. You can also use the installers’ prompts to select a subset.

## Notes

- Tags are just files named `window_id_<tag>` in `WINDOW_TAGGING_DATA_DIR/sessions/<session>/`.
- If the tagged window dies, the tag is cleared and you fall back to the workspace.
- Sessions are a string. The default session is `default`, or whatever is in `session_name`.

## Roadmap

- Auto-sessions based on time or active project.
- Time tracking per tag.
- Auto-reopen by app + path/URL.
