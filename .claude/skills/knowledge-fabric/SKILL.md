---
name: knowledge-fabric
description: Advanced multi-source knowledge retrieval system using MCP tools. Use this when researching technical topics, comparing options, or answering questions that require comprehensive information from multiple sources (code search, SearXNG metasearch, web search, NixOS options, academic papers). Automatically classifies query intent (CODE, FACTUAL, PROCEDURAL, REALTIME, COMPARATIVE, CONTEXTUAL), routes to optimal MCP tools, executes parallel searches, aggregates results, and presents ranked findings. This is superior to direct web search for complex research tasks. Use for: "research X", "compare Y vs Z", "how do I configure X", "find information about Y", "explain topic Z". Works with MCP tools (search_code, search_github, search_stackoverflow, search_research, web_search, etc.) via your gateway MCP server.
compatibility: Requires MCP tools configured in settings.json (gateway bridge or direct SearXNG MCP server).
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

The Knowledge Fabric uses MCP tools directly for reliable, fast knowledge retrieval:
- **SearXNG URL**: `http://10.1.1.110:30080` (NodePort for LAN access)
- **Qdrant URL**: `http://127.0.0.1:6333`
- **Gateway API**: `http://127.0.0.1:8080` (used for direct API access, not for skill execution)

## Skill Workflow

When this skill is invoked, execute the following workflow:

### Step 1: Analyze Query Intent

Classify the user's query into one or more intent categories:
- **CODE**: Functions, APIs, implementations, debugging, code examples
- **FACTUAL**: Definitions, explanations, specific information, documentation
- **PROCEDURAL**: How-to, tutorials, setup guides, step-by-step instructions
- **REALTIME**: Current data, news, recent changes, time-sensitive information
- **COMPARATIVE**: X vs Y, alternatives, comparisons, trade-offs
- **CONTEXTUAL**: Deep explanations, background, concepts, theory

**Classification Indicators**:
- Code keywords: `function`, `class`, `API`, `implement`, `debug`, `syntax`, `programming`
- Reasoning keywords: `analyze`, `compare`, `evaluate`, `explain why`, `logic`, `inference`
- Procedural keywords: `how to`, `configure`, `setup`, `install`, `steps`, `tutorial`

### Step 2: Select Optimal MCP Tools

Based on the query intent, select the appropriate MCP tools:

| Intent | Primary Tools | Secondary Tools |
|--------|---------------|-----------------|
| **CODE** | `search_code`, `search_github`, `search_stackoverflow` | `search_mdn` (web dev), `search_nixos_options` |
| **FACTUAL** | `web_search`, `search_research` | `ping_searxng` |
| **PROCEDURAL** | `search_code`, `web_search`, `search_devops` | `search_github` (for examples) |
| **REALTIME** | `web_search` | `ping_searxng` |
| **COMPARATIVE** | `web_search`, `search_research` | `search_code` (for implementations) |
| **CONTEXTUAL** | `search_research`, `web_search` | `search_code` |

**Domain-Specific Tool Selection**:
- **NixOS/Configuration**: `search_nixos_options`, `search_code`
- **Kubernetes/DevOps**: `search_devops`, `search_github`
- **Academic/Papers**: `search_research`
- **Machine Learning**: `search_data`
- **Web Development**: `search_mdn`, `search_code`

### Step 3: Execute Parallel Searches

Call the selected MCP tools in parallel (not sequentially):

```python
# Example: CODE intent query
tools_to_call = [
    "search_code",
    "search_github",
    "search_stackoverflow"
]

# Execute all tools concurrently
results = await execute_tools_in_parallel(tools_call, query)
```

**Important**: Always use parallel execution for multiple tools to minimize latency.

### Step 4: Aggregate and Rank Results

1. **Collect results** from all tools
2. **Remove duplicates** based on URL/title similarity
3. **Score by relevance**:
   - Keyword matches in title: +3 points
   - Keyword matches in content: +1 point
   - Source reputation (GitHub docs > blog > forum): +2 points
   - Recency (for REALTIME): +2 points
4. **Sort by score** (highest first)
5. **Return top 10-15 results**

### Step 5: Present Results

Format the results as:
```markdown
## Knowledge Fabric Results

### Query Analysis
- **Intent**: [CODE/FACTUAL/PROCEDURAL/etc]
- **Sources**: [list of tools used]
- **Total Results**: [number]

### Top Results

#### 1. [Result Title]
**Source**: [Tool name]
**URL**: [Link]
**Snippet**: [Relevant excerpt]
**Relevance**: [High/Medium/Low]

#### 2. [Next Result]
...

### Summary
[2-3 sentence synthesis of key findings]
```

### Step 6: Provide Follow-up Suggestions

Based on the results, suggest:
- **Refined searches**: "Narrow down with specific keywords"
- **Related topics**: "You might also be interested in..."
- **Actionable next steps**: "To implement this, consider..."

---

## Example Execution

**User Query**: "How do I configure NixOS flakes for colmena deployment?"

