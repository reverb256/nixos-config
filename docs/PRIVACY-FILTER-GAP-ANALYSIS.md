# Privacy Filter Gap Analysis & Research Summary

**Generated:** 2026-04-24
**Scope:** AI Inference Gateway PII Filtering Architecture
**Research Context:** "The Safety Map" paper + OpenAI Privacy Filter integration

---

## Executive Summary

Your cluster has **two PII detection systems** that are deployed but **not integrated** into the AI Gateway's request flow. This creates critical security vulnerabilities identified in recent LLM safety research.

**Critical Finding:** The OpenAI Privacy Filter service is running but **disconnected** from the AI Gateway. Environment variables are set, but the gateway doesn't read them, and no middleware applies PII filtering to LLM inputs/outputs.

---

## Gap Inventory

### Gap 1: Config Disconnect (CRITICAL)

| Component | Status | Details |
|-----------|--------|---------|
| **K8s Config** | ✅ Set | `PRIVACY_FILTER_URL` and `PRIVACY_FILTER_ENABLED` defined |
| **Gateway Config** | ❌ Missing | `src/config.py` has no `PrivacyFilterConfig` class |
| **Runtime Behavior** | ❌ Ignored | Env vars are not loaded → privacy filter never called |

**Evidence:**
```nix
# kubernetes/modules/ai-inference.nix:81-82
PRIVACY_FILTER_URL = "http://privacy-filter.ai-inference.svc.cluster.local:8081";
PRIVACY_FILTER_ENABLED = "true";
```

```python
# src/config.py - NO privacy filter fields defined!
class GatewayConfig(BaseSettings):
    # Has: backend_url, zai_api_key, middleware, etc.
    # MISSING: privacy_filter_url, privacy_filter_enabled
```

**Impact:** Privacy filter service is deployed but orphaned. Zero traffic reaches it.

---

### Gap 2: No Automatic PII Filtering (CRITICAL)

The AI Gateway exposes LLM endpoints without inspecting or filtering content:

| Endpoint | Current Behavior | Required Behavior |
|----------|-----------------|-------------------|
| `POST /v1/chat/completions` | Pass-through | Filter input messages + output response |
| `POST /v1/embeddings` | Pass-through | Filter input text |
| `POST /v1/search/*` | Pass-through | Filter query + results |
| Tool calls | Pass-through | Filter `tool_calls.arguments` |
| Reasoning traces | Pass-through | Filter `reasoning_content` before logging |

**Evidence from `src/main.py`:**
```python
@app.post("/v1/chat/completions")
async def chat_completion(request: ChatCompletionRequest):
    # NO PII filtering here!
    # Direct pass-through to backend
    messages = request.messages
    # ... sends to LLM unfiltered
```

**Impact:** User PII flows unfiltered to:
- LLM providers (potentially logged by them)
- Tool call recipients (webhooks, APIs)
- Observability stacks (Loki, Tempo, Datadog)

---

### Gap 3: Output Channel Vulnerabilities (CRITICAL)

Research from "The Safety Map" (2026-04-24) identified **3 leak channels**. Your gateway covers **none**:

| Leak Channel | Research Finding | Your Coverage | Risk |
|--------------|------------------|---------------|------|
| **Chat Response** | Models leak PII in final output | 🟡 Manual `/pii/redact` endpoint only | MEDIUM |
| **Tool Calls** | 20/73 runs leaked via `tool_calls.arguments` | 🔴 NOT INSPECTED | CRITICAL |
| **Reasoning Traces** | 29/43 runs leaked via `reasoning_content` | 🔴 NOT INSPECTED | CRITICAL |

**Research Evidence:**
> "Of 73 runs that populated `tool_calls.arguments`, 20 exfiltrated sensitive values through that channel. The chat response reads 'I've identified three flagged records' (clean). Meanwhile the tool-call payload reads `{'body': 'Customer John Martinez, SSN 123-45-6789...'}`"

**Your Gateway's Vulnerability:**
```python
# src/main.py - Chat completion handler
response_data = {
    "choices": [{
        "message": {
            "content": final_content,  # ❌ NOT FILTERED
            "tool_calls": tool_calls  # ❌ NOT FILTERED
        }
    }],
    "usage": usage,
    # If reasoning enabled:
    "reasoning_content": reasoning  # ❌ NOT FILTERED
}
# Returns directly to user - no PII inspection
```

