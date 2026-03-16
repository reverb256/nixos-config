# AI Inference Gateway - Improvement Roadmap

**Date**: 2026-03-04
**Status**: Draft
**Last Updated**: 2026-03-16
**Priority**: Address documentation debt and missing features

---

## ✅ Completed Quick Wins (2026-03-15)

Three high-impact improvements completed in ~4 hours total:

### 1. Tool Calling Loop Detection ✅
**File**: `utils/tool_utils.py`
**Status**: COMPLETED
**Effort**: 1 hour

**Implementation**:
- Added `has_tool_calls_openai()` - Detects OpenAI-format tool calls
- Added `has_tool_calls_anthropic()` - Detects Anthropic-format tool use blocks
- Added `has_tool_calls()` - Generic auto-detect wrapper
- Added `is_tool_response_format()` - Distinguishes tool results from tool calls
- Full extraction utilities for both formats

**Impact**: Gateway can now safely detect and handle agentic tool loops, preventing infinite loops in multi-turn conversations.

---

### 2. Enable Streaming for Tools ✅
**File**: `main.py`
**Status**: COMPLETED
**Effort**: 1 hour

**Implementation**:
- Added `stream_backend_response_with_tools()` function
- Handles `tool_use` content blocks in streaming responses
- Returns both `content` blocks and `tool_use` blocks to client
- Preserves tool_use ID and input for tool execution

**Impact**: Clients can stream responses while still receiving tool calls, enabling real-time agentic workflows.

---

### 3. File Upload/Download API with Garage S3 ✅
**Files**: `files.py` (new), `main.py` (updated)
**Status**: COMPLETED
**Effort**: 2 hours

**Implementation**:
- **New module**: `files.py` with complete Garage S3 client
  - `GarageS3Client` class with async HTTP operations
  - File metadata support (filename, bytes, created_at, purpose, mime_type)
  - Custom exceptions for error handling
  - MIME type detection for 50+ file formats
  - Unique file ID generation (Anthropic-compatible `file_*` format)

- **New endpoints** (OpenAI/Anthropic-compatible):
  - `POST /v1/files` - Upload files to Garage S3
  - `GET /v1/files/{file_id}` - Retrieve file metadata and content
  - `DELETE /v1/files/{file_id}` - Delete files

**Integration**:
- Optional import pattern with `FILES_AVAILABLE` flag
- Graceful degradation if files module unavailable
- GatewayState singleton for client management
- Direct HTTP requests via httpx (no boto3 dependency)

**Storage**:
- Uses local Garage S3 at `127.0.0.1:3900`
- Default bucket: `ai-gateway-files`
- Metadata stored as `x-amz-meta-*` headers

**Impact**: Full OpenAI-compatible Files API, enabling document upload for RAG, vision processing, and file-based workflows.

---

## 📊 Executive Summary

**STATUS UPDATE (2026-03-16):**
- ✅ **Phase 0 (Quick Wins)** - COMPLETED (tool loop detection, streaming tools, Files API)
- ✅ **Feature Audit** - RAG and MCP ARE implemented (previous assessment was incorrect)
- ⚠️ **Phase 1** - Documentation updates needed to reflect actual implementation

The gateway is **functionally solid** with more features working than previously documented. RAG and MCP support are **fully implemented** and operational.

**Current Status**: ✅ Production-ready with RAG ✅, MCP ✅, Tool calling ✅, Files API ✅
**Target**: Accurate documentation that matches working implementation

The gateway is **functionally solid for core use cases** but has significant gaps between documentation and implementation. This roadmap prioritizes fixing documentation accuracy, implementing critical missing features, and resolving technical debt.

**Current Status**: ✅ Production-ready for basic chat completions, ✅ Tool calling support (2026-03-15), ✅ Files API with Garage S3 (2026-03-15)
**Target**: Fully-documented, feature-complete gateway

**Recent Updates** (2026-03-15):
- ✅ Tool calling loop detection implemented
- ✅ Streaming responses with tool use enabled
- ✅ Files API endpoints (upload/download/delete) with local Garage S3 storage

---

## 🎯 Roadmap Phases

### Phase 1: Critical Fixes (Week 1) ⚠️ **HIGH PRIORITY**

#### 1.1 Documentation Accuracy
**Issue**: Gateway improvement roadmap incorrectly claimed RAG/MCP features don't exist
**Impact**: User confusion about available features
**Effort**: 2-4 hours

**Action Items**:
- [x] ~~Audit README.md against actual implementation~~ - COMPLETED (2026-03-16)
- [x] ~~Verify RAG endpoints exist~~ - CONFIRMED: RAG is fully implemented
- [x] ~~Verify MCP broker functionality~~ - CONFIRMED: MCP broker exists
- [ ] Add "Implemented Features" section with checkboxes
- [ ] Create "Known Limitations" section
- [ ] Update health endpoint documentation

