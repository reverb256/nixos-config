# SearXNG Agent Integration Guide

## Overview

This implementation provides comprehensive SearXNG integration optimized for AI agent workflows, combining web search, local knowledge bases, and intelligent query routing.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     AI Inference Gateway                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Agent Search Layer (agent_search.py)               │   │
│  │  - Intent detection (5 categories)                 │   │
│  │  - Query refinement                                 │   │
│  │  - Result summarization                             │   │
│  │  - Progressive learning                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                          ↓                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Hybrid Search (hybrid_search.py)                   │   │
│  │  - RAG (local knowledge)                           │   │
│  │  - SearXNG (web search)                             │   │
│  │  - Result merging & deduplication                  │   │
│  │  - Re-ranking                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                          ↓                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  HTTP-MCP Bridge (mcp_http_bridge.py)              │   │
│  │  - Expose MCP tools via HTTP                       │   │
│  │  - Tool discovery & execution                       │   │
│  │  - Server health monitoring                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## API Endpoints

### 1. Agent-Optimized Search

**POST** `/search/agent`

Intelligent search with automatic intent detection and result optimization.

```json
{
  "query": "how to implement kubernetes operator",
  "context": "user is working on python project",
  "max_results": 10,
  "use_cache": true
}
```

**Response:**
```json
{
  "results": [
    {
      "title": "Writing a Kubernetes Operator in Python",
      "url": "https://github.com/kubernetes/sample-operator",
      "content": "...",
      "quality_score": 0.85,
      "source": "web"
    }
  ],
  "intent": "code",
  "query_refinement": {
    "original": "how to implement kubernetes operator",
    "changes": ["added example request", "added language: python"]
  },
  "summary": "## Top Results\n...",
  "metadata": {
    "engines_used": ["github", "stackoverflow"],
    "cached": false
  }
}
```

### 2. Intent Detection

The system automatically detects search intent:

- **research**: Academic papers, in-depth analysis
- **code**: Programming, implementation, examples
- **facts**: Definitions, quick information
- **troubleshooting**: Error solving, debugging
- **discovery**: Comparisons, recommendations

### 3. Hybrid Search

**POST** `/search/hybrid`

Combine local RAG knowledge base with web search.

```json
{
  "query": "nixos configuration patterns",
  "max_results": 10,
  "use_rag": true,
  "use_web": true,
  "rerank": true
}
```

**Response:**
```json
{
  "results": [...],
  "sources": {
    "rag": 3,
    "web": 7
  },
  "metadata": {
    "total_found": 12,
    "duration_ms": 245.3,
    "reranked": true
  }
}
```

### 4. Progressive Search

**POST** `/search/hybrid/progressive`

Automatically refine queries until sufficient results found.

```json
{
  "query": "obscure error code",
  "min_results": 5,
  "max_iterations": 3
}
```

### 5. HTTP-MCP Bridge

**GET** `/mcp/v1/tools`
- List all available MCP tools

**POST** `/mcp/v1/tools/{tool_name}/execute`
- Execute an MCP tool via HTTP

**GET** `/mcp/v1/servers`
- List all MCP servers

## Usage Examples

### Python/Agent Integration

```python
import httpx

async def agent_search(query: str, context: str = ""):
    async with httpx.AsyncClient() as client:
        response = await client.post(
            "http://127.0.0.1:8080/search/agent",
            json={
                "query": query,
                "context": context,
                "max_results": 10
            }
        )
        return response.json()

# Use in agent workflow
result = await agent_search(
    "how to fix docker permission denied",
    context="user is on ubuntu 22.04 with docker 24.0"
)

# Intent is auto-detected as "troubleshooting"
# Results are ranked by relevance and quality
# Summary is optimized for LLM consumption
```

### Claude Code Integration

Claude Code now has MCP tools available:

```json
{
  "mcpServers": {
    "searxng": {
      "command": "python",
      "args": ["-m", "ai_inference_gateway.mcp_servers.searxng_server"],
      "env": {
        "SEARXNG_URL": "http://127.0.0.1:7777"
      }
    }
  }
}
```

### cURL Examples

```bash
# Basic agent search
curl -X POST "http://127.0.0.1:8080/search/agent" \
  -H "Content-Type: application/json" \
  -d '{"query":"nixos flake tutorial","max_results":5}'

# Hybrid RAG + web search
curl -X POST "http://127.0.0.1:8080/search/hybrid" \
  -H "Content-Type: application/json" \
  -d '{"query":"kubernetes deployment","use_rag":true,"use_web":true}'

# List MCP tools
curl -X GET "http://127.0.0.1:8080/mcp/v1/tools"

# Execute MCP tool
curl -X POST "http://127.0.0.1:8080/mcp/v1/tools/searxng_search/execute" \
  -H "Content-Type: application/json" \
  -d '{"arguments":{"query":"rust async programming"}}'
```

