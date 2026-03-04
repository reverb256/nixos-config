# ZAI 401 Root Cause Analysis

**Date**: 2026-03-04
**Status**: 🔍 Root Cause Identified | ✅ Solution Proposed

## Problem Summary

Gateway returns 401 Unauthorized when calling ZAI, even though:
- Direct curl with same API key works perfectly ✅
- OpenCode can successfully use ZAI ✅
- Gateway configuration is correct ✅

## Root Cause

**The streaming response path is NOT using the failover logic!**

Looking at the code:

1. `/v1/chat/completions` endpoint checks `stream = body.get("stream", False)`
2. If `stream=True` → uses `stream_backend_response()`
3. If `stream=False` → uses `handle_non_streaming_request()` which calls `try_backends_with_failover()`

**The problem**: `stream_backend_response()` (lines 471-534):
- Does NOT use `try_backends_with_failover()`
- Directly connects to backend: `client.stream("POST", f"{backend_url}/v1/chat/completions", ...)`
- Does NOT handle ZAI endpoint format differences (`/chat/completions` vs `/v1/chat/completions`)
- Does NOT try fallback backends

## Secondary Finding

**User-Agent header IS being preserved correctly!**

The `build_backend_headers()` function (lines 62-99):
- Excludes: `host`, `content-length`, `content-encoding`, `transfer-encoding`
- **PRESERVES**: `user-agent` and all other client headers

So User-Agent was never the issue.

## Actual Issues

### Issue 1: Streaming Path Missing Failover
`stream_backend_response()` directly connects to primary backend:
```python
async with client.stream(
    "POST", f"{backend_url}/v1/chat/completions", json=body, headers=headers
) as response:
```

This means:
- Never tries ZAI fallback
- Never applies ZAI endpoint path normalization
- Should use `try_backends_with_failover()` instead

### Issue 2: ZAI URL Path Format
ZAI uses `/chat/completions` not `/v1/chat/completions`:

The failover logic handles this (line 598):
```python
if backend_api_type == "zai":
    zai_endpoint = endpoint.replace("/v1/", "/") if endpoint.startswith("/v1/") else endpoint
    url = f"{backend_url}{zai_endpoint}"
```

But streaming path hardcodes `/v1/chat/completions`, breaking ZAI.

## Solutions

### Option 1: Fix Streaming Path (Quick Fix)
Update `stream_backend_response()` to use failover:

```python
async def stream_backend_response(
    backend_url: str,  # This parameter becomes unused
    body: dict,
    headers: dict,
    pipeline: MiddlewarePipeline,
    context: dict,
    config: GatewayConfig,
):
    # Use try_backends_with_failover for consistent behavior
    # Note: This requires async generator refactoring
```

### Option 2: Use OpenAI Python SDK (Recommended)
Instead of manual httpx calls, use the official OpenAI SDK:

```python
from openai import AsyncOpenAI

# For ZAI fallback
zai_client = AsyncOpenAI(
    base_url="https://api.z.ai/api/coding/paas/v4",
    api_key=zai_api_key
)

response = await zai_client.chat.completions.create(
    model="glm-4.6",
    messages=messages
)
```

Benefits:
- ✅ Automatic header handling (User-Agent, etc.)
- ✅ Automatic authentication
- ✅ Request/response parsing
- ✅ Streaming support built-in
- ✅ Better error handling

### Option 3: Hybrid Approach
Keep manual httpx for LM Studio (primary)
Use OpenAI SDK for ZAI fallback

## Recommended Next Steps

1. **Quick fix**: Update streaming path to use `try_backends_with_failover()`
2. **Long-term**: Refactor to use OpenAI SDK for all backends
3. **Test**: Verify failover works with LM Studio down

## Test Verification

To verify the fix:
```bash
# Stop LM Studio
# Test gateway - should fallback to ZAI successfully
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "User-Agent: ai-sdk/openai-compatible/2.0.33" \
  -d '{"model":"glm-4.6","messages":[{"role":"user","content":"Hello"}],"stream":false}'
```

Expected after fix:
- Gateway tries LM Studio → connection fails
- Gateway tries ZAI → success (no 401)

## Current Status

| Component | Status | Notes |
|-----------|--------|-------|
| Failover logic (non-streaming) | ✅ Implemented | Works correctly |
| Failover logic (streaming) | ❌ NOT implemented | Always uses primary |
| User-Agent preservation | ✅ Working | Headers preserved correctly |
| ZAI endpoint format | ⚠️ Partial | Fixed in failover, broken in streaming |
| ZAI authentication | ❌ 401 error | Due to streaming path not using failover |

## Conclusion

The 401 error is NOT a missing User-Agent header. The real issue is that the **streaming response path completely bypasses the failover logic** and directly connects to the primary backend with the wrong URL format for ZAI.

**Priority**: High - Failover is broken for streaming requests

**Estimated Fix Time**:
- Quick fix (update streaming): 15 minutes
- Proper fix (use OpenAI SDK): 1-2 hours
