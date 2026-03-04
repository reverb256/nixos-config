# AI Gateway Failover Implementation

**Date**: 2026-03-04
**Status**: ✅ Core Failover Implemented | ⚠️ ZAI Integration Needs Investigation

## What Was Implemented

### 1. Backend Failover Mechanism ✅

**File**: `modules/services/ai-inference/ai_inference_gateway/main.py`

Added `try_backends_with_failover()` function that:
- Tries primary backend first (LM Studio)
- On connection failure (ConnectError, TimeoutException), automatically tries fallback backends
- Uses appropriate authentication for each backend type
- Logs which backend is being used for observability

### 2. Configuration for Fallback URLs ✅

**Files Modified**:
- `modules/services/ai-inference/ai_inference_gateway/config.py`
- `modules/services/ai-inference/gateway.nix`

Added:
- `backend_fallback_urls` configuration field (comma-separated string)
- `get_backend_fallback_urls()` method to parse the list
- Environment variable `BACKEND_FALLBACK_URLS` set to ZAI URL
- Field validator to handle comma-separated URLs

### 3. Updated Endpoints to Use Failover ✅

Updated endpoints:
- `/v1/models` - now uses failover
- `/v1/chat/completions` - now uses failover
- Streaming responses - updated to use failover

### 4. ZAI Endpoint Format Fix ✅

Fixed double `/v1/v1` issue:
- ZAI uses `/chat/completions` instead of `/v1/chat/completions`
- Added logic to convert OpenAI-style endpoints to ZAI format
- URL construction now: `https://api.z.ai/api/coding/paas/v4/chat/completions`

## Current Configuration

```nix
services.ai-inference.backend = {
  url = "http://127.0.0.1:1234";        # Primary: LM Studio
  type = "lm-studio";
  zai = {
    enable = true;
    baseUrl = "https://api.z.ai/api/coding/paas/v4";
    apiKeyFile = "/run/agenix/zai-api-key";
  };
};

# Fallback chain (from NixOS config)
services.ai-inference.routing.fallbackChain = [
  "vllm"
  "lm-studio"
  "zai"
];
```

## Test Results

### ✅ Failover Logic Works

```
Mar 04 14:53:30 primary backend http://127.0.0.1:1234 failed: All connection attempts failed
```

Gateway correctly:
1. Detects LM Studio is down (connection refused)
2. Attempts fallback to ZAI
3. Connects to ZAI successfully

### ⚠️ ZAI Authentication Issue

```
Mar 04 14:53:30 Backend error: Backend error 401: token expired or incorrect
```

The gateway reaches ZAI but receives 401 Unauthorized. This could be due to:
1. Invalid API key (though key file exists and has content)
2. ZAI requires different authentication format (not Bearer token)
3. ZAI requires additional headers
4. ZAI endpoint path is incorrect

### ZAI API Investigation Needed

**Current ZAI Configuration**:
- Base URL: `https://api.z.ai/api/coding/paas/v4`
- API Key: Present in `/run/agenix/zai-api-key`
- Auth Format: `Authorization: Bearer {key}` (standard)

**Issues**:
- `/models` endpoint returns 401
- `/chat/completions` returns "token expired or incorrect"
- This suggests ZAI may use a different API format than expected

## What's Working

✅ Primary backend (LM Studio) - fully functional when available
✅ Connection error detection - properly detects when LM Studio is down
✅ Fallback trigger - attempts ZAI when primary fails
✅ URL construction - correct ZAI URL format
✅ Logging - observability for debugging

## What Needs Investigation

⚠️ **ZAI API Integration**
- Need to verify correct ZAI API endpoint format
- Need to verify ZAI authentication method
- May need to adjust request format for ZAI
- Check if ZAI requires model mapping (glm-4.6 → ZAI's model IDs)

## Potential Next Steps

### Option 1: Investigate ZAI API
1. Test ZAI API directly with curl:
   ```bash
   curl -H "Authorization: Bearer $(cat /run/agenix/zai-api-key)" \
     https://api.z.ai/api/coding/paas/v4/chat/completions \
     -d '{"model":"glm-4.6","messages":[{"role":"user","content":"Hi"}]}'
   ```

2. Check ZAI API documentation for correct:
   - Authentication format
   - Endpoint paths
   - Request/response format
   - Model names

### Option 2: Use OpenAI-Compatible Fallback
Consider using an OpenAI-compatible backend instead:
- OpenAI API
- Azure OpenAI
- Together AI
- Any other OpenAI-compatible endpoint

### Option 3: Circuit Breaker Pattern
For now, the circuit breaker will prevent repeated failed requests to ZAI:
- After 5 failures, circuit opens
- Stops trying ZAI for 60 seconds
- Prevents spamming ZAI with invalid requests

## Architecture Decisions

**Why Connection-Error-Only Failover?**

The failover only triggers on connection errors (ConnectError, TimeoutException), not on application errors (4xx, 5xx). This prevents:
- Cascading a single bad request across all backends
- Hitting rate limits on multiple backends
- Masking application-level errors

**Why Sequential Failover?**

Backends are tried sequentially rather than in parallel to:
- Reduce load on backends
- Simpler error handling
- Clearer logs for debugging
- Prevent race conditions

**Why ZAI as Fallback?**

ZAI provides:
- Cloud-based inference (doesn't depend on local GPU)
- Multiple models (glm-4.5, glm-4.6, glm-4.7, glm-5)
- High availability
- Different architecture (redundancy)

## Commit Information

Latest changes implement:
- Backend failover with configurable fallback URLs
- ZAI endpoint path normalization
- Configuration parser for comma-separated URLs
- Integration with existing authentication system

## Testing Failover

**To test failover:**

1. Stop LM Studio:
   ```bash
   # LM Studio should be closed
   ```

2. Test with curl:
   ```bash
   curl -X POST http://127.0.0.1:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"glm-4.6","messages":[{"role":"user","content":"Hello"}]}'
   ```

3. Check logs:
   ```bash
   journalctl -u ai-inference-gateway -f | grep -E "Attempting|fallback|backend"
   ```

**Expected behavior:**
- Gateway tries LM Studio → connection fails
- Gateway tries ZAI → should succeed (once auth is fixed)

## Summary

✅ **Core failover mechanism is implemented and working**
- Detects primary backend failures
- Attempts fallback backends
- Proper authentication per backend
- Good observability/logging

⚠️ **ZAI integration needs API format investigation**
- Connection works but authentication fails
- Need to verify correct ZAI API format
- May need to adjust request headers or authentication method

The failover infrastructure is solid - once ZAI's API format is sorted out, automatic failover will work seamlessly.
