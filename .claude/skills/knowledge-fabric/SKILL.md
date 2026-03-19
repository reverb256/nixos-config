---
name: knowledge-fabric
description: Advanced multi-source knowledge retrieval system. Use this when researching technical topics, comparing options, or answering questions that require comprehensive information from multiple sources (RAG knowledge base, code search, SearXNG metasearch, web search). Automatically classifies query intent (CODE, FACTUAL, PROCEDURAL, REALTIME, COMPARATIVE, CONTEXTUAL), routes to optimal sources, and fuses results using Reciprocal Rank Fusion (RRF). This is superior to direct web search for complex research tasks. Use for: "research X", "compare Y vs Z", "how do I configure X", "find information about Y", "explain topic Z". Works with your NixOS AI infrastructure's Knowledge Fabric middleware.
compatibility: Requires local AI Gateway at http://127.0.0.1:8080 with Knowledge Fabric middleware enabled.
---

# Knowledge Fabric - Multi-Source Knowledge Retrieval

The Knowledge Fabric is your cluster's advanced knowledge retrieval system that combines multiple intelligent sources into unified, contextual answers.

## When to Use This Skill

Use the Knowledge Fabric when you need to:
- **Research technical topics** (NixOS, Kubernetes, development tools)
- **Compare options** (technologies, approaches, configurations)
- **Find comprehensive information** from multiple sources simultaneously
- **Get contextual answers** with cited sources
- **Leverage your cluster's private knowledge base** (RAG indexed documents)

## What Makes It Different

Unlike single-source search, Knowledge Fabric:
1. **Classifies your query intent** - Understands if you need code, facts, procedures, or real-time data
2. **Routes to optimal sources** - Selects the best combination of RAG, code search, SearXNG, and web search
3. **Retrieves in parallel** - All sources queried simultaneously for speed
4. **Fuses with RRF** - Reciprocal Rank Fusion merges results by relevance
5. **Circuit breaker protection** - Gracefully handles source failures

## Available Knowledge Sources

| Source | Priority | Best For | Location |
|--------|----------|---------|----------|
| **Code Search** | CRITICAL | Implementation examples, API usage | `/etc/nixos` codebase |
| **RAG Knowledge Base** | HIGH | Previously indexed docs, guides | Qdrant vector DB |
| **SearXNG Metasearch** | MEDIUM | Web-wide search, privacy-respecting | Local SearXNG instance |
| **Web Search** | MEDIUM | Fresh results, current data | MCP web_search_prime |

## Query Intent Classification

The semantic router classifies your query into intents:

- **CODE**: Functions, APIs, implementations, debugging
- **FACTUAL**: Definitions, explanations, specific information
- **PROCEDURAL**: How-to, tutorials, setup guides, steps
- **REALTIME**: Current data, news, recent changes
- **COMPARATIVE**: X vs Y, alternatives, comparisons
- **CONTEXTUAL**: Deep explanations, background, concepts

## Usage Examples

### Research a Technical Topic
```
"How does Kubernetes networking work?"
→ Routes to: Code Search (K8s code), RAG (docs), SearXNG (guides)
→ Returns: Code snippets, documentation excerpts, tutorial links
```

### Compare Options
```
"Compare ZFS and Btrfs for NixOS"
→ Routes to: SearXNG (comparisons), RAG (storage docs)
→ Returns: Feature comparisons, benchmarks, recommendations
```

### Find Configuration Help
```
"How do I configure Flakes for colmena deployment?"
→ Routes to: Code Search (flake.nix examples), RAG (NixOS docs)
→ Returns: Code examples, step-by-step guides, common pitfalls
```

## Understanding RRF Fusion

The Knowledge Fabric uses **Reciprocal Rank Fusion** to merge results from multiple sources:

```
RRF_score(d) = Σ 1/(k + rank_i(d))
```

Where:
- `d` = a document/result
- `k` = constant (default 60)
- `rank_i(d)` = rank of document in source i's results

This gives higher scores to results that appear near the top of multiple sources.

## Domain-Aware Routing

For SearXNG queries, the system automatically detects the domain and routes to specialized engines:

