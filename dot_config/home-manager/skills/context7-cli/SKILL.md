---
name: context7-cli
description: Use when fetching library documentation that would previously use Context7 MCP. Prefer the local context7x CLI.
---

# Context7 CLI

Use `context7x` for library documentation. Do not use Context7 MCP.

## Commands

- Search libraries: `context7x search '<library-or-framework>'`
- Fetch docs: `context7x docs <library-id> [topic] [tokens]`

## Workflow

1. Search for the library.
2. Pick the most relevant verified or official result.
3. Fetch only the topic needed for the task.
4. Keep excerpts short and cite the source path shown in the output.

## Example

```bash
context7x search react
context7x docs /reactjs/react.dev useState 2000
```
