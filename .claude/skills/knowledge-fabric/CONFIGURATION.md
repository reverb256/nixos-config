# Knowledge Fabric Configuration Guide

## Environment Variables

The Knowledge Fabric uses several environment variables for configuration. These are set in `/home/j_kro/.claude/settings.json`:

```json
{
  "env": {
    "SEARXNG_URL": "http://10.1.1.110:30080",
    "SEARXNG_CACHE_TTL": "300",
    "GATEWAY_URL": "http://127.0.0.1:8080",
    "GATEWAY_TIMEOUT": "30.0"
  }
}
```

### Variable Descriptions

| Variable | Default | Purpose |
|----------|---------|---------|
| `SEARXNG_URL` | http://10.1.1.110:30080 | SearXNG metasearch endpoint (NodePort for LAN access) |
| `SEARXNG_CACHE_TTL` | 300 | Cache time-to-live in seconds |
| `GATEWAY_URL` | http://127.0.0.1:8080 | AI Inference Gateway API endpoint |
| `GATEWAY_TIMEOUT` | 30.0 | Gateway request timeout in seconds |

## Service Endpoints

### SearXNG Metasearch
- **Public URL**: http://10.1.1.110:30080 (NodePort - LAN accessible)
- **ClusterIP**: http://10.0.0.230:7777 (Kubernetes internal)
- **Health Check**: `curl http://10.1.1.110:30080/`

### Qdrant Vector Database
- **HTTP API**: http://127.0.0.1:6333
- **Collections**: `curl http://127.0.0.1:6333/collections`
- **Health**: `curl http://127.0.0.1:6333/`

### Redis Cache
- **Port**: 6380 (custom port)
- **Connection**: `redis-cli -p 6380`
- **Health**: `redis-cli -p 6380 PING`

### AI Inference Gateway
- **API**: http://127.0.0.1:8080
- **Health**: `curl http://127.0.0.1:8080/health`
- **Chat Completions**: POST http://127.0.0.1:8080/v1/chat/completions

## MCP Server Configuration

### Gateway MCP Bridge

The MCP gateway bridge (`mcp-gateway-bridge`) forwards stdio MCP requests to the gateway's HTTP API.

**Configuration** (in Claude settings.json):
```json
{
  "mcpServers": {
    "gateway": {
      "command": "mcp-gateway-bridge"
    }
  }
}
```

**Environment Variables**:
```bash
export GATEWAY_URL="http://127.0.0.1:8080"
export GATEWAY_TIMEOUT="30.0"
```

### SearXNG MCP Server

The SearXNG MCP server provides 13 specialized search tools.

**Direct Usage** (alternative to gateway bridge):
```json
{
  "mcpServers": {
    "searxng": {
      "command": "python",
      "args": ["-m", "ai_inference_gateway.mcp_servers.searxng_server"],
      "env": {
        "SEARXNG_URL": "http://10.1.1.110:30080",
        "SEARXNG_CACHE_TTL": "300"
      }
    }
  }
}
```

## URL Migration Notes

### Kubernetes → NodePort Migration

The system has been updated to use NodePort URLs instead of Kubernetes internal URLs:

| Service | Old URL (K8s Internal) | New URL (NodePort) |
|---------|----------------------|-------------------|
| SearXNG | http://searxng.search.svc.cluster.local:7777 | http://10.1.1.110:30080 |
| SearXNG | http://10.0.0.230:7777 | http://10.1.1.110:30080 |

**Why NodePort?**
- ✅ Accessible from all cluster nodes
- ✅ Works from host machine (Zephyr)
- ✅ More reliable for development/testing
- ✅ No need for Kubernetes network policies

## Testing Configuration

### Verify All Services

```bash
# Test SearXNG (NodePort)
curl -s "http://10.1.1.110:30080/search?q=test&format=json" | jq '.results | length'

# Test Qdrant
curl -s http://127.0.0.1:6333/collections | jq '.result.collections | length'

# Test Redis
redis-cli -p 6380 PING

# Test Gateway
curl -s http://127.0.0.1:8080/health | jq '.status'

# Test MCP Bridge
echo '{"jsonrpc":"2.0","id":1,"method":"ping"}' | mcp-gateway-bridge
```

### Expected Results

| Service | Expected Output |
|---------|----------------|
| SearXNG | `10` (number of results) |
| Qdrant | `8` (number of collections) |
| Redis | `PONG` |
| Gateway | `{"status":"healthy"}` |
| MCP Bridge | JSON-RPC response |

## Troubleshooting

### SearXNG Connection Refused

**Symptom**: `curl: (7) Failed to connect to 10.1.1.110 port 30080`

**Solutions**:
1. Check SearXNG service: `systemctl status searx`
2. Check Kubernetes service: `kubectl get svc -n search`
3. Verify NodePort: `kubectl describe svc searxng -n search`
4. Check firewall: `sudo iptables -L -n | grep 30080`

