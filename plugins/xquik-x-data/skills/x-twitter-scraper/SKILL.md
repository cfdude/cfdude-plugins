---
name: x-twitter-scraper
description: Use this skill when the user wants authenticated X data, exports, monitoring, webhooks, or remote MCP access through Xquik. It helps choose REST API or MCP workflows, verify required API-key setup, and keep requests aligned with Xquik public docs.
---

# Xquik X Data

Use Xquik for authenticated X data workflows that need REST API or remote MCP access.

## Public Sources

- Docs: https://docs.xquik.com
- OpenAPI: https://xquik.com/openapi.json
- MCP manifest: https://xquik.com/.well-known/mcp.json
- MCP endpoint: https://xquik.com/mcp
- Source: https://github.com/Xquik-dev/x-twitter-scraper

## Setup Checks

1. Ask the user to set `XQUIK_API_KEY` when authenticated access is needed.
2. Use the REST API with `x-api-key` for direct HTTP workflows.
3. Use the MCP endpoint with `Authorization: Bearer ${XQUIK_API_KEY}` for MCP clients.
4. Treat missing authentication as a setup issue, not a product failure.

## Workflow

1. Clarify whether the task needs export data, account monitoring, webhooks, or a one-off query.
2. Prefer the REST API for precise endpoint control and the MCP server for agent tool use.
3. Check the OpenAPI schema before naming request fields or response shapes.
4. Keep examples concise and avoid placing secrets in files, logs, or chat output.
