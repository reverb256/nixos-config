# RAG Architecture Design - 2026 Best Practices

## Overview
Production-ready RAG implementation for AI inference gateway using state-of-the-art 2026 practices.

## Technology Stack

### Embedding Model
**Model**: `BAAI/bge-m3` (FlagEmbedding)
- **MTEB Score**: 63.0
- **Dimensions**: 1024
- **Context Window**: 8192 tokens (excellent for long documents)
- **Languages**: Multilingual (excellent Chinese + English)
- **Cost**: Free (open-source)
- **Why**: Best balance of performance, multilingual support, and long context handling

### Chunking Strategy
**Method**: Recursive Character Text Splitting
- **Chunk Size**: 512 tokens
- **Overlap**: 50 tokens (~10%)
- **Separators**: `["\n\n", "\n", ". ", " ", ""]`
- **Why**: Proven baseline, preserves document structure, maintains semantic integrity

### Hybrid Search
**Dense (Vector)**: BGE-M3 embeddings
**Sparse (BM25)**: Qdrant sparse vector support
**Fusion**: Reciprocal Rank Fusion (RRF) with k=60
**Why**: Combines semantic understanding with precise keyword matching

### Reranking
**Model**: `BAAI/bge-reranker-v2-base`
**Pipeline**: Recall top-30 → Rerank to top-5
**Why**: Refines results, improves precision by 15-30%

### Vector Database
**Database**: Qdrant (already running)
**Client**: AsyncQdrantClient (async/await)
**Protocol**: gRPC (prefer_grpc=True)
**Why**: Production-ready, excellent performance, async support

## API Endpoints

### 1. POST /rag/documents
**Purpose**: Ingest documents into RAG knowledge base
**Request**:
```json
{
  "collection": "default",
  "documents": [
    {
      "content": "Document text...",
      "metadata": {
        "title": "Document Title",
        "source": "path/to/document.txt",
        "category": "documentation",
        "timestamp": "2026-03-05T00:00:00Z"
      }
    }
  ]
}
```
**Response**:
```json
{
  "success": true,
  "documents_ingested": 5,
  "chunks_created": 47,
  "collection": "default"
}
```

### 2. GET /rag/search
**Purpose**: Semantic search over knowledge base
**Query Params**:
- `query` (required): Search query
- `collection` (optional): Collection name (default: "default")
- `top_k` (optional): Number of results (default: 5)
- `rerank` (optional): Enable reranking (default: true)

**Response**:
```json
{
  "query": "How do I configure NixOS?",
  "results": [
    {
      "content": "NixOS configuration...",
      "score": 0.892,
      "metadata": {...}
    }
  ],
  "total_results": 5,
  "reranked": true
}
```

### 3. GET /rag/collections
**Purpose**: List all RAG collections
**Response**:
```json
{
  "collections": [
    {
      "name": "default",
      "documents_count": 150,
      "chunks_count": 1247,
      "created_at": "2026-03-05T00:00:00Z"
    }
  ]
}
```

### 4. DELETE /rag/documents
**Purpose**: Delete document from knowledge base
**Request**:
```json
{
  "collection": "default",
  "document_id": "doc_uuid"
}
```

## Data Models

### Document Ingestion Pipeline
```
Document → Validation → Chunking → Embedding (Dense + Sparse) → Qdrant Storage
```

### Qdrant Collection Schema
```python
{
  "collection_name": "default",
  "vectors": {
    "size": 1024,  # BGE-M3 dimensions
    "distance": "Cosine"
  },
  "sparse_vectors": {
    "text": {}  # BM25 sparse vectors
  },
  "payload_schema": {
    "document_id": "string",
    "chunk_id": "string",
    "content": "string",
    "metadata": "object"
  }
}
```

## Implementation Architecture

### Module Structure
```
ai_inference_gateway/
├── rag/
│   ├── __init__.py
│   ├── config.py          # RAG configuration
│   ├── embeddings.py      # Embedding service (BGE-M3)
│   ├── chunker.py         # Document chunking
│   ├── qdrant_client.py   # Qdrant client manager
│   ├── search.py          # Hybrid search logic
│   └── reranker.py        # Reranking service
```

