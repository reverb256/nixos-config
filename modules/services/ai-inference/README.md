# AI Inference Service v2

OpenAI-compatible API gateway with intelligent routing, circuit breaker failover, security proxy, RAG, and MCP brokerage.

## Architecture

```
┌─────────────┐     ┌──────────────────────────────────────────┐
│   Client    │────▶│         AI Gateway v2 (Port 8080)        │
└─────────────┘     │  ┌─────────────────────────────────────┐ │
                    │  │  Security Layer                     │ │
                    │  │  - Rate limiting                    │ │
                    │  │  - Input sanitization               │ │
                    │  │  - Request size limits              │ │
                    │  └──────────────┬──────────────────────┘ │
                    │                 │                         │
                    │  ┌──────────────▼──────────────────────┐ │
                    │  │  Router & Reranker                  │ │
                    │  │  - Prompt analysis                  │ │
                    │  │  - Token estimation                 │ │
                    │  │  - Model selection by complexity    │ │
                    │  └──────────────┬──────────────────────┘ │
                    │                 │                         │
                    │  ┌──────────────▼──────────────────────┐ │
                    │  │  RAG Engine (Optional)              │ │
                    │  │  - Hybrid vector + BM25 search      │ │
                    │  │  - Token-scoped collections         │ │
                    │  │  - Auto-retrieval detection         │ │
                    │  └──────────────┬──────────────────────┘ │
                    │                 │                         │
                    │  ┌──────────────▼──────────────────────┐ │
                    │  │  Circuit Breaker                   │ │
                    │  │  - Health monitoring                │ │
                    │  │  - Automatic failover               │ │
                    │  │  - Graceful degradation             │ │
                    │  └──────────────┬──────────────────────┘ │
                    │                 │                         │
                    │  ┌──────────────▼──────────────────────┐ │
                    │  │  Backend Pool                       │ │
                    │  │  ┌─────────┬─────────┐              │ │
                    │  │  │ LM Studio │ ZAI │ ... │          │ │
                    │  │  └─────────┴─────────┘              │ │
                    │  └─────────────────────────────────────┘ │
                    │                                         │
                    │  ┌─────────────────────────────────────┐ │
                    │  │  MCP Broker                         │ │
                    │  │  - Tool aggregation                 │ │
                    │  │  - Server health monitoring         │ │
                    │  │  - Request proxying                 │ │
                    │  └─────────────────────────────────────┘ │
                    └──────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Qdrant (RAG)    │
                    │  Port 6333       │
                    └──────────────────┘
```

## Features

### Gateway v2 Capabilities

| Feature | Description |
|---------|-------------|
| **Auto Model Discovery** | Caches models from backend, refreshes every 60s |
| **Intelligent Router** | Selects model based on token count, complexity, code detection |
| **Circuit Breaker** | Prevents cascading failures, automatic recovery |
| **Security Proxy** | Rate limiting, input sanitization, size limits |
| **RAG Engine** | Hybrid vector + BM25 search with token-scoped knowledge bases |
| **MCP Broker** | Aggregate tools from multiple MCP servers |
| **Metrics** | Prometheus export for monitoring |

### Quick Start

### 1. Enable LM Studio

Install LM Studio and load your model:

```nix
# hosts/zephyr/configuration.nix
programs.lm-studio.enable = true;
```

### 2. Configure API Token (Optional)

If LM Studio requires authentication, set up the API token with agenix:

```bash
# Encrypt the token
echo -n "sk-lm-..." | /nix/store/...-age/bin/age -e -r age1p98yp8w64rdugp03332gxnz5q2vcnucn69cs5qm6s2l2u7epqfcqmu2pqe -o secrets/lm-studio-api-key.age

# Add to secrets.nix
"lm-studio-api-key.age".publicKeys = [users.j_kro];

# Configure in host
age.secrets.lm-studio-api-key = {
  file = ../../secrets/lm-studio-api-key.age;
  mode = "440";
  owner = "ai-inference";
  group = "ai-inference";
};
```

### 3. Enable the Service

