# Phase 08: Hooks and Safety Enforcement

Back to [overview](overview.md)

## Goal

Use hooks as enforcement and logging boundaries around Codex activity. Hooks should not become the main implementation engine; they should prevent dangerous actions and preserve observability.

## Changes

- Review existing `/Users/fujitanisora/.codex/hooks.json`.
- Add project-local hook plan only where needed.
- Add policy checks for dangerous commands and paths.
- Add Stop-time run log validation.
- Add prompt / secret safety checks if practical.

## Data Structures

- `HookDecision`: allow, warn, block.
- `HookEventLog`: event, command/tool, decision, reason.
- `StopValidation`: run log present, state updated, no unresolved active run.

## Verification

Static:

- Hook definitions are valid JSON/TOML.
- Hook commands resolve from stable paths.
- Hook trust requirements are documented.

Runtime:

- Test harmless command path.
- Test denied destructive command path.
- Test a loop finishing without run log and confirm Stop validation catches it.
- Confirm hooks do not block read-only exploration.

