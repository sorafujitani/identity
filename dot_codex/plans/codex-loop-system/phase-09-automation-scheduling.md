# Phase 09: Automation Scheduling

Back to [overview](overview.md)

## Goal

Schedule mature L1 loops and selected L2 loops through Codex Automations or scriptable `codex exec` workflows.

## Changes

- Define automation prompts for daily triage, PR babysitter, and CI sweeper.
- Decide per loop whether it is thread automation, standalone automation, or external scheduler.
- Prefer worktrees for Git repositories.
- Define cadence, stop conditions, and reporting destination.
- Define first-week manual review process.

## Data Structures

- `AutomationSpec`: loop name, cadence, scope, autonomy tier, sandbox, output destination.
- `AutomationRunSummary`: findings, actions, escalations, archive decision.

## Verification

Static:

- Automation prompt includes what to do, what to report, when to stop, and when to ask for input.
- Sandbox and approval mode are documented.
- Cadence is justified by value and cost.

Runtime:

- Test prompt manually before scheduling.
- Run first scheduled execution in L1 only.
- Confirm findings arrive in expected destination.
- Confirm no local work is modified unexpectedly.
- Review first several outputs before enabling L2.

