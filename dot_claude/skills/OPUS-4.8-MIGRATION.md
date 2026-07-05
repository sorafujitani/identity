# Opus 4.8 移行ノート — skills/ コレクション

作成日: 2026-05-29 / 対象: `~/.claude/skills/` 配下の agent skill 全17件

このファイルは `/document-skills:claude-api migrate Opus4.8` の実行記録兼リファレンスです。
プラグインキャッシュ内の移行ガイド（`anthropic-agent-skills/.../shared/model-migration.md`）は
プラグイン更新で上書きされるため、編集可能な手元コピーとしてここに残します。

出典（2026-05-29 取得）:
- Prompting best practices: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- What's new in Claude Opus 4.8: https://platform.claude.com/docs/en/about-claude/models/whats-new-claude-4-8
- Migration guide (4.7→4.8): https://platform.claude.com/docs/en/about-claude/models/migration-guide#migrating-from-claude-opus-47

---

## 1. Opus 4.8 の要点

| 項目 | 値 |
|------|-----|
| モデルID | `claude-opus-4-8` |
| コンテキスト | 1M（Claude API / Bedrock / Vertex）/ 200k（Microsoft Foundry）|
| 最大出力 | 128k トークン |
| thinking | adaptive のみ（`thinking: {type: "adaptive"}`）。デフォルトは OFF |
| effort デフォルト | `high`（全サーフェス。Claude Code 含む）|

### 4.7 → 4.8 は API 破壊的変更ゼロ
4.7 で動くコードは無修正で 4.8 に載る。新規追加は会話途中 system メッセージ、
`stop_details`（refusal カテゴリ）の公開、Fast mode（`speed: "fast"`、リサーチプレビュー）、
プロンプトキャッシュ最小長 1,024 トークンへの低下。

### 4.7 から継承する制約（4.6 以前から来る場合のみ要対応）
- `temperature` / `top_p` / `top_k` を非デフォルト値にすると **400**
- `thinking: {type: "enabled", budget_tokens: N}` は **400**（adaptive のみ）
- 最後の assistant ターンの prefill は **400**（4.6 以降）

---

## 2. agent skill にとっての「移行」の意味

この17スキルには **モデルID・SDK呼び出し・`budget_tokens`・`temperature` が一切存在しない**
（grep 結果 0 件）。したがって「モデル文字列の差し替え」型の移行は **対象ゼロ**。

agent skill は Claude API を直接呼ぶコードではなく**プロンプト指示書**なので、
4.8 移行とは実質「プロンプト挙動の変化に対するチューニング」を指す。
公式ドキュメントも「4.8 は既存の Opus 4.7 プロンプトで良好に動作する」と明言しており、
**広範な書き換えは不要かつ有害**。

### 4.8 の挙動変化のうち、このコレクションに関係するもの

| 挙動変化 | このコレクションへの影響 | 対策状況 |
|----------|------------------------|----------|
| サブエージェント生成が控えめ | `review-code`(4並列), `dry-coding`(Explore×3/Plan×2-3) が並列前提 | **本パスで明示補強** |
| ツール呼び出しを控えめに | ハルシネーション防止が `WebSearch`/`Read` 依存（review-code, dry-coding, issue-analysis）| `必ず…で裏取り/実在確認` の既存記述で担保済 |
| 応答長をタスク複雑度に合わせる | 各スキルが出力フォーマットを固定済み | 担保済 |
| 指示をより字義通りに解釈 | 詳細・明示的な手順書なので有利に働く | 問題なし |
| 大きな system プロンプトで thinking 過剰発火 | 長文スキルあり。気になれば下記スニペット | 任意 |

### やってはいけない誤チューニング（本パスで除外した項目）
- `Critical` / `Important` / `Minor` は**バグ深刻度ラベル**であり、4.8 が問題視する
  「ツール過剰起動を煽る命令」ではない。緩和すると出力仕様が壊れる → **触らない**
- `必ず順番に進む` `必ず複数仮説を立てる` `必ず実在確認する` 等の `必ず` は
  **意図的なワークフロー規律・ツール起動保証**であり、旧モデルの忌避克服用の煽りではない。
  4.8 はツールを控えめに使う傾向があるため、これらはむしろ**残すべき** → **触らない**

---

## 3. 全スキル監査結果（17件）

| スキル | モデル参照 | 4.8 関連の調整 | 判定 |
|--------|-----------|----------------|------|
| review-code | なし | サブエージェント並列起動を明示補強 | **編集** |
| dry-coding | なし | サブエージェント並列起動を明示補強 | **編集** |
| issue-analysis | なし | `Task(ctx:github)` は単発取得。`必ず実在確認`がツール起動を担保 | 変更不要 |
| pr-comment-plan | なし | `Critical/Important/Minor` は深刻度ラベル | 変更不要 |
| property-based-test | なし | `severity: critical\|major\|minor` はスキーマ値 | 変更不要 |
| milestone-triage | なし | `must` は CLI 仕様説明 | 変更不要 |
| graph-think-map | なし | 「思考」は説明語。thinking パラメータ無関係 | 変更不要 |
| pr-generator | なし | `必ず記載` は出力規律 | 変更不要 |
| linear-code-leader | なし | `必ず守る/必ず通る` はワークフロー規律 | 変更不要 |
| guided-code | なし | `必ず提供すること` は出力規律 | 変更不要 |
| ts-lint-searcher | なし | — | 変更不要 |
| karin-info | なし | `混同禁止` は検索除外規律 | 変更不要 |
| exploratory-test | なし | — | 変更不要 |
| guided-code | なし | — | 変更不要 |
| local-repo-finder | なし | — | 変更不要 |
| print-debug | なし | — | 変更不要 |
| skill-zip | なし | — | 変更不要 |
| research-questioner | なし | — | 変更不要 |

---

## 4. 任意で使えるプロンプトスニペット（必要時のみ）

### サブエージェントを確実に並列起動させたい（4.8 は控えめ）
```text
直接1レスポンスで完了できる作業ではサブエージェントを生成しない。
複数項目へのファンアウトや複数ファイル読み込み時は、同一ターンで複数サブエージェントを並列起動する。
```

### thinking の過剰発火を抑えたい（大きな system プロンプト時）
```text
thinking はレイテンシを増やすため、回答品質を有意に改善する場合（多段推論が必要な問題など）のみ使う。
迷ったら直接回答する。
```

### 冗長さを抑えたい
```text
簡潔で焦点を絞った応答を返す。不要な前置きを省き、例は最小限にする。
```

### effort の目安（4.8）
- `xhigh`: コーディング・エージェント用途の最良設定（Claude Code デフォルト）
- `high`: 知性が要る用途の最低ライン（4.8 デフォルト）
- `medium`: コスト重視
- `low`: 短く範囲の狭いタスク・低レイテンシ用途
- `max`: 最難タスクの上限テスト用（過剰思考に注意）

---

## 5. 本パスの変更サマリー
- `review-code/SKILL.md`: Phase 2 のサブエージェント並列起動に 4.8 向け補強を1行追記
- `dry-coding/SKILL.md`: Phase 1 のサブエージェント並列起動に 4.8 向け補強を1行追記
- 上記以外の15スキルは 4.8 互換のため無変更
