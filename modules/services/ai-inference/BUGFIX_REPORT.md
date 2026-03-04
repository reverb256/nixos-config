# Gateway Bug Fix Report

## Issue
The AI inference gateway service was failing to start with the error:
```
RuntimeError: Failed to create FastAPI app - check logs for errors
```

## Root Cause
The `create_app()` function had a critical structural bug where the messages and metrics endpoints were incorrectly indented inside the `handle_non_streaming_request()` helper function instead of inside `create_app()`.

### File Structure Issue
**Before Fix:**
```python
def create_app(config: Optional[GatewayConfig] = None) -> FastAPI:
    # ... setup code ...
    @app.post("/v1/chat/completions")
    async def chat_completions(request: Request):
        # ... endpoint code ...
        return await handle_non_streaming_request(...)

# End of create_app() function here!

async def handle_non_streaming_request(...):
    # ... helper function code ...

    # BUG: These endpoints were incorrectly indented here!
    @app.post("/v1/messages")
    async def messages(request: Request):
        # ... endpoint code ...

    @app.get("/metrics")
    async def metrics():
        # ... endpoint code ...

    return app  # This was at the wrong indentation level
```

**After Fix:**
```python
def create_app(config: Optional[GatewayConfig] = None) -> FastAPI:
    # ... setup code ...

    @app.post("/v1/chat/completions")
    async def chat_completions(request: Request):
        # ... endpoint code ...
        return await handle_non_streaming_request(...)

    # FIXED: Messages endpoint now correctly placed inside create_app()
    @app.post("/v1/messages")
    async def messages(request: Request):
        # ... endpoint code ...

    # FIXED: Metrics endpoint now correctly placed inside create_app()
    if PROMETHEUS_AVAILABLE:
        @app.get("/metrics")
        async def metrics():
            # ... endpoint code ...

    return app  # Now at the correct location


# Helper functions at module level
async def handle_non_streaming_request(...):
    # ... helper function code ...

async def stream_backend_response(...):
    # ... helper function code ...
```

## Investigation Process
1. Added diagnostic logging to trace execution
2. Discovered the logging wasn't appearing, indicating the function wasn't being called
3. Used print statements for immediate visibility
4. Analyzed the file structure and discovered the indentation bug
5. Confirmed that endpoints were inside the wrong function

## Fix Applied
Moved the messages and metrics endpoints from inside `handle_non_streaming_request()` to inside `create_app()` where they belong.

### Changed Files
- `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/main.py`
  - Lines 333-639: Moved from incorrect location to inside `create_app()`

## Verification
After the fix:
- ✅ Gateway service starts successfully
- ✅ All endpoints registered correctly
- ✅ Health endpoint returns proper response
- ✅ Models endpoint accessible (returns auth error as expected)
- ✅ Metrics endpoint returns Prometheus data
- ✅ Application startup complete message logged

## Test Results
```bash
$ curl -s http://127.0.0.1:8080/health | jq .
{
  "status": "healthy",
  "gateway": {
    "version": "2.0.0",
    "host": "127.0.0.1",
    "port": 8080
  },
  "backend": {
    "url": "http://127.0.0.1:1234",
    "type": "lm-studio",
    "healthy": true
  }
}

$ curl -s http://127.0.0.1:8080/metrics | head -20
# HELP python_gc_objects_collected_total Objects collected during gc
# TYPE python_gc_objects_collected_total counter
python_gc_objects_collected_total{generation="0"} 903.0
...
```

## Lessons Learned
1. **Indentation matters**: In Python, incorrect indentation can cause silent failures where code is placed in unexpected scopes
2. **Function boundaries**: Always verify that endpoints are defined inside the correct function scope
3. **Debug systematically**: Add diagnostic output at each step to trace execution flow
4. **Test incrementally**: Verify structure with tools like `grep -n "^def \|^    @app\." to visualize function hierarchy

## Status
✅ **RESOLVED** - Gateway fully operational
