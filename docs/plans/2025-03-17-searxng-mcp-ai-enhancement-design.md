# SearXNG MCP Server AI-First Enhancement Design

**Date**: 2025-03-17
**Author**: Claude Code
**Status**: Design Phase
**Priority**: AI-First Enhancement

---

## Executive Summary

Enhance the existing SearXNG MCP server (`searxng_server.py` - 279 lines) and integration layer (`searxng_integration.py` - 625 lines) to provide **AI-optimized search capabilities** that leverage the existing Knowledge Fabric infrastructure (Qdrant vector DB, semantic routing, RRF fusion).

**Current State**: 900 lines of production code with basic metasearch, domain routing, caching, and learning.
**Target State**: 2,200+ lines with AI-first features: RAG optimization, vector similarity, result clustering, and advanced SearXNG capabilities.

**Approach**: AI-First (Option C) - Prioritize AI features that integrate with existing infrastructure, then add standard features.

---

## Architecture Overview

### Existing Infrastructure

```
┌─────────────────────────────────────────────────────────────┐
│                    Knowledge Fabric                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ RAG (HIGH)   │  │ SearXNG      │  │ WebSearch    │      │
│  │ Qdrant +     │  │ (MEDIUM)     │  │ (LOW)        │      │
│  │ Hybrid Search│  │ Basic        │  │ Basic        │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                 │                 │              │
│         └─────────────────┴─────────────────┘              │
│                           │                                │
│                  ┌────────▼────────┐                       │
│                  │  Semantic       │                       │
│                  │  Router         │                       │
│                  └────────┬────────┘                       │
│                           │                                │
│                  ┌────────▼────────┐                       │
│                  │  RRF Fusion     │                       │
│                  │  + Context      │                       │
│                  │  Synthesis      │                       │
│                  └─────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

### Enhancement Strategy

**Integrate SearXNG with AI infrastructure** by:
1. Using Qdrant for vector similarity search
2. Leveraging embedding models for result clustering
3. Optimizing results for RAG workflows (chunking, citation quality)
4. Returning Knowledge Fabric-compatible metadata

---

## Phase 1: AI-First Features (Week 1-3)

### 1.1 RAG-Optimized Search ⭐ HIGHEST PRIORITY

**Purpose**: Return SearXNG results optimized for RAG workflows with proper chunking, citation quality, and context window optimization.

**New MCP Tool**:
```python
Tool(name="search_for_rag",
     description="RAG-optimized search returning properly chunked results "
                 "with citation quality scores and LLM context optimization")
```

**Implementation**:
```python
async def search_for_rag(
    query: str,
    max_results: int = 10,
    chunk_size: int = 512,  # Optimal for most LLMs
    chunk_overlap: int = 64,
    include_citations: bool = True,
) -> Dict[str, Any]:
    """
    Search optimized for RAG ingestion.

    Returns:
        - chunks: Properly sized text chunks for vectorization
        - citations: High-quality metadata for Qdrant payload
        - quality_score: RAG suitability score (0-1)
    """
```

**Integration Points**:
- Use `rag/chunker.py` for intelligent text segmentation
- Return `KnowledgeChunk`-compatible metadata for Knowledge Fabric
- Score results by citation quality (domain authority, date, technical depth)
- Filter out low-quality sources (blogs, forums) for RAG use

**File Changes**:
- `searxng_integration.py`: Add `_chunk_for_rag()`, `_score_rag_quality()`
- `searxng_server.py`: Add `search_for_rag` tool with Pydantic schema
- **Lines**: +150

---

### 1.2 Vector Similarity Search ⭐ HIGH PRIORITY

**Purpose**: Enable "find similar content" searches using existing Qdrant infrastructure.

**New MCP Tools**:
```python
Tool(name="search_similar_to_url",
     description="Find content similar to a given URL using vector similarity")

Tool(name="search_similar_to_text",
     description="Find content similar to given text snippet")
