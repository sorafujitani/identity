---
name: linear
description: Managing Linear issues, projects, and teams. Use when working with Linear tasks, creating issues, updating status, querying projects, or managing team workflows.
allowed-tools:
  - mcp__linear
  - WebFetch(domain:linear.app)
  - Bash
---

# Linear

Tools and workflows for managing issues, projects, and teams in Linear.

## Tool Selection

Choose the right tool for the task:

1. **MCP tools** - Use for simple operations (create/update/query single issues, basic filters)
2. **SDK scripts** - Use for complex operations (loops, bulk updates, conditional logic, data transformations)
3. **GraphQL API** - Fallback for operations not supported by MCP or SDK

## Conventions

### Issue Status

When creating issues, set the appropriate status based on assignment:

- **Assigned to me** (`assignee: "me"`): Set `state: "Todo"`
- **Unassigned**: Set `state: "Backlog"`

Example:
```typescript
// Issue for myself
await linear.create_issue({
  team: "ENG",
  title: "Fix authentication bug",
  assignee: "me",
  state: "Todo"
})

// Unassigned issue
await linear.create_issue({
  team: "ENG",
  title: "Research API performance",
  state: "Backlog"
})
```

### Querying Issues

Use `assignee: "me"` to filter issues assigned to the authenticated user:

```typescript
// My issues
await linear.list_issues({ assignee: "me" })

// Team backlog
await linear.list_issues({ team: "ENG", state: "Backlog" })
```

### Labels

You can use label names directly in `create_issue` and `update_issue` - no need to look up IDs:

```typescript
await linear.create_issue({
  team: "ENG",
  title: "Update documentation",
  labels: ["documentation", "high-priority"]
})
```

## SDK Automation Scripts

**Use only when MCP tools are insufficient.** For complex operations involving loops, mapping, or bulk updates, write TypeScript scripts using `@linear/sdk`. See `sdk.md` for:

- Complete script patterns and templates
- Common automation examples (bulk updates, filtering, reporting)
- Tool selection criteria

Scripts provide full type hints and are easier to debug than raw GraphQL for multi-step operations.

## GraphQL API

**Fallback only.** Use when operations aren't supported by MCP or SDK. See `api.md` for documentation on using the Linear GraphQL API directly.

### linearx CLI fallback

The local `linearx` wrapper currently fails on an internal `jq --argjson` error (`linearx issue`, `linearx query` both die). If it errors, do not retry or debug it mid-task. Fall back immediately:

1. Get the API key from Keychain into a shell variable first, then use it in the header. Expanding it inline on the same line as the assignment yields an empty value (known trap). Never print the key.
   ```bash
   LINEAR_API_KEY=$(security find-generic-password -s linear-api-key -w)
   curl -s https://api.linear.app/graphql \
     -H "Authorization: $LINEAR_API_KEY" -H "Content-Type: application/json" \
     -d '{"query": "..."}'
   ```
2. Known API gotchas, verified in past sessions:
   - `IssueFilter` does not support `identifier`. Fetch a single issue with `issue(id: "TAS-123")` — the identifier works as `id`.
   - Marking an issue as Duplicate requires creating the duplicate relation first, then the state change.
   - Project lookups by slug return empty lists. Use the project **UUID**.
   - Review-comment replies via REST return 404; use GraphQL `reviewThread` mutations (GitHub-side lesson that also applies to Linear comment threading: prefer GraphQL).
3. Working minimal templates for the common mutations (description update, comment create, relation create) live in `api.md`. Extend `api.md` when you hand-build a new one, so the next session reuses it instead of rediscovering it.

### Ad-Hoc Queries

Use `scripts/query.ts` to execute GraphQL queries:

```bash
LINEAR_API_KEY=lin_api_xxx node scripts/query.ts "query { viewer { id name } }"
```

If `LINEAR_API_KEY` is not provided to the Claude process, inform the user that GraphQL queries cannot be executed without an API key.

## Reference

- Linear MCP: https://linear.app/docs/mcp.md
- GraphQL API: See `api.md`
