# Codex Loop System Plan

## Context

Codex を使った開発作業を、都度プロンプトする運用から、状態・検証・ゲートを持つ反復システムへ移行するための長期計画。

ここで設計する loop は、Codex 内部の agent loop そのものではなく、その外側にある開発運用 loop である。つまり、作業候補を発見し、Codex に渡し、結果を検証し、状態を残し、次の実行可否を判断する仕組みを作る。

参考にする考え方:

- Addy Osmani "Loop Engineering": https://addyosmani.com/blog/loop-engineering/
- suwa-sh "Loop Engineering 入門": https://zenn.dev/suwash/articles/loop-engineering_20260610
- OpenAI "Unrolling the Codex agent loop": https://openai.com/index/unrolling-the-codex-agent-loop/
- Codex docs: https://developers.openai.com/codex/

注意: `https://zenn.dev/acrosstudioblog/articles/38509c0473683aZ` は確認時点で取得できなかったため、この plan では一次参照に含めない。

## Goal

最終的には、以下の開発作業を Codex が半自律的に回せる状態を目指す。

- GitHub issue の実装候補を分類する
- main 起点で安全に branch / worktree を切る
- issue を source of truth として最小差分を実装する
- maker と checker を分離して検証する
- CI failure や review comment を継続監視する
- PR 作成、追加修正、停止、エスカレーションを判断する
- 実行結果を state / run log に保存し、次回 loop の入力にする

## Non-goals

初期段階では以下をやらない。

- auto-merge
- production deploy
- secret / auth / payment / infra / DB migration の無人変更
- 大規模リファクタの無人実行
- 人間が理解していない差分の自動蓄積
- 外部に残る文章への AI 署名追加

## Design Principles

1. L1 report-only を飛ばさない。
2. loop の成果物は会話ではなく、state、run log、PR、検証結果である。
3. Codex の自己申告を完了条件にしない。test、diff、CI、checker、issue acceptance criteria で判定する。
4. maker と checker を同一コンテキストに置かない。
5. 作業は原則 isolated worktree で行い、local checkout を汚さない。
6. state は外部ファイルに残し、会話履歴に依存しない。
7. denylist に触れたら止める。迷ったら人間へ戻す。
8. 自動化対象は repetitive、reviewable、valuable の 3 条件を満たすものに限定する。
9. token / iteration / false positive / human escalation を計測する。
10. loop が失敗したら prompt を盛る前に、state schema、skill、gate、検証コマンドを直す。

## Target Architecture

```text
Trigger
  |
  v
Triage Skill
  |
  v
State Spine (.codex/loop/state.json, STATE.md)
  |
  v
Human Gate / Risk Gate
  |
  +-- report only --> Triage inbox / markdown report
  |
  +-- allowed L2 --> Isolated Worktree
                      |
                      v
                    Maker Agent
                      |
                      v
                    Checker Agent
                      |
                      +-- approve --> PR / comment / patch
                      |
                      +-- reject  --> retry or escalate
  |
  v
Run Log (.codex/loop/runs/*.json)
```

## Repository Layout

Long-term target:

```text
.codex/
  plans/
    codex-loop-system/
      overview.md
      phase-01-state-spine.md
      ...
  loop/
    STATE.md
    state.schema.json
    policy.yaml
    runs/
  agents/
    maker.toml
    checker.toml
    reviewer.toml
  hooks.json

.agents/
  skills/
    daily-triage/
      SKILL.md
    issue-implementation/
      SKILL.md
    pr-babysitter/
      SKILL.md
    ci-sweeper/
      SKILL.md
```

## Core Loops

### Daily Triage Loop

Autonomy: L1 first, optionally L2 later.

Purpose:

- open issues、open PR、CI failure、stale branch、review request を集約する
- Codex に任せる候補と人間が見るべき候補を分ける
- `.codex/loop/STATE.md` を更新する

Initial output:

- 実行日
- 候補一覧
- loopable / not loopable の理由
- リスク分類
- 推奨 next action
- no-action noise

### Issue Implementation Loop

Autonomy: L2.

Purpose:

- GitHub issue を source of truth にして実装する
- main 起点で branch / worktree を切る
- targeted test を回す
- checker が approve したら PR を作る

Human gate:

- scope が曖昧
- acceptance criteria がない
- denylist path に触る
- 3 回連続で同じ失敗
- diff が大きすぎる
- dependency / migration / secret / auth / payment / infra に関係する

### PR Babysitter Loop

Autonomy: L1 to L2.

Purpose:

- PR の CI、review comment、conflict、staleness を継続確認する
- 最初は report only
- 安定後、lint / type / test failure / small review fix だけ修正する

### CI Sweeper Loop

Autonomy: L1 to L2.

Purpose:

- CI failure を分類する
- 再現コマンドを特定する
- deterministic failure のみ修正候補にする
- flaky / infra failure は人間に返す

## Autonomy Tiers

| Tier | Name | Allowed actions | Exit condition |
| --- | --- | --- | --- |
| L0 | Manual | 人間が都度 Codex に依頼 | 手動完了 |
| L1 | Report only | 調査、分類、state 更新、提案 | report 作成 |
| L2 | Assisted PR | worktree 実装、検証、PR 作成 | checker approve + PR |
| L3 | Narrow unattended | allowlist 内の小修正のみ自動適用 | CI green + policy pass |

L3 は長期目標であり、docs typo、formatter-only、snapshot-only など、極端に狭い allowlist から始める。

## State Model

Initial fields:

```json
{
  "version": 1,
  "updated_at": "2026-06-17T00:00:00+09:00",
  "active_runs": [],
  "queue": [],
  "recent_findings": [],
  "blocked_items": [],
  "policy": {
    "autonomy_tier": "L1",
    "max_iterations_per_item": 3,
    "max_parallel_runs": 2
  }
}
```

Run log fields:

```json
{
  "run_id": "20260617-001",
  "loop": "daily-triage",
  "source": "manual",
  "started_at": "2026-06-17T09:00:00+09:00",
  "finished_at": "2026-06-17T09:03:00+09:00",
  "autonomy_tier": "L1",
  "target": null,
  "findings": [],
  "actions": [],
  "escalations": [],
  "verification": [],
  "outcome": "completed"
}
```

## Policy Model

Minimum policy:

- allowlist
  - docs-only changes
  - tests-only changes
  - formatter-only changes
  - small bug fix with existing test coverage
- denylist
  - auth
  - payment
  - secret
  - infrastructure
  - production deploy
  - database migration
  - dependency upgrade unless explicitly requested
  - destructive git commands
- thresholds
  - max iterations per item: 3
  - max changed files for L2: 5 initially
  - max parallel runs: 2 initially
  - checker required: true for L2+

## Applicable Codex Surfaces

- `AGENTS.md`: durable global / repo conventions.
- `.agents/skills/*/SKILL.md`: reusable loop procedures.
- `.codex/agents/*.toml`: maker / checker / reviewer role definitions.
- Codex Automations: recurring daily triage, PR babysitter, CI sweeper.
- Codex Worktrees: isolated implementation and background runs.
- Codex Hooks: policy checks, run log writing, prompt safety, stop-time validation.
- `codex exec --json`: scriptable, non-interactive execution for CI or local scheduler.
- GitHub CLI / connectors: issue, PR, CI, review context retrieval.

## Phases

1. [Phase 01: State Spine](phase-01-state-spine.md)
2. [Phase 02: Policy and Gates](phase-02-policy-and-gates.md)
3. [Phase 03: Daily Triage Skill](phase-03-daily-triage-skill.md)
4. [Phase 04: Maker and Checker Agents](phase-04-maker-checker-agents.md)
5. [Phase 05: Issue Implementation Loop](phase-05-issue-implementation-loop.md)
6. [Phase 06: PR Babysitter Loop](phase-06-pr-babysitter-loop.md)
7. [Phase 07: CI Sweeper Loop](phase-07-ci-sweeper-loop.md)
8. [Phase 08: Hooks and Safety Enforcement](phase-08-hooks-safety.md)
9. [Phase 09: Automation Scheduling](phase-09-automation-scheduling.md)
10. [Phase 10: Observability and Weekly Review](phase-10-observability-weekly-review.md)
11. [Phase 11: L3 Narrow Unattended Rollout](phase-11-l3-narrow-rollout.md)

## Verification Strategy

Each phase must prove three things:

1. The loop can stop.
2. The loop can explain why it stopped.
3. The next run can continue from persisted state without relying on chat history.

Project-level checks:

- state schema validation passes
- policy validation passes
- skill trigger descriptions are scoped and non-overlapping
- maker cannot self-approve
- checker reports concrete commands and outputs
- run logs are written for success, reject, and escalation paths
- dangerous paths trigger human gate
- dry-run mode works before any write mode

## Rollout Milestones

### Milestone A: L1 usable

- state files exist
- daily triage produces useful reports
- human can select candidate tasks
- false positive rate is tracked

### Milestone B: L2 issue implementation

- issue implementation can create a branch / worktree
- maker implements narrow scope
- checker verifies independently
- PR is created with no AI signature

### Milestone C: L2 maintenance loops

- PR babysitter monitors active PRs
- CI sweeper classifies failures
- deterministic small fixes can be proposed

### Milestone D: controlled L3

- allowlist / denylist stable for several weeks
- weekly metrics are acceptable
- only narrow, reversible changes can run unattended

