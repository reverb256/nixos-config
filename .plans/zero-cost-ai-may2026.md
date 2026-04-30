# Plan: $0 AI Infrastructure (Post Z.AI Expiry -- May 8, 2026)

**Created:** 2026-04-29 | **Updated:** 2026-04-30 | **Deadline:** May 8, 2026 (8 days)

## Goal

Replace all Z.AI-dependent AI routing with a fully free stack: local models + NVIDIA NIM free tier + OpenRouter free tier, all routed through the AI Inference Gateway.

## Verified Current State (2026-04-30)

### Local Models (2/3 UP)
| Server | Endpoint | Model | GPU | Status |
|--------|----------|-------|-----|--------|
| Zephyr 3060 Ti | :1236 | Qwen3.5-9B-Q4_K_M | 8GB VRAM | Running |
| Sentry RX 5600 XT | :1235 | Qwen3.5-4B-Q4_K_M | 8GB VRAM (Vulkan) | Running |
| Zephyr RTX 3090 | :1237 | -- | 24GB VRAM | No service exists |

### Gateway (Healthy -- running on Nexus, external IP 10.15.67.242)
- Health: http://10.15.67.242:8080/health -> healthy
- Version: 2.0.0
- Primary BACKEND_URL: zephyr-3060ti:1236 (Qwen3.5-9B)
- DEFAULT_MODEL: Qwen3.5-9B-Q4_K_M.gguf
- RFF fallback chain: BACKEND_FALLBACK_URLS = sentry:1235, zephyr-3060ti:1236 (local-only, NO cloud)
- Cloud discovery: 5 models visible -- nvidia (3x Nemotron), minimaxai (2x)
- ZAI failover: Hardcoded in router.py route(), NOT in BACKEND_FALLBACK_URLS
- K8s secrets present: zai-api-key, nvidia-api-key, hf-token (openrouter agenix exists but no K8s secret)
- Cloud keys in pod env: ZAI_API_KEY, NVIDIA_API_KEY (wired via secretKeyRef)
- OpenRouter key: agenix file exists, but NO K8s secret or env var wired

### Middleware Pipeline (Config enabled, runtime UNVERIFIED -- 0 log lines)

The gateway has a full middleware pipeline that runs on every request.
Pipeline built in build_middleware_pipeline() (main.py:902), invoked at startup line 493.
Processed via state.pipeline.process_request() at lines 1136, 1871, 2144.

| Middleware | Config | Purpose | Runtime Status |
|-----------|--------|---------|---------------|
| Observability | enabled | Request tracking | Config ok, Logs unknown |
| RAG Injector | RAG_ENABLED=true | Qdrant -> system msg injection | Config ok, Logs unknown |
| Knowledge Fabric | ENABLED=true | Multi-source RRF fusion retrieval | Config ok, Logs unknown |
| - RAG source | enabled | Qdrant hybrid search (vector+BM25) | Config ok, Qdrant EMPTY |
| - SearXNG source | enabled | Web metasearch via K8s SearXNG | Config ok, SearXNG UP |
| - Code search | enabled | Semantic code search in /etc/nixos | Config ok |
| - Brain wiki | enabled | ~/brain/wiki filesystem | Config ok |
| - Web search | via fabric | MCP web search | Config ok |
| Security Filter | SECURITY_PROXY_ENABLED=false | DISABLED | Off |
| Rate Limiter | 120 RPM, enabled | Per-IP | Config ok |
| Concurrency Limiter | enabled | Max concurrent requests | Config ok |
| Circuit Breaker | CIRCUIT_BREAKER_ENABLED=true | Auto-failover on backend down | Config ok |
| PII Filter | PRIVACY_FILTER_ENABLED=false | PII detection/redaction | Off |
| Audit Log | -- | Request audit trail | File exists |

**Middleware architecture:**
1. base.py -- ABC: process_request -> (bool, error) + process_response
2. Pipeline: Observability -> RAG -> Knowledge Fabric -> Security -> Rate Limit -> Concurrency -> Circuit Breaker
3. RAG Injector: Classifies queries (factual/how-to/comparison/troubleshoot/creative/conversation),
   retrieves from Qdrant, injects as system message context
4. Knowledge Fabric: Multi-source parallel retrieval with:
   - SemanticRouter classifies intent -> selects sources
   - Sources: RAG, SearXNG, CodeSearch, BrainWiki, WebSearch
   - RRF fusion merges across sources
   - ContextSynthesizer formats for LLM injection
   - Per-source circuit breakers + Prometheus metrics

**Dependencies:**
- Qdrant: healthy, collections=[] (EMPTY)
- SearXNG: running in K8s, HTTP 200
- Redis: PONG
- Knowledge Fabric API: http://10.6.31.109:3000 -> healthy
- Privacy Filter svc: exists but disabled

