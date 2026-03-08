# Pinecone Skills Consolidation Specification

**Overview**: Consolidate 7 Pinecone skills into 3 category-based skills
**Created**: 2026-03-07
**Status**: Specification ready for implementation

---

## Consolidation Map

| New Skill | Source Skills (Remove) | Count |
|-----------|----------------------|-------|
| `pinecone:guide` | pinecone:help, pinecone:docs, pinecone:quickstart, pinecone:join-discord | 4→1 |
| `pinecone:usage` | pinecone:assistant, pinecone:cli, pinecone:query | 3→1 |
| `pinecone:mcp` | pinecone:mcp | 1→1 (keep as-is) |

**Total**: 7 source skills → 3 consolidated skills

---

## 1. pinecone:guide

### Skill Manifest
```yaml
name: pinecone:guide
description: Complete Pinecone documentation and quick start guide including setup, configuration, best practices, and community resources.

triggers:
  - "Pinecone quickstart..."
  - "Pinecone setup guide..."
  - "Pinecone documentation..."
  - "How to use Pinecone..."
```

### Content Structure

#### 1.1 Quick Start Guide

**Installation**:
```bash
# Install Pinecone CLI
npm install -g @pinecone-database/pinecone-cli

# Or using pip
pip install pinecone-client

# Authenticate
pinecone login
```

**Create Your First Index**:
```python
import pinecone

# Initialize
pc = pinecone.Pinecone(api_key="your-api-key")

# Create index
pc.create_index(
    name="my-first-index",
    dimension=768,  # Match your model
    metric="cosine",
    spec=ServerlessSpec(
        cloud="aws",
        region="us-east-1"
    )
)
```

#### 1.2 Core Concepts

**Index Types**:
| Type | Best For | Cost |
|------|----------|------|
| **Serverless** | Variable/spiky workloads | Pay per usage |
| **Pod-based** | Consistent high performance | Fixed price |

**Metrics**:
- `cosine`: Best for normalized embeddings (0-1)
- `dotproduct`: Faster when vectors are normalized
- `euclidean`: Physical distance, slower

**Dimension Guidelines**:
| Model | Dimension | Use Case |
|-------|-----------|----------|
| text-embedding-ada-002 | 1536 | General text |
| multilingual-e5-large | 1024 | Multilingual |
| all-MiniLM-L6-v2 | 384 | Fast, lightweight |
| BGE-large | 1024 | Chinese/English |

#### 1.3 Best Practices

**Index Naming**:
```
# Good
- product-embeddings-v1
- user-preferences-prod
- docs-search-staging

# Bad
- index1
- test
- embeddings
```

**Batch Size Recommendations**:
```python
# Optimal batch sizes
upsert_batch_size = 100  # Balance speed and memory
query_batch_size = 10     # For multiple queries
```

**Namespace Strategy**:
```
# Use namespaces for multi-tenancy
index.upsert([
    ("tenant1/doc1", vector1),
    ("tenant2/doc1", vector2),
], namespace="tenant1")  # Each tenant isolated
```

#### 1.4 Common Patterns

**Hybrid Search (Keyword + Vector)**:
```python
# 1. Filter metadata first
results = index.query(
    vector=query_vector,
    filter={"category": "electronics"},
    top_k=10
)

# 2. Re-rank with cross-encoder
from sentence_transformers import CrossEncoder
reranker = CrossEncoder('ms-marco-MiniLM-L-6-v2')
reranked = reranker.rank(query, results)
```

**Updating vs Upserting**:
```python
# Update: Replace existing vector
index.update(id="doc1", values=new_vector)

# Upsert: Insert or replace
index.upsert([("doc1", new_vector)])
```

#### 1.5 Community Resources

**Official Resources**:
- Documentation: https://docs.pinecone.io
- GitHub: https://github.com/pinecone-io
- Discord: https://discord.gg/pinecone

**Community Examples**:
- Recipe search assistant
- Document Q&A system
- Recommendation engine
- Semantic search
- Deduplication system

---

## 2. pinecone:usage

### Skill Manifest
```yaml
name: pinecone:usage
description: Complete Pinecone usage expertise including CLI operations, assistant integration, and query patterns.

triggers:
  - "Pinecone CLI..."
  - "Query Pinecone..."
  - "Pinecone assistant..."
  - "Upsert vectors..."
```

### Content Structure

#### 2.1 CLI Operations

```bash
# List indexes
pinecone index list

# Describe index
pinecone index describe my-index

# Delete index
pinecone index delete my-index

# Create index (CLI)
pinecone index create \
  --name my-index \
  --dimension 768 \
  --metric cosine \
  --cloud aws \
  --region us-east-1

# Configure
pinecone configure set-api-key YOUR_KEY
pinecone configure set-environment us-east-1-aws
```

#### 2.2 Vector Operations

**Upsert (Insert/Update)**:
```python
# Single vector
index.upsert([("doc1", [0.1, 0.2, ...], {"category": "tech"})])

# Batch upsert (recommended)
vectors = [
    ("doc1", vec1, {"url": "https://..."}),
    ("doc2", vec2, {"url": "https://..."}),
]
index.upsert(vectors, batch_size=100)

# Async upsert for large batches
async def upsert_async(vectors):
    tasks = [index.upsert_async(batch)
              for batch in chunks(vectors, 100)]
    await asyncio.gather(*tasks)
```

