# End-to-End ML Security Plan

**Created:** 2026-04-24
**Owner:** j_kro
**Scope:** AI inference stack on 4-node NixOS/K3s cluster
**Informed by:** "The Safety Map" research (39 LLMs, 14 labs), OWASP LLM Top 10, gap analysis of existing infrastructure

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Threat Model](#2-threat-model)
3. [Architecture Overview](#3-architecture-overview)
4. [Layer 1: Input Security](#4-layer-1-input-security)
5. [Layer 2: Model Security](#5-layer-2-model-security)
6. [Layer 3: Output Security](#6-layer-3-output-security)
7. [Layer 4: Infrastructure Security](#7-layer-4-infrastructure-security)
8. [Layer 5: Data Security](#8-layer-5-data-security)
9. [Layer 6: Observability Security](#9-layer-6-observability-security)
10. [Layer 7: Supply Chain Security](#10-layer-7-supply-chain-security)
11. [Compliance & Governance](#11-compliance--governance)
12. [Monitoring, Alerting & Incident Response](#12-monitoring-alerting--incident-response)
13. [Implementation Roadmap](#13-implementation-roadmap)
14. [Acceptance Criteria](#14-acceptance-criteria)
15. [References](#15-references)

---

## 1. Executive Summary

### Current State

The cluster runs an AI Gateway (FastAPI on Nexus) that proxies LLM requests to multiple backends (Qwen3.6-35B on RTX 3090, SuperGemma4 on RTX 3060 Ti, Qwen3.5-4B on AMD RX 5600 XT). Two PII detection systems exist but are **disconnected from the request flow**:

- **Regex redactor** (`pii_redactor.py`): 8 patterns, only accessible via manual `/pii/redact` endpoint
- **OpenAI Privacy Filter** (K8s deployment): 8 entity categories via BIOES NER model, deployed but never called by the gateway

### Research Findings ("The Safety Map")

The paper tested 39 LLMs across 14 labs and found:

1. **Output channel dissociation**: Models can be SAFE in chat responses but LEAK PII via `tool_calls.arguments` (20/73 runs) or `reasoning_content` (29/43 runs)
2. **Non-deterministic safety**: 9/39 models showed both SAFE and LEAKED on identical inputs across runs
3. **Architecture floor**: Models below ~24B parameters have fundamentally unreliable safety behavior
4. **No transfer**: Safety on one PII category does NOT predict safety on another

### Critical Gaps

| Gap | Severity | Current State |
|-----|----------|---------------|
| No automatic PII filtering on any endpoint | P0 | Env vars set, gateway ignores them |
| Tool call arguments never inspected | P0 | Pass-through to external APIs |
| Reasoning traces never filtered | P0 | Logged raw to Loki/Tempo |
| Observability ingests unredacted data | P0 | Loki/Tempo/Grafana store raw PII |
| No prompt injection defense | P1 | Gateway trusts all inputs |
| No model integrity verification | P2 | GGUF files not checksummed |
| No adversarial input detection | P2 | No rate limiting or anomaly detection |

---

## 2. Threat Model

### Attack Surfaces

```
EXTERNAL USERS / AGENTS (Hermes, omp, cron)
         |
         v
    [AI Gateway :8080]  <--- Entry point
         |
    +----+----+----+
    |         |    |
    v         v    v
[llama-server] [Qdrant] [SearXNG]
 (LLM infer)  (vectors) (web search)
    |              |
    v              v
[Tool Calls]  [Embeddings]
 (outbound)   (stored)
    |
    v
[Loki/Tempo/Grafana]  <--- Observability (logs everything)
```

### Threat Actors

| Actor | Motivation | Capability | Target |
|-------|------------|------------|--------|
| **External user** | Data exfiltration, prompt injection | Can craft arbitrary prompts to gateway | Chat completions, tool calls |
| **Compromised agent** (Hermes, omp) | Lateral movement, PII harvest | Has service account, calls gateway programmatically | All endpoints |
| **Malicious model output** | PII leakage via tool calls/reasoning | LLM generates crafted responses | Tool call arguments, reasoning traces |
| **Supply chain** | Model poisoning, backdoored weights | Can modify GGUF files in transit | Model behavior |
| **Insider with log access** | PII harvest from observability | Grafana/Loki access | Stored traces, logs |

### Threat Matrix

| Threat | OWASP Ref | Likelihood | Impact | Risk |
|--------|-----------|------------|--------|------|
| PII in chat responses | LLM02 | Medium | High | HIGH |
| PII exfiltrated via tool calls | LLM02 | High (20/73) | Critical | CRITICAL |
| PII in reasoning traces | LLM02 | High (29/43) | High | CRITICAL |
| Prompt injection | LLM01 | High | High | CRITICAL |
| Training data extraction | LLM06 | Low | Critical | MEDIUM |
| Supply chain model poisoning | LLM05 | Low | Critical | HIGH |
| Denial of service | LLM10 | Medium | Medium | MEDIUM |
| Observability PII exposure | LLM02 | High | High | CRITICAL |

---

## 3. Architecture Overview

### Target Architecture (Defense in Depth)

```
USER REQUEST
    |
    v
+--[INPUT GATE]------------------------------------------+
| 1. Rate limiting & request validation                   |
| 2. Prompt injection detection (heuristic + ML)          |
| 3. PII detection (regex fast path + Privacy Filter ML)  |
| 4. Input sanitization (mask PII before LLM)             |
+---------------------------------------------------------+
    |
    v
+--[MODEL ROUTING]---------------------------------------+
| Route to appropriate backend based on:                   |
| - Model capability (24B+ for sensitive data)             |
| - Request type (chat, tool, reasoning)                   |
| - Sensitivity classification                             |
+---------------------------------------------------------+
    |
    v
+--[LLM INFERENCE]---------------------------------------+
| llama-server instances (CUDA/ROCm/Vulkan)                |
| Model integrity verified at load time                    |
+---------------------------------------------------------+
    |
    v
+--[OUTPUT GATE]-----------------------------------------+
| Filter ALL output channels:                              |
| 1. Chat response content -> regex + Privacy Filter       |
| 2. Tool call arguments -> recursive sanitize             |
| 3. Reasoning content -> regex + Privacy Filter           |
| 4. Any other structured output -> sanitize               |
+---------------------------------------------------------+
    |
    v
+--[OBSERVABILITY GATE]----------------------------------+
| Sanitize before logging:                                 |
| 1. OTel spans -> redact PII from attributes             |
| 2. Log messages -> redact before Loki ingestion         |
| 3. Traces -> redact before Tempo ingestion              |
| 4. Metrics -> no PII (counts/latencies only)            |
+---------------------------------------------------------+
    |
    v
USER RESPONSE (sanitized) + GRAFANA (sanitized data only)
```

### Component Inventory

| Component | Location | Current Security | Target Security |
|-----------|----------|-----------------|-----------------|
| AI Gateway | Nexus K8s pod | None | Input+Output filtering |
| Privacy Filter ML | Nexus K8s pod | Deployed, unused | Active on all requests |
| Regex Redactor | Gateway code | Manual API only | Inline on all requests |
| llama-servers | Zephyr/Sentry | None | Model integrity checks |
| Qdrant | Nexus K8s pod | None | Embedding sanitization |
| SearXNG | Nexus K8s pod | None | Query sanitization |
| Loki | Sentry | Raw ingestion | Pre-ingestion filtering |
| Tempo | Sentry | Raw ingestion | Span attribute filtering |
| Grafana | Sentry/Zephyr | Displays raw data | Sanitized views only |

---

## 4. Layer 1: Input Security

### 4.1 Request Validation & Rate Limiting

**Problem:** Gateway accepts unlimited requests with no validation.

**Implementation:**

```python
# src/middleware/rate_limit.py
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@app.post("/v1/chat/completions")
@limiter.limit("60/minute")  # Per-client rate limit
async def chat_completion(request: Request, ...):
    ...
```

**Tasks:**
- [ ] Add `slowapi` dependency to gateway
- [ ] Configure per-endpoint rate limits
- [ ] Add request size validation (max 128K tokens)
- [ ] Block malformed JSON early (400, not 500)

### 4.2 Prompt Injection Detection

**Problem:** Gateway passes all user input directly to LLMs. OWASP LLM01.

**Detection strategies (tiered):**

| Layer | Method | Latency | Catch Rate |
|-------|--------|---------|------------|
| 1. Regex patterns | Known attack signatures | <1ms | ~40% |
| 2. Heuristic scoring | Instruction density, role confusion | <5ms | ~60% |
| 3. ML classifier | Fine-tuned on prompt injection datasets | ~50ms | ~85% |

**Regex patterns (fast path):**

```python
INJECTION_PATTERNS = [
    r"ignore\s+(all\s+)?previous\s+instructions",
    r"you\s+are\s+now\s+(?:a\s+)?(?:DAN|jailbreak)",
    r"system\s*:\s*",
    r"<\|im_start\|>",
    r"\[INST\]",
    r"###\s*Instruction",
    r"pretend\s+you\s+(?:are|can)",
]
```

**Tasks:**
- [ ] Create `src/prompt_injection_detector.py`
- [ ] Add regex-based fast path
- [ ] Add heuristic scorer (instruction density, role confusion markers)
- [ ] Evaluate ML classifier (use BGE-M3 embeddings + small classifier head)
- [ ] Add `X-Prompt-Safety-Score` response header
- [ ] Log rejected requests for analysis

### 4.3 Input PII Sanitization

**Problem:** User PII flows unfiltered to LLM backends (and their logs).

**Strategy: Two-pass filtering**

```
Pass 1: Regex (fast, ~1ms)
  -> email, phone, SSN, credit card, API key, IP, bearer token, password

Pass 2: Privacy Filter ML (thorough, ~50ms)
  -> names, addresses, dates, account numbers, URLs, secrets
  -> Only if Pass 1 finds PII OR sensitivity flag is set
```

**Implementation:**

```python
# src/middleware/pii_input.py
async def sanitize_input(messages: list[dict], pii_filter) -> list[dict]:
    for msg in messages:
        if msg["role"] == "user":
            # Pass 1: Regex (always runs)
            msg["content"] = regex_redactor.redact(msg["content"])

            # Pass 2: ML filter (if PII detected or sensitive request)
            if pii_detected or msg.get("sensitive"):
                msg["content"] = await pii_filter.redact(msg["content"])

    return messages
```

**Tasks:**
- [ ] Add `PrivacyFilterConfig` to `src/config.py`:
  ```python
  class PrivacyFilterConfig(BaseModel):
      enabled: bool = False
      url: str = "http://localhost:8081"
      timeout: float = 5.0
      mode: str = "redact"  # redact | detect | hash
  ```
- [ ] Load from `PRIVACY_FILTER_URL` / `PRIVACY_FILTER_ENABLED` env vars
- [ ] Create HTTP client to call privacy-filter service
- [ ] Add input sanitization middleware to `/v1/chat/completions`
- [ ] Add input sanitization to `/v1/embeddings` (sanitize embedding text)
- [ ] Add input sanitization to `/search` endpoints (sanitize queries)
- [ ] Preserve original text in request context for audit logging (sanitized)

### 4.4 Tool Call Input Validation

**Problem:** User can define arbitrary tool schemas. Tool calls execute without validation.

**Tasks:**
- [ ] Validate tool definitions against allow-list
- [ ] Block dangerous tool patterns (file system access, network, eval)
- [ ] Sanitize tool descriptions (prompt injection vector)
- [ ] Rate limit tool execution per client

---

## 5. Layer 2: Model Security

### 5.1 Model Integrity Verification

**Problem:** GGUF model files are downloaded without verification. Compromised files could inject behavior.

**Implementation:**

```nix
# packages/llama-cpp-turboquant.nix or similar
# Pin model files to known SHA256 hashes
let
  modelHashes = {
    "qwen3.6-35b-a3b-iq4_nl.gguf" = "sha256-XXXX...";
    "supergemma4-q5_k_m.gguf" = "sha256-XXXX...";
    "qwen3.5-4b-q4_k_m.gguf" = "sha256-XXXX...";
  };
in
  # Verify hash on download
  builtins.fetchurl {
    url = "https://huggingface.co/.../${name}";
    sha256 = modelHashes.${name};
  }
```

**Tasks:**
- [ ] Catalog all GGUF files with SHA256 hashes
- [ ] Add hash verification to model download scripts
- [ ] Verify hashes at llama-server startup
- [ ] Alert on hash mismatch (fail-closed)

### 5.2 Model Parameter Floor

**Problem:** Research shows models below ~24B parameters have unreliable safety behavior.

**Current models:**

| Model | Active Params | Safety Floor Met? | Notes |
|-------|---------------|-------------------|-------|
| Qwen3.6-35B-A3B | 4B active (35B total) | Borderline | MoE - safety depends on expert routing |
| SuperGemma4-Q5_K_M | ~4B active | NO | Below 24B floor |
| Qwen3.5-4B-Q4_K_M | 4B | NO | Below 24B floor |

**Implication:** Only the Qwen3.6-35B model approaches the safety floor, and its MoE architecture means active parameters per token are only ~4B. **No current model reliably passes safety tests.**

**Tasks:**
- [ ] Document safety floor analysis for each model
- [ ] Add model safety tier to `/v1/models` response
- [ ] Restrict sensitive workloads to largest available model
- [ ] Plan for deploying a 24B+ dense model (requires >12GB VRAM)

### 5.3 Inference Stack Consistency

**Problem:** Research found that same weights on different serving stacks produce different safety profiles.

**Current stacks:**

| Instance | Stack | GPU | Notes |
|----------|-------|-----|-------|
| Zephyr RTX 3090 | llama.cpp (TurboQuant, CUDA) | CUDA 1 | Custom patches |
| Zephyr RTX 3060 Ti | llama.cpp (TurboQuant, CUDA) | CUDA 0 | Custom patches |
| Sentry AMD | llama.cpp (ROCm/Vulkan) | ROCm | Different backend |

**Tasks:**
- [ ] Test safety consistency across all serving stacks
- [ ] Document per-stack safety profile
- [ ] Add serving stack identifier to responses
- [ ] Re-test when updating llama.cpp version

### 5.4 Non-Deterministic Safety Mitigation

**Problem:** 9/39 models showed both SAFE and LEAKED on identical inputs.

**Mitigation: Multi-run consensus for sensitive operations**

```python
async def safe_completion(messages, pii_filter, runs=3):
    results = []
    for _ in range(runs):
        response = await call_llm(messages)
        leak_score = await detect_pii(response, pii_filter)
        results.append((response, leak_score))

    # If any run leaked, apply full sanitization
    if any(r[1] > 0 for r in results):
        return sanitize_all_channels(results[0][0], pii_filter)

    return results[0][0]
```

**Tasks:**
- [ ] Add multi-run mode for high-sensitivity requests
- [ ] Add sensitivity classification to requests (auto or manual)
- [ ] Log all runs for audit trail
- [ ] Implement consensus logic (majority vote on safety)

---

## 6. Layer 3: Output Security

### 6.1 The Three Output Channels

Research ("The Safety Map") identified three distinct channels where LLMs output data, each with independent safety behavior:

```
LLM RESPONSE
    |
    +---> chat content         (visible to user, filtered in some models)
    +---> tool_calls.arguments (sent to external APIs, NEVER filtered by models)
    +---> reasoning_content    (logged to observability, NEVER filtered by models)
```

**Critical finding:** Safety on one channel does NOT predict safety on others.

### 6.2 Chat Response Filtering

**Status:** Partially covered by regex redactor (manual endpoint only).

**Tasks:**
- [ ] Apply regex redactor to ALL chat completion responses automatically
- [ ] Add Privacy Filter ML as second pass for high-sensitivity requests
- [ ] Add response content-type awareness (don't filter code blocks destructively)
- [ ] Log redaction events (what was redacted, not the original value)

### 6.3 Tool Call Argument Sanitization (P0 CRITICAL)

**Status:** Zero coverage. 20/73 research runs leaked PII via tool calls.

**Implementation:**

```python
# src/output/tool_call_sanitizer.py
import json

def sanitize_tool_call(tool_call: dict, redactor) -> dict:
    name = tool_call["function"]["name"]
    args_str = tool_call["function"]["arguments"]

    try:
        args = json.loads(args_str)
    except json.JSONDecodeError:
        return tool_call  # Can't sanitize invalid JSON

    sanitized = _sanitize_recursive(args, redactor)
    tool_call["function"]["arguments"] = json.dumps(sanitized)
    return tool_call

def _sanitize_recursive(obj, redactor, depth=0):
    if depth > 10:
        return obj
    if isinstance(obj, str):
        return redactor.redact(obj)
    if isinstance(obj, dict):
        return {k: _sanitize_recursive(v, redactor, depth+1) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_sanitize_recursive(v, redactor, depth+1) for v in obj]
    return obj  # int, float, bool, None
```

**Tasks:**
- [ ] Create `src/output/tool_call_sanitizer.py`
- [ ] Apply to all tool calls BEFORE execution
- [ ] Apply to all tool calls BEFORE returning to client
- [ ] Log sanitized tool calls (not originals)
- [ ] Test with nested JSON, arrays, mixed types

### 6.4 Reasoning Trace Filtering (P0 CRITICAL)

**Status:** Zero coverage. 29/43 research runs leaked PII via reasoning.

**Implementation:**

```python
# In response handler, before any logging
if "reasoning_content" in response:
    response["reasoning_content"] = redactor.redact(response["reasoning_content"])

# Anthropic extended thinking format
for block in response.get("content", []):
    if block.get("type") == "thinking":
        block["thinking"] = redactor.redact(block["thinking"])

# DeepSeek R1 format (embedded in content)
if "<think" in response.get("content", ""):
    # Parse thinking blocks and redact
    response["content"] = redact_thinking_blocks(response["content"], redactor)
```

**Tasks:**
- [ ] Create `src/output/reasoning_sanitizer.py`
- [ ] Support OpenAI `reasoning_content` format
- [ ] Support Anthropic `thinking` block format
- [ ] Support DeepSeek `<think/>` embedded format
- [ ] Filter BEFORE any logging or observability export
- [ ] Add response header `X-Reasoning-Filtered: true`

### 6.5 Unified Output Sanitizer

**Tasks:**
- [ ] Create `src/output/response_sanitizer.py` that combines all channel filters
- [ ] Apply as response middleware on `/v1/chat/completions`
- [ ] Apply as response middleware on all streaming endpoints
- [ ] Handle streaming partial responses (buffer and sanitize chunks)

---

## 7. Layer 4: Infrastructure Security

### 7.1 Network Policies (Partially Implemented)

**Current state:** Default-deny policies exist for some namespaces.

**Tasks:**
- [ ] Verify default-deny on ALL namespaces
- [ ] Add egress rules: gateway -> privacy-filter only on port 8081
- [ ] Add egress rules: gateway -> llama-servers only on model ports
- [ ] Block gateway -> internet egress (prevent data exfiltration)
- [ ] Allow gateway -> SearXNG only in `search` namespace
- [ ] Allow gateway -> Qdrant only in `ai-inference` namespace
- [ ] Audit and document all network policy exceptions

### 7.2 Pod Security Standards (Partially Implemented)

**Current state:** PSS labels applied to namespaces.

**Tasks:**
- [ ] Enforce `restricted` profile on `ai-inference` namespace
- [ ] Drop all capabilities, run as non-root
- [ ] Read-only root filesystem for gateway and privacy-filter
- [ ] Verify Falco rules cover AI-specific threats

### 7.3 Secrets Management

**Current state:** Agenix for NixOS secrets, K8s Secrets for cluster.

**Tasks:**
- [ ] Move all API keys from env vars to K8s Secrets (or external secret manager)
- [ ] Rotate gateway secrets on schedule
- [ ] Never log secret values (add to redaction patterns)
- [ ] Audit: are any secrets in plaintext ConfigMaps?

### 7.4 RBAC for AI Services

**Tasks:**
- [ ] Create dedicated ServiceAccounts for gateway, privacy-filter, qdrant
- [ ] Minimize permissions per service
- [ ] Add network policy per service account
- [ ] Audit existing RBAC for overprivileged accounts

### 7.5 llama-server Hardening

**Problem:** llama-servers bind `0.0.0.0` (accessible from any network).

**Tasks:**
- [ ] Bind to LAN-only (10.0.0.0/8) or pod network only
- [ ] Add API key authentication to llama-servers
- [ ] Restrict to gateway-originated traffic only
- [ ] Add request logging with sanitized output

---

## 8. Layer 5: Data Security

### 8.1 Embedding Vector Sanitization

**Problem:** PII in source text gets embedded into vectors. Similarity search can reconstruct original PII.

**Tasks:**
- [ ] Sanitize text before embedding generation
- [ ] Add metadata about sanitization to Qdrant payloads
- [ ] Evaluate: can embedding inversion attacks recover PII?
- [ ] Document what data exists in Qdrant and its sensitivity level

### 8.2 Qdrant Access Control

**Tasks:**
- [ ] Enable Qdrant API key authentication
- [ ] Restrict Qdrant access to gateway service only
- [ ] Add collection-level access policies
- [ ] Audit existing collections for PII content

### 8.3 Cache Security (Redis/Valkey)

**Problem:** Gateway caches may contain raw PII.

**Tasks:**
- [ ] Sanitize cached responses (or don't cache responses with PII)
- [ ] Set TTL on all cache entries containing LLM output
- [ ] Add cache flush endpoint for incident response
- [ ] Encrypt Redis at rest

### 8.4 SearXNG Query Sanitization

**Problem:** Search queries may contain PII from user prompts.

**Tasks:**
- [ ] Sanitize queries before sending to SearXNG
- [ ] Don't log raw search queries
- [ ] Evaluate SearXNG's own logging configuration

---

## 9. Layer 6: Observability Security

### 9.1 The Observability PII Problem

**Current data flow:**

```
Gateway -> Alloy (OTel collector) -> Loki/Tempo -> Grafana
                  |
                  v
          RAW PII IN LOGS AND TRACES
          Retained 30-90 days
          Searchable by anyone with access
```

### 9.2 Application-Level Sanitization (Primary Defense)

**Strategy:** Sanitize ALL data before it leaves the gateway process.

```python
# src/observability/sanitizing_logger.py
import logging

class PIISanitizingFilter(logging.Filter):
    def __init__(self, redactor):
        super().__init__()
        self.redactor = redactor

    def filter(self, record):
        if isinstance(record.msg, str):
            record.msg = self.redactor.redact(record.msg)
        if record.args:
            record.args = tuple(
                self.redactor.redact(str(a)) if isinstance(a, str) else a
                for a in record.args
            )
        return True

# Apply to all loggers
for name in logging.root.manager.loggerDict:
    logging.getLogger(name).addFilter(PIISanitizingFilter(redactor))
```

**Tasks:**
- [ ] Create `src/observability/sanitizing_logger.py`
- [ ] Replace all `logger.info(f"...")` with sanitized versions
- [ ] Add PII filter to all OTel span attributes before export
- [ ] Never log raw request bodies or response bodies
- [ ] Log redaction events (count of redactions, not content)

### 9.3 OTel Span Sanitization

```python
# src/observability/otel_sanitizer.py
from opentelemetry import trace

def sanitized_span(span, attributes, redactor):
    sanitized = {}
    for key, value in attributes.items():
        if isinstance(value, str) and any(
            tag in key for tag in ["llm.", "input", "output", "content", "message"]
        ):
            sanitized[key] = redactor.redact(value)
        else:
            sanitized[key] = value
    span.set_attributes(sanitized)
```

**Tasks:**
- [ ] Create OTel sanitizer middleware
- [ ] Wrap all `span.set_attributes()` calls
- [ ] Add to gateway's OTel instrumentation

### 9.4 Loki Ingestion Filtering

**Strategy:** Add pipeline stages to Loki/Promtail to catch PII that slips through application-level filtering.

```yaml
# Alloy/OTel processor configuration
processors:
  pii_redaction:
    # Regex-based PII stripping at collector level
    # This is the BACKSTOP, not the primary defense
```

**Tasks:**
- [ ] Add Alloy processing pipeline for PII redaction
- [ ] Add regex-based PII stripping as backstop
- [ ] Reduce retention for AI gateway logs to 7 days
- [ ] Encrypt Loki storage at rest

### 9.5 Grafana Access Controls

**Tasks:**
- [ ] Add RBAC to Grafana (viewer/editor/admin roles)
- [ ] Create sanitized dashboard views (no raw log display)
- [ ] Remove log details panels from AI-related dashboards
- [ ] Audit who has access to observability data

---

## 10. Layer 7: Supply Chain Security

### 10.1 Current Supply Chain Protections

The cluster already has strong supply chain controls:

| Control | Status | Coverage |
|---------|--------|----------|
| 7-day package cooldown (npm, bun, uv, pnpm) | Active | All package managers |
| Container image pinning (no `:latest`) | Active | All K8s deployments |
| K8s admission policy (deny `:latest`) | Active | Cluster-wide |
| Trivy image scanning | Active | Weekly scans |
| GitHub Actions SHA-pinned | Active | All CI workflows |
| Flake input age validation | Active | Auto-updates |

### 10.2 ML-Specific Supply Chain

**Tasks:**
- [ ] Pin model file hashes (GGUF SHA256 verification)
- [ ] Pin HuggingFace model revisions (not tags)
- [ ] Verify model card claims against actual behavior
- [ ] Audit transformer dependencies for vulnerabilities
- [ ] Pin Privacy Filter model version in Nix derivation
- [ ] Add `nix hash` verification to model download scripts

### 10.3 Dependency Audit

**Gateway dependencies to audit:**

| Dependency | Version | Risk |
|------------|---------|------|
| fastapi | Current | Standard web framework |
| uvicorn | Current | ASGI server |
| pydantic | Current | Input validation |
| httpx | Current | HTTP client (calls LLMs) |
| transformers | Current | Privacy Filter model loading |
| torch | Current | Privacy Filter inference |

**Tasks:**
- [ ] Run `pip-audit` or `safety check` on gateway dependencies
- [ ] Pin all dependency versions (no floating versions)
- [ ] Set up automated dependency scanning in CI
- [ ] Review transitive dependencies for known vulnerabilities

---

## 11. Compliance & Governance

### 11.1 Applicable Frameworks

| Framework | Applicability | Current Gap |
|-----------|--------------|-------------|
| **OWASP LLM Top 10** | Direct | LLM01, LLM02, LLM05 not addressed |
| **NIST AI RMF** | Best practice | No risk documentation |
| **HIPAA** | If PHI processed | PII in logs = violation |
| **GDPR** | If EU data processed | No data subject access process |
| **SOC 2 Type I** | If pursuing certification | No access controls on logs |

### 11.2 Governance Tasks

- [ ] Create data classification policy (what data is sensitive?)
- [ ] Document PII handling procedures
- [ ] Create data retention policy for observability
- [ ] Implement data deletion workflow (right to be forgotten)
- [ ] Document model safety evaluations
- [ ] Create incident response plan for PII leaks
- [ ] Quarterly review of ML security posture

### 11.3 Audit Trail Requirements

- [ ] Log all PII redaction events (what type, which endpoint, timestamp)
- [ ] Never log the original PII value
- [ ] Log model safety scores per request
- [ ] Log prompt injection detection results
- [ ] Log tool call sanitization events
- [ ] Maintain audit log for 90 days minimum

---

## 12. Monitoring, Alerting & Incident Response

### 12.1 Security Metrics

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| PII redactions per minute | Gateway logs | >10/min (anomaly) |
| Prompt injection attempts | Injection detector | >5/min (attack) |
| Tool call sanitization rate | Tool sanitizer | >0 (any leak) |
| Reasoning trace PII detected | Reasoning sanitizer | >0 (any leak) |
| Privacy Filter service errors | Health checks | >1 error in 5 min |
| Model safety score variance | Multi-run checks | Delta >0.3 between runs |

### 12.2 Alerting Rules

```yaml
# Prometheus alerting rules
groups:
  - name: mlsec
    rules:
      - alert: PIILeakDetected
        expr: pii_redaction_events_total{channel="output"} > 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "PII detected in LLM output"

      - alert: PromptInjectionAttempt
        expr: prompt_injection_detected_total > 5
        for: 1m
        labels:
          severity: warning

      - alert: PrivacyFilterDown
        expr: up{job="privacy-filter"} == 0
        for: 2m
        labels:
          severity: critical

      - alert: HighPIIRedactionRate
        expr: rate(pii_redaction_events_total[5m]) > 10
        labels:
          severity: warning
```

### 12.3 Incident Response Plan

**PII Leak Detection:**

1. **Alert fires** (PII detected in output/observability)
2. **Triage:** Is it a real leak or false positive?
3. **Contain:** Flush affected caches, quarantine logs
4. **Investigate:** Which request caused the leak? What data was involved?
5. **Remediate:** Fix filtering gap that allowed leak
6. **Report:** Document incident, update risk assessment
7. **Prevent:** Add test case for this leak pattern

**Model Compromise:**

1. **Detection:** Hash mismatch at load time OR anomalous behavior
2. **Contain:** Stop affected llama-server immediately
3. **Investigate:** How were weights modified? Network, supply chain, insider?
4. **Remediate:** Re-download from trusted source, verify hash
5. **Report:** Document incident, review supply chain controls
6. **Prevent:** Add additional integrity checks

### 12.4 Grafana Security Dashboards

**Tasks:**
- [ ] Create "ML Security" dashboard:
  - PII redaction rate by channel (chat/tool/reasoning)
  - Prompt injection attempt rate
  - Privacy Filter latency and error rate
  - Model safety scores over time
  - Top redacted PII types (by count, not content)
- [ ] Create "Privacy Filter" health dashboard:
  - Service availability
  - Inference latency
  - Cache hit rate
  - Entity type distribution
- [ ] Remove raw log access from all dashboards
- [ ] Add audit log for dashboard access

---

## 13. Implementation Roadmap

### Phase 1: Critical Fixes (Week 1) — ~15 hours

**Goal:** Eliminate the highest-risk gaps identified in research.

| # | Task | File(s) | Est. Time | Priority |
|---|------|---------|-----------|----------|
| 1.1 | Add `PrivacyFilterConfig` to gateway | `src/config.py` | 1h | P0 |
| 1.2 | Create privacy filter HTTP client | `src/privacy_filter_client.py` | 2h | P0 |
| 1.3 | Add output channel sanitization (all 3 channels) | `src/output/response_sanitizer.py` | 3h | P0 |
| 1.4 | Add tool call argument sanitizer | `src/output/tool_call_sanitizer.py` | 2h | P0 |
| 1.5 | Add reasoning trace sanitizer | `src/output/reasoning_sanitizer.py` | 1h | P0 |
| 1.6 | Wire sanitization into `/v1/chat/completions` | `src/main.py` | 2h | P0 |
| 1.7 | Add PII-aware logging filter | `src/observability/sanitizing_logger.py` | 2h | P0 |
| 1.8 | Fix port mismatch (privacy-filter 8080 vs 8081) | `kubernetes/modules/ai-inference.nix` | 0.5h | P0 |
| 1.9 | Basic test suite for sanitization | `tests/test_pii_sanitization.py` | 1.5h | P0 |

**Deliverable:** All LLM outputs filtered on all channels. No raw PII in logs.

### Phase 2: Input Security (Week 2) — ~12 hours

**Goal:** Filter inputs before they reach LLMs.

| # | Task | File(s) | Est. Time | Priority |
|---|------|---------|-----------|----------|
| 2.1 | Input PII sanitization middleware | `src/middleware/pii_input.py` | 3h | P0 |
| 2.2 | Apply to all LLM endpoints | `src/main.py` | 1h | P0 |
| 2.3 | Apply to embedding endpoint | `src/main.py` | 1h | P0 |
| 2.4 | Apply to search endpoints | `src/main.py` | 1h | P0 |
| 2.5 | Basic prompt injection detection (regex) | `src/prompt_injection_detector.py` | 2h | P1 |
| 2.6 | Rate limiting | `src/middleware/rate_limit.py` | 2h | P1 |
| 2.7 | Request validation | `src/middleware/validation.py` | 2h | P1 |

**Deliverable:** All inputs sanitized before reaching LLM. Basic injection detection.

### Phase 3: Observability Hardening (Week 3) — ~10 hours

**Goal:** Ensure observability stack contains zero PII.

| # | Task | File(s) | Est. Time | Priority |
|---|------|---------|-----------|----------|
| 3.1 | OTel span attribute sanitizer | `src/observability/otel_sanitizer.py` | 2h | P0 |
| 3.2 | Alloy/collector PII stripping pipeline | `kubernetes/modules/monitoring.nix` | 3h | P0 |
| 3.3 | Loki retention reduction (7 days) | `modules/services/monitoring.nix` | 1h | P1 |
| 3.4 | Loki encryption at rest | `modules/services/monitoring.nix` | 1h | P1 |
| 3.5 | Grafana RBAC and sanitized dashboards | Grafana config | 2h | P1 |
| 3.6 | Verify: query Loki for PII patterns | Manual testing | 1h | P0 |

**Deliverable:** Zero PII in observability. Verified by querying logs.

### Phase 4: Infrastructure Hardening (Week 4) — ~8 hours

**Goal:** Lock down network, RBAC, and service access.

| # | Task | File(s) | Est. Time | Priority |
|---|------|---------|-----------|----------|
| 4.1 | Complete network policies for all services | `kubernetes-manifests/security/` | 2h | P1 |
| 4.2 | llama-server network binding (LAN-only) | `modules/services/llama-server*.nix` | 1h | P1 |
| 4.3 | llama-server API key auth | `modules/services/llama-server*.nix` | 2h | P1 |
| 4.4 | Service account RBAC for AI services | K8s manifests | 2h | P1 |
| 4.5 | Secrets audit (no plaintext in ConfigMaps) | Manual audit | 1h | P1 |

**Deliverable:** Network-isolated AI services. No unauthorized access paths.

### Phase 5: Advanced Detection (Week 5-6) — ~15 hours

**Goal:** Move beyond regex to ML-based detection.

| # | Task | File(s) | Est. Time | Priority |
|---|------|---------|-----------|----------|
| 5.1 | Heuristic prompt injection scorer | `src/prompt_injection_detector.py` | 3h | P1 |
| 5.2 | Evaluate ML injection classifier | Research + prototype | 4h | P2 |
| 5.3 | Multi-run consensus for sensitive requests | `src/output/consensus.py` | 3h | P2 |
| 5.4 | Model safety scoring per request | `src/output/safety_scorer.py` | 2h | P2 |
| 5.5 | Prometheus alerting rules for MLsec | `monitoring rules` | 1h | P1 |
| 5.6 | Grafana ML Security dashboard | Grafana config | 2h | P1 |

**Deliverable:** ML-based detection. Automated alerting on security events.

### Phase 6: Supply Chain & Governance (Week 7-8) — ~10 hours

**Goal:** Complete supply chain verification and documentation.

| # | Task | File(s) | Est. Time | Priority |
|---|------|---------|-----------|----------|
| 6.1 | Model file hash catalog and verification | `scripts/verify-model-hashes.sh` | 2h | P2 |
| 6.2 | Dependency audit (pip-audit) | CI pipeline | 2h | P2 |
| 6.3 | Data classification policy | `docs/governance/` | 2h | P2 |
| 6.4 | PII incident response playbook | `docs/governance/` | 2h | P2 |
| 6.5 | Quarterly security review template | `docs/governance/` | 1h | P2 |
| 6.6 | Model safety evaluation checklist | `docs/governance/` | 1h | P2 |

**Deliverable:** Verified supply chain. Governance documentation.

### Phase 7: Validation & Testing (Ongoing)

| # | Task | Est. Time | Priority |
|---|------|-----------|----------|
| 7.1 | Multi-run PII test suite (5+ runs per test) | 4h | P0 |
| 7.2 | Tool call injection test scenarios | 2h | P0 |
| 7.3 | Reasoning trace leak scenarios | 2h | P0 |
| 7.4 | Observability PII scanning (query Loki) | 2h | P0 |
| 7.5 | Prompt injection adversarial testing | 3h | P1 |
| 7.6 | Performance benchmarking (latency impact) | 2h | P1 |
| 7.7 | Red team exercise | 4h | P2 |

---

## 14. Acceptance Criteria

### Phase 1 Acceptance (Critical)

- [ ] `/v1/chat/completions` applies PII filtering to chat content
- [ ] `/v1/chat/completions` applies PII filtering to `tool_calls.arguments`
- [ ] `/v1/chat/completions` applies PII filtering to `reasoning_content`
- [ ] Privacy Filter service is actively called by gateway (check logs)
- [ ] No raw PII in Python logging output
- [ ] Port mismatch between service and deployment resolved
- [ ] All sanitization tests pass (5+ runs each)

### Phase 2 Acceptance (Input Security)

- [ ] User messages sanitized before reaching LLM
- [ ] Embedding input text sanitized before vectorization
- [ ] Search queries sanitized before SearXNG
- [ ] Basic prompt injection detection active
- [ ] Rate limiting active on all endpoints

### Phase 3 Acceptance (Observability)

- [ ] Query Loki for SSN/email patterns: ZERO results
- [ ] Query Tempo for PII in span attributes: ZERO results
- [ ] Grafana dashboards show no raw PII
- [ ] OTel spans contain only sanitized data

### Full Plan Acceptance

- [ ] All P0 tasks complete
- [ ] All tests pass with multi-run validation
- [ ] No PII detectable in observability
- [ ] Network policies enforce isolation
- [ ] Supply chain verified (hash pinning)
- [ ] Governance documentation complete
- [ ] Incident response playbook tested

---

## 15. References

### Primary Research

1. **"The Safety Map: What Does and Doesn't Transfer in LLM Sensitive-Data Handling"**
   - Published: 2026-04-24
   - Key findings: Output channel dissociation, non-deterministic safety, 24B parameter floor
   - DOI: https://doi.org/10.5281/zenodo.19688433

### Standards & Frameworks

2. **OWASP LLM Top 10 (2025)**
   - LLM01: Prompt Injection
   - LLM02: Sensitive Information Disclosure
   - LLM05: Supply Chain Vulnerabilities
   - LLM06: Sensitive Data Disclosure (training)
   - https://genai.owasp.org/

3. **NIST AI Risk Management Framework (AI RMF)**
   - Govern, Map, Measure, Manage functions
   - https://www.nist.gov/artificial-intelligence

### Internal Documentation

4. **Gap Analysis:** `docs/PRIVACY-FILTER-GAP-ANALYSIS.md`
5. **Tool Call Security Research:** `docs/RESEARCH-TOOL-CALL-SECURITY.md`
6. **Reasoning Traces Research:** `docs/RESEARCH-REASONING-TRACES.md`
7. **Privacy Filter Research Summary:** `docs/PRIVACY-FILTER-RESEARCH-SUMMARY.md`
8. **Infrastructure Audit:** `INFRASTRUCTURE-AUDIT.md`
9. **Supply Chain Security:** `CLAUDE.md` (supply chain section)

### External Tools Evaluated

10. **CloakPipe** — Rust privacy proxy (<5ms, 33+ entity types)
    - https://github.com/rohansx/cloakpipe
11. **LLM Sentinel** — Go proxy (80+ PII types, injection protection)
    - https://github.com/raaihank/llm-sentinel
12. **OpenAI Privacy Filter** — 1.5B NER model (8 categories, Apache 2.0)
    - https://huggingface.co/openai/privacy-filter

---

## Appendix A: Current Configuration Audit

### Privacy Filter K8s Deployment

```nix
# kubernetes/modules/ai-inference.nix lines 2045-2170
# Service: ClusterIP, port 8080
# Deployment: privacy-filter-server container, port 8081
# BUG: Port mismatch (8080 vs 8081)
# Env vars: PRIVACY_FILTER_URL, PRIVACY_FILTER_ENABLED (set but unused)
```

### Gateway Configuration Gaps

```python
# src/config.py - MISSING:
# class PrivacyFilterConfig(BaseModel):
#     enabled: bool = False
#     url: str = "http://localhost:8081"
#     timeout: float = 5.0

# src/main.py - MISSING:
# - No PrivacyFilterConfig loaded
# - No input sanitization
# - No output sanitization
# - No tool call filtering
# - No reasoning trace filtering
```

### Existing Security Controls

```nix
# Already deployed:
# - 7-day package cooldown (npm, bun, uv, pnpm)
# - Container image pinning (no :latest)
# - K8s admission policy (deny :latest)
# - Trivy image scanning (weekly)
# - GitHub Actions SHA-pinned
# - Network policies (partial)
# - Pod Security Standards (partial)
# - Falco rules (deployed)
```

---

**Document Status:** Active plan
**Review Date:** 2026-05-01
**Next Action:** Begin Phase 1 implementation
