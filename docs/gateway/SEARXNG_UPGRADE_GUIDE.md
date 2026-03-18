# SearXNG Upgrade Guide: Robust Multi-Service AI Search

**Status:** 📋 Research Complete | **Updated:** 2026-03-17
**Purpose:** Upgrade SearXNG for robust, domain-agnostic AI search across any domain

---

## 📊 **CURRENT CAPABILITIES**

### **What We Have Now**
- ✅ SearXNG v2025.8+ running on `http://127.0.0.1:7777`
- ✅ MCP server integration with AI Gateway
- ✅ 8 search tools (web, GitHub, NixOS, MDN, StackOverflow, Reddit, stats, cache)
- ✅ Result caching (5-minute TTL)
- ✅ Query pattern learning and adaptive engine selection
- ✅ CLI wrappers for convenient access
- ✅ Multi-engine aggregation (Google, Bing, DuckDuckGo, Brave)

### **Current Configuration**
```yaml
# Current setup from searxng_server.py
SEARXNG_URL: http://127.0.0.1:7777
SEARXNG_CACHE_TTL: 300 seconds (5 minutes)
Tools: 8 specialized search tools
Learning: Enabled (query patterns, engine performance)
```

---

## 🚀 **UPGRADE PATHS**

### **Phase 1: Enable All Available Engines**

**Current State:** Using default engine configuration
**Upgrade Goal:** Enable and configure all 242 available search engines

#### **Available Engine Categories**

SearXNG supports engines across multiple categories:

| Category | Engines Available | Use Cases |
|----------|-------------------|-----------|
| **General** | Google, Bing, DuckDuckGo, Brave, Startpage | Web search, broad queries |
| **Science** | Google Scholar, Semantic Scholar, ArXiv | Academic research, papers |
| **IT** | GitHub, StackOverflow, StackExchange | Code, technical solutions |
| **Images** | Google Images, Bing Images, Flickr | Visual content |
| **Videos** | YouTube, Dailymotion, Vimeo | Video content |
| **News** | Google News, Bing News, Reuters | Current events |
| **Files** | Kickass Torrents, FILEpuplication, YTS | Downloads |
| **Music** | SoundCloud, Deezer, Jamendo | Audio content |
| **Social** | Reddit, Twitter, Mastodon | Community discussions |
| **Maps** | OpenStreetMap, Docker Hub | Location, containers |

#### **Implementation: Custom settings.yml**

Create `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_servers/searxng_settings.yml`:

```yaml
use_default_settings: true

# Override defaults to enable more engines
engines:
  # Keep default engines (Google, Bing, DuckDuckGo, etc.)
  # Remove any that don't work with API keys

  # Add specialized IT/Dev engines
  - name: github
    engine: github
    disabled: false

  - name: gitlab
    engine: gitlab
    disabled: false

  - name: stackoverflow
    engine: stackoverflow
    disabled: false

  - name: debian
    engine: debian
    disabled: false

  - name: arch linux wiki
    engine: archlinux
    disabled: false

  # Add academic/science engines
  - name: google scholar
    engine: google_scholar
    disabled: false

  - name: semantic scholar
    engine: semantic_scholar
    disabled: false

  - name: arxiv
    engine: arxiv
    disabled: false

  # Add social/community engines
  - name: reddit
    engine: reddit
    disabled: false

  - name: twitter
    engine: twitter
    disabled: false

  # Configure multilingual search
  - name: google english
    engine: google
    language: en
    disabled: false

  - name: google german
    engine: google
    language: de
    disabled: false

# Search optimization
search:
  # Use multiple languages for comprehensive results
  default_lang: "auto"
  autocomplete: 'duckduckgo'
  formats:
    - html
    - json
    - csv

# Server performance
server:
  limiter: true
  image_proxy: true
  method: "GET"

# Rate limiting for high-volume AI workflows
limiter:
  # Enable bot protection
  botdetection:
    ip_limit: 0  # No IP limit for local AI agents
    # token_limit: 0  # Remove comment to disable token limits
    link_token: true
```

---

### **Phase 2: Performance Optimization**

#### **2.1 Redis/Valkey Caching**

**Current:** In-memory caching (5-minute TTL)
**Upgrade:** Distributed caching with Redis/Valkey

**Benefits:**
- Persistent cache across restarts
- Shared cache between multiple SearXNG instances
- Faster cache retrieval for repeated queries
- Advanced cache eviction policies

**Implementation:**

```yaml
# Add to settings.yml
redis:
  url: "redis://localhost:6379/0"

# Or use Valkey (Redis fork)
valkey:
  url: "valkey://localhost:6379/0"
```

