# Phase 03: Daily Triage Skill

Back to [overview](overview.md)

## Goal

Create the first L1 loop: a daily report-only triage workflow that finds candidate work and updates state without modifying project code.

## Changes

- Create `.agents/skills/daily-triage/SKILL.md`.
- Instruct implementers to use the `skill-creator` skill when creating this skill.
- Define inputs: repositories, issue / PR filters, CI source, cadence.
- Define outputs: candidate list, blocked list, no-action noise, recommended next actions.
- Add examples for manual run and automation prompt.

## Data Structures

- `TriageCandidate`: source, ID, title, risk, loop type, reason, recommendation.
- `TriageNoise`: item that should not trigger action.
- `TriageReport`: daily summary plus state updates.

## Verification

Static:

- Skill description clearly triggers only for daily triage.
- Skill does not overlap with implementation or PR babysitter skills.
- Output format is documented.

Runtime:

- Run the skill manually on one repository.
- Confirm no code files are modified.
- Confirm `STATE.md` and run log are updated.
- Review false positives and add at least one noise example.

