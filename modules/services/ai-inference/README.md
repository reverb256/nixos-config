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
| **Enhanced Intelligent Router** | Model specialization, latency-aware routing, and reranking |
| **Model Specialization** | Automatic detection of coding, agentic, fast, and large-context tasks |
| **Latency-Aware Routing** | Tracks response times and routes around overloaded models |
| **Reranking** | Ranks multiple model candidates based on task type, urgency, and performance |
| **Circuit Breaker** | Prevents cascading failures, automatic recovery |
| **Security Proxy** | Rate limiting, input sanitization, size limits |
| **RAG Engine** | Hybrid vector + BM25 search with token-scoped knowledge bases |
| **MCP Broker** | Aggregate tools from multiple MCP servers |
| **Metrics** | Prometheus export for monitoring |
| **Modular Middleware Pipeline** | Extensible middleware architecture with observability, security, rate limiting, circuit breaker, and load balancing |

## Implemented Features

### Core Features
- [x] OpenAI-compatible `/v1/chat/completions` endpoint
- [x] Streaming responses
- [x] Intelligent routing with model specialization
- [x] ZAI fallback with automatic failover
- [x] Circuit breaker for backend protection
- [x] Prometheus metrics at `/metrics`
- [x] Health check at `/health` (with actual backend health status)
- [x] Model listing at `/v1/models`
- [x] Anthropic Messages API compatibility (`/v1/messages`)
- [x] Modular middleware pipeline (observability, security, rate limiting, circuit breaker)

### Not Implemented (Needs Implementation)
- [ ] RAG endpoints (use LM Studio RAG directly for now)
- [ ] MCP broker (planned for future release)
- [ ] Reranker integration (removed - unused dead code)

## Known Limitations

- **No RAG endpoints**: RAG is handled directly by LM Studio (can be added later if needed)
- **Backend health**: Cached with 30-second TTL, not real-time (prevents excessive health checks)
- **Processing time tracking**: Currently returns 0ms (will be fixed in Phase 2)
- **MCP broker**: Not yet implemented (use MCP directly with clients for now)

## Middleware Architecture

The gateway v2 features a modular middleware pipeline that provides a clean, extensible architecture for request processing. Each middleware component can be independently enabled, configured, and monitored.

### Pipeline Overview

```
Incoming Request
       │
       ▼
┌─────────────────────────────────────────────────────────┐
│  1. Observability Middleware                            │
│  - Generates/preserves X-Request-ID for tracing        │
│  - Records start time for latency tracking             │
│  - Adds gateway_metadata to responses                  │
└──────────────┬──────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────┐
│  2. Security Filter Middleware                          │
│  - Request size validation (max 10MB default)          │
│  - PII redaction (optional)                            │
│  - Input sanitization                                  │
│  - Blocks malicious requests                           │
└──────────────┬──────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────┐
│  3. Rate Limiter Middleware                             │
│  - Token-based rate limiting (TPM/TPH/TPD)             │
│  - Request-based rate limiting (RPM)                   │
│  - Redis or in-memory backend                          │
│  - Configurable limits per API key                     │
└──────────────┬──────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────┐
│  4. Circuit Breaker Middleware                          │
│  - Prevents cascading failures                         │
│  - Automatic failover on failures                      │
│  - Health monitoring with auto-recovery                │
│  - Configurable thresholds and timeouts                │
└──────────────┬──────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────┐
│  5. Load Balancer Middleware (Optional)                 │
│  - Weighted round-robin backend selection              │
│  - Periodic health checks                              │
│  - Connection limits per backend                       │
│  - Automatic failover to healthy backends              │
└──────────────┬──────────────────────────────────────────┘
               │
               ▼
         Router & Backend
```

### Middleware Configuration

All middleware is configured via environment variables or NixOS configuration:

#### Observability

```nix
services.ai-inference.gateway.middleware.observability = {
  enable = true;  # Default: true
  structuredLogging = true;  # Default: true
  requestIdHeader = "X-Request-ID";  # Default
};
```

**Environment Variables:**
- `OBSERVABILITY_ENABLED=true|false`
- `STRUCTURED_LOGGING=true|false`

