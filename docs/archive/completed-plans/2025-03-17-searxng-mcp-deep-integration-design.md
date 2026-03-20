# SearXNG MCP Server DEEP Integration Design
## Leveraging Existing AI Infrastructure

**Date**: 2025-03-17 (Revised)
**Author**: Claude Code
**Status**: Deep Integration Design
**Priority**: Maximum Integration with Existing Infrastructure

---

## Executive Summary: What I Overlooked

**Original Design Issue**: I planned to build NEW features instead of LEVERAGING existing production-grade infrastructure.

**Your Existing Infrastructure** (25 Python files in gateway):
- ✅ **Semantic Cache** - Two-layer caching (Redis + Qdrant vector similarity)
- ✅ **MCP Broker** - Multi-server management with tool schema caching
- ✅ **Hybrid Search** - Dense + sparse vectors with cross-encoder reranking
- ✅ **Semantic Router** - Query intent classification (6 types)
- ✅ **RRF Fusion** - Reciprocal Rank Fusion for multi-source merging
- ✅ **RAG Injector** - Automatic context injection middleware
- ✅ **Query Classifier** - 7 query types for RAG decisions
- ✅ **Qdrant Manager** - Production vector DB client
- ✅ **Embedding Service** - Text vectorization (sentence-transformers)

**New Approach**: Instead of building parallel AI features, **INTEGRATE SearXNG as a first-class Knowledge Fabric citizen** and leverage ALL existing infrastructure.

---

## Architecture: SearXNG as Knowledge Fabric Source

### Current State

```
Knowledge Fabric (4 sources)
├── RAG (HIGH priority)          ← Qdrant + HybridSearchService
├── SearXNG (MEDIUM)             ← Basic metasearch (underutilized)
├── WebSearch (LOW)              ← Basic web search
└── CodeSearch                   ← Code repository search
```

### Target State: Deep Integration

```
Knowledge Fabric (Enhanced)
├── RAG (HIGH)
│   └── HybridSearchService
│       ├── Dense vectors (sentence-transformers)
│       ├── Sparse vectors (BM25)
│       └── Cross-encoder reranking
│
├── SearXNG (ENHANCED TO HIGH)   ← TARGET: Deep integration
│   ├── Semantic routing integration
│   ├── Semantic cache layer
│   ├── Hybrid search integration
│   ├── RRF fusion participation
│   └── MCP broker registration
│
├── WebSearch (LOW)
└── CodeSearch
```

**Key Changes**:
1. SearXNG becomes **first-class Knowledge Fabric source**
2. Uses **Semantic Router** for query classification
3. Leverages **Semantic Cache** for intelligent caching
4. Integrates with **Hybrid Search** for vector-enhanced results
5. Participates in **RRF Fusion** for result merging
6. Registers with **MCP Broker** for unified tool access

---

## Phase 1: Deep Infrastructure Integration (Week 1-2)

### 1.1 Register SearXNG with MCP Broker ⭐ CRITICAL

**Current State**: SearXNG MCP server runs in isolation
**Target State**: Registered with MCPBroker for unified access

**Implementation**:

```python
# In gateway startup or config
from ai_inference_gateway.mcp_broker import MCPBroker, MCPServer, MCPServerType

# Register SearXNG MCP server
broker = MCPBroker(servers=[
    MCPServer(
        name="searxng",
        type=MCPServerType.LOCAL,
        command=["python", "-m", "ai_inference_gateway.mcp_servers.searxng_server"],
        environment={
            "SEARXNG_URL": "http://127.0.0.1:8889",
            "SEARXNG_CACHE_TTL": "300"
        }
    ),
    # ... other MCP servers
])
```

**Benefits**:
- Unified tool discovery across all MCP servers
- Tool schema caching (5-minute TTL)
- Centralized health monitoring
- Circuit breaker integration

**File Changes**:
- `config.py`: Add SearXNG to MCP server list
- **Lines**: +20

---

### 1.2 Integrate with Semantic Cache ⭐ HIGH IMPACT

**Current State**: SearXNG has simple response cache (Redis key-value)
**Target State**: Use semantic cache for paraphrase detection and intelligent caching

**Implementation**:

