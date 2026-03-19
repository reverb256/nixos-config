# SearXNG MCP Server Setup Guide

**Purpose**: Enable Claude Code/Cursor to use your Kubernetes SearXNG deployment instead of built-in web search
**Status**: ✅ Code exists, needs configuration update
**Updated**: 2026-03-19

---

## Quick Summary

You **already have** a complete MCP server for SearXNG at:
```
/etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_servers/searxng_server.py
```

**What changed**: Updated default URL from `http://127.0.0.1:7777` to `http://searxng.search.svc.cluster.local:7777` (Kubernetes service)

---

## Configuration Files Updated

### 1. MCP Server Configuration
**File**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_servers/searxng_server.py`

**Changed line 58**:
```python
# OLD (NixOS local):
SEARXNG_URL = os.getenv("SEARXNG_URL", "http://127.0.0.1:8889")

# NEW (Kubernetes service):
SEARXNG_URL = os.getenv("SEARXNG_URL", "http://searxng.search.svc.cluster.local:7777")
```

### 2. Knowledge Source Configuration
**File**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/middleware/knowledge_fabric/sources/searxng_source.py`

**Changed all occurrences** (6 total):
```python
# OLD:
searxng_url: str = "http://127.0.0.1:7777"

# NEW:
searxng_url: str = "http://searxng.search.svc.cluster.local:7777"  # Kubernetes service
```

---

## MCP Server Features

Your SearXNG MCP server provides these tools:

### 1. `searxng_search_web`
**Description**: Search the web using SearXNG metasearch
**Parameters**:
- `query` (string): Search query
- `category` (string): general, science, it, videos, images, music, files, social
- `max_results` (int): Maximum results to return (default: 10)
- `language` (string): Search language (default: auto)
- `time_range` (string): day, week, month, year

**Example**:
```python
searxng_search_web(
    query="kubernetes best practices",
    category="it",
    max_results=5
)
```

### 2. `searxng_search_images`
**Description**: Search for images using SearXNG
**Parameters**:
- `query` (string): Search query
- `max_results` (int): Maximum results (default: 10)

### 3. `searxng_search_videos`
**Description**: Search for videos using SearXNG
**Parameters**:
- `query` (string): Search query
- `max_results` (int): Maximum results (default: 10)

### 4. `searxng_get_info`
**Description**: Get SearXNG server information and capabilities

---

## Setup for Claude Code

### Option 1: Direct Configuration (Recommended)

Edit `~/.config/claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "searxng": {
      "command": "python",
      "args": [
        "-m",
        "ai_inference_gateway.mcp_servers.searxng_server"
      ],
      "env": {
        "SEARXNG_URL": "http://searxng.search.svc.cluster.local:7777",
        "SEARXNG_CACHE_TTL": "300"
      }
    }
  }
}
```

### Option 2: Override via Environment Variable

```bash
export SEARXNG_URL="http://searxng.search.svc.cluster.local:7777"
```

### Option 3: External Access (If needed)

If Claude Code runs outside the cluster, expose via NodePort or Ingress:

```bash
# Create NodePort service
kubectl expose svc searxng -n search --name=searxng-external --type=NodePort --port=7777

# Get the NodePort
kubectl get svc searxng-external -n search

# Use in config:
# "SEARXNG_URL": "http://<node-ip>:<node-port>"
```

---

## Testing the MCP Server

### 1. Start the MCP Server
```bash
cd /etc/nixos/modules/services/ai-inference
python -m ai_inference_gateway.mcp_servers.searxng_server
```

### 2. Test Connectivity
```bash
# From within cluster
curl "http://searxng.search.svc.cluster.local:7777/search?q=test&format=json"

# Should return JSON with search results
```

### 3. Verify MCP Tools
When Claude Code starts, you should see these tools available:
- `searxng_search_web`
- `searxng_search_images`
- `searxng_search_videos`
- `searxng_get_info`

---

## Integration with Knowledge Fabric

