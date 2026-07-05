---
name: issue-driven-design
description: |
  ソフトウェア設計の意思決定を支援するイシュードリブン設計ドキュメント生成。
  以下の場合に使用:
  (1) 新規システム・機能の設計時
  (2) アーキテクチャ選定・比較検討時
  (3) 技術的課題の解決策策定時
  (4) インフラストラクチャ構成の決定時
  (5) 既存システムのリファクタリング計画時
  入力: 現状、達成目標、利用可能インフラ、課題、仮説
  出力: 検証可能な設計ドキュメント（reference付き）
---

# Issue-Driven Software Design

イシューからはじめる設計ドキュメント生成スキル。

## Philosophy

このスキルは安宅和人氏の「イシューからはじめよ」の方法論をソフトウェア設計に適用する:

1. **イシューありき**: 何を解決するのか、何に白黒つけるのかを最初に明確化
2. **仮説ドリブン**: 設計仮説とそれを支えるサブ論点を構造化
3. **アウトプットドリブン**: 論理が崩れると全体が崩壊する上流課題から着手
4. **メッセージドリブン**: 曖昧さのない、検証可能な設計判断

## Input Format

ユーザーから以下の情報を収集する（不足時は質問で補完）:

```yaml
issue:           # 解決すべき本質的な問題（1文で表現）
context:
  current_state: # 現状わかっていること
  constraints:   # 制約条件（予算、期間、チーム構成等）
  available:     # 利用可能なインフラ・技術スタック
goal:
  outcome:       # 達成したい状態
  metrics:       # 成功指標（定量的に）
hypothesis:      # 設計仮説（「〜すれば〜できる」形式）
concerns:        # 懸念・課題・リスク
```

## Execution Process

### Phase 1: Issue Crystallization

イシューを結晶化する。曖昧な要求を「白黒つけられる問い」に変換:

```
❌ 「パフォーマンスを改善したい」
✅ 「P95レイテンシを500ms以下に抑えつつ、月間100万リクエストを処理できるか」
```

イシューが不明確な場合、以下を質問:
- 「何ができたら成功と言えますか？」
- 「何が起きたら失敗ですか？」
- 「いつまでに、誰が、どう使いますか？」

### Phase 2: Hypothesis Structuring

設計仮説をピラミッド構造で分解:

```
Main Thesis (設計方針)
├── Sub-thesis 1 (サブ論点)
│   └── Evidence: 技術検証、ベンチマーク、公式ドキュメント
├── Sub-thesis 2
│   └── Evidence: 類似事例、制約との整合性
└── Sub-thesis 3
    └── Evidence: コスト試算、運用実績
```

各サブ論点は以下を満たす:
- 検証可能（何をもって正しいと言えるか明確）
- 独立（他のサブ論点と重複しない）
- 網羅的（メインの論点を支えるのに十分）

### Phase 3: Critical Path First

論理が崩れると全体が崩壊する「上流課題」から検証:

優先順位の判断基準:
1. **Blocker**: これが成立しないと他の全てが無意味
2. **Architectural**: システム全体の構造を決定
3. **Integration**: 外部システムとの結合点
4. **Implementation**: 実装詳細

```
例: バッチ処理システム設計
1. [Blocker] SLAの3時間以内に処理完了は技術的に可能か？
2. [Architectural] SQS + Lambda vs ECS + Step Functions、どちらがSLAを満たすか？
3. [Integration] 上流システムのデータ形式と整合性は取れるか？
4. [Implementation] エラーリトライのロジックはどう実装するか？
```

### Phase 4: Evidence-Based Design

各設計判断に対してエビデンスを付与:

**必須の検証項目**:
- [ ] 公式ドキュメントからの機能・制約の確認
- [ ] 類似ユースケースの実績・事例
- [ ] ベンチマーク・性能特性
- [ ] コスト試算（初期・運用）
- [ ] 制約条件との整合性

**Web検索で確認すべき情報**:
- 最新のサービス制限・クォータ
- 既知の問題・ワークアラウンド
- ベストプラクティスの更新
- 価格改定

### Phase 5: Defensive Design Review

設計の防御的レビュー。以下の観点で脆弱性を検証:

#### Data Integrity
- スキーマの不整合が起きる条件は？
- 部分的な更新失敗時のロールバック戦略は？
- 楽観的ロック vs 悲観的ロックの選択根拠は？

#### Security
- 認証・認可の境界は明確か？
- 機密データの暗号化（at-rest, in-transit）は？
- インジェクション・XSS等の対策は？

#### Operational Resilience
- 障害時の検知・通知・復旧手順は？
- スケールアウト/インのトリガーと閾値は？
- デプロイ時のロールバック戦略は？

#### Observability
- メトリクス・ログ・トレースの設計は？
- アラートの閾値と対応手順は？
- デバッグに必要な情報は取得できるか？

#### Test Strategy
- 単体テストでカバーすべき境界条件は？
- 統合テストで検証すべきシナリオは？
- 負荷テストの条件と合格基準は？

## Output Format

以下の構造で設計ドキュメントを生成:

```markdown
# {Issue Title}

## Executive Summary
{3行以内で設計判断の結論}

## Issue
### Problem Statement
{解決すべき問題を1文で}

### Success Criteria
{成功指標を箇条書きで}

### Constraints
{制約条件}

## Design Decision

### Main Thesis
{設計方針を1文で}

### Sub-thesis 1: {論点タイトル}
**Claim**: {主張}
**Evidence**: {根拠・出典}
**Implication**: {設計への影響}

### Sub-thesis 2: {論点タイトル}
...

## Architecture

### System Overview
{アーキテクチャ図（Mermaid）}

### Component Design
{各コンポーネントの責務と相互作用}

### Data Model
{データ構造とフロー}

## Implementation

### Critical Path
{最優先で検証・実装すべき項目}

### Code Examples
{具体的な実装例}

### Configuration
{設定値とその根拠}

## Defensive Review

### Risk Matrix
| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|

### Security Considerations
{セキュリティ設計}

### Failure Modes
{障害モードと対応}

## Test Plan
{テスト戦略と具体的なテストケース}

## References
{参照した公式ドキュメント、URL}

## Decision Log
| Date | Decision | Rationale | Alternatives Considered |
|------|----------|-----------|------------------------|
```

## Quality Criteria

生成したドキュメントは以下を満たすこと:

1. **Verifiable**: 全ての主張に検証方法がある
2. **Traceable**: 全ての判断に根拠（URL/引用）がある
3. **Actionable**: 次のアクションが明確
4. **Defensive**: リスクと対策が網羅されている
5. **Maintainable**: 将来の変更に対応できる構造

## Anti-patterns to Avoid

- ❌ 根拠なき「〜すべき」
- ❌ 検証不能な主張
- ❌ 代替案の検討なき選択
- ❌ Happy pathのみの設計
- ❌ 運用観点の欠落

## Iteration Protocol

このドキュメントは教師データとして機能し、以下のルールで成長する:

1. **追加のみ**: 既存の構造・責務は変更しない
2. **拡張**: 新しいドメイン知識はセクションとして追加
3. **事例蓄積**: 成功した設計パターンをExamplesに追加
4. **フィードバック反映**: レビュー指摘をAnti-patternsに追加

## Usage Examples

See `references/examples/` for domain-specific examples:
- `batch-processing.md`: バッチ処理システム設計
- `api-design.md`: REST/GraphQL API設計
- `event-driven.md`: イベント駆動アーキテクチャ
- `data-pipeline.md`: データパイプライン設計