### External Free Providers
| Provider | Agenix | K8s Secret | Pod Env | Discovery | Proxy |
|----------|--------|-----------|---------|-----------|-------|
| NVIDIA NIM | yes | yes | yes | yes (3 models) | No |
| OpenRouter | yes | NO | NO | NO | NO |
| Z.AI | yes | yes | yes | yes (hardcoded) | Hardcoded |

### Tool -> Provider Routing
| Tool | Routes To | Post-May-8 |
|------|-----------|------------|
| Hermes | Z.AI | Breaks |
| Claude Code | Z.AI | Breaks |
| Claude Code Router | :3456 | Running |
| OpenCode | Gateway + Z.AI | Cloud breaks |
| OMP | Empty | Not working |

## Plan

### Phase 1: Fix Observability (Day 1) -- PREREQUISITE
- [ ] 1.1 Check gateway pod stdout/stderr capture (uvicorn logging config)
- [ ] 1.2 Ensure PYTHONUNBUFFERED=1 is set (already in ConfigMap)
- [ ] 1.3 Verify middleware pipeline init appears in pod logs after restart
- [ ] 1.4 Document which middleware actually loaded vs just configured

### Phase 2: Wire Cloud Keys + Fallback (Day 1-2)
- [ ] 2.1 Create OpenRouter K8s secret (decrypt from agenix)
- [ ] 2.2 Wire OPENROUTER_API_KEY into gateway pod env via secretKeyRef
- [ ] 2.3 Add cloud URLs to BACKEND_FALLBACK_URLS (NIM, OpenRouter)
- [ ] 2.4 Verify cloud discovery shows openrouter/* models in /v1/models
- [ ] 2.5 Test cloud fallback: kill local llama -> verify request goes to NIM

### Phase 3: Bring Up 3090 (Day 2)
- [ ] 3.1 Create llama-server-zephyr-3090 (systemd + K8s deploy)
- [ ] 3.2 Model: Qwen3.6-35B-A3B, CUDA_VISIBLE_DEVICES=0, port 1237
- [ ] 3.3 Make 3090 primary BACKEND_URL
- [ ] 3.4 Current 3060Ti becomes first fallback

### Phase 4: Gateway as Universal Proxy (Day 2-3)
- [ ] 4.1 Verify OpenAI compat for Hermes/OpenCode
- [ ] 4.2 Reconfigure CCR to point at gateway (not ZAI)
  - Edit `/var/lib/claude-code-router/config.json` or make it declarative in `modules/services/claude-code-router.nix`
  - Add gateway provider: `http://10.15.67.242:8080/v1/chat/completions`
  - Add NIM provider: `https://integrate.api.nvidia.com/v1/chat/completions`
  - Router rules: default → gateway local model, think → NIM large model
  - CCR handles Anthropic→OpenAI translation, no gateway code change needed
- [ ] 4.3 Point Claude Code at CCR: `ANTHROPIC_BASE_URL=http://localhost:3456/anthropic`
  - Full path: `Claude Code → CCR:3456 (Anthropic protocol) → Gateway:8080 (OpenAI protocol) → local/NIM/OpenRouter`
- [ ] 4.4 Update Hermes config -> gateway base_url
  ```yaml
  model:
    provider: custom
    base_url: http://10.15.67.242:8080/v1
    default: Qwen3.5-9B-Q4_K_M.gguf
  ```
- [ ] 4.5 Update OpenCode/OMP to use gateway for cloud models

### Phase 5: Fix Middleware Runtime (Day 3-4)
- [ ] 5.1 Index knowledge into Qdrant (cluster docs, brain wiki, runbooks)
- [ ] 5.2 Verify RAG Injector end-to-end (query -> Qdrant -> system msg injection)
- [ ] 5.3 Verify Knowledge Fabric sources: SearXNG, code search, brain wiki
- [ ] 5.4 Verify RRF fusion produces meaningful context
- [ ] 5.5 Consider enabling Security Filter and PII Filter
- [ ] 5.6 Benchmark: request with vs without middleware (latency impact)

### Phase 6: Remove ZAI (Day 5-7)
- [ ] 6.1 Remove ZAI from gateway (key + hardcoded failover in router.py)
- [ ] 6.2 Remove ZAI K8s secret
- [ ] 6.3-6.4 Update all tools to gateway-only

### Phase 7: Validation (Day 7-8)
- [ ] 7.1 E2E test each tool through gateway
- [ ] 7.2 Verify free tier sustainability (NIM rate limits, OpenRouter credits)
- [ ] 7.3 Monitor health, circuit breaker, cost tracker
- [ ] 7.4 Verify middleware adds value (RAG context improves responses)

## Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| Gateway 0 logs | High | Phase 1 fixes logging first |
| Qdrant empty | Medium | Phase 5 indexes knowledge |
| Router hardcodes ZAI | Medium | Code change in route() |
| No Anthropic endpoint | High | CCR shim exists |
| OpenRouter free tier restrictive | Medium | NIM is primary cloud |
| Middleware latency | Medium | Benchmark in 5.6 |
| KF circuit breakers hide failures | Low | Check per-source metrics |