---

### Gap 4: Observability Logging (CRITICAL)

Your cluster runs observability stacks that may log raw LLM output:

| Component | Risk | Evidence |
|-----------|------|----------|
| **Loki** (log aggregation) | Stores raw model output | `modules/services/monitoring.nix` |
| **Tempo** (distributed tracing) | Traces may contain prompts/responses | `modules/services/monitoring.nix` |
| **Grafana** (dashboards) | Displays unfiltered logs | K8s manifests |

**Research Finding:**
> "If any of those [observability systems] retain raw model output (most do, by default), you now have sensitive data sitting in a third-party SaaS log system for 30 to 90 days, searchable by anyone with log access"

**Your Configuration:**
```nix
# Alloy OTel collector sends traces to Tempo
# Logs go to Loki
# NO PII sanitization before ingestion
```

**Legal Risk:** If you process:
- HIPAA data (PHI) → logged in Loki/Tempo = HIPAA violation
- GDPR data (EU citizens) → logged outside EU = GDPR violation
- Financial data → logged without access controls = SOX/compliance issue

---

### Gap 5: Context-Based PII (HIGH)

The research identified that **context-based PII** is the hardest category:

**Example from Research:**
```
Input: "Row 47: SSN detected. Customer: John Doe"
Model Output: "Row 47 contains an SSN. Customer: John Doe"
```

The model redacts the SSN but leaks the **customer name**, which becomes sensitive *because* it's adjacent to the SSN.

**Your Current Regex Redactor:**
```python
# src/pii_redactor.py
DEFAULT_PATTERNS = [
    "email",    # ✅ Detects john@example.com
    "phone",    # ✅ Detects 555-123-4567
    "ssn",      # ✅ Detects 123-45-6789
    "credit_card", # ✅ Detects 4111-1111-1111-1111
    # ❌ NO context awareness
    # ❌ Doesn't understand "name adjacent to SSN = sensitive"
]
```

**OpenAI Privacy Filter Capability:**
```python
# Detects 8 categories including:
- private_person (names)
- private_date (birthdays, dates)
# But also lacks true semantic context understanding
```

**Gap:** Neither system understands that *relationships* between entities create sensitivity.

---

### Gap 6: Non-Deterministic Safety (MEDIUM)

Research found that 9/39 models showed **NON-DET behavior** (same prompt, different safety outcomes across runs).

**Implication for Your Gateway:**
- Single-run evaluation passes 70% of the time on a model that leaks 30% of the time
- Your regex redactor is deterministic, but the OpenAI model is probabilistic
- No multi-run validation before production deployment

**Your Testing:**
```bash
# No evidence of multi-run PII testing
# Single-pass evaluation assumed sufficient
```

**Recommendation:** Run 3-5 evaluations on any model before trusting it with sensitive data.

---

### Gap 7: Inference Stack Variance (MEDIUM)

Research finding: *Same weights, different stack = different leak rates*

**Your Deployment:**
```
openai/privacy-filter model
├─ K8s deployment (transformers + torch)
├─ Different than: llama.cpp, ONNX
└─ Safety profile tied to serving stack
```

**Risk:** If you switch serving stacks, you must re-evaluate safety.

---

## Architecture Comparison

### Current State (Broken)

```
┌─────────────────────────────────────────────────────────────┐
│                     AI GATEWAY (Current)                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  User Request ──→ [NO FILTER] ──→ LLM Backend               │
│                         │                                    │
│                         ├─→ Chat Response                   │
│                         ├─→ Tool Calls (NOT INSPECTED)       │
│                         └─→ Reasoning (NOT INSPECTED)        │
│                                                              │
│  Observability (Loki/Tempo) ──→ [RAW DATA LOGGED]            │
│                                                              │
│  Privacy Filter Service ──→ [DEPLOYED BUT UNUSED]            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Target State (Secure)

```
┌─────────────────────────────────────────────────────────────┐
│                   AI GATEWAY (Target)                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. INPUT LAYER                                              │
│     ├─ Regex redactor: email, phone, SSN, API keys          │
│     └─ OpenAI Privacy Filter: names, addresses, dates        │
│                                                              │
│  2. LLM PROCESSING                                           │
│     └─ Model generation (Qwen, GPT, etc.)                    │
│                                                              │
│  3. OUTPUT LAYER (ALL CHANNELS)                              │
│     ├─ Chat Response → Filtered                             │
│     ├─ tool_calls.arguments → Filtered                      │
│     └─ reasoning_content → Filtered BEFORE logging           │
│                                                              │
│  4. OBSERVABILITY LAYER                                      │
│     └─ Sanitized data only to Loki/Tempo                     │
│                                                              │
│  5. PRIVACY FILTER SERVICE                                   │
│     └─ ACTIVELY CALLED by gateway middleware                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Roadmap