#### Security Filter

```nix
services.ai-inference.gateway.middleware.security = {
  enable = true;  # Default: true
  piiRedaction = true;  # Default: true
  maxRequestSize = 10485760;  # 10MB default
};
```

**Environment Variables:**
- `SECURITY_ENABLED=true|false`
- `PII_REDACTION=true|false`
- `MAX_REQUEST_SIZE=10485760`

#### Rate Limiter

```nix
services.ai-inference.gateway.middleware.rateLimiting = {
  enable = false;  # Default: false
  backend = "memory";  # "redis" or "memory"
  tokensPerMinute = 10000;
  tokensPerHour = 50000;
  tokensPerDay = 500000;
  rpm = 60;  # Legacy request-based limit
};
```

**Environment Variables:**
- `RATE_LIMIT_ENABLED=true|false`
- `RATE_LIMIT_BACKEND=redis|memory`
- `RATE_LIMIT_TPM=10000`
- `RATE_LIMIT_TPH=50000`
- `RATE_LIMIT_TPD=500000`
- `RATE_LIMIT_RPM=60`

#### Circuit Breaker

```nix
services.ai-inference.gateway.middleware.circuitBreaker = {
  enable = true;  # Default: true
  failureThreshold = 5;  # Failures before opening
  successThreshold = 2;  # Successes to close
  timeoutSeconds = 60;  # Seconds before attempting recovery
  healthCheckInterval = 10;  # Seconds between checks
};
```

**Environment Variables:**
- `CIRCUIT_BREAKER_ENABLED=true|false`
- `CIRCUIT_FAILURE_THRESHOLD=5`
- `CIRCUIT_TIMEOUT=60`

#### Load Balancer

```nix
services.ai-inference.gateway.middleware.loadBalancer = {
  enable = false;  # Default: false (single backend)
  # Backends configured via main gateway.backend.url
};
```

For multiple backends, configure in the gateway service:

```nix
services.ai-inference.gateway = {
  enable = true;
  backends = [
    {
      name = "backend1";
      url = "http://127.0.0.1:1234";
      weight = 100;
      maxConcurrentRequests = 100;
    }
    {
      name = "backend2";
      url = "http://127.0.0.1:1235";
      weight = 200;  # Gets 2x traffic
      maxConcurrentRequests = 50;
    }
  ];
};
```

### Metrics and Monitoring

All middleware components integrate with Prometheus metrics:

**Available Metrics:**
- `gateway_http_requests_total` - Total HTTP requests (by method, endpoint, status)
- `gateway_http_request_duration_seconds` - Request latency histogram
- `gateway_middleware_duration_seconds` - Middleware processing time
- `gateway_rate_limit_denied_total` - Rate limit denials (by type)
- `gateway_security_blocked_total` - Security blocks (by reason)
- `gateway_circuit_breaker_state` - Circuit breaker state (0=closed, 1=open, 2=half_open)
- `gateway_backend_health` - Backend health status
- `gateway_load_balancer_selections_total` - Backend selection count

**Access Metrics:**
```bash
curl http://127.0.0.1:8080/metrics
```

### Testing Guide

#### Test Middleware Functionality

```bash
# Test full middleware pipeline
./test-all.sh

# Test specific components
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: test-123" \
  -d '{
    "model": "qwen3.5-4b",
    "messages": [{"role": "user", "content": "Hello!"}]
  }' | jq '.gateway_metadata'
```

Expected response includes:
```json
{
  "gateway_metadata": {
    "request_id": "test-123",
    "processing_time_ms": 45.23,
    "load_balancer": {
      "backend_name": "backend1",
      "backend_latency_ms": 42.1
    }
  }
}
```

#### Test Rate Limiting

```bash
# Enable rate limiting
export RATE_LIMIT_ENABLED=true
export RATE_LIMIT_TPM=100

# Send requests until limited
for i in {1..150}; do
  curl -s -X POST http://127.0.0.1:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"qwen3.5-4b","messages":[{"role":"user","content":"Hi"}]}' \
    | jq -r '.error // "success"'
done
```

