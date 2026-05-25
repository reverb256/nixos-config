# Tool Call Security Research

**Topic:** LLM Tool/Function Calling Security & PII Sanitization
**Generated:** 2026-04-24
**Context:** AI Gateway tool call filtering requirements

---

## Research Summary

### The Problem

When LLMs generate function/tool calls, they populate the `arguments` field with structured data. **This field is NOT filtered by standard content filters** and can exfiltrate sensitive data.

**From "The Safety Map" Research:**
> "Of 73 runs that populated `tool_calls.arguments`, 20 exfiltrated sensitive values through that channel. The chat response reads 'I've identified three flagged records and scheduled a notification.' Clean. Meanwhile the tool-call payload reads `{'to': 'compliance@example.com', 'body': 'Customer John Martinez, SSN 123-45-6789, flagged...'}`"

### Attack Vector

```
┌─────────────────────────────────────────────────────────────┐
│  USER ASKS: "Audit this file for PII exposure"              │
│                                                              │
│  LLM THINKS: "I found SSNs. I should notify compliance."    │
│                                                              │
│  CHAT RESPONSE (visible to user):                            │
│  "I found 5 records with PII. A notification was sent."      │
│  ✅ CLEAN - No sensitive data exposed                        │
│                                                              │
│  TOOL CALL (invisible to user, sent to external API):        │
│  {                                                            │
│    "function": "send_email",                                 │
│    "arguments": {                                            │
│      "to": "compliance@company.com",                         │
│      "body": "Found SSN 123-45-6789 for John Doe, SSN       │
│               987-65-4321 for Jane Smith..."                 │
│    }                                                          │
│  }                                                            │
│  ❌ LEAKED - Full PII sent to external service               │
└─────────────────────────────────────────────────────────────┘
```

---

## OpenAI Tool Call Format

```python
{
  "id": "call_abc123",
  "type": "function",
  "function": {
    "name": "send_email",
    "arguments": '{"to": "user@example.com", "body": "SSN: 123-45-6789"}'
  }
}
```

**Key Points:**
- `arguments` is a **JSON string**, not a dict
- Must parse → inspect → sanitize → re-serialize
- Arguments can be **nested objects** (recursive inspection needed)

---

## Sanitization Strategy

### 1. Parse and Inspect

```python
import json

def sanitize_tool_call(tool_call, pii_filter):
    """Sanitize a single tool call."""
    function_name = tool_call["function"]["name"]
    arguments_str = tool_call["function"]["arguments"]

    # Parse JSON
    try:
        arguments = json.loads(arguments_str)
    except json.JSONDecodeError:
        # Invalid JSON - return as-is or log error
        return tool_call

    # Recursively sanitize all string values
    sanitized = sanitize_dict(arguments, pii_filter)

    # Re-serialize
    tool_call["function"]["arguments"] = json.dumps(sanitized)
    return tool_call

def sanitize_dict(obj, pii_filter, max_depth=10):
    """Recursively sanitize dict/list values."""
    if max_depth <= 0:
        return obj  # Prevent infinite recursion

    if isinstance(obj, dict):
        return {
            k: sanitize_dict(v, pii_filter, max_depth - 1)
            for k, v in obj.items()
        }
    elif isinstance(obj, list):
        return [
            sanitize_dict(item, pii_filter, max_depth - 1)
            for item in obj
        ]
    elif isinstance(obj, str):
        # Apply PII filter
        return pii_filter.redact(obj)
    else:
        return obj  # Numbers, bools, None
```

### 2. Apply to All Tool Calls

```python
def sanitize_response(response, pii_filter):
    """Sanitize all output channels in LLM response."""
    # Sanitize chat content
    if "content" in response:
        response["content"] = pii_filter.redact(response["content"])

    # Sanitize tool calls
    if "tool_calls" in response:
        response["tool_calls"] = [
            sanitize_tool_call(tc, pii_filter)
            for tc in response["tool_calls"]
        ]

    # Sanitize reasoning traces (if present)
    if "reasoning_content" in response:
        response["reasoning_content"] = pii_filter.redact(
            response["reasoning_content"]
        )

    return response
```

---

## Implementation Checklist

### Required Filters

| Data Type | Example | Filter Required |
|-----------|---------|-----------------|
| Email addresses | `user@example.com` | Regex + Privacy Filter |
| Phone numbers | `555-123-4567` | Regex + Privacy Filter |
| SSNs | `123-45-6789` | Regex + Privacy Filter |
| Names | `John Doe` | Privacy Filter only |
| Addresses | `123 Main St` | Privacy Filter only |
| Dates | `1985-03-15` | Privacy Filter only |
| URLs | `https://example.com` | Regex + Privacy Filter |
| API keys | `sk-...1234` | Regex (high entropy) |
| Account numbers | `ACC-123456` | Privacy Filter |

