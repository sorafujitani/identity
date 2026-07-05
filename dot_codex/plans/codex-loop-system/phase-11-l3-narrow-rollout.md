# Phase 11: L3 Narrow Unattended Rollout

Back to [overview](overview.md)

## Goal

Only after L1 and L2 have produced stable metrics, enable very narrow unattended operation for reversible, low-risk changes.

## Changes

- Define L3 allowlist with exact paths and operation classes.
- Define required observation window before enabling.
- Define automatic rollback or revert strategy.
- Define hard budgets for iterations, parallelism, and daily runs.
- Define mandatory weekly review for L3 behavior.

## Data Structures

- `L3AllowlistEntry`: path pattern, operation, max diff size, required tests.
- `L3Budget`: daily runs, tokens, retries, max changed files.
- `L3Incident`: unexpected change, rollback status, policy update.

## Verification

Static:

- L3 allowlist is narrower than L2 allowlist.
- Denylist still overrides allowlist.
- Auto-merge remains disabled unless separately approved.

Runtime:

- Run L3 in dry-run shadow mode for at least one week.
- Compare proposed unattended actions with human judgment.
- Enable one low-risk class, such as docs typo or formatter-only.
- Confirm rollback path works before expanding scope.

