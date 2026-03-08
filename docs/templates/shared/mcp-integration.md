## MCP (Model Context Protocol) Integration

### Overview
AI inference gateway includes MCP broker aggregating tools from multiple MCP servers.

### Server Configuration
```json
{
  "mcpServers": {
    "web-search-prime": {
      "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
      "headers": {
        "Authorization": "Bearer /run/agenix/zai-api-key"
      }
    }
  }
}
```

### Protocol Details
- **Format**: JSON-RPC 2.0 over HTTP/SSE
- **Methods**: `initialize`, `tools/list`, `tools/call`
- **Response**: Server-Sent Events (SSE)
- **Critical Header**: `Accept: application/json, text/event-stream`

### Authentication Pattern
Headers with file paths need special handling:
```python
if header_value.startswith("Bearer "):
    file_path = header_value.split(" ", 1)[1].strip()
    with open(file_path, "r") as f:
        api_key = f.read().strip()
        headers[header_name] = f"Bearer {api_key}"
```

### Common Tools
- **webSearchPrime**: Web search with ranking
- **imageSearchPrime**: Image search and analysis

### Usage Examples
```bash
# List available tools
curl http://127.0.0.1:8080/mcp/tools | jq '.'

# Invoke tool
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{"server": "web-search-prime", "tool": "webSearchPrime"}'
```

### Troubleshooting
**400 Bad Request from ZAI MCP**: Missing Accept header
- Fix: Always include `Accept: application/json, text/event-stream`
- See: `.claude/hookify.warn-mcp-accept-headers.local.md`

**404 Not Found**: Incorrect tool name (case-sensitive)
- Fix: Use exact name from `/mcp/tools`
- Example: `webSearchPrime` not `web_search`

### Documentation
- **MCP Spec**: https://modelcontextprotocol.io/
- **Cluster Architecture**: See ROADMAP.md
