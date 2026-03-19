# SearXNG AI Integration Guide

**Endpoint**: `http://10.0.0.230:7777` (internal) or via Ingress (external)
**Formats**: JSON, CSV, RSS
**Optimized**: For AI inference pipelines and LLM consumption

---

## API Endpoints

### Search (JSON)
```bash
GET /search?q={query}&format=json
```

**Parameters**:
- `q`: Search query (required)
- `format`: `json`, `csv`, `rss`, or `html` (default)
- `categories`: `general`, `science`, `it`, `videos`, `images`, `music`, `files`, `social`
- `language`: `auto`, `en`, `de`, `fr`, `es`, etc.
- `time_range`: `day`, `week`, `month`, `year`
- `safesearch`: `0` (none), `1` (moderate), `2` (strict)
- `pageno`: Page number (default: 1)

### Example: AI Search Pipeline
```python
import requests
import json

def search_ai(query, category="general", max_results=10):
    """Execute search and return structured results for AI processing"""
    url = "http://10.0.0.230:7777/search"
    params = {
        "q": query,
        "format": "json",
        "categories": category,
        "language": "auto"
    }

    response = requests.get(url, params=params)
    data = response.json()

    # Return top results with metadata
    return [
        {
            "title": r["title"],
            "url": r["url"],
            "snippet": r.get("content", ""),
            "engine": r["engine"],
            "score": r["score"],
            "category": r["category"]
        }
        for r in data["results"][:max_results]
    ]

# Usage
results = search_ai("kubernetes best practices", category="it")
print(json.dumps(results, indent=2))
```

---

## JSON Response Schema

```json
{
  "query": "search query",
  "results": [
    {
      "title": "Result title",
      "url": "https://example.com",
      "content": "Snippet/description text",
      "engine": "google",
      "score": 4.5,
      "category": "general"
    }
  ],
  "answers": [
    {
      "title": "Direct answer",
      "url": "https://example.com",
      "content": "Answer content"
    }
  ],
  "infoboxes": [],
  "suggestions": []
}
```

---

## AI-Optimized Features

### 1. **Multi-Category Search**
```bash
# IT/Code search
curl "http://10.0.0.230:7777/search?q=async+python&format=json&categories=it"

# Academic search
curl "http://10.0.0.230:7777/search?q=machine+learning&format=json&categories=science"

# Video search
curl "http://10.0.0.230:7777/search?q=tutorial&format=json&categories=videos"
```

### 2. **Time-Ranged Search**
```bash
# Recent results (last day)
curl "http://10.0.0.230:7777/search?q=ai+news&format=json&time_range=day"

# Past week
curl "http://10.0.0.230:7777/search?q=llm&format=json&time_range=week"

# Past year
curl "http://10.0.0.230:7777/search?q=kubernetes&format=json&time_range=year"
```

### 3. **Site-Specific Search**
```bash
# Search specific domain
curl "http://10.0.0.230:7777/search?q=deployment+site:kubernetes.io&format=json"

# Search GitHub
curl "http://10.0.0.230:7777/search?q=rag+site:github.com&format=json&categories=it"
```

---

## Integration Examples

### RAG Pipeline Integration
```python
def retrieve_context(query, top_k=5):
    """Retrieve relevant context for RAG systems"""
    results = search_ai(query, max_results=top_k)
    return "\n\n".join([
        f"{r['title']}\n{r['snippet']}\nSource: {r['url']}"
        for r in results
    ])

# Use in LLM prompt
context = retrieve_context("nixos kubernetes")
prompt = f"Context:\n{context}\n\nQuestion: How do I deploy to Kubernetes?"
```

### Knowledge Fabric Integration
```python
# Your existing MCP server can use:
import requests

def searxng_search(query):
    """Search via SearXNG for knowledge fabric"""
    response = requests.get(
        "http://10.0.0.230:7777/search",
        params={"q": query, "format": "json"}
    )
    return response.json()

# Integrate with your existing sources
def multi_source_search(query):
    results = {
        "searxng": searxng_search(query),
        # ... other sources
    }
    return aggregate_results(results)
```

### Batch Processing (CSV)
```bash
# Export to CSV for batch AI processing
curl "http://10.0.0.230:7777/search?q=nixos&format=csv" > results.csv

# Process with pandas
python << EOF
import pandas as pd
df = pd.read_csv('results.csv')
# AI processing on DataFrame
print(df[['title', 'url', 'score']])
EOF
```

---

## Performance Tips

### 1. **Connection Pooling** (Already configured)
- 100 concurrent connections
- HTTP/2 enabled
- 12-second timeout (prevents hangs)

### 2. **Scaling for High Load**
```bash
# Scale horizontally for AI workloads
kubectl scale deployment searxng -n search --replicas=3

# Or use HPA for auto-scaling
kubectl autoscale deployment searxng -n search \
  --min=2 --max=10 --cpu-percent=70
```

### 3. **Caching Strategy**
```python
# Cache results to reduce redundant searches
from functools import lru_cache
import hashlib

@lru_cache(maxsize=1000)
def cached_search(query):
    # Hash query to ensure valid cache key
    return search_ai(query)

# Or use Redis for distributed caching
def redis_search(query):
    cache_key = f"searxng:{hashlib.md5(query.encode()).hexdigest()}"
    cached = redis.get(cache_key)
    if cached:
        return json.loads(cached)

    results = search_ai(query)
    redis.setex(cache_key, 3600, json.dumps(results))
    return results
```

---

## Monitoring & Metrics

### Check Search Health
```bash
# Pod status
kubectl get pods -n search

# Recent logs
kubectl logs -n search deployment/searxng --tail=50

# Search metrics (if enabled in settings.yml)
curl "http://10.0.0.230:7777/stats"
```

### Common Issues & Solutions

**Issue**: Timeouts on complex queries
```yaml
# Already fixed: request_timeout: 12.0 (was 3.0)
# Max timeout: 18.0 seconds
```

**Issue**: Engine 403 errors
```yaml
# Already fixed: retries: 2
# Retries on: 403, 429, 500, 502, 503, 504
```

**Issue**: Rate limiting warnings
```yaml
# Already configured: limiter: false
# Scale horizontally instead of rate limiting
```

---

## Configuration Reference

**Current Settings** (in `/etc/searxng/settings.yml`):
- ✅ JSON/CSV/RSS formats enabled
- ✅ 12-second timeout (no more DuckDuckGo failures)
- ✅ Retry logic for 403/429 errors
- ✅ No rate limiting (scale horizontally instead)
- ✅ Connection pooling (100 concurrent)
- ✅ HTTP/2 enabled
- ✅ Custom user agent

---

## Quick Test Commands

```bash
# Test JSON output
curl -s "http://10.0.0.230:7777/search?q=test&format=json" | jq '.results | length'

# Test specific category
curl -s "http://10.0.0.230:7777/search?q=kubernetes&format=json&categories=it" | jq '.results[0]'

# Test CSV output
curl -s "http://10.0.0.230:7777/search?q=nixos&format=csv" | head -5

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -s "http://searxng.search.svc.cluster.local:7777/search?q=test&format=json" | jq '.'
```

---

**Status**: Ready for AI integration ✅
**Structured Output**: JSON, CSV, RSS enabled ✅
**Performance**: Optimized for high concurrency ✅
**Scaling**: Horizontal scaling ready ✅
