# Xquik X Data

Use this plugin when Claude Code needs authenticated X data workflows through Xquik. It points agents to the public REST API, docs, and optional remote MCP server without adding hooks or changing default behavior.

## Setup

1. Create an API key in the Xquik dashboard.
2. Export it before starting Claude Code.

```shell
export XQUIK_API_KEY="xq_your_key"
```

3. Install the plugin from this marketplace.

```text
/plugin install xquik-x-data@cfdude-plugins
```

## Public References

- Docs: https://docs.xquik.com
- OpenAPI: https://xquik.com/openapi.json
- MCP manifest: https://xquik.com/.well-known/mcp.json
- Source: https://github.com/Xquik-dev/x-twitter-scraper
