# AI Inference Gateway - Improvement Roadmap

**Date**: 2026-03-04
**Status**: Draft
**Priority**: Address documentation debt and missing features

---

## 📊 Executive Summary

The gateway is **functionally solid for core use cases** but has significant gaps between documentation and implementation. This roadmap prioritizes fixing documentation accuracy, implementing critical missing features, and resolving technical debt.

**Current Status**: ✅ Production-ready for basic chat completions
**Target**: Fully-documented, feature-complete gateway

---

## 🎯 Roadmap Phases

### Phase 1: Critical Fixes (Week 1) ⚠️ **HIGH PRIORITY**

#### 1.1 Documentation Accuracy
**Issue**: README.md documents features that don't exist
**Impact**: User confusion, wasted time trying non-existent endpoints
**Effort**: 2-4 hours

**Action Items**:
- [ ] Audit README.md against actual implementation
- [ ] Remove or mark as "Planned" for:
  - [ ] RAG endpoints (`/rag/documents`, `/rag/search`, `/rag/collections`)
  - [ ] MCP broker functionality
  - [ ] Reranker in routing decisions
- [ ] Add "Implemented Features" section with checkboxes
- [ ] Create "Known Limitations" section
- [ ] Update health endpoint documentation

**Deliverable**: Accurate README.md that matches implementation

**Files**: `modules/services/ai-inference/README.md`

---

#### 1.2 Implement Actual Health Checks
**Issue**: Health endpoint always returns `healthy: true` (TODO at line 272)
**Impact**: Cannot detect backend failures proactively
**Effort**: 4-6 hours

**Action Items**:
- [ ] Implement backend health check function:
  ```python
  async def check_backend_health(url: str, timeout: float = 5.0) -> bool:
      try:
          async with httpx.AsyncClient() as client:
              response = await client.get(
                  f"{url}/v1/models",
                  timeout=timeout
              )
              return response.status_code == 200
      except:
          return False
  ```
