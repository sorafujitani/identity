# glow 全体構成マップ

## 1. ディレクトリツリー (重要ファイルのみ)

```
glow/
├── main.go              # cobra root cmd, sourceFromArg, execute, executeCLI, runTUI, init
├── config_cmd.go        # `glow config` サブコマンド (EDITOR で yaml を開く)
├── man_cmd.go           # `glow man` (manpage 生成)
├── url.go               # github:// / gitlab:// URL の解決、isURL
├── github.go            # GitHub API で README を見つける
├── gitlab.go            # GitLab 用
├── log.go               # ~/.cache/glow/glow.log にログ出力
├── style.go             # ヘルプ文中のスタイル (緑色キーワード等)
├── glow_test.go         # ごく小さなテスト
├── console_windows.go   # Windows でだけ ANSI を有効化する初期化
├── utils/
│   └── utils.go         # RemoveFrontmatter, IsMarkdownFile, WrapCodeBlock, GlamourStyle
└── ui/                  # ★ TUI まわり全部
    ├── ui.go            # ルート Model (state, stash, pager の切替)
    ├── config.go        # Config 構造体 (env タグ付き)
    ├── stash.go         # 一覧画面の Model (paginator + filter + spinner)
    ├── stashitem.go     # 一覧の 1 項目の View
    ├── stashhelp.go     # 一覧画面のヘルプ
    ├── pager.go         # 本文画面の Model (viewport + fsnotify + statusbar)
    ├── markdown.go      # 内部表現 markdown struct と相対時刻表示
    ├── editor.go        # EDITOR を tea.ExecProcess で起動
    ├── keys.go          # キー名定数 (enter, esc) だけ
    ├── styles.go        # lipgloss スタイル定義
    ├── sort.go          # markdowns を Modtime でソート
    ├── ignore_general.go / ignore_darwin.go  # gitcha の除外パターン
```

## 2. 依存ライブラリの役割

| パッケージ                               | 何を担うか                                      |
|------------------------------------------|------------------------------------------------|
| `github.com/spf13/cobra`                 | CLI フレームワーク (root cmd + subcommands)    |
| `github.com/spf13/viper`                 | 設定ファイル / env / flag の統合               |
| `github.com/caarlos0/env/v11`            | 環境変数を struct タグで読む (`ui.Config`)     |
| `github.com/muesli/go-app-paths` (gap)   | XDG 準拠の config dir / cache dir 取得         |
| `github.com/charmbracelet/glamour`       | **Markdown → ANSI 端末出力** の本体           |
| `github.com/charmbracelet/bubbletea`     | Elm Architecture TUI フレームワーク            |
| `github.com/charmbracelet/bubbles`       | viewport / paginator / spinner / textinput     |
| `github.com/charmbracelet/lipgloss`      | スタイル DSL (色、余白、ボーダー)              |
| `github.com/charmbracelet/log`           | 構造化ログ                                     |
| `github.com/charmbracelet/x/editor`      | `$EDITOR` をクロスプラットフォームで起動       |
| `github.com/muesli/gitcha`               | `.gitignore` を尊重した再帰ファイル検索        |
| `github.com/muesli/termenv`              | 端末機能検出 (ダーク背景判定など)              |
| `github.com/fsnotify/fsnotify`           | ファイルの変更を検知して自動再読込             |
| `github.com/sahilm/fuzzy`                | filter モードの fuzzy 検索                     |
| `mvdan.cc/sh/v3/shell`                   | `$PAGER` を shell ライクに分割 (`less -r` 等) |
| `github.com/atotto/clipboard`            | OS のクリップボードに本文をコピー (`c` キー)   |
| `golang.org/x/term`                      | 端末判定 (`isatty`) と幅取得                   |

## 3. 実行モードの分岐 (鳥瞰)

`main.go: execute()` が分岐の中心:

```
                      execute(cmd, args)
                            │
   ┌────────────────────────┼────────────────────────┐
   │                        │                        │
stdin が pipe?         len(args)==0            len(args)==1 で
   │ Yes                    │                  かつ args[0] がディレクトリ
   ▼                        ▼                        ▼
executeCLI            runTUI("", "")           runTUI(absPath, "")
(stdin から読む)      (cwd を一覧)             (指定ディレクトリを一覧)
                                                     │ No (ファイルや URL)
                                                     ▼
                                          executeArg → executeCLI
                                          (1 ファイルを直接レンダ)
```

さらに `executeCLI` の中で `--pager` / `--tui` フラグによって出力先が変わる:

```
executeCLI
  ├─ pager フラグ → exec.Command(PAGER) に stdin 経由で流す
  ├─ tui フラグ   → runTUI(path, content)  (CLI で読んだ内容を TUI で表示)
  └─ default     → fmt.Fprint(w, out)      (普通に stdout に出す)
```

## 4. データの流れ (1 行サマリ)

CLI モード:
```
arg → sourceFromArg → io.Reader → io.ReadAll → []byte
    → RemoveFrontmatter → glamour.TermRenderer.Render → string → Stdout / pager / TUI
```

TUI モード (一覧経由の場合):
```
gitcha 検索 → foundLocalFileMsg → stash.markdowns に追加
ユーザが Enter → loadLocalMarkdown (os.ReadFile) → fetchedMarkdownMsg
              → renderWithGlamour → contentRenderedMsg → viewport.SetContent
              → pager.View() で毎フレーム描画
```

## 5. 状態 (state machine)

`ui/ui.go` のトップレベル `state`:
```
stateShowStash  ←→  stateShowDocument
   ↑ esc / left / h / delete
   ↓ Enter (一覧から開く)
```

`pager.go` の `pagerState`:
```
pagerStateBrowse  →  pagerStateStatusMessage  → (3 秒タイマで戻る)
```

`stash.go` の `stashViewState`:
```
stashStateReady → stashStateLoadingDocument → (fetchedMarkdownMsg で抜ける)
              → stashStateShowingError
```

`stash.go` の `filterState`:
```
unfiltered  →[/]→  filtering  →[Enter]→  filterApplied  →[esc]→ unfiltered
```
