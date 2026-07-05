# Design Input Template

このテンプレートに記入してLLMに渡すことで、Issue-Driven Designドキュメントが生成されます。

## 基本情報

### Issue（解決すべき問題）
```
{1文で表現。「〜できるか？」「〜すべきか？」の形式}
```

### 背景（なぜこの問題を解決する必要があるか）
```
{ビジネス背景、技術的背景}
```

---

## Context

### 現状わかっていること
```yaml
system:
  # 現行システムの構成
  # 技術スタック
  # データ量・トラフィック量

performance:
  # 現在の性能特性
  # ボトルネック

issues:
  # 既知の問題点
```

### 制約条件
```yaml
budget:
  initial:    # 初期構築予算
  monthly:    # 月額運用予算

timeline:
  deadline:   # 期限
  milestones: # マイルストーン

team:
  size:       # 人数
  skills:     # 保有スキル
  bandwidth:  # 稼働率

compliance:
  # 法規制、セキュリティ要件
```

### 利用可能なインフラ・技術
```yaml
cloud:
  # AWS/GCP/Azure等
  # 利用可能なサービス

existing:
  # 既存のインフラ
  # 再利用可能なコンポーネント

tools:
  # CI/CD
  # モニタリング
  # IaC
```

---

## Goal

### 達成したい状態
```
{具体的に何ができる状態になるべきか}
```

### 成功指標（定量的に）
```yaml
metrics:
  - name: 
    target: 
    current: 
  - name: 
    target: 
    current: 
```

### 非機能要件
```yaml
availability:     # 可用性 (e.g., 99.9%)
latency:          # レイテンシ (e.g., P99 < 500ms)
throughput:       # スループット (e.g., 1000 req/s)
scalability:      # スケーラビリティ要件
security:         # セキュリティ要件
```

---

## Hypothesis

### 設計仮説
```
{「〜すれば〜できる」形式で}
```

### 仮説の根拠
```
{なぜそう考えるか、参考にした事例・ドキュメント}
```

### 代替案（検討したが選ばなかった選択肢）
```yaml
alternatives:
  - option: 
    pros: 
    cons: 
    reason_rejected: 
```

---

## Concerns

### 技術的懸念
```yaml
concerns:
  - description: 
    impact: # High/Medium/Low
    likelihood: # High/Medium/Low
    
  - description: 
    impact: 
    likelihood: 
```

### 不確実性（わからないこと）
```yaml
unknowns:
  - question: 
    how_to_validate: 
    
  - question: 
    how_to_validate: 
```

---

## Additional Context

### 参照すべきドキュメント
```
{URL、ファイルパス}
```

### ステークホルダー
```yaml
stakeholders:
  - role: 
    concerns: 
    decision_authority: 
```

### 過去の類似プロジェクト（あれば）
```
{学びや注意点}
```

---

## Output Preferences

### 重視するポイント
```yaml
priorities:
  - # e.g., コスト最適化
  - # e.g., 開発速度
  - # e.g., 運用負荷軽減
  - # e.g., スケーラビリティ
```

### 出力に含めてほしい内容
```yaml
include:
  - [ ] アーキテクチャ図（Mermaid）
  - [ ] 具体的なコード例
  - [ ] インフラ構成（Terraform等）
  - [ ] コスト試算
  - [ ] テスト計画
  - [ ] 移行計画
  - [ ] 運用手順
```