### Edge Cases

1. **Nested objects**: Must recurse infinitely (with depth limit)
2. **Arrays of strings**: Each element needs filtering
3. **Mixed types**: Objects with strings + numbers + bools
4. **Empty values**: `null`, `""`, `[]` - handle gracefully
5. **Malformed JSON**: Log error, don't crash

---

## Testing Strategy

### Test Cases

```python
# Test 1: Simple string argument
{
    "function": "send_email",
    "arguments": '{"body": "Call John at 555-123-4567"}'
}
# Expected: body contains [PHONE] not the number

# Test 2: Nested object
{
    "function": "create_record",
    "arguments": '{"user": {"name": "Jane Doe", "contact": "jane@example.com"}}'
}
# Expected: Both name and email redacted

# Test 3: Array of strings
{
    "function": "bulk_notify",
    "arguments": '{"emails": ["user1@example.com", "user2@example.com"]}'
}
# Expected: All emails redacted

# Test 4: Mixed types
{
    "function": "log_event",
    "arguments": '{"count": 5, "message": "User John Smith logged in", "active": true}'
}
# Expected: Only message filtered, count/active preserved
```

### Multi-Run Testing

Per research recommendations:
- Run each test **5 times**
- Any leak = failure
- Models can be non-deterministic

---

## Best Practices

### DO ✅

1. **Filter before tool execution**
   ```python
   sanitized_calls = sanitize_tool_calls(calls, filter)
   execute_tool_calls(sanitized_calls)
   ```

2. **Log filtered versions**
   ```python
   logger.info(f"Tool call: {sanitize_for_log(tool_call)}")
   ```

3. **Validate JSON structure**
   ```python
   try:
       args = json.loads(call["arguments"])
   except JSONDecodeError:
       logger.error("Invalid tool call JSON")
       return error_response()
   ```

4. **Use allow-listed functions**
   ```python
   ALLOWED_FUNCTIONS = {"send_email", "query_database", "get_weather"}
   if call["function"]["name"] not in ALLOWED_FUNCTIONS:
       raise ValueError("Function not allowed")
   ```

### DON'T ❌

1. **Don't filter after tool execution**
   ```python
   # WRONG - Tool already received PII
   execute_tool_calls(calls)
   sanitize_tool_calls(calls)  # Too late!
   ```

2. **Don't trust LLM-generated arguments**
   ```python
   # WRONG - No validation
   send_email(**json.loads(call["arguments"]))
   ```

3. **Don't forget nested structures**
   ```python
   # WRONG - Only filters top-level strings
   def bad_filter(args):
       return {k: filter(v) if isinstance(v, str) else v}
   ```

4. **Don't log raw arguments**
   ```python
   # WRONG - PII in logs
   logger.info(f"Executing tool with args: {arguments}")
   ```

---

## Integration with AI Gateway

### Current State (Your Gateway)

```python
# src/main.py - Chat completion handler
@app.post("/v1/chat/completions")
async def chat_completion(request: ChatCompletionRequest):
    # ... LLM call ...

    response_data = {
        "choices": [{
            "message": {
                "content": final_content,
                "tool_calls": tool_calls  # ❌ NOT SANITIZED
            }
        }]
    }
    return response_data  # ❌ Returns raw PII
```

### Required Changes

```python
# Add privacy middleware
@app.post("/v1/chat/completions")
async def chat_completion(request: ChatCompletionRequest):
    # Filter INPUT
    filtered_messages = filter_pii(request.messages)

    # ... LLM call ...

    # Filter OUTPUT (all channels)
    response_data = {
        "choices": [{
            "message": {
                "content": filter_pii(final_content),
                "tool_calls": [
                    sanitize_tool_call(tc, pii_filter)
                    for tc in tool_calls
                ],
                "reasoning_content": filter_pii(reasoning) if reasoning else None
            }
        }]
    }

    # Log sanitized version only
    logger.info(f"Response: {sanitize_for_log(response_data)}")

    return response_data
```

---

## References

1. **OpenAI Function Calling**
   - https://platform.openai.com/docs/guides/function-calling
   - Tool call format and best practices

2. **"The Safety Map" Research**
   - DOI: https://doi.org/10.5281/zenodo.19688433
   - Section: "Output Channel Dissociation"

3. **OWASP LLM Top 10**
   - https://owasp.org/www-project-top-10-for-large-language-model-applications/
   - Prompt injection via tool calls

---

**Status:** Research complete, implementation pending
**Priority:** P0 (CRITICAL)
