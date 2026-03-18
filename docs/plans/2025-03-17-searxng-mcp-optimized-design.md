# SearXNG MCP Server - Optimized Design
## High-Impact Embedding Features + Deep Infrastructure Integration

**Date**: 2025-03-17 (Final)
**Author**: Claude Code
**Status**: Optimized Implementation Plan
**Priority**: Maximum Value with Minimum Code

---

## Executive Summary

**Strategy**: Prioritize 3 high-impact embedding features that leverage existing infrastructure, then add standard SearXNG capabilities.

**Key Insight**: You have **production-grade embedding infrastructure** (EmbeddingService, Qdrant, SemanticCache, SemanticRouter). By leveraging these, we can build a **powerful SearXNG MCP server** with only ~850 lines of new code (not 1,300+).

---

## 🎯 The 3 High-Impact Features

### Priority 1: Semantic Cache ⭐⭐⭐

**What**: Two-layer caching (Redis exact + Qdrant semantic)
**Value**: 30-50% more cache hits, sub-100ms cached responses
**Effort**: 80 lines
**Risk**: LOW (you already have SemanticCache)

**Impact**:
```
Query: "nixos installation guide"
Semantic Cache finds: "how to install nixos" (similarity: 0.91)
Response: <100ms (vs. 2s for fresh search)
```

---

### Priority 2: Query Routing ⭐⭐⭐

**What**: Semantic intent classification using SemanticRouter
**Value**: 90% routing accuracy, optimal engine selection
**Effort**: 120 lines
**Risk**: LOW (you already have SemanticRouter)

**Impact**:
```
Query: "implement REST API python"
Semantic Router detects: PROCEDURAL + CODE intent
Engines selected: stackoverflow, github, google (not just google)
Results: More code examples, fewer general web pages
```

---

### Priority 3: Result Clustering ⭐⭐

**What**: Group search results by semantic similarity
**Value**: Organized results, easier navigation
**Effort**: 130 lines
**Risk**: MEDIUM (need to validate clustering quality)

**Impact**:
```
20 flat results → 3 organized clusters:
  Cluster 1: "Installation Guides" (8 results)
  Cluster 2: "Configuration Examples" (7 results)
  Cluster 3: "Troubleshooting" (5 results)
```

---

## 📁 Optimized File Structure

```
ai_inference_gateway/
├── mcp_servers/
│   ├── searxng_server.py              # ENHANCED (279 → 400 lines)
│   │   # New tools:
│   │   ├── search_with_semantic_cache
│   │   ├── search_with_intent_routing
│   │   └── cluster_search_results
│   │
│   └── searxng_tools/                 # NEW (optional, for organization)
│       └── __init__.py
│
├── searxng_integration.py              # ENHANCED (625 → 800 lines)
│   # Key integrations:
│   ├── Semantic cache (Priority 1)    # +80 lines
│   ├── Semantic router (Priority 2)   # +120 lines
│   ├── Result clustering (Priority 3) # +130 lines
│   ├── RRF fusion                     # +150 lines
│   └── Observability                  # +50 lines
│
├── config.py                          # ENHANCED (+20 lines)
│   # Register SearXNG with MCPBroker
│
└── rag/                               # EXISTING (reuse, no changes)
    ├── embeddings.py                  # ✅ Use as-is
    ├── search.py                      # ✅ Use as-is
    ├── chunker.py                     # ✅ Use as-is
    └── qdrant_client.py               # ✅ Use as-is
```

**Total New Code**: ~580 lines (not 850!)
**Total Enhanced**: 1,200 lines (from 900)

---

## 🚀 Implementation Plan (6 Weeks)

### Week 1: Foundation + Semantic Cache ⭐⭐⭐

**Tasks**:
1. Register SearXNG with MCPBroker
2. Integrate SemanticCache for two-layer caching
3. Add observability metrics
4. Write unit tests
5. Performance benchmarking

**Implementation**:

```python
# searxng_integration.py - Add semantic cache
from ai_inference_gateway.semantic_cache import SemanticCache, CacheConfig

class SearxngIntegration:
    def __init__(self, cache_ttl: int = 300, enable_semantic_cache: bool = True):
        # Existing simple cache
        self.response_cache = {}
        self.cache_ttl = cache_ttl

        # NEW: Semantic cache integration
        if enable_semantic_cache:
            self.semantic_cache = SemanticCache(
                config=CacheConfig(
                    redis_url="redis://localhost:6379",
                    qdrant_url="http://localhost:6333",
                    qdrant_collection="searxng-searches",
                    similarity_threshold=0.85,
                    exact_ttl_seconds=cache_ttl,
                    semantic_ttl_seconds=cache_ttl * 2,  # Keep semantic longer
                )
            )
        else:
            self.semantic_cache = None

    async def search(self, query: str, category: str = "general", ...) -> Dict[str, Any]:
        """
        Search with two-layer semantic caching.

        Layers:
            1. Exact cache (dict) - sub-1ms lookup
            2. Semantic cache (Qdrant) - paraphrase detection
            3. Fresh SearXNG search
        """
        # Layer 1: Exact cache check
        cache_key = self._cache_key(query, category)
        if cache_key in self.response_cache:
            cached = self.response_cache[cache_key]
            if time.time() - cached["timestamp"] < self.cache_ttl:
                logger.info(f"Exact cache hit: {query[:30]}...")
                return cached["result"]

        # Layer 2: Semantic cache check (if enabled)
        if self.semantic_cache:
            semantic_hit = await self.semantic_cache.get(query)
            if semantic_hit:
                logger.info(
                    f"Semantic cache hit (similarity: {semantic_hit.similarity_score:.2f}): "
                    f"'{query[:30]}...' ≈ '{semantic_hit.metadata.get('original_query', '')[:30]}...'"
                )
                # Store in exact cache for faster next access
                self.response_cache[cache_key] = {
                    "result": semantic_hit.response,
                    "timestamp": time.time()
                }
                return semantic_hit.response

        # Layer 3: Cache miss - search SearXNG
        logger.info(f"Cache miss: {query[:30]}...")
        result = await self._search_searxng(query, category, ...)

        # Store in both caches
        self.response_cache[cache_key] = {
            "result": result,
            "timestamp": time.time()
        }

        if self.semantic_cache:
            await self.semantic_cache.put(query, result)

        return result
```

**New MCP Tool**:
```python
# searxng_server.py - Add semantic cache tool
Tool(
    name="search_with_semantic_cache",
    description=(
        "Search with intelligent semantic caching. "
        "Finds paraphrases and similar past searches to reduce latency. "
        "Use for repeated queries with different wording."
    ),
    inputSchema=WebSearchParams.model_json_schema(),
)
```

**Deliverables**:
- ✅ Semantic cache integrated
- ✅ Cache hit rate >40%
- ✅ Cached responses <100ms
- **Lines**: +100

---

### Week 2: Query Routing ⭐⭐⭐

**Tasks**:
1. Integrate SemanticRouter for intent classification
2. Add intent-based engine selection
3. Implement `search_with_intent_routing` tool
4. Test routing accuracy
5. Document intent types

**Implementation**:

