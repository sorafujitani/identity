# WezTerm Config

WezTerm terminal configuration for macOS.

## Overview

- **Font**: Hack Nerd Font (14pt)
- **Color Scheme**: Ef-Night
- **Translucent Background**: opacity 0.92 + blur 20
- **Tab Bar**: Minimal style (matches color scheme)
- **IME**: Enabled
- **Leader Key**: `Ctrl+A`

### Key Bindings

| Key | Action |
|---|---|
| `Cmd+Shift+R` | Reload config |
| `Cmd+W` | Close pane |
| `Cmd+,` | Split vertically |
| `Cmd+.` | Split horizontally |
| `Shift+Arrow` | Navigate panes |
| `Cmd+Left/Right` | Switch workspace |
| `Alt+9` | Workspace list (Fuzzy) |
| `Ctrl+N` | Toggle pane zoom |

## Setup

### 1. Install WezTerm

```bash
brew install --cask wezterm
```

### 2. Install Font

```bash
brew install --cask font-hack-nerd-font
```

### 3. Clone Config

```bash
git clone <repo-url> ~/.config/wezterm
```

If `~/.config/wezterm` already exists, back it up first:

```bash
mv ~/.config/wezterm ~/.config/wezterm.bak
git clone <repo-url> ~/.config/wezterm
```

Launch WezTerm and the config will be loaded automatically.

## wlay - Overlay Pane Command

A shell script that opens an overlay pane by combining `split-pane` + `zoom-pane` to cover the current pane. The overlay pane auto-closes on program exit, restoring the original pane.

### Usage

| Command | Action |
|---|---|
| `wlay` / `wlay sh` | Open zsh |
| `wlay nv` | Open nvim |
| `wlay nv file.lua` | Open file in nvim |
| `wlay git` | Open lazygit |

Any argument other than the subcommands (`sh`, `nv`, `git`) is executed as-is (e.g. `wlay htop`).

### Setup

Create a symlink in `~/.config/scripts/` and add it to PATH:

```bash
mkdir -p ~/.config/scripts
ln -s ~/.config/wezterm/wlay ~/.config/scripts/wlay
```

Add to `~/.zshrc`:

```bash
export PATH="$HOME/.config/scripts:$PATH"
```
