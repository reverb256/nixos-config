# Z.AI MCP Remote Servers Bug Report

**Date:** 2026-03-14
**Status:** Critical - Z.AI Platform Bug
**Affected Services:** web-search-prime, web-reader, zread, 4-5v-mcp-server

## Bug Description

Z.AI's remote MCP API endpoints inconsistently validate API keys:
- **`tools/list` method**: Works correctly, returns tool schemas
- **`tools/call` method**: Fails with HTTP 401 "Api key not found"

Both methods use the **same API key**, **same headers**, **same base URL**.

## Evidence

```bash
# API Key (50 chars): a304de1a9f0e46fb870d59d884b9616c.4Zeci63KC3W6FzuR

# ✅ WORKS - tools/list
curl -X POST "https://api.z.ai/api/mcp/web_search_prime/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer a304de1a9f0e46fb870d59d884b9616c.4Zeci63KC3W6FzuR" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
# Returns: 200 OK with tool schema

# ❌ FAILS - tools/call
curl -X POST "https://api.z.ai/api/mcp/web_search_prime/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer a304de1a9f0e46fb870d59d884b9616c.4Zeci63KC3W6FzuR" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"web_search_prime","arguments":{"search_query":"test"}}'
# Returns: {"content":[{"text":"MCP error -401: Api key not found..."}],"isError":true}
```

## Why This Happens

The Z.AI MCP server appears to have **inconsistent API key validation**:
1. `tools/list` → Minimal validation, checks if key format is valid
2. `tools/call` → Full validation, checks if key has MCP execution permissions

The API key generated at https://z.ai/manage-apikey/apikey-list may only have permissions for:
- ✅ Chat API (`/api/coding/paas/v4/*`)
- ✅ Vision MCP API (local execution)
- ❌ Remote MCP server execution (`/api/mcp/*` tool execution)

## Workarounds

### Option 1: Contact Z.AI Support
Request MCP execution permissions for the existing API key.

### Option 2: Use Alternative Web Search
Implement a local web search MCP server using:
- **Tavily API**: https://tavily.com
- **Serper API**: https://serper.dev
- **Brave Search API**: https://brave.com/search/api
- **DuckDuckGo HTML**: Direct scraping

### Option 3: Use Chat API for Web Search
The Chat API (`/api/coding/paas/v4/chat/completions`) works with the current API key. However, Z.AI's Chat API doesn't auto-execute web search - it just returns tool calls that the client must execute externally.

## Impact

**Affected tools through gateway:**
- `web-search-prime.web_search_prime` - Web search
- `web-reader.webReader` - URL content extraction
- `zread.search_doc` - GitHub repo search
- `zread.read_file` - GitHub file reading
- `4-5v-mcp-server` - Vision analysis

**Working tools (local MCP servers):**
- `context7.*` - Documentation search
- `nix-rebuild.*` - NixOS rebuild commands
- `add-service.*` - Service creation

## Files

- Gateway: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_broker.py`
- Config: `/etc/nixos/hosts/zephyr/configuration.nix`
- Docs: `/etc/nixos/docs/gateway/WEB_SEARCH_MCP_ISSUE.md`

## Next Steps

1. Contact Z.AI support about MCP endpoint 401 errors
2. Consider implementing local web search MCP server
3. Or use alternative web search API providers
