# Claude Code グローバル設定

## 言語設定
全てのプロジェクトで、必ず日本語でレスポンスしてください。

## 基本ルール
- ユーザーへの説明、応答、エラーメッセージは全て日本語で提供
- コード内のコメントは各プロジェクトの規約に従う
- commit messageはシンプルさ, 次に伝達性を重視します
- 

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
