# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal Neovim configuration for macOS. Plugin management via Lazy.nvim, using Neovim 0.11+ built-in LSP features.

This directory is managed by chezmoi. The source repository is github.com/sorafujitani/dotfiles (`~/.local/share/chezmoi/dot_config/nvim/`). Edit files here, then sync with `chezmoi re-add ~/.config/nvim`. Deleted files must also be removed from the source state with `chezmoi forget`.

## Commands

```bash
# Reload config (inside Neovim)
:source %

# Plugin management
:Lazy sync          # Update plugins
:Lazy health        # Check status

# Health check
:checkhealth

# LSP info
:LspInfo            # Show attached LSP client details
:LspRestart [name]  # Restart LSP (all if name omitted)
:LspStop [name]     # Stop LSP

# Measure startup time
nvim --startuptime /tmp/startup.log && tail -30 /tmp/startup.log
```

## Architecture

```
init.lua                    # Entry point
├── lua/config/lazy.lua     # Lazy.nvim setup + plugin declarations
├── lua/core/
│   ├── options.lua         # vim.opt settings (leader=" ")
│   ├── autocmds.lua        # Autocommands
│   ├── commands.lua        # Custom commands (Sed, Cfp, Crp, Fmt, etc.)
│   └── file-watch.lua      # libuv fs_event によるバッファ監視
├── lua/keymaps/
│   ├── init.lua            # Base keymaps + submodule loader
│   ├── lsp.lua             # LSP keymaps ([d, ]d, gi, gt, <leader>a, etc.)
│   ├── picker.lua          # snacks.picker (gd, gr, <C-p>, <C-g>, etc.)
│   ├── git.lua             # Git operations
│   ├── terminal.lua        # snacks.terminal
│   ├── debug.lua           # DAP (lazy-loaded)
│   └── test.lua            # Neotest (lazy-loaded)
├── lua/lsp/
│   ├── init.lua            # Enable servers via vim.lsp.enable()
│   └── diagnostics.lua     # Diagnostic settings
├── lua/plugins/
│   └── *.lua               # Per-plugin configuration
├── lua/ui/
│   └── highlights.lua      # Highlight settings
└── lsp/
    └── *.lua               # LSP server configs (vim.lsp.Config format)
```

## LSP Configuration

Uses Neovim 0.11+ `vim.lsp.config()` / `vim.lsp.enable()`.

Server configs live in the `lsp/` directory:
```lua
-- Example: lsp/ts_ls.lua
---@type vim.lsp.Config
return {
  cmd = { 'typescript-language-server', '--stdio' },
  filetypes = { 'javascript', 'typescript', ... },
  root_markers = { 'package.json', 'tsconfig.json' },
}
```

Enabled servers: lua_ls, ts_ls, denols, biome, rust_analyzer, ruby_lsp, rfmt, gopls, ty, nil_ls

**Note:** denols only starts when `deno.json` is present (via root_markers)

## Lazy Loading Strategy

Default is `lazy = true`; snacks loads on first `require("snacks")` (keymaps etc.).

- **Immediate** (`lazy = false`): vim-orbital (colorscheme)
- **VeryLazy**: lualine, flash, mini.surround, nerdfont
- **BufReadPost / BufNewFile**: treesitter (main branch, highlight/indent は FileType autocmd で起動), auto-save (okuuva/auto-save.nvim)
- **BufReadPre**: gitsigns
- **InsertEnter**: blink.cmp, mini.snippets, mini.pairs, copilot
- **TextYankPost**: vim-yoink
- **ft**: render-markdown (markdown), lazydev (lua), nvim-dap-go (go)
- **Keys**: mini.comment (`gc`), Oil (`<S-e>`), flash (`s` / `S`)
- **Commands**: Rg, Git/GitBlame, Neogit, Diffview, BlameToggle, Atac, RaySo, Fyler, ConformInfo, Neotest, MiniTest
- DAP/Neotest are manually loaded via `:DapLoad` / `:NeotestLoad`

## Key Bindings

### LSP
| Key | Description |
|-----|-------------|
| `gd` | Go to definition (picker) |
| `gr` | List references (picker) |
| `gi` | Go to implementation |
| `gt` | Go to type definition |
| `K` | Hover documentation |
| `<leader>a` | Code action |
| `[d` / `]d` | Previous / next diagnostic |
| `<leader>dd` | Show diagnostic float |
| `<leader>dl` | Diagnostic list |

### Picker (snacks.picker)
| Key | Description |
|-----|-------------|
| `<C-p>` | Find files |
| `<C-g>` | Grep |
| `<C-f>` | Search lines in buffer |
| `<C-b>` | List buffers |
| `<C-l>` | Recent files |
| `<leader>sw` | Grep word under cursor |
| `<leader>ds` | Document symbols |
| `<leader>ws` | Workspace symbols |

## Custom Commands

| Command | Description |
|---------|-------------|
| `:Sed old new` | Global search and replace |
| `:Cfp` | Copy full path |
| `:Crp` | Copy relative path (with optional line number) |
| `:Cfn` | Copy filename |
| `:Fmt` | Format via conform.nvim |
| `:LspRestart [name]` | Restart LSP |
| `:LspStop [name]` | Stop LSP |
| `:NotePush` | Run git add/commit/push in one shot |