**CORRECTIONS (2026-03-16):**
- ✅ RAG IS implemented (`modules/services/ai-inference/gateway.nix:169-178`)
- ✅ MCP broker EXISTS (`mcp_broker.py`, environment variable `MCP_ENABLED`)
- ✅ Reranker IS configured (`RERANKER_ENABLED`, `RERANKER_MODEL`)
- ❌ Health check still TODO (line 272 in main.py)

**Deliverable**: Accurate documentation that matches implementation

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

### Phase 3: Optional Features (Week 4+) 📋 **LOW PRIORITY - STATUS UPDATE**

**STATUS UPDATE (2026-03-16):**
- ✅ **RAG:** FULLY IMPLEMENTED - See `modules/services/ai-inference/middleware/knowledge_fabric/`
- ✅ **MCP Broker:** FULLY IMPLEMENTED - See `modules/services/ai-inference/mcp_broker.py`
- ⚠️ **Reranker:** CONFIGURED but usage in routing decisions unclear

#### 3.1 RAG Implementation Status ✅ COMPLETE
**Original Issue**: Documentation claimed RAG support but no endpoints exist
**Actual Status**: FULLY IMPLEMENTED

**Implemented Components:**
- ✅ RAG source: `middleware/knowledge_fabric/sources/rag_source.py`
- ✅ RAG injection: `middleware/rag_injector.py`
- ✅ Knowledge fabric integration: `middleware/knowledge_fabric/fabric.py`
- ✅ Configuration: `RAG_ENABLED`, `QDRANT_URL`, `EMBEDDING_MODEL` in gateway.nix
- ✅ Hybrid search: Vector + BM25

**Decision Required**: Do you need additional RAG endpoints beyond existing implementation?

**If Additional Features Needed:**
- [ ] Design additional RAG endpoint API (if gaps exist)
- [ ] Document existing RAG capabilities in README.md
- [ ] Test RAG with real data

**If No Additional Features:**
- [x] ~~Remove RAG from documentation~~ - CORRECTED: RAG is implemented
- [ ] Update README.md to accurately describe RAG capabilities

**Deliverable**: Documented RAG capabilities or additional features

**Files**: `modules/services/ai-inference/middleware/knowledge_fabric/`

---

#### 3.2 MCP Broker Status ✅ COMPLETE
**Original Issue**: Documentation claimed MCP support but doesn't exist
**Actual Status**: FULLY IMPLEMENTED

**Implemented Components:**
- ✅ MCP broker: `mcp_broker.py` (lines 1235-1300+)
- ✅ MCP environment variable: `MCP_ENABLED`
- ✅ MCP server configuration: `MCP_SERVERS` in gateway.nix
- ✅ MCP tools integration in chat completions

**Decision Required**: Do you need additional MCP aggregation features?

**If Additional Features Needed:**
- [ ] Design additional MCP broker capabilities (if gaps exist)
- [ ] Document existing MCP capabilities in README.md

**If No Additional Features:**
- [x] ~~Remove MCP from documentation~~ - CORRECTED: MCP is implemented
- [ ] Update README.md to accurately describe MCP capabilities

**Deliverable**: Documented MCP capabilities or additional features

**Files**: `modules/services/ai-inference/mcp_broker.py`

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
| Phase 0: Quick Wins | 1 day | HIGH | ✅ **COMPLETED** (2026-03-15) |
| Phase 1: Critical Fixes | 1 week | HIGH | Not Started |
| Phase 2: Feature Completion | 2 weeks | MEDIUM | Not Started |
| Phase 3: Optional Features | 1-2 weeks | LOW | Not Started |
| Phase 4: Code Quality | Ongoing | MAINTENANCE | Not Started |

**Total Time for Phase 0**: 4 hours (completed)
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

### ✅ Completed (2026-03-15)

1. ~~**Remove debug logs**~~ (1 hour) - **PENDING**
2. ~~**Update README.md**~~ with "Implemented vs Planned" (2 hours) - **PENDING**
3. **Tool calling loop detection** (1 hour) - ✅ **COMPLETED**
4. **Enable streaming for tools** (1 hour) - ✅ **COMPLETED**
5. **File upload/download API** (2 hours) - ✅ **COMPLETED**

### Remaining Quick Wins

1. **Remove debug logs** (1 hour)
2. **Update README.md** with "Implemented vs Planned" (2 hours)
3. **Add processing time tracking** (3 hours)

**Total Completed Quick Win Time**: 4 hours
**Remaining Quick Win Time**: 6 hours

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
