# Plan: $0 AI Infrastructure (Post Z.AI Expiry — May 8, 2026)

**Created:** 2026-04-29 | **Updated:** 2026-04-30 | **Deadline:** May 8, 2026 (8 days)

## Goal

Replace all Z.AI-dependent AI routing with a fully free stack: local models + NVIDIA NIM free tier + OpenRouter free tier, all routed through the AI Inference Gateway.

## Verified Current State (2026-04-30 — post-audit)

### Local Models (3/3 UP)

| Server | Endpoint | Model | GPU | Status |
|--------|----------|-------|-----|--------|
| Zephyr 3060 Ti | :1236 | Qwen3.5-9B-Q4_K_M | 8GB VRAM | Running |
| Sentry RX 5600 XT | :1235 | Qwen3.5-4B-Q4_K_M | 8GB VRAM (Vulkan) | Running |
| Zephyr RTX 3090 | :1237 | Qwen3.6-35B-A3B | 24GB VRAM | **Running** (K8s deploy, 1/1) |

### Gateway (Healthy — ClusterIP 10.15.67.242)

- Health: `http://10.15.67.242:8080/health` → healthy, v2.0.0
- BACKEND_URL: `llama-server-zephyr-3060ti:1236` (**should be 3090**)
- DEFAULT_MODEL: `Qwen3.6-35B-A3B-UD-IQ3_S.gguf` (**mismatch** — 3060ti serves 9B)
- BACKEND_FALLBACK_URLS: sentry:1235, zephyr-3060ti:1236, **ZAI URL still present**
- Model catalog: **20+ models** from llama-cpp (2), zai (7), nvidia (6+), pollinations (TTS/STT/vision)
- Logs: **flowing** (no longer 0 lines)
- K8s secrets: zai-api-key, nvidia-api-key, hf-token, **openrouter-api-key** (wired!)

### External Free Providers

| Provider | Agenix | K8s Secret | In Gateway | Status |
|----------|--------|-----------|------------|--------|
| NVIDIA NIM | yes | yes | yes (6+ models) | Wired |
| OpenRouter | yes | **yes** | In fallback chain | Wired |
| Gemini Flash | yes | NO | NO | Not wired |
| Z.AI | yes | yes | **Hardcoded in fallback + router.py** | Still active |

### Tool → Provider Routing (Current)

| Tool | Routes To | Post-May-8 |
|------|-----------|------------|
| Hermes | **Gateway** (sentry-qwen4b → 10.15.67.242:8080) | **Works** (already on gateway) |
| Claude Code | Z.AI (via `ANTHROPIC_BASE_URL`) | **Breaks** |
| OpenCode | Gateway + Z.AI | Cloud breaks |
| CCR (:3456) | 100% ZAI | **Dropped — will be removed** |
| hermes-webui | Via Hermes agent | Depends on Hermes |

### Active Issues

| Issue | Detail | Impact |
|-------|--------|--------|
| **3090 not reachable from gateway** | `"Failed to query llama-3090: All connection attempts failed"` in logs | 3090 unused despite running |
| **BACKEND_URL → 3060ti** | ConfigMap points to 3060ti, not 3090 | 3090 not primary |
| **ZAI in fallback chain** | `BACKEND_FALLBACK_URLS` includes `api.z.ai` | Breaks May 8 |
| **DEFAULT_MODEL mismatch** | ConfigMap: `Qwen3.6-35B-A3B-UD-IQ3_S.gguf`, backend serves `Qwen3.5-9B` | Wrong model advertised |
| **Hermes `local-qwen35` misconfigured** | Points to `10.1.1.110:1235` (wrong host/port) | Falls back silently |
| **hermes-webui inactive** | `systemctl is-active hermes-webui` → inactive | WebUI down |
| **No Anthropic endpoint in gateway** | `claude_client.py` exists but no `/anthropic` route | Claude Code can't use gateway |

---

## Plan

### Phase 1: Fix Gateway Config + 3090 as Primary (Day 1)

- [ ] 1.1 Debug 3090 connectivity from gateway pod (K8s service vs host port)
- [ ] 1.2 Update ConfigMap: `BACKEND_URL` → `llama-server-zephyr-3090-moe:1237`
- [ ] 1.3 Update ConfigMap: `DEFAULT_MODEL` → match actual 3090 model name
- [ ] 1.4 Update ConfigMap: remove ZAI from `BACKEND_FALLBACK_URLS`, keep OpenRouter
- [ ] 1.5 Restart gateway, verify 3090 as primary, 3060ti as fallback
- [ ] 1.6 Fix Hermes `local-qwen35`: change `10.1.1.110:1235` → `10.1.1.110:1237`

### Phase 2: Claude Code Path (Day 1-2)

Gateway has `claude_client.py` with Anthropic translation logic. Need to expose it as an HTTP endpoint.

