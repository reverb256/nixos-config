# SearXNG Default Search Setup

**Status:** ✅ Complete and Verified
**Updated:** 2026-03-17

---

## 🎯 **OVERVIEW**

SearXNG is now configured as the **default search provider** for your NixOS AI cluster. All search operations go through the AI Inference Gateway, providing consistent, cached, and intelligent web search capabilities.

---

## ✅ **WHAT'S WORKING**

### **Core Infrastructure**
- ✅ SearXNG instance running on `http://127.0.0.1:7777`
- ✅ MCP server integration via AI Gateway `http://127.0.0.1:8080`
- ✅ Health monitoring and automatic failover
- ✅ Result caching (5-minute TTL)
- ✅ Query pattern learning and adaptive engine selection

### **Available Search Tools**
| Tool | Purpose | Usage |
|------|---------|-------|
| `web_search` | General web search | `search "query"` |
| `search_github` | GitHub repositories | `search-github "query"` |
| `search_nixos_options` | NixOS documentation | `search-nixos "query"` |
| `search_mdn` | MDN web docs | Direct API call |
| `search_stackoverflow` | Stack Overflow Q&A | Direct API call |
| `search_reddit` | Reddit discussions | Direct API call |
| `search_stats` | View learning statistics | Direct API call |
| `clear_search_cache` | Clear cached results | Direct API call |

---

## 🚀 **USAGE**

### **Command Line Wrappers**

Add to your shell (already done in `~/.bashrc` and `~/.zshrc`):
```bash
export PATH="$HOME/.local/bin:$PATH"
```

#### **General Web Search**
```bash
# Basic usage
search "NixOS configuration"

# Specify number of results
search "kubernetes deployment" 5

# Quick searches
search "python async await" 3
```

#### **GitHub Search**
```bash
# Find repositories
search-github "nixos flake"

# Find code examples
search-github "rust async tokio" 10
```

#### **NixOS Documentation Search**
```bash
# Search configuration options
search-nixos "networking firewall"

# Find specific options
search-nixos "boot loader" 10
```

### **Direct API Access**

#### **Web Search**
```bash
curl -X POST "http://127.0.0.1:8080/mcp/call" \
  -H "Content-Type: application/json" \
  -d '{
    "server": "searxng",
    "tool": "web_search",
    "arguments": {
      "query": "NixOS cluster",
      "max_results": 5,
      "category": "general"
    }
  }' | jq -r '.result' | jq -r '.content[0].text'
```

#### **GitHub Search**
```bash
curl -X POST "http://127.0.0.1:8080/mcp/call" \
  -H "Content-Type: application/json" \
  -d '{
    "server": "searxng",
    "tool": "search_github",
    "arguments": {
      "query": "kubernetes operator",
      "max_results": 10
    }
  }' | jq -r '.result' | jq -r '.content[0].text'
```

#### **NixOS Options Search**
```bash
curl -X POST "http://127.0.0.1:8080/mcp/call" \
  -H "Content-Type: application/json" \
  -d '{
    "server": "searxng",
    "tool": "search_nixos_options",
    "arguments": {
      "query": "networking firewall",
      "max_results": 5
    }
  }' | jq -r '.result' | jq -r '.content[0].text'
```

---

## 📊 **PERFORMANCE & CACHING**

### **Cache Statistics**
```bash
# View current cache stats
curl -X POST "http://127.0.0.1:8080/mcp/call" \
  -H "Content-Type: application/json" \
  -d '{
    "server": "searxng",
    "tool": "search_stats",
    "arguments": {}
  }' | jq -r '.result' | jq '.content[0].text'
```

### **Cache Management**
- **TTL:** 5 minutes (300 seconds)
- **Auto-refresh:** Cached results automatically refresh after TTL
- **Manual clear:** Use `clear_search_cache` tool
- **Cache size:** Track with `search_stats`

---

## 🔧 **ADVANCED CONFIGURATION**

### **Search Categories**
```bash
# General search (default)
search "query" --category general

# Image search
curl -X POST "http://127.0.0.1:8080/mcp/call" \
  -H "Content-Type: application/json" \
  -d '{
    "server": "searxng",
    "tool": "web_search",
    "arguments": {
      "query": "kubernetes architecture",
      "category": "science",
      "max_results": 5
    }
  }'
```

### **Language & Time Filters**
```bash
# English results only
curl -X POST "http://127.0.0.1:8080/mcp/call" \
  -H "Content-Type: application/json" \
  -d '{
    "server": "searxng",
    "tool": "web_search",
    "arguments": {
      "query": "machine learning",
      "language": "en",
      "time_range": "week",
      "max_results": 5
    }
  }'
```

---

## 📈 **MONITORING**

### **Health Checks**
```bash
# Check SearXNG server health
curl -s http://127.0.0.1:8080/mcp/servers | jq '.servers[] | select(.name == "searxng")'

# Expected output:
# {
#   "name": "searxng",
#   "type": "local",
#   "url": null,
#   "healthy": true
# }
```

### **Performance Metrics**
- **Query patterns tracked:** Yes
- **Engine performance monitored:** Yes
- **Success/failure rates:** Tracked
- **Cache hit rates:** Available via `search_stats`

---

## 🆚 **COMPARISON: SearXNG vs Alternatives**

| Feature | SearXNG | web-search-prime | Tavily |
|---------|---------|------------------|--------|
| **Status** | ✅ Working | ❌ API permission issue | 💰 Paid |
| **Cost** | Free | Free | Paid |
| **Privacy** | High | Medium | Medium |
| **Speed** | Fast | Fast | Fastest |
| **Results** | 10 engines | Unknown | Optimized |
| **Caching** | Yes (5min) | No | Yes |
| **Learning** | Adaptive | No | AI-optimized |
| **Setup** | Self-hosted | Remote API | API key |

---

## 🛠️ **MAINTENANCE**

### **Restart SearXNG**
```bash
# Check if SearXNG is running
ps aux | grep searxng

# Restart via systemd (if configured)
sudo systemctl restart searxng

# Or via the AI Gateway
sudo systemctl restart ai-inference-gateway
```

### **Update Configuration**
```bash
# Edit SearXNG settings
sudo nano /etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_servers/searxng_server.py

# Rebuild and restart
cd /etc/nixos
sudo nixos-rebuild switch
```

---

## 📚 **REFERENCE FILES**

- **Setup Script:** `/etc/nixos/scripts/searxng-default-search.sh`
- **Test Script:** `/etc/nixos/scripts/test-search.sh`
- **Search Wrappers:** `~/.local/bin/search*`
- **Server Config:** `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_servers/searxng_server.py`
- **Gateway Config:** `/etc/nixos/modules/services/ai-inference/gateway.nix`

---

## 🎯 **BENEFITS FOR YOUR CLUSTER**

1. **Privacy-First:** No tracking, no profiling
2. **Multi-Engine:** Aggregates Google, Bing, DuckDuckGo, Brave
3. **Intelligent:** Learns from query patterns
4. **Fast:** Local caching reduces latency
5. **Reliable:** Self-hosted, no external dependencies
6. **Free:** No API costs or rate limits
7. **Integrated:** Works with AI Gateway and MCP tools

---

## ✅ **VERIFICATION**

Run the test script to verify everything works:
```bash
/etc/nixos/scripts/test-search.sh
```

Expected output: All three search types should return results.

---

**Status:** ✅ SearXNG is your default search provider and fully operational!
