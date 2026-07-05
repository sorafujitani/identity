# Phase 0: スコープ宣言

> ユーザーからフォローアップ質問が取れない前提のため、与えられた情報からこちらで判断して宣言する。

## スコープ

- **対象**: `github.com/charmbracelet/glow` リポジトリ全体 (Go ファイル群、`main.go` + `ui/*.go` + `utils/`)
  - 言語/規模: Go, アプリ本体は `main.go` 473行 + `ui/` 約 2,500行 + `utils/` 113行 (テスト除く)
  - 主要外部依存: `cobra` / `viper` (CLI/設定), `bubbletea` / `bubbles` / `lipgloss` (TUI), `glamour` (Markdown レンダリング), `gitcha` (ローカル探索), `glamour/styles`

## 目的

- **`glow README.md` 実行から、ターミナルに Markdown が描画されるまでの実行フローを完全に追える** こと
- Go の基本文法は既知。Bubble Tea (Elm Architecture: Init / Update / View) は初見、なのでそこは丁寧に。
- 後で「TUI モードで起動した時はどこを通る？」「pager に渡すとどうなる？」も自分で予測できる状態にする (Phase 6 の検証で使う)

## 時間配分 (3 時間想定)

| Phase | 配分 | 時間 |
|---|---|---|
| 0 スコープ確認 | 5% | 約 10 分 (済) |
| 1 鳥瞰 | 10% | 約 20 分 |
| 2 アーキテクチャ | 15% | 約 30 分 |
| 3 ドメイン | 10% | 約 20 分 (CLI なのでドメインは薄く) |
| 4 代表フロー (★) | **35%** | **約 60 分** |
| 5 横断的関心事 | 15% | 約 30 分 |
| 6 統合と検証 | 10% | 約 20 分 |

> CLI 用途のアダプテーション (SKILL.md の表) に従い、**Phase 1 (どんな CLI か) と Phase 4 (主要サブコマンドの実行フロー) を重点化** し、Phase 3 は最小限にする。

## 代表フロー (Phase 4 のターゲット)

`$ glow README.md` を実行 → CLI モードで `glamour` が Markdown を描画 → 標準出力に書き出されるまで。
ピペや TUI モードはサブフローとして触れるが、メインの 1 本はこの「CLI で 1 ファイル描画」のパス。

## 前提

- Go の基本文法・標準ライブラリは既知
- `cobra` / `viper` は名前は知っているレベル
- Bubble Tea (Elm Architecture: `Init() Cmd / Update(msg) (Model, Cmd) / View() string`) は **初見**
- glamour, lipgloss も初見だが、Phase 4 の代表フローが CLI 直接描画なので glamour は **API レベル** のみで深追いしない (公式ライブラリのため glow 側から見れば不透明箱)

## ゴール (Phase 6 終了時に達成したい状態)

1. `glow README.md` を打鍵した瞬間からターミナルに描画が出るまでを、コードを開かずに 5〜7 個の関数名 + ファイル:行番号で言える
2. CLI モードと TUI モードの分岐点が `execute()` の中にあり、TUI モードに行く条件を即答できる
3. Bubble Tea がなぜ `Init / Update / View` で構成されているのか、自分の言葉で 3 文で説明できる
