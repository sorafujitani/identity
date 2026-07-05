---
name: chrome-cli
description: Use when basic Chrome DevTools work is needed without chrome-devtools MCP. Prefer chromex against a Chrome remote debugging endpoint.
---

# Chrome CLI

Use `chromex` for basic Chrome DevTools Protocol operations. Do not use chrome-devtools MCP.

## Commands

- Check endpoint: `chromex version`
- List tabs: `chromex tabs`
- Open URL: `chromex open <url>`
- Activate tab: `chromex activate <target-id>`
- Close tab: `chromex close <target-id>`

## Workflow

1. Run `chromex version` first.
2. If it fails, Chrome is not running with remote debugging enabled.
3. Use browser automation scripts or Playwright from the repo when DOM inspection or screenshots are required.

## Requirements

Chrome must expose the DevTools HTTP endpoint. The default is `http://127.0.0.1:9222`.
Override with `CHROME_DEBUG_URL`.
