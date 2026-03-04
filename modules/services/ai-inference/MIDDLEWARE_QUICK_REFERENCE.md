# Middleware Quick Reference Guide

## Middleware Execution Order

```
Request → Observability → Security → Rate Limiter → Circuit Breaker → Load Balancer → Backend
                                                                            ↓
Response ← Observability ← Security ← Rate Limiter ← Circuit Breaker ← Load Balancer
```

## Component Files

| Component | File Path | Purpose |
|-----------|-----------|---------|
| Base Interface | `middleware/base.py` | Abstract middleware class |
| Observability | `middleware/observability.py` | Request ID, timing, logging |
| Security | `middleware/security_filter.py` | Size limits, PII redaction |
| Rate Limiter | `middleware/rate_limiter.py` | Token/rate limiting |
| Circuit Breaker | `middleware/circuit_breaker.py` | Failover, health checks |
| Load Balancer | `middleware/load_balancer.py` | Backend selection |
| Pipeline | `pipeline.py` | Orchestrates middleware |
| Config | `config.py` | Configuration dataclasses |
| Metrics | `utils/metrics.py` | Prometheus metrics |
| Redis Client | `utils/redis_client.py` | Async Redis wrapper |

## Environment Variables

```bash
# Observability
OBSERVABILITY_ENABLED=true
STRUCTURED_LOGGING=true

# Security
SECURITY_ENABLED=true
PII_REDACTION=true
MAX_REQUEST_SIZE=10485760

# Rate Limiting
RATE_LIMIT_ENABLED=false
RATE_LIMIT_BACKEND=memory
RATE_LIMIT_TPM=10000
RATE_LIMIT_TPH=50000
RATE_LIMIT_TPD=500000
RATE_LIMIT_RPM=60

# Circuit Breaker
CIRCUIT_BREAKER_ENABLED=true
CIRCUIT_FAILURE_THRESHOLD=5
CIRCUIT_SUCCESS_THRESHOLD=2
CIRCUIT_TIMEOUT=60
```

## Common Operations

### Enable Middleware

```nix
services.ai-inference.gateway.middleware.observability.enable = true;
services.ai-inference.gateway.middleware.security.enable = true;
services.ai-inference.gateway.middleware.rateLimiting.enable = true;
services.ai-inference.gateway.middleware.circuitBreaker.enable = true;
```

### Configure Multiple Backends

```nix
services.ai-inference.gateway.backends = [
  {
    name = "backend1";
    url = "http://127.0.0.1:1234";
    weight = 100;
    maxConcurrentRequests = 100;
  }
  {
    name = "backend2";
    url = "http://127.0.0.1:1235";
    weight = 200;
  }
];
```

### Test Middleware

```bash
# Health check
curl http://127.0.0.1:8080/health | jq

# Metrics
curl http://127.0.0.1:8080/metrics | grep gateway_

# Test with request ID
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Request-ID: test-123" \
  -d '{"model":"qwen3.5-4b","messages":[{"role":"user","content":"Hi"}]}' \
  | jq '.gateway_metadata'
```

## Key Metrics

```bash
# View all gateway metrics
curl http://127.0.0.1:8080/metrics | grep gateway

# Key metrics to monitor:
# - gateway_http_requests_total
# - gateway_http_request_duration_seconds
# - gateway_middleware_duration_seconds
# - gateway_circuit_breaker_state
# - gateway_backend_health
# - gateway_rate_limit_denied_total
# - gateway_security_blocked_total
```

## Troubleshooting Commands

```bash
# Check if middleware is loaded
journalctl -u ai-inference-gateway -n 100 | grep -i middleware

# View circuit breaker state
curl http://127.0.0.1:8080/metrics | grep circuit_breaker_state

# Check rate limiting
curl http://127.0.0.1:8080/metrics | grep rate_limit

# View backend selection
curl http://127.0.0.1:8080/metrics | grep load_balancer_selections

# Test middleware timing
curl http://127.0.0.1:8080/metrics | grep middleware_duration
```

## Response Metadata

Every response includes `gateway_metadata`:

```json
{
  "gateway_metadata": {
    "request_id": "uuid-here",
    "processing_time_ms": 45.23,
    "load_balancer": {
      "backend_name": "backend1",
      "backend_url": "http://127.0.0.1:1234",
      "backend_latency_ms": 42.1,
      "backend_connections": 5
    }
  }
}
```

## Adding New Middleware

1. Create `middleware/your_middleware.py`:
```python
from ai_inference_gateway.middleware.base import Middleware

class YourMiddleware(Middleware):
    async def process_request(self, request, context):
        # Process request
        return True, None  # (continue, error)

    async def process_response(self, response, context):
        # Process response
        return response

    @property
    def enabled(self) -> bool:
        return self.config.enabled
```

2. Add to `middleware/__init__.py`:
```python
try:
    from .your_middleware import YourMiddleware
    __all__.append("YourMiddleware")
except ImportError:
    pass
```

3. Add config to `config.py`:
```python
@dataclass
class YourMiddlewareConfig:
    enabled: bool = False
    # Add your config options
```

4. Add tests to `tests/test_your_middleware.py`

## Testing

```bash
# Run all tests
cd /etc/nixos/modules/services/ai-inference
./test-all.sh

# Test specific middleware
python3 -c "
from ai_inference_gateway.middleware import YourMiddleware
from ai_inference_gateway.config import YourMiddlewareConfig
config = YourMiddlewareConfig(enabled=True)
middleware = YourMiddleware(config)
print(f'Middleware enabled: {middleware.enabled}')
"
```

## Performance Tuning

### Reduce Latency
- Disable unnecessary middleware
- Reduce circuit breaker health check interval
- Use in-memory rate limiting (not Redis)
- Optimize backend connection pooling

### Increase Throughput
- Adjust rate limiter thresholds
- Increase backend `maxConcurrentRequests`
- Use load balancer for multiple backends
- Enable Redis for distributed rate limiting

### Improve Reliability
- Lower circuit breaker `failureThreshold`
- Enable health checks on all backends
- Set appropriate `timeoutSeconds`
- Monitor metrics for anomalies
