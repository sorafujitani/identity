# Phase 01: State Spine

Back to [overview](overview.md)

## Goal

Create the durable state layer that every loop reads and writes. This phase does not automate implementation work. It only defines where loop state lives, what fields are required, and how runs are recorded.

## Changes

- Add `.codex/loop/STATE.md` for human-readable current state.
- Add `.codex/loop/state.schema.json` for machine-readable state validation.
- Add `.codex/loop/runs/` for append-only run records.
- Document run ID format and state update rules.

## Data Structures

- `LoopState`: global queue, active runs, recent findings, blocked items, policy snapshot.
- `LoopRun`: one execution record with source, target, actions, verification, outcome.
- `LoopFinding`: actionable or non-actionable item discovered by triage.

## Verification

Static:

- JSON schema is valid.
- Example `state.json` validates against schema.
- Markdown state file and JSON state agree on active runs and queue.

Runtime:

- Simulate a successful L1 triage run and write one run log.
- Simulate a blocked run and confirm the blocked reason is visible in both `STATE.md` and the run log.
- Start a second simulated run from the saved state and verify it does not need prior chat context.

