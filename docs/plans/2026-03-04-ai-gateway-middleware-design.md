# AI Gateway Middleware Architecture Design

**Date**: 2026-03-04
**Author**: Claude Code
**Status**: Approved

## Overview

Refactor the AI Inference Gateway from a monolithic 2000+ line Python file to a layered architecture with pluggable middleware components. This enables better maintainability, testability, and extensibility while maintaining NixOS simplicity (single service).

## Architecture

### Directory Structure

```
modules/services/ai-inference/
├── gateway.nix                          # Main service configuration
├── ai_inference_gateway/                # Python package
│   ├── __init__.py
│   ├── main.py                          # FastAPI app (~300 lines)
│   ├── config.py                        # Configuration loading
│   ├── middleware/
│   │   ├── __init__.py
│   │   ├── base.py                      # Abstract middleware interface
│   │   ├── rate_limiter.py              # Token-based rate limiting
│   │   ├── circuit_breaker.py           # Enhanced circuit breaker
│   │   ├── security_filter.py           # Input/output security
│   │   ├── cache.py                     # Redis-backed caching
│   │   ├── request_queue.py             # Priority request queuing
│   │   ├── load_balancer.py             # Weighted load balancing
│   │   └── observability.py             # Structured logging & tracing
│   └── utils/
│       ├── redis_client.py              # Redis connection management
│       └── metrics.py                   # Prometheus metrics helpers
└── README.md                            # Updated documentation
```

### Request Flow

```
Client Request
    ↓
FastAPI Main App
    ↓
Middleware Pipeline (in order):
  1. Observability (request ID, logging start)
  2. Security Filter (input validation)
  3. Rate Limiter (token-based checks)
  4. Request Queue (priority scheduling)
  5. Cache (exact match lookup)
  6. Load Balancer (backend selection)
    ↓
Router & Reranker (existing functionality)
    ↓
Circuit Breaker (backend health check)
    ↓
Backend (LM Studio / ZAI)
    ↓
Response (reverse middleware order)
```

## Components

### 1. Middleware Base Interface

All middleware implement a common interface:

```python
class Middleware(ABC):
    @abstractmethod
    async def process_request(self, request: Request, context: dict) -> Tuple[bool, Optional[HTTPException]]:
        """Process incoming request. Return (should_continue, optional_error)."""

    @abstractmethod
    async def process_response(self, response: dict, context: dict) -> dict:
        """Process outgoing response. Return modified response."""

    @property
    @abstractmethod
    def enabled(self) -> bool:
        """Check if middleware is enabled."""
```

### 2. Token-Based Rate Limiter

**Purpose**: Rate limit based on estimated tokens, not request count.

**Features**:
- Sliding window rate limiting (minute, hour, day)
- Per-API-key quotas
- Redis-backed with in-memory fallback
- Token estimation from request content

**Configuration**:
```nix
middleware.rateLimiting = {
  enable = true;
  backend = "redis";  # or "memory"
  defaultQuota = {
    tokensPerMinute = 10000;
    tokensPerHour = 50000;
    tokensPerDay = 500000;
  };
  quotas = {
    "premium-key" = { tokensPerMinute = 50000; };
  };
};
```

### 3. Enhanced Circuit Breaker

**Purpose**: Prevent cascading failures with automatic recovery.

**Features**:
- State machine (CLOSED, OPEN, HALF_OPEN)
- Health check endpoints
- Automatic timeout and recovery
- Per-backend circuit state tracking in Redis

**Configuration**:
```nix
middleware.circuitBreaker = {
  enable = true;
  failureThreshold = 5;
  timeoutSeconds = 60;
  healthCheckInterval = 10;
};
```

### 4. Security Filter (Bidirectional)

**Purpose**: Input validation and output PII redaction.

**Features**:
- Prompt injection detection
- Request size limits
- PII redaction (email, phone, SSN, API keys, credit cards)
- Configurable patterns

**Configuration**:
```nix
middleware.security = {
  enable = true;
  piiRedaction = true;
  maxRequestSize = 10485760;  # 10MB
};
```

### 5. Redis-Backed Cache

**Purpose**: Cache identical requests to reduce backend load.

**Features**:
- Exact match cache key generation
- Configurable TTL
- Cache hit/miss metrics
- Invalidate on streaming requests