```python
# searxng_integration.py - Add semantic routing
from ai_inference_gateway.middleware.knowledge_fabric.routing import (
    SemanticRouter,
    QueryIntent,
    RoutingDecision,
)

class SearxngIntegration:
    def __init__(self, ..., enable_semantic_routing: bool = True):
        # NEW: Semantic router for query classification
        if enable_semantic_routing:
            self.semantic_router = SemanticRouter()
        else:
            self.semantic_router = None

    async def search_with_intent_routing(
        self,
        query: str,
        max_results: int = 10,
        use_cache: bool = True,
    ) -> Dict[str, Any]:
        """
        Search with semantic intent classification.

        Workflow:
            1. Classify query intent (CODE, FACTUAL, PROCEDURAL, etc.)
            2. Select optimal engines based on intent
            3. Apply intent-specific ranking
            4. Return results with routing metadata
        """
        # Classify query intent
        if self.semantic_router:
            routing_decision: RoutingDecision = self.semantic_router.route(
                query=query,
                available_sources=["searxng"]
            )
            intent = routing_decision.intent
            confidence = routing_decision.confidence
            reasoning = routing_decision.reasoning

            logger.info(
                f"Query intent: {intent.value} "
                f"(confidence: {confidence:.2f}) - {reasoning}"
            )
        else:
            # Fallback to simple domain detection
            intent = self._detect_domain_simple(query)
            confidence = 0.7
            reasoning = "Simple keyword detection"

        # Select engines based on intent
        engines = self._get_engines_for_intent(intent)

        # Determine category from intent
        category = self._get_category_for_intent(intent)

        # Search with intent-optimized parameters
        result = await self.search(
            query=query,
            category=category,
            max_results=max_results,
            use_cache=use_cache,
            engines=engines,  # Intent-specific engine selection
        )

        # Add routing metadata
        result["routing"] = {
            "intent": intent.value,
            "confidence": confidence,
            "reasoning": reasoning,
            "engines_selected": engines,
        }

        return result

    def _get_engines_for_intent(self, intent: QueryIntent) -> List[str]:
        """Map query intent to optimal search engines."""
        engine_map = {
            QueryIntent.CODE: ["stackoverflow", "github", "google"],
            QueryIntent.FACTUAL: ["google", "bing", "duckduckgo", "wikipedia"],
            QueryIntent.PROCEDURAL: ["google", "bing", "duckduckgo"],
            QueryIntent.REALTIME: ["google news", "bing news"],
            QueryIntent.COMPARATIVE: ["google", "bing", "duckduckgo"],
            QueryIntent.CONTEXTUAL: ["google", "bing", "wikipedia"],
        }
        return engine_map.get(intent, ["google", "bing", "duckduckgo"])

    def _get_category_for_intent(self, intent: QueryIntent) -> str:
        """Map query intent to SearXNG category."""
        category_map = {
            QueryIntent.CODE: "it",
            QueryIntent.REALTIME: "news",
            QueryIntent.FACTUAL: "general",
            QueryIntent.PROCEDURAL: "general",
            QueryIntent.COMPARATIVE: "general",
            QueryIntent.CONTEXTUAL: "general",
        }
        return category_map.get(intent, "general")
```

**New MCP Tool**:
```python
# searxng_server.py - Add intent routing tool
Tool(
    name="search_with_intent_routing",
    description=(
        "Search with AI-powered query intent classification. "
        "Automatically detects if you're looking for code, facts, procedures, "
        "or comparisons and selects optimal search engines. "
        "Returns results with routing metadata explaining the classification."
    ),
    inputSchema=SiteSearchParams.model_json_schema(),
)
```

**Deliverables**:
- ✅ Semantic routing integrated
- ✅ Routing accuracy >85%
- ✅ Intent metadata in results
- **Lines**: +150

---

### Week 3: Result Clustering ⭐⭐

**Tasks**:
1. Integrate EmbeddingService for result vectorization
2. Implement DBSCAN clustering
3. Add auto-labeling for clusters
4. Implement `cluster_search_results` tool
5. Validate clustering quality

**Implementation**:

```python
# searxng_integration.py - Add clustering
from ai_inference_gateway.rag.embeddings import EmbeddingService
from sklearn.cluster import DBSCAN
from sklearn.metrics import silhouette_score
import numpy as np

class SearxngIntegration:
    def __init__(
        self,
        ...,
        embedder: EmbeddingService = None,
        enable_clustering: bool = True,
    ):
        # NEW: Embedding service for clustering
        if enable_clustering and embedder:
            self.embedder = embedder
        else:
            self.embedder = None

    async def cluster_search_results(
        self,
        query: str,
        max_results: int = 20,
        min_cluster_size: int = 2,
        clustering_algorithm: str = "dbscan",
    ) -> Dict[str, Any]:
        """
        Search and cluster results by semantic similarity.

        Returns results grouped into topical clusters.
        """
        if not self.embedder:
            raise ValueError(
                "Embedding service not configured. "
                "Please provide embedder to enable clustering."
            )

        # Search SearXNG
        search_result = await self.search(query=query, max_results=max_results)
        results = search_result.get("results", [])

        if len(results) < 2:
            return {
                "query": query,
                "clusters": [],
                "message": "Not enough results to cluster",
                "n_clusters": 0,
            }

        # Prepare texts for embedding
        texts = []
        for r in results:
            title = r.get("title", "")
            content = r.get("content", "")
            text = f"{title}\n{content}" if content else title
            texts.append(text[:500])  # First 500 chars

        # Generate embeddings (batch processing)
        embeddings = await self.embedder.embed_batch(texts)
        embeddings_array = np.array(embeddings)

        # Cluster using DBSCAN
        if clustering_algorithm == "dbscan":
            clustering = DBSCAN(eps=0.5, min_samples=min_cluster_size)
            labels = clustering.fit_predict(embeddings_array)

            # Count clusters (excluding noise, label=-1)
            unique_labels = set(labels)
            n_clusters = len(unique_labels) - (1 if -1 in unique_labels else 0)
        else:
            # Fallback: single cluster
            labels = np.zeros(len(results), dtype=int)
            n_clusters = 1

        # Organize results by cluster
        clusters = []
        for label in unique_labels:
            if label == -1:  # Skip noise
                continue

            # Get results for this cluster
            cluster_results = [
                results[i]
                for i, l in enumerate(labels)
                if l == label
            ]

            # Generate topic label
            topic = self._label_cluster(cluster_results)

            clusters.append({
                "topic": topic,
                "results": cluster_results,
                "size": len(cluster_results),
            })

        # Sort clusters by size (largest first)
        clusters.sort(key=lambda x: x["size"], reverse=True)

        # Calculate quality score
        quality_score = 0.0
        if n_clusters > 1:
            try:
                quality_score = silhouette_score(
                    embeddings_array[labels != -1],
                    labels[labels != -1]
                )
            except Exception as e:
                logger.warning(f"Could not calculate silhouette score: {e}")

        return {
            "query": query,
            "clusters": clusters,
            "n_clusters": n_clusters,
            "quality_score": float(quality_score),
            "algorithm": clustering_algorithm,
            "total_results": len(results),
        }

    def _label_cluster(self, results: List[Dict]) -> str:
        """
        Generate topic label from cluster results using keyword extraction.

        Uses TF-IDF style keyword frequency to identify dominant topics.
        """
        from collections import Counter
        import re

        # Extract keywords from titles and snippets
        words = []
        for r in results:
            # Extract from title
            title = r.get("title", "").lower()
            title_words = re.findall(r'\b[a-z]{4,}\b', title)
            words.extend(title_words)

            # Extract from content (first 200 chars)
            content = r.get("content", "")[:200].lower()
            content_words = re.findall(r'\b[a-z]{4,}\b', content)
            words.extend(content_words)

        if not words:
            return "General"

        # Filter common stop words
        stop_words = {
            "that", "this", "with", "from", "have", "they", "been",
            "what", "when", "where", "which", "their", "about", "into",
            "through", "during", "before", "after", "above", "below"
        }
        filtered = [w for w in words if w not in stop_words and len(w) >= 4]

        if not filtered:
            return "General"

        # Get most common keywords (top 3)
        most_common = Counter(filtered).most_common(3)

        # Create label from top keywords
        keywords = [w for w, _ in most_common]
        return ", ".join(keywords).title()
```

**New MCP Tool**:
```python
# searxng_server.py - Add clustering tool
Tool(
    name="cluster_search_results",
    description=(
        "Search and automatically group results by semantic similarity. "
        "Organizes scattered results into topical clusters for easier navigation. "
        "Returns auto-generated topic labels and quality score."
    ),
    inputSchema=...,
)
```

**Deliverables**:
- ✅ Clustering integrated
- ✅ Silhouette score >0.5
- ✅ Auto-labeling working
- **Lines**: +180

---

### Week 4: RRF Fusion + Hybrid Search

**Tasks**:
1. Integrate RRFFusion for SearXNG + RAG merging
2. Add `search_and_fuse_with_rag` tool
3. Test fusion quality
4. Document fusion behavior

**Implementation**:

```python
# searxng_integration.py - Add RRF fusion
from ai_inference_gateway.middleware.knowledge_fabric.fusion import RRFFusion

class SearxngIntegration:
    def __init__(self, ..., enable_rrf_fusion: bool = True):
        # NEW: RRF fusion integration
        if enable_rrf_fusion:
            self.rrf_fusion = RRFFusion(
                k=60,
                reranker_enabled=True,
                reranker_model="BAAI/bge-reranker-v2-base",
            )
        else:
            self.rrf_fusion = None

    async def search_and_fuse_with_rag(
        self,
        query: str,
        rag_source: HybridSearchService,
        max_results: int = 10,
    ) -> Dict[str, Any]:
        """
        Search SearXNG and fuse with RAG results using RRF.

        Combines fresh web results with curated knowledge base.
        """
        if not self.rrf_fusion:
            raise ValueError("RRF fusion not enabled")

        # Parallel search
        searxng_task = self.search(query=query, max_results=max_results)
        rag_task = rag_source.search(query=query, top_k=max_results)

        searxng_result, rag_result = await asyncio.gather(
            searxng_task,
            rag_task,
            return_exceptions=True
        )

        # Handle exceptions
        if isinstance(searxng_result, Exception):
            logger.error(f"SearXNG search failed: {searxng_result}")
            searxng_result = {"results": []}

        if isinstance(rag_result, Exception):
            logger.error(f"RAG search failed: {rag_result}")
            rag_result = {"results": []}

        # Convert to KnowledgeChunk format
        from ai_inference_gateway.middleware.knowledge_fabric.core import (
            KnowledgeResult,
            KnowledgeChunk,
        )

        # SearXNG results
        searxng_chunks = [
            KnowledgeChunk(
                content=f"{r['title']}\n{r.get('content', '')}",
                source="searxng",
                score=1.0 - (i * 0.1),
                metadata={
                    "url": r.get("url"),
                    "title": r.get("title"),
                    "engine": r.get("engine", ""),
                }
            )
            for i, r in enumerate(searxng_result.get("results", []))
        ]

        searxng_kr = KnowledgeResult(
            source_name="searxng",
            chunks=searxng_chunks,
            query=query,
            retrieval_time=searxng_result.get("timing", 0),
        )

        # RAG results (already KnowledgeResult format)
        rag_kr = KnowledgeResult(
            source_name="rag",
            chunks=rag_result.get("results", []),
            query=query,
            retrieval_time=rag_result.get("timing", 0),
        )

        # Fuse with RRF
        fused_result = await self.rrf_fusion.fuse(
            results=[searxng_kr, rag_kr],
            query=query,
            final_k=max_results
        )

        return {
            "query": query,
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
            "searxng_count": len(searxng_chunks),
            "rag_count": len(rag_kr.chunks),
        }
```

**Deliverables**:
- ✅ RRF fusion integrated
- ✅ Fusion quality validated
- **Lines**: +150

---

### Week 5-6: Standard SearXNG Features

**Tasks**:
1. Advanced search operators (boolean, phrase, wildcards)
2. Category support (images, videos, news, science, files)
3. Time range and language filters
4. Engine selection and pagination
5. Search history and saved searches
6. Export formats (JSON, CSV, RSS)

**Standard Implementation** (as before, but less priority):

```python
# Advanced search operators
async def advanced_search(
    query: str,
    boolean_mode: bool = False,
    phrase_search: bool = False,
    file_types: List[str] = None,
) -> Dict[str, Any]:
    """Advanced search with operators."""

# Categories
async def search_images(query: str, max_results: int = 10) -> Dict[str, Any]:
    """Search for images."""

async def search_videos(query: str, max_results: int = 10) -> Dict[str, Any]:
    """Search for videos."""

# ... more standard tools
```

**Deliverables**:
- ✅ 15 standard tools
- ✅ Full SearXNG API coverage
- **Lines**: +430

---

## 📊 Summary: Optimized Approach

### Code Reduction Through Reuse