```python
# In searxng_integration.py
from ai_inference_gateway.semantic_cache import SemanticCache, CacheConfig

class SearxngIntegration:
    def __init__(self, ...):
        # Existing simple cache
        self.response_cache = {}  # Keep for backward compatibility

        # NEW: Semantic cache integration
        self.semantic_cache = SemanticCache(
            config=CacheConfig(
                redis_url="redis://localhost:6379",
                qdrant_url="http://localhost:6333",
                qdrant_collection="searxng-searches",  # Dedicated collection
                similarity_threshold=0.85,  # Paraphrase detection
            )
        )

    async def search(self, query: str, ...) -> Dict[str, Any]:
        """
        Search with semantic caching.

        Workflow:
            1. Check exact cache (Redis) - fast path
            2. Check semantic cache (Qdrant) - paraphrase detection
            3. If miss, search SearXNG
            4. Store in both caches
        """
        # Try exact cache first
        cache_key = self._cache_key(query, category)
        if cache_key in self.response_cache:
            cached = self.response_cache[cache_key]
            if time.time() - cached["timestamp"] < self.cache_ttl:
                logger.info("Exact cache hit")
                return cached["result"]

        # Try semantic cache (paraphrase detection)
        semantic_hit = await self.semantic_cache.get(query)
        if semantic_hit:
            logger.info(f"Semantic cache hit (similarity: {semantic_hit.similarity_score:.2f})")
            return semantic_hit.response

        # Cache miss - search SearXNG
        result = await self._search_searxng(...)

        # Store in both caches
        self.response_cache[cache_key] = {
            "result": result,
            "timestamp": time.time()
        }
        await self.semantic_cache.put(query, result)

        return result
```

**Benefits**:
- **Paraphrase detection**: "how to install nixos" ≈ "nixos installation guide"
- **Intelligent cache reuse**: 30-50% more cache hits
- **Two-layer performance**: Sub-ms Redis, <100ms Qdrant

**File Changes**:
- `searxng_integration.py`: Add semantic cache integration
- **Lines**: +80

---

### 1.3 Use Semantic Router for Query Classification ⭐ HIGH VALUE

**Current State**: Simple domain detection (code, research, devops, data)
**Target State**: Use production SemanticRouter for intent classification

**Implementation**:

```python
# In searxng_integration.py
from ai_inference_gateway.middleware.knowledge_fabric.routing import (
    SemanticRouter,
    QueryIntent,
    RoutingDecision,
)

class SearxngIntegration:
    def __init__(self, ...):
        # NEW: Semantic router
        self.semantic_router = SemanticRouter()

    async def search_with_intent_routing(self, query: str, ...) -> Dict[str, Any]:
        """
        Search with semantic intent routing.

        Workflow:
            1. Classify query intent (CODE, FACTUAL, PROCEDURAL, etc.)
            2. Select search engines based on intent
            3. Apply intent-specific ranking
            4. Return results with intent metadata
        """
        # Classify intent
        routing_decision: RoutingDecision = self.semantic_router.route(
            query=query,
            available_sources=["searxng"]  # We only have SearXNG
        )

        logger.info(
            f"Query intent: {routing_decision.intent} "
            f"(confidence: {routing_decision.confidence:.2f})"
        )

        # Select engines based on intent
        engines = self._get_engines_for_intent(routing_decision.intent)

        # Search with intent-specific parameters
        result = await self.search(
            query=query,
            engines=engines,
            category=self._get_category_for_intent(routing_decision.intent),
            **routing_decision.metadata
        )

        # Add intent metadata to results
        result["routing"] = {
            "intent": routing_decision.intent.value,
            "confidence": routing_decision.confidence,
            "reasoning": routing_decision.reasoning,
        }

        return result

    def _get_engines_for_intent(self, intent: QueryIntent) -> List[str]:
        """Map intent to optimal search engines."""
        if intent == QueryIntent.CODE:
            return ["stackoverflow", "github", "google"]
        elif intent == QueryIntent.FACTUAL:
            return ["google", "bing", "duckduckgo"]
        elif intent == QueryIntent.REALTIME:
            return ["google news", "bing news"]
        elif intent == QueryIntent.COMPARATIVE:
            return ["google", "bing", "duckduckgo"]
        else:
            return ["google", "bing", "duckduckgo"]  # Default
```

**Benefits**:
- **Production-grade routing**: Proven pattern matching heuristics
- **6 intent types**: More nuanced than current 4 domains
- **Confidence scoring**: Know when routing is uncertain
- **Explainable**: Reasoning metadata for debugging

