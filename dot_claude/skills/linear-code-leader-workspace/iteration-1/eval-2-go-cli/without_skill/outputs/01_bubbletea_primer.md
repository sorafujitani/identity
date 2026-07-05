# Bubble Tea 最小限プライマ (glow を読むため版)

Bubble Tea は Elm Architecture を Go に持ち込んだ TUI フレームワーク。
glow を読む上で押さえるべきは **4 つの概念** だけ。

## 1. `tea.Model` インターフェース

```go
type Model interface {
    Init() tea.Cmd               // 起動直後に 1 回呼ばれる。初期コマンドを返す。
    Update(msg tea.Msg) (Model, tea.Cmd)  // 全イベントを処理する純関数。
    View() string                // 現在の Model から画面文字列を生成する純関数。
}
```

ポイント:
- `Update` は **副作用を持たない**。ファイル I/O やネットワークなどは全部
  `tea.Cmd` (= `func() tea.Msg`) として後段に投げる。
- 戻り値の `Model` は新しい状態。値レシーバなので "コピーして書き換えて返す"
  パターンになる (glow も全部このスタイル)。

glow の場合: `ui/ui.go` の `type model struct` がトップレベルの Model。
内部に `stash stashModel` と `pager pagerModel` を持ち、`state` フィールドで
どちらをアクティブにするかを切り替える複合モデル。

## 2. `tea.Msg` (= `interface{}`)

ただの空インターフェース。`Update` で型スイッチして処理する。

glow で重要なメッセージ型 (全部 `ui/` 配下に定義されている):

| Msg 型                       | 発生源                                     | 受け取った時の処理 |
|------------------------------|--------------------------------------------|--------------------|
| `tea.KeyMsg`                 | Bubble Tea 本体 (キー入力)                 | キーバインド処理   |
| `tea.WindowSizeMsg`          | Bubble Tea 本体 (起動 & リサイズ)          | レイアウト計算     |
| `initLocalFileSearchMsg`     | `findLocalFiles` コマンド                  | チャネル登録       |
| `foundLocalFileMsg`          | `findNextLocalFile` コマンド               | stash に追加 → 再帰 |
| `localFileSearchFinished`    | チャネルクローズ時                         | spinner 停止       |
| `fetchedMarkdownMsg`         | `loadLocalMarkdown` コマンド               | レンダ依頼         |
| `contentRenderedMsg`         | `renderWithGlamour` コマンド               | viewport に流す    |
| `reloadMsg`                  | fsnotify Watcher                           | 再読込             |
| `editorFinishedMsg`          | `openEditor` (tea.ExecProcess) コールバック | 再読込             |
| `filteredMarkdownMsg`        | `filterMarkdowns` コマンド                 | filteredMarkdowns 更新 |

## 3. `tea.Cmd` (= `func() tea.Msg`)

副作用の単位。"関数を返す関数" として宣言され、Bubble Tea のランタイムが
別 goroutine で実行し、戻り値の `tea.Msg` を `Update` に再注入する。

glow の典型例 (`ui/ui.go`):

```go
func findLocalFiles(m commonModel) tea.Cmd {
    return func() tea.Msg {
        // gitcha でカレントディレクトリ以下を歩いて *.md を探す
        ch, err := gitcha.FindFilesExcept(cwd, markdownExtensions, ignorePatterns(m))
        if err != nil {
            return errMsg{err}
        }
        return initLocalFileSearchMsg{ch: ch, cwd: cwd}   // ←これが Update に届く
    }
}
```

複数の Cmd をまとめて発射するには `tea.Batch(cmd1, cmd2, ...)` を使う。
glow の `Update` は `cmds []tea.Cmd` に積んで最後に `tea.Batch(cmds...)` を返す
パターンを徹底している。

特殊な Cmd:
- `tea.Quit` … プログラム終了
- `tea.Suspend` … Ctrl+Z でジョブをサスペンド
- `tea.ClearScrollArea` … 高速ページャの再描画
- `tea.ExecProcess` … 外部プロセス (EDITOR 等) を実行して終了後に Msg を返す

## 4. `tea.Program`

ランタイム本体。`tea.NewProgram(model, opts...)` で作り、`.Run()` でメインループ
に入る。glow では `ui/ui.go: NewProgram` がラッパで、

```go
opts := []tea.ProgramOption{tea.WithAltScreen()}   // 代替スクリーン (vim と同じ挙動)
if cfg.EnableMouse {
    opts = append(opts, tea.WithMouseCellMotion())
}
return tea.NewProgram(m, opts...)
```

として `--mouse` フラグがあるときだけマウスを有効化している。

## 5. glow で使われている bubbles 部品

`ui/` のコードに頻出する小コンポーネント (`bubbles` パッケージ提供)。これらも
**それぞれ Model / Update / View を持つ Bubble Tea の小 Model** で、親 Model が
自分の `Update` 内で `child, cmd = child.Update(msg)` のように子に委譲する。

| 部品          | glow での用途                                    | 使用箇所 |
|---------------|--------------------------------------------------|----------|
| `viewport`    | レンダ済 Markdown のスクロール表示               | `pager.go` |
| `spinner`     | ファイル検索中のローディング                     | `stash.go` |
| `paginator`   | stash 一覧のページネーション (ドット表示)        | `stash.go` |
| `textinput`   | filter (検索ボックス) の入力                     | `stash.go` |

## 6. Bubble Tea でよくある誤読を避けるための注意

- **`Update` は値レシーバ**。`m.x = y` してから `return m, cmd` するパターンが
  正解。ポインタレシーバを使うと意図が崩れる。glow も `func (m model) Update(...)`。
- **Cmd は実行を遅延させる**。`Update` の中で I/O を直接やらない。
- **メッセージは型で分岐する**。`switch msg := msg.(type)` が必ず出てくる。
- **`tea.WindowSizeMsg` は起動時にも 1 回来る**。レイアウト初期化を兼ねる。
  glow も `setSize` をここで呼んでいる (`ui/ui.go:264`)。
- **`tea.Batch` の中の Cmd は順序保証なしの並行実行**。シーケンシャルにしたい
  なら `tea.Sequence` を使う (glow は使っていない)。
