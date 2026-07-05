# Phase 04: Maker and Checker Agents

Back to [overview](overview.md)

## Goal

Separate implementation from verification. The maker may propose or create changes, but only the checker can approve that the work satisfies the goal.

## Changes

- Add or refine `.codex/agents/maker.toml`.
- Add or refine `.codex/agents/checker.toml`.
- Optionally add `.codex/agents/reviewer.toml` for broader code review.
- Document when to spawn each agent and what each agent must output.
- Ensure checker uses fresh context and independently runs verification commands.

## Data Structures

- `MakerResult`: changed files, implementation summary, commands run, open questions.
- `CheckerResult`: approve / reject, evidence, commands run, residual risks.
- `AgentContract`: required output fields for handoff between agents.

## Verification

Static:

- Maker instructions prohibit self-approval.
- Checker instructions require concrete command evidence.
- Checker instructions prioritize correctness, regressions, security, and missing tests.

Runtime:

- Run a dry maker/checker handoff on a trivial docs-only change.
- Confirm checker can reject incomplete work.
- Confirm checker result is written into run log.

