# AI Inference Gateway - Feature Roadmap 2026

**Last Updated**: 2026-03-05
**Gateway Version**: 2.0.0
**Status**: Planning & Prioritization

---

## Executive Summary

This roadmap outlines planned enhancements for the AI Inference Gateway based on modern production requirements and cutting-edge techniques as of March 2026. The gateway currently provides solid foundational capabilities (routing, metrics, RAG, MCP) but lacks several features that are becoming standard in production AI systems.

### Current State Assessment

| Category | Status | Coverage |
|----------|--------|----------|
| **Model Routing** | ✅ Implemented | Basic intelligent routing, token-based selection |
| **Observability** | ✅ Implemented | Comprehensive per-model metrics, Grafana dashboards |
| **RAG** | 🟡 Partial | Ingestion exists, but no URL fetching |
| **MCP Integration** | 🟡 Partial | Tool calling exists, but no schema caching |
| **JSON Mode** | ❌ Missing | No response_format transformation |
| **Resilience** | 🟡 Partial | Circuit breaker exists, but limited retry logic |
| **Streaming** | ✅ Implemented | SSE streaming supported |
| **Caching** | ❌ Missing | No semantic or KV caching |
| **Multi-Agent** | ❌ Missing | No agent orchestration |
| **Security** | 🟡 Partial | Basic auth, no advanced governance |

---

## Priority Matrix

```
HIGH PRIORITY (Production Readiness)
├── response_format transformation (JSON mode)
├── Semantic caching with compression
├── MCP tool schema caching
└── Enhanced retry with exponential backoff

MEDIUM PRIORITY (Enhanced Capabilities)
├── **Multi-GPU distributed architecture** ⚡ **NEW**
├── RAG URL ingestion (web-reader integration)
├── Request governance (content moderation, PII redaction)
├── Multi-agent orchestration
├── Observability enhancements (distributed tracing)
└── Cost optimization (token budgeting, auto-degradation)

LOW PRIORITY (Advanced Features)
├── Speculative decoding integration
├── Prompt optimization/compression
├── A/B testing framework
└── Multi-model ensembling
```

---

## Roadmap Phases

### Phase 1: Production Readiness (Weeks 1-4)

**Goal**: Achieve production-grade reliability and compatibility

#### 1.1 response_format Transformation ⚡ HIGH
**Estimated**: 1 hour
**Impact**: Critical for OpenAI compatibility

**Problem**:
- OpenAI clients expect `response_format: {type: "json_object"}` or `response_format: {type: "json_schema", json_schema: {...}}`
- LM Studio doesn't natively support structured outputs
- JSON-mode clients break when gateway doesn't handle response_format

**Solution**:
```python
# Transform OpenAI response_format → LM Studio instructions
RESPONSE_FORMAT_TRANSFORMS = {
    "json_object": "Respond ONLY with valid JSON. No markdown, no code blocks.",
    "json_schema": lambda schema: (
        f"Respond ONLY with valid JSON matching this schema:\n"
        f"{json.dumps(schema)}\n"
        f"No markdown, no code blocks, no explanations."
    ),
    "text": None  # No transformation needed
}

# In chat completions endpoint:
if "response_format" in body:
    format_spec = body["response_format"]
    if format_spec.get("type") == "json_object":
        system_msg = "You must respond with valid JSON only."
        body["messages"].insert(0, {"role": "system", "content": system_msg})
    elif format_spec.get("type") == "json_schema":
        schema = format_spec.get("json_schema", {})
        system_msg = format_schema_as_instruction(schema)
        body["messages"].insert(0, {"role": "system", "content": system_msg})
```

**Acceptance Criteria**:
- ✅ OpenAI SDK `response_format={type:"json_object"}` works
- ✅ OpenAI SDK `response_format={type:"json_schema", ...}` works
- ✅ LM Studio returns valid JSON responses
- ✅ No breaking changes for non-JSON requests

