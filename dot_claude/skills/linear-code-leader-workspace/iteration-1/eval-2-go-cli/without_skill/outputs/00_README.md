# charmbracelet/glow コードリーディングガイド

このディレクトリは、`glow` (Go 製 Markdown レンダラ CLI) のソースを 3 時間で
"CLI 起動 → Markdown 描画完了" の実行フローを完全に追えるレベルまで読み解くため
の手引きです。Bubble Tea (charm 系 TUI ライブラリ) を初めて触る人向け。

## 読む順番 (推奨)

1. **`01_bubbletea_primer.md`**
   Bubble Tea の Elm Architecture (Model / Msg / Cmd / Program) を最小限の語彙で。
   glow のコードに出てくる `tea.Model`, `tea.Cmd`, `tea.Msg`, `tea.Batch` などが
   全部ここで腑に落ちる。所要 20 分。

2. **`02_overview_architecture.md`**
   glow のディレクトリ構成・依存パッケージ・実行モード (CLI / TUI / Pager) の
   全体像。"どこに何があるか" のマップ。所要 15 分。

3. **`03_flow_cli_render.md`**
   **メインの成果物**。`main()` から Markdown が `os.Stdout` に書き出されるまで
   の CLI モードの実行フローを、関数呼び出しと該当行番号付きでステップごとに
   解説。引数解析 → ソース解決 → glamour レンダリング → 出力先分岐 まで。
   所要 50 分。

4. **`04_flow_tui_render.md`**
   TUI モードのフロー。`runTUI()` → `tea.Program.Run()` → `model.Init()` →
   `Update` ループ → ファイル発見 → 読み込み → glamour レンダ → viewport
   描画 まで。Bubble Tea のメッセージパッシングを追う実例。所要 40 分。

5. **`05_call_graph.md`**
   両モードを 1 枚にまとめた呼び出しグラフ (テキスト版) と、主要 message
   型一覧。リファレンスとして手元に置く用。所要 10 分。

6. **`06_reading_checklist.md`**
   "このファイルを読み終えたら次に何を確認するか" のチェックリスト。脱線対策。

## 大原則 (時間がない人向け 30 秒サマリ)

- glow は **cobra** で CLI を組み、引数の有無で 2 つの世界に分かれる:
  - **引数あり (ファイル/URL) または stdin pipe** → CLI モード。`executeCLI`
    が **glamour** で 1 回レンダして `os.Stdout` (or pager / TUI) に流すだけ。
  - **引数なし、または引数がディレクトリ** → TUI モード。`runTUI` →
    `ui.NewProgram` で **Bubble Tea** プログラムを起動し、stash (一覧) と
    pager (本文) の 2 画面を Model-Update-View ループで回す。

- Markdown → ANSI 端末出力の変換そのものは glow 内部ではやっていない。全部
  **`github.com/charmbracelet/glamour`** に委譲している。glow がやるのは
  「入力ソースを特定し、glamour に食わせ、出力先を振り分ける」だけ。

- 関連リポジトリ (読まなくてよいが、概念だけ知っておくと安心):
  - `charmbracelet/bubbletea` … Elm Architecture フレームワーク
  - `charmbracelet/bubbles` … viewport, paginator, spinner, textinput など部品
  - `charmbracelet/lipgloss` … スタイル定義 (色・パディング・ボーダー)
  - `charmbracelet/glamour` … Markdown → ANSI レンダラ本体
