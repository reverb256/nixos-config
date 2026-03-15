# Phase 1 Feature Tests

Comprehensive test suite for Phase 1: Production Readiness features.

## Test Files

### Core Feature Tests

- **`test_response_format.py`** - JSON Schema Mode transformation tests
  - Tests for `json_object`, `json_schema`, and `text` modes
  - Response validation tests
  - Edge cases and error handling

- **`test_mcp_cache.py`** - MCP Tool Schema Caching tests
  - Cache hit/miss scenarios
  - TTL and expiration tests
  - Cache invalidation (specific/all)
  - Metrics tracking
  - Cache warm-up functionality

- **`test_pii_redactor.py`** - PII Redaction tests
  - Email, phone, SSN, credit card, IP address redaction
  - Different redaction modes (redact, hash, mask, remove)
  - Message redaction for chat
  - PII detection without redaction
  - Pattern filtering

- **`test_moderation.py`** - Content Moderation tests
  - Jailbreak detection
  - Prompt injection detection
  - Violence, self-harm, hate speech detection
  - Spam detection
  - Strictness levels (low/medium/high)
  - Message moderation

### Existing Tests (Previously Created)

- `test_config.py` - Configuration tests
- `test_middleware_base.py` - Middleware base tests
- `test_redis_client.py` - Redis client tests
- `test_observability.py` - Observability middleware tests
- `test_security_filter.py` - Security filter tests
- `test_rate_limiter.py` - Rate limiter tests
- `test_pipeline.py` - Pipeline tests
- `test_circuit_breaker.py` - Circuit breaker tests
- `test_load_balancer.py` - Load balancer tests
- `test_metrics.py` - Metrics tests
- `test_main.py` - Main gateway tests
- `test_integration.py` - Integration tests

## Running Tests

### Install Test Dependencies

```bash
pip install -r requirements-test.txt
```

### Quick Start

```bash
# Run all Phase 1 tests
python tests/run_tests.py phase1

# Run all tests with coverage
python tests/run_tests.py all

# Run unit tests only
python tests/run_tests.py unit

# Run integration tests
python tests/run_tests.py integration

# Generate coverage report
python tests/run_tests.py coverage
```

### Using Pytest Directly

```bash
# Run specific test file
pytest tests/test_response_format.py -v

# Run specific test class
pytest tests/test_pii_redactor.py::TestEmailRedaction -v

# Run specific test
pytest tests/test_moderation.py::TestJailbreakDetection::test_detect_ignore_instructions -v

# Run with coverage
pytest tests/ --cov=ai_inference_gateway --cov-report=html

# Run only fast tests (exclude slow)
pytest tests/ -m "not slow" -v

# Run async tests
pytest tests/ -m asyncio -v
```

## Test Organization

### Test Class Structure

```python
class TestFeatureName:
    """Tests for specific feature aspect."""

    def test_specific_behavior(self):
        """Test description."""
        # Arrange
        # Act
        # Assert
```

### Fixtures

Shared fixtures are defined in `conftest.py`:

- `sample_chat_messages` - Sample chat messages
- `sample_pii_text` - Text containing PII
- `sample_harmful_content` - Sample harmful content
- `sample_urls` - Sample URLs for testing
- `mock_http_response` - HTTP response factory
- `mock_httpx_client` - Mock httpx client
- `retry_config` - Retry configuration
- `cache_config` - Cache configuration
- And more...

### Markers

Tests are marked with appropriate markers:

- `@pytest.mark.unit` - Unit tests (fast, isolated)
- `@pytest.mark.integration` - Integration tests
- `@pytest.mark.slow` - Slow tests
- `@pytest.mark.asyncio` - Async tests
- `@pytest.mark.requires_redis` - Requires Redis
- `@pytest.mark.requires_qdrant` - Requires Qdrant
- `@pytest.mark.requires_network` - Requires network

## Test Coverage Goals

Phase 1 features should achieve:

- **Line Coverage**: >80%
- **Branch Coverage**: >70%
- **Function Coverage**: >90%

Current coverage estimates per feature:

| Feature | Est. Coverage | Status |
|---------|---------------|--------|
| JSON Schema Mode | 85% | ✅ |
| MCP Caching | 90% | ✅ |
| Retry Handler | 80% | ⚠️ (needs integration tests) |
| Semantic Cache | 75% | ⚠️ (needs Redis/Qdrant) |
| PII Redaction | 95% | ✅ |
| Content Moderation | 90% | ✅ |

## Writing New Tests

### Template for Unit Tests

```python
class TestFeatureAspect:
    """Tests for specific feature aspect."""

    def test_success_scenario(self):
        """Test successful operation."""
        # Arrange
        input_data = {}

        # Act
        result = function_under_test(input_data)

        # Assert
        assert result == expected_output

    def test_error_handling(self):
        """Test error handling."""
        with pytest.raises(ExpectedException):
            function_under_test(invalid_input)
```

### Template for Async Tests

```python
class TestAsyncFeature:
    """Tests for async feature."""

    @pytest.mark.asyncio
    async def test_async_operation(self):
        """Test async operation."""
        # Arrange
        async def setup():
            return await async_setup_function()

        # Act
        result = await async_function_under_test(await setup())

        # Assert
        assert result == expected_output
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install -r requirements-test.txt
      - name: Run Phase 1 tests
        run: python tests/run_tests.py phase1
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

## Known Issues and Limitations

### Semantic Cache Tests

⚠️ **Requires Redis and Qdrant**

Semantic cache tests require external services:

```bash
# Start Redis
docker run -d -p 6379:6379 redis:latest

