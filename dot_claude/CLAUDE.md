# Claude Code グローバル設定

## 言語設定
全てのプロジェクトで、必ず日本語でレスポンスしてください。

## 基本ルール
- ユーザーへの説明、応答、エラーメッセージは全て日本語で提供
- コード内のコメントは各プロジェクトの規約に従う
- commit messageはシンプルさ, 次に伝達性を重視します

## コーディング規約（全repo共通）
- コメントは最小限。書くのは why だけ。仕様・意図は命名とテストで表現する
- 実装のまとまりごとに、新しい context window の subagent でレビューを起動し、指摘を自律的に改善してから次へ進む

## 成果物のルール
- 外部に残る文面（PR本文・issue・release note・README）に AI 署名・絵文字・定型フッターを入れない
- 言語: toridori 系リポジトリは日本語、OSS・公開個人リポ（github.com/sorafujitani/*, fs0414/* など）は英語
- commit / push は明示的な指示があるまで行わない。ファイル編集までは進めてよい
- 解説HTMLなどリポジトリ外の生成物は `~/Downloads/` に置く。Desktop には置かない

## Brain（永続メモリ / brainmaxxing）
`/Users/fujitanisora/brain/` は全セッション共通の永続メモリ（Obsidian vault）。Codex と共有している（`~/.claude/brain` と `~/.codex/brain` は実体への symlink。既存のパス参照は symlink 経由でそのまま動く）。

- **最初に読む。** セッション開始時に `brain/index.md` を読む。タスクに関係する brain ファイルを着手前に読む。
- **書く。** ミス・指摘・コードベースの重要な学びがあったら brain に書く（`reflect` skill）。
- **構造:** 1トピック1ファイル。ディレクトリは `[[wikilink]]` の index で繋ぐ。本文をindexに埋めない。
- **原則:** `brain/principles.md` がエンジニアリング原則の index。`brain-plan`・`brain-review` skill はこれを全文読んでから判断する。
- **メンテ:** 古いノートは削除。`meditate` で監査・剪定、`ruminate` で過去ログ採掘。

利用できる skill: `reflect` / `meditate` / `ruminate` / `brain` / `brain-plan` / `brain-review`。

## sora-mode（作業スタイル）
マルチステップの実装・調査タスクは、着手前に `sora-mode` skill を起動する（pstack poteto-mode の移植）。playbook の手順を todolist に verbatim でコピーし、適用した原則を返答で明示する。原則の実体は `brain/principles/`。