```

**Implementation**:
```python
async def search_similar_to_url(
    url: str,
    max_results: int = 10,
    similarity_threshold: float = 0.75,
) -> Dict[str, Any]:
    """
    Fetch content from URL, embed it, and find similar pages via SearXNG + Qdrant.

    Workflow:
        1. Fetch and extract text from URL
        2. Generate embedding using rag/embeddings.py
        3. Search Qdrant for similar vectors
        4. Use SearXNG to find fresh web results
        5. Merge and rank by similarity
    """
```

**Integration Points**:
- Use `rag/embeddings.py` for text vectorization
- Use `rag/qdrant_client.py` for vector search
- Hybrid approach: Vector similarity + SearXNG freshness

**File Changes**:
- `searxng_integration.py`: Add `_fetch_and_embed()`, `_query_similar_vectors()`
- `searxng_server.py`: Add similarity search tools
- **Lines**: +200

---

### 1.3 Result Clustering & Topic Grouping ⭐ HIGH PRIORITY

**Purpose**: Automatically group search results by semantic similarity for better understanding.

**New MCP Tool**:
```python
Tool(name="cluster_search_results",
     description="Group search results by semantic similarity using embeddings")
```

**Implementation**:
```python
async def cluster_search_results(
    query: str,
    max_clusters: int = 5,
    clustering_algorithm: str = "dbscan",  # or "kmeans", "hierarchical"
) -> Dict[str, Any]:
    """
    Search and cluster results by topic.

    Returns:
        - clusters: List of topic groups with:
            - topic_name: Auto-generated label
            - results: Clustered search results
            - centroid: Representative result
        - dendrogram: Hierarchical structure (if hierarchical algorithm)
    """
```

**Integration Points**:
- Use `rag/embeddings.py` for result vectorization
- Use scikit-learn for clustering (DBSCAN, AgglomerativeClustering)
- Auto-generate topic labels using most frequent keywords in cluster

**File Changes**:
- `searxng_integration.py`: Add `_cluster_results()`, `_label_cluster()`
- `searxng_server.py`: Add `cluster_search_results` tool
- **Lines**: +180

---

### 1.4 AI-Aware Quality Scoring ⭐ MEDIUM PRIORITY

**Purpose**: Enhance existing quality scoring to prioritize results useful for AI agents.

**Enhancement to Existing**:
```python
# Current: searxng_integration.py already has quality scoring
# Enhance with AI-specific factors:

def _score_ai_quality(self, result: Dict, domain: str) -> float:
    """
    Score result for AI agent usefulness (0-1).

    Factors:
        - Citation quality (domain authority, .gov, .edu)
        - Code examples present
        - Technical depth (code snippets, API docs)
        - Freshness (publication date)
        - Structured content (JSON, API docs)
        - LLM training friendliness (clear structure, markdown)
    """
```

**File Changes**:
- `searxng_integration.py`: Enhance `_score_result_quality()`, add `_score_ai_quality()`
- **Lines**: +80

---

## Phase 2: Standard SearXNG Coverage (Week 4-5)

### 2.1 Advanced Search Operators

**New MCP Tool**:
```python
Tool(name="advanced_search",
     description="Search with boolean operators, phrase search, wildcards")
```

**Features**:
- Boolean: AND, OR, NOT operators
- Phrase: "exact phrase" queries
- Wildcard: *, ? pattern matching
- File type: filetype:pdf, filetype:doc
- Site: site:github.com specific site search
- Intitle: intitle:nixos search titles only

**Implementation**:
```python
async def advanced_search(
    query: str,
    boolean_mode: bool = False,
    phrase_mode: bool = False,
    wildcard_mode: bool = False,
    file_types: List[str] = None,
) -> Dict[str, Any]:
    """
    Advanced search with operators.
    """
