---
name: notion-cli
description: Use when searching, reading, or updating Notion from Codex without Notion MCP. Prefer the official ntn CLI.
---

# Notion CLI

Use the official `ntn` CLI for Notion work. Do not use Notion MCP.

## Commands

- Check version: `ntn --version`
- Log in: `ntn login`
- Search: `ntn api v1/search query='<text>' page_size:=10`
- Read page metadata: `ntn api v1/pages/<page-id>`
- Read page/block children: `ntn api v1/blocks/<block-id>/children?page_size=100`
- Raw API fallback: `ntn api <path> [fields...]`

## Workflow

1. Run `ntn --version` first.
2. Read the selected page or block children before summarizing.
3. For edits, prepare the exact API body and keep the scope small.
4. If auth is missing, run `ntn login` or report that login is required. Do not fall back to MCP.

## Requirements

`ntn` stores credentials in the system keychain after `ntn login`.
