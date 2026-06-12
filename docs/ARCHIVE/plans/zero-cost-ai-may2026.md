# Plan: $0 AI Infrastructure (Post Z.AI Expiry -- May 8, 2026)

**Created:** 2026-04-29 | **Updated:** 2026-04-30 | **Deadline:** May 8, 2026
**Consolidates:** zero-cost-ai-may2026.md, action-plan-zero-cost-ai.md, PIPELINE-ZERO-COST.md

## Goal

Replace all Z.AI-dependent AI routing with a fully free stack: local models + NVIDIA NIM + Gemini Flash, all routed through the AI Inference Gateway. Maximum cost: $0/month. OpenRouter removed 2026-05-23.

---

## Verified Current State (2026-04-30 -- post-agent-work)

### Local Models (2/3 UP)
| Server | Endpoint | Model | GPU | Status |
|--------|----------|-------|-----|--------|
| Zephyr 3060 Ti | :1236 | Qwen3.5-9B-Q4_K_M | 8GB VRAM | Running |
| Sentry RX 5600 XT | :1235 | Qwen3.5-4B-Q4_K_M | 8GB VRAM (Vulkan) | Running |
| Zephyr RTX 3090 | :1237 | -- | 24GB VRAM | NOT DEPLOYED (manifest exists, model on disk, no pod) |

### Gateway (Healthy -- Nexus, 10.15.67.242:8080)
- **Health**: healthy, version 2.0.0
- **Primary**: zephyr-3060ti:1236 (Qwen3.5-9B)
- **BACKEND_FALLBACK_URLS**: sentry:1235, zephyr-3060ti:1236
  - WARNING: NIM is NOT in fallback chain.
- **ZAI in router.py**: Still present. Lines 514-515 (base URL), 637-638 (health), 987-993 (streaming offload). Commit c0998ae partially removed it.
- **Cloud discovery**: 53 models from nvidia (27), zai (6), qwen (10), pollinations (3), minimaxai (2)
  - NIM gap FIXED: qwen3-coder-480b, deepseek-v4-flash, kimi-k2, llama-3.3-70b, etc. all visible
- **K8s secrets**: zai-api-key, nvidia-api-key, hf-token
- **Anthropic endpoint**: NEW -- `/v1/messages` (main.py:1937) with streaming + thinking support
  - Has bug: injection detection disabled due to event loop error (commit 806d37b)
- **Streaming**: SSE supported
- **MCP broker**: Initialized at startup
- **Auth**: AUTH_MODE=api-key, VirtualKeyManager available but NOT configured
- **Cost tracker**: SQLite-based, per-model/agent/backend
- **Branch**: `zero-cost-ai-complete` (NOT merged to main)

### Tool Routing Status
| Tool | Config | Status |
|------|--------|--------|
| Hermes | `sentry-qwen4b` = gateway:8080/v1 | DONE -- routes through gateway |
| Claude Code | `anthropicBaseUrl` = gateway:8080/anthropic | DONE -- routes directly to gateway (bypasses CCR) |
| CCR (claude-code-router) | Still ZAI-only (glm-4.7 default) | STALE -- not reconfigured, still all ZAI |
| OpenCode | Unknown | UNKNOWN |
| OMP | Empty | NOT DONE |
| Pi pipeline | zai.ts still has ZAI in provider order | NOT DONE |

### Middleware (Config enabled, runtime PARTIALLY verified)
- Gateway logs now captured (agent summary visible in logs)
- Qdrant: STILL EMPTY (no collections, no data)
- Embedding model cache: UNVERIFIED
- All middleware config unchanged from before

### 3090 Status
- Commit b4b9e113 in nixos repo tries to enable llama-server-zephyr-3090-moe
- But NO K8s deployment or service exists -- pod never created
- Model on disk: hermes-qwen3.5-35b-a3b-Q4_K_M (20GB) and Qwen3.6-27B-Q4_K_M (16GB)

---

## Remaining Work (checked = done)

### Phase 1: Fix Observability
- [x] 1.1 Check uvicorn logging config
- [x] 1.2 PYTHONUNBUFFERED=1 set
- [x] 1.3 Gateway logs now visible
- [ ] 1.4 Document which middleware actually loaded (need detailed log check)
- [ ] 1.5 Verify SSE streaming works end-to-end
- [ ] 1.6 Verify MCP broker initializes

### Phase 2: Wire Cloud Fallback
- ~~2.1-2.3 OpenRouter removed 2026-05-23~~
- [ ] 2.4 Add NIM to BACKEND_FALLBACK_URLS (currently MISSING)
- [x] 2.5 NIM model discovery working (53 models visible)
- [ ] 2.6 Test full fallback chain: local -> sentry -> NIM
- [ ] 2.7 Set up virtual keys with budget caps per agent

### Phase 3: Deploy 3090
- [ ] 3.1 Deploy llama-server-zephyr-3090-moe pod (manifest exists, never applied)
  - K8s memory limit note: 16Gi cluster max, MoE 3B active should fit
  - Fallback: Qwen3.6-27B-Q4_K_M (16GB dense) if MoE OOMs
- [ ] 3.2 Verify pod starts, model loads, :1237 healthy
- [ ] 3.3 Make 3090 primary BACKEND_URL
- [ ] 3.4 Update fallback: 3090 -> 3060Ti -> sentry -> NIM
- [ ] 3.5 Verify mining-inference-coordinator handles GPU sharing