### Async Client Management
```python
class QdrantClientManager:
    """Singleton pattern for Qdrant client"""
    _instance = None
    _client: Optional[AsyncQdrantClient] = None

    async def get_client(self) -> AsyncQdrantClient:
        if self._client is None:
            self._client = AsyncQdrantClient(
                url="http://127.0.0.1:6333",
                prefer_grpc=True,
                timeout=10
            )
        return self._client
```

### Hybrid Search Flow
```python
async def hybrid_search(query: str, top_k: int = 5):
    # 1. Embed query
    query_dense = await embedder.embed_dense(query)
    query_sparse = await embedder.embed_sparse(query)

    # 2. Parallel search (dense + sparse)
    dense_results = await qdrant.search_dense(query_dense, limit=30)
    sparse_results = await qdrant.search_sparse(query_sparse, limit=30)

    # 3. Reciprocal Rank Fusion
    fused_results = reciprocal_rank_fusion(dense_results, sparse_results, k=60)

    # 4. Rerank top results
    reranked = await reranker.rerank(query, fused_results[:30])

    return reranked[:top_k]
```

## Configuration

### NixOS Configuration
```nix
services.ai-inference.rag = {
  enable = true;

  # Embedding model
  embeddingModel = "BAAI/bge-m3";
  embeddingDevice = "cuda";  # Use RTX 3090 GPU

  # Chunking
  chunkSize = 512;
  chunkOverlap = 50;

  # Search
  defaultTopK = 5;
  hybridSearch.enable = true;
  hybridSearch.denseWeight = 0.5;  # RRF equivalent
  hybridSearch.sparseWeight = 0.5;

  # Reranking
  reranker.enable = true;
  reranker.model = "BAAI/bge-reranker-v2-base";
  reranker.topK = 30;  # Recall top-K
  reranker.finalK = 5;  # Rerank to final-K

  # Qdrant
  qdrantUrl = "http://127.0.0.1:6333";
};
```

## Performance Targets

- **Ingestion**: 100 documents/second
- **Search**: <100ms p95 latency
- **Reranking**: <200ms for top-30 → top-5
- **Memory**: <4GB for embedding models
- **GPU**: Utilize RTX 3090 for embeddings

## Error Handling

### Embedding Failures
- Retry with exponential backoff
- Fallback to CPU if GPU fails
- Log errors for monitoring

### Qdrant Failures
- Circuit breaker after 5 consecutive failures
- Graceful degradation to keyword-only search
- Automatic reconnection

### Reranking Failures
- Return unranked results if reranker fails
- Log failures for monitoring
- Don't block search pipeline

## Monitoring & Metrics

### Prometheus Metrics
- `rag_ingestion_duration_seconds`
- `rag_search_duration_seconds`
- `rag_rerank_duration_seconds`
- `rag_documents_total{collection}`
- `rag_chunks_total{collection}`
- `rag_search_requests_total`

### Health Checks
- Embedding model availability
- Qdrant connection status
- Reranker model availability

## Security

### Document Validation
- Max document size: 10MB
- Supported formats: txt, md, pdf
- Content sanitization

### Access Control
- Collection-level isolation
- API key authentication (future)

## Testing Strategy

### Unit Tests
- Embedding model accuracy
- Chunking logic
- Search result ranking

### Integration Tests
- End-to-end ingestion
- Search accuracy benchmarks
- Performance targets

### Evaluation
- Precision@K
- Recall@K
- MRR (Mean Reciprocal Rank)
- User satisfaction metrics

## Deployment

### Requirements
- Python 3.13+
- CUDA 12+ (for GPU acceleration)
- Qdrant running
- 4GB+ RAM for models

### Installation
```bash
pip install sentence-transformers qdrant-client fastapi
```

## Sources
- [MTEB Leaderboard](https://huggingface.co/spaces/mteb/leaderboard)
- [BGE-M3 Paper](https://huggingface.co/BAAI/bge-m3)
- [Qdrant Documentation](https://qdrant.tech/documentation/)
- [Hybrid Search Best Practices](https://qdrant.tech/articles/hybrid_search/)
- [RAG Chunking Guide](https://github.com/FullStackRetrieval-com/Retrieval-based-language-model-Retrieval-Augmented-Generation)