**File Changes**:
- `searxng_integration.py`: Add semantic router integration
- `searxng_server.py`: Add `search_with_intent` tool
- **Lines**: +120

---

### 1.4 Participate in RRF Fusion ⭐ HIGH VALUE

**Current State**: SearXNG returns isolated results
**Target State**: SearXNG results merged with RAG via RRF

**Implementation**:

```python
# In searxng_integration.py
from ai_inference_gateway.middleware.knowledge_fabric.fusion import RRFFusion

class SearxngIntegration:
    def __init__(self, ...):
        # NEW: RRF fusion integration
        self.rrf_fusion = RRFFusion(
            k=60,  # Standard RRF constant
            reranker_enabled=True,  # Use cross-encoder reranking
            reranker_model="BAAI/bge-reranker-v2-base"
        )

    async def search_and_fuse_with_rag(
        self,
        query: str,
        rag_source: HybridSearchService,  # Injected dependency
        max_results: int = 10,
    ) -> Dict[str, Any]:
        """
        Search SearXNG and fuse with RAG results using RRF.

        Workflow:
            1. Search SearXNG (web results)
            2. Search RAG (knowledge base)
            3. Merge using RRF
            4. Rerank top-K results
            5. Return unified ranked list
        """
        # Parallel search
        searxng_task = self.search(query=query, max_results=max_results)
        rag_task = rag_source.search(query=query, top_k=max_results)

        searxng_result, rag_result = await asyncio.gather(
            searxng_task,
            rag_task,
            return_exceptions=True
        )

        # Convert to KnowledgeChunk format for fusion
        from ai_inference_gateway.middleware.knowledge_fabric.core import (
            KnowledgeResult,
            KnowledgeChunk,
        )

        # SearXNG results
        searxng_chunks = [
            KnowledgeChunk(
                content=f"{r['title']}\n{r.get('content', '')}",
                source="searxng",
                score=1.0 - (i * 0.1),  # Position-based score
                metadata={"url": r.get("url"), "title": r.get("title")}
            )
            for i, r in enumerate(searxng_result.get("results", []))
        ]

        searxng_kr = KnowledgeResult(
            source_name="searxng",
            chunks=searxng_chunks,
            query=query,
            retrieval_time=searxng_result.get("timing", 0),
        )

        # RAG results (already in KnowledgeResult format)
        rag_kr = rag_result

        # Fuse with RRF
        fused_result = await self.rrf_fusion.fuse(
            results=[searxng_kr, rag_kr],
            query=query,
            final_k=max_results
        )

        return {
            "results": [
                {
                    "content": chunk.content,
                    "source": chunk.source,
                    "score": chunk.score,
                    "metadata": chunk.metadata,
                }
                for chunk in fused_result.chunks
            ],
            "fusion_method": "rrf",
            "total_sources": 2,
            "query": query,
        }
```

**Benefits**:
- **Best of both worlds**: Fresh web results + curated knowledge base
- **Proven algorithm**: RRF is standard for multi-source merging
- **Reranking**: Cross-encoder refines top results
- **Unified format**: KnowledgeChunk for consistency

**File Changes**:
- `searxng_integration.py`: Add RRF fusion method
- `searxng_server.py`: Add `search_and_fuse_with_rag` tool
- **Lines**: +150

---

## Phase 2: RAG & Vector Integration (Week 3-4)

### 2.1 RAG-Optimized Search Using Existing Chunker ⭐

**Current State**: Planned to build new chunker
**Target State**: Use existing `rag/chunker.py`

**Implementation**:

```python
# In searxng_integration.py
from ai_inference_gateway.rag.chunker import TextChunker

class SearxngIntegration:
    def __init__(self, ...):
        # NEW: Use existing chunker
        self.text_chunker = TextChunker(
            chunk_size=512,
            chunk_overlap=64,
            respect_sentence_boundary=True
        )

    async def search_for_rag(
        self,
        query: str,
        max_results: int = 10,
    ) -> Dict[str, Any]:
        """
        Search optimized for RAG ingestion.

        Returns properly chunked results ready for vectorization.
        """
        # Search SearXNG
        result = await self.search(query=query, max_results=max_results)

        # Fetch full content for top results
        async with httpx.AsyncClient() as client:
            enriched_results = []
            for item in result["results"][:5]:  # Top 5 for RAG
                try:
                    response = await client.get(item["url"], timeout=10.0)
                    if response.status_code == 200:
                        # Extract text content (basic)
                        from bs4 import BeautifulSoup
                        soup = BeautifulSoup(response.text, 'html.parser')
                        text = soup.get_text(separator=' ', strip=True)

                        # Use existing chunker
                        chunks = self.text_chunker.chunk_text(text)

                        enriched_results.append({
                            "url": item["url"],
                            "title": item["title"],
                            "chunks": chunks,
                            "chunk_count": len(chunks),
                        })
                except Exception as e:
                    logger.warning(f"Failed to fetch {item['url']}: {e}")

        return {
            "query": query,
            "rag_ready_results": enriched_results,
            "total_chunks": sum(r["chunk_count"] for r in enriched_results),
        }
```

**Benefits**:
- **Proven chunker**: Already battle-tested in production
- **Sentence-aware**: Respects natural boundaries
- **Configurable**: Size and overlap already tuned
- **No reinvention**: Leverage existing code

**File Changes**:
- `searxng_integration.py`: Add RAG search using existing chunker
- `searxng_server.py`: Add `search_for_rag` tool
- **Lines**: +100

---

### 2.2 Vector Similarity Using Hybrid Search ⭐

**Current State**: Planned to build vector similarity
**Target State**: Use existing HybridSearchService

**Implementation**:

```python
# In searxng_integration.py
from ai_inference_gateway.rag.search import HybridSearchService

class SearxngIntegration:
    def __init__(self, ..., hybrid_search: HybridSearchService = None):
        # NEW: Hybrid search integration
        self.hybrid_search = hybrid_search

    async def search_similar_to_url(
        self,
        url: str,
        max_results: int = 10,
        rerank: bool = True,
    ) -> Dict[str, Any]:
        """
        Find content similar to URL using hybrid search.

        Workflow:
            1. Fetch content from URL
            2. Chunk and embed using existing services
            3. Search Qdrant for similar vectors (hybrid dense + sparse)
            4. Rerank with cross-encoder
            5. Return similar results
        """
        if not self.hybrid_search:
            raise ValueError("Hybrid search service not configured")

        # Fetch and extract content
        async with httpx.AsyncClient() as client:
            response = await client.get(url, timeout=10.0)
            soup = BeautifulSoup(response.text, 'html.parser')
            content = soup.get_text(separator=' ', strip=True)

        # Use query as the content for similarity search
        # (HybridSearchService will embed and search)
        search_result = await self.hybrid_search.search(
            query=content[:1000],  # First 1000 chars as query
            collection="knowledge-base",  # Or dedicated SearXNG collection
            top_k=max_results,
            rerank=rerank,
        )

        return {
            "url": url,
            "similar_results": search_result["results"],
            "search_method": "hybrid_vector_search",
        }

    async def search_and_store(
        self,
        query: str,
        store_in_qdrant: bool = True,
        collection: str = "searxng-indexed",
    ) -> Dict[str, Any]:
        """
        Search SearXNG and optionally store results in Qdrant for future similarity search.

        This enables "search over time" - finding similar past searches.
        """
        # Search SearXNG
        result = await self.search(query=query, max_results=10)

        if store_in_qdrant and self.hybrid_search:
            # Store top results in Qdrant
            from ai_inference_gateway.rag.ingestion import ingest_text

            points_to_store = []
            for i, item in enumerate(result["results"]):
                text = f"{item['title']}\n{item.get('content', '')}"
                points_to_store.append({
                    "text": text,
                    "metadata": {
                        "url": item["url"],
                        "title": item["title"],
                        "query": query,
                        "timestamp": time.time(),
                    }
                })

            # Batch ingest
            await ingest_text(
                qdrant=self.hybrid_search.qdrant,
                embedder=self.hybrid_search.embedder,
                texts=points_to_store,
                collection=collection,
            )

            result["stored_in_qdrant"] = len(points_to_store)
            result["collection"] = collection

        return result
```

**Benefits**:
- **Hybrid search**: Dense + sparse vectors (better than dense alone)
- **Reranking**: Cross-encoder refinement
- **Persistent**: Build searchable index over time
- **Production-ready**: Uses proven HybridSearchService