```

**File Changes**:
- `searxng_integration.py`: Add `_build_advanced_query()`
- `searxng_server.py`: Add `advanced_search` tool
- **Lines**: +120

---

### 2.2 Category Support

**New MCP Tools**:
```python
Tool(name="search_images", description="Search for images")
Tool(name="search_videos", description="Search for videos")
Tool(name="search_news", description="Search news articles")
Tool(name="search_science", description="Search academic papers")
Tool(name="search_files", description="Search for files (torrents, etc.)")
```

**File Changes**:
- `searxng_integration.py`: Add category-specific methods
- `searxng_server.py`: Add 5 category tools
- **Lines**: +150

---

### 2.3 Time Range & Language Filters

**Enhancement to Existing**:
- `web_search` already has `time_range` parameter (enhance implementation)
- Add `language_filter` parameter with full language code support
- Add `safe_search` parameter

**File Changes**:
- `searxng_integration.py`: Enhance existing search methods
- **Lines**: +60

---

### 2.4 Engine Selection & Pagination

**New MCP Tools**:
```python
Tool(name="search_with_engines",
     description="Search using specific engines (google, bing, duckduckgo, etc.)")

Tool(name="search_next_page",
     description="Get next page of results from previous search")
```

**Implementation**:
- Add engine selection with fallback logic
- Implement session-based pagination
- Store search state in Redis cache

**File Changes**:
- `searxng_integration.py`: Add engine selection, pagination state
- `searxng_server.py`: Add engine and pagination tools
- **Lines**: +100

---

## Phase 3: Advanced Features (Week 6-7)

### 3.1 Search History & Saved Searches

**New MCP Tools**:
```python
Tool(name="search_history", description="Get past search queries and results")
Tool(name="save_search", description="Save a search query for later reuse")
Tool(name="saved_searches", description="List all saved searches")
Tool(name="run_saved_search", description="Execute a saved search")
```

**Storage**:
- Use existing Redis cache (`utils/redis_client.py`)
- Store in `searxng:saved_searches:{user_id}` key
- TTL: 30 days for history, 365 days for saved searches

**File Changes**:
- `searxng_integration.py`: Add history/save methods using Redis
- `searxng_server.py`: Add 4 history/save tools
- **Lines**: +130

---

### 3.2 Export Formats

**New MCP Tool**:
```python
Tool(name="export_search_results",
     description="Export search results to JSON, CSV, RSS, or ATOM format")
```

**Formats**:
- **JSON**: Structured data for programmatic use
- **CSV**: Spreadsheet-compatible format
- **RSS**: RSS 2.0 feed format
- **ATOM**: Atom Syndication Format

**File Changes**:
- `searxng_integration.py`: Add export methods
- `searxng_server.py`: Add `export_search_results` tool
- **Lines**: +80

---

### 3.3 Search Monitoring & Alerts

**New MCP Tools**:
```python
Tool(name="monitor_search",
     description="Monitor a search query for new results over time")

Tool(name="search_alerts",
     description="Create, list, or delete search alerts")

Tool(name="check_alerts",
     description="Check if any monitored searches have new results")
```

**Implementation**:
- Background task to periodically re-run monitored searches
- Compare results with previous run (using Redis cache)
- Trigger alert on new results (via webhook or callback)

**File Changes**:
- `searxng_integration.py`: Add monitoring logic
- `searxng_server.py`: Add 3 alert tools
- **Lines**: +140

---

## File Structure Changes

### New Files

```
ai_inference_gateway/
├── mcp_servers/
│   ├── searxng_server.py         # ENHANCED (279 → 450 lines)
│   └── searxng_tools/            # NEW DIRECTORY
│       ├── __init__.py
│       ├── rag_tools.py          # RAG-optimized search tools
│       ├── cluster_tools.py      # Clustering tools
│       ├── similarity_tools.py   # Vector similarity tools
│       └── export_tools.py       # Export format tools
│
├── searxng_integration.py        # ENHANCED (625 → 950 lines)
├── searxng_chunker.py            # NEW - RAG chunking utilities
├── searxng_clustering.py         # NEW - Result clustering
├── searxng_quality.py            # NEW - AI-aware quality scoring
└── searxng_monitoring.py         # ENHANCED (add alert monitoring)
```

### Module Organization

**Rationale**: Split into focused modules for:
- **Maintainability**: Each module has single responsibility
- **Testability**: Easier to unit test individual components
- **Reusability**: Tools can be imported independently

---

## Dependencies

### New Dependencies

```python
# Add to pyproject.toml or requirements.txt

# Clustering algorithms
scikit-learn >= 1.3.0

# Text processing for chunking
beautifulsoup4 >= 4.12.0
lxml >= 4.9.0