#### Test Circuit Breaker

```bash
# Configure circuit breaker with low threshold
export CIRCUIT_FAILURE_THRESHOLD=2
export CIRCUIT_TIMEOUT=30

# Trigger circuit breaker with failing requests
# (Requires backend to be down or returning errors)
```

#### Test Security Filter

```bash
# Test request size limit
export MAX_REQUEST_SIZE=100

curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "$(python3 -c 'print("{\"model\":\"qwen3.5-4b\",\"messages\":[{\"role\":\"user\",\"content\":\"" + "x"*1000 + "\"}]}')") \
  | jq '.error'
```

### Troubleshooting

#### Middleware Not Processing Requests

**Problem:** Requests bypass middleware entirely.

**Solution:**
1. Check middleware is enabled in config
2. Verify middleware appears in gateway startup logs
3. Check for import errors in gateway logs

```bash
journalctl -u ai-inference-gateway -n 50 | grep middleware
```

#### Rate Limiter Not Enforcing Limits

**Problem:** Rate limits not being applied.

**Solution:**
1. Verify `RATE_LIMIT_ENABLED=true`
2. Check Redis connection if using Redis backend
3. Verify token counting in metrics: `curl http://127.0.0.1:8080/metrics | grep rate_limit`

#### Circuit Breaker Stuck Open

**Problem:** Circuit breaker remains open after backend recovers.

**Solution:**
1. Check `CIRCUIT_TIMEOUT` setting (default 60s)
2. Manually reset by restarting gateway
3. Adjust `CIRCUIT_FAILURE_THRESHOLD` if too sensitive

```bash
# Check circuit breaker state
curl http://127.0.0.1:8080/metrics | grep circuit_breaker_state
```

#### Load Balancer Not Distributing

**Problem:** All requests go to single backend.

**Solution:**
1. Verify multiple backends configured
2. Check backend health status
3. Review backend weights in configuration

```bash
# Check backend selection distribution
curl http://127.0.0.1:8080/metrics | grep load_balancer_selections
```

#### High Middleware Latency

**Problem:** Gateway adding significant latency.

**Solution:**
1. Check metrics for slow middleware: `curl http://127.0.0.1:8080/metrics | grep middleware_duration`
2. Disable unnecessary middleware
3. Optimize middleware configuration (e.g., reduce circuit breaker health check interval)

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

RAG functionality is available through LM Studio directly. The gateway does not currently implement RAG endpoints.

### RAG Configuration

To use RAG, enable it directly in LM Studio or use LM Studio's built-in RAG features.

```nix
services.ai-inference = {
  enable = true;
  backend = {
    url = "http://127.0.0.1:1234";
    type = "lm-studio";
  };
};
```

### Using RAG

Use LM Studio's RAG features directly, or implement RAG at the application level.

## Enhanced Intelligent Routing

The gateway v2 includes an enhanced routing system with model specialization, latency-aware routing, and reranking capabilities.

### Model Specialization

The router automatically detects task types and routes to the most appropriate model:

| Task Type | Detection Patterns | Primary Models | Fallback Models |
|-----------|-------------------|----------------|-----------------|
| **Coding** | Code blocks, `def`, `class`, `function`, `import` | GLM-4.7 (ZAI), Magnum Opus 35B | GLM-5 |
| **Agentic** | "agent", "workflow", "multi-step", "plan", "execute" | GLM-5 (ZAI) | Magnum Opus 35B |
| **Large Context** | >200K tokens, long documents | Magnum Opus 35B (256K) | GLM-5 (200K) |
| **Fast** | "quickly", "asap", "simple", "brief" | GLM-4.5-Air (ZAI) | Local small models |
| **General** | Default | Magnum Opus 35B, GLM-5 | Any available model |

### Latency-Aware Routing

The gateway tracks response times for each model and automatically routes around overloaded models:

- **Latency Tracking**: Records response times for the last 100 requests per model
- **Overload Detection**: Flags models with >5 second average latency
- **Automatic Rerouting**: Routes to faster alternatives during high load
- **Urgency Awareness**: Considers user's urgency preference ("fast", "normal", "quality")

