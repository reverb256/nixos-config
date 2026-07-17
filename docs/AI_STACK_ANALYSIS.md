# AI Stack Analysis

**Date:** 2026-03-31
**Cluster:** NixOS 4-host (Zephyr, Nexus, Forge, Sentry)
**Status:** Hybrid (Kubernetes + NixOS systemd)

---

## Executive Summary

The cluster runs a sophisticated AI inference stack with:
- **Gateway v2.0**: OpenAI-compatible API with intelligent routing, circuit breaker, security, RAG
- **Backend**: ZAI (Zhipu AI) cloud API with 200K+ context models
- **Kubernetes**: Gateway, Qdrant, Redis, MCP services
- **Local Models**: Previously LM Studio (removed), now cloud-only
- **GPU Resources**: 7 GPUs across 4 nodes (5x NVIDIA, 2x AMD)

**Current State**: Gateway deployed on Kubernetes, using ZAI backend exclusively

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                      │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  ai-inference Namespace                                  │  │
│  │                                                          │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ AI Gateway (K8s Deployment)                        │  │  │
│  │  │ - Port 8080 (NodePort: 30443)                     │  │  │
│  │  │ - OpenAI / Anthropic / Ollama API endpoints       │  │  │
│  │  │ - Intelligent routing, circuit breaker             │  │  │
│  │  │ - Security, PII redaction, content moderation      │  │  │
│  │  │ - MCP broker, semantic caching                     │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                          │                               │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ Support Services                                   │  │  │
│  │  │ - Qdrant (RAG vector DB)                           │  │  │
│  │  │ - Redis (cache/state)                               │  │  │
│  │  │ - MCP Gateway Proxies (5x)                          │  │  │
│  │  │ - Knowledge Base MCP                               │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  ai-coding Namespace                                     │  │
│  │                                                          │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │  │
│  │  │ Claude Code │  │  OpenCode    │  │  Cursor IDE   │     │  │
│  │  │ (K8s)        │  │  (K8s)       │  │  (K8s)        │     │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │  ZAI Backend (Cloud)  │
                    │  - GLM-5 (200K)      │
                    │  - GLM-4.7 (200K)    │
                    │  - GLM-4.5 Air (128K) │
                    └─────────────────────┘
