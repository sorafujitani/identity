---
name: datadog-cli
description: Use when investigating Datadog logs, traces, spans, monitors, or production telemetry. Prefer the local ddx CLI instead of Datadog MCP.
---

# Datadog CLI

Use `ddx` for Datadog work. Do not use Datadog MCP.

## Commands

- Check auth: `ddx auth status`
- Search logs: `ddx logs search '<query>' now-30m now 20`
- Search spans: `ddx spans search '<query>' now-30m now 20`
- Raw API fallback: `ddx api GET /api/v1/validate`

## Workflow

1. Start with a narrow time window.
2. Include `env`, `service`, and error filters when known.
3. Prefer aggregate evidence before raw event dumps.
4. Return the exact command shape and a short interpretation.

## Requirements

`DD_API_KEY` and `DD_APP_KEY` must be available in the shell environment.
Set `DD_SITE` if the account is not on `datadoghq.com`.