| Domain | Indicators | Engines Used |
|--------|------------|--------------|
| **code** | github, function, API, implementation | GitHub, GitLab, StackOverflow |
| **research** | paper, arxiv, scholar, academic | Google Scholar, arXiv, Semantic Scholar |
| **devops** | docker, kubernetes, deploy, terraform | Docker Hub, GitHub, StackOverflow |
| **data** | machine learning, neural, model, training | arXiv, Kaggle, HuggingFace |

## Configuration

The Knowledge Fabric is configured in your NixOS gateway:
- **Location**: `modules/services/ai-inference/ai_inference_gateway/middleware/knowledge_fabric/`
- **Main File**: `fabric.py` (orchestrator)
- **Sources**: `sources/` directory
- **SearXNG URL**: `http://127.0.0.1:7777`
- **Qdrant URL**: `http://127.0.0.1:6333`

## Testing the Knowledge Fabric

### Quick Health Check
```bash
# Check gateway is running
curl http://127.0.0.1:8080/health

# Test SearXNG directly
curl "http://127.0.0.1:7777/search?q=test&format=json" | jq '.results | length'
```

### Query via Gateway
```bash
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4",
    "messages": [{"role": "user", "content": "How do I configure NixOS flakes?"}],
    "stream": false
  }'
```

## Troubleshooting

### No Results Returned
1. Check SearXNG: `systemctl status searx`
2. Check Qdrant: `systemctl status qdrant`
3. Check Gateway logs: `journalctl -u ai-inference-gateway -f`

### All Results from One Source
- Check semantic router is working: Gateway logs should show "Routing decision"
- Verify source priorities in `fabric.py`

### Circuit Breaker Tripping
- A source may be temporarily disabled after failures
- Check circuit breaker state in gateway logs
- Sources automatically recover after success threshold

## Advanced Features

### RAG-Optimized Search
SearXNG results can be automatically indexed in Qdrant for future retrieval:
```python
await rag_indexer.search_and_index(
    query="nixos flake tutorial",
    searxng_client=searxng,
    collection="searxng-results"
)
```

### Similarity Search
Find content similar to a URL or text:
```python
await rag_indexer.search_similar_to_url(
    url="https://nixos.org/guides/",
    max_results=10
)
```

### Result Clustering
Group search results into semantic topics:
```python
clusters = await clusterer.cluster_results(
    results=search_results,
    max_clusters=5
)
```

### Search History
Query and result history with 30-day TTL:
```python
# Save search
await history.save_search(query, results, domain="code")

# Retrieve history
entries = await history.get_history(user_id="user", limit=50)
```

## Integration Points

The Knowledge Fabric integrates with:
- **MCP Broker** (`:9000/mcp`) - Tool aggregation
- **Semantic Router** - Query classification
- **Circuit Breaker** - Resilience patterns
- **Prometheus Metrics** - `knowledge_fabric_*` metrics
- **Qdrant** - Vector storage for RAG
- **Redis** - Cache and history storage

## Key Files Reference

| File | Purpose |
|------|---------|
| `fabric.py` | Main middleware orchestrator |
| `routing.py` | Semantic query classification |
| `fusion.py` | RRF result merging |
| `sources/searxng_source.py` | SearXNG integration (enhanced) |
| `sources/code_search_source.py` | Local code search |
| `sources/rag_source.py` | RAG knowledge base |
| `core.py` | Data structures and abstractions |
| `metrics.py` | Prometheus metrics |

## Best Practices

1. **Be specific in queries** - More specific queries get better routing
2. **Use technical keywords** - Helps CODE intent detection
3. **Quote when searching for exact phrases** - Improves precision
4. **Check multiple sources** - RRF fuses across all selected sources
5. **Leverage domain routing** - Code/research/devops domains use specialized engines

## See Also

- [Knowledge Fabric Integration Guide](modules/services/ai-inference/KNOWLEDGE_FABRIC_INTEGRATION.md)
- [SearXNG Integration](modules/services/ai-inference/searxng_integration.py)
- [RAG Documentation](modules/services/ai-inference/ai_inference_gateway/rag/)