```nix
# hosts/zephyr/configuration.nix
services.ai-inference = {
  enable = true;
  backend = {
    url = "http://127.0.0.1:1234";  # LM Studio default port
    type = "lm-studio";
    lmStudio.apiKeyFile = "/run/agenix/lm-studio-api-key";  # Optional
  };
  gateway = {
    enable = true;
    host = "127.0.0.1";
    port = 8080;
  };
  auth.mode = "none";  # or "api-key" for API token auth
  # Enable RAG
  rag = {
    enable = true;
    qdrant.enable = true;  # Also starts Qdrant service
  };
};
```

### 4. Test

```bash
# Check health (includes RAG status)
curl http://127.0.0.1:8080/health | jq

# List models
curl http://127.0.0.1:8080/v1/models

# Chat completion
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5-4b",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## RAG (Retrieval Augmented Generation)

### Overview

The gateway includes production-grade RAG with:
- **Hybrid Search**: Combines semantic vector search with BM25 keyword matching (5-10% recall improvement)
- **Token-Scoped Collections**: Each API key gets isolated knowledge bases for multi-tenancy
- **Auto-RAG**: Intelligently detects when to retrieve based on query analysis
- **Flexible Embedding**: Uses local sentence-transformers models (default: all-MiniLM-L6-v2)

### RAG Configuration

```nix
services.ai-inference.rag = {
  enable = true;
  qdrantUrl = "http://127.0.0.1:6333";
  embeddingModel = "sentence-transformers/all-MiniLM-L6-v2";
  chunkSize = 512;
  chunkOverlap = 50;
  topK = 5;

  # Hybrid search weights
  hybridSearch = {
    enable = true;
    vectorWeight = 0.7;
    bm25Weight = 0.3;
  };

  # Auto-detection settings
  autoRag = {
    enable = true;
    keywords = ["what", "how", "explain", "describe", "find"];
  };

  # Multi-tenancy
  tokenScopedCollections = true;
};
```

### RAG Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/rag/documents` | POST | Add a document to the knowledge base |
| `/rag/search` | POST | Search the knowledge base |
| `/rag/collections` | GET | List collections (scoped to API token) |
| `/rag/collections/{name}` | DELETE | Delete a collection |

### Adding Documents

```bash
# Add a document
curl -X POST http://127.0.0.1:8080/rag/documents \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "text": "NixOS is a Linux distribution built on the Nix package manager...",
    "doc_id": "nixos-doc",
    "collection": "docs",
    "metadata": {"source": "README", "topic": "nixos"}
  }'
```

### Using RAG in Chat Completions

RAG can be used automatically (keyword-based detection) or explicitly:

```bash
# Auto-RAG (detected by keywords like "what", "how", "explain")
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5-4b",
    "messages": [{"role": "user", "content": "What is NixOS?"}]
  }'

# Explicit RAG
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5-4b",
    "messages": [{"role": "user", "content": "Tell me about the gateway"}],
    "use_rag": true,
    "rag_collection": "docs",
    "rag_top_k": 3
  }'
```

The response includes RAG metadata:
```json
{
  "choices": [...],
  "usage": {
    "total_tokens": 150,
    "rag_sources_used": 2
  },
  "rag_metadata": {
    "enabled": true,
    "retrieval_method": "hybrid",
    "context_length": 1234
  }
}
```

### Manual Search

```bash
curl -X POST http://127.0.0.1:8080/rag/search \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "query": "How does the circuit breaker work?",
    "collection": "docs",
    "top_k": 5
  }'
```

## Configuration Options

### Backend

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `backend.url` | string | `"http://127.0.0.1:1234"` | Backend API URL |
| `backend.type` | enum | `"lm-studio"` | Backend type (lm-studio, vllm, llama-cpp, sglang, zai) |
| `backend.lmStudio.apiKey` | string | `""` | API token (plaintext, not recommended) |
| `backend.lmStudio.apiKeyFile` | path | `null` | Path to file containing API token |

### Gateway

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `gateway.enable` | bool | `true` | Enable API gateway |
| `gateway.host` | string | `"127.0.0.1"` | Listen address |
| `gateway.port` | port | `8080` | Listen port |
| `gateway.workers` | int | `4` | Uvicorn workers |

