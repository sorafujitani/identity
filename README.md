# identity

Dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## What's inside

| Path | Description |
|---|---|
| `~/.config/nvim` | Neovim |
| `~/.config/wezterm` | WezTerm |
| `~/.config/ghostty` | Ghostty |
| `~/.config/herdr` | herdr |
| `~/.codex` | Codex CLI (AGENTS.md, agents, hooks, plans) |
| `~/.claude` | Claude Code user scope (CLAUDE.md, settings, agents, commands, skills) |

## Setup

```sh
brew install chezmoi
chezmoi init https://github.com/sorafujitani/identity.git
chezmoi diff    # preview
chezmoi apply
```

## Daily usage

```sh
chezmoi add <file>   # capture local changes into the source
chezmoi diff         # diff between source and local
chezmoi apply        # apply source to local
chezmoi cd           # enter the source repo for git operations
```

The source directory is `~/.local/share/chezmoi`. The `dot_` prefix maps to `.` (`dot_config/nvim` → `~/.config/nvim`).