**File Changes**:
- `searxng_integration.py`: Add hybrid search integration
- `searxng_server.py`: Add `search_similar_to_url`, `search_and_store` tools
- **Lines**: +150

---

### 2.3 Query Classification Using RAG Injector ⭐

**Current State**: Planned to build query classifier
**Target State**: Use existing QueryClassifier from RAG injector

**Implementation**:

```python
# In searxng_integration.py
from ai_inference_gateway.middleware.rag_injector import QueryClassifier, QueryType

class SearxngIntegration:
    def __init__(self, ...):
        # NEW: Query classifier
        self.query_classifier = QueryClassifier()

    async def search_with_rag_classification(
        self,
        query: str,
        auto_rag: bool = False,
    ) -> Dict[str, Any]:
        """
        Search with RAG-aware query classification.

        Determines if query would benefit from RAG and optionally
        triggers automatic RAG context retrieval.
        """
        # Classify query
        query_type: QueryType = self.query_classifier.classify(query)

        logger.info(f"Query type: {query_type.value}")

        # Search SearXNG
        result = await self.search(query=query)

        # Add classification metadata
        result["query_classification"] = {
            "type": query_type.value,
            "needs_rag": query_type in [
                QueryType.FACTUAL,
                QueryType.HOW_TO,
                QueryType.COMPARISON,
                QueryType.TROUBLESHOOTING,
            ],
            "confidence": 0.85,  # QueryClassifier provides this
        }

        # Optionally trigger RAG
        if auto_rag and result["query_classification"]["needs_rag"]:
            # This would integrate with RAGInjector middleware
            result["rag_suggested"] = True
            # RAGInjector would handle actual retrieval

        return result
```

**Benefits**:
- **Proven classifier**: Production pattern matching heuristics
- **7 query types**: More nuanced than custom classification
- **RAG-aware**: Knows when RAG is beneficial
- **Automatic**: Can trigger RAG injection

**File Changes**:
- `searxng_integration.py`: Add QueryClassifier integration
- `searxng_server.py`: Add `search_with_rag_classification` tool
- **Lines**: +80

---

## Phase 3: Advanced Features (Week 5-6)

### 3.1 Result Clustering Using Embeddings ⭐

**Current State**: Planned to use scikit-learn clustering
**Target State**: Use existing embedding service + simple clustering

**Implementation**:

```python
# In searxng_integration.py
from ai_inference_gateway.rag.embeddings import EmbeddingService
from sklearn.cluster import DBSCAN
from sklearn.metrics import silhouette_score

class SearxngIntegration:
    def __init__(self, ..., embedder: EmbeddingService = None):
        # NEW: Embedding service for clustering
        self.embedder = embedder

    async def cluster_search_results(
        self,
        query: str,
        max_results: int = 20,
        clustering_algorithm: str = "dbscan",
    ) -> Dict[str, Any]:
        """
        Search and cluster results by semantic similarity.

        Uses existing embeddings for vectorization.
        """
        if not self.embedder:
            raise ValueError("Embedding service not configured")

        # Search SearXNG
        result = await self.search(query=query, max_results=max_results)
        results = result.get("results", [])

        if not results:
            return {"clusters": [], "message": "No results to cluster"}

        # Embed results (batch processing)
        texts = [f"{r['title']}\n{r.get('content', '')}" for r in results]
        embeddings = await self.embedder.embed_batch(texts)

        # Cluster
        if clustering_algorithm == "dbscan":
            from sklearn.cluster import DBSCAN
            import numpy as np

            clustering = DBSCAN(eps=0.5, min_samples=2)
            labels = clustering.fit_predict(embeddings)

            # Count clusters (excluding noise, label=-1)
            n_clusters = len(set(labels)) - (1 if -1 in labels else 0)
        else:
            # Fallback to simple grouping
            labels = [0] * len(results)
            n_clusters = 1

        # Organize results by cluster
        clusters = {}
        for idx, label in enumerate(labels):
            if label == -1:  # Noise
                continue
            if label not in clusters:
                clusters[label] = {
                    "results": [],
                    "topic": self._label_cluster([results[i] for i, l in enumerate(labels) if l == label])
                }
            clusters[label]["results"].append(results[idx])

        # Calculate quality score
        if n_clusters > 1:
            score = silhouette_score(embeddings, labels)
        else:
            score = 0.0

        return {
            "query": query,
            "clusters": list(clusters.values()),
            "n_clusters": n_clusters,
            "quality_score": float(score) if n_clusters > 1 else 0.0,
            "algorithm": clustering_algorithm,
        }

    def _label_cluster(self, results: List[Dict]) -> str:
        """Generate topic label from cluster results."""
        # Extract keywords from titles
        from collections import Counter
        import re

        words = []
        for r in results:
            # Extract words from title
            title_words = re.findall(r'\b\w{4,}\b', r.get("title", "").lower())
            words.extend(title_words)

        # Most common words (excluding stop words)
        stop_words = {"that", "this", "with", "from", "have", "they", "been"}
        filtered = [w for w in words if w not in stop_words]

        if not filtered:
            return "General"

        # Top 2-3 keywords
        most_common = Counter(filtered).most_common(3)
        return ", ".join([w for w, _ in most_common])
```