- [ ] 2.1 Add `/anthropic/v1/messages` endpoint to gateway (using existing `claude_client.py`)
  - Translates Anthropic API → OpenAI format internally
  - Claude Code → gateway `/anthropic/v1/messages` → local/NIM/OpenRouter
- [ ] 2.2 Update Claude Code: `ANTHROPIC_BASE_URL=http://10.15.67.242:8080/anthropic`
- [ ] 2.3 Test Claude Code end-to-end through gateway
- [ ] 2.4 Remove/decommission CCR (port 3456)

### Phase 3: Remove ZAI (Day 2-3)

- [ ] 3.1 Remove ZAI hardcoded failover from `router.py` `route()` method
- [ ] 3.2 Remove ZAI from `cloud_discovery.py` model prioritization
- [ ] 3.3 Remove ZAI K8s secret
- [ ] 3.4 Remove `zai-api-key` from gateway pod env
- [ ] 3.5 Remove CCR service from NixOS config
- [ ] 3.6 Test: `ZAI_API_KEY` unset → all tools still function

### Phase 4: Middleware Runtime (Day 3-4)

- [ ] 4.1 Verify embedding model cached (BidirLM-Omni-2.5B) — RAG dead without it
- [ ] 4.2 Index knowledge into Qdrant (cluster docs, brain wiki, runbooks)
- [ ] 4.3 Verify RAG Injector end-to-end (query → Qdrant → system msg injection)
- [ ] 4.4 Verify Knowledge Fabric sources: SearXNG, code search, brain wiki
- [ ] 4.5 Verify RRF fusion produces meaningful context
- [ ] 4.6 Verify Prometheus metrics scraped
- [ ] 4.7 Benchmark: request with vs without middleware (latency impact)

### Phase 5: Validation (Day 4-5)

- [ ] 5.1 E2E test each tool through gateway (Hermes, Claude Code, OpenCode)
- [ ] 5.2 Full fallback chain test:
  1. Baseline: all requests → 3090 (:1237)
  2. Kill 3090 → verify 3060ti takeover
  3. Kill 3060ti → verify sentry takeover
  4. Kill sentry → verify NIM/OpenRouter takeover
  5. Restore → verify traffic returns to 3090
- [ ] 5.3 Verify free tier sustainability (NIM rate limits, OpenRouter credits)
- [ ] 5.4 Monitor circuit breaker, cost tracker
- [ ] 5.5 Verify middleware adds value (RAG context improves responses)

### Phase 6: Cleanup (Day 5-7)

- [ ] 6.1 Restart hermes-webui, verify terminal fix
- [ ] 6.2 Fix or remove casdoor module (currently failing)
- [ ] 6.3 Consider enabling Security Filter and PII Filter
- [ ] 6.4 Gemini Flash wiring (optional — 15 RPM, 1M tokens/day free)

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Z.AI expires before Anthropic endpoint ready | High | Keep ZAI active until endpoint works |
| 3090 unreachable from gateway pod | High | Phase 1.1 — likely K8s service networking |
| Anthropic endpoint implementation | Medium | `claude_client.py` exists, just needs route |
| OpenRouter free tier restrictive | Medium | NIM is primary cloud fallback |
| Middleware latency | Medium | Benchmark in 4.7 |
| Qdrant empty | Medium | Phase 4 indexes knowledge |
| Embedding model not cached | High | RAG dead without it; check in 4.1 |

## Out of Scope

- **CCR (Claude Code Router)**: Dropped. Gateway will handle Anthropic translation directly.
- **Casdoor SSO**: Module failing, separate effort. Gateway uses API-key auth.
- **TLS termination**: Gateway is HTTP-only on LAN. Fine for internal.
- **Gemini Flash**: Nice-to-have. Key in agenix, not wired.

## Timeline

| Date | Milestone |
|------|-----------|
| **May 1** | Phase 1: Gateway fixed, 3090 primary |
| **May 2-3** | Phase 2: Anthropic endpoint, Claude Code on gateway |
| **May 3-4** | Phase 3: ZAI removed |
| **May 4-5** | Phase 4: Middleware verified |
| **May 5-6** | Phase 5: Full validation |
| **May 6-7** | Phase 6: Cleanup |
| **May 8** | **Z.AI expires** — everything must be off ZAI |

## Success Criteria

- [ ] All tools route through gateway (no direct ZAI calls)
- [ ] 3090 as primary local model (35B > 9B)
- [ ] Cloud fallback: NIM → OpenRouter works
- [ ] Claude Code operational via gateway Anthropic endpoint
- [ ] Hermes operational through gateway
- [ ] RAG returns local knowledge (Qdrant populated)
- [ ] Full fallback chain tested: 3090 → 3060ti → sentry → cloud
- [ ] Monthly cost: $0.00 verified
