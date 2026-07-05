# Phase 07: CI Sweeper Loop

Back to [overview](overview.md)

## Goal

Classify CI failures and propose or implement narrow fixes only when the failure is reproducible and low risk.

## Changes

- Create `.agents/skills/ci-sweeper/SKILL.md`.
- Instruct implementers to use the `skill-creator` skill when creating this skill.
- Define CI log intake contract.
- Define failure categories: deterministic test, lint, type, dependency, infra, flaky, unknown.
- Define when to retry, when to fix, and when to escalate.
- Optionally prepare a GitHub Actions integration later.

## Data Structures

- `CIFailureContext`: workflow, job, commit, branch, failing command, logs.
- `FailureClassification`: category, confidence, evidence, recommended action.
- `FixCandidate`: minimal change, expected verification, risk level.

## Verification

Static:

- Skill requires reproducing failure before L2 fix.
- Infra and flaky categories do not trigger code changes.
- Logs are summarized with key evidence, not pasted wholesale.

Runtime:

- Feed known lint failure logs and confirm classification.
- Feed known infra failure logs and confirm escalation/no-op.
- Run a small deterministic failure through maker/checker.
- Confirm run log records command evidence.

