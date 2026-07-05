# Phase 05: Issue Implementation Loop

Back to [overview](overview.md)

## Goal

Build the main L2 implementation loop: take a GitHub issue, create isolated work, implement the minimum change, verify it, and prepare a PR.

## Changes

- Create `.agents/skills/issue-implementation/SKILL.md`.
- Instruct implementers to use the `skill-creator` skill when creating this skill.
- Define issue intake contract.
- Define branch / worktree setup rules.
- Define implementation boundaries.
- Define checker gate and PR creation rules.
- Record issue implementation attempts in run logs.

## Data Structures

- `IssueContext`: repo, issue number, title, body, comments, labels, acceptance criteria.
- `ImplementationAttempt`: branch, worktree, commit range, tests, outcome.
- `PullRequestDraft`: title, body, verification, linked issue, residual risks.

## Verification

Static:

- Skill states that issue is the source of truth.
- Skill requires main/default branch refresh before starting when safe and writable.
- Skill prohibits unrelated refactors.
- PR body instructions exclude AI signatures and generated footers.

Runtime:

- Run against a low-risk issue in dry-run mode first.
- Run against one small real issue after L1 triage selects it.
- Confirm branch/worktree isolation.
- Confirm targeted tests run.
- Confirm checker approval is required before PR creation.
- Confirm failure paths update state instead of looping indefinitely.