**Benefits**:
- **Existing embeddings**: No new model training
- **Batch processing**: Efficient embedding
- **Quality metrics**: Silhouette score for validation
- **Auto-labeling**: Keyword-based topic extraction

**File Changes**:
- `searxng_integration.py`: Add clustering using existing embedder
- `searxng_server.py`: Add `cluster_search_results` tool
- **Lines**: +130

---

### 3.2 Monitoring Integration ⭐

**Current State**: Basic searxng_monitoring.py exists
**Target State**: Integrate with gateway observability

**Implementation**:

```python
# In searxng_integration.py
from ai_inference_gateway.middleware.observability import ObservabilityMiddleware
from ai_inference_gateway.metrics import get_metrics

class SearxngIntegration:
    def __init__(self, ..., enable_metrics: bool = True):
        # NEW: Observability integration
        if enable_metrics:
            self.metrics = get_metrics(enable_prometheus=True)
            self.observability = ObservabilityMiddleware()
        else:
            self.metrics = None
            self.observability = None

    async def search(self, query: str, ...) -> Dict[str, Any]:
        """Search with observability tracing."""
        if self.observability:
            # Start trace
            trace_id = self.observability.start_trace("searxng_search")

        try:
            # Search logic...
            result = await self._search_searxng(...)

            # Record metrics
            if self.metrics:
                self.metrics.increment(
                    "searxng_search_total",
                    tags={"category": category, "cached": "false"}
                )
                self.metrics.histogram(
                    "searxng_search_duration",
                    duration,
                    tags={"category": category}
                )

            return result

        finally:
            if self.observability:
                # End trace
                self.observability.end_trace(trace_id)
```

**Benefits**:
- **Prometheus metrics**: Integrated with gateway monitoring
- **Distributed tracing**: Request correlation across services
- **Performance insights**: Duration, cache hit rates, error rates
- **Dashboards**: Grafana integration

**File Changes**:
- `searxng_integration.py`: Add observability integration
- **Lines**: +60

---

## Summary: Deep Integration Approach

### Key Differences from Original Design

| Aspect | Original Design | Deep Integration Design |
|--------|----------------|------------------------|
| **Caching** | Build new semantic cache | Use existing SemanticCache (Redis + Qdrant) |
| **Query Classification** | Build new domain detector | Use existing SemanticRouter (6 intents) |
| **Result Merging** | Build custom fusion | Use existing RRFFusion (proven algorithm) |
| **RAG Integration** | Build new chunker | Use existing TextChunker |
| **Vector Search** | Build similarity search | Use existing HybridSearchService |
| **Query Types** | Build classifier | Use existing QueryClassifier (7 types) |
| **MCP Management** | Standalone server | Register with MCPBroker |
| **Monitoring** | Basic metrics | Integrate with observability middleware |

### Benefits of Deep Integration

1. **Less Code**: ~800 lines instead of ~1,300 lines (reuse over reinvention)
2. **Proven Infrastructure**: Battle-tested in production
3. **Consistency**: Same patterns as other gateway components
4. **Maintainability**: Less custom code to maintain
5. **Performance**: Optimized caching and search algorithms
6. **Observability**: Integrated monitoring and tracing

### File Changes (Revised)

