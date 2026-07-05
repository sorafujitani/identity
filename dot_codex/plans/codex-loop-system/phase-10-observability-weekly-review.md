# Phase 10: Observability and Weekly Review

Back to [overview](overview.md)

## Goal

Make loop behavior measurable. Use metrics to decide whether to tighten prompts, update skills, adjust gates, or promote autonomy.

## Changes

- Add weekly review template.
- Aggregate run logs by loop, outcome, cost estimate, false positive, and escalation reason.
- Define health thresholds.
- Define state cleanup routine.
- Define skill / policy update process based on findings.

## Data Structures

- `WeeklyLoopReport`: runs, success rate, false positives, escalations, average duration.
- `StateCleanupItem`: stale queue item, closed PR, resolved issue, obsolete blocker.
- `LoopImprovement`: problem, evidence, proposed skill/policy/state change.

## Verification

Static:

- Weekly template covers cost, success, false positive, escalation, and stale state.
- Metrics can be computed from run logs.

Runtime:

- Generate one weekly report from sample run logs.
- Remove stale state entries and confirm no active work is lost.
- Use one observed failure to update either policy, skill, or state schema.