### Reranking

When multiple models could handle a request, the gateway:

1. **Generates Candidates**: Identifies all suitable models based on:
   - Context length requirements
   - Task specialization match
   - Current latency/performance
   - Cost tier

2. **Ranks Candidates**: Scores each model based on:
   - Priority and capability match
   - Specialization alignment with task type
   - Current latency (penalizes overloaded models)
   - Cost-effectiveness (considers urgency)
   - Historical performance

3. **Selects Best**: Routes to the highest-ranked model

### Routing Metadata

Every response includes routing information:

```json
{
  "gateway_routing": {
    "backend": "lm-studio",
    "backend_url": "http://127.0.0.1:1234",
    "model": "magnum-opus-35b-a3b-i1",
    "routing_reason": "Claude model 'claude-sonnet-4-20250514' mapped to magnum-opus-35b-a3b-i1 (large_context)",
    "specialization": "large_context",
    "expected_latency_ms": 1234.5,
    "estimated_tokens": 15000
  }
}
```

### Claude Model Mapping

The gateway maps Anthropic Claude models to your available models:

| Claude Model | Mapped To | Context | Backend | Specialization |
|-------------|-----------|---------|---------|----------------|
| `claude-sonnet-4-20250514` | Magnum Opus 35B A3B | 256K | LM Studio | Large Context |
| `claude-opus-4-20250514` | Magnum Opus 35B A3B | 256K | LM Studio | Large Context |
| `claude-sonnet-4` | GLM-5 | 200K | ZAI | Agentic |
| `claude-sonnet-4-20250514-simplified` | GLM-4.7 | 200K | ZAI | Coding |
| `claude-haiku-4-20250514` | GLM-4.5 Air | 128K | ZAI | Fast |

### Configuration

Routing is enabled by default:

```nix
services.ai-inference = {
  routing.enable = true;  # Default: true

  # Optional: Define custom routing rules
  routing.rules = lib.mkOption [ {
    minTokens = 0;
    maxTokens = 4096;
    model = "qwen3.5-2b";
    priority = 10;
  } ];

  # Fallback chain (order to try on failure)
  routing.fallbackChain = [ "vllm" "lm-studio" "zai" ];
};
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

### Anthropic API (Claude Code)

The gateway provides full Anthropic Messages API compatibility, enabling Claude Code to use the gateway with transparent routing to LM Studio or ZAI backends.

#### Endpoint

- `POST /v1/messages` - Anthropic Messages API endpoint

#### Model Mapping

When Claude Code requests a Claude model, the gateway automatically routes to the best available model:

| Claude Model | Mapped To | Context | Backend |
|-------------|-----------|---------|---------|
| `claude-sonnet-4-20250514` | Magnum Opus 35B A3B | 256K | LM Studio |
| `claude-opus-4-20250514` | Magnum Opus 35B A3B | 256K | LM Studio |
| `claude-sonnet-4` | GLM-5 | 200K | ZAI |
| `claude-sonnet-4-20250514-simplified` | GLM-4.7 | 200K | ZAI |
| `claude-haiku-4-20250514` | GLM-4.5 Air | 128K | ZAI |
| `claude-3-5-sonnet` | Qwen3.5-35B-A3B | Local | LM Studio |

**Primary Model:** Magnum Opus 35B A3B (256K context) for highest-tier requests

#### Features

- **Full Anthropic API Compatibility**: Accepts Anthropic request format with system prompts, tools, and streaming
- **Automatic Model Mapping**: Claude model names are mapped to available models, prioritizing Magnum Opus 35B A3B
- **Response Translation**: OpenAI backend responses are translated to Anthropic format
- **Gateway Features**: All gateway features work (routing, RAG, structured output, metrics)

#### Headers

```http
anthropic-version: 2023-06-01
x-api-key: your-api-key  # Optional, uses gateway auth if not provided
```

#### Example Request

```json
POST /v1/messages
Content-Type: application/json
anthropic-version: 2023-06-01

