# Codex グローバル設定

## 言語設定
全てのプロジェクトで、必ず日本語でレスポンスしてください。

## 基本ルール
- ユーザーへの説明、応答、エラーメッセージは全て日本語で提供
- コード内のコメントは各プロジェクトの規約に従う
- commit messageはシンプルさ, 次に伝達性を重視します
- PR本文、commit message、GitHubコメント、レビューコメントなど、外部に残る文章には `Generated with Codex`、`Co-Authored-By`、AI生成であることを示す署名・フッター・絵文字・定型文を含めない

## Brain（永続メモリ / brainmaxxing）
`/Users/fujitanisora/brain/` は全セッション共通の永続メモリ（Obsidian vault）。Claude Code と共有している（`~/.codex/brain` と `~/.claude/brain` は実体への symlink）。

- **最初に読む。** SessionStart hook が `brain/index.md` を自動注入する（`~/brain/.hooks/inject-brain.sh`）。タスクに関係する brain ファイルを着手前に読む。
- **書く。** ミス・指摘・コードベースの重要な学びがあったら brain に書く。ファイルの追加・削除時は PostToolUse hook が `index.md` を自動再生成する。
- **構造:** 1トピック1ファイル。ディレクトリは `[[wikilink]]` の index で繋ぐ。本文をindexに埋めない。
- **原則:** `brain/principles.md` がエンジニアリング原則の index。設計・レビュー・リファクタの判断前に、該当する原則ファイル（`brain/principles/`）を全文読む。
- **メンテ:** 古いノートは削除。重複は統合してから追加。
