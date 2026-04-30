# Action Plan: Complete $0 AI Infrastructure Deployment

**Created:** 2026-04-30 | **Deadline:** May 8, 2026 (8 days) | **Status:** 85% Complete

---

## Executive Summary

**Current State:**
- ✅ Gateway operational with cloud fallback (local → NIM → OpenRouter)
- ✅ 29 cloud models discovered from 14 providers
- ✅ Qdrant collection created (empty, ready for indexing)
- ✅ Middleware pipeline active (RAG + Knowledge Fabric)
- ⚠️ 3090 llama server deferred (K8s hostPath complexity)
- ⚠️ Tools still pointing to Z.AI (expires May 8)

**Critical Path:** Point all tools at gateway + remove Z.AI hardcoding before May 8.

---

## Issue Tracker

### 1. Tools Not Routing Through Gateway

**Problem:** Hermes, Claude Code, OpenCode still use Z.AI directly.

**Impact:** All tools break on May 8 when Z.AI key expires.

**Solution:**
| Tool | Current Config | Target Config | Effort |
|------|---------------|---------------|--------|
| **Hermes** | `provider: zai` | `provider: custom, base_url: http://10.15.67.242:8080/v1` | Low |
| **Claude Code** | `ANTHROPIC_BASE_URL: https://api.anthropic.com` (via Z.AI proxy) | `ANTHROPIC_BASE_URL: http://10.15.67.242:8080/anthropic` | Medium |
| **OpenCode** | Mixed gateway/Z.AI | Full gateway routing | Low |
| **OMP** | Empty config | Gateway routing | Medium |

**Action Items:**
- [ ] **1.1** Add Anthropic-compatible endpoint to gateway (`/v1/anthropic/messages`)
- [ ] **1.2** Update Hermes config (`~/.hermes/config.yaml`)
- [ ] **1.3** Update Claude Code settings (`~/.claude-code/config.json` or env)
- [ ] **1.4** Update OpenCode model config
- [ ] **1.5** Configure OMP (create `~/.pi/agent/config.json`)

**Owner:** @j_kro | **Priority:** P0 | **ETA:** 2 days

---

### 2. Z.AI Hardcoded in Router Fallback Logic

**Problem:** `router.py` line ~890 has hardcoded Z.AI failover instead of using `BACKEND_FALLBACK_URLS`.

**Location:** `/data/projects/own/ai-inference-gateway/src/router.py`

**Current Code:**
```python
if not local_backend_healthy:
    logger.info("Local backend (llama-cpp) is down, auto-failing over to ZAI")
    zai_models = [m for m in self.models.values() if m.backend == "zai"]
    # ...
```

**Required Change:**
- Remove hardcoded Z.AI references
- Use `BACKEND_FALLBACK_URLS` from config (already supports NIM + OpenRouter)
- Update failover logic to try: local → NIM → OpenRouter (no Z.AI)

**Action Items:**
- [ ] **2.1** Modify `router.py` `route()` method to remove Z.AI special case
- [ ] **2.2** Update `cloud_discovery.py` to not prioritize Z.AI models
- [ ] **2.3** Test failover: kill local backend → verify NIM/OpenRouter takeover
- [ ] **2.4** Remove `zai-api-key` secret from K8s (after May 8)

**Owner:** @j_kro | **Priority:** P0 | **ETA:** 1 day

---

### 3. 3090 Llama Server Not Running

**Problem:** Qwen3.6-35B-A3B (MoE) not deployed. 21GB VRAM idle on RTX 3090.

**Root Cause:** K8s hostPath volumes require nix-csi scratch pattern; manual deployment failed due to memory limits + missing Nix paths.

**Options:**

**Option A: K8s Deployment (Recommended)**
- Use existing `llama-server-zephyr-3090-moe` deployment from `llama-servers.nix`
- Fix: reduce memory limit to 16Gi (cluster max)
- Use nix-csi scratch image with proper Nix mount paths
- Model: Qwen3.6-27B-Q4_K_M.gguf (smaller, fits in memory)

**Option B: Systemd Service (Fallback)**
- Create systemd service on zephyr
- Direct llama-server binary from Nix store
- Simpler, no K8s complexity

**Action Items:**
- [ ] **3.1** Choose approach (A or B)
- [ ] **3.2A** If K8s: patch `llama-servers.nix` with 16Gi limit + correct image
- [ ] **3.2B** If systemd: create service definition in `hosts/zephyr/services.nix`
- [ ] **3.3** Deploy and test: `curl http://zephyr:1237/health`
- [ ] **3.4** Add to gateway BACKEND_FALLBACK_URLS as primary (35B > 9B)

**Owner:** @j_kro | **Priority:** P1 | **ETA:** 1-2 days

---

### 4. Qdrant Empty (No Knowledge Indexed)

**Problem:** `knowledge-base` collection exists but has 0 documents. RAG/Knowledge Fabric have nothing to retrieve.

**Impact:** RAG injection returns empty context; Knowledge Fabric falls back to web search only.

**Solution:** Index documents into Qdrant.

**Ingestion Methods:**
1. **Knowledge Fabric API** (`10.6.31.109:3000`) - has TypeScript CLI
2. **Gateway RAG endpoint** - if it has ingestion API
3. **Direct Qdrant upsert** - manual vector embedding

