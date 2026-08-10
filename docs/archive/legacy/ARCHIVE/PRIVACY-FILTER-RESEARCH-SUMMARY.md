# Privacy Filter Research Summary (Compiled via SearXNG)

**Generated:** 2026-04-24
**Research Method:** Self-hosted SearXNG search + GitHub/doc analysis
**Scope:** LLM privacy filtering implementations & best practices

---

## Key Findings from Research

### 1. Existing Open Source Solutions

Your research identified **3 production-ready privacy proxies** you could deploy alongside or instead of your custom implementation:

| Solution | Language | Features | Deployment |
|----------|----------|----------|------------|
| **CloakPipe** | Rust | <5ms latency, 33+ entity types, 91.7% protection | Docker: `ghcr.io/cloakpipe/cloakpipe:latest` |
| **LLM Sentinel** | Go | 80+ PII types, prompt injection protection, WebSocket monitoring | `docker-compose up --build` |
| **Universal LLM Safeguard** | Python | Plug-and-play middleware, Trinity project framework | `pip install universal-llm-safeguard` |

### 2. Industry Standards (OWASP GenAI)

**OWASP LLM02:2025 - Sensitive Information Disclosure**
- **Vulnerability:** LLMs leak PII, financial details, health records, credentials
- **Risk Categories:** Training data leakage, unintended PII exposure, context leakage
- **Prevention:**
  - Sanitize inputs before LLM processing
  - Implement data loss prevention (DLP) filters
  - Use anonymization/pseudonymization
  - Apply output validation and redaction

### 3. Tool/Function Calling Security

**Key Vulnerability:**
> "LLMs are given access to tools or functions that they can call without proper validation, enabling code execution, data access, or system manipulation."

**Attack Vector:**
```
User: "Send the audit results to compliance"
LLM: Calls send_email({body: "Customer SSN: 123-45-6789..."})
Result: PII exfiltrated via tool arguments
```

**Mitigation Strategies:**
1. **Validate all tool call arguments** before execution
2. **Sanitize PII from arguments** using regex + ML filters
3. **Allow-list only safe functions**
4. **Implement human approval** for sensitive operations

### 4. Observability Security (LangSmith Guidance)

**LangSmith "Prevent logging of sensitive data":**
- Mask inputs/outputs before sending to observability
- Use `mask_inputs_outputs` middleware
- Implement shared responsibility model for data protection

**Your Risk:**
- Loki logs contain raw LLM reasoning traces
- Tempo traces have unfiltered span attributes
- Grafana dashboards display PII in logs

---

## Comparison: Your Implementation vs Research Findings

### Your Current Stack

```
┌─────────────────────────────────────────────────────────────┐
│  Your AI Gateway                                           │
├─────────────────────────────────────────────────────────────┤
│  ✅ Regex PII redactor (8 patterns)                         │
│  ✅ OpenAI Privacy Filter deployed (unused)                 │
│  ❌ No input filtering on LLM endpoints                     │
│  ❌ No output filtering on any channel                      │
│  ❌ No tool call sanitization                               │
│  ❌ No reasoning trace filtering                            │
│  ❌ No observability sanitization                           │
└─────────────────────────────────────────────────────────────┘
```

### Research-Based Best Practices

```
┌─────────────────────────────────────────────────────────────┐
│  Recommended Architecture (from research)                   │
├─────────────────────────────────────────────────────────────┤
│  1. INPUT LAYER                                             │
│     ├─ Detect & mask PII before LLM                         │
│     └─ Validate & sanitize tool call arguments              │
│                                                             │
│  2. OUTPUT LAYER                                            │
│     ├─ Chat response → Filtered                            │
│     ├─ Tool calls → Arguments sanitized                    │
│     └─ Reasoning traces → Filtered before logging          │
│                                                             │
│  3. OBSERVABILITY LAYER                                     │
│     └─ Only sanitized data reaches Loki/Tempo               │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Recommendations (Based on Research)

### Option A: Integrate OpenAI Privacy Filter (Your Current Path)

**Pros:**
- Already deployed in your cluster
- Apache 2.0 licensed
- 8 PII categories
- 128K token context

**Cons:**
- Not integrated into gateway
- Requires custom middleware development
- Lacks context-based PII understanding

**Effort:** 10-15 hours development

### Option B: Deploy CloakPipe (Research Finding)

**Pros:**
- Production-ready, <5ms latency
- 33+ entity types (vs your 8 regex patterns)
- OpenAI-compatible drop-in replacement
- Battle-tested (91.7% protection)

**Cons:**
- External dependency (Rust-based)
- Another service to maintain
- May need customization for your K8s setup

**Effort:** 2-3 hours deployment

**Deployment:**
```bash
# Add to your K8s manifests
docker run -p 3100:3100 ghcr.io/cloakpipe/cloakpipe:latest