{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 1024,
  "messages": [
    {"role": "user", "content": "Explain NixOS in one sentence."}
  ]
}
```

#### Example Response

```json
{
  "id": "msg_013Zva2CMHLNnXjNJJKqJ2EF",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "NixOS is a Linux distribution built on the Nix package manager that provides declarative system configuration, atomic upgrades, and reliable rollbacks through purely functional package management."
    }
  ],
  "model": "claude-sonnet-4-20250514",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 14,
    "output_tokens": 32
  }
}
```

#### Extended Thinking

```json
{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 1024,
  "messages": [
    {"role": "user", "content": "Solve this complex problem..."}
  ],
  "thinking": {
    "type": "enabled",
    "budget_tokens": 1024
  }
}
```

#### System Prompt

```json
{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 1024,
  "system": "You are a helpful assistant with expertise in NixOS configuration.",
  "messages": [
    {"role": "user", "content": "How do I enable a service?"}
  ]
}
```

#### Streaming

```json
{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 1024,
  "stream": true,
  "messages": [
    {"role": "user", "content": "Tell me a story"}
  ]
}
```

#### Claude Code Configuration

Configure Claude Code to use the gateway by setting the API base URL:

```bash
# Set environment variable
export ANTHROPIC_API_KEY="dummy"  # Not used when auth.mode = "none"
export ANTHROPIC_BASE_URL="http://127.0.0.1:8080"

# Or use in claude command
claude --api-base http://127.0.0.1:8080 "Your prompt here"
```

Or configure in `~/.config/claude-code/config.json`:

```json
{
  "apiBaseUrl": "http://127.0.0.1:8080",
  "apiKey": "dummy"
}
```

## ZAI Coding Plan Integration

The gateway provides robust ZAI (Zhipu AI) integration with automatic failover, retry logic, and enterprise features. ZAI serves as a powerful fallback for models not available locally.

### ZAI Models

Your configuration includes these ZAI models with massive context windows:

| Model | Context Window | Best For |
|-------|---------------|----------|
| **GLM-5** | 200K tokens | Highest quality reasoning, complex analysis |
| **GLM-4.7** | 200K tokens | Advanced coding, technical documentation |
| **GLM-4.6** | 256K tokens | Long-form content, large codebases |
| **GLM-4.5 Air** | 128K tokens | Fast responses, cost-effective |

### Configuration

```nix
services.ai-inference = {
  backend.zai = {
    enable = true;
    apiKeyFile = "/run/agenix/zai-api-key";
    baseUrl = "https://api.z.ai/v1";  # Matches OpenCode config

    # Advanced retry configuration (optional)
    maxRetries = 3;
    retryDelay = 1.0;
    timeout = 300.0;
    enableRetry = true;
  };

  routing.fallbackChain = ["vllm" "lm-studio" "zai"];
};
```

### Automatic Fallback Behavior

```
Request arrives for model "glm-5"
    ↓
Check local models → Not found
    ↓
Route to ZAI → Use gateway's ZAI client with retry logic
    ↓
Response returned with gateway metadata
```

### ZAI-Specific Features

#### 1. Exponential Backoff Retry

Automatic retry with intelligent backoff for:
- **Rate limits (429)**: Exponential backoff: 1s → 2s → 4s → 8s
- **Server errors (5xx)**: Aggressive backoff: 1s → 1.5s → 2.25s
- **Timeouts**: Conservative backoff: 1s → 1.2s → 1.44s
- **Connection errors**: Standard backoff: 1s → 1.5s → 2.25s

#### 2. Circuit Breaker Integration

ZAI has its own circuit breaker that:
- Tracks ZAI-specific failures independently from LM Studio
- Opens after 5 consecutive failures
- Automatically recovers with half-open testing
- Prevents cascading failures

#### 3. Error Handling

ZAI-specific error codes are handled intelligently:
- **401/1001-1002**: Authentication failures (no retry, log error)
- **429/1003**: Rate limits (retry with backoff)
- **402/1004**: Insufficient balance (no retry)
- **404/1005**: Model not found (no retry)
- **500/1006**: Server errors (retry with backoff)

### Usage Examples

#### Direct ZAI Model Request

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "model": "glm-5",
    "messages": [{"role": "user", "content": "Explain quantum computing"}]
  }'
```

