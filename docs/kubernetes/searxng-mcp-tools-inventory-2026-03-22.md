# SearXNG MCP Tools - Complete Inventory

**Date**: 2026-03-22
**Source**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_servers/searxng_server.py`

## ✅ All Tools Present and Functional

### General Search Tools (1 tool)

| Tool | Purpose | Status |
|------|---------|--------|
| **web_search** | Multi-engine web search (Google, Bing, DuckDuckGo, etc.) | ✅ Implemented |

### Domain-Specific AI-Optimized Tools (4 tools)

| Tool | Domain | Purpose | Status |
|------|--------|---------|--------|
| **search_code** | Code | GitHub, StackOverflow, GitLab, developer docs | ✅ Implemented |
| **search_research** | Research | Google Scholar, ArXiv, Semantic Scholar, academic | ✅ Implemented |
| **search_devops** | DevOps | Docker Hub, GitLab, infrastructure docs | ✅ Implemented |
| **search_data** | Data Science | HuggingFace, Kaggle, ML papers, AI repos | ✅ Implemented |

### Site-Specific Search Tools (5 tools)

| Tool | Site | Purpose | Status |
|------|-----|---------|--------|
| **search_github** | GitHub | Repositories, code, discussions | ✅ Implemented |
| **search_nixos_options** | NixOS | Configuration options manual | ✅ Implemented |
| **search_mdn** | MDN | Web development docs (HTML, CSS, JS) | ✅ Implemented |
| **search_stackoverflow** | Stack Overflow | Programming Q&A | ✅ Implemented |
| **search_reddit** | Reddit | Community discussions | ✅ Implemented |

### Utility Tools (3 tools)

| Tool | Purpose | Status |
|------|---------|--------|
| **search_stats** | Learning statistics, cache size, top queries | ✅ Implemented |
| **clear_search_cache** | Clear SearXNG cache | ✅ Implemented |
| **ping_searxng** | Health check, connection status | ✅ Implemented |

---

## Knowledge Fabric Skill Coverage

**Skill File**: `/etc/nixos/.claude/skills/knowledge-fabric/SKILL.md`

The skill expects these tools (all present ✅):

| Required Tool | Available? | Notes |
|--------------|------------|-------|
| search_code | ✅ Yes | Matches perfectly |
| search_research | ✅ Yes | Matches perfectly |
| search_devops | ✅ Yes | Matches perfectly |
| search_data | ✅ Yes | Matches perfectly |
| search_github | ✅ Yes | Matches perfectly |
| search_stackoverflow | ✅ Yes | Matches perfectly |
| search_nixos_options | ✅ Yes | Matches perfectly |
| web_search | ✅ Yes | Matches perfectly |
| ping_searxng | ✅ Yes | Matches perfectly |

**Result**: 100% coverage - all expected tools are present and implemented.

---

## Tool Features

### Input Parameters

**WebSearchParams** (for web_search):
- `query` (required): Search query string
- `category`: Search category (default: "general")
- `max_results`: 1-50 results (default: 10)
- `language`: Language filter (default: "all")
- `time_range`: Time filter (day, week, month, year)
- `use_cache`: Use cached results (default: true)

**SiteSearchParams** (for all domain/site tools):
- `query` (required): Search query string
- `max_results`: 1-50 results (default: 10)
- `use_cache`: Use cached results (default: true)

### Categories Supported

**web_search categories**:
- general, images, videos, news, science, IT, files, music, map

### Output Format

Each tool returns:
```markdown
# Search Results for: {query}
**Category:** {category}
**Cached:** {true/false}
**Engines:** {engines_used}

## 1. {title}
- **URL:** {url}
- **Engine:** {engine}
- **Snippet:** {content}
```

---

## Configuration

**Environment Variables**:
```bash
SEARXNG_URL="http://10.0.0.102:8080"  # K8s ClusterIP
SEARXNG_CACHE_TTL="300"                    # 5 minutes
```

**MCP Server Info**:
- **Name**: mcp-searxng
- **Version**: 1.0.0
- **Transport**: stdio (standard input/output)
- **Wrapper**: `/etc/nixos/modules/services/ai-inference/bin/opencode-searxng-mcp`

---

## Summary

✅ **All 13 SearXNG MCP tools are implemented and available**

**Categories**:
- 1 general search tool
- 4 domain-optimized tools (code, research, devops, data)
- 5 site-specific tools (GitHub, NixOS, MDN, StackOverflow, Reddit)
- 3 utility tools (stats, cache clear, ping)

**Integration Status**:
- ✅ SearXNG service: 11 pods running in Kubernetes
- ✅ MCP server: 2 processes active
- ✅ Configuration: Using K8s service URL (http://10.0.0.102:8080)
- ✅ Cache: 300-second TTL with learning enabled
- ✅ Knowledge fabric skill: 100% tool coverage

**Performance**:
- Cache TTL: 5 minutes (auto-refresh)
- Learning enabled: Query pattern optimization
- Adaptive engine selection: Auto-improving
- Max results: 1-50 (configurable)

---

**Status**: ✅ **COMPLETE** - All SearXNG MCP tools operational