# Point AI Gateway to CloakPipe
OPENAI_BASE_URL=http://cloakpipe.ai-inference.svc.cluster.local:3100/v1
```

### Option C: Deploy LLM Sentinel (Research Finding)

**Pros:**
- 80+ PII types
- Prompt injection protection
- WebSocket monitoring dashboard
- Multi-provider support

**Cons:**
- Another service to run
- Less mature than CloakPipe

**Effort:** 2-3 hours deployment

### Option D: Hybrid (Recommended)

```
┌─────────────────────────────────────────────────────────────┐
│  HYBRID ARCHITECTURE                                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Layer 1: CloakProxy (input sanitization)                   │
│           ↓                                                 │
│  Layer 2: OpenAI Privacy Filter (output filtering)          │
│           ↓                                                 │
│  Layer 3: Regex redactor (final safety net)                 │
│                                                             │
│  All layers feed into observability sanitization            │
└─────────────────────────────────────────────────────────────┘
```

**Benefits:**
- Defense in depth (multiple filtering layers)
- Leverages your existing OpenAI Privacy Filter deployment
- Battle-tested CloakPipe for input sanitization
- Regex as final safety net

---

## Specific Implementation Tasks (Prioritized)

### P0: Critical Security Gaps

1. **Tool Call Sanitization** (2-3 hours)
   ```python
   # In src/main.py
   def sanitize_tool_calls(tool_calls, pii_filter):
       for call in tool_calls:
           args = json.loads(call["function"]["arguments"])
           sanitized = recursively_sanitize(args, pii_filter)
           call["function"]["arguments"] = json.dumps(sanitized)
       return tool_calls
   ```

2. **Reasoning Trace Filtering** (1-2 hours)
   ```python
   # Before returning response
   if "reasoning_content" in response:
       response["reasoning_content"] = pii_filter.redact(
           response["reasoning_content"]
       )
   ```

3. **Observability Sanitization** (2-3 hours)
   ```python
   # In logging/OTel exporter
   def sanitize_span(span):
       for attr in span.attributes:
           if attr.startswith("llm."):
               span.attributes[attr] = pii_filter.redact(
                   span.attributes[attr]
               )
   ```

### P1: Integration Work

4. **Connect Privacy Filter Service** (2-3 hours)
   - Add `PrivacyFilterConfig` to `src/config.py`
   - Create HTTP client to call `http://privacy-filter:8081/filter`
   - Add middleware to all LLM endpoints

5. **Input Filtering Middleware** (2-3 hours)
   ```python
   @app.middleware("http")
   async def pii_middleware(request, call_next):
       # Filter input body
       # Call next handler
       # Filter output body
       return response
   ```

### P2: Testing & Validation

6. **Multi-Run Test Suite** (3-4 hours)
   - Test each PII category 5+ times
   - Test tool call injection scenarios
   - Test reasoning trace leaks
   - Verify observability sanitization

---

## Action Items for Your Cluster

### Immediate (This Week)

- [ ] Choose implementation path (A: Integrate existing, B: Deploy CloakPipe, C: Hybrid)
- [ ] Implement tool call sanitization (P0)
- [ ] Implement reasoning trace filtering (P0)
- [ ] Test with PII-loaded prompts

### This Month

- [ ] Deploy full input/output filtering pipeline
- [ ] Implement observability sanitization
- [ ] Create multi-run test suite
- [ ] Document PII handling for compliance

### Ongoing

- [ ] Monitor for new research (OWASP GenAI updates)
- [ ] Re-evaluate models on every update
- [ ] Regular PII scanning of observability data
- [ ] Maintain gap analysis document

---

## Research Sources

### Primary Sources (via SearXNG)

1. **OWASP GenAI Project**
   - https://genai.owasp.org/llmrisk/llm022025-sensitive-information-disclosure/
   - LLM02: Sensitive Information Disclosure

2. **CloakPipe Privacy Middleware**
   - https://github.com/rohansx/cloakpipe
   - Rust-based privacy proxy, <5ms latency

3. **LLM Sentinel**
   - https://github.com/raaihank/llm-sentinel
   - Go-based proxy with PII detection + prompt injection protection

4. **Universal LLM Safeguard**
   - https://github.com/HAAIL-Universe/universal-llm-safeguard
   - Python plug-and-play middleware

5. **LangChain Guardrails**
   - https://docs.langchain.com/oss/python/langchain/guardrails
   - Built-in middleware for sensitive operations

6. **Sourcery AI Security**
   - https://www.sourcery.ai/security/categories/insecure_tool_calls
   - Tool use vulnerability documentation

7. **"The Safety Map" Research**
   - DOI: https://doi.org/10.5281/zenodo.19688433
   - Output channel dissociation findings

### Secondary Sources

8. **OpenAI o1 System Card**
   - https://openai.com/index/openai-o1-system-card/
   - Reasoning trace security considerations

9. **Kong AI Gateway PII Sanitization**
   - https://konghq.com/blog/enterprise/building-pii-sanitization-for-llms-and-agentic-ai
   - Enterprise implementation patterns

10. **Blue Prism AI Gateway PII**
    - https://www.blueprism.com/resources/blog/ai-gateway-pii-sanitization/
    - Agentic AI protection strategies

---

## Conclusion

Your cluster has **strong foundations** (OpenAI Privacy Filter deployed, regex redactor built) but **critical integration gaps**. Research shows:

1. **Tool call and reasoning trace filtering** are the highest-risk vulnerabilities
2. **Observability sanitization** is often overlooked but critical for compliance
3. **Existing solutions** (CloakPipe, LLM Sentinel) can accelerate deployment
4. **Defense in depth** (multiple filtering layers) is the industry best practice

**Recommendation:** Start with P0 tasks (tool call + reasoning sanitization) this week, then decide on integration path (A vs B vs C) based on your team's capacity and risk tolerance.

---

**Document Status:** Complete (via SearXNG research)
**Next Review:** 2026-05-01
**Owner:** j_kro
