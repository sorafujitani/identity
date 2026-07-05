# Phase 06: PR Babysitter Loop

Back to [overview](overview.md)

## Goal

Monitor active PRs and keep them moving by reporting review comments, CI state, conflicts, and stale status. Start as L1 and only later allow narrow L2 fixes.

## Changes

- Create `.agents/skills/pr-babysitter/SKILL.md`.
- Instruct implementers to use the `skill-creator` skill when creating this skill.
- Define PR intake from URL, branch, or repository query.
- Define monitored signals: CI, reviews, comments, mergeability, conflicts, age.
- Define L1 report format.
- Define L2 allowed fixes: formatter, lint, small review comment fixes.

## Data Structures

- `PRWatchTarget`: repo, PR number, branch, owner, last checked time.
- `PRSignal`: CI failure, review request, review comment, conflict, stale state.
- `PRAction`: report, fix attempt, ask human, archive.

## Verification

Static:

- Skill separates monitoring from fixing.
- L2 fixes are gated by policy.
- Review comments are summarized without losing actionable details.

Runtime:

- Run on one open PR with no write actions.
- Confirm report distinguishes action items from noise.
- Simulate failing CI and review comment inputs.
- Confirm L2 attempts stop at PR update and do not merge.