# Start Qdrant
docker run -d -p 6333:6333 qdrant/qdrant:latest

# Run tests
pytest tests/test_semantic_cache.py -v
```

### RAG Ingestion Tests

⚠️ **Requires network access and MCP servers**

RAG ingestion tests require:
- Network access for HTTP fetching
- MCP web-reader server (or mock)

### Retry Handler Tests

⚠️ **Integration tests needed**

Retry handler has good unit test coverage but needs:
- Integration tests with actual HTTP client
- Tests for actual retry scenarios with delays
- Tests for rate limit handling

## Troubleshooting

### Import Errors

If you get import errors:

```bash
# Make sure you're in the project root
cd /etc/nixos/modules/services/ai-inference/ai_inference_gateway

# Add project to Python path
export PYTHONPATH="${PYTHONPATH}:$(pwd)"
```

### Async Tests Failing

If async tests fail:

```bash
# Install pytest-asyncio
pip install pytest-asyncio>=0.21.0

# Run with asyncio mode
pytest tests/ -m asyncio -v
```

### Coverage Not Showing

If coverage report doesn't show:

```bash
# Install pytest-cov
pip install pytest-cov>=4.1.0

# Run with cov flag
pytest tests/ --cov=ai_inference_gateway --cov-report=html
```

## Next Steps

1. ✅ Create unit tests for all Phase 1 features
2. ⏳ Add integration tests for retry handler
3. ⏳ Add semantic cache integration tests (with Redis/Qdrant)
4. ⏳ Add RAG ingestion integration tests
5. ⏳ Add end-to-end API tests
6. ⏳ Add load/performance tests
7. ⏳ Set up CI/CD pipeline

## Test Statistics

- **Total Test Files**: 15 (3 new + 12 existing)
- **Total Test Cases**: ~300+
- **Phase 1 Test Cases**: ~150
- **Code Coverage**: Target >80%

---

**For more information, see:**
- Main roadmap: `/etc/nixos/docs/comprehensive-implementation-roadmap.md`
- Phase 1 summary: `/tmp/phase1-summary.md`

---

# Knowledge Fabric Tests (Phase 4)

## Overview

The Knowledge Fabric tests validate the semantic routing, parallel retrieval, RRF fusion, and context synthesis features.

## Test Environment

**Using Nix Shell (Recommended):**

The Knowledge Fabric tests require pytest with async support. Use the provided Nix shell:

```bash
cd /etc/nixos/modules/services/ai-inference/ai_inference_gateway
nix-shell
```

This enters an isolated environment with all required dependencies:
- pytest
- pytest-asyncio
- pytest-cov
- pytest-mock
- pydantic
- httpx
- requests

## Running Knowledge Fabric Tests

```bash
# Run all Knowledge Fabric tests
pytest tests/test_knowledge_fabric.py tests/test_fabric_routing.py tests/test_fabric_fusion.py tests/test_fabric_sources.py

# Run specific test file
pytest tests/test_knowledge_fabric.py -v

# Run with coverage
pytest --cov=ai_inference_gateway.middleware.knowledge_fabric --cov-report=term-missing tests/test_knowledge_fabric.py

# Run with verbose output
pytest tests/test_knowledge_fabric.py -v -s
```

## Test Files

| File | Lines | Purpose |
|------|-------|---------|
| `test_knowledge_fabric.py` | 470 | Main orchestrator, query extraction, parallel retrieval |
| `test_fabric_routing.py` | 375 | Semantic router intent classification |
| `test_fabric_fusion.py` | 461 | RRF algorithm and context synthesis |
| `test_fabric_sources.py` | 464 | RAG, SearXNG, web search, code search adapters |

## Coverage Goals

- Line coverage: >80%
- Branch coverage: >70%
- Function coverage: >90%

## Key Test Scenarios

### Semantic Routing
- CODE intent detection (code keywords, syntax patterns)
- FACTUAL queries (encyclopedic, definitional)
- PROCEDURAL queries (how-to, step-by-step)
- REALTIME queries (current events, prices, weather)
- COMPARATIVE queries (X vs Y, differences)
- CONTEXTUAL queries (conversation references)

### Parallel Retrieval
- Multiple sources queried simultaneously
- Graceful handling of source failures
- Query extraction from various message formats
- Multi-modal content (text + images)

### RRF Fusion
- Single source fusion
- Multi-source deduplication
- Rank score calculation verification
- Empty result handling

### Source Adapters
- RAG: search service integration
- SearXNG: web meta-search with categories
- Web search: MCP JSON-RPC format
- Code search: file globbing and content matching

## Troubleshooting Knowledge Fabric Tests

### Import errors for knowledge_fabric module

```bash
# Ensure you're in the correct directory
cd /etc/nixos/modules/services/ai-inference/ai_inference_gateway
nix-shell  # Enters environment with all dependencies
```

### Tests fail with "No module named 'pytest'"

```bash
# Use nix-shell instead of system Python
nix-shell
pytest tests/
```

### Async tests hang or timeout

```bash
# Use pytest-asyncio (included in nix-shell)
pytest tests/test_knowledge_fabric.py --timeout=30
```

### Mock objects not behaving as expected

The tests use `unittest.mock.Mock` and `AsyncMock`. Ensure:
- Mock return values are set with `return_value=`
- Async functions use `AsyncMock(return_value=...)`
- Patch paths match actual import locations
