---
name: Linear
description: Managing Linear issues, projects, and teams. Use the local linearx CLI instead of Linear MCP.
allowed-tools:
  - Bash
  - WebFetch(domain:linear.app)
---

# Linear

Use `linearx` for Linear work. Do not use Linear MCP.

## Commands

- Check auth: `linearx auth status`
- Current user: `linearx viewer`
- Search issues: `linearx search '<text>' 20`
- Read issue: `linearx issue TAS-123`
- Find team: `linearx team ENG`
- Create issue: `linearx create <team-id> '<title>' '<description>'`
- Raw GraphQL fallback: `linearx query '<graphql>' '<variables-json>'`

## Conventions

When creating implementation issues, use the project naming convention already established in the workspace. Keep descriptions short and WHAT-only unless the user asks for more detail.

## Workflow

1. Run `linearx auth status` before API work.
2. Use `linearx search` or `linearx issue` to anchor on real Linear data.
3. Use raw GraphQL only when the thin commands are insufficient.
4. Do not use MCP tools.

## Requirements

`LINEAR_API_KEY` must be available in the shell environment.