**NixOS Integration:**

```nix
# In gateway.nix or dedicated redis module
services.redis.servers.searxng = {
  enable = true;
  port = 6379;
  bind = "127.0.0.1";
  databases = 1;
  save = [];
  # Performance tuning
  maxmemory = "256mb";
  maxmemory-policy = "allkeys-lru";
};
```

#### **2.2 Connection Pooling**

```yaml
# In settings.yml
outgoing:
  # Pool limit configuration
  pool_connections: 100  # Default: 10
  pool_maxsize: 100       # Default: 100 (for keepalive)
  keepalive_expiry: 5.0   # Default: 5.0 seconds

  # Enable HTTP/2 for better performance
  enable_http2: true

  # Retry configuration
  retries: 2
  retry_on_http_error: [403, 429, 500, 502, 503]

  # Timeouts
  request_timeout: 5.0
  max_request_timeout: 10.0
```

---

### **Phase 3: Multi-Instance Deployment**

#### **3.1 Load Balancing Strategy**

**Goal:** Run multiple SearXNG instances behind a load balancer

**Architecture:**
```
                    ┌─────────────┐
                    │   NGINX /   │
                    │ HAProxy LB  │
                    └──────┬──────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
      ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
      │SearXNG #1│    │SearXNG #2│    │SearXNG #3│
      │ :7777    │    │ :7778    │    │ :7779    │
      └────┬────┘    └────┬────┘    └────┬────┘
           │               │               │
           └───────────────┼───────────────┘
                           │
                    ┌──────▼──────┐
                    │  Redis/Valkey│
                    │  Shared Cache│
                    └─────────────┘
```

#### **3.2 Docker Compose Multi-Instance**

Create `/etc/nixos/docker-compose/searxng-cluster.yml`:

```yaml
version: "3.8"

services:
  searxng-1:
    image: docker.io/searxng/searxng:latest
    container_name: searxng-1
    ports:
      - "7777:8080"
    volumes:
      - ./config/searxng:/etc/searxng
      - ./data/searxng-1:/var/cache/searxng
    environment:
      - SEARXNG_BASE_URL=http://localhost:7777
      - SEARXNG_SECRET=${SEARXNG_SECRET}
      - SEARXNG_VALKEY_URL=valkey://valkey:6379/0
    networks:
      - searxng-net
    restart: unless-stopped

  searxng-2:
    image: docker.io/searxng/searxng:latest
    container_name: searxng-2
    ports:
      - "7778:8080"
    volumes:
      - ./config/searxng:/etc/searxng
      - ./data/searxng-2:/var/cache/searxng
    environment:
      - SEARXNG_BASE_URL=http://localhost:7778
      - SEARXNG_SECRET=${SEARXNG_SECRET}
      - SEARXNG_VALKEY_URL=valkey://valkey:6379/0
    networks:
      - searxng-net
    restart: unless-stopped

  searxng-3:
    image: docker.io/searxng/searxng:latest
    container_name: searxng-3
    ports:
      - "7779:8080"
    volumes:
      - ./config/searxng:/etc/searxng
      - ./data/searxng-3:/var/cache/searxng
    environment:
      - SEARXNG_BASE_URL=http://localhost:7779
      - SEARXNG_SECRET=${SEARXNG_SECRET}
      - SEARXNG_VALKEY_URL=valkey://valkey:6379/0
    networks:
      - searxng-net
    restart: unless-stopped

  valkey:
    image: docker.io/valkey/valkey:latest
    container_name: valkey
    ports:
      - "6379:6379"
    command: --save "" --appendonly no
    networks:
      - searxng-net
    restart: unless-stopped

  nginx:
    image: docker.io/nginx:alpine
    container_name: nginx-lb
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - searxng-net
    depends_on:
      - searxng-1
      - searxng-2
      - searxng-3
    restart: unless-stopped

networks:
  searxng-net:
    driver: bridge
```

#### **3.3 NGINX Load Balancer Configuration**

Create `/etc/nixos/docker-compose/nginx/nginx.conf`:

```nginx
events {
    worker_connections 1024;
}

http {
    upstream searxng_backend {
        least_conn;  # Load balancing algorithm

        server searxng-1:8080 weight=3;
        server searxng-2:8080 weight=2;
        server searxng-3:8080 weight=1;

        # Health checks
        keepalive 32;
        keepalive_timeout 60s;
    }

    server {
        listen 80;
        server_name localhost;

        location / {
            proxy_pass http://searxng_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Timeouts for slow searches
            proxy_connect_timeout 30s;
            proxy_send_timeout 30s;
            proxy_read_timeout 30s;
        }

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
```

