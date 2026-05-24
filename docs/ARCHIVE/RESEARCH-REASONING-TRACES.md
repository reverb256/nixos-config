# Reasoning Traces & Observability Security Research

**Topic:** LLM Reasoning/Chain-of-Thought Privacy & Observability Sanitization
**Generated:** 2026-04-24
**Context:** AI Gateway observability configuration

---

## Research Summary

### The Problem

Modern LLMs (OpenAI o1/o3, Anthropic with extended thinking) expose **reasoning traces** - their internal chain-of-thought process. These traces often contain **more PII than the final answer**.

**From "The Safety Map" Research:**
> "Of 43 runs where the provider populated `reasoning_content`, 29 leaked sensitive values into reasoning while the chat response was classified SAFE. The model thinks out loud: 'Looking at row 47, I see John Martinez with SSN 123-45-6789. This is PII and should be flagged.' Then in the final answer it says 'Row 47 contains PII that should be redacted.' The chat response is perfect. The reasoning trace has the values."

### Why This Matters

```
┌─────────────────────────────────────────────────────────────┐
│  USER ASKS: "Summarize this medical record"                 │
│                                                              │
│  REASONING TRACE (internal, logged to observability):        │
│  "Looking at patient John Smith, DOB 1985-03-15,            │
│   diagnosed with Type 2 Diabetes in 2019.                   │
│   Current medications: Metformin 500mg.                     │
│   I should redact the name and DOB from the summary."        │
│  ❌ LEAKED: Name, DOB, diagnosis, medication                 │
│                                                              │
│  CHAT RESPONSE (visible to user):                            │
│  "This record contains a patient with Type 2 Diabetes        │
│   diagnosed in 2019, currently on Metformin."                │
│  ✅ CLEAN: Name and DOB redacted                            │
│                                                              │
│  OBSERVABILITY STACK (Loki, Tempo, Grafana):                │
│  ❌ Stores raw reasoning trace with full PII                 │
│  ❌ Searchable by anyone with log access                     │
│  ❌ Retained for 30-90 days (default)                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Reasoning Trace Formats

### OpenAI o1/o3 Format

```python
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "Final answer here",  # Filtered
    },
    "reasoning_content": "Step-by-step thinking process with PII",  # NOT FILTERED
  }]
}
```

### Anthropic Extended Thinking

```python
{
  "id": "msg_abc123",
  "type": "message",
  "content": [
    {"type": "thinking", "text": "Internal reasoning with PII"},  # NOT FILTERED
    {"type": "text", "text": "Final answer"}  # Filtered
  ]
}
```

### DeepSeek R1

```python
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "<think>Reasoning with PII here</think>\n\nFinal answer"
    }
  }]
}
```

---

## Observability Stack Vulnerabilities

### Your Current Configuration

```nix
# modules/services/monitoring.nix
services.grafana.enable = true;
services.loki.enable = true;
services.prometheus.enable = true;
services.alloy.enable = true;  # OTel collector

# Alloy sends traces to Tempo
# Logs go to Loki
# NO PII sanitization configured
```

### Data Flow (Current - Insecure)

```
┌─────────────┐
│ AI Gateway  │
└──────┬──────┘
       │
       ├─→ Chat Response → User (filtered)
       │
       ├─→ Tool Calls → External API (filtered)
       │
       ├─→ Reasoning Trace → Loki/Tempo (RAW - NOT FILTERED) ❌
       │
       └─→ Metrics → Prometheus (aggregated, safer)
```

### What Gets Logged

| Component | Data Logged | PII Risk |
|-----------|-------------|----------|
| **Loki** | Request/response bodies, traces | CRITICAL |
| **Tempo** | Span attributes, headers, payloads | CRITICAL |
| **Grafana** | Displays logs/traces from Loki/Tempo | CRITICAL |
| **Prometheus** | Metrics (counts, timings) | LOW (aggregated) |

---

## Sanitization Strategy

### 1. Filter Before Logging

```python
import logging

class PIISanitizingFilter(logging.Filter):
    """Sanitize PII from log records."""

    def __init__(self, pii_filter):
        super().__init__()
        self.pii_filter = pii_filter

    def filter(self, record):
        # Sanitize the log message
        if isinstance(record.msg, str):
            record.msg = self.pii_filter.redact(record.msg)

        # Sanitize extra fields
        if hasattr(record, 'model_output'):
            record.model_output = self.sanitize_output(
                record.model_output
            )

        return True

    def sanitize_output(self, output):
        """Sanitize all output channels in model response."""
        if isinstance(output, dict):
            sanitized = {}
            for key, value in output.items():
                if key in ["content", "reasoning_content"]:
                    sanitized[key] = self.pii_filter.redact(value)
                elif key == "tool_calls":
                    sanitized[key] = [
                        self.sanitize_tool_call(tc)
                        for tc in value
                    ]
                else:
                    sanitized[key] = value
            return sanitized
        return output

