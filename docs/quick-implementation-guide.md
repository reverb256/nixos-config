# Quick Implementation Guide
## Based on Comprehensive Roadmap

**Last Updated**: 2026-03-05

---

## Immediate Actions (Next 1-2 Weeks)

### ✅ Quick Wins (< 4 hours each)

#### 1. JSON Schema Mode (1 hour)
**File**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/response_format.py`

```python
async def transform_response_format(body: dict) -> dict:
    response_format = body.get("response_format", {})
    if not response_format:
        return body

    format_type = response_format.get("type")
    if format_type == "json_object":
        msg = "Respond ONLY with valid JSON. No markdown, no code blocks."
        body["messages"].insert(0, {"role": "system", "content": msg})
    elif format_type == "json_schema":
        schema = json.dumps(response_format.get("json_schema", {}), indent=2)
        msg = f"Respond ONLY with valid JSON matching:\n{schema}\nNo markdown."
        body["messages"].insert(0, {"role": "system", "content": msg})
    del body["response_format"]
    return body
```

#### 2. MCP Tool Schema Caching (2 hours)
**File**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_cache.py`

- Add in-memory cache with 5-minute TTL
- Warm up schemas on startup
- Add cache metrics

#### 3. Retry with Exponential Backoff (3 hours)
**File**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/retry_handler.py`

- Use tenacity library
- 5 attempts with 1-2-4-8-16s backoff
- Handle rate limits (429) with Retry-After

---

## Medium Priority (Next 2-4 Weeks)

### 4. Semantic Caching (4 hours)
**Requirements**: Redis, Qdrant
- Exact match cache (Redis)
- Semantic cache (vector similarity)
- Cache hit/miss metrics

### 5. RAG URL Ingestion (3 hours)
**Requirements**: MCP web-reader
- Fetch from URLs
- Domain whitelist
- Batch ingestion

### 6. PII Redaction (2 hours)
**File**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/pii_redactor.py`

- Detect and redact: email, SSN, credit card, IP, phone
- Configurable for input/output
- Redaction logging

### 7. Content Moderation (2 hours)
**File**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/moderation.py`

- Block harmful patterns
- Detect jailbreaks
- Configurable strictness

---

## Infrastructure Setup

### Install Services
```bash
# Redis (for caching)
sudo nixos-rebuild switch
# Add to configuration.nix:
services.redis.enable = true;

# Jaeger (for tracing)
services.jaeger.enable = true;

# Qdrant (for semantic cache)
services.qdrant.enable = true;
```

### Python Dependencies
```bash
# Add to requirements.txt
tenacity>=8.2.0
redis>=5.0.0
beautifulsoup4>=4.12.0
qdrant-client>=1.7.0
opentelemetry-api>=1.22.0
opentelemetry-sdk>=1.22.0
```

---

## Recommended Starting Order

1. **JSON Schema Mode** - Critical for compatibility
2. **MCP Caching** - Quick win, immediate performance gain
3. **Retry Logic** - Production reliability
4. **Semantic Caching** - Significant performance improvement
5. **URL Ingestion** - Enhances RAG capabilities
6. **PII/Moderation** - Security requirements

---

## Cost & Timeline

**Solo Developer**: ~60 hours (1.5 months)
**2-3 Developers**: ~2-3 weeks
**4+ Developers**: ~1 week

---

## Files Created

1. `/etc/nixos/docs/gateway-feature-roadmap.md` - Original feature roadmap
2. `/etc/nixos/docs/comprehensive-implementation-roadmap.md` - Complete platform roadmap
3. `/etc/nixos/docs/quick-implementation-guide.md` - This file

---

**See Also**:
- Full roadmap: `/etc/nixos/docs/comprehensive-implementation-roadmap.md`
- Original feature roadmap: `/etc/nixos/docs/gateway-feature-roadmap.md`
- Monitoring guide: `/etc/nixos/docs/ai-inference-monitoring.md`
