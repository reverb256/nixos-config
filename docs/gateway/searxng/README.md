# SearXNG Metasearch Engine

**Status**: ✅ Deployed | **URL**: http://127.0.0.1:8888
**Version**: Multi-instance cluster (3 instances) | **Updated**: 2026-03-19

---

## Overview

SearXNG is a privacy-respecting metasearch engine that aggregates results from multiple search services. This deployment runs a 3-instance cluster behind NGINX load balancer with Redis caching and AI-optimized routing.

### Architecture

```
┌─────────────────────────────────────┐
│         NGINX Load Balancer         │
│              (Port 8888)             │
└───────────┬─────────────────────────┘
            │
    ┌───────┼───────┬───────┐
    │       │       │       │
┌───▼───┐ ┌▼────┐ ┌▼────┐ ┌▼──────┐
│SearXNG│ │SearXNG│ │SearXNG│ │Valkey │
│  #1   │ │  #2  │ │  #3  │ │ Cache │
│:7777  │ │:7778 │ │:7779 │ │ :6379 │
└───────┘ └─────┘ └─────┘ └───────┘
```

---

## Quick Start

### Check Status

```bash
cd /etc/nixos/docker-compose/searxng-cluster
./deploy.sh status
```

### Test Search

```bash
# Basic search
curl "http://127.0.0.1:8888/search?q=nixos&format=json"

# Test via script
./deploy.sh test "nixos configuration"
```

### Management Commands

```bash
./deploy.sh start    # Start cluster
./deploy.sh stop     # Stop cluster
./deploy.sh restart  # Restart cluster
./deploy.sh status   # Check health
./deploy.sh logs     # View logs
```

---

## Configuration

### Engines (242 total)

**General**: Google, Bing, DuckDuckGo, Brave, Startpage
**Code/IT**: GitHub, GitLab, StackOverflow, StackExchange, Debian, Arch Wiki, Gentoo, Fedora
**Academic**: Google Scholar, Semantic Scholar, ArXiv, PubMed, Crossref, DOAJ, BASE
**Social**: Reddit, Twitter, Mastodon
**Content**: Google Images, Bing Images, YouTube, Dailymotion
**News**: Google News, Bing News
**Files**: PirateBay, YTS
**Music**: SoundCloud, Deezer
**Maps**: OpenStreetMap
**DevOps**: Docker Hub, NPM, PyPI

### Performance Settings

- **Connection pooling**: 100 connections
- **HTTP/2**: Enabled
- **Retry logic**: 403, 429, 500, 502, 503
- **Timeouts**: 5s request, 10s max
- **Cache**: Valkey (Redis fork), 256MB, LRU eviction

### Load Balancing

- **Algorithm**: Least connections
- **Weights**: Instance 1 (3), Instance 2 (2), Instance 3 (1)
- **Health checks**: 30s interval, 3 retries
- **Failover**: Automatic

---

## Integration

### Knowledge Fabric Integration

SearXNG is integrated into the AI inference gateway's Knowledge Fabric system for domain-aware search:

```python
# Domain-aware routing
domains = {
    "code": ["github", "gitlab", "stackoverflow"],
    "research": ["google scholar", "arxiv", "semantic scholar"],
    "devops": ["docker hub", "npm", "kubernetes"]
}
```

### MCP Server Tools

The SearXNG MCP server provides 4 domain-specific tools:
- `code_search`: GitHub, GitLab, StackOverflow
- `research_search`: Scholar, ArXiv, Semantic Scholar
- `devops_search`: Docker Hub, NPM, Kubernetes docs
- `general_search`: Google, Bing, DuckDuckGo

### Prometheus Metrics

Available at `http://127.0.0.1:8888/stats`:

- `searxng_requests_total` - Total search requests
- `searxng_cache_hits_total` - Cache hit count
- `searxng_response_time_seconds` - Response time histogram
- `searxng_engine_errors_total` - Engine error count

---

## Deployment Files

| File | Purpose | Location |
|------|---------|----------|
| `docker-compose.yml` | Multi-instance cluster | `/etc/nixos/docker-compose/searxng-cluster/` |
| `nginx/nginx.conf` | Load balancer config | Same directory |
| `config/searxng_settings.yml` | Engine configuration | Same directory |
| `.env` | Environment variables | Same directory (create from `.env.example`) |
| `deploy.sh` | Management script | Same directory |
| `redis-cache.nix` | NixOS Valkey module | `/etc/nixos/modules/services/` |

---

## Maintenance

### Daily Checks

```bash
# Check cluster health
./deploy.sh status

# Monitor response times
curl -w "@curl-format.txt" "http://127.0.0.1:8888/search?q=test"
```

### Weekly Tasks

```bash
# Review error logs
docker logs searxng-1 2>&1 | grep ERROR | tail -50

# Check cache hit rate
redis-cli -p 6379 INFO stats | grep keyspace

# Test all engine categories
./deploy.sh test "code"     # Code engines
./deploy.sh test "research" # Academic engines
./deploy.sh test "news"     # News engines
```

### Troubleshooting

**High response times**:
```bash
# Check if cache is working
redis-cli -p 6379 INFO stats

# Restart cluster
./deploy.sh restart
```

**Engine failures**:
```bash
# Check which engines are failing
docker logs searxng-1 2>&1 | grep "engine"

# Test specific engine
curl "http://127.0.0.1:8888/search?q=test&engines=google"
```

**Load balancer issues**:
```bash
# Check NGINX status
docker logs nginx-lb 2>&1 | tail -50

# Test individual instances
curl "http://127.0.0.1:7777/search?q=test"
curl "http://127.0.0.1:7778/search?q=test"
curl "http://127.0.0.1:7779/search?q=test"
```

---

## Performance Optimization

### Cache Configuration

Current settings (optimal for most workloads):
- **Max memory**: 256MB
- **Eviction policy**: allkeys-lru
- **Persistence**: Disabled (pure cache)

### Tuning for Specific Workloads

**Heavy code search workload**:
```yaml
# Increase cache size
maxmemory: 512mb

# Pin code engines to cache
# (engine-specific caching in settings.yml)
```

**Low-latency requirement**:
```yaml
# Reduce timeouts
timeout: 3  # from 5

# Enable HTTP/3 (future)
enable_http3: true
```

---

## References

### Official Documentation
- [SearXNG Documentation](https://docs.searxng.org/)
- [Engine Configuration](https://searxng.github.io/searxng/admin/settings/)
- [Installation Guide](https://searxng.github.io/searxng/admin/installation.html)

### Internal Documentation
- `modules/services/ai-inference/ai_inference_gateway/middleware/knowledge_fabric/` - Knowledge Fabric integration
- `docs/gateway/SEARXNG_UPGRADE_GUIDE.md` - Archived: upgrade history
- `k8s/SEARXNG-MCP-SETUP.md` - Archived: Kubernetes deployment

---

## History

- **2026-03-19**: Consolidated from 17 separate documents
- **2026-03-17**: Multi-instance deployment completed
- **2026-03-15**: AI integration and domain-aware routing added
- **2026-03-10**: Initial single-instance deployment