# Configure logging
logger = logging.getLogger(__name__)
logger.addFilter(PIISanitizingFilter(pii_filter))
```

### 2. OTel Span Sanitization

```python
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

def sanitize_span_attributes(attributes, pii_filter):
    """Sanitize PII from span attributes."""
    sanitized = {}
    for key, value in attributes.items():
        if key in ["llm.request.messages", "llm.response.content"]:
            # Sanitize message content
            sanitized[key] = pii_filter.redact(value)
        elif key == "llm.response.reasoning":
            # CRITICAL: Sanitize reasoning traces
            sanitized[key] = pii_filter.redact(value)
        else:
            sanitized[key] = value
    return sanitized

# In your tracer
tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("llm.request") as span:
    # Set attributes (sanitized)
    span.set_attributes(
        sanitize_span_attributes({
            "llm.request.messages": str(messages),
            "llm.model": model_name,
        }, pii_filter)
    )

    # ... LLM call ...

    # Sanitize response before logging
    span.set_attributes(
        sanitize_span_attributes({
            "llm.response.content": response.content,
            "llm.response.reasoning": response.reasoning_content,
        }, pii_filter)
    )
```

### 3. Middleware Pattern

```python
from fastapi import Request
import json

async def sanitize_observability_middleware(
    request: Request,
    call_next
):
    """Sanitize all data before it reaches observability."""

    response = await call_next(request)

    # If response contains reasoning, sanitize it
    if hasattr(response, 'body'):
        body = json.loads(response.body)

        # Sanitize reasoning traces
        if "reasoning_content" in body:
            body["reasoning_content"] = pii_filter.redact(
                body["reasoning_content"]
            )

        # Re-encode
        response.body = json.dumps(body).encode()

    return response

# Add to FastAPI app
app.middleware("http")(sanitize_observability_middleware)
```

---

## Configuration for Your Stack

### Loki (Promtail Configuration)

```yaml
# promtail/config.yml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: ai-gateway
    pipeline_stages:
      # PII SANITIZATION STAGE
      - regex:
          expression: '(?P<pii_content>.*)'  # Match all content

      - template:
          source: pii_content
          template: '{{ regex_replace_all "\\b\\d{3}-\\d{2}-\\d{4}\\b" .Value "[SSN]" }}'
          # Add more regex patterns for email, phone, etc.

      - labels:
          job: ai-gateway
          component: gateway
```

### Tempo (OTel Configuration)

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
      http:

processors:
  batch:
  # PII SANITIZATION PROCESSOR
  pii_sanitizer:
    # Custom processor or use attributes processor
    attributes:
      # Redact reasoning content
      - action: update
        key: llm.response.reasoning
        value: "[REDACTED]"
      # Or use regex to redact patterns
      - action: regex
        pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b"
        replacement: "[SSN]"

exporters:
  otlp:
    endpoint: tempo:4317

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, pii_sanitizer]  # Add sanitization
      exporters: [otlp]
```

### Grafana Dashboard Queries

**WARNING:** Dashboards can still expose PII if they query raw logs. Use filtered queries:

```promql
# BAD - Shows raw content
{job="ai-gateway"} |= "content"

# GOOD - Shows only filtered content
{job="ai-gateway"} |= "[REDACTED]"
```

---

## Compliance Considerations

### HIPAA (Health Insurance Portability and Accountability Act)

**Requirement:** PHI must be secured at rest and in transit.

**Your Risk:**
```
PHI in reasoning traces → Loki (unencrypted at rest) → Violation
PHI in Tempo traces → Retained 90 days → Violation
PHI in Grafana dashboards → Accessible to admins → Violation
```

**Solution:**
- Encrypt Loki storage
- Shorten retention (7 days for PHI)
- Sanitize before ingestion
- Role-based access control

### GDPR (General Data Protection Regulation)

**Requirement:** EU personal data must be protected.

**Your Risk:**
```
EU user data in traces → Logged in US-region Loki → Violation
Data retained >30 days → Violation
No data subject access request (DSAR) process → Violation
```

**Solution:**
- Sanitize PII before logging
- Use EU-hosted observability for EU users
- Implement data deletion workflow
- Document data processing