**Step 1: Intent Classification**
- Keywords: "configure", "NixOS flakes", "colmena deployment"
- Intent: **PROCEDURAL** + **CODE**

**Step 2: Tool Selection**
- Primary: `search_code` (flake.nix examples)
- Secondary: `search_nixos_options` (configuration options)
- Tertiary: `web_search` (tutorials, guides)

**Step 3: Parallel Execution**
```python
results = {
    "search_code": [...],  # 10 flake.nix examples
    "search_nixos_options": [...],  # 5 relevant options
    "web_search": [...]  # 8 tutorials
}
```

**Step 4: Aggregation**
- Total: 23 raw results
- After deduplication: 18 unique results
- Top 10 selected

**Step 5: Presentation**
```markdown
## Knowledge Fabric Results

### Query Analysis
- **Intent**: PROCEDURAL + CODE
- **Sources**: search_code, search_nixos_options, web_search
- **Total Results**: 18 unique results

### Top Results

#### 1. Colmena Flake Configuration Example
**Source**: search_code
**URL**: https://github.com/zefroser/colmena-flake-example
**Snippet**: Complete flake.nix with colmena deployment configuration...
**Relevance**: High

#### 2. NixOS Flakes Guide
**Source**: web_search
**URL**: https://nixos.wiki/wiki/Flakes
**Snippet**: Comprehensive guide to NixOS flakes...
**Relevance**: High

[... more results ...]

### Summary
Colmena works seamlessly with NixOS flakes. You need to:
1. Initialize a flake with `nix flake init`
2. Configure colmena in `flake.nix`
3. Use `colmena apply` to deploy
```

## Testing the Knowledge Fabric

### Quick Health Check
```bash
# Check gateway is running
curl http://127.0.0.1:8080/health

# Test SearXNG directly (NodePort)
curl "http://10.1.1.110:30080/search?q=test&format=json" | jq '.results | length'

# Test Qdrant vector DB
curl http://127.0.0.1:6333/collections

# Test Redis cache
redis-cli -p 6380 PING
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

---

## Comprehensive Test Results (2026-03-19)

All infrastructure components validated and operational:

| Component | Status | Endpoint | Performance |
|-----------|--------|----------|-------------|
| **SearXNG Metasearch** | ✅ OPERATIONAL | http://10.1.1.110:30080 | <1s response, 10 results/query |
| **Qdrant Vector DB** | ✅ OPERATIONAL v1.16.3 | http://127.0.0.1:6333 | 8 collections active |
| **Redis Cache** | ✅ OPERATIONAL v8.2.3 | localhost:6380 | 787KB memory, sub-ms PING |
| **Code Search Base** | ✅ INDEXED | /etc/nixos | 428 NixOS files, 97 Python modules |
| **Domain Routing** | ✅ OPERATIONAL | All domains | CODE/GITHUB/ACADEMIC working |

## Optimal Access Patterns

### Access Hierarchy (Power Level)

**📍 LEVEL 1: Direct MCP Tools** (⭐⭐)
```
Use specific MCP tools directly for simple queries:
- search_code for code examples
- web_search for general web search
- search_nixos_options for NixOS configuration
```
Best for: Single-source queries, quick lookups

**📍 LEVEL 2: /knowledge-fabric Skill** (⭐⭐⭐⭐⭐)
```
/knowledge-fabric
Your complex research question here
```
Most powerful because:
- Semantic query classification (CODE/FACTUAL/PROCEDURAL/REALTIME)
- Multi-source parallel execution using MCP tools
- Intelligent result aggregation and ranking
- Domain-aware tool selection
- Comprehensive result synthesis

Best for: Complex research requiring multiple sources

**📍 LEVEL 3: Gateway API** (⭐⭐⭐⭐)
```bash
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-sonnet-4", "messages": [...]}'
```
Best for: Application integration, automated workflows

### Usage Recommendations

| Query Type | Recommended Method | Example |
|------------|-------------------|---------|
| Complex research | `/knowledge-fabric` | "Compare ZFS vs Btrfs for NixOS" |
| Code examples | MCP `search_code` | "Kubernetes deployment NixOS flake" |
| Academic papers | MCP `search_research` | "transformer optimization 2024" |
| Troubleshooting | `/knowledge-fabric` | "permission denied Kubernetes pods" |
| Quick lookup | MCP `web_search` | Simple factual queries |
| App integration | Gateway API | Automated workflows |

### MCP Tools Catalog

**General**: `web_search`, `ping_searxng`, `search_stats`, `clear_search_cache`

**Code & Development**:
- `search_code` - Domain-aware code search
- `search_github` - GitHub repositories
- `search_stackoverflow` - Programming Q&A
- `search_mdn` - Web development docs

**Academic & Research**:
- `search_research` - Papers and academic sources

**DevOps & Infrastructure**:
- `search_devops` - Docker, Kubernetes, deployment

**AI/ML & Data Science**:
- `search_data` - ML models, datasets, training

**Configuration**:
- `search_nixos_options` - NixOS configuration docs
