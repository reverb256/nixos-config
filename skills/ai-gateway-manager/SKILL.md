---
name: ai-gateway-manager
description: Manage the AI inference gateway, LM Studio backend, and MCP servers. Use when user asks to: check gateway status, restart gateway, add MCP server, test API endpoints, configure models, or troubleshoot ai-inference-gateway service.
---

# AI Gateway Manager

Manages the AI inference gateway (`ai-inference-gateway` service) that provides OpenAI-compatible API endpoints and MCP tool aggregation. The ZAI/agenix snippets below are legacy examples retained for historical troubleshooting; do not treat them as the current default secret or provider wiring. Current cluster secrets use `/run/secrets/` and the declarative secretspec/sops configuration.

## When to Use This Skill

Use this skill when the user:
- Asks to "check gateway status", "is the gateway running?", "test the AI API"
- Wants to "add MCP server", "configure MCP", "list MCP tools"
- Needs to "restart gateway", "restart AI service", "reload config"
- Asks about "LM Studio", "backend models", "model configuration"
- Wants to troubleshoot 503 errors, connection issues, or MCP failures
- Asks about "Spacebot", "OpenAI compatibility", "v1/chat/completions"

## Architecture Overview

```
                    ┌─────────────────────────────────────┐
                    │     ai-inference-gateway:8080       │
                    ├─────────────────────────────────────┤
                    │  /v1/*       OpenAI-compatible API  │
                    │  /mcp/*      MCP tool aggregation   │
                    │  /health     Health check endpoint  │
                    │  /metrics    Prometheus metrics     │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────┴──────────────────────┐
                    │
                    ┌▼───────────────┐
                    │  LM Studio     │
                    │  :1234         │
                    └────────────────┘

                    ┌──────────────────────────────────────┐
                    │         MCP Servers                   │
                    ├──────────────────────────────────────┤
                    │ context7          (documentation)    │
                    │ local MCP servers (configured in Nix) │
                    │ 4-5v-mcp-server    (Image analysis)   │
                    │ nix-rebuild        (NixOS rebuilds)   │
                    │ add-service       (Service creation) │
                    └──────────────────────────────────────┘
```

## Gateway Endpoints

### OpenAI-Compatible API
```bash
# List available models
curl http://127.0.0.1:8080/v1/models | jq .

# Chat completion (Spacebot compatible)
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen/qwen3.5-9b",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }' | jq .
```

### MCP Endpoints
```bash
# List all MCP tools
curl http://127.0.0.1:8080/mcp/tools | jq .

# List configured MCP servers
curl http://127.0.0.1:8080/mcp/servers | jq .

# Check MCP server health
curl http://127.0.0.1:8080/mcp/health/web-search-prime | jq .

# Call MCP tool
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "web-search-prime",
    "tool": "webSearchPrime",
    "arguments": {"search_query": "NixOS"}
  }' | jq .
```

### Health & Metrics
```bash
# Overall health
curl http://127.0.0.1:8080/health | jq .

# Prometheus metrics
curl http://127.0.0.1:8080/metrics | grep ai_inference
```

## Service Management

```bash
# Check service status
systemctl status ai-inference-gateway

# View live logs
journalctl -u ai-inference-gateway -f

# Check recent errors
journalctl -u ai-inference-gateway -n 100 --no-pager | grep -i error

# Restart service
systemctl restart ai-inference-gateway

# Check if enabled
systemctl is-enabled ai-inference-gateway
```

## Configuration Location

The gateway is configured in:
```
/etc/nixos/modules/services/ai-inference/
├── gateway.nix           # Main service configuration
├── ai_inference_gateway/
│   ├── main.py           # FastAPI application
│   ├── config.py         # Configuration schemas
│   ├── mcp_broker.py     # MCP server aggregation
│   └── backends/
│       └── lm_studio.py  # LM Studio backend
```

Host-specific configuration in:
```
/etc/nixos/hosts/<hostname>/configuration.nix
```

## Adding New MCP Servers

### 1. Via NixOS Configuration (Recommended)

Edit `/etc/nixos/.mcp.json`:
```json
{
  "mcpServers": {
    "my-new-server": {
      "url": "https://api.example.com/mcp",
      "headers": {
        "Authorization": "Bearer /run/secrets/my-api-key"
      }
    }
  }
}
```

### 2. Via Host Configuration

Add to `hosts/zephyr/configuration.nix`:
```nix
services.ai-inference.mcp.servers = {
  my-new-server = {
    url = "https://api.example.com/mcp";
    headers = {
      Authorization = "Bearer /run/secrets/my-api-key";
    };
  };
};
```

### 3. Rebuild
```bash
just check
just build
just switch
```

## Troubleshooting

### Gateway Not Starting
```bash
# Check service logs for errors
journalctl -u ai-inference-gateway -n 50 --no-page

# Check if port is already in use
sudo lsof -i :8080

# Verify configuration
sudo systemctl show ai-inference-gateway --property=Environment
```

### MCP Tools Not Available

Check the gateway's configured local MCP servers and service logs. The former
ZAI-hosted MCP examples and `/run/agenix/*` paths are retired; current cluster
secret material is provisioned declaratively under `/run/secrets/`.

```bash
# Check gateway MCP tools
curl http://127.0.0.1:8080/mcp/tools | jq '.tools | length'

# Check configured server health
curl http://127.0.0.1:8080/mcp/health/<server-name> | jq .

# Inspect recent gateway errors
journalctl -u ai-inference-gateway -n 100 --no-pager | grep -i mcp
```

### LM Studio Connection Issues
```bash
# Check if LM Studio is running
curl http://127.0.0.1:1234/v1/models

# Check gateway backend health
curl http://127.0.0.1:8080/health | jq .backend

# Test LM Studio directly
curl -X POST http://127.0.0.1:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-2","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
```

### Secret/credential Issues

Verify the declarative secret wiring and the service's environment rather than
reading secret contents directly:

```bash
# Inspect the service's credential-related environment declarations
systemctl show ai-inference-gateway -p Environment

# Validate the declared production secret schema
just secretspec-check
```

## Common Workflows

### Update Gateway Code
1. Edit Python files in `modules/services/ai-inference/ai_inference_gateway/`
2. **IMPORTANT**: `git add` new files before rebuilding
3. `just check && just build && just test-apply`
4. Verify service works, then `just switch`

### Add New API Endpoint
1. Add route in `main.py`
2. Update corresponding handler
3. `git add` changes
4. `just check && just build && just test-apply`

### Debug MCP Integration
1. Test server directly (bypass gateway)
2. Check gateway logs: `journalctl -u ai-inference-gateway -f | grep -i mcp`
3. Verify tool names are exact (case-sensitive)
4. Check Accept header includes `text/event-stream`

## Spacebot Integration

Spacebot uses the gateway as its API backend:
```bash
# Configure Spacebot
spacebot config set api-base-url http://127.0.0.1:8080
spacebot config set model qwen/qwen3.5-9b

# Spacebot can now:
# - Make concurrent requests
# - Get OpenAI-compatible responses
# - Route requests according to the currently configured backend chain
# - Use streaming responses
```

## Related Skills
- **nix-rebuild**: For rebuilding NixOS configuration
- **add-service**: For creating new systemd services
- **lm-studio-manager**: For managing LM Studio models (if available)

## Files Modified When Adding MCP Servers
| File | Purpose |
|------|---------|
| `.mcp.json` | MCP server configurations |
| `secretspec.toml` | Declared secret schema and provider routing |
| `hosts/*/configuration.nix` | Per-host MCP settings |