# Export formats
feedgenerator >= 0.9.0  # RSS/ATOM generation

# Already present (rag/ module)
qdrant-client >= 1.7.0
sentence-transformers >= 2.2.0
```

### Existing Dependencies to Leverage

```python
# Already in gateway
- qdrant-client          # Vector DB
- sentence-transformers   # Embeddings
- redis                  # Caching
- httpx                  # HTTP client
- fastapi                # API framework
- pydantic               # Validation
```

---

## Testing Strategy

### Unit Tests

**New Test Files**:
```
tests/
├── test_searxng_rag_tools.py
├── test_searxng_clustering.py
├── test_searxng_similarity.py
├── test_searxng_quality.py
└── test_searxng_exports.py
```

**Coverage Goals**:
- RAG tools: 90%+ (critical path)
- Clustering: 80%+
- Similarity: 85%+
- Quality scoring: 85%+
- Exports: 75%+

### Integration Tests

**Test Scenarios**:
1. RAG search → vectorize → store in Qdrant
2. Similarity search → embed → query Qdrant → merge with SearXNG
3. Clustering → vectorize results → cluster → label topics
4. End-to-end: SearXNG → chunk → RAG ingestion → LLM response

### Performance Tests

**Benchmarks**:
- RAG chunking: <500ms for 10 results
- Vector similarity: <300ms for Qdrant query
- Clustering: <1s for 50 results
- Advanced search: <2s for complex queries

---

## Success Metrics

### Phase 1 (AI Features)

**Week 3 Deliverables**:
- ✅ RAG-optimized search returning properly chunked results
- ✅ Vector similarity search integrated with Qdrant
- ✅ Result clustering with auto-generated topics
- ✅ AI-aware quality scoring implemented
- ✅ 4 new MCP tools, +610 lines of code

**Success Criteria**:
- RAG chunks are citation-quality (score >0.7)
- Similarity search returns relevant results (precision >0.8)
- Clustering produces meaningful topic groups (silhouette score >0.5)

### Phase 2 (Standard Features)

**Week 5 Deliverables**:
- ✅ Advanced search operators (boolean, phrase, wildcard)
- ✅ 5 category tools (images, videos, news, science, files)
- ✅ Time range and language filters
- ✅ Engine selection and pagination
- ✅ 11 new MCP tools, +430 lines of code

**Success Criteria**:
- All standard SearXNG API features exposed
- Advanced operators work correctly (boolean logic valid)
- Categories return appropriate results

### Phase 3 (Advanced Features)

**Week 7 Deliverables**:
- ✅ Search history and saved searches (Redis-backed)
- ✅ Export formats (JSON, CSV, RSS, ATOM)
- ✅ Search monitoring and alerts
- ✅ 10 new MCP tools, +350 lines of code

**Success Criteria**:
- History persists across sessions (Redis verified)
- Exports produce valid, parseable output
- Alerts trigger correctly on new results

---

## Risks & Mitigations

### Risk 1: Qdrant Performance Impact

**Risk**: Vector similarity searches may slow down SearXNG queries.

**Mitigation**:
- Use async operations throughout
- Set timeouts on Qdrant queries (500ms)
- Cache vector embeddings in Redis (TTL: 24h)
- Fallback to keyword-only search if Qdrant times out

### Risk 2: Clustering Quality

**Risk**: Poor clustering may produce meaningless topic groups.

**Mitigation**:
- Start with DBSCAN (automatically determines cluster count)
- Fallback to K-means with optimal K calculation
- Validate clusters with silhouette score
- Allow manual override of cluster count

### Risk 3: RAG Chunking Quality

**Risk**: Poor chunking may break context for LLMs.

**Mitigation**:
- Use existing `rag/chunker.py` (proven in production)
- Respect sentence boundaries
- Maintain overlap for context continuity
- Validate chunk sizes (target: 512 tokens, max: 1024)

### Risk 4: Increased Latency

**Risk**: AI features (clustering, similarity) add latency to searches.

**Mitigation**:
- Make AI features opt-in (separate tools)
- Keep basic `web_search` fast (<2s)
- Use caching aggressively
- Parallelize independent operations (asyncio.gather)

---

## Rollout Plan

### Week 1: RAG Foundation

**Tasks**:
1. Implement RAG-optimized search
2. Integrate with existing `rag/chunker.py`
3. Add AI-aware quality scoring
4. Write unit tests for RAG tools
5. Manual testing with sample queries

**Deliverables**:
- `searxng_chunker.py` module
- Enhanced `searxng_integration.py` with RAG methods
- 2 new MCP tools: `search_for_rag`, advanced quality scoring
- 80%+ test coverage

### Week 2: Vector Similarity

**Tasks**:
1. Integrate with `rag/qdrant_client.py`
2. Implement similarity search (URL and text-based)
3. Add hybrid ranking (vector + keyword)
4. Write unit and integration tests
5. Performance testing

**Deliverables**:
- Similarity search tools
- Qdrant integration working
- Hybrid ranking implemented
- 85%+ test coverage

### Week 3: Clustering

**Tasks**:
1. Implement result clustering (DBSCAN, K-means)
2. Auto-generate topic labels
3. Add cluster visualization (dendrogram)
4. Write tests with validation
5. Manual testing with diverse queries

**Deliverables**:
- Clustering tools
- Auto-labeling working
- 80%+ test coverage
- Documentation for clustering algorithms

### Week 4-5: Standard Features

**Tasks**:
1. Advanced search operators
2. Category support (5 tools)
3. Time range and language filters
4. Engine selection and pagination
5. Integration testing

**Deliverables**:
- 11 new standard search tools
- Full SearXNG API coverage
- Integration tests passing

### Week 6-7: Advanced Features

**Tasks**:
1. Search history (Redis-backed)
2. Export formats (JSON, CSV, RSS, ATOM)
3. Search monitoring and alerts
4. End-to-end testing
5. Documentation and examples

**Deliverables**:
- 10 new advanced tools
- Complete MCP server (40+ tools)
- Comprehensive documentation
- All tests passing

---

## Documentation

### User Documentation

**New Docs**:
```
docs/
├── searxng_mcp/
│   ├── README.md                    # Overview
│   ├── AI_FEATURES.md               # RAG, similarity, clustering
│   ├── STANDARD_FEATURES.md         # Operators, categories, filters
│   ├── ADVANCED_FEATURES.md         # History, exports, monitoring
│   ├── API_REFERENCE.md             # Complete tool reference
│   └── EXAMPLES.md                  # Usage examples
```

### Developer Documentation

**New Docs**:
```
docs/
├── searxng_mcp/
│   ├── ARCHITECTURE.md              # System design
│   ├── INTEGRATION.md               # Knowledge Fabric integration
│   ├── TESTING.md                   # Testing strategy
│   └── PERFORMANCE.md               # Benchmarks and optimization
```

---

## Next Steps

1. **Review and approve this design** ✅ (awaiting approval)
2. **Set up development environment**
   - Install scikit-learn, beautifulsoup4, feedgenerator
   - Verify Qdrant connectivity
   - Test existing SearXNG instance
3. **Create implementation tasks** (using writing-plans skill)
4. **Begin Phase 1 implementation** (Week 1)

---

## Questions for Review

1. **Clustering Algorithm**: Should we default to DBSCAN or K-means? (DBSCAN is parameter-free, K-means requires K)
2. **Qdrant Collection**: Should we create a dedicated SearXNG collection in Qdrant, or use the existing knowledge-base?
3. **Caching Strategy**: TTL for vector embeddings? (Proposed: 24h for content, 7 days for URLs)
4. **RAG Chunk Size**: Target 512 tokens or 1024? (Proposed: 512 with 64-token overlap)
5. **Performance Targets**: Are the latency targets acceptable? (RAG <500ms, similarity <300ms, clustering <1s)

---

**Total Estimated Effort**: 7 weeks
**Total Code Addition**: ~1,300 lines (from 900 → 2,200 lines)
**New MCP Tools**: 30 tools (from 10 → 40 tools)
**Risk Level**: Medium (integrating with existing proven infrastructure)

---

**End of Design Document**