### Phase 1: Config Integration (1-2 hours)

**Files to modify:**
- `src/config.py` - Add `PrivacyFilterConfig` class
- `src/main.py` - Load privacy filter client on startup

**Deliverable:** Gateway reads `PRIVACY_FILTER_URL` and `PRIVACY_FILTER_ENABLED`

### Phase 2: Input Filtering Middleware (2-3 hours)

**Files to modify:**
- `src/main.py` - Add middleware to all LLM endpoints
- Create `src/privacy_middleware.py` - Unified filtering logic

**Deliverable:** All user inputs filtered before reaching LLM

### Phase 3: Output Channel Filtering (3-4 hours)

**Files to modify:**
- `src/main.py` - Filter all output channels
- Create output sanitizer for chat, tools, reasoning

**Deliverable:** All LLM outputs filtered before returning to user

### Phase 4: Observability Sanitization (2-3 hours)

**Files to modify:**
- `src/main.py` - Sanitize before sending to Loki/Tempo
- OTel configuration

**Deliverable:** Logs/traces contain only redacted data

### Phase 5: Testing & Validation (2-3 hours)

**Tasks:**
- Multi-run PII testing (5+ runs)
- Tool call injection tests
- Reasoning trace leak tests
- Observability inspection tests

**Deliverable:** Test suite with documented pass/fail criteria

---

## Research Sources

### Primary Research
1. **"The Safety Map: What Does and Doesn't Transfer in LLM Sensitive-Data Handling"**
   - Published: 2026-04-24
   - DOI: https://doi.org/10.5281/zenodo.19688433
   - Key findings: Output channel dissociation, non-deterministic safety, inference stack variance

### OpenAI Privacy Filter Documentation
2. **Model Card** - https://huggingface.co/openai/privacy-filter
   - 8 PII categories: account_number, private_address, private_email, private_person, private_phone, private_url, private_date, secret
   - 1.5B parameters, 50M active, Apache 2.0 licensed
   - 128K token context window

### Best Practices (General Knowledge)
3. **OWASP AI Security Top 10** - LLM prompt injection, data poisoning, model theft
4. **NIST AI Risk Management Framework** - AI system governance, testing, monitoring
5. **HIPAA Security Rule** - PHI handling, logging, access controls
6. **GDPR Article 25** - Data protection by design, data minimization

---

## Risk Assessment

| Gap | Severity | Exploitability | Impact | Priority |
|-----|----------|----------------|--------|----------|
| Config disconnect | HIGH | Low (service orphaned) | MEDIUM | P1 |
| No automatic filtering | CRITICAL | High (all traffic exposed) | HIGH | P0 |
| Output channel leaks | CRITICAL | High (tool calls active) | CRITICAL | P0 |
| Observability logging | CRITICAL | Medium (logs accessible) | CRITICAL | P0 |
| Context-based PII | HIGH | Medium (edge cases) | MEDIUM | P1 |
| Non-deterministic safety | MEDIUM | Low (testing gap) | MEDIUM | P2 |
| Inference stack variance | MEDIUM | Low (deployment control) | LOW | P2 |

---

## Next Steps

1. **Immediate (This Week):**
   - [ ] Add `PrivacyFilterConfig` to `src/config.py`
   - [ ] Implement input filtering middleware
   - [ ] Test with PII-loaded prompts

2. **This Month:**
   - [ ] Implement all 3 output channel filters
   - [ ] Add observability sanitization
   - [ ] Create multi-run test suite

3. **Ongoing:**
   - [ ] Monitor for new research on LLM safety
   - [ ] Re-evaluate models on every update
   - [ ] Document all PII handling for compliance

---

**Document Status:** Draft v1.0
**Owner:** j_kro
**Review Date:** 2026-05-01