### SOC 2 / ISO 27001

**Requirement:** Access controls, logging, monitoring.

**Your Risk:**
```
Logs contain PII → Anyone with log access sees PII → Violation
No audit trail of who accessed logs → Violation
```

**Solution:**
- Role-based access for observability
- Audit log access
- Sanitize logs before storage

---

## Testing Strategy

### Test Cases

```python
# Test 1: Reasoning trace with SSN
response = {
    "content": "Record contains PII",
    "reasoning_content": "SSN 123-45-6789 found in row 47"
}
# Expected: reasoning_content contains [SSN]

# Test 2: Multi-step reasoning with PHI
response = {
    "content": "Patient has Type 2 Diabetes",
    "reasoning_content": """
    Patient John Smith (DOB: 1985-03-15) has
    Type 2 Diabetes diagnosed in 2019.
    Current meds: Metformin 500mg.
    """
}
# Expected: All PII redacted from reasoning

# Test 3: Tool call + reasoning
response = {
    "content": "Email sent",
    "tool_calls": [{"arguments": '{"body": "John SSN: 123-45-6789"}'}],
    "reasoning_content": "Notifying compliance about John's SSN"
}
# Expected: Both tool_calls and reasoning_content sanitized

# Test 4: Observability doesn't receive PII
# Check Loki logs - should contain [REDACTED] not actual values
# Check Tempo traces - span attributes should be sanitized
```

### Multi-Run Testing

Per research:
- Run each test **5 times**
- Non-deterministic models leak inconsistently
- Any leak = failure

---

## Implementation Checklist

### Phase 1: Basic Sanitization

- [ ] Add `PIISanitizingFilter` to Python logging
- [ ] Sanitize `reasoning_content` before returning to client
- [ ] Add middleware to filter all responses

### Phase 2: Observability Integration

- [ ] Configure Loki to sanitize logs at ingestion
- [ ] Configure Tempo to sanitize span attributes
- [ ] Add OTel processor for PII filtering

### Phase 3: Compliance

- [ ] Implement log encryption at rest
- [ ] Shorten retention for sensitive logs (7 days)
- [ ] Add RBAC for observability access
- [ ] Document data processing for GDPR/HIPAA

### Phase 4: Monitoring

- [ ] Alert on PII detection in logs
- [ ] Audit log access
- [ ] Regular PII scanning of observability data

---

## Best Practices

### DO ✅

1. **Sanitize at the source**
   ```python
   # Filter as soon as data enters your system
   filtered_input = pii_filter.redact(user_input)
   ```

2. **Filter all output channels**
   ```python
   for channel in ["content", "reasoning", "tool_calls"]:
       response[channel] = pii_filter.redact(response[channel])
   ```

3. **Use structured logging with sanitization**
   ```python
   logger.info("Response", extra={
       "response": pii_filter.redact(response_dict)
   })
   ```

4. **Test observability directly**
   ```python
   # Check Loki for PII
   loki_query = '{job="ai-gateway"} |= "\\d{3}-\\d{2}-\\d{4}"'
   # Should return 0 results
   ```

### DON'T ❌

1. **Don't log before sanitizing**
   ```python
   # WRONG - PII in logs
   logger.info(f"User said: {user_input}")
   llm.process(user_input)
   ```

2. **Don't forget reasoning traces**
   ```python
   # WRONG - Reasoning not filtered
   response = {
       "content": pii_filter.redact(content),
       "reasoning_content": reasoning  # ❌ Raw PII
   }
   ```

3. **Don't trust observability defaults**
   ```python
   # WRONG - Default retention may be 90 days
   # Should be 7 days for PII
   ```

4. **Don't ignore nested structures**
   ```python
   # WRONG - Only filters top-level
   def bad_filter(obj):
       return {k: redact(v) for k, v in obj.items()}
   ```

---

## References

1. **"The Safety Map" Research**
   - DOI: https://doi.org/10.5281/zenodo.19688433
   - Section: "Output Channel Dissociation"

2. **OpenAI o1 API Documentation**
   - https://platform.openai.com/docs/guides/reasoning
   - Reasoning format and best practices

3. **Grafana Loki Documentation**
   - https://grafana.com/docs/loki/latest/
   - Log sanitization pipeline stages

4. **OpenTelemetry Documentation**
   - https://opentelemetry.io/docs/
   - Span attribute sanitization

5. **HIPAA Security Rule**
   - 45 CFR § 164.312(a)(1)
   - Encryption and access controls

---

**Status:** Research complete, implementation pending
**Priority:** P0 (CRITICAL)
