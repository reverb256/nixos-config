---
name: ai-gateway-config
description: Configure and manage the AI Inference Gateway with routing and backends
version: 1.0.0
author: j_kro
license: MIT
metadata:
  hermes:
    tags: [AI, Gateway, LM-Studio, Configuration]
---

# AI Inference Gateway Configuration

The AI Gateway provides OpenAI-compatible API with intelligent routing.

## Architecture

```
Request -> Gateway -> Backend Selection -> LM Studio | ZAI | Pollinations
                  |
                  v
              Knowledge Fabric
              (RAG + Semantic Search)
```

## Configuration Location

```nix
modules/services/ai-inference/default.nix
```

## Backend Priority

1. **LM Studio** (local, port 1234) - Primary
2. **ZAI** (cloud, coding plan) - Fallback
3. **Pollinations** (free tier) - Fallback

## Model Routing

By token count:
- 0-128K tokens: `qwen3.5-35b-a3b`
- 128K+ tokens: `qwen3.5-27b`

## Adding New Models

Edit the `models` section in `default.nix`:

```nix
models."my-model" = {
  name = "My Custom Model";
};
```

## Testing

```bash
# Check gateway health
curl http://localhost:8080/health

# List available models
curl http://localhost:8080/v1/models

# Test inference
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.5-35b-a3b","messages":[{"role":"user","content":"Hello"}]}'
```

## RAG Integration

Knowledge Fabric with:
- Qdrant vector database (port 6333)
- Semantic search with sentence-transformers
- Hybrid search (vector + BM25)
- MCP broker for tool integration

## Related Skills
- cluster-management: Multi-host operations
- k8s-migration: Future container deployment