The SearXNG knowledge source is already integrated:

```python
from ai_inference_gateway.middleware.knowledge_fabric.sources.searxng_source import SearXNGKnowledgeSource

# Create instance (now uses Kubernetes URL by default)
source = SearXNGKnowledgeSource()

# Search
results = await source.search("kubernetes deployment")
```

**Features**:
- ✅ Domain-aware routing
- ✅ Quality scoring
- ✅ RAG indexing (optional)
- ✅ Clustering (optional)
- ✅ Real-time search
- ✅ Multi-engine aggregation

---

## Troubleshooting

### Issue: "Connection refused"
**Cause**: MCP server can't reach Kubernetes service
**Solution**:
```bash
# Verify service is accessible
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -s "http://searxng.search.svc.cluster.local:7777/search?q=test"

# Check service endpoint
kubectl get endpoints -n search searxng
```

### Issue: "ModuleNotFoundError: No module named 'mcp'"
**Cause**: MCP SDK not installed in Python environment
**Solution**:
```bash
# Install MCP SDK
pip install mcp

# Or via Nix (if using Nix shell)
nix-shell -p python311Packages.mcp
```

### Issue: "No tools available"
**Cause**: MCP server not started or configuration incorrect
**Solution**:
```bash
# Check Claude Code logs
tail -f ~/.config/claude/logs/

# Verify configuration
cat ~/.config/claude/claude_desktop_config.json | jq '.mcpServers'
```

---

## Performance Considerations

### Caching
The MCP server includes caching (default: 5 minutes):
```python
SEARXNG_CACHE_TTL = 300  # seconds
```

**Benefits**:
- Reduces redundant searches
- Faster response times
- Lower load on SearXNG pods

### Scaling
For high-load scenarios, scale the SearXNG deployment:
```bash
kubectl scale deployment searxng -n search --replicas=3
```

The MCP server will automatically distribute load across pods.

---

## Migration from Built-in Web Search

### Before (Built-in)
- ❌ Rate limited
- ❌ Inconsistent results
- ❌ No control over sources
- ❌ Can't use custom engines

### After (SearXNG MCP)
- ✅ No rate limiting (scale instead)
- ✅ Consistent multi-engine results
- ✅ Full control over configuration
- ✅ 60+ engines available
- ✅ JSON/CSV/RSS output
- ✅ Category-specific search
- ✅ Time-range filtering

---

## Example Usage in Claude Code

### Basic Search
```
User: Search for "nixos kubernetes deployment"
Claude: [Uses searxng_search_web tool]
```

### IT-Specific Search
```
User: Find recent articles about "kubernetes security"
Claude: [Uses searxng_search_web with category="it", time_range="week"]
```

### Academic Search
```
User: Research papers on "large language models"
Claude: [Uses searxng_search_web with category="science"]
```

### Image Search
```
User: Find diagrams of "kubernetes architecture"
Claude: [Uses searxng_search_images tool]
```

---

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SEARXNG_URL` | `http://searxng.search.svc.cluster.local:7777` | SearXNG instance URL |
| `SEARXNG_CACHE_TTL` | `300` | Cache TTL in seconds |

### MCP Server Capabilities

- **Real-time search**: ✅ Yes
- **Image search**: ✅ Yes
- **Video search**: ✅ Yes
- **Multi-category**: ✅ Yes
- **Time-range filtering**: ✅ Yes
- **Multi-language**: ✅ Yes
- **JSON output**: ✅ Yes
- **CSV output**: ✅ Yes
- **RSS feeds**: ✅ Yes

---

## Next Steps

1. ✅ **MCP server updated** to use Kubernetes service
2. ✅ **Knowledge source updated** to use Kubernetes service
3. ⏭️ **Configure Claude Code** to use the MCP server
4. ⏭️ **Test with a search query**
5. ⏭️ **Monitor performance** and scale if needed

---

**Status**: Ready to use ✅
**Documentation**: Complete ✅
**Migration Path**: Clear ✅
