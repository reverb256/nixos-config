# Web Search MCP Tool - 401 Authentication Issue

**Date:** 2026-03-14
**Status:** Open - Requires Z.AI API key update

## Problem

The Z.AI remote MCP servers (`web-search-prime`, `web-reader`, `zread`, `4-5v-mcp-server`) return HTTP 401 "Api key not found" errors when called through the AI Inference Gateway.

## Root Cause

The Z.AI API has **separate permissions/scopes** for:
1. **Chat API endpoints** (`/api/coding/paas/v4/*`) - ✅ Working
2. **MCP endpoints** (`/api/mcp/*`) - ❌ Failing with 401

The current API key (`/run/agenix/zai-api-key`) has permission for Chat API but NOT for MCP endpoints.

## Evidence

```bash
# Chat API - WORKS
curl -X POST "https://api.z.ai/api/coding/paas/v4/chat/completions" \
  -H "Authorization: Bearer $(cat /run/agenix/zai-api-key)" \
  -d '{"model":"glm-4.5-air","messages":[{"role":"user","content":"hi"}]}'
# Returns: 200 OK with valid response

# MCP API - FAILS
curl -X POST "https://api.z.ai/api/mcp/web_search_prime/mcp" \
  -H "Authorization: Bearer $(cat /run/agenix/zai-api-key)" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"web_search_prime","arguments":{"search_query":"test"}}}'
# Returns: 401 "MCP error -401: Api key not found, please get your apikey"
```

## What Works

- ✅ Local MCP servers (context7, nix-rebuild, add-service)
- ✅ Z.AI Chat API with function calling
- ✅ Gateway's MCP broker infrastructure
- ✅ SSE response parsing
- ✅ API key file loading from `/run/agenix/zai-api-key`

## What Doesn't Work

- ❌ Z.AI remote MCP servers (web-search-prime, web-reader, zread, 4-5v-mcp-server)

## Solution

### Option 1: Get MCP-enabled API Key from Z.AI

1. Visit https://z.ai/manage-apikey/apikey-list
2. Create a new API key or update the existing one
3. Ensure the key has permissions for:
   - Chat API (`/api/coding/paas/v4/*`)
   - MCP endpoints (`/api/mcp/*`)
4. Update `/etc/nixos/secrets/zai-api-key.age` with the new key
5. Run: `sudo nixos-rebuild switch`

### Option 2: Use Alternative Web Search

Implement a local web search MCP server using:
- Tavily API
- Serper API
- Brave Search API
- DuckDuckGo HTML scraping

## Testing

After fixing the API key:

```bash
# Test gateway web search
curl -X POST "http://127.0.0.1:8080/mcp/call" \
  -H "Content-Type: application/json" \
  -d '{"server":"web-search-prime","tool":"web_search_prime","arguments":{"search_query":"kubernetes tutorial"}}'

# Expected: JSON with search results (not 401 error)
```

## Files Modified

- `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_broker.py`
  - Fixed tool name mapping: `webSearchPrime` → `web_search_prime`
  - Added proper 401 detection for Chat API fallback
  - Implemented two-step Chat API execution (though Chat API doesn't execute web_search)

## Related Documentation

- Z.AI API Reference: https://docs.z.ai/api-reference/introduction
- Z.AI MCP Server: https://docs.z.ai/devpack/mcp/vision-mcp-server
- Gateway docs: `/etc/nixos/docs/gateway/`