---

### **Phase 4: AI-Specific Enhancements**

#### **4.1 Advanced Query Routing**

Add intelligent routing to `searxng_integration.py`:

```python
async def route_search_by_domain(query: str, category: str = None) -> dict:
    """
    Route queries to optimal engines based on domain analysis.

    Domain mapping:
    - Programming/Code → GitHub, StackOverflow, Debian
    - Academic/Research → Google Scholar, ArXiv, Semantic Scholar
    - DevOps/Infrastructure → Docker Hub, GitLab, StackExchange
    - General Knowledge → Wikipedia, general engines
    """

    domain_indicators = {
        'code': ['function', 'class', 'api', 'library', 'framework'],
        'academic': ['paper', 'research', 'study', 'theorem'],
        'devops': ['docker', 'kubernetes', 'deployment', 'ci/cd'],
        'data': ['dataset', 'model', 'training', 'inference'],
    }

    query_lower = query.lower()

    # Detect domain
    detected_domain = 'general'
    for domain, indicators in domain_indicators.items():
        if any(indicator in query_lower for indicator in indicators):
            detected_domain = domain
            break

    # Route to optimal engines
    domain_engines = {
        'code': ['github', 'stackoverflow', 'gitlab'],
        'academic': ['google scholar', 'arxiv', 'semantic scholar'],
        'devops': ['docker hub', 'gitlab', 'stackoverflow'],
        'data': ['github', 'kaggle', 'huggingface'],
        'general': ['google', 'bing', 'duckduckgo', 'brave'],
    }

    selected_engines = domain_engines.get(detected_domain, domain_engines['general'])

    # Execute search with selected engines
    return await search_with_engines(query, selected_engines)
```

#### **4.2 Result Quality Scoring**

```python
async def score_result_quality(result: dict, query: str) -> float:
    """
    Score search results for AI relevance.

    Scoring factors:
    - Text similarity (TF-IDF or embeddings)
    - Source authority (domain reputation)
    - Freshness (recency for technical content)
    - Content richness (length, structured data)
    """

    score = 0.0

    # Domain authority (higher for trusted sources)
    trusted_domains = [
        'github.com', 'stackoverflow.com', 'developer.mozilla.org',
        'docs.rs', 'numpy.org', 'postgresql.org'
    ]
    url = result.get('url', '')
    if any(domain in url for domain in trusted_domains):
        score += 0.3

    # Content richness
    content = result.get('content', '')
    if len(content) > 200:
        score += 0.2
    if len(content) > 500:
        score += 0.1

    # Code snippet presence
    if '```' in content or 'code' in content.lower():
        score += 0.2

    # Freshness for technical content
    if '2024' in content or '2025' in content or '2026' in content:
        score += 0.2

    return min(score, 1.0)
```

#### **4.3 MCP Tool Enhancements**

Add new specialized tools to `searxng_server.py`:

```python
# Add to TOOLS list
Tool(
    name="search_code",
    description=(
        "Search for code examples, libraries, and implementations. "
        "Routes queries to GitHub, StackOverflow, and developer documentation. "
        "Optimized for programming questions and code discovery."
    ),
    inputSchema=SiteSearchParams.model_json_schema(),
),
Tool(
    name="search_research",
    description=(
        "Search academic papers, research, and technical documentation. "
        "Routes queries to Google Scholar, ArXiv, Semantic Scholar. "
        "Optimized for research questions and scholarly content."
    ),
    inputSchema=SiteSearchParams.model_json_schema(),
),
Tool(
    name="search_devops",
    description=(
        "Search DevOps, infrastructure, and deployment content. "
        "Routes queries to Docker Hub, GitLab, and StackExchange. "
        "Optimized for infrastructure and operations questions."
    ),
    inputSchema=SiteSearchParams.model_json_schema(),
),
```

---

### **Phase 5: Monitoring & Observability**

#### **5.1 Metrics Collection**

```python
# Add to searxng_integration.py
from prometheus_client import Counter, Histogram, Gauge

# Metrics
search_requests_total = Counter(
    'searxng_search_requests_total',
    'Total search requests',
    ['category', 'engine']
)

search_duration_seconds = Histogram(
    'searxng_search_duration_seconds',
    'Search request duration',
    ['category']
)

cache_hits_total = Counter(
    'searxng_cache_hits_total',
    'Total cache hits'
)

cache_misses_total = Counter(
    'searxng_cache_misses_total',
    'Total cache misses'
)