**Configuration**:
```nix
middleware.cache = {
  enable = true;
  backend = "redis";  # or "memory"
  defaultTtl = 3600;  # 1 hour
};
```

### 6. Priority Request Queue

**Purpose**: Manage concurrency and prioritize requests.

**Features**:
- Priority queue implementation
- Configurable max concurrency
- Priority via headers or estimation
- Per-client queue limits

**Configuration**:
```nix
middleware.requestQueue = {
  enable = true;
  maxConcurrent = 10;
};
```

### 7. Weighted Load Balancer

**Purpose**: Distribute load across multiple backend instances.

**Features**:
- Weighted round-robin selection
- Health check loop
- Support for multiple LM Studio/vLLM instances
- Automatic failover

**Configuration**:
```nix
middleware.loadBalancer = {
  enable = true;
  backends = [
    {
      name = "lm-studio-1";
      url = "http://127.0.0.1:1234";
      weight = 1;
      healthCheckUrl = "http://127.0.0.1:1234/health";
    }
  ];
};
```

### 8. Enhanced Observability

**Purpose**: Structured logging with request tracing.

**Features**:
- Request ID correlation (X-Request-ID header or UUID)
- Structured JSON logging
- Span tracking for distributed tracing
- Processing time metrics

**Configuration**:
```nix
middleware.observability = {
  enable = true;
  structuredLogging = true;
};
```

## Data Flow Details

### Request Processing

1. **Observability middleware** generates request ID, starts logging
2. **Security filter** validates input, checks for injection
3. **Rate limiter** checks token quotas against Redis
4. **Request queue** adds to priority queue (or processes immediately if capacity)
5. **Cache** checks for cached response (returns early if hit)
6. **Load balancer** selects healthy backend
7. **Router** analyzes prompt, selects model
8. **Circuit breaker** checks backend health, proxies request
9. **Backend** processes request
10. **Response** returns through middleware in reverse order

### Error Handling

Each middleware can:
- Return `False, HTTPException` to short-circuit
- Modify context dict for downstream middleware
- Handle errors gracefully with fallbacks

Redis failures fall back to in-memory:
```python
try:
    await self.redis.get(key)
except RedisError:
    # Fallback to in-memory dict
    return self.memory_cache.get(key)
```

## Testing Strategy

### Unit Tests
- Mock Redis for rate limiter, cache, circuit breaker
- Test each middleware independently
- Verify error conditions and edge cases

### Integration Tests
- Test middleware pipeline end-to-end
- Verify request/response flow
- Test failover scenarios

### Load Tests
- Test queue backpressure
- Verify rate limiting under load
- Check cache hit rates

## Deployment Strategy

### Phase 1: Infrastructure
1. Add Redis service to NixOS config
2. Create ai_inference_gateway package structure
3. Update gateway.nix to use new structure

### Phase 2: Core Middleware
4. Implement base interface and utils
5. Implement observability and security (no dependencies)
6. Test with existing functionality

### Phase 3: Redis Middleware
7. Implement Redis client and connection pooling
8. Implement rate limiter, cache, circuit breaker with Redis
9. Configure Redis and test

### Phase 4: Advanced Features
10. Implement request queue
11. Implement load balancer
12. Integration testing

### Phase 5: Documentation
13. Update README with new architecture
14. Add configuration examples
15. Create troubleshooting guide

## Rollback Plan

The new architecture maintains backward compatibility:
- Old gateway.nix continues to work during migration
- Feature flags allow gradual rollout
- Each middleware can be independently disabled
- Redis failures gracefully fall back to in-memory

To rollback:
1. Set all `middleware.*.enable = false`
2. Service continues with core routing functionality
3. Investigate and fix issues
4. Re-enable middleware one at a time

## Success Criteria

- ✅ All existing tests pass
- ✅ New middleware unit tests >80% coverage
- ✅ Rate limiting correctly tracks tokens
- ✅ Cache reduces backend load by >20% (measured)
- ✅ Circuit breaker prevents cascading failures
- ✅ Load balancer distributes traffic evenly
- ✅ Structured logs enable request tracing
- ✅ No performance regression (<5% overhead)
- ✅ Documentation is complete and accurate