**Related Research**:
- [OpenAI Structured Outputs](https://platform.openai.com/docs/guides/structured-outputs)
- [Qwen JSON Schema Mode (2026)](https://help.aliyun.com/zh/model-studio/developer-reference/json-mode)

---

#### 1.2 Enhanced Retry with Exponential Backoff ⚡ HIGH
**Estimated**: 3 hours
**Impact**: High availability, reduced failures

**Problem**:
- Limited retry logic exists
- No exponential backoff
- Rate limit errors aren't handled intelligently

**Solution**:
```python
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type,
    before_sleep_log
)

class RetryableError(Exception):
    """Base class for errors that should trigger retry."""
    pass

class RateLimitError(RetryableError):
    """Rate limit exceeded - retry with backoff."""
    pass

class TimeoutError(RetryableError):
    """Request timeout - retry."""
    pass

class OverloadedError(RetryableError):
    """Service overloaded - retry with backoff."""
    pass

@retry(
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=1, min=1, max=60),
    retry=retry_if_exception_type(RetryableError),
    before_sleep=before_sleep_log(logger, logging.WARNING)
)
async def call_backend_with_retry(
    client,
    messages,
    model,
    stream=False,
    max_tokens=None
):
    """Call backend with intelligent retry logic."""
    try:
        response = await client.chat_completion(
            messages=messages,
            model=model,
            stream=stream,
            max_tokens=max_tokens
        )
        return response
    except httpx.HTTPStatusError as e:
        if e.response.status_code == 429:
            # Rate limit - extract retry-after if available
            retry_after = e.response.headers.get("Retry-After")
            if retry_after:
                wait_time = int(retry_after)
                logger.warning(f"Rate limited, retry after {wait_time}s")
                await asyncio.sleep(wait_time)
            raise RateLimitError(f"Rate limited: {e}")
        elif e.response.status_code >= 500:
            raise OverloadedError(f"Backend overloaded: {e}")
        elif e.response.status_code in (408, 504):
            raise TimeoutError(f"Request timeout: {e}")
        else:
            # Don't retry client errors (4xx except 429)
            raise
    except (httpx.ConnectTimeout, httpx.ReadTimeout) as e:
        raise TimeoutError(f"Connection timeout: {e}")
```

**Configuration**:
```python
# In GatewayConfig
retry_config = {
    "max_attempts": 5,
    "initial_backoff_ms": 1000,
    "max_backoff_ms": 60000,
    "multiplier": 2.0,
    "jitter_ms": 500,  # Add randomness to prevent thundering herd
    "retryable_status_codes": [408, 429, 500, 502, 503, 504]
}
```

**Acceptance Criteria**:
- ✅ Exponential backoff: 1s → 2s → 4s → 8s → 16s
- ✅ Jitter added to prevent synchronized retries
- ✅ Rate limit (429) triggers retry with Retry-After header respect
- ✅ 5xx errors trigger retry
- ✅ 4xx errors (except 429) don't retry
- ✅ Max 5 retry attempts
- ✅ Configurable via NixOS options

**Related Research**:
- [Portkey AI Gateway Retry](https://portkey.ai/docs/gateway-capabilities/retries)
- [Tenacity Retry Library](https://tenacity.readthedocs.io/)
- [Exponential Backoff Patterns](https://github.com/census-instrumentation/opencensus-python/blob/master/contrib/opencensus-ext-retry/opencensus/ext/retry/utils.py)

---

#### 1.3 MCP Tool Schema Caching ⚡ HIGH
**Estimated**: 2 hours
**Impact**: Performance, reduced MCP server load

**Problem**:
- Every `get_tools()` call hits the MCP server
- Repeated tool schema queries waste network calls
- No TTL or freshness management

**Solution**:
```python
from typing import Dict, List, Optional
from datetime import datetime, timedelta
import hashlib
import json

class ToolSchemaCache:
    """Cache MCP tool schemas with TTL."""

    def __init__(self, default_ttl_seconds: int = 300):
        self.cache: Dict[str, CachedSchema] = {}
        self.default_ttl = timedelta(seconds=default_ttl_seconds)

    @dataclass
    class CachedSchema:
        schema: Dict
        cached_at: datetime
        ttl: timedelta
        etag: Optional[str] = None

        def is_fresh(self) -> bool:
            return datetime.now() < (self.cached_at + self.ttl)

    def _make_key(self, server_name: str) -> str:
        return f"tools:{server_name}"

    async def get_tools(
        self,
        server_name: str,
        force_refresh: bool = False
    ) -> Optional[List[Dict]]:
        """Get tools from cache or fetch from server."""
        cache_key = self._make_key(server_name)

        # Check cache
        if not force_refresh and cache_key in self.cache:
            cached = self.cache[cache_key]
            if cached.is_fresh():
                logger.debug(f"Cache HIT: {server_name}")
                return cached.schema["tools"]

        # Cache miss or stale - fetch from server
        logger.debug(f"Cache MISS: {server_name}")
        tools = await self._fetch_tools_from_server(server_name)

        if tools:
            self.cache[cache_key] = CachedSchema(
                schema={"tools": tools},
                cached_at=datetime.now(),
                ttl=self.default_ttl
            )

        return tools

    async def invalidate(self, server_name: str):
        """Invalidate cache for a server."""
        cache_key = self._make_key(server_name)
        self.cache.pop(cache_key, None)
        logger.info(f"Invalidated cache for {server_name}")

    async def warm_up(self, servers: List[str]):
        """Pre-fetch tool schemas for all servers."""
        tasks = [self.get_tools(server) for server in servers]
        await asyncio.gather(*tasks, return_exceptions=True)
        logger.info(f"Warmed up cache for {len(servers)} servers")
```

**Integration into MCPBroker**:
```python
class MCPBroker:
    def __init__(self, servers: List[MCPServer], cache_ttl: int = 300):
        self.servers = {server.name: server for server in servers}
        self.tool_cache = ToolSchemaCache(default_ttl_seconds=cache_ttl)

    async def get_tools(self, server_name: Optional[str] = None) -> List[Dict]:
        """Get tools with caching."""
        if server_name:
            tools = await self.tool_cache.get_tools(server_name)
            return tools or []

        # Get tools from all servers
        all_tools = []
        for name in self.servers.keys():
            tools = await self.tool_cache.get_tools(name)
            if tools:
                all_tools.extend(tools)
        return all_tools
```

**NixOS Configuration**:
```nix
# In ai-inference gateway config
mcp = {
  enable = true;
  cache_ttl_seconds = mkOption {
    default = 300;  # 5 minutes
    type = types.int;
    description = "TTL for MCP tool schema cache";
  };

  warmup_on_startup = mkOption {
    default = true;
    type = types.bool;
    description = "Pre-fetch tool schemas on gateway startup";
  };
};
```

**Acceptance Criteria**:
- ✅ Tool schemas cached for 5 minutes (configurable)
- ✅ Cache HIT returns immediately (no network call)
- ✅ Cache MISS fetches from MCP server
- ✅ TTL-based invalidation
- ✅ Manual invalidation API endpoint
- ✅ Warm-up on startup
- ✅ Cache metrics (hit rate, miss rate)

**Related Research**:
- [Azure AI Gateway MCP Governance](https://azure.microsoft.com/en-us/products/ai-services/ai-gateway)
- [AgentGateway (Linux Foundation)](https://github.com/agentgateway/agentgateway)
- [Redis Caching Patterns](https://redis.io/docs/manual/patterns/caching/)

---

### Phase 1.5: Multi-GPU Distributed Architecture ⚡ **NEW**

**Goal**: Distribute LM Studio across 3 machines for optimal Spacebot performance
**Estimated**: 7-11 hours
**Status**: Design Complete, Ready for Implementation
**Date Added**: 2026-03-05

#### Architecture Overview

Distribute LM Studio instances across 3 machines with 5 GPUs total (56GB VRAM):

```
                    AI Inference Gateway (zephyr:8080)
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
         Zephyr (32GB)      Forge (16GB)      Nexus (8GB)
         ─────────────      ─────────────      ─────────────
         3090: 24GB         4060 #1: 8GB       3060 Ti: 8GB
         3060 Ti: 8GB       4060 #2: 8GB
         Multi-GPU ✅       Multi-GPU ✅       Single GPU
         75/25 split        50/50 split
```

#### Problem

- Single machine (zephyr) has 32GB VRAM limit
- Spacebot's 5-process architecture needs varied model sizes
- Cortex requires 256K context for long-term memory (35B models)
- Channels/Workers need faster responses (9B/4B models)
- No intelligent routing across multiple machines

#### Solution - Three-Tier Model Distribution

**Tier 1 - Large Models (Zephyr - 32GB):**
- qwen3.5-35b-a3b (17GB + 8GB KV cache @ 256K) = 25GB ✅
- qwen3.5-27b (15GB + 6GB KV cache @ 256K) = 21GB ✅
- Context: 256K tokens with quantized KV cache
- Speed: 110-150 tokens/sec
- Target: Cortex, complex Workers

**Tier 2 - Medium Models (Forge - 16GB):**
- qwen3.5-9b (5.1GB + 2GB KV cache @ 64K) = 7.1GB per GPU ✅
- crow-9b-opus-4.6-distill-heretic_qwen3.5 (5GB + 2GB KV cache) = 7GB per GPU ✅
- Context: 64K tokens (configurable to 128K with multi-GPU)
- Speed: ~200 tokens/sec
- Target: Channels, Branches, standard Workers

**Tier 3 - Small/Fast Models (Nexus - 8GB):**
- qwen3.5-4b (2.5GB + 0.5GB KV cache @ 32K) = 3GB ✅
- qwen3.5-2b (1.9GB + 0.2GB KV cache @ 16K) = 2.1GB ✅
- Context: 16-32K tokens
- Speed: 300-400 tokens/sec
- Target: Compactor, quick tool execution

#### Implementation

**Step 1: Configure Forge (1-2 hours)**
```bash
# Install LM Studio
# Configure hardware-config.json (50/50 split)
# Download qwen3.5-9b-IQ4_NL.gguf
# Enable API server on port 1234
curl http://forge:1234/v1/models  # Verify
```

**Step 2: Configure Nexus (1-2 hours)**
```bash
# Install LM Studio
# Download qwen3.5-4b-IQ4_NL.gguf
# Enable API server on port 1234
curl http://nexus:1234/v1/models  # Verify
```

**Step 3: Update Gateway (2-3 hours)**

Create multi-backend NixOS module:
```nix
services.ai-inference.backend = {
  type = "multi-backend";

  tier1 = {  # Zephyr
    enable = true;
    url = "http://127.0.0.1:1234";
    maxModelSize = "32GB";
    models = ["qwen3.5-35b-a3b", "qwen3.5-27b"];
  };

  tier2 = {  # Forge
    enable = true;
    url = "http://forge:1234";
    maxModelSize = "16GB";
    models = ["qwen3.5-9b", "crow-9b-*"];
  };

  tier3 = {  # Nexus
    enable = true;
    url = "http://nexus:1234";
    maxModelSize = "8GB";
    models = ["qwen3.5-4b", "qwen3.5-2b"];
  };
};
```

Update router.py with model-to-backend mapping:
```python
MODEL_BACKENDS = {
    "qwen3.5-35b-a3b": {"backend": "tier1", "url": "http://127.0.0.1:1234"},
    "qwen3.5-27b": {"backend": "tier1", "url": "http://127.0.0.1:1234"},
    "qwen3.5-9b": {"backend": "tier2", "url": "http://forge:1234", "overflow": "tier1"},
    "qwen3.5-4b": {"backend": "tier3", "url": "http://nexus:1234", "overflow": "tier2"},
}
```

**Step 4: Testing (2-3 hours)**
- Test each Spacebot process routing
- Measure throughput (target: >1000 t/s total)
- Test overflow scenarios
- Validate failover

#### Per-Spacebot-Process Model Assignment

| Process | Model | Context | Backend | Speed |
|---------|-------|---------|---------|-------|
| Cortex | qwen3.5-35b-a3b | 256K | Zephyr | 110 t/s |
| Workers (complex) | qwen3.5-35b-a3b | 256K | Zephyr | 110 t/s |
| Workers (standard) | qwen3.5-27b | 128K | Zephyr | 150 t/s |
| Channels | qwen3.5-9b | 32K | Forge | 200 t/s |
| Branches | qwen3.5-9b-claude-4.6-opus | 64K | Forge | 200 t/s |
| Compactor | qwen3.5-4b | 16K | Nexus | 300 t/s |

#### Expected Performance

| Backend | Model | Context | Speed | Concurrent | Total |
|---------|-------|---------|-------|------------|-------|
| Zephyr | 35B A3B | 256K | 110 t/s | 1 | 110 t/s |
| Zephyr | 27B | 256K | 150 t/s | 1 | 150 t/s |
| Forge | 9B | 64K | 200 t/s | 2 | 400 t/s |
| Nexus | 4B | 32K | 300 t/s | 3 | 900 t/s |
| **Total** | - | - | - | - | **~1500 t/s** |

#### Acceptance Criteria

- [ ] All three LM Studio instances running
- [ ] Gateway routing configured correctly
- [ ] Cortex gets 110 t/s with 256K context ✅
- [ ] Channels get 200 t/s with 32K context ✅
- [ ] Compactor gets 300 t/s with 16K context ✅
- [ ] Overflow routing works (forge → zephyr, nexus → forge)
- [ ] Health checks detect backend failures
- [ ] All Spacebot processes functional
- [ ] Total throughput > 1000 t/s
- [ ] No backend exceeds 90% VRAM utilization

#### Related Documentation

- **Design Document**: `docs/plans/2026-03-05-multi-gpu-lmstudio-architecture.md`
- **LM Studio Multi-GPU**: `~/.lmstudio/MULTI_GPU_QUICK_START.md`
- **Spacebot Integration**: `docs/gateway-spacebot-compatibility-analysis.md`

---

### Phase 2: Enhanced Capabilities (Weeks 5-8)

**Goal**: Add advanced features for production workloads

#### 2.1 Semantic Caching with Compression 🚀 MEDIUM
**Estimated**: 4 hours
**Impact**: Cost reduction, faster responses

**Problem**:
- Repeated identical prompts hit the backend every time
- Semantic similarity not detected (e.g., "What's 2+2?" vs "Calculate 2+2")
- No KV cache optimization

**Solution - Two-Layer Caching**:

**Layer 1: Exact Match Cache (Redis)**
```python
import redis
import hashlib
import json

class ExactMatchCache:
    """Cache responses for identical prompts."""

    def __init__(self, redis_url: str = "redis://127.0.0.1:6379"):
        self.redis = redis.from_url(redis_url)
        self.default_ttl = 3600  # 1 hour

    def _make_cache_key(
        self,
        model: str,
        messages: List[Dict],
        temperature: float = 0.7
    ) -> str:
        """Create cache key from request parameters."""
        # Normalize messages for consistent hashing
        normalized = {
            "model": model,
            "messages": messages,
            "temperature": temperature
        }
        key_material = json.dumps(normalized, sort_keys=True)
        return f"response:v1:{hashlib.sha256(key_material.encode()).hexdigest()}"

    async def get(self, model: str, messages: List[Dict]) -> Optional[str]:
        """Get cached response if available."""
        cache_key = self._make_cache_key(model, messages)
        cached = await self.redis.get(cache_key)

        if cached:
            logger.info(f"Exact cache HIT: {cache_key[:16]}...")
            return json.loads(cached)

        logger.debug(f"Exact cache MISS: {cache_key[:16]}...")
        return None

    async def set(
        self,
        model: str,
        messages: List[Dict],
        response: str,
        ttl: Optional[int] = None
    ):
        """Cache a response."""
        cache_key = self._make_cache_key(model, messages)
        await self.redis.setex(
            cache_key,
            ttl or self.default_ttl,
            json.dumps(response)
        )
```

**Layer 2: Semantic Cache (Vector DB)**
```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct
import numpy as np

class SemanticCache:
    """Cache responses for semantically similar prompts."""

    def __init__(self, qdrant_url: str = "http://127.0.0.1:6333"):
        self.qdrant = QdrantClient(url=qdrant_url)
        self.collection_name = "semantic_cache"
        self.similarity_threshold = 0.95  # Cosine similarity

        async def _ensure_collection():
            """Create collection if not exists."""
            collections = await self.qdrant.get_collections()
            if not any(c.name == self.collection_name for c in collections.collections):
                await self.qdrant.create_collection(
                    collection_name=self.collection_name,
                    vectors_config=VectorParams(size=1536, distance=Distance.COSINE)
                )

    async def get(
        self,
        prompt_embedding: List[float],
        model: str
    ) -> Optional[str]:
        """Find semantically similar cached response."""
        results = await self.qdrant.search(
            collection_name=self.collection_name,
            query_vector=prompt_embedding,
            query_filter={
                "must": [
                    {"key": "model", "match": {"value": model}}
                ]
            },
            limit=1,
            score_threshold=self.similarity_threshold
        )

        if results and results[0].score >= self.similarity_threshold:
            cached = results[0].payload
            logger.info(f"Semantic cache HIT (score={results[0].score:.3f})")
            return cached["response"]

        return None

    async def set(
        self,
        prompt_embedding: List[float],
        model: str,
        response: str,
        ttl: int = 3600
    ):
        """Cache response with semantic embedding."""
        point_id = hashlib.uuid4().hex
        await self.qdrant.upsert(
            collection_name=self.collection_name,
            points=[PointStruct(
                id=point_id,
                vector=prompt_embedding,
                payload={
                    "model": model,
                    "response": response,
                    "created_at": datetime.now().isoformat(),
                    "ttl": ttl
                }
            )]
        )
```

**Integration**:
```python
class CacheLayer:
    """Two-layer caching: exact match → semantic match → backend."""

    def __init__(self):
        self.exact_cache = ExactMatchCache()
        self.semantic_cache = SemanticCache()

    async def get_cached_or_fetch(
        self,
        model: str,
        messages: List[Dict],
        backend_callback: Callable
    ) -> str:
        """Try exact cache, then semantic cache, then fetch."""

        # 1. Try exact match cache (fastest)
        cached = await self.exact_cache.get(model, messages)
        if cached:
            return cached

        # 2. Try semantic cache (similar prompts)
        last_message = messages[-1]["content"]
        embedding = await self._get_embedding(last_message)
        cached = await self.semantic_cache.get(embedding, model)
        if cached:
            # Also populate exact cache for future hits
            await self.exact_cache.set(model, messages, cached)
            return cached

        # 3. Cache miss - fetch from backend
        response = await backend_callback()

        # Populate both caches
        await self.exact_cache.set(model, messages, response)
        await self.semantic_cache.set(embedding, model, response)

        return response
```

**Prompt Compression** (for long contexts):
```python
class PromptCompressor:
    """Compress long prompts using summarization."""

    async def compress(
        self,
        messages: List[Dict],
        max_tokens: int,
        compression_ratio: float = 0.5
    ) -> List[Dict]:
        """Compress messages that exceed token limit."""
        total_tokens = sum(count_tokens(m["content"]) for m in messages)

        if total_tokens <= max_tokens:
            return messages  # No compression needed

        # Compress early messages while preserving recent context
        to_compress = messages[:-2]  # Keep last 2 messages intact
        preserved = messages[-2:]

        compressed = []
        for msg in to_compress:
            if msg["role"] == "system":
                # Keep system prompt but truncate
                compressed.append({
                    "role": "system",
                    "content": msg["content"][:500] + "..."
                })
            elif msg["role"] == "user":
                # Summarize user message
                summary = await self._summarize(msg["content"])
                compressed.append({
                    "role": "user",
                    "content": f"[Summary: {summary}]"
                })
            # Skip assistant messages (inferred from context)

        return compressed + preserved
```

**Acceptance Criteria**:
- ✅ Exact match cache for identical prompts
- ✅ Semantic cache for similar prompts (cosine similarity ≥0.95)
- ✅ Cache hit/miss metrics
- ✅ TTL-based invalidation (1 hour default)
- ✅ Long prompt compression when approaching context limit
- ✅ Configurable similarity threshold
- ✅ Cache warming on startup

**Related Research**:
- [Prompt Caching Evaluation (arXiv, Jan 2026)](https://arxiv.org/html/2601.06007v2)
- [SentenceKV Semantic Caching](https://arxiv.org/abs/2506.15723)
- [Baidu Prompt Caching Implementation](https://cloud.baidu.com/article/2380696)
- [Four Caching Strategies](https://www.51cto.com/article/704581.html)

---

#### 2.2 RAG URL Ingestion (web-reader Integration) 🚀 MEDIUM
**Estimated**: 3 hours
**Impact**: Streamlined knowledge base population

**Problem**:
- RAG ingestion only accepts raw text
- No URL fetching capability
- Manual download + ingest workflow is tedious

**Solution**:
```python
from ai_inference_gateway.rag.search import SearchService
from typing import List, Dict, Optional
import httpx
from urllib.parse import urlparse
import asyncio

class URLIngestionService:
    """Ingest documents from URLs into RAG knowledge base."""

    def __init__(
        self,
        search_service: SearchService,
        mcp_broker: Optional[MCPBroker] = None,
        timeout: int = 30
    ):
        self.search = search_service
        self.mcp_broker = mcp_broker
        self.timeout = timeout
        self.allowed_domains = None  # If set, only allow these domains

        # User-Agent for web requests
        self.user_agent = "AI-Inference-Gateway/2.0 (+https://github.com/your-repo)"

    def _is_allowed_url(self, url: str) -> bool:
        """Check if URL is allowed for ingestion."""
        parsed = urlparse(url)

        # Block private/local IPs
        if parsed.hostname in ('localhost', '127.0.0.1'):
            return False

        # Check domain whitelist if configured
        if self.allowed_domains:
            return parsed.hostname in self.allowed_domains

        return True

    async def _fetch_with_web_reader(
        self,
        url: str
    ) -> Optional[str]:
        """Fetch content using MCP web-reader server if available."""
        if not self.mcp_broker:
            return None

        try:
            # Call web-reader MCP tool
            result = await self.mcp_broker.call_tool(
                server_name="web-reader",
                tool_name="fetch_url",
                arguments={"url": url}
            )

            if result and "content" in result:
                return result["content"]
        except Exception as e:
            logger.warning(f"web-reader fetch failed: {e}")

        return None

    async def _fetch_with_http_client(self, url: str) -> Optional[str]:
        """Fetch content using HTTP client (fallback)."""
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                headers = {"User-Agent": self.user_agent}
                response = await client.get(url, headers=headers, follow_redirects=True)
                response.raise_for_status()

                # Check content type
                content_type = response.headers.get("content-type", "")
                if "text/html" in content_type:
                    # HTML - would need parsing (BeautifulSoup, etc.)
                    # For now, just extract text roughly
                    from html.parser import HTMLParser
                    import re

                    # Remove script/style tags
                    cleaned = re.sub(r'<script[^>]*>.*?</script>', '', response.text, flags=re.DOTALL)
                    cleaned = re.sub(r'<style[^>]*>.*?</style>', '', cleaned, flags=re.DOTALL)

                    # Extract text from HTML (simple version)
                    text_match = re.search(r'<body[^>]*>(.*?)</body>', cleaned, re.DOTALL)
                    if text_match:
                        return re.sub(r'<[^>]+>', '\n', text_match.group(1))

                elif "text/plain" in content_type or "application/json" in content_type:
                    return response.text

                else:
                    logger.warning(f"Unsupported content-type: {content_type}")
                    return None

        except Exception as e:
            logger.error(f"HTTP fetch failed for {url}: {e}")
            return None

    async def ingest_url(
        self,
        url: str,
        collection: str,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Ingest a document from URL into RAG collection."""

        # Validate URL
        if not self._is_allowed_url(url):
            raise ValueError(f"URL not allowed: {url}")

        # Fetch content
        content = await self._fetch_with_web_reader(url)
        if not content:
            content = await self._fetch_with_http_client(url)

        if not content:
            raise ValueError(f"Failed to fetch content from {url}")

        # Prepare metadata
        doc_metadata = {
            "source_url": url,
            "ingested_at": datetime.now().isoformat(),
            "content_length": len(content)
        }
        if metadata:
            doc_metadata.update(metadata)

        # Ingest into RAG
        document_id = await self.search.ingest_document(
            collection=collection,
            content=content,
            metadata=doc_metadata
        )

        logger.info(f"Ingested {url} into {collection} as {document_id}")

        return {
            "document_id": document_id,
            "collection": collection,
            "source_url": url,
            "content_length": len(content)
        }

    async def ingest_urls_batch(
        self,
        urls: List[str],
        collection: str,
        metadata: Optional[Dict[str, Any]] = None,
        concurrency: int = 5
    ) -> List[Dict[str, Any]]:
        """Ingest multiple URLs concurrently."""
        semaphore = asyncio.Semaphore(concurrency)

        async def ingest_with_semaphore(url: str):
            async with semaphore:
                try:
                    return await self.ingest_url(url, collection, metadata)
                except Exception as e:
                    logger.error(f"Failed to ingest {url}: {e}")
                    return {"source_url": url, "error": str(e)}

        tasks = [ingest_with_semaphore(url) for url in urls]
        results = await asyncio.gather(*tasks)

        successful = sum(1 for r in results if "error" not in r)
        logger.info(f"Batch ingest complete: {successful}/{len(urls)} successful")

        return results
```

**API Endpoint**:
```python
# In main.py
@app.post("/v1/rag/ingest_url")
async def ingest_url(request: Request):
    """Ingest a document from URL into RAG collection."""
    state: GatewayState = app.state.gateway

    body = await request.json()
    url = body.get("url")
    collection = body.get("collection", "default")
    metadata = body.get("metadata", {})

    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    ingestor = URLIngestionService(
        search_service=state.rag_search,
        mcp_broker=state.mcp_broker
    )

    result = await ingestor.ingest_url(url, collection, metadata)
    return JSONResponse(content=result)

@app.post("/v1/rag/ingest_urls_batch")
async def ingest_urls_batch(request: Request):
    """Ingest multiple URLs concurrently."""
    state: GatewayState = app.state.gateway

    body = await request.json()
    urls = body.get("urls", [])
    collection = body.get("collection", "default")
    metadata = body.get("metadata", {})
    concurrency = body.get("concurrency", 5)

    if not urls:
        raise HTTPException(status_code=400, detail="URLs are required")

    ingestor = URLIngestionService(
        search_service=state.rag_search,
        mcp_broker=state.mcp_broker
    )

    results = await ingestor.ingest_urls_batch(
        urls=urls,
        collection=collection,
        metadata=metadata,
        concurrency=concurrency
    )

    return JSONResponse(content={"results": results})
```

**NixOS Configuration**:
```nix
rag.ingestion = {
  enable = true;

  allowed_domains = mkOption {
    default = null;
    type = types.nullOr (types.listOf types.str);
    description = "Whitelist of domains allowed for URL ingestion";
  };

  max_concurrent_ingests = mkOption {
    default = 5;
    type = types.int;
    description = "Max concurrent URL ingestions";
  };

  fetch_timeout_seconds = mkOption {
    default = 30;
    type = types.int;
    description = "Timeout for fetching URLs";
  };
};
```

**Acceptance Criteria**:
- ✅ Fetch documents from URLs
- ✅ Prefer MCP web-reader if available, fallback to HTTP
- ✅ Domain whitelist support
- ✅ Block private IPs (localhost, 127.0.0.1)
- ✅ Batch ingestion with concurrency control
- ✅ Store source URL in document metadata
- ✅ Handle HTML (basic text extraction)
- ✅ Handle plain text and JSON
- ✅ API endpoints for single and batch ingestion

**Related Research**:
- [MCP Web-Reader Integration](https://modelcontextprotocol.io/blogs/introduction)
- [Azure AI Gateway MCP](https://azure.microsoft.com/en-us/products/ai-services/ai-gateway)

---

#### 2.3 Request Governance (Content Moderation + PII Redaction) 🚀 MEDIUM
**Estimated**: 4 hours
**Impact**: Security, compliance

**Problem**:
- No input validation or sanitization
- No PII redaction
- No content moderation (harmful content)
- No sensitive data masking

**Solution**:

**Content Moderation**:
```python
from typing import List, Optional
import re

class ContentModerator:
    """Filter and moderate user inputs."""

    # Block list for harmful patterns
    BLOCKED_PATTERNS = [
        r'(?i)(password|secret|api[_-]?key)\s*[:=]\s*\S+',  # Credentials
        r'(?i)<script[^>]*>.*?</script>',  # XSS attempts
        r'(?i)(drop table|delete from)\s+\w+',  # SQL injection
    ]

    # Allow list for code-like content
    ALLOWED_CODE_PREFIXES = [
        '```',  # Code blocks
        'def ', 'class ', 'function ',  # Code definitions
        'import ', 'from ', 'require(',  # Import statements
    ]

    def __init__(self, strict_mode: bool = False):
        self.strict_mode = strict_mode

    async def moderate_input(self, content: str) -> tuple[bool, Optional[str]]:
        """
        Check if input content is acceptable.

        Returns:
            (allowed, reason) - If not allowed, reason is provided
        """
        # Check for blocked patterns
        for pattern in self.BLOCKED_PATTERNS:
            if re.search(pattern, content):
                return False, f"Blocked content matched pattern: {pattern}"

        # In strict mode, additional checks
        if self.strict_mode:
            # Check for potential jailbreak attempts
            jailbreak_patterns = [
                r'(?i)(ignore|forget).*(previous|above).*(instructions?|system)',
                r'(?i)(you are|act as).*(not.*constrained|unrestricted)',
            ]
            for pattern in jailbreak_patterns:
                if re.search(pattern, content):
                    return False, "Potential jailbreak attempt detected"

        return True, None

    async def moderate_output(self, content: str) -> tuple[bool, Optional[str]]:
        """Check model output for policy violations."""
        # Basic checks
        if len(content) > 100000:  # 100k character limit
            return False, "Response too long"

        # Check for potential API key leakage
        if re.search(r'(?i)(sk-|api_key|apikey)\s*[:=]\s*[a-zA-Z0-9_-]{20,}', content):
            return False, "Potential credential leakage detected"

        return True, None
```

**PII Redaction**:
```python
class PIIRedactor:
    """Redact personally identifiable information."""

    # Patterns for PII detection
    PII_PATTERNS = {
        'email': r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
        'ssn': r'\b\d{3}-\d{2}-\d{4}\b',
        'credit_card': r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b',
        'ip_address': r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b',
        'phone': r'\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b',
    }

    REDACTION_PLACEHOLDERS = {
        'email': '[REDACTED_EMAIL]',
        'ssn': '[REDACTED_SSN]',
        'credit_card': '[REDACTED_CARD]',
        'ip_address': '[REDACTED_IP]',
        'phone': '[REDACTED_PHONE]',
    }

    def __init__(self, redact_user: bool = True, redact_model: bool = False):
        self.redact_user = redact_user
        self.redact_model = redact_model

    def redact(self, content: str) -> tuple[str, List[Dict]]:
        """
        Redact PII from content.

        Returns:
            (redacted_content, redaction_log)
        """
        redacted = content
        redaction_log = []

        for pii_type, pattern in self.PII_PATTERNS.items():
            matches = list(re.finditer(pattern, redacted))
            for match in matches:
                redacted_log.append({
                    "type": pii_type,
                    "start": match.start(),
                    "end": match.end(),
                    "original": match.group(),
                    "placeholder": self.REDACTION_PLACEHOLDERS[pii_type]
                })

            redacted = re.sub(
                pattern,
                self.REDACTION_PLACEHOLDERS[pii_type],
                redacted
            )

        return redacted, redaction_log
```

**Integration into Chat Completions**:
```python
# In main.py chat_completions endpoint

# After reading request body
content_moderator = ContentModerator(strict_mode=config.security.strict_mode)
pii_redactor = PIIRedactor(redact_user=True)

# Moderate user input
for msg in messages:
    allowed, reason = await content_moderator.moderate_input(msg["content"])
    if not allowed:
        raise HTTPException(
            status_code=400,
            detail={"error": "content_policy_violation", "reason": reason}
        )

    # Redact PII from user input
    if pii_redactor.redact_user:
        redacted_content, redactions = pii_redactor.redact(msg["content"])
        if redactions:
            msg["original_content"] = msg["content"]  # Store original
            msg["content"] = redacted_content
            logger.info(f"Redacted {len(redactions)} PII instances from user input")

# After getting model response
# Moderate model output
allowed, reason = await content_moderator.moderate_output(response_text)
if not allowed:
    # Log violation and return error
    logger.warning(f"Output moderation failed: {reason}")
    raise HTTPException(status_code=500, detail="Response blocked by content policy")

# Optionally redact PII from model output
if pii_redactor.redact_model:
    response_text, redactions = pii_redactor.redact(response_text)
```

**NixOS Configuration**:
```nix
security = {
  content_moderation = {
    enable = mkOption {
      default = true;
      type = types.bool;
    };

    strict_mode = mkOption {
      default = false;
      type = types.bool;
      description = "Enable strict jailbreak detection";
    };
  };

  pii_redaction = {
    enable = mkOption {
      default = true;
      type = types.bool;
    };

    redact_user_input = mkOption {
      default = true;
      type = types.bool;
    };

    redact_model_output = mkOption {
      default = false;
      type = types.bool;
    };

    log_redactions = mkOption {
      default = true;
      type = types.bool;
    };
  };
};
```

**Acceptance Criteria**:
- ✅ Block harmful patterns (credentials, XSS, SQL injection)
- ✅ Detect jailbreak attempts (strict mode)
- ✅ Redact PII (email, SSN, credit card, IP, phone)
- ✅ Configurable strictness
- ✅ Separate redaction for user input vs model output
- ✅ Redaction logging
- ✅ Policy violation metrics

---

### Phase 3: Advanced Features (Weeks 9-12)

#### 3.1 Multi-Agent Orchestration 🚀 MEDIUM
**Estimated**: 6 hours
**Impact**: Complex workflows, agent collaboration

**Problem**:
- Single model limitation
- No agent routing or specialization
- No agent collaboration patterns

**Solution**:
```python
from enum import Enum
from typing import Dict, List, Optional, Callable

class AgentRole(Enum):
    """Agent specializations."""
    CODING = "coding"
    RESEARCH = "research"
    WRITING = "writing"
    ANALYSIS = "analysis"
    COORDINATION = "coordination"

@dataclass
class Agent:
    """An AI agent with specific capabilities."""
    name: str
    role: AgentRole
    model: str
    system_prompt: str
    tools: List[str] = None
    max_tokens: int = 4096
    temperature: float = 0.7

@dataclass
class AgentTask:
    """A task to be executed by an agent."""
    task_id: str
    description: str
    required_role: AgentRole
    input_data: Dict
    dependencies: List[str] = None  # Tasks that must complete first

class MultiAgentOrchestrator:
    """Orchestrate multiple specialized agents."""

    def __init__(self, agents: List[Agent]):
        self.agents = {agent.name: agent for agent in agents}
        self.agent_by_role = {
            agent.role: agent.name
            for agent in agents
        }
        self.task_queue: List[AgentTask] = []
        self.completed_tasks: Dict[str, Any] = {}

    async def route_to_agent(
        self,
        task: AgentTask,
        context: Dict
    ) -> str:
        """Route a task to the appropriate agent."""
        agent_name = self.agent_by_role.get(task.required_role)

        if not agent_name:
            # Fallback: use routing to select best model
            agent_name = await self._select_agent_for_task(task)

        agent = self.agents[agent_name]

        # Execute task with agent
        result = await self._execute_agent_task(agent, task, context)

        self.completed_tasks[task.task_id] = result
        return result

    async def execute_workflow(
        self,
        workflow: List[AgentTask],
        context: Dict
    ) -> Dict[str, Any]:
        """Execute a multi-agent workflow."""
        results = {}

        # Build dependency graph
        task_graph = self._build_dependency_graph(workflow)

        # Execute tasks in topological order
        for task_id in task_graph.topological_sort():
            task = next(t for t in workflow if t.task_id == task_id)

            # Check dependencies
            if task.dependencies:
                if not all(dep in results for dep in task.dependencies):
                    raise ValueError(f"Unmet dependencies for task {task_id}")

            # Execute task
            context["previous_results"] = results
            result = await self.route_to_agent(task, context)
            results[task_id] = result

        return results
```

**API Endpoints**:
```python
@app.post("/v1/agents/execute")
async def execute_agent_task(request: Request):
    """Execute a task with a specific agent."""
    # Implementation...

@app.post("/v1/agents/workflow")
async def execute_workflow(request: Request):
    """Execute a multi-agent workflow."""
    # Implementation...

@app.get("/v1/agents")
async def list_agents(request: Request):
    """List available agents and their capabilities."""
    # Implementation...
```

---

#### 3.2 Distributed Tracing 🔧 LOW
**Estimated**: 5 hours
**Impact**: Debugging, performance analysis

**Solution**:
```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.jaeger import JaegerExporter

# Initialize tracing
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

jaeger_exporter = JaegerExporter(
    agent_host_name="127.0.0.1",
    agent_port=6831,
)

trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(jaeger_exporter)
)

# In chat completions endpoint
with tracer.start_as_current_span("chat_completion") as span:
    span.set_attribute("model", route_decision.model)
    span.set_attribute("backend", route_decision.backend)

    with tracer.start_as_current_span("routing"):
        # Routing logic...

    with tracer.start_as_current_span("backend_call"):
        # Backend call...

    with tracer.start_as_current_span("response_processing"):
        # Response processing...
```

---

#### 3.3 Cost Optimization 🔧 LOW
**Estimated**: 4 hours
**Impact**: Budget control, auto-degradation

**Solution**:
```python
class CostTracker:
    """Track token costs and enforce budgets."""

    PRICING = {
        "gpt-4": {"input": 0.03, "output": 0.06},  # per 1K tokens
        "gpt-3.5-turbo": {"input": 0.001, "output": 0.002},
        "qwen/qwen3.5-9b": {"input": 0.0001, "output": 0.0001},
    }

    def __init__(self, monthly_budget: float = 100.0):
        self.monthly_budget = monthly_budget
        self.current_spend = 0.0
        self.alert_threshold = 0.8  # Alert at 80%

    async def check_budget(
        self,
        model: str,
        input_tokens: int,
        output_tokens: int
    ) -> tuple[bool, float]:
        """Check if request is within budget."""
        pricing = self.PRICING.get(model, {"input": 0, "output": 0})

        estimated_cost = (
            (input_tokens / 1000) * pricing["input"] +
            (output_tokens / 1000) * pricing["output"]
        )

        if self.current_spend + estimated_cost > self.monthly_budget:
            # Budget exceeded - suggest cheaper model
            return False, estimated_cost

        if self.current_spend + estimated_cost > self.monthly_budget * self.alert_threshold:
            # Near threshold - log warning
            logger.warning(f"Cost threshold approaching: ${self.current_spend:.2f}")

        return True, estimated_cost

    def suggest_degraded_model(self, requested_model: str) -> str:
        """Suggest a cheaper alternative model."""
        # Simple degradation logic
        if "gpt-4" in requested_model.lower():
            return "gpt-3.5-turbo"
        return "qwen/qwen3.5-9b"  # Cheapest local option
```

---

## Additional Modern Features (Research-Based)

Based on 2026 research and industry trends, here are additional features to consider:

### 4. Speculative Decoding Integration 🔧 LOW
**Estimated**: 8 hours (complex)
**Impact**: 2-3x latency reduction

Research shows [speculative decoding](https://arxiv.org/abs/2305.10442) can achieve 2-3x speedup using smaller draft models.

**Implementation approach**:
```python
class SpeculativeDecoder:
    """Use small draft model to predict tokens, validate with target model."""

    def __init__(
        self,
        target_model: str,
        draft_model: str,
        spec_length: int = 5
    ):
        self.target_model = target_model
        self.draft_model = draft_model
        self.spec_length = spec_length

    async def generate_with_speculation(
        self,
        prompt: str,
        max_tokens: int
    ) -> str:
        """Generate using speculative decoding."""
        # 1. Draft model predicts spec_length tokens
        draft_tokens = await self._draft_prediction(prompt, self.spec_length)

        # 2. Target model verifies in parallel
        verified_tokens = await self._verify_speculation(prompt, draft_tokens)

        # 3. Accept verified tokens, continue normally
        return verified_tokens + await self._normal_generation(prompt, verified_tokens)
```

**Requirements**:
- Draft model (e.g., qwen3.5-2b)
- Target model (e.g., magnum-opus-35b-a3b-i1)
- KV cache sharing between models
- Acceptance rate tracking

---

### 5. Prompt Optimization Engine 🔧 LOW
**Estimated**: 6 hours
**Impact**: Better responses, lower token usage

Based on [prompt caching research](https://arxiv.org/html/2601.06007v2), optimize prompts for:

1. **Token reduction** - Remove redundant instructions
2. **Structure optimization** - Reorder for better attention
3. **Example selection** - Use minimal few-shot examples

```python
class PromptOptimizer:
    """Optimize prompts for efficiency and effectiveness."""

    async def optimize_prompt(
        self,
        messages: List[Dict],
        model: str
    ) -> List[Dict]:
        """Optimize prompt messages."""
        # 1. Remove redundant content
        optimized = self._remove_redundancy(messages)

        # 2. Optimize system prompt
        optimized = self._compress_system_prompt(optimized)

        # 3. Select optimal few-shot examples
        optimized = self._select_examples(optimized)

        return optimized
```

---

### 6. A/B Testing Framework 🔧 LOW
**Estimated**: 5 hours
**Impact**: Model selection optimization

```python
class ABTestFramework:
    """A/B test different models for requests."""

    async def route_with_ab_test(
        self,
        messages: List[Dict],
        experiment: str
    ) -> str:
        """Route request based on A/B test configuration."""
        config = await self._get_experiment_config(experiment)

        # Select variant
        variant = self._select_variant(config)

        # Track impression
        await self._track_impression(experiment, variant)

        # Route to variant's model
        return variant.model

    async def track_conversion(
        self,
        experiment: str,
        variant: str,
        outcome: str
    ):
        """Track conversion outcome for analysis."""
        # Store in analytics...
```

---

## Infrastructure Requirements

### New Dependencies

```nix
# In ai-inference/default.nix
dependencies = with python311Packages; [
  # Existing...

  # NEW: Phase 1
  tenacity  # Retry with exponential backoff
  redis     # Exact match caching

  # NEW: Phase 2
  beautifulsoup4  # HTML parsing for URL ingestion
  qdrant-client    # Semantic caching

  # NEW: Phase 3
  opentelemetry-api         # Distributed tracing
  opentelemetry-sdk         # Distributed tracing
  opentelemetry-exporter-jaeger  # Jaeger export
];
```

### Services to Add

```nix
# In system services
services = {
  # Redis for exact-match caching
  redis = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
  };

  # Jaeger for distributed tracing
  jaeger = {
    enable = true;
    agent = {
      enable = true;
      host = "127.0.0.1";
      port = 6831;
    };
  };
};
```

---

## Metrics & Observability Enhancements

### New Metrics to Track

```python
# In metrics.py

# Cache metrics
cache_hits_total = Counter(
    'gateway_cache_hits_total',
    'Cache hits',
    ['cache_type', 'model']  # exact, semantic
)

cache_misses_total = Counter(
    'gateway_cache_misses_total',
    'Cache misses',
    ['cache_type', 'model']
)

# Retry metrics
retry_attempts_total = Counter(
    'gateway_retry_attempts_total',
    'Retry attempts',
    ['model', 'error_type']
)

# Cost metrics
cost_tracker = Gauge(
    'gateway_cost_usd',
    'Total cost in USD',
    ['model']
)

budget_utilization_percent = Gauge(
    'gateway_budget_utilization_percent',
    'Budget utilization percentage',
    []
)

# Content moderation metrics
moderation_blocked_total = Counter(
    'gateway_moderation_blocked_total',
    'Blocked by content moderation',
    ['reason']
)

pii_redactions_total = Counter(
    'gateway_pii_redactions_total',
    'PII redactions performed',
    ['pii_type']
)

# A/B testing metrics
ab_test_impressions_total = Counter(
    'gateway_ab_test_impressions_total',
    'A/B test impressions',
    ['experiment', 'variant']
)

ab_test_conversions_total = Counter(
    'gateway_ab_test_conversions_total',
    'A/B test conversions',
    ['experiment', 'variant', 'outcome']
)
```

---

## Success Metrics

### Phase 1 Success Criteria
- ✅ JSON mode compatibility with OpenAI SDK
- ✅ <1% failure rate with retry logic
- ✅ 90%+ cache hit rate for repeated MCP tool queries
- ✅ <100ms average cache response time

### Phase 2 Success Criteria
- ✅ 40%+ cache hit rate for exact matches
- ✅ 20%+ cache hit rate for semantic matches
- ✅ <5 second average URL ingestion time
- ✅ 100% PII redaction coverage
- ✅ Zero security policy violations

### Phase 3 Success Criteria
- ✅ Multi-agent workflows operational
- ✅ Distributed tracing end-to-end
- ✅ Cost tracking within 5% accuracy
- ✅ Budget alerts working

---

## Risk Assessment

| Feature | Risk | Mitigation |
|---------|------|------------|
| response_format | LM Studio may not follow JSON instructions | Add validation, error handling |
| Retry Logic | Exponential backoff may cause long waits | Set max timeout, user feedback |
| Semantic Cache | False positives (wrong cache hit) | High similarity threshold (0.95+) |
| URL Ingestion | Malicious URLs, large files | Domain whitelist, size limits |
| PII Redaction | False positives (redacting non-PII) | Configurable patterns, logging |

---

## Summary Timeline

```
Week 1-4: Phase 1 - Production Readiness
├── Week 1: response_format transformation
├── Week 2: Enhanced retry with exponential backoff
├── Week 3: MCP tool schema caching
└── Week 4: Testing, documentation, monitoring

Week 5-8: Phase 2 - Enhanced Capabilities
├── Week 5: Semantic caching with compression
├── Week 6: RAG URL ingestion
├── Week 7: Request governance (PII, moderation)
└── Week 8: Testing, optimization

Week 9-12: Phase 3 - Advanced Features
├── Week 9: Multi-agent orchestration
├── Week 10: Distributed tracing
├── Week 11: Cost optimization
└── Week 12: Testing, refinement, docs
```

---

## References & Sources

### Model Routing & Observability
- [AI Gateway Features 2026](https://learn.microsoft.com/azure/ai-studio/how-to/enterprise-gateway) - Microsoft Azure AI Gateway routing and observability features
- [Portkey AI Gateway](https://portkey.ai/docs/gateway-capabilities) - Multi-provider gateway with intelligent routing
- [Aliyun LLM Gateway](https://help.aliyun.com/zh/llm-service/developer-reference/gateway) - Enterprise LLM gateway service

### Speculative Decoding
- [万字长文带你全面了解大模型高效推理与优化](https://blog.csdn.net/) (Feb 28, 2026) - Comprehensive speculative decoding overview
- [投机解码实战](https://blog.csdn.net/) (Feb 20, 2026) - Practical Python implementation
- [BigDL Self-Speculative Decoding](https://bigdl.readthedocs.io/) (Jan 23, 2026) - 3x speedup techniques

### JSON Schema & Structured Outputs
- [OpenAI Structured Outputs](https://platform.openai.com/docs/guides/structured-outputs) - JSON Schema mode documentation
- [Qwen JSON Schema Mode](https://help.aliyun.com/zh/model-studio/developer-reference/json-mode) (2026 models) - Qwen 3.5 JSON mode

### Semantic Caching & Compression
- [Prompt Caching Evaluation (arXiv, Jan 2026)](https://arxiv.org/html/2601.06007v2) - Long-context prompt caching research
- [SentenceKV Semantic Caching](https://arxiv.org/abs/2506.15723) - Sentence-level semantic caching
- [Baidu Prompt Caching](https://cloud.baidu.com/article/2380696) - Redis-based implementation
- [Four Caching Strategies](https://www.51cto.com/article/704581.html) - Exact, normalized, semantic, hybrid approaches

### Retry & Resilience
- [Portkey Retry Logic](https://portkey.ai/docs/gateway-capabilities/retries) - Up to 5 attempts with exponential backoff
- [Aliyun Gateway Retry](https://help.aliyun.com/zh/llm-service/developer-reference/gateway) - retry_count, max_queue_size configuration
- [Tenacity Library](https://tenacity.readthedocs.io/) - Python retry library

### Streaming & Chunking
- [AI Gateway Event Streaming](https://learn.microsoft.com/azure/ai-studio) - Real-time streaming capabilities
- [Streaming Response Patterns](https://python.langchain.com/docs/modules/model_io/models/llms/streaming) - Chunking and incremental delivery

### Multi-Agent & Tool Calling
- [OpenClaw Gateway](https://github.com/openclaw/gateway) - Local gateway with multi-agent routing
- [Azure AI Gateway MCP](https://azure.microsoft.com/en-us/products/ai-services/ai-gateway) - MCP governance and routing
- [AgentGateway (Linux Foundation)](https://github.com/agentgateway/agentgateway) - Rust-based agent protocol gateway
- [LangGraph Multi-Agent](https://langchain-ai.github.io/langgraph/) - Multi-agent orchestration patterns

### Web-Reader & URL Ingestion
- [MCP Web-Reader](https://modelcontextprotocol.io/blogs/introduction) - Model Context Protocol web reader
- [MCP Web-Reader Implementation](https://github.com/modelcontextprotocol) - URL fetching capabilities

---

**Next Steps**: Review and prioritize based on your immediate needs. Phase 1 features are recommended for production readiness.