### Gateway Not Listening

**Symptom**: `curl: (7) Failed to connect to 127.0.0.1 port 8080`

**Solutions**:
1. Check gateway service: `systemctl status ai-inference-gateway`
2. Check gateway logs: `journalctl -u ai-inference-gateway -n 50`
3. Verify syntax: `python3 -m py_compile <path_to_gateway_files>`
4. Restart gateway: `systemctl restart ai-inference-gateway`

### MCP Bridge Issues

**Symptom**: MCP tools not appearing in Claude Code

**Solutions**:
1. Check bridge is executable: `which mcp-gateway-bridge`
2. Test bridge manually: `echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"test","version":"1.0"}}}' | mcp-gateway-bridge`
3. Check settings.json: `cat ~/.claude/settings.json | grep -A5 mcpServers`
4. Restart Claude Code

### Qdrant Connection Issues

**Symptom**: Failed to connect to Qdrant

**Solutions**:
1. Check Qdrant service: `systemctl status qdrant`
2. Check Qdrant logs: `journalctl -u qdrant -n 50`
3. Verify port: `ss -tlnp | grep 6333`
4. Test HTTP API: `curl http://127.0.0.1:6333/`

## Performance Tuning

### Cache TTL

**Default**: 300 seconds (5 minutes)

**Increase** for:
- Static documentation (7200s = 2 hours)
- Infrequently changing content

**Decrease** for:
- Real-time data (60s = 1 minute)
- Rapidly changing content

### Request Timeout

**Default**: 30.0 seconds

**Increase** for:
- Complex queries (60.0s)
- Slow external APIs

**Decrease** for:
- Fast failure detection (10.0s)
- Interactive applications

### Max Results

**SearXNG**: 10 results (default)
- Increase for comprehensive research (20-50)
- Decrease for faster responses (5)

**Knowledge Fabric**: Uses RRF fusion, so can handle more sources
- Each source provides 10 results
- RRF merges and re-ranks all results
- Final output typically 5-15 highest-quality results

## Security Considerations

### NodePort Access

The NodePort (30080) is accessible on the LAN (10.1.1.0/24). For production:

1. **Restrict access** via firewall:
```bash
sudo iptables -A INPUT -p tcp --dport 30080 -s 10.1.1.0/24 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 30080 -j DROP
```

2. **Use ClusterIP** for internal services:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: searxng-internal
spec:
  type: ClusterIP
  ports:
  - port: 7777
```

3. **Enable authentication** in production deployments

### Gateway API

The gateway API (127.0.0.1:8080) is only accessible locally. To expose:

1. **Use reverse proxy** (nginx/caddy) with auth
2. **Enable TLS** for secure connections
3. **Add API key authentication** in production

## Monitoring

### Health Check Script

```bash
#!/usr/bin/env bash
# /usr/local/bin/knowledge-fabric-health

echo "Knowledge Fabric Health Check"
echo "=============================="

# Check SearXNG
if curl -s http://10.1.1.110:30080/ > /dev/null; then
  echo "✓ SearXNG: OPERATIONAL"
else
  echo "✗ SearXNG: DOWN"
fi

# Check Qdrant
if curl -s http://127.0.0.1:6333/ > /dev/null; then
  echo "✓ Qdrant: OPERATIONAL"
else
  echo "✗ Qdrant: DOWN"
fi

# Check Redis
if redis-cli -p 6380 PING > /dev/null 2>&1; then
  echo "✓ Redis: OPERATIONAL"
else
  echo "✗ Redis: DOWN"
fi

# Check Gateway
if curl -s http://127.0.0.1:8080/health > /dev/null; then
  echo "✓ Gateway: OPERATIONAL"
else
  echo "✗ Gateway: DOWN"
fi

echo "=============================="
```

### Prometheus Metrics

The Knowledge Fabric exposes Prometheus metrics:

- `knowledge_fabric_queries_total` - Total queries processed
- `knowledge_fabric_query_duration_seconds` - Query latency
- `knowledge_fabric_source_errors_total` - Source errors
- `knowledge_fabric_rrf_fusion_duration_seconds` - RRF fusion time

Access at: `http://127.0.0.1:8080/metrics`

## Best Practices

1. **Always use environment variables** for configuration
2. **Test all endpoints** after configuration changes
3. **Monitor cache hit rates** to optimize TTL
4. **Use domain-aware routing** for better relevance
5. **Enable quality scoring** for result filtering
6. **Check circuit breaker state** if sources are failing
7. **Review Prometheus metrics** regularly
8. **Keep documentation updated** with any changes

---

**Last Updated**: 2026-03-19
**Version**: 1.0.0
**Status**: ✅ All services operational and tested