```

---

## Component Details

### 1. AI Gateway v2.0

**Purpose:** OpenAI-compatible API gateway with enterprise features

**Location:** Kubernetes (`ai-inference` namespace)

**Key Features:**
- ✅ OpenAI API (`/v1/chat/completions`, `/v1/models`, `/v1/embeddings`)
- ✅ Anthropic Messages API (`/v1/messages`)
- ✅ Ollama API (`/api/chat` for Spacebot)
- ✅ Intelligent routing by task type (coding, agentic, fast, large-context)
- ✅ Circuit breaker with automatic failover
- ✅ Security layer (rate limiting, PII redaction, content moderation)
- ✅ MCP broker (tool aggregation with caching)
- ✅ Semantic caching (Redis + Qdrant)
- ✅ JSON Schema mode for structured outputs
- ✅ Retry handler with exponential backoff
- ✅ Prometheus metrics (`/metrics`)

**Endpoints:**
- `GET /health` - Health check
- `GET /v1/models` - List available models
- `POST /v1/chat/completions` - OpenAI completions
- `POST /v1/messages` - Anthropic messages
- `POST /api/chat` - Ollama (Spacebot)
- `GET /metrics` - Prometheus metrics
- `GET /mcp/servers` - List MCP servers
- `GET /mcp/tools` - List available tools
- `POST /mcp/call` - Call MCP tool

**Configuration:** `modules/services/ai-inference/gateway.nix`

---

### 2. Backend: ZAI (Zhipu AI)

**Purpose:** Cloud-based LLM backend with massive context windows

**Why ZAI:**
- 200K+ token context (larger than most local models)
- Multiple model sizes for different use cases
- Enterprise-grade reliability
- No local GPU memory constraints

**Models:**
| Model | Context | Best For |
|-------|---------|----------|
| **GLM-5** | 200K | Highest quality reasoning, complex analysis |
| **GLM-4.7** | 200K | Advanced coding, technical documentation |
| **GLM-4.5 Air** | 128K | Fast responses, cost-effective |

**Configuration:** `hosts/nexus/ai-inference.nix`

---

### 3. Support Services

#### Qdrant (Vector Database)
- **Purpose:** RAG (Retrieval Augmented Generation), semantic caching
- **Port:** 6333
- **Deployment:** Kubernetes StatefulSet
- **Collections:** Semantic cache, knowledge bases

#### Redis
- **Purpose:** Caching, rate limiting state, MCP tool schemas
- **Port:** 6379 (Kubernetes service)
- **Deployment:** Kubernetes Deployment

#### MCP Gateway Proxies
- **Purpose:** Aggregate tools from multiple MCP servers
- **Count:** 5 proxy pods
- **Servers:** Knowledge Base, ZAI, and others

---

### 4. AI Coding Tools

#### Claude Code
- **Namespace:** `ai-coding`
- **Integration:** Uses Gateway via Anthropic API
- **Model Mapping:** Claude models → ZAI models
- **Purpose:** AI-powered code assistant

#### OpenCode
- **Namespace:** `ai-coding`
- **Integration:** Uses Gateway via OpenAI API
- **Purpose:** AI coding assistant with IDE integration

#### Cursor IDE
- **Namespace:** `ai-coding`
- **Integration:** Uses Gateway via OpenAI API
- **Purpose:** AI code editor

---

## Model Routing Strategy

The gateway uses intelligent routing based on task type and token requirements:

| Task Type | Detection Patterns | Primary Model |
|-----------|-------------------|---------------|
| **Coding** | Code blocks, `def`, `class`, `import` | GLM-4.7 |
| **Agentic** | "agent", "workflow", "multi-step" | GLM-5 |
| **Large Context** | >200K tokens | GLM-4.6 |
| **Fast** | "quickly", "asap", "simple" | GLM-4.5 Air |
| **General** | Default | GLM-5 |

**Claude Model Mapping:**
| Claude Model | Mapped To | Context |
|-------------|-----------|---------|
| `claude-sonnet-4-20250514` | Magnum Opus 35B A3B (if local) or GLM-5 | 256K/200K |
| `claude-opus-4-20250514` | Magnum Opus 35B A3B (if local) or GLM-5 | 256K/200K |
| `claude-haiku-4-20250514` | GLM-4.5 Air | 128K |

---

## Gateway Configuration

### Current Setup (Nexus)
```nix
{ lib, ... }: {
  services.ai-inference = {
    enable = true;
    backend = {
      type = "zai";
      zai = {
        enable = true;
        apiKeyFile = "/run/agenix/zai-api-key";
      };
    };
    gateway = {
      enable = false;  # Migrated to Kubernetes
    };
    routing = {
      enable = true;
      defaultModel = "qwen3.5-4b";
      rules = [
        { minTokens = 0; maxTokens = 4096; model = "qwen3.5-2b"; priority = 10; }
        { minTokens = 4097; maxTokens = 32768; model = "qwen3.5-4b"; priority = 20; }
        { minTokens = 32769; maxTokens = 999999; model = "qwen3.5-35b-a3b@q4_k_m"; priority = 30; }
      ];
    };
  };
}
```

---

## Known Issues

### 1. Gateway Not Accessible from Host
- **Issue:** `curl http://127.0.0.1:8080/health` fails
- **Reason:** Gateway runs on Kubernetes, not systemd
- **Workaround:** Use NodePort or service DNS: `http://10.1.1.120:8080` or `ai-inference-gateway.ai-inference.svc.cluster.local:8080`

### 2. LM Studio Removed
- **Reason:** 35B models require 22-28GB VRAM (exceeds RTX 3090 24GB)
- **Current:** ZAI cloud backend only
- **Impact:** No local inference (all requests go to cloud)

### 3. DNS Resolution Issues
- **Issue:** Pods can't resolve services across namespaces
- **Status:** Identified, not resolved
- **Workaround:** Use direct IPs (`10.1.1.120:8080`)

---

## GPU Resources

| Node | GPUs | Total VRAM | Available for AI | Status |
|------|------|-----------|------------------|--------|
| **Zephyr** | RTX 3090 + 3060 Ti | 24GB + 8GB | 0GB (gaming/mining) | Not used for AI |
| **Nexus** | RTX 3060 Ti | 8GB | 0GB (storage) | Not used for AI |
| **Forge** | 2x RTX 4060 + 2x RX 5700 XT | 16GB + 16GB | 0GB (mining) | Not used for AI |
| **Sentry** | RX 5600 XT | 8GB | 0GB (monitoring) | Not used for AI |

**Total Cluster GPU VRAM:** ~72GB (but allocated to mining/gaming, not AI)

---

## Access Patterns

### From Kubernetes Pods
```bash
# Via service DNS (if working)
curl http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/health

# Via NodePort
curl http://10.1.1.120:30443/health
```

### From Host (Zephyr/Nexus)
```bash
# Via node IP
curl http://10.1.1.120:8080/health
```

### From Claude Code
```bash
# Set environment variables
export ANTHROPIC_BASE_URL="http://10.1.1.120:8080"
export ANTHROPIC_API_KEY="dummy"

# Use Claude Code normally
claude "Explain NixOS"
```

---

## Monitoring

### Metrics Available
- `gateway_http_requests_total` - Total requests by method, endpoint, status
- `gateway_http_request_duration_seconds` - Request latency histogram
- `gateway_middleware_duration_seconds` - Middleware processing time
- `gateway_rate_limit_denied_total` - Rate limit denials
- `gateway_circuit_breaker_state` - Circuit breaker state
- `gateway_backend_health` - Backend health status