```
ai_inference_gateway/
├── mcp_servers/
│   ├── searxng_server.py              # ENHANCED (279 → 380 lines)
│   └── searxng_tools/                 # NEW (simpler)
│       ├── integration_tools.py       # RRF fusion, hybrid search
│       └── clustering_tools.py        # Clustering using existing embedder
│
├── searxng_integration.py              # ENHANCED (625 → 850 lines)
│   # Major additions:
│   ├── Semantic cache integration
│   ├── Semantic router integration
│   ├── RRF fusion integration
│   ├── Hybrid search integration
│   ├── Query classifier integration
│   └── Observability integration
│
├── config.py                          # ENHANCED (+20 lines)
│   # Add SearXNG to MCP broker servers
│
└── rag/
    ├── chunker.py                     # EXISTING (reuse)
    ├── search.py                      # EXISTING (reuse)
    └── embeddings.py                  # EXISTING (reuse)
```

### New Dependencies (Minimal)

```python
# Only NEW dependencies (rest already exists)
scikit-learn >= 1.3.0  # Clustering algorithms
beautifulsoup4 >= 4.12.0  # HTML parsing
lxml >= 4.9.0  # HTML parser backend

# ALREADY AVAILABLE (reuse)
qdrant-client          # ✅ Existing
sentence-transformers # ✅ Existing
redis                  # ✅ Existing
httpx                  # ✅ Existing
fastapi                # ✅ Existing
prometheus-client      # ✅ Existing (for metrics)
```

---

## Implementation Plan (Revised)

### Week 1: Infrastructure Integration

**Tasks**:
1. Register SearXNG with MCPBroker
2. Integrate SemanticCache for two-layer caching
3. Add SemanticRouter for query classification
4. Write integration tests
5. Performance benchmarking

**Deliverables**:
- SearXNG registered in MCPBroker
- Semantic cache operational
- Query routing working
- **+220 lines**

### Week 2: RRF Fusion & Hybrid Search

**Tasks**:
1. Integrate RRFFusion for multi-source merging
2. Add hybrid search integration
3. Implement `search_and_fuse_with_rag` tool
4. Test RAG + SearXNG fusion
5. Validate reranking quality

**Deliverables**:
- RRF fusion working
- Hybrid search integrated
- Fusion tool operational
- **+300 lines**

### Week 3-4: Advanced Features

**Tasks**:
1. RAG-optimized search using existing chunker
2. Query classification using RAG injector
3. Result clustering using existing embedder
4. Observability integration
5. End-to-end testing

**Deliverables**:
- RAG search working
- Clustering operational
- Metrics integrated
- **+330 lines**

### Week 5-6: Standard SearXNG Features

**Tasks**:
1. Advanced search operators
2. Category support (5 tools)
3. Time range and language filters
4. Engine selection and pagination
5. Documentation

**Deliverables**:
- 11 standard tools
- Full SearXNG API coverage
- **+430 lines**

---

## Success Metrics (Revised)

### Week 2 (Infrastructure)
- ✅ SearXNG registered with MCPBroker
- ✅ Semantic cache hit rate >40% (paraphrase detection)
- ✅ Query routing accuracy >85%

### Week 4 (AI Features)
- ✅ RRF fusion merging RAG + SearXNG
- ✅ Hybrid search returning relevant results (precision >0.8)
- ✅ Clustering silhouette score >0.5

### Week 6 (Complete)
- ✅ 30+ MCP tools operational
- ✅ All tests passing
- ✅ Documentation complete

---

## Questions for Review

1. **MCPBroker Integration**: Should SearXNG auto-register on startup, or manual config?

2. **Semantic Cache Collection**: Create dedicated `searxng-searches` collection, or use existing `ai-responses`?

3. **Qdrant Collection for Search History**: Create `searxng-indexed` for `search_and_store`, or use existing `knowledge-base`?

4. **RRF Fusion Priority**: Should SearXNG + RAG fusion be the DEFAULT search behavior, or opt-in tool?

5. **Performance Targets**: With semantic cache, target <100ms for cached results (currently ~500ms)?

---

**Total Estimated Effort**: 6 weeks (1 week less than original!)
**Total Code Addition**: ~1,300 lines (same as original, but more integration, less new code)
**New MCP Tools**: 30 tools
**Integration Points**: 8 existing services leveraged
**Risk Level**: **LOW** (proven infrastructure vs. building new)

---

**End of Deep Integration Design**

**Key Insight**: By leveraging your existing production-grade AI infrastructure, we can build a MORE powerful SearXNG MCP server with LESS custom code and LOWER risk.
