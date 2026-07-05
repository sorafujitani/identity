# Phase 02: Policy and Gates

Back to [overview](overview.md)

## Goal

Define the safety policy that controls whether a loop reports, acts, retries, or escalates to a human.

## Changes

- Add `.codex/loop/policy.yaml`.
- Define autonomy tiers L0, L1, L2, L3.
- Define allowlist and denylist path / operation categories.
- Define thresholds for changed files, iterations, parallel runs, and retry count.
- Define escalation reasons and required context.

## Data Structures

- `LoopPolicy`: autonomy tier, thresholds, allowlist, denylist.
- `GateDecision`: `allow`, `report_only`, `retry`, `escalate`, or `reject`.
- `EscalationContext`: target, reason, observed evidence, suggested next step.

## Verification

Static:

- Policy file parses.
- Denylist contains auth, payment, secrets, infra, production deploy, DB migration, destructive git operations.
- L2+ requires checker approval.

Runtime:

- Feed sample changes through the gate:
  - docs-only change is allowed for L2 proposal.
  - auth change escalates.
  - dependency addition escalates unless explicitly requested.
  - fourth retry rejects or escalates.
- Confirm every gate decision includes a reason suitable for run logs.