### Access Metrics
```bash
# From cluster
curl http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/metrics

# Via NodePort
curl http://10.1.1.120:30443/metrics
```

---

## Security Features

### 1. Authentication
- **Current:** `auth.mode = "none"` (no authentication)
- **Options:** API key, Tailscale ACL tags

### 2. PII Redaction
- **Enabled:** Yes (middleware.security.piiRedaction)
- **Detected:** Email, phone, SSN, credit card, IP address
- **Modes:** REDACT, HASH, MASK, REMOVE

### 3. Content Moderation
- **Enabled:** Yes (Phase 1 feature)
- **Categories:** Jailbreak, violence, self-harm, hate speech, spam
- **Strictness:** Low, Medium, High

### 4. Rate Limiting
- **Status:** Available but disabled
- **Backend:** Redis or in-memory
- **Limits:** TPM, TPH, TPD, RPM

---

## RAG (Retrieval Augmented Generation)

### Status
- **Gateway RAG endpoints:** Not implemented
- **LM Studio RAG:** Used directly (but LM Studio removed)
- **Qdrant:** Running, used for semantic caching
- **Knowledge Base:** Via MCP server integration

### Current RAG Workflow
1. Application → Gateway (with request)
2. Gateway → Qdrant (semantic search)
3. Qdrant → Gateway (vector matches)
4. Gateway → Backend (with RAG context)
5. Backend → Gateway (response)
6. Gateway → Application (augmented response)

---

## MCP (Model Context Protocol) Integration

### MCP Gateway Proxies (5x)
- Aggregate tools from multiple MCP servers
- Cache tool schemas (1-hour TTL)
- Health monitoring

### MCP Servers
- **Knowledge Base:** Documentation, codebase, internal knowledge
- **ZAI:** ZAI-specific tools and capabilities

### MCP Endpoints
- `GET /mcp/servers` - List configured MCP servers
- `GET /mcp/tools` - List available tools (cached)
- `POST /mcp/call` - Call MCP tool
- `POST /mcp/cache/invalidate` - Cache management

---

## Cost Considerations

### ZAI Pricing (Estimated)
- **GLM-5:** $0.50 per 1M input tokens, $0.50 per 1M output tokens
- **GLM-4.7:** $0.40 per 1M input tokens, $0.40 per 1M output tokens
- **GLM-4.5 Air:** $0.20 per 1M input tokens, $0.20 per 1M output tokens

### Cost Optimization
- **Semantic caching:** Reduces duplicate API calls
- **Intelligent routing:** Routes to cheapest suitable model
- **Circuit breaker:** Prevents failed requests from consuming quota

---

## Future Improvements

### Short-term
1. **Fix DNS resolution** between namespaces
2. **Build container image** for gateway (currently uses hybrid systemd+K8s)
3. **Enable rate limiting** for production use
4. **Add processing time tracking** to metrics

### Long-term
1. **Local models:** Consider smaller models that fit in GPU memory
2. **Pure Kubernetes:** Remove systemd dependency
3. **GPU allocation:** Reserve GPU resources for AI workloads
4. **Model fine-tuning:** Fine-tune models for specific use cases

---

## Troubleshooting

### Gateway not responding
```bash
# Check pod status
kubectl get pods -n ai-inference

# Check logs
kubectl logs -n ai-inference-gateway-xxx -n ai-inference

# Check service
kubectl get svc -n ai-inference

# Test from within cluster
kubectl run test -n ai-inference --image=curlimages/curl --rm -i --restart=Never -- curl -v http://ai-inference-gateway:8080/health
```

### Backend connection failed
```bash
# Check ZAI API key
cat /run/agenix/zai-api-key

# Test ZAI directly
curl https://api.z.ai/v1/models \
  -H "Authorization: Bearer $(cat /run/agenix/zai-api-key)"

# Check gateway health
curl http://10.1.1.120:8080/health | jq .backend
```

### Circuit breaker issues
```bash
# Check circuit breaker state
curl http://10.1.1.120:8080/metrics | grep circuit_breaker

# Reset by restarting gateway
kubectl rollout restart deployment ai-inference-gateway -n ai-inference
```

---

## Documentation

- **Gateway README:** `modules/services/ai-inference/README.md`
- **Migration Status:** `docs/ai-inference-status-2026-03-21.md`
- **Nexus Config:** `hosts/nexus/ai-inference.nix`
- **K8s Manifests:** `kubernetes-manifests/ai-inference/`

---

**Summary:** The AI stack is fully operational with cloud-based ZAI backend. The gateway provides a unified API for multiple AI coding tools (Claude, OpenCode, Cursor) with enterprise features like intelligent routing, caching, and security. Local inference is not currently available due to GPU memory constraints and mining priorities.
