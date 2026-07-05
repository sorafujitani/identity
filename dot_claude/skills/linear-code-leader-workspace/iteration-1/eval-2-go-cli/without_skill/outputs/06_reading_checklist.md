# 読書チェックリスト & 演習

3 時間で "実行フローを完全に追える" になるためのマイルストーン。各項目に
**自分の言葉で答えられるか** を測ること。

## フェーズ A: 全体像 (30 分)

- [ ] `glow --help` で表示されるフラグと、対応する viper キーが頭に入っている
      → `main.go: init()` の `BindPFlag` 群を読む
- [ ] `cobra.Command` の `PersistentPreRunE` と `RunE` の役割を区別できる
- [ ] glow の 2 大モード (CLI / TUI) がコード上のどこで分岐するか即答できる
      → `main.go: execute()` の switch
- [ ] glow と glamour の責任境界 (=入力解決 vs レンダ本体) を 1 文で言える

## フェーズ B: CLI モード (40 分)

- [ ] `sourceFromArg` の優先順位 5 段を順番に挙げられる
- [ ] `utils.RemoveFrontmatter` がどんな正規表現でフロントマターを検出している
      か言える。先頭以外の `---` ペアを誤検出しないのはなぜか?
      ヒント: `frontmatterBoundaries[0] == 0` チェック
- [ ] `utils.IsMarkdownFile` が **拡張子なしを markdown 扱い** にする理由を
      想像できる (例: `README` がよくある)
- [ ] `utils.GlamourStyle(style, isCode=true)` で `CodeBlock.Margin = 0` に
      してるのはなぜか? → `WrapCodeBlock` で囲んだ時にインデントが二重に
      なるのを避けるため
- [ ] `--pager` 経路で `mvdan.cc/sh/v3/shell` を使う必要があるのはなぜか?
      → `PAGER="less -r --quit-at-eos"` のような shell ライク文字列を引数
        配列に分解するため
- [ ] **演習**: `glow -p README.md` 実行時の goroutine 構成を描いてみる
      (`exec.Command.Run` で less プロセス + 親プロセスで `strings.NewReader`
       が読まれる)

## フェーズ C: Bubble Tea 入門 (20 分)

- [ ] `tea.Model` の 3 メソッドの呼ばれる回数とタイミングを言える
      (Init=1, Update=毎メッセージ, View=毎フレーム)
- [ ] `tea.Cmd` が "Bubble Tea が別 goroutine で実行する関数" だと納得できる
- [ ] `tea.Batch` と `tea.Sequence` の違いを言える (Batch=並行、Sequence=逐次)
- [ ] glow の `model` が **値レシーバ** で `Update` を実装している理由を言える
      → 値レシーバなら "コピーを変更して返す" Elm 流の不変更新が自然
- [ ] **演習**: `Init() → Update(initLocalFileSearchMsg) → Update(foundLocalFileMsg)
      → ...` のメッセージ列をホワイトボードに書ける

## フェーズ D: TUI モード (50 分)

- [ ] `newModel` の path 分岐 3 通り (空+content, 空+no content=cwd, ファイル,
      ディレクトリ) を全部追える
- [ ] `findLocalFiles` → `initLocalFileSearchMsg` → `findNextLocalFile` →
      `foundLocalFileMsg` → 再帰 という生産者-消費者ループを図示できる
- [ ] **なぜ `findNextLocalFile` の中でチャネル受信をブロックしていいのか**
      を Bubble Tea ランタイムの観点で説明できる (Cmd 単位で goroutine 別)
- [ ] `loadLocalMarkdown` が `md` ポインタを介して Body を書き換える設計の
      利点と注意点を言える (利点: 既存 markdown オブジェクトの参照を維持。
      注意: 並行アクセスはしない前提)
- [ ] `pager.glamourRender` が `WindowSizeMsg` のたびに **毎回呼ばれる** こと
      に気づいた (`pager.go:269-270`)。重そうだが、glamour 自体が十分速い
      前提
- [ ] `viewport.HighPerformanceRendering` モードで `viewport.Sync` を発射
      しないと再描画されない理由を `bubbles/viewport` の README で確認しても
      よい
- [ ] **演習**: `glow .` 起動から README.md が表示されるまでに `Update` が
      呼ばれる回数 (おおよそ) を数える

## フェーズ E: 横断的関心事 (30 分)

- [ ] 設定の優先順位: CLI flag > 環境変数 (`GLOW_*`) > yaml > default を
      コードで追える (`main.go: tryLoadConfigFromDefaultPlaces` + `viper.BindPFlag`)
- [ ] `~/.cache/glow/glow.log` に何が出るか (`log.go`, log.Info / log.Debug 呼び出し)
- [ ] fsnotify の監視は **ファイル自体ではなく親ディレクトリ** に対して張る
      理由 (`pager.go: localDir()`) — エディタが atomic save する場合にファイル
      自体の watch が消えるのを避けるため
- [ ] `console_windows.go` (build tag `windows`) で `golang.org/x/sys/windows`
      の `EnableVirtualTerminalProcessing` を立てている理由

## フェーズ F: 自分で動かす (30 分)

- [ ] `git checkout -b reading` してビルド: `go build .`
- [ ] `./glow README.md` → CLI モードを確認
- [ ] `./glow -p README.md` → pager モード
- [ ] `./glow -t README.md` → CLI で読んだのを TUI に流すモード
- [ ] `./glow .` → 一覧モード。`/` で fuzzy 検索、Enter で開く
- [ ] `./glow github://charmbracelet/bubbletea` → README フェッチ
- [ ] 試しに `pager.go: setContent` の前に `log.Info("content", "len", len(s))`
      を入れて、`GLOW_HIGH_PERFORMANCE_PAGER=false ./glow .` で
      `tail -f ~/.cache/glow/glow.log` を見る

## 詰まった時のヒント

- **"この Msg どこから来るの?"** → `grep -rn "MsgName" .` でファクトリと
  受信箇所が全部出る (glow は型名が一意なので grep が効く)
- **"この Cmd は何を返す?"** → `func() tea.Msg { ... return ??? }` の最後の
  return を読む
- **"なんで View() の中で state を見てるの?"** → glow は state machine。
  state ごとに完全に違うレイアウトを描画する
- **Bubble Tea 公式 tutorial** (https://github.com/charmbracelet/bubbletea/tree/main/tutorials)
  の `commands` と `basics` を 30 分やると一気に解像度が上がる

## 学習の停止条件 (これができたら卒業)

紙とペンだけで:

1. `glow ~/README.md` 実行時の関数呼び出しを `main()` から `fmt.Fprint` まで
   全部書ける
2. `glow .` 実行時のメッセージ列を、`Init` → `WindowSize` → `initLocal...`
   → 任意の数の `foundLocal...` → `localFileSearchFinished` → ... → `Enter`
   → `fetchedMarkdownMsg` → `contentRenderedMsg` まで再現できる
3. glamour に渡る `markdown string` の中身がどんな前処理を受けているか
   (`RemoveFrontmatter`, `WrapCodeBlock`) を即答できる