**Query Patterns**:
```python
# Basic query
results = index.query(
    vector=[0.1, 0.2, ...],
    top_k=10,
    include_metadata=True,
    include_values=True
)

# Filtered query
results = index.query(
    vector=query_vec,
    filter={
        "category": {"$eq": "tech"},
        "price": {"$lt": 100}
    },
    top_k=10
)

# Namespace query
results = index.query(
    vector=query_vec,
    namespace="tenant1",
    top_k=10
)

# Sparse vector search (hybrid)
results = index.query(
    vector=dense_vec,
    sparse_vector=sparse_vec,  # BM25-style
    top_k=10
)
```

**Delete Operations**:
```python
# Delete by ID
index.delete(ids=["doc1", "doc2"])

# Delete by filter
index.delete(
    filter={"status": {"$eq": "archived"}},
    namespace="docs"
)

# Delete all
index.delete(delete_all=True)
```

#### 2.3 Assistant Integration

**Pinecone Assistant Setup**:
```python
from pinecone import Pinecone, Assistant

pc = Pinecone(api_key="your-key")

# Create assistant
assistant = pc.Assistant.create(
    assistant_name="my-assistant",
    instructions="You are a helpful assistant for...",
    context="docs",  # Reference to files/knowledge
    tool="file_search"  # Enable file search
)

# Chat with assistant
response = assistant.chat_messages(
    assistant_id="asst_xxx",
    messages=[
        {"role": "user", "content": "What is...?"}
    ]
)
```

**Assistant Configuration**:
```python
# With RAG
assistant = pc.Assistant.create(
    assistant_name="rag-assistant",
    context=[
        {"file": "doc1.pdf"},
        {"text": "Additional context..."}
    ],
    tool_relevance_threshold=0.7
)

# With tool use
assistant = pc.Assistant.create(
    assistant_name="tool-assistant",
    instructions="Use tools when needed...",
    tools=["web_search", "code_interpreter"]
)
```

#### 2.4 Query Optimization

**Prefiltering** (Metadata filters before vector search):
```python
# Faster: Filter first
results = index.query(
    vector=query_vec,
    filter={"in_stock": True, "price": {"$lt": 100}},
    top_k=10
)
```

**Re-ranking** (Improve relevance):
```python
# 1. Get more results than needed
results = index.query(vector=query_vec, top_k=100)

# 2. Re-rank with cross-encoder
from rank_bm25 import BM25Okapi
reranker = BM25Okapi([r.metadata['text'] for r in results])
reranked = reranker.get_top_n(query, n=10)
```

**Query Caching**:
```python
from functools import lru_cache

@lru_cache(maxsize=1000)
def cached_query(vector_hash, namespace):
    return index.query(vector=vector, namespace=namespace)
```

---

## 3. pinecone:mcp

### Skill Manifest
```yaml
name: pinecone:mcp
description: Pinecone MCP server integration for AI agents, including tool definitions and usage patterns.

triggers:
  - "Pinecone MCP..."
  - "Vector search MCP..."
  - "Pinecone tools..."
```

### Content Structure

#### 3.1 MCP Server Setup

**MCP Server Configuration**:
```json
{
  "mcpServers": {
    "pinecone": {
      "command": "npx",
      "args": ["-y", "@pinecone-database/mcp-server"],
      "env": {
        "PINECONE_API_KEY": "your-api-key"
      }
    }
  }
}
```

**Available MCP Tools**:
```yaml
# List indexes
pinecone:list_indexes()

# Create index
pinecone:create_index(
  name="my-index",
  dimension=768,
  metric="cosine"
)

# Upsert records
pinecone:upsert_records(
  name="my-index",
  namespace="default",
  records=[
    {
      "id": "doc1",
      "values": [0.1, 0.2, ...],
      "metadata": {"text": "..."}
    }
  ]
)

# Search records
pinecone:search_records(
  name="my-index",
  namespace="default",
  query={
    "topK": 10,
    "values": [0.1, 0.2, ...],
    "filter": {"category": "tech"}
  }
)

# Describe index
pinecone:describe_index(name="my-index")

# Delete index
pinecone:delete_index(name="my-index")
```

#### 3.2 Agent Integration Pattern

```python
# Example: AI agent using Pinecone MCP
async def agent_knowledge_search(query: str):
    # 1. Generate embedding for query
    query_vec = await embed_query(query)

    # 2. Search via MCP
    results = await mcp_client.call_tool(
        "pinecone:search_records",
        {
            "name": "knowledge-base",
            "query": {
                "topK": 5,
                "values": query_vec
            }
        }
    )

    # 3. Use results in generation
    context = "\n".join([r["metadata"]["text"] for r in results])
    return await generate_with_context(query, context)
```

---

## Quick Reference

| Task | Use This Skill |
|------|---------------|
| Get started with Pinecone | pinecone:guide |
| Set up first index | pinecone:guide |
| Learn best practices | pinecone:guide |
| Use CLI commands | pinecone:usage |
| Query vectors | pinecone:usage |
| Assistant integration | pinecone:usage |
| MCP server setup | pinecone:mcp |
| Agent integration | pinecone:mcp |

---

## References

- Pinecone Docs: https://docs.pinecone.io
- Pinecone GitHub: https://github.com/pinecone-io/pinecone-ts-client
- Pinecone Discord: https://discord.gg/pinecone
