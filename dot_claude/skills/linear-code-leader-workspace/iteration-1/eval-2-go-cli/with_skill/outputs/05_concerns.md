# Phase 5: 横断的関心事

ユーザー目的 (CLI から Markdown 描画までを完全に追える) に直結する関心事を中心に、glow リポジトリ全体の方針を 2〜4 行ずつでまとめる。

## エラーハンドリング

- **Go 標準の error 値を上に伝播**するスタイル。`fmt.Errorf("...: %w", err)` で **wrap** しながら呼び出し階層を遡る (`main.go:97, 144, 147, 278, 302, 313, 332, ...`)。カスタムエラー型は無い。
- 公開 entry である Cobra の `rootCmd` は `SilenceErrors: false` + `SilenceUsage: true` (`main.go:54-55`) → エラー時は Cobra が **自前のフォーマットで stderr に表示**し、`main` は `os.Exit(1)` だけする (`main.go:384`)。
- TUI 側 (`ui`) では **error をメッセージにくるんで Bubble Tea のメッセージループに流す**: `errMsg struct{ err error }` (`ui/ui.go:51`) を `tea.Msg` として `Init`/コマンドから返す。`Update` 内で fatal な error を受け取ったら次のキー押下で `tea.Quit` (`ui/ui.go:206-210`)。
- ログレベルとの分担: 非致命的なエラーは `log.Error(...)` でファイルログに書き、TUI は動作継続 (例: `ui/ui.go:167-169`, `ui/pager.go:414`)。

## 認証 / 認可

- glow には **認証の概念がない**。GitHub/GitLab API も **公開 README 取得** 用に未認証で叩く (`github.go:28`, `gitlab.go`)。
- そのため Rate Limit を踏むと普通に `errors.New("can't find README in GitHub repository")` (`github.go:56`) を返して終了する。

## ロギング / 観測性

- ライブラリは `charmbracelet/log`。デフォルトでは `io.Discard` に書く (`log.go:22`) → 終局的にはユーザーのキャッシュディレクトリ (`gap.User`, `glow/glow.log`) にファイル出力 (`log.go:13-37`)。
- レベルは **常に DebugLevel** (`log.go:38`)。コンソールには出ない仕様 (TUI が走るので干渉を避けるため)。
- 失敗時もログを諦めて nil err で空 closer を返す (`log.go:30,34`) → **ログが書けなくても本体は動かす** という設計。
- メトリクスやトレースは無い (CLI なので不要)。

## 設定管理

- 3 段重ね: **環境変数 → YAML (`glow.yml`) → CLI フラグ** がすべて `viper` に統合される (`main.go:413-426`)。
- YAML の置き場所は `go-app-paths` (`gap.User`) が決める。`XDG_CONFIG_HOME` / `GLOW_CONFIG_HOME` で上書き可能 (`main.go:439-445`)。
- TUI 専用設定 (`ui.Config`) は `caarlos0/env` の **構造体タグ (`env:"..."`)** で環境変数から自動マッピング (`ui/config.go:7-19`)。`GLAMOUR_STYLE`, `GLOW_HIGH_PERFORMANCE_PAGER`, `GLOW_ENABLE_GLAMOUR` 等。
- シークレットは扱わない。設定はすべて非機密。

## 永続化

- glow 本体は **ステートレス**。ローカルディスクへの永続化はログ書き込みと `glow config` で書く設定ファイルだけ。
- DB / キャッシュ / state ファイルは無い。

## 非同期 / 並行性

- **CLI モードはすべて同期** (`io.ReadAll` で全文読み → 同期 `Render` → 同期 `fmt.Fprint`)。
- **TUI モードでは goroutine が複数立つ**:
  - Bubble Tea ランタイム本体が `tea.Cmd` (= `func() tea.Msg`) を非同期実行する仕組み。各 `tea.Cmd` は別 goroutine で走り、結果が `Msg` として `Update` の入力チャネルに流される。
  - 例: `findLocalFiles` (`ui/ui.go:357`) → gitcha が結果を `chan SearchResult` に流す → `findNextLocalFile` (`ui/ui.go:400`) が 1 件ずつ吸い出して `foundLocalFileMsg` を返す再帰的なパターン。
  - `renderWithGlamour` (`ui/pager.go:410`) も `func() tea.Msg` 形式で、レンダリング自体を Update から切り離す。
  - `fsnotify.Watcher` で開いているファイルの変更検知 (`ui/pager.go:17, 503`)。

## テスト戦略

- 全部で **わずか 2 テストファイル**: `glow_test.go` (41 行) と `url_test.go` (30 行)。
- スモール / 単体テストのみ。`url.go` の URL 解決ロジックや `main.go` の `validateStyle` のように **純粋関数化されている小さな部分だけ** をテストしている。
- TUI の挙動 (`ui` パッケージ) には自動テストが見当たらない → 振る舞いの変更は手動確認で担保されている前提。
- テストはコードの「動く仕様」として、Phase 4 の代表フローの URL 入力パスを補強できる位置にいる (`url_test.go`)。

## クロスプラットフォーム配慮

- `console_windows.go` (`//go:build windows` 推測) で Windows 用 ANSI 有効化処理が分離。
- `ui/ignore_darwin.go` と `ui/ignore_general.go` で macOS とそれ以外の除外パターンを切替。
- `go-app-paths` で OS ごとの設定 / キャッシュディレクトリを抽象化。

## ターミナル環境の自動検出 (CLI ツールならではのポイント)

これは glow を読むときの **最重要ポイント**:

1. `term.IsTerminal(int(os.Stdout.Fd()))` (`main.go:187`) で stdout が TTY かを判定。
2. **TTY でなく、`-s` 未指定**なら自動的に `style = "notty"` に切替 (`main.go:191`) → 色なし出力に切替。これによりパイプ先 (`glow README.md | cat`) でも壊れない。
3. **TTY なら端末幅を取得し最大 120 に丸める** (`main.go:202-203`)。
4. ダーク/ライトテーマは `lipgloss.HasDarkBackground()` / `termenv.HasDarkBackground()` で背景色を問い合わせる (`utils/utils.go:88`, `ui/ui.go:137`)。

## 終了条件チェック

CLI ツールの「ターミナル環境検出」「設定の 3 段重ね」「Bubble Tea の Cmd 非同期パターン」を 3 行で説明できる → **OK**。
