# identity

sorafujitani の dotfiles。[chezmoi](https://www.chezmoi.io/) で管理する。

以下の分散していた repo を統合したもの。

| 旧 repo | 管理対象 |
|---|---|
| neovimdot | `~/.config/nvim` |
| ghosttydot | `~/.config/ghostty` |
| herdrdot | `~/.config/herdr` |
| weztermdot | `~/.config/wezterm` |
| codexdot | `~/.codex`（AGENTS.md / agents / hooks.json / herdr-agent-state.sh / plans） |

## セットアップ

```sh
brew install chezmoi
chezmoi init https://github.com/sorafujitani/identity.git
chezmoi diff    # 適用内容の確認
chezmoi apply
```

## 日常操作

```sh
chezmoi add ~/.config/nvim/init.lua   # ローカルの変更をソースに取り込む
chezmoi diff                          # ソースとローカルの差分
chezmoi apply                         # ソースをローカルに反映
chezmoi cd                            # ソース repo (このrepo) に入って git 操作
```

ソースディレクトリは `~/.local/share/chezmoi`。`dot_` プレフィックスが `.` に対応する（`dot_config/nvim` → `~/.config/nvim`）。