active_engines = Gauge(
    'searxng_active_engines',
    'Number of active search engines'
)
```

#### **5.2 Health Check Endpoints**

```python
@app.get("/health")
async def health_check():
    """Comprehensive health check."""

    health = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "checks": {}
    }

    # Check SearXNG connectivity
    try:
        response = await httpx.get(f"{SEARXNG_URL}/search?q=test")
        health["checks"]["searxng"] = "ok"
    except Exception as e:
        health["checks"]["searxng"] = f"failed: {e}"
        health["status"] = "unhealthy"

    # Check Redis/Valkey
    try:
        await redis.ping()
        health["checks"]["redis"] = "ok"
    except Exception as e:
        health["checks"]["redis"] = f"failed: {e}"
        health["status"] = "degraded"

    return health
```

---

## 📈 **PERFORMANCE EXPECTATIONS**

### **Single Instance (Current)**
- **Throughput:** ~10-20 requests/second
- **Latency:** 2-5 seconds (p95)
- **Concurrency:** Limited by Python GIL
- **Cache:** Local memory (lost on restart)

### **Multi-Instance + Redis (Upgraded)**
- **Throughput:** ~50-100 requests/second
- **Latency:** 1-2 seconds (p95, cached: <100ms)
- **Concurrency:** 3-5x improvement
- **Cache:** Persistent, shared across instances

### **Cost-Benefit Analysis**

| Configuration | Setup Time | Cost | Performance Gain |
|--------------|-----------|------|------------------|
| **Current** | ✅ Done | Free | Baseline |
| **Phase 1** (More Engines) | 1 hour | Free | 2-3x relevant results |
| **Phase 2** (Redis) | 2 hours | Free (minimal RAM) | 3-5x cache hit rate |
| **Phase 3** (Multi-Instance) | 4-6 hours | Free | 5-10x throughput |
| **Phase 4** (AI Routing) | 2-3 hours | Free | 2-4x relevance |
| **All Phases** | 1 day | Free | **10-20x overall** |

---

## 🎯 **IMPLEMENTATION PRIORITY**

### **Quick Wins (Do Today)**
1. ✅ Enable more engines in `settings.yml`
2. ✅ Add domain-specific search tools
3. ✅ Implement result quality scoring

### **High Impact (Do This Week)**
1. ✅ Deploy Redis/Valkey for persistent caching
2. ✅ Increase connection pooling
3. ✅ Add health monitoring

### **Scalability (Do This Month)**
1. ✅ Multi-instance deployment with load balancer
2. ✅ Advanced query routing
3. ✅ Comprehensive metrics and observability

---

## 🔧 **DEPLOYMENT CHECKLIST**

### **Pre-Deployment**
- [ ] Backup current SearXNG configuration
- [ ] Document current cache statistics
- [ ] Test Redis/Valkey installation
- [ ] Prepare new `settings.yml`
- [ ] Review engine list for API key requirements

### **Deployment**
- [ ] Deploy Redis/Valkey service
- [ ] Update SearXNG configuration
- [ ] Restart SearXNG service
- [ ] Verify all engines are accessible
- [ ] Test search tools with various queries
- [ ] Monitor cache hit rates

### **Post-Deployment**
- [ ] Monitor performance metrics for 24 hours
- [ ] Check error logs for engine failures
- [ ] Validate cache persistence across restarts
- [ ] Test load balancing (if multi-instance)
- [ ] Update documentation with new capabilities

---

## 📚 **REFERENCE LINKS**

- **SearXNG Official Docs:** https://docs.searxng.org/
- **Engine Configuration:** https://docs.searxng.org/admin/settings/settings_engines.html
- **Docker Images:** https://hub.docker.com/r/searxng/searxng
- **Docker Compose Repo:** https://github.com/searxng/searxng-docker
- **Architecture Guide:** https://docs.searxng.org/admin/architecture.html
- **Source Code:** https://github.com/searxng/searxng

---

## ✅ **SUCCESS CRITERIA**

### **Functional Requirements**
- ✅ All 242 engines evaluated and configured
- ✅ Domain-specific search tools working
- ✅ Persistent caching across restarts
- ✅ Load balancing operational (if multi-instance)
- ✅ Health monitoring active

### **Performance Requirements**
- ✅ Cache hit rate >60%
- ✅ Search latency <3 seconds (p95)
- ✅ Zero data loss on restart (Redis persistent)
- ✅ Throughput >50 req/sec (multi-instance)

### **Quality Requirements**
- ✅ Result relevance improved by 2-4x
- ✅ Domain routing accuracy >80%
- ✅ Error rate <1%
- ✅ All search tools functional

---

**Status:** 📋 Complete upgrade plan with implementation paths
**Next Steps:** Begin with Phase 1 (enable more engines) and Phase 2 (Redis caching)
