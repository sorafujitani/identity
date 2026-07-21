---
name: Linear
description: Managing Linear issues, projects, and teams. Use the local linearx CLI instead of Linear MCP.
allowed-tools:
  - Bash
  - WebFetch(domain:linear.app)
---

# Linear

Use `/Users/fujitanisora/.local/bin/linearx` for Linear work. Do not use Linear MCP.

The absolute path is intentional. This wrapper loads `LINEAR_API_KEY` from macOS
Keychain. Do not resolve `linearx` from `PATH`, because agent environments may put
the unwrapped Nix binary first.

## Commands

- Check auth: `/Users/fujitanisora/.local/bin/linearx auth status`
- Current user: `/Users/fujitanisora/.local/bin/linearx viewer`
- Search issues: `/Users/fujitanisora/.local/bin/linearx search '<text>' 20`
- Read issue: `/Users/fujitanisora/.local/bin/linearx issue TAS-123`
- Find team: `/Users/fujitanisora/.local/bin/linearx team ENG`
- Create issue: `/Users/fujitanisora/.local/bin/linearx create <team-id> '<title>' '<description>'`
- Raw GraphQL fallback: `/Users/fujitanisora/.local/bin/linearx query '<graphql>' '<variables-json>'`

## Conventions

When creating implementation issues, use the project naming convention already established in the workspace. Keep descriptions short and WHAT-only unless the user asks for more detail.

## Workflow

1. Run `/Users/fujitanisora/.local/bin/linearx auth status` before API work.
2. Use `/Users/fujitanisora/.local/bin/linearx search` or `/Users/fujitanisora/.local/bin/linearx issue` to anchor on real Linear data.
3. Use raw GraphQL only when the thin commands are insufficient.
4. Do not use MCP tools.

## Requirements

The macOS Keychain entry `linearx.LINEAR_API_KEY` must exist. The wrapper makes
`LINEAR_API_KEY` available to the real CLI; callers do not need to export it.