### RAG

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rag.enable` | bool | `false` | Enable RAG engine |
| `rag.qdrantUrl` | string | `"http://127.0.0.1:6333"` | Qdrant URL |
| `rag.qdrant.enable` | bool | `false` | Enable Qdrant service |
| `rag.embeddingModel` | string | `"sentence-transformers/all-MiniLM-L6-v2"` | Embedding model |
| `rag.chunkSize` | int | `512` | Document chunk size |
| `rag.topK` | int | `5` | Documents to retrieve |
| `rag.hybridSearch.enable` | bool | `true` | Enable hybrid search |
| `rag.autoRag.enable` | bool | `true` | Enable auto-detection |

### Authentication

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `auth.mode` | enum | `"none"` | Auth mode (none, tailscale, api-key) |
| `auth.tailscale.aclTags` | list | `[]` | Allowed Tailscale ACL tags |

### Monitoring

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `monitoring.enable` | bool | `true` | Enable Prometheus metrics |
| `monitoring.port` | port | `9190` | Metrics port |

## Usage

### OpenAI-Compatible Endpoints

- `GET /v1/models` - List available models
- `POST /v1/chat/completions` - Chat completions (supports streaming, RAG)
- `POST /v1/completions` - Text completions
- `POST /v1/embeddings` - Embeddings

### Monitoring

- `GET /health` - Health check (includes backend and RAG status)
- `GET /metrics` - Prometheus metrics

### Example with Python

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8080/v1",
    api_key="dummy",  # Not used when auth.mode = "none"
)

response = client.chat.completions.create(
    model="qwen3.5-4b",
    messages=[{"role": "user", "content": "Explain NixOS in one sentence."}]
)

print(response.choices[0].message.content)
```

### Example with OpenCode

OpenCode can be configured to use the local gateway. Edit `~/.config/opencode/opencode.json`:

```json
{
  "provider": {
    "gateway": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "AI Gateway v2",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "YOUR_LM_STUDIO_API_KEY"
      },
      "models": {
        "magnum-opus-35b-a3b-i1": {
          "name": "Magnum Opus 35B A3B"
        }
      }
    }
  },
  "model": "gateway/magnum-opus-35b-a3b-i1"
}
```

Then select the gateway model in OpenCode with `opencode` and choose your model.

## Why LM Studio instead of vLLM/SGLang?

The Qwen3.5-35B-A3B model requires approximately 22-28GB VRAM even with 4-bit quantization. On an RTX 3090 (24GB VRAM):

- **vLLM**: Loads entire model into VRAM → Out of memory
- **SGLang**: Similar memory requirements → Out of memory
- **LM Studio**: Uses CPU offloading and smart memory management → Works

LM Studio provides a desktop interface for managing models and includes a built-in API server that the gateway connects to.

## Troubleshooting

### Gateway can't connect to backend

Check if LM Studio is running and serving the API:
```bash
curl http://127.0.0.1:1234/v1/models
```

### Qdrant connection failed

Check if Qdrant is running:
```bash
curl http://127.0.0.1:6333/collections
journalctl -u qdrant -f
```

### RAG not retrieving documents

1. Check RAG is enabled in health endpoint: `curl http://127.0.0.1:8080/health | jq .rag`
2. Verify documents were added: `curl http://127.0.0.1:8080/rag/collections`
3. Check your API key - collections are scoped by token

### Authentication errors

If using `apiKeyFile`, verify the secret exists:
```bash
ls -l /run/agenix/lm-studio-api-key
cat /run/agenix/lm-studio-api-key
```

### View logs

```bash
# Gateway logs
journalctl -u ai-inference-gateway -f

# Qdrant logs
journalctl -u qdrant -f
```

## Migration from vLLM/SGLang

1. Remove vLLM/SGLang modules from configuration
2. Enable `programs.lm-studio.enable = true`
3. Load your model in LM Studio
4. Change `backend.type = "lm-studio"`
5. Change `backend.url = "http://127.0.0.1:1234"`
6. Rebuild and switch