**Action Items:**
- [ ] **4.1** Check knowledge-fabric CLI: `cd /data/projects/own/knowledge-fabric && nix develop && npm run ingest --help`
- [ ] **4.2** Identify source documents: `~/brain/wiki/*.md`, `/etc/nixos/**/*.md`
- [ ] **4.3** Run ingestion pipeline
- [ ] **4.4** Verify: `curl http://10.5.93.32:6333/collections/knowledge-base/points/count`
- [ ] **4.5** Test RAG: query should return local results + web results (RRF fusion)

**Owner:** @j_kro | **Priority:** P2 | **ETA:** 2 days

---

### 5. Gateway Logging Not Working

**Problem:** Gateway pod produces 0 log lines. Cannot verify middleware initialization at runtime.

**Impact:** Blind to middleware failures, circuit breaker state, RAG retrieval stats.

**Root Cause:** Uvicorn in scratch container may not be writing to stdout/stderr, or K8s not capturing.

**Action Items:**
- [ ] **5.1** Check deployment: `kubectl get deploy ai-inference-gateway -o yaml | grep -A5 log`
- [ ] **5.2** Verify `--log-level info` flag is present
- [ ] **5.3** Check if PYTHONUNBUFFERED=1 is set
- [ ] **5.4** Try: `kubectl logs -f deploy/ai-inference-gateway -n ai-inference --tail=100`
- [ ] **5.5** If still no logs: add `logging.basicConfig(level=INFO)` to main.py

**Owner:** @j_kro | **Priority:** P3 | **ETA:** 0.5 days

---

### 6. Full Fallback Testing Not Done

**Problem:** Haven't verified end-to-end failover: local down → cloud takeover.

**Test Plan:**
1. **Baseline:** All requests go to local (zephyr-3060ti:1236)
2. **Failover Test 1:** Scale down local deployment → verify requests route to sentry:1235
3. **Failover Test 2:** Scale down sentry → verify requests route to OpenRouter/NIM
4. **Recovery:** Scale up local → verify traffic returns

**Action Items:**
- [ ] **6.1** Record baseline latency (local)
- [ ] **6.2** `kubectl scale deployment llama-server-zephyr-3060ti --replicas=0`
- [ ] **6.3** Verify gateway switches to sentry:1235 (check `/health` backend URL)
- [ ] **6.4** Test query latency (should increase but succeed)
- [ ] **6.5** `kubectl scale deployment llama-server-sentry --replicas=0`
- [ ] **6.6** Verify gateway switches to OpenRouter/NIM
- [ ] **6.7** Test cloud model query (e.g., `nvidia/nemotron-49b`)
- [ ] **6.8** Restore: `kubectl scale deployment llama-server-zephyr-3060ti --replicas=1`
- [ ] **6.9** Verify traffic returns to local

**Owner:** @j_kro | **Priority:** P1 | **ETA:** 0.5 days

---

## Timeline

| Date | Milestone |
|------|-----------|
| **Apr 30 (Today)** | Gateway cloud fallback operational ✅ |
| **May 1-2** | Tool config updates (Hermes, Claude Code, OpenCode, OMP) |
| **May 3** | Remove Z.AI hardcode from router.py |
| **May 4** | 3090 deployment (if pursuing) |
| **May 5** | Knowledge ingestion into Qdrant |
| **May 6** | Full fallback testing + validation |
| **May 7** | Buffer / contingency |
| **May 8** | **Z.AI expires** - all tools must be on gateway |

---

## Success Criteria

- [ ] All tools route through gateway (no direct Z.AI calls)
- [ ] Local models primary (9B + optional 35B)
- [ ] Cloud fallback via NIM + OpenRouter works
- [ ] Claude Code operational (Anthropic endpoint or OpenAI mode)
- [ ] Hermes operational through gateway
- [ ] OpenCode/OMP operational through gateway
- [ ] RAG returns local knowledge (Qdrant populated)
- [ ] Knowledge Fabric returns fused results (local + web)
- [ ] Fallback chain tested: local → sentry → cloud
- [ ] Zero cost ($0.00) verified via gateway cost tracker

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Z.AI expires before migration complete | High | Keep Z.AI key active until May 8; test with `ZAI_API_KEY` unset |
| OpenRouter free tier rate-limited | Medium | NIM is primary cloud fallback; OpenRouter secondary |
| 3090 deployment fails | Low | 9B model on 3060ti is sufficient; 35B is nice-to-have |
| Qdrant ingestion fails | Medium | Web search fallback still works; RAG degrades gracefully |
| Claude Code has no Anthropic endpoint | High | Use Claude Code Router (port 3456) as shim, or switch to OpenAI mode |

---

## Next Steps (Immediate)

1. **Today:** Update tool configurations (Hermes, Claude Code)
2. **Tomorrow:** Remove Z.AI hardcode from router.py
3. **Day 3:** Full fallback testing
4. **Day 4-5:** Knowledge ingestion + 3090 deployment (if time permits)

---

**Status:** Ready for execution. All infrastructure in place; remaining work is configuration and testing.