- [ ] Cache health status (don't check on every request)
- [ ] Update health endpoint to return actual backend status
- [ ] Add circuit breaker state to health response
- [ ] Add Qdrant status if RAG is enabled

**Deliverable**: Working health checks for all backends

**Files**: `modules/services/ai-inference/ai_inference_gateway/main.py`

---

#### 1.3 Remove Production Debug Logs
**Issue**: Debug logs with `[DEBUG]` and `[ZAI DEBUG]` in production code
**Impact**: Log spam, potential information leakage
**Effort**: 1-2 hours

**Action Items**:
- [ ] Remove or gate behind `LOG_LEVEL=DEBUG`:
  - Line 649: `Forwarding User-Agent`
  - Line 651: `No User-Agent header`
  - Line 679-681: ZAI debug logs
  - Line 700-703: ZAI response debug
- [ ] Ensure all debug logs use `logger.debug()` instead of `logger.info()`

**Deliverable**: Clean production logs

**Files**: `modules/services/ai-inference/ai_inference_gateway/main.py`

---

### Phase 1.5: Multi-GPU Architecture Setup ⚡ **HIGH PRIORITY** **NEW**

**Goal**: Distribute LM Studio across 3 machines for optimal Spacebot performance
**Status**: Design Complete, Ready for Implementation
**Effort**: 7-11 hours
**Date Added**: 2026-03-05

#### Architecture Overview

```
                    AI Inference Gateway (zephyr:8080)
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
         Zephyr (32GB)      Forge (16GB)      Nexus (8GB)
         ─────────────      ─────────────      ─────────────
         3090: 24GB         4060 #1: 8GB       3060 Ti: 8GB
         3060 Ti: 8GB       4060 #2: 8GB
         Multi-GPU ✅       Multi-GPU ✅       Single GPU
         75/25 split        50/50 split
```

#### Action Items

**Configure Forge (1-2 hours):**
- [ ] Install LM Studio on forge
- [ ] Configure hardware-config.json (50/50 split)
- [ ] Download qwen3.5-9b-IQ4_NL.gguf (5.1GB)
- [ ] Configure context length (64K), KV cache quantization
- [ ] Enable API server on port 1234
- [ ] Test connectivity from zephyr

**Configure Nexus (1-2 hours):**
- [ ] Install LM Studio on nexus
- [ ] Download qwen3.5-4b-IQ4_NL.gguf (2.5GB)
- [ ] Configure context length (32K), KV cache quantization
- [ ] Enable API server on port 1234
- [ ] Test connectivity from zephyr

**Update Gateway (2-3 hours):**
- [ ] Create multi-backend NixOS module
- [ ] Implement model-to-backend mapping
- [ ] Add overflow logic for tier2/tier3 models
- [ ] Add health checks for all backends

**Testing (2-3 hours):**
- [ ] Test each Spacebot process routing
- [ ] Measure throughput (target: >1000 t/s total)
- [ ] Test overflow scenarios
- [ ] Validate failover

**Integration (1 hour):**
- [ ] Update Spacebot configuration
- [ ] End-to-end validation

#### Expected Performance

| Backend | Model | Context | Speed | Concurrent |
|---------|-------|---------|-------|------------|
| Zephyr | qwen3.5-35b-a3b | 256K | 110 t/s | 1 |
| Zephyr | qwen3.5-27b | 256K | 150 t/s | 1 |
| Forge | qwen3.5-9b | 64K | 200 t/s | 2 |
| Nexus | qwen3.5-4b | 32K | 300 t/s | 3 |
| **Total** | - | - | - | **~1500 t/s** |

#### Success Criteria

- [ ] All three LM Studio instances running
- [ ] Gateway routing configured correctly
- [ ] Cortex gets 110 t/s with 256K context
- [ ] Channels get 200 t/s with 32K context
- [ ] Compactor gets 300 t/s with 16K context
- [ ] Overflow routing works
- [ ] All Spacebot processes functional

**Documentation**: `docs/plans/2026-03-05-multi-gpu-lmstudio-architecture.md`

---

### Phase 2: Feature Completion (Week 2-3) 🔧 **MEDIUM PRIORITY**

#### 2.1 Implement Processing Time Tracking
**Issue**: `processing_time_ms` is always 0 (TODO at line 770)
**Impact**: Cannot measure actual gateway performance
**Effort**: 3-4 hours

**Action Items**:
- [ ] Add time tracking to request lifecycle:
  ```python
  start_time = time.time()
  # ... request processing ...
  processing_time_ms = (time.time() - start_time) * 1000
  ```
- [ ] Track times for:
  - [ ] Middleware processing
  - [ ] Backend request
  - [ ] Total request time
- [ ] Add to response metadata

**Deliverable**: Accurate performance metrics

**Files**: `modules/services/ai-inference/ai_inference_gateway/main.py`

---

#### 2.2 Fix Prometheus Metrics Label Conflicts
**Issue**: Metrics disabled due to label conflicts (TODO at line 1624)
**Impact**: Missing observability data
**Effort**: 4-6 hours

**Action Items**:
- [ ] Identify which metrics have label conflicts
- [ ] Fix label cardinality issues:
  - Use consistent label names
  - Limit label values (e.g., bucket model names)
  - Remove high-cardinality labels (backend URLs)
- [ ] Re-enable commented-out metrics
- [ ] Test with Prometheus

**Deliverable**: Complete metrics without conflicts

**Files**: `modules/services/ai-inference/gateway.nix`

---

#### 2.3 Reranker Integration Decision
**Issue**: Reranker initialized but never used for routing
**Impact**: Wasted resources, dead code
**Effort**: 2 hours decision, 8-16 hours if implementing

**Decision Required**:
- **Option A**: Remove reranker entirely
  - Pros: Simpler code, less memory
  - Cons: Lost future capability
- **Option B**: Integrate reranker into routing
  - Pros: Better model selection
  - Cons: More complexity, slower routing

**Action Items (if implementing)**:
- [ ] Update `Router.route()` to call reranker
- [ ] Add reranking to model candidate scoring
- [ ] Test with cross-encoder models
- [ ] Add latency metrics for reranking

**Action Items (if removing)**:
- [ ] Remove reranker initialization
- [ ] Remove reranker.py file
- [ ] Update documentation

**Deliverable**: Decision + implementation/removal

**Files**: `modules/services/ai-inference/ai_inference_gateway/router.py`, `reranker.py`, `main.py`

---

### Phase 3: Optional Features (Week 4+) 📋 **LOW PRIORITY**

#### 3.1 RAG Implementation (If Needed)
**Issue**: Documentation claims RAG support but no endpoints exist
**Impact**: Cannot use retrieval-augmented generation
**Effort**: 16-24 hours

**Decision Required**: Do you need RAG?

**If Yes**:
- [ ] Design RAG endpoint API:
  ```
  POST /rag/documents - Add document to KB
  POST /rag/search - Search knowledge base
  GET  /rag/collections - List collections
  DELETE /rag/collections/{name} - Delete collection
  ```
- [ ] Integrate with Qdrant
- [ ] Add document chunking
- [ ] Implement embedding generation
- [ ] Add hybrid search (vector + BM25)
- [ ] Test with real data

**If No**:
- [ ] Remove RAG from documentation
- [ ] Consider removing Qdrant dependency

**Deliverable**: Working RAG or updated docs

**Files**: New RAG module, `main.py`

---

#### 3.2 MCP Broker Implementation (If Needed)
**Issue**: Documentation claims MCP support but doesn't exist
**Impact**: Cannot use MCP tools through gateway
**Effort**: 20-30 hours

**Decision Required**: Do you need MCP aggregation?

**If Yes**:
- [ ] Design MCP broker architecture:
  ```
  GET  /mcp/tools - List available tools
  POST /mcp/call - Call MCP tool
  GET  /mcp/servers - List MCP servers
  ```
- [ ] Implement MCP client for:
  - [ ] Local servers (stdio)
  - [ ] Remote servers (SSE)
- [ ] Add server health monitoring
- [ ] Implement tool aggregation
- [ ] Add to chat completions (tool use)
- [ ] Test with real MCP servers

**If No**:
- [ ] Remove MCP from documentation

**Deliverable**: Working MCP broker or updated docs

**Files**: New MCP module, `main.py`

---

#### 3.3 Latency-Aware Routing Enhancement
**Issue**: Latency tracker exists but routing doesn't use it fully
**Impact**: Doesn't route around overloaded models optimally
**Effort**: 6-8 hours

**Action Items**:
- [ ] Update `Router.route()` to check latency
- [ ] Skip overloaded models in candidate selection
- [ ] Add latency-based rerouting
- [ ] Track model performance over time
- [ ] Add metrics for routing decisions

**Deliverable**: Smarter routing based on actual performance

**Files**: `modules/services/ai-inference/ai_inference_gateway/router.py`

---

### Phase 4: Code Quality & Testing (Ongoing) 🧪 **MAINTENANCE**

#### 4.1 Comprehensive Test Suite
**Effort**: 16-24 hours

**Action Items**:
- [ ] Add tests for streaming responses
- [ ] Add tests for circuit breaker
- [ ] Add tests for middleware pipeline
- [ ] Add tests for routing decisions
- [ ] Add integration tests with real backends
- [ ] Add load tests
- [ ] Set up CI/CD for tests

**Deliverable**: Test coverage >80%

**Files**: `modules/services/ai-inference/ai_inference_gateway/tests/`

---

#### 4.2 Resolve All TODOs
**Effort**: 4-8 hours

**Action Items**:
- [ ] Search codebase for "TODO", "FIXME", "XXX"
- [ ] Create GitHub issues for each
- [ ] Prioritize and schedule
- [ ] Resolve or document why not resolving

**Deliverable**: TODO-free code or documented technical debt

---

#### 4.3 Configuration Validation
**Effort**: 4-6 hours

**Action Items**:
- [ ] Add startup validation for all config
- [ ] Test backend connectivity on startup
- [ ] Validate API keys work
- [ ] Check Qdrant connection if RAG enabled
- [ ] Provide clear error messages for misconfig

**Deliverable**: Fail-fast on invalid configuration

**Files**: `modules/services/ai-inference/ai_inference_gateway/main.py`

---

## 📅 Timeline Summary

| Phase | Duration | Priority | Status |
|-------|----------|----------|--------|
| Phase 1: Critical Fixes | 1 week | HIGH | Not Started |
| Phase 2: Feature Completion | 2 weeks | MEDIUM | Not Started |
| Phase 3: Optional Features | 1-2 weeks | LOW | Not Started |
| Phase 4: Code Quality | Ongoing | MAINTENANCE | Not Started |

**Total Time for Phases 1-2**: 3 weeks
**Total Time for All Phases**: 5-7 weeks

---

## 🎯 Success Criteria

### Phase 1 Success (Week 1)
- [ ] README.md matches actual implementation
- [ ] Health endpoint returns real status
- [ ] No debug logs in production

### Phase 2 Success (Week 3)
- [ ] Processing times tracked accurately
- [ ] All Prometheus metrics working
- [ ] Reranker decision made and implemented

### Phase 3 Success (Week 5+)
- [ ] RAG and/or MCP decision made
- [ ] Implemented or removed from docs

### Overall Success
- [ ] Documentation debt eliminated
- [ ] No TODOs in production code
- [ ] Test coverage >80%
- [ ] All documented features work

---

## 🚀 Quick Wins (Can Do Today)

1. **Remove debug logs** (1 hour)
2. **Update README.md** with "Implemented vs Planned" (2 hours)
3. **Add processing time tracking** (3 hours)

**Total Quick Win Time**: 6 hours

---

## 📊 Priority Matrix

| Issue | Impact | Effort | Priority |
|-------|--------|--------|----------|
| Documentation accuracy | HIGH | LOW | 🔴 P0 |
| Health check implementation | HIGH | MED | 🔴 P0 |
| Debug log removal | MED | LOW | 🟡 P1 |
| Processing time tracking | MED | MED | 🟡 P1 |
| Metrics label conflicts | MED | MED | 🟡 P1 |
| Reranker decision | LOW | LOW | 🟢 P2 |
| RAG implementation | LOW | HIGH | 🟢 P3 |
| MCP broker | LOW | HIGH | 🟢 P3 |

---

## 🔍 Open Questions

1. **RAG**: Do you need RAG functionality? If yes, for what use cases?
2. **MCP**: Do you need MCP tool aggregation? If yes, which servers?
3. **Reranker**: Should we integrate reranker or remove it?
4. **Priority**: Is Phase 3 (RAG/MCP) actually needed or can we document as future work?

---

## 📝 Notes

- This roadmap is **living document** - update as priorities change
- Focus on **Phase 1** first to address documentation debt
- **Phase 2** adds important missing functionality
- **Phase 3** is optional - only if features are actually needed
- **Phase 4** should be ongoing maintenance

---

**Next Steps**:
1. Review and prioritize this roadmap
2. Answer open questions
3. Start with Phase 1.1 (Documentation audit)
4. Create GitHub issues for tracking