| Component | Original Plan | Optimized Plan | Savings |
|-----------|--------------|----------------|---------|
| Semantic Cache | Build new (+150 lines) | Use existing (+80 lines) | **-70 lines** |
| Query Routing | Build new (+150 lines) | Use existing (+120 lines) | **-30 lines** |
| RAG Chunking | Build new (+120 lines) | Use existing (+50 lines) | **-70 lines** |
| Vector Search | Build new (+180 lines) | Use existing (+100 lines) | **-80 lines** |
| **Total** | **+600 lines** | **+350 lines** | **-250 lines (42% reduction)** |

### Final Code Count

```
Current State:        900 lines (279 server + 625 integration)
Add (Reuse):          +350 lines (leverage existing infra)
Add (New):            +430 lines (standard SearXNG features)
─────────────────────────────────────────────────────
Final State:          1,680 lines (400 server + 800 integration + 480 docs/tests)
```

**Compared to original plan**: 520 lines LESS code (24% reduction)

### Feature Comparison

| Feature | Original Plan | Optimized Plan | Status |
|---------|--------------|----------------|--------|
| Semantic Cache | ✅ Build new | ✅ **Use existing** | **BETTER** |
| Query Routing | ✅ Build new | ✅ **Use existing** | **BETTER** |
| RRF Fusion | ✅ Build new | ✅ **Use existing** | **BETTER** |
| RAG Chunking | ✅ Build new | ✅ **Use existing** | **BETTER** |
| Vector Search | ✅ Build new | ✅ **Use existing** | **BETTER** |
| Clustering | ✅ Build new | ✅ **Simpler (reuse embedder)** | **BETTER** |
| Monitoring | ✅ Basic | ✅ **Full observability** | **BETTER** |
| Standard Features | ✅ Full coverage | ✅ **Full coverage** | SAME |

---

## 🎯 Success Metrics

### Week 2 (Foundation)
- ✅ Semantic cache hit rate >40%
- ✅ Cached responses <100ms
- ✅ Query routing accuracy >85%

### Week 4 (AI Features)
- ✅ Clustering silhouette score >0.5
- ✅ RRF fusion merging working
- ✅ All 3 embedding features operational

### Week 6 (Complete)
- ✅ 28+ MCP tools
- ✅ All tests passing
- ✅ Documentation complete

---

## 🚦 Implementation Order

**Priority 1** (Week 1-2): Semantic Cache + Query Routing
- **Highest value** (40% cache hits, 90% routing accuracy)
- **Lowest risk** (using proven infrastructure)
- **Fastest implementation** (200 lines total)

**Priority 2** (Week 3): Result Clustering
- **Medium value** (better organization)
- **Medium risk** (need to validate quality)
- **Reasonable effort** (130 lines)

**Priority 3** (Week 4-6): RRF Fusion + Standard Features
- **Integrates everything**
- **Completes the MCP server**
- **Full SearXNG coverage**

---

## ❓ Final Questions

1. **Confirm Priority 1**: Start with semantic cache + query routing (Week 1-2)?

2. **Qdrant Collections**:
   - `searxng-searches` for semantic cache?
   - Reuse `knowledge-base` for RRF fusion?

3. **Embedding Service**: Should SearXngIntegration accept it as dependency, or create its own instance?

4. **MCPBroker Registration**: Auto-register on gateway startup, or manual config in `config.py`?

5. **Performance Target**: With semantic cache, target <100ms for cached results?

---

**Total Estimated Effort**: 6 weeks
**Total New Code**: ~780 lines (350 reuse + 430 new)
**Total Enhanced**: 1,680 lines (from 900)
**New MCP Tools**: 28 tools
**Risk Level**: **VERY LOW** (mostly proven infrastructure)

---

## Key Advantages of Optimized Approach

1. ✅ **42% less custom code** (reuse over reinvention)
2. ✅ **Lower risk** (proven infrastructure)
3. ✅ **Faster time to value** (Priority 1 features in 2 weeks)
4. ✅ **Better performance** (optimized caching and routing)
5. ✅ **Easier maintenance** (less custom code to maintain)
6. ✅ **Consistency** (same patterns as other gateway components)

---

**End of Optimized Design**

**Bottom Line**: By leveraging your existing production-grade AI infrastructure, we build a MORE powerful SearXNG MCP server with LESS code, LOWER risk, and FASTER time to value.