The gateway will:
1. Detect "glm-5" is not a local model
2. Route to ZAI automatically
3. Apply retry logic if needed
4. Return response with metadata

#### Response with ZAI Metadata

```json
{
  "choices": [{"message": {"content": "Quantum computing is..."}}],
  "usage": {"total_tokens": 150},
  "gateway_routing": {
    "backend": "zai",
    "backend_url": "https://api.z.ai/v1",
    "model": "glm-5",
    "routing_reason": "User specified model (not available locally, routing to fallback)"
  },
  "prediction_stats": {
    "time_to_first_token_seconds": 0.342,
    "tokens_per_second": 52.3
  }
}
```

### Monitoring ZAI

ZAI-specific metrics (all Prometheus compatible):

```bash
# Check ZAI health
curl http://127.0.0.1:8080/health | jq .backend

# ZAI-specific metrics
curl http://127.0.0.1:8080/metrics | grep -E "(zai|backend.*zai)"
```

**Grafana Queries:**

```promql
# ZAI request rate
sum(rate(ai_inference_requests_total{backend="https://api.z.ai/v1"}[5m]))

# ZAI success rate
sum(rate(ai_inference_requests_total{backend="https://api.z.ai/v1",status="success"}[5m])) /
sum(rate(ai_inference_requests_total{backend="https://api.z.ai/v1"}[5m]))

# ZAI circuit breaker status
ai_inference_backend_health{backend_url="https://api.z.ai/v1"}

# ZAI circuit breaker trips
rate(ai_inference_circuit_breaker_trips_total{backend_url="https://api.z.ai/v1"}[5m])
```

## OpenCode Integration

OpenCode can seamlessly use your AI gateway for both local and ZAI models with all gateway features.

### Current OpenCode Configuration

Your OpenCode config (`~/.config/opencode/opencode.json`):

```json
{
  "provider": {
    "gateway": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "{env:LM_STUDIO_API_KEY}"
      },
      "models": {
        "magnum-opus-35b-a3b-i1": {
          "name": "Magnum Opus 35B A3B",
          "limit": {"context": 262144, "output": 32000}
        }
      }
    }
  }
}
```

### Gateway Features Available in OpenCode

When OpenCode uses your gateway, it gets:

✅ **Intelligent Routing**
- Automatically routes to local LM Studio models when available
- Falls back to ZAI for large context or specific models
- Token-aware model selection

✅ **Structured Output**
- JSON mode and JSON Schema validation
- Perfect for code generation and API responses

✅ **Function Calling**
- Tool/function calling support
- Integration with MCP servers
- ZAI MCP server integration

✅ **Enhanced Statistics**
- Time to first token metrics
- Tokens per second tracking
- Detailed usage breakdown

✅ **Unified Monitoring**
- All requests tracked in Prometheus/Grafana
- Single dashboard for all backends
- Request tracing and debugging

### Recommended OpenCode Setup

For optimal experience, route ZAI models through the gateway too:

```json
{
  "provider": {
    "gateway": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "{env:LM_STUDIO_API_KEY}"
      },
      "models": {
        "magnum-opus-35b-a3b-i1": {
          "name": "Magnum Opus 35B A3B (Local)",
          "limit": {"context": 262144, "output": 32000}
        },
        "glm-5": {
          "name": "GLM-5 (ZAI Fallback)",
          "limit": {"context": 200000, "output": 32000}
        },
        "glm-4.7": {
          "name": "GLM-4.7 (ZAI Coding)",
          "limit": {"context": 200000, "output": 32000}
        }
      }
    }
  }
}
```

**Benefits of routing ZAI through the gateway:**
1. **Unified authentication** - Single API key management
2. **Retry logic** - Automatic retry on failures
3. **Rate limit handling** - Graceful backoff
4. **Circuit breaking** - Protection against ZAI outages
5. **Metrics aggregation** - All requests in one dashboard
6. **Structured output** - Consistent JSON/schema enforcement

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
