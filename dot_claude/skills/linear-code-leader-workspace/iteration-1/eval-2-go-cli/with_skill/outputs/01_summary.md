# Phase 1: 鳥瞰 (Orientation)

## 1 行で

`glow` は **Markdown をリッチに端末描画する Go 製 CLI/TUI**。Cobra で CLI を組み、Charm 系ライブラリ群 (Bubble Tea / Glamour / Lipgloss) で TUI レンダリングを行う、薄いラッパー的アプリ。

## 1 段落で (自分の言葉で再記述)

`glow` は、引数なしで起動すると **TUI** モードに入って手元の Markdown を一覧表示・閲覧でき、引数 (ファイルパス・URL・GitHub/GitLab レポ・stdin の `-`) を渡すと **CLI** モードでその Markdown を 1 回だけ整形して標準出力に書き出す、二面性のあるツールである。中核となる Markdown→ANSI 変換は **glamour** ライブラリに完全に委譲しており、glow 本体の責務は (1) ソースの解決 (ファイル / URL / GitHub README API / stdin)、(2) ターミナルの環境検出 (TTY か否か、幅、ダーク/ライト)、(3) 出力先の選択 (直接 stdout / pager / TUI) に絞られている。TUI は **Bubble Tea** (Elm Architecture) を用いて、トップレベル `model` の下に `stash` (ファイル一覧) と `pager` (1 ドキュメント表示) の 2 つのサブモデルが状態 `stateShowStash | stateShowDocument` で切り替わる構造。

## 技術スタック (go.mod から抜粋)

| カテゴリ | 依存 | 役割 |
|---|---|---|
| CLI フレームワーク | `spf13/cobra` | サブコマンド / フラグ |
| 設定管理 | `spf13/viper`, `caarlos0/env/v11` | YAML 設定 + 環境変数 |
| TUI フレームワーク | `charmbracelet/bubbletea` | Elm 風 Model/Update/View |
| TUI ウィジェット | `charmbracelet/bubbles` | viewport / spinner / paginator / textinput |
| スタイル | `charmbracelet/lipgloss` | ANSI スタイリング DSL |
| **描画エンジン** | `charmbracelet/glamour` | **Markdown→ANSI 変換 (core)** |
| ファイル探索 | `muesli/gitcha` | .gitignore 対応ローカル検索 |
| ファイル監視 | `fsnotify/fsnotify` | 再描画トリガー (TUI) |
| ログ | `charmbracelet/log` | 構造化ログ (file 出力) |
| ヘルパー | `mvdan.cc/sh/v3/shell`, `atotto/clipboard`, ... | PAGER 解釈, クリップボードなど |

## エントリポイント

- **`/tmp/eval-2/glow/main.go:376` `func main()`** — `setupLog` → `rootCmd.Execute()` の 2 行だけ。
- `rootCmd` は同ファイル `main.go:48` で宣言、`RunE: execute` (`main.go:224`) が実体。
- サブコマンド: `configCmd` (`config_cmd.go:28`) と `manCmd` (`man_cmd.go:12`) が `init()` で `rootCmd.AddCommand` される。

## ディレクトリツリー (役割注釈付き)

```
glow/
├── main.go                   # エントリポイント + Cobra root command + CLI 経路 + TUI 起動 (executeCLI/runTUI)
├── config_cmd.go             # `glow config` サブコマンド (YAML を $EDITOR で開く)
├── man_cmd.go                # `glow man` サブコマンド (隠し: manpage 生成)
├── log.go                    # キャッシュディレクトリにファイルログを開く
├── style.go                  # lipgloss のスタイル: keyword/paragraph (ヘルプ装飾)
├── url.go                    # github.com/foo/bar → URL 解決の振り分け
├── github.go                 # GitHub API で README ファイル名を解決
├── gitlab.go                 # GitLab API で README ファイル名を解決
├── console_windows.go        # Windows 用 ANSI 有効化 (build tag)
├── glow_test.go / url_test.go
├── go.mod / go.sum / Taskfile.yaml / Dockerfile / README.md / LICENSE
│
├── ui/                       # TUI 全部入り (Bubble Tea で動く)
│   ├── ui.go                 # トップレベル Model: stash/pager を束ねる + Init/Update/View
│   ├── config.go             # ui.Config 構造体 (env tag で環境変数読込)
│   ├── markdown.go           # 内部表現 markdown{path, body, modtime, ...}
│   ├── pager.go              # 1 ドキュメント表示 (viewport ラップ) + glamourRender
│   ├── stash.go              # ファイル一覧画面 (一番大きい・891行)
│   ├── stashhelp.go          # stash ヘルプ表示
│   ├── stashitem.go          # stash の各アイテム描画
│   ├── styles.go             # ui 共通の lipgloss スタイル
│   ├── keys.go               # 定数キーバインド
│   ├── sort.go               # ファイル一覧のソート
│   ├── editor.go             # 外部エディタ起動 (`e` キー)
│   ├── ignore_darwin.go / ignore_general.go  # 検索除外パターン (OS 別)
│
└── utils/
    └── utils.go              # RemoveFrontmatter / IsMarkdownFile / ExpandPath / GlamourStyle / WrapCodeBlock
```

## CI / ビルド (Taskfile.yaml, .github/workflows/ から推測)

`go build` で単一バイナリ。`goreleaser` で配布。`go test` でテストは小規模 (`glow_test.go`, `url_test.go` 計 71 行)。

## このフェーズで読まなかったもの (意図的)

- `ui/stash.go` の細部 (891 行): Phase 4 の代表フローは CLI モードなので、TUI 一覧の細部は Phase 5 でも触れない。
- `glamour` 内部: glow から見れば不透明箱。「`r := glamour.NewTermRenderer(opts...); r.Render(markdown)` で ANSI 文字列が返る」とだけ理解する。
- `gitcha` 内部: Markdown ファイル探索だけが責務、TUI モードでだけ動く。

## 終了条件チェック

「これが何のコードか」を 1 段落で説明可能 → **OK**。