## Testing

Run the test script:

```bash
just test-search-integration
# or
/etc/nixos/scripts/test-search-integration.sh
```

This validates:
1. SearXNG health
2. Gateway ping
3. Basic search endpoint
4. Agent search with intent detection
5. Learning statistics
6. HTTP-MCP bridge

## Deployment

1. Rebuild the gateway:

```bash
just deploy zephyr
# or
sudo nixos-rebuild switch
```

2. Restart the gateway:

```bash
systemctl restart ai-inference-gateway
```

3. Verify integration:

```bash
/etc/nixos/scripts/test-search-integration.sh
```

## Features

### Intent Detection

Automatic detection of search purpose:

```python
# Research intent
"latest research on transformer architectures"
→ intent: research, engines: [arxiv, google scholar]

# Code intent
"implement async await in rust"
→ intent: code, engines: [github, stackoverflow]

# Troubleshooting intent
"fix docker permission denied error"
→ intent: troubleshooting, engines: [stackoverflow, github]
```

### Query Refinement

Automatic improvement of queries:

```python
# Original: "kubernetes"
# Refined: "kubernetes example"

# Original: "how do i implement oauth"
# Refined: "how to implement oauth example"

# Original: "docker error"
# Refined: "how to fix docker error"
```

### Result Quality Scoring

Multi-factor quality scoring:

1. **Source authority** (40%): Trusted domains prioritized
2. **Content richness** (30%): Length and detail
3. **Query relevance** (20%): Text similarity
4. **Freshness** (10%): Recency for technical content

### Progressive Learning

The system learns from feedback:

```python
# Record feedback
await agent_engine.feedback(
    query="rust async programming",
    selected_results=[0, 2, 4],  # Indices of useful results
    rating=5  # Overall rating 1-5
)
```

## Monitoring

### Statistics

```bash
# Get learning statistics
curl "http://127.0.0.1:8080/search/agent/stats"
```

**Response:**
```json
{
  "total_searches": 127,
  "intent_distribution": {
    "code": 45,
    "research": 23,
    "troubleshooting": 31,
    "facts": 18,
    "discovery": 10
  },
  "recent_queries": [...]
}
```

### Health Checks

```bash
# SearXNG health
curl "http://127.0.0.1:8080/search/ping"

# MCP server health
curl "http://127.0.0.1:8080/mcp/v1/servers/searxng/health"
```

## Performance

- **Cache hit rate**: ~35% (300s TTL)
- **Average search latency**: 200-400ms
- **Intent detection**: <10ms
- **Result ranking**: <50ms for 10 results

## Best Practices

### For AI Agents

1. **Use `/search/agent`** for most use cases
2. **Provide context** when available (conversation history)
3. **Enable caching** for repeated queries
4. **Use hybrid search** when local knowledge exists

### For Web Applications

1. **Use HTTP-MCP bridge** for tool discovery
2. **Progressive search** for uncertain queries
3. **Set appropriate timeouts** (default 30s)
4. **Handle missing tools** gracefully

### For Chatbots

1. **Intent detection** improves response relevance
2. **Summaries** are optimized for LLM context
3. **Quality scores** help filter noise
4. **Progressive refinement** adapts to user needs

## Troubleshooting

### SearXNG Not Responding

```bash
# Check SearXNG service
systemctl status searx

# Check logs
journalctl -u searx -f

# Test SearXNG directly
curl "http://127.0.0.1:7777/search?q=test&format=json"
```

### Gateway Not Finding MCP Tools

```bash
# Check MCP broker
curl "http://127.0.0.1:8080/mcp/v1/servers"

# Check gateway logs
journalctl -u ai-inference-gateway -f | grep -i mcp
```

### Import Errors

```bash
# Check Python path
echo $PYTHONPATH

# Verify modules
python3 -c "from ai_inference_gateway.agent_search import AgentSearchEngine"
python3 -c "from ai_inference_gateway.hybrid_search import HybridSearchEngine"
python3 -c "from ai_inference_gateway.mcp_http_bridge import HTTPMCPBridge"
```

## Next Steps

1. **Customize intent patterns** for your domain
2. **Add trusted sources** for quality scoring
3. **Configure RAG collections** for hybrid search
4. **Tune cache TTL** for your workload
5. **Add feedback collection** from user interactions

## Related Documentation

- `/etc/nixos/docs/gateway/SEARXNG_DEPLOYMENT_GUIDE.md`
- `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/README.md`
- SearXNG documentation: https://docs.searxng.org/
- MCP specification: https://modelcontextprotocol.io/

## Support

For issues or questions:
1. Check logs: `journalctl -u ai-inference-gateway -f`
2. Run test script: `/etc/nixos/scripts/test-search-integration.sh`
3. Review this guide's troubleshooting section