### Phase 4: Rewire All Tools
- [x] 4.1 Claude Code points at gateway /v1/messages (Anthropic protocol)
- [ ] 4.2 Decide: keep CCR or drop it?
  - Claude Code now points directly at gateway, bypassing CCR
  - CCR is stale (still ZAI-only). Either reconfigure or remove from path
  - If keeping CCR: add gateway + NIM providers, update router rules
  - If dropping CCR: gateway handles Anthropic protocol directly now
- [x] 4.3 Hermes config points at gateway (sentry-qwen4b provider)
- [ ] 4.4 Update OpenCode -> gateway
- [ ] 4.5 Configure OMP -> gateway
- [ ] 4.6 Update Pi pipeline zai.ts: remove ZAI from provider order and tier arrays
  - fast=[sentry,llama-cpp,nvidia-nim], quality=[llama-cpp,nvidia-nim,sentry], verify=[nvidia-nim,llama-cpp,sentry]
- [ ] 4.7 Wire Gemini Flash as last-resort fallback (agenix key exists, 15 RPM, 1M tokens/day)

### Phase 5: Fix Middleware Runtime
- [ ] 5.1 Verify embedding model cached in /var/cache/ai-inference
- [ ] 5.2 Index knowledge into Qdrant (~/brain/wiki, /etc/nixos/**/*.md, runbooks)
- [ ] 5.3 Verify RAG Injector E2E
- [ ] 5.4 Verify Knowledge Fabric sources: SearXNG, code search, brain wiki
- [ ] 5.5 Verify RRF fusion
- [ ] 5.6 Benchmark middleware latency (disable if >500ms)
- [ ] 5.7 Verify Prometheus scraping
- [ ] 5.8 Fix injection detection event loop bug (currently disabled, commit 806d37b)
- [ ] 5.9 Consider enabling Security Filter and PII Filter

### Phase 6: Remove ZAI
- [ ] 6.1 Finish removing ZAI from router.py (lines 514-515, 637-638, 987-993 still reference ZAI)
- [ ] 6.2 Remove ZAI from cloud_discovery.py prioritization
- [ ] 6.3 Remove zai-api-key K8s secret
- [ ] 6.4 Remove ZAI_API_KEY from pod env
- [ ] 6.5 Reconfigure CCR away from ZAI (or remove CCR from path entirely)
- [ ] 6.6 Verify all tools still work without ZAI

### Phase 7: Merge + Validate
- [ ] 7.1 Merge `zero-cost-ai-complete` branches to main (both ai-inference-gateway and nixos repos)
- [ ] 7.2 Full fallback chain test:
  - Local up -> verify local
  - Kill local -> verify sentry
  - Kill sentry -> verify NIM
  - Restore -> verify traffic returns
- [ ] 7.3 E2E test each tool: Hermes, Claude Code, OpenCode, OMP, Pi
- [ ] 7.4 Verify free tier sustainability (NIM credits, Gemini RPM)
- [ ] 7.5 Check cost tracker: $0.00 across all agents
- [ ] 7.6 Verify middleware adds value (RAG context present)
- [ ] 7.7 Record baseline latency

---

## Success Criteria

- [ ] All tools route through gateway (zero direct Z.AI calls)
- [ ] Local models primary (35B MoE -> 9B -> 4B)
- [ ] Cloud fallback works: local -> NIM -> Gemini
- [ ] Claude Code operational via gateway Anthropic endpoint
- [ ] Hermes operational via gateway
- [ ] OpenCode/OMP operational via gateway
- [ ] Pi pipeline routes through gateway (no ZAI)
- [ ] RAG returns local knowledge (Qdrant populated)
- [ ] Fallback chain tested end-to-end
- [ ] Zero cost ($0.00) verified
- [ ] Gateway logging operational
- [ ] Both repos merged to main
- [ ] Streaming works through full chain

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| NIM not in fallback chain | High | Phase 2.4 |
| ZAI still in router.py streaming | High | Lines 987-993 still offload to ZAI -- breaks May 8 |
| CCR stale (ZAI-only) | Medium | Decide in Phase 4.2 -- reconfigure or drop |
| Feature branches not merged | Medium | Phase 7.1 -- both repos on zero-cost-ai-complete |
| Anthropic injection detection bug | Medium | Phase 5.8 -- disabled, needs proper async fix |
| 3090 not deployed | Low | Phase 3 -- manifests exist, just needs apply |
| Qdrant empty | Medium | Phase 5 -- RAG returns nothing currently |
| Embedding model not cached | High | RAG dead without it, check in 5.1 |
| No virtual key budgets | Medium | Phase 2.7 -- no spend caps on cloud usage |
| 3090 vs mining conflict | Medium | mining-inference-coordinator exists |
| Middleware latency unknown | Medium | Benchmark in 5.6 |
| Gemini not wired | Low | Phase 4.7 -- last resort fallback |

## Out of Scope
- **Casdoor SSO/OIDC**: module exists but not enabled. Only relevant for web UI auth.
- **TLS termination**: HTTP-only on LAN. Fine for internal.
- **3090 dense variant**: -moe is primary. -dense is backup if MoE has issues.
- **LM Studio**: superseded by K8s llama-server pods.

## Superseded Documents
- `action-plan-zero-cost-ai.md` -- contained false claims. Test steps absorbed. Archived.
- `PIPELINE-ZERO-COST.md` -- predates gateway. NIM catalog, Gemini, Pi changes absorbed.
