# AI Inference Gateway v2 - Advanced Router with Failover, Security, and Reranking
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ai-inference;
  inherit (lib) mkIf mkOption types;

  # Python environment with gateway dependencies (including RAG)
  gatewayPython = pkgs.python3.withPackages (ps: [
    ps.fastapi
    ps.uvicorn
    ps.httpx
    ps.openai  # OpenAI SDK for proper API communication
    ps.prometheus-client
    ps.pyjwt
    ps.cryptography
    ps.python-multipart
    ps.uvloop
    ps.httptools
    ps.aiohttp
    ps.psutil
    ps.qdrant-client
    ps.sentence-transformers
    ps.rank-bm25
    ps.numpy
    ps.redis
    ps.pydantic
    ps.pydantic-settings
  ]);

  # Gateway main.py v2
  gatewayMain = pkgs.writeText "ai-inference-gateway-v2.py" ''
        import os
        import sys
        import asyncio
        import json
        import re
        import time
        import hashlib
        import logging
        import traceback
        from datetime import datetime, timedelta
        from typing import Optional, Dict, List, Any, Tuple
        from dataclasses import dataclass, field
        from enum import Enum
        from collections import defaultdict
        from functools import lru_cache
        from contextvars import ContextVar

        from fastapi import FastAPI, Request, Response, HTTPException, status
        from fastapi.responses import StreamingResponse, JSONResponse
        import httpx
        from prometheus_client import (
            Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST,
            CollectorRegistry
        )

        # ============================================================================
        # STRUCTURED LOGGING SETUP
        # ============================================================================

        # Request context for structured logging
        request_context: ContextVar[Dict[str, Any]] = ContextVar('request_context', default={})

        class JSONFormatter(logging.Formatter):
            """JSON structured formatter for production logging"""
            
            def format(self, record: logging.LogRecord) -> str:
                log_entry = {
                    "timestamp": datetime.utcnow().isoformat() + "Z",
                    "level": record.levelname,
                    "logger": record.name,
                    "message": record.getMessage(),
                    "module": record.module,
                    "function": record.funcName,
                    "line": record.lineno
                }
                
                # Add request context if available
                ctx = request_context.get()
                if ctx:
                    log_entry["request"] = ctx
                
                # Add extra fields
                if hasattr(record, 'extra') and record.extra:
                    log_entry["extra"] = record.extra
                
                # Add exception info if present
                if record.exc_info:
                    log_entry["exception"] = {
                        "type": record.exc_info[0].__name__,
                        "message": str(record.exc_info[1]),
                        "traceback": self.formatException(record.exc_info)
                    }
                
                return json.dumps(log_entry)
        
        class HumanFormatter(logging.Formatter):
            """Human-readable formatter with emoji support for development"""
            
            def format(self, record: logging.LogRecord) -> str:
                # Base format with timestamp
                base = f"%(asctime)s - %(name)s - %(levelname)s - %(message)s"
                
                # Add request context if available
                ctx = request_context.get()
                if ctx and "request_id" in ctx:
                    base = f"[{ctx['request_id'][:8]}] {base}"
                
                formatter = logging.Formatter(base, datefmt='%Y-%m-%d %H:%M:%S')
                return formatter.format(record)
        
        def setup_logging() -> logging.Logger:
            """Configure structured logging with JSON or human-readable format"""
            log_level = os.getenv("LOG_LEVEL", "INFO").upper()
            structured = os.getenv("STRUCTURED_LOGGING", "false").lower() == "true"
            
            # Create logger
            logger = logging.getLogger("ai-gateway")
            logger.setLevel(getattr(logging, log_level, logging.INFO))
            
            # Remove existing handlers
            logger.handlers = []
            
            # Create console handler
            handler = logging.StreamHandler(sys.stdout)
            handler.setLevel(getattr(logging, log_level, logging.INFO))
            
            # Choose formatter based on configuration
            if structured:
                handler.setFormatter(JSONFormatter())
            else:
                handler.setFormatter(HumanFormatter())
            
            logger.addHandler(handler)
            
            return logger
        
        # Initialize logger
        logger = setup_logging()
        logger.info("🔄 Initializing AI Inference Gateway v2")

        # ============================================================================
        # CONFIGURATION
        # ============================================================================

        BACKEND_URL = os.getenv("BACKEND_URL", "http://127.0.0.1:1234")
        BACKEND_TYPE = os.getenv("BACKEND_TYPE", "lm-studio")
        GATEWAY_HOST = os.getenv("GATEWAY_HOST", "0.0.0.0")
        AUTH_MODE = os.getenv("AUTH_MODE", "none")

        # Load LM Studio API key from environment or file
        LM_STUDIO_API_KEY_FILE = os.getenv("LM_STUDIO_API_KEY_FILE", "")
        LM_STUDIO_API_KEY = os.getenv("LM_STUDIO_API_KEY", "")
        if LM_STUDIO_API_KEY_FILE and not LM_STUDIO_API_KEY:
            try:
                with open(LM_STUDIO_API_KEY_FILE, 'r') as f:
                    LM_STUDIO_API_KEY = f.read().strip()
            except Exception as e:
                logger.error(
                    "⚠ Failed to read LM Studio API key from file",
                    extra={"file": LM_STUDIO_API_KEY_FILE, "error": str(e)}
                )

        # Load ZAI API key from environment or file
        ZAI_API_KEY_FILE = os.getenv("ZAI_API_KEY_FILE", "")
        ZAI_API_KEY = os.getenv("ZAI_API_KEY", "")
        if ZAI_API_KEY_FILE and not ZAI_API_KEY:
            try:
                with open(ZAI_API_KEY_FILE, 'r') as f:
                    ZAI_API_KEY = f.read().strip()
            except Exception as e:
                logger.error(
                    "⚠ Failed to read ZAI API key from file",
                    extra={"file": ZAI_API_KEY_FILE, "error": str(e)}
                )

        ZAI_BASE_URL = os.getenv("ZAI_BASE_URL", "https://api.z.ai/api/coding/paas/v4")
        ZAI_MODELS_JSON = os.getenv("ZAI_MODELS", "{}")
        try:
            ZAI_MODELS = json.loads(ZAI_MODELS_JSON) if ZAI_MODELS_JSON else {}
        except:
            ZAI_MODELS = {}

        # Routing configuration
        ROUTING_ENABLED = os.getenv("ROUTING_ENABLED", "true").lower() == "true"
        DEFAULT_MODEL = os.getenv("DEFAULT_MODEL", "qwen3.5-35b-a3b")

        # Security configuration
        RATE_LIMIT_ENABLED = os.getenv("RATE_LIMIT_ENABLED", "false").lower() == "true"
        RATE_LIMIT_RPM = int(os.getenv("RATE_LIMIT_RPM", "60"))
        MAX_REQUEST_SIZE = int(os.getenv("MAX_REQUEST_SIZE", "10485760"))  # 10MB
        SECURITY_PROXY_ENABLED = os.getenv("SECURITY_PROXY_ENABLED", "false").lower() == "true"

        # Build backend headers
        backend_headers = {}
        if BACKEND_TYPE == "lm-studio" and LM_STUDIO_API_KEY:
            backend_headers["Authorization"] = f"Bearer {LM_STUDIO_API_KEY}"
        elif BACKEND_TYPE == "zai" and ZAI_API_KEY:
            backend_headers["Authorization"] = f"Bearer {ZAI_API_KEY}"

        # RAG configuration
        RAG_ENABLED = os.getenv("RAG_ENABLED", "false").lower() == "true"
        QDRANT_URL = os.getenv("QDRANT_URL", "http://127.0.0.1:6333")
        EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "sentence-transformers/all-MiniLM-L6-v2")
        CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "512"))
        CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "50"))
        RAG_TOP_K = int(os.getenv("RAG_TOP_K", "5"))
        HYBRID_SEARCH_ENABLED = os.getenv("HYBRID_SEARCH_ENABLED", "true").lower() == "true"
        VECTOR_WEIGHT = float(os.getenv("VECTOR_WEIGHT", "0.7"))
        BM25_WEIGHT = float(os.getenv("BM25_WEIGHT", "0.3"))
        AUTO_RAG_ENABLED = os.getenv("AUTO_RAG_ENABLED", "true").lower() == "true"
        TOKEN_SCOPED_COLLECTIONS = os.getenv("TOKEN_SCOPED_COLLECTIONS", "true").lower() == "true"

        # ============================================================================
        # PROMETHEUS METRICS
        # ============================================================================

        registry = CollectorRegistry()
        request_counter = Counter('ai_inference_requests_total', 'Total inference requests',
            ['model', 'status', 'backend', 'auth_mode'], registry=registry)
        request_duration = Histogram('ai_inference_request_duration_seconds', 'Request duration',
            ['model', 'backend'], registry=registry)
        tokens_generated = Counter('ai_inference_tokens_generated_total', 'Total tokens generated',
            ['model', 'backend'], registry=registry)
        active_requests = Gauge('ai_inference_active_requests', 'Active inference requests',
            registry=registry)
        backend_health = Gauge('ai_inference_backend_health', 'Backend health status (1=healthy, 0=unhealthy)',
            ['backend_url'], registry=registry)
        circuit_breaker_trips = Counter('ai_inference_circuit_breaker_trips_total', 'Circuit breaker trips',
            ['backend_url'], registry=registry)
        rate_limit_blocks = Counter('ai_inference_rate_limit_blocks_total', 'Rate limit blocks',
            ['client_ip'], registry=registry)
        security_blocks = Counter('ai_inference_security_blocks_total', 'Security blocks',
            ['reason'], registry=registry)
        models_cache_age = Gauge('ai_inference_models_cache_age_seconds', 'Age of models cache',
            registry=registry)
        models_cache_size = Gauge('ai_inference_models_cache_size', 'Number of cached models',
            registry=registry)

        # New prediction statistics metrics
        time_to_first_token = Histogram('ai_inference_time_to_first_token_seconds', 'Time to first token',
            ['model', 'backend'], registry=registry)
        tokens_per_second = Histogram('ai_inference_tokens_per_second', 'Tokens generated per second',
            ['model', 'backend'], registry=registry)
        prompt_tokens = Counter('ai_inference_prompt_tokens_total', 'Total prompt tokens',
            ['model', 'backend'], registry=registry)
        completion_tokens = Counter('ai_inference_completion_tokens_total', 'Total completion tokens',
            ['model', 'backend'], registry=registry)
        structured_output_requests = Counter('ai_inference_structured_output_requests_total', 'Structured output requests',
            ['model', 'format_type'], registry=registry)
        tool_calls = Counter('ai_inference_tool_calls_total', 'Tool/function calls',
            ['model', 'tool_name'], registry=registry)

        # ============================================================================
        # USAGE ANALYTICS - Enhanced metrics for dashboard
        # ============================================================================

        # Token usage metrics
        total_tokens = Counter('ai_inference_total_tokens_total',
            'Total tokens processed', ['model', 'backend', 'token_type'], registry=registry)

        tokens_per_request = Histogram('ai_inference_tokens_per_request',
            'Tokens per request', ['model'],
            buckets=[100, 500, 1000, 2000, 4000, 8000, 16000, 32000], registry=registry)

        # Cost tracking (estimated costs per 1M tokens)
        cost_tracker = Counter('ai_inference_cost_usd_total',
            'Estimated cost in USD', ['model', 'backend'],
            registry=registry)

        # Cache performance
        cache_hits = Counter('ai_inference_cache_hits_total',
            'Cache hits', ['cache_type'], registry=registry)
        cache_misses = Counter('ai_inference_cache_misses_total',
            'Cache misses', ['cache_type'], registry=registry)

        # Error tracking
        errors_total = Counter('ai_inference_errors_total',
            'Total errors', ['model', 'backend', 'error_type'], registry=registry)

        # Rate limiting
        rate_limit_hits = Counter('ai_inference_rate_limit_hits_total',
            'Rate limit violations', ['client_ip'], registry=registry)

        # Model usage patterns
        model_switches = Counter('ai_inference_model_switches_total',
            'Model routing decisions', ['from_model', 'to_model', 'reason'], registry=registry)

        # Streaming metrics
        streaming_chunks = Counter('ai_inference_streaming_chunks_total',
            'Streaming chunks sent', ['model'], registry=registry)
        streaming_duration = Histogram('ai_inference_streaming_duration_seconds',
            'Streaming duration', ['model'],
            buckets=[1.0, 5.0, 10.0, 30.0, 60.0, 120.0], registry=registry)

        # ============================================================================
        # SECURITY LAYER
        # ============================================================================

        class SecurityLevel(Enum):
            SAFE = "safe"
            WARNING = "warning"
            BLOCKED = "blocked"

        @dataclass
        class SecurityCheck:
            level: SecurityLevel
            reason: str = ""
            score: float = 0.0

        class SecurityProxy:
            """Security layer for input validation and filtering."""

            # Patterns for potential attacks
            INJECTION_PATTERNS = [
                r'<script[^>]*>.*?</script>',  # XSS
                r'javascript:',                  # JS injection
                r'on\w+\s*=',                   # Event handlers
                r'\\x[0-9a-f]{2}',              # Hex escape
                r'\\u[0-9a-f]{4}',              # Unicode escape
            ]

            # Max lengths for different fields
            MAX_MESSAGE_LENGTH = 100000
            MAX_MESSAGES = 100

            def __init__(self):
                self.injection_regex = re.compile('|'.join(self.INJECTION_PATTERNS), re.IGNORECASE)

            def check_request(self, body: Dict[str, Any]) -> SecurityCheck:
                """Validate incoming request for security issues."""
                # Check request size
                if len(json.dumps(body)) > MAX_REQUEST_SIZE:
                    return SecurityCheck(SecurityLevel.BLOCKED, "Request too large")

                # Check messages structure
                messages = body.get("messages", [])
                if not messages:
                    return SecurityCheck(SecurityLevel.WARNING, "No messages provided")

                if len(messages) > self.MAX_MESSAGES:
                    return SecurityCheck(SecurityLevel.BLOCKED, f"Too many messages (max {self.MAX_MESSAGES})")

                # Check each message
                for msg in messages:
                    content = msg.get("content", "")
                    if not isinstance(content, str):
                        return SecurityCheck(SecurityLevel.BLOCKED, "Invalid content type")

                    if len(content) > self.MAX_MESSAGE_LENGTH:
                        return SecurityCheck(SecurityLevel.BLOCKED, "Message too long")

                    # Check for injection patterns
                    if self.injection_regex.search(content):
                        return SecurityCheck(SecurityLevel.BLOCKED, "Potentially malicious content detected")

                return SecurityCheck(SecurityLevel.SAFE, "", score=1.0)

        security_proxy = SecurityProxy()

        # ============================================================================
        # RATE LIMITING
        # ============================================================================

        @dataclass
        class RateLimitEntry:
            requests: List[float] = field(default_factory=list)
            blocked: bool = False
            block_until: float = 0.0

        class RateLimiter:
            """Token bucket rate limiter."""

            def __init__(self, rpm: int = 60):
                self.rpm = rpm
                self.window = 60.0  # 1 minute window
                self.clients: Dict[str, RateLimitEntry] = {}
                self._lock = asyncio.Lock()

            async def check(self, client_ip: str) -> Tuple[bool, str]:
                """Check if client is within rate limit."""
                if not RATE_LIMIT_ENABLED:
                    return True, ""

                async with self._lock:
                    now = time.time()
                    entry = self.clients.get(client_ip, RateLimitEntry())

                    # Check if currently blocked
                    if entry.blocked and now < entry.block_until:
                        remaining = int(entry.block_until - now)
                        return False, f"Rate limited. Try again in {remaining}s"

                    # Reset if block expired
                    if entry.blocked:
                        entry.blocked = False
                        entry.blocked_until = 0.0

                    # Clean old requests outside window
                    entry.requests = [t for t in entry.requests if now - t < self.window]

                    # Check if over limit
                    if len(entry.requests) >= self.rpm:
                        entry.blocked = True
                        entry.blocked_until = now + 60.0  # Block for 1 minute
                        self.clients[client_ip] = entry
                        rate_limit_blocks.labels(client_ip=client_ip).inc()
                        return False, f"Rate limit exceeded ({self.rpm} req/min)"

                    # Add current request
                    entry.requests.append(now)
                    self.clients[client_ip] = entry
                    return True, ""

            async def cleanup(self):
                """Periodic cleanup of old entries."""
                while True:
                    await asyncio.sleep(300)  # Every 5 minutes
                    async with self._lock:
                        now = time.time()
                        to_delete = [
                            ip for ip, entry in self.clients.items()
                            if not entry.blocked and (not entry.requests or now - max(entry.requests) > 3600)
                        ]
                        for ip in to_delete:
                            del self.clients[ip]

        rate_limiter = RateLimiter(RATE_LIMIT_RPM)

        # ============================================================================
        # ROUTER & RERANKER
        # ============================================================================

        @dataclass
        class ModelInfo:
            id: str
            name: str
            context_length: int = 262144  # Qwen3.5 supports 256K!
            priority: int = 0
            capabilities: List[str] = field(default_factory=list)
            estimated_tokens_per_second: float = 50.0

        @dataclass
        class RouteDecision:
            model: str
            confidence: float
            reason: str
            estimated_tokens: int
            backend: str = BACKEND_URL

        class Router:
            """Intelligent router with prompt analysis and model selection."""

            # Rough token estimation: ~4 chars per token
            CHARS_PER_TOKEN = 4

            def __init__(self):
                self.models: Dict[str, ModelInfo] = {}
                self.routing_rules: List[Dict[str, Any]] = []

            def set_models(self, models: List[Dict[str, Any]]):
                """Update available models from backend."""
                self.models = {}
                for model in models:
                    model_id = model.get("id", "")
                    if model_id:
                        # Extract model info
                        context_len = model.get("context_length", 262144)  # Default to 256K for Qwen3.5
                        self.models[model_id] = ModelInfo(
                            id=model_id,
                            name=model.get("id", model_id),
                            context_length=context_len,
                            priority=self._calculate_priority(model_id)
                        )

            def _calculate_priority(self, model_id: str) -> int:
                """Calculate priority based on model characteristics."""
                # Larger models generally have higher priority
                if "35b" in model_id.lower() or "33b" in model_id.lower():
                    return 100
                elif "14b" in model_id.lower() or "13b" in model_id.lower():
                    return 75
                elif "9b" in model_id.lower() or "7b" in model_id.lower():
                    return 50
                elif "4b" in model_id.lower() or "3b" in model_id.lower():
                    return 25
                return 10

            def estimate_tokens(self, text: str) -> int:
                """Estimate token count for text."""
                return max(1, len(text) // self.CHARS_PER_TOKEN)

            def estimate_input_tokens(self, messages: List[Dict[str, Any]]) -> int:
                """Estimate total input tokens from messages."""
                total = 0
                for msg in messages:
                    content = msg.get("content", "")
                    total += self.estimate_tokens(content)
                return total

            def analyze_prompt(self, messages: List[Dict[str, Any]]) -> Dict[str, Any]:
                """Analyze prompt to determine complexity and requirements."""
                analysis = {
                    "estimated_tokens": 0,
                    "complexity": "medium",
                    "has_code": False,
                    "has_structured_data": False,
                    "language": "unknown",
                    "requires_reasoning": False
                }

                # Combine all message content
                all_text = " ".join([msg.get("content", "") for msg in messages])
                analysis["estimated_tokens"] = self.estimate_input_tokens(messages)

                # Detect code
                code_indicators = ["```", "def ", "class ", "function", "import ", "#include", "public class"]
                analysis["has_code"] = any(indicator in all_text for indicator in code_indicators)

                # Detect structured data
                analysis["has_structured_data"] = any(marker in all_text for marker in ["{", "}", "[", "]", "JSON"])

                # Detect reasoning requirements
                reasoning_words = ["explain", "why", "how", "analyze", "compare", "evaluate", "reason"]
                analysis["requires_reasoning"] = any(word in all_text.lower() for word in reasoning_words)

                # Determine complexity
                if analysis["estimated_tokens"] > 10000 or analysis["has_code"]:
                    analysis["complexity"] = "high"
                elif analysis["estimated_tokens"] < 1000:
                    analysis["complexity"] = "low"

                return analysis

            def select_model(self, messages: List[Dict[str, Any]], requested_model: Optional[str] = None) -> RouteDecision:
                """Select best model for given request."""
                analysis = self.analyze_prompt(messages)
                estimated_tokens = analysis["estimated_tokens"]

                # If user specified a model and it exists locally, use it
                if requested_model and requested_model in self.models:
                    return RouteDecision(
                        model=requested_model,
                        confidence=1.0,
                        reason="User specified model (local)",
                        estimated_tokens=estimated_tokens,
                        backend="lm-studio"
                    )

                # If user specified a model but it's NOT available locally, route to ZAI
                if requested_model and requested_model not in self.models:
                    return RouteDecision(
                        model=requested_model,
                        confidence=1.0,
                        reason="User specified model (not available locally, routing to fallback)",
                        estimated_tokens=estimated_tokens,
                        backend="zai"
                    )

                # If user specified a model that doesn't exist, find closest match
                if requested_model:
                    for model_id, model_info in self.models.items():
                        if requested_model.lower() in model_id.lower():
                            return RouteDecision(
                                model=model_id,
                                confidence=0.9,
                                reason="Close match to requested model",
                                estimated_tokens=estimated_tokens
                            )

                # Intelligent routing based on analysis
                if not self.models:
                    # Fallback to default if no models available
                    return RouteDecision(
                        model=DEFAULT_MODEL,
                        confidence=0.5,
                        reason="No models discovered, using default",
                        estimated_tokens=estimated_tokens
                    )

                # Select model based on token count and complexity
                best_model = None
                best_score = -1

                for model_id, model_info in sorted(self.models.items(), key=lambda x: x[1].priority, reverse=True):
                    score = model_info.priority

                    # Penalize if context length is insufficient
                    if estimated_tokens > model_info.context_length:
                        score *= 0.1

                    # Boost for high complexity requests to larger models
                    if analysis["complexity"] == "high" and model_info.priority >= 50:
                        score *= 1.5
                    elif analysis["complexity"] == "low" and model_info.priority < 50:
                        score *= 1.2

                    if score > best_score:
                        best_score = score
                        best_model = model_id

                if best_model:
                    return RouteDecision(
                        model=best_model,
                        confidence=min(1.0, best_score / 100),
                        reason=f"Selected based on {analysis['complexity']} complexity (~{estimated_tokens} tokens)",
                        estimated_tokens=estimated_tokens
                    )

                # Final fallback
                return RouteDecision(
                    model=list(self.models.keys())[0] if self.models else DEFAULT_MODEL,
                    confidence=0.3,
                    reason="Fallback selection",
                    estimated_tokens=estimated_tokens
                )

        router = Router()

        # Simple latency tracker for routing optimization
        class SimpleLatencyTracker:
            """Track model response times for latency-aware routing."""
            def __init__(self):
                self.latencies = {}

            async def record_latency(self, model: str, latency_ms: float):
                """Record a latency measurement."""
                if model not in self.latencies:
                    self.latencies[model] = []
                self.latencies[model].append(latency_ms)
                # Keep only last 100 measurements
                if len(self.latencies[model]) > 100:
                    self.latencies[model] = self.latencies[model][-100:]

            async def get_avg_latency(self, model: str):
                """Get average latency for a model."""
                if model not in self.latencies or not self.latencies[model]:
                    return None
                return sum(self.latencies[model]) / len(self.latencies[model])

        latency_tracker = SimpleLatencyTracker()

        # ============================================================================
        # BACKEND POOL & CIRCUIT BREAKER
        # ============================================================================

        class CircuitState(Enum):
            CLOSED = "closed"      # Normal operation
            OPEN = "open"          # Failing, not accepting requests
            HALF_OPEN = "half_open"  # Testing if recovered

        @dataclass
        class CircuitBreakerConfig:
            failure_threshold: int = 5      # Failures before opening
            recovery_timeout: float = 60.0  # Seconds before half-open
            half_open_calls: int = 3        # Calls allowed in half-open

        @dataclass
        class CircuitBreakerState:
            state: CircuitState = CircuitState.CLOSED
            failures: int = 0
            last_failure_time: float = 0.0
            half_open_calls_made: int = 0
            last_success_time: float = 0.0

        class CircuitBreaker:
            """Circuit breaker for backend failover."""

            def __init__(self, backend_url: str, config: CircuitBreakerConfig = None):
                self.backend_url = backend_url
                self.config = config or CircuitBreakerConfig()
                self.state = CircuitBreakerState()
                self._lock = asyncio.Lock()

            async def can_request(self) -> bool:
                """Check if requests can be made to this backend."""
                async with self._lock:
                    if self.state.state == CircuitState.OPEN:
                        # Check if we should try half-open
                        if time.time() - self.state.last_failure_time >= self.config.recovery_timeout:
                            self.state.state = CircuitState.HALF_OPEN
                            self.state.half_open_calls_made = 0
                            logger.warning("Circuit breaker in half-open state", extra={"backend": self.backend_url, "state": "half_open"})
                            return True
                        return False

                    return True

            async def record_success(self):
                """Record a successful request."""
                async with self._lock:
                    self.state.failures = 0
                    self.state.last_success_time = time.time()

                    if self.state.state == CircuitState.HALF_OPEN:
                        self.state.half_open_calls_made += 1
                        if self.state.half_open_calls_made >= self.config.half_open_calls:
                            self.state.state = CircuitState.CLOSED
                            logger.info("Circuit breaker recovered", extra={"backend": self.backend_url, "state": "closed"})

            async def record_failure(self):
                """Record a failed request."""
                async with self._lock:
                    self.state.failures += 1
                    self.state.last_failure_time = time.time()

                    if self.state.failures >= self.config.failure_threshold:
                        if self.state.state != CircuitState.OPEN:
                            self.state.state = CircuitState.OPEN
                            circuit_breaker_trips.labels(backend_url=self.backend_url).inc()
                            logger.error("Circuit breaker opened due to failures", extra={"backend": self.backend_url, "state": "open", "failures": self.state.failures})

            def is_healthy(self) -> bool:
                return self.state.state != CircuitState.OPEN

        class BackendClient:
            """HTTP client with circuit breaker and health monitoring."""

            def __init__(self, url: str, headers: Dict[str, str] = None):
                self.url = url
                self.headers = headers or {}
                self.client = httpx.AsyncClient(base_url=url, timeout=300.0, headers=headers)
                self.circuit_breaker = CircuitBreaker(url)
                self.health_status = True
                self.last_health_check = 0.0

            async def is_available(self) -> bool:
                """Check if backend is available (circuit breaker + health)."""
                return await self.circuit_breaker.can_request()

            async def request(self, method: str, path: str, **kwargs) -> httpx.Response:
                """Make request with circuit breaker protection."""
                if not await self.circuit_breaker.can_request():
                    raise HTTPException(
                        status_code=503,
                        detail=f"Backend {self.url} is temporarily unavailable (circuit breaker open)"
                    )

                try:
                    response = await self.client.request(method, path, **kwargs)

                    if response.status_code >= 500:
                        await self.circuit_breaker.record_failure()
                    else:
                        await self.circuit_breaker.record_success()

                    return response

                except Exception as e:
                    await self.circuit_breaker.record_failure()
                    raise

            async def close(self):
                await self.client.aclose()

        # ============================================================================
        # FALLBACK BACKEND MANAGEMENT
        # ============================================================================

        class FallbackBackend:
            """Manages primary backend with ZAI fallback."""

            def __init__(self, primary: BackendClient, fallback: BackendClient = None):
                self.primary = primary
                self.fallback = fallback
                self.fallback_used = False

            async def is_available(self) -> bool:
                """Check if primary is available."""
                return await self.primary.is_available()

            async def request_with_fallback(self, method: str, path: str, **kwargs) -> httpx.Response:
                """Try primary, fallback to ZAI if unavailable."""
                self.fallback_used = False

                # Try primary first
                if await self.primary.is_available():
                    try:
                        response = await self.primary.request(method, path, **kwargs)
                        return response
                    except HTTPException as e:
                        if e.status_code == 503 and self.fallback:
                            logger.warning("Primary backend unavailable, using ZAI fallback")
                            self.fallback_used = True
                            return await self.fallback.request(method, path, **kwargs)
                        raise
                elif self.fallback:
                    # Primary circuit breaker open, use fallback
                    logger.warning("Circuit breaker open, using ZAI fallback")
                    self.fallback_used = True
                    return await self.fallback.request(method, path, **kwargs)
                else:
                    # No fallback available, raise unavailable
                    raise HTTPException(
                        status_code=503,
                        detail=f"Backend {self.primary.url} is temporarily unavailable (circuit breaker open, no fallback configured)"
                    )

            async def close(self):
                await self.primary.close()
                if self.fallback:
                    await self.fallback.close()

        # Primary backend (LM Studio)
        backend_client = BackendClient(BACKEND_URL, backend_headers)

        # Fallback backend (ZAI)
        fallback_client = None
        if ZAI_API_KEY and ZAI_BASE_URL and ROUTING_ENABLED:
            fallback_headers = {"Authorization": f"Bearer {ZAI_API_KEY}"}
            fallback_client = BackendClient(ZAI_BASE_URL, fallback_headers)
            logger.info("ZAI fallback backend configured", extra={"url": ZAI_BASE_URL})

        # Unified backend with fallback
        backend = FallbackBackend(backend_client, fallback_client)

        # ============================================================================
        # MODEL CACHE
        # ============================================================================

        class ModelCache:
            def __init__(self):
                self.models: List[Dict[str, Any]] = []
                self.last_refresh: Optional[float] = None
                self._lock = asyncio.Lock()

            async def get(self) -> List[Dict[str, Any]]:
                async with self._lock:
                    return list(self.models)

            async def refresh_multi(self, primary: BackendClient, fallback: BackendClient = None) -> bool:
                """Refresh models from multiple backends and merge them."""
                models_to_add = []
                
                # Refresh primary backend models
                try:
                    resp = await primary.client.get("/v1/models", timeout=10.0)
                    if resp.status_code == 200:
                        data = resp.json()
                        raw_models = data.get("data", [])
                        for model in raw_models:
                            model["backend"] = "lm-studio"
                        models_to_add.extend(raw_models)
                        
                        await primary.circuit_breaker.record_success()
                        logger.info("Refreshed models from LM Studio", extra={"count": len(raw_models), "backend": "lm-studio"})
                    else:
                        await primary.circuit_breaker.record_failure()
                        logger.error("Failed to refresh LM Studio models")
                except Exception as e:
                    await primary.circuit_breaker.record_failure()
                    logger.error("Failed to refresh LM Studio models", extra={"error": str(e)})
                
                # Refresh fallback backend models
                if fallback:
                    try:
                        resp = await fallback.client.get("/v1/models", timeout=10.0)
                        if resp.status_code == 200:
                            data = resp.json()
                            raw_models = data.get("data", [])
                            for model in raw_models:
                                model["backend"] = "zai"
                            models_to_add.extend(raw_models)
                            
                            await fallback.circuit_breaker.record_success()
                            logger.info("Refreshed models from ZAI", extra={"count": len(raw_models), "backend": "zai"})
                        else:
                            await fallback.circuit_breaker.record_failure()
                            logger.error("Failed to refresh ZAI models")
                    except Exception as e:
                        await fallback.circuit_breaker.record_failure()
                        logger.error("Failed to refresh ZAI models", extra={"error": str(e)})
                
                # Merge and update models
                async with self._lock:
                    # Remove stale models by checking which backends are currently accessible
                    # For now, just append all models
                    self.models.extend(models_to_add)
                    self.last_refresh = time.time()
                    models_cache_size.set(len(self.models))
                    
                    # Update router with merged list
                    router.set_models(self.models)
                    
                    return True

            async def refresh(self, client: BackendClient) -> bool:
                """Refresh from single backend (legacy compatibility)."""
                return await self.refresh_multi(client, None)

            def age(self) -> float:
                if self.last_refresh is None:
                    return -1
                return time.time() - self.last_refresh

        model_cache = ModelCache()

        # ============================================================================
        # STRUCTURED OUTPUT SUPPORT
        # ============================================================================

        class StructuredOutputHandler:
            """Handle LM Studio structured output (JSON mode, JSON Schema)."""

            @staticmethod
            def process_request(body: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
                """Process response_format in request, return (modified_body, metadata)."""
                response_format = body.get("response_format", {})
                metadata = {"structured_output": False, "type": None}

                if not response_format:
                    return body, metadata

                format_type = response_format.get("type", "")

                if format_type == "json_object":
                    # Simple JSON mode
                    metadata["structured_output"] = True
                    metadata["type"] = "json_object"
                    # Add JSON instruction to system message
                    messages = body.get("messages", [])
                    system_msg = {
                        "role": "system",
                        "content": "You must respond with valid JSON only. No markdown, no code blocks, just the raw JSON object."
                    }
                    body["messages"] = [system_msg] + messages
                    structured_output_requests.labels(model=body.get("model", "unknown"), format_type="json_object").inc()

                elif format_type == "json_schema":
                    # JSON Schema mode - extract schema
                    json_schema = response_format.get("json_schema", {})
                    schema = json_schema.get("schema", {})

                    metadata["structured_output"] = True
                    metadata["type"] = "json_schema"
                    metadata["schema"] = schema

                    # Inject schema instructions into system message
                    schema_instruction = f"""You must respond with valid JSON that conforms to this schema:
    {json.dumps(schema, indent=2)}

    Requirements:
    - Respond ONLY with valid JSON
    - Do not include markdown code blocks
    - Do not include any explanation outside the JSON
    - Ensure all required fields are present
    - Match the exact structure specified"""

                    messages = body.get("messages", [])
                    system_msg = {
                        "role": "system",
                        "content": schema_instruction
                    }
                    body["messages"] = [system_msg] + messages
                    structured_output_requests.labels(model=body.get("model", "unknown"), format_type="json_schema").inc()

                return body, metadata

            @staticmethod
            def process_response(content: str, metadata: Dict[str, Any]) -> Tuple[str, bool]:
                """Validate and process structured output response."""
                if not metadata.get("structured_output"):
                    return content, True

                format_type = metadata.get("type", "")

                if format_type == "json_object":
                    try:
                        # Try to parse JSON, also strip markdown code blocks
                        cleaned = content.strip()
                        if cleaned.startswith("```json"):
                            cleaned = cleaned.split("```json")[1].split("```")[0].strip()
                        elif cleaned.startswith("```"):
                            cleaned = cleaned.split("```")[1].split("```")[0].strip()

                        json.loads(cleaned)  # Validate
                        return cleaned, True
                    except json.JSONDecodeError:
                        # Invalid JSON, return as-is but mark validation failed
                        return content, False

                elif format_type == "json_schema":
                    try:
                        schema = metadata.get("schema", {})
                        cleaned = content.strip()
                        if cleaned.startswith("```json"):
                            cleaned = cleaned.split("```json")[1].split("```")[0].strip()
                        elif cleaned.startswith("```"):
                            cleaned = cleaned.split("```")[1].split("```")[0].strip()

                        parsed = json.loads(cleaned)
                        # Basic schema validation (could be enhanced with jsonschema library)
                        # For now, just ensure it's valid JSON
                        return cleaned, True
                    except json.JSONDecodeError:
                        return content, False

                return content, True

        structured_output_handler = StructuredOutputHandler()

        # ============================================================================
        # TOOLS / FUNCTION CALLING SUPPORT
        # ============================================================================

        class ToolsHandler:
            """Handle OpenAI-compatible function calling."""

            def __init__(self, mcp_broker):
                self.mcp_broker = mcp_broker

            def process_request(self, body: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
                """Process tools in request, return (modified_body, metadata)."""
                tools = body.get("tools", [])
                tool_choice = body.get("tool_choice", "auto")

                metadata = {
                    "has_tools": len(tools) > 0,
                    "tool_choice": tool_choice,
                    "tools_count": len(tools)
                }

                if not tools:
                    return body, metadata

                # LM Studio/OpenAI function calling format
                # The tools array should be passed through to the backend
                # LM Studio supports native function calling
                return body, metadata

            async def handle_tool_call(self, tool_call: Dict[str, Any], model: str) -> Dict[str, Any]:
                """Execute a tool call via MCP broker or direct execution."""
                function_name = tool_call.get("function", {}).get("name", "")
                arguments_str = tool_call.get("function", {}).get("arguments", "{}")

                try:
                    arguments = json.loads(arguments_str) if isinstance(arguments_str, str) else arguments_str
                except:
                    arguments = {}

                # Try to execute via MCP broker if tool name matches pattern
                # Format: mcp:<server_name>:<tool_name>
                if function_name.startswith("mcp:"):
                    parts = function_name.split(":")
                    if len(parts) >= 3:
                        server_name = parts[1]
                        tool_name = ":".join(parts[2:])  # Handle colons in tool names

                        result = await self.mcp_broker.call_tool(server_name, tool_name, arguments)
                        tool_calls.labels(model=model, tool_name=function_name).inc()

                        return {
                            "tool_call_id": tool_call.get("id", ""),
                            "role": "tool",
                            "name": function_name,
                            "content": json.dumps(result)
                        }

                # If not MCP tool, return error for now
                # In production, you might want to execute local functions here
                return {
                    "tool_call_id": tool_call.get("id", ""),
                    "role": "tool",
                    "name": function_name,
                    "content": json.dumps({"error": f"Tool {function_name} not implemented"})
                }

        # ============================================================================
        # PREDICTION STATS TRACKER
        # ============================================================================

        @dataclass
        class PredictionStats:
            """Track detailed prediction statistics."""
            start_time: float = 0.0
            first_token_time: Optional[float] = None
            end_time: float = 0.0
            prompt_tokens: int = 0
            completion_tokens: int = 0
            total_tokens: int = 0
            stop_reason: str = ""

            @property
            def time_to_first_token(self) -> float:
                if self.first_token_time:
                    return self.first_token_time - self.start_time
                return 0.0

            @property
            def duration(self) -> float:
                return self.end_time - self.start_time

            @property
            def tokens_per_second(self) -> float:
                if self.duration > 0 and self.completion_tokens > 0:
                    return self.completion_tokens / self.duration
                return 0.0

            def to_dict(self) -> Dict[str, Any]:
                return {
                    "time_to_first_token_seconds": round(self.time_to_first_token, 3),
                    "duration_seconds": round(self.duration, 3),
                    "tokens_per_second": round(self.tokens_per_second, 2),
                    "prompt_tokens": self.prompt_tokens,
                    "completion_tokens": self.completion_tokens,
                    "total_tokens": self.total_tokens,
                    "stop_reason": self.stop_reason
                }

        # Global stats tracking
        active_predictions: Dict[str, PredictionStats] = {}

        async def background_refresh():
            """Periodically refresh models and health from all backends."""
            while True:
                await asyncio.sleep(60)
                await model_cache.refresh_multi(backend.primary, backend.fallback)
                models_cache_age.set(model_cache.age())
                backend_health.labels(backend_type="lm-studio").set(1 if backend.primary.circuit_breaker.is_healthy() else 0)
                if backend.fallback:
                    backend_health.labels(backend_type="zai").set(1 if backend.fallback.circuit_breaker.is_healthy() else 0)

        # ============================================================================
        # FASTAPI APP
        # ============================================================================

        app = FastAPI(
            title="AI Inference Gateway v2",
            description="Advanced gateway with routing, failover, and security",
            version="2.0.0"
        )

        @app.on_event("startup")
        async def startup():
            # Initial model fetch
            await model_cache.refresh(backend.primary)
            models_cache_age.set(0)

            # Start background tasks
            asyncio.create_task(background_refresh())
            asyncio.create_task(rate_limiter.cleanup())

            models = await model_cache.get()
            logger.info("Gateway started", extra={"host": GATEWAY_HOST, "version": "2.0"})
            logger.info("Backend configured", extra={"type": BACKEND_TYPE, "url": BACKEND_URL})
            logger.info("Fallback configuration", extra={"url": ZAI_BASE_URL if backend.fallback else "disabled"})
            logger.info("Security configuration", extra={"auth_mode": AUTH_MODE, "rate_limiting": RATE_LIMIT_ENABLED})
            logger.info("Models loaded", extra={"count": len(models)})
            logger.info("Routing configuration", extra={"enabled": ROUTING_ENABLED})
            if RAG_ENABLED and rag_engine.enabled:
                logger.info("RAG configuration", extra={"qdrant_url": QDRANT_URL, "hybrid_search": HYBRID_SEARCH_ENABLED})

        @app.on_event("shutdown")
        async def shutdown():
            await backend.close()

        # ============================================================================
        # HEALTH & METRICS
        # ============================================================================

        @app.get("/health")
        async def health():
            """Comprehensive health check."""
            models = await model_cache.get()

            health_data = {
                "status": "healthy",
                "gateway": {
                    "version": "2.0.0",
                    "host": GATEWAY_HOST,
                    "auth_mode": AUTH_MODE,
                    "rate_limit_enabled": RATE_LIMIT_ENABLED,
                    "routing_enabled": ROUTING_ENABLED
                },
                "backend": {
                    "url": BACKEND_URL,
                    "type": BACKEND_TYPE,
                    "healthy": backend.primary.circuit_breaker.is_healthy(),
                    "circuit_state": backend.primary.circuit_breaker.state.state.value,
                    "fallback_enabled": backend.fallback is not None,
                    "fallback_url": ZAI_BASE_URL if backend.fallback else None
                },
                "models": {
                    "cached": len(models),
                    "cache_age_seconds": model_cache.age()
                }
            }

            # Add RAG status if enabled
            if RAG_ENABLED and rag_engine.enabled:
                try:
                    collections = rag_engine.qdrant_client.get_collections()
                    health_data["rag"] = {
                        "enabled": True,
                        "qdrant_url": QDRANT_URL,
                        "embedding_model": EMBEDDING_MODEL,
                        "hybrid_search": HYBRID_SEARCH_ENABLED,
                        "auto_rag": AUTO_RAG_ENABLED,
                        "collections_count": len(collections.collections),
                        "token_scoped": TOKEN_SCOPED_COLLECTIONS
                    }
                except Exception as e:
                    health_data["rag"] = {
                        "enabled": True,
                        "error": str(e)
                    }
            else:
                health_data["rag"] = {"enabled": False}

            return JSONResponse(health_data)

        @app.get("/usage")
        async def usage_analytics(
            start_date: str = None,
            end_date: str = None,
            model: str = None,
            backend: str = None
        ):
            """
            Usage analytics endpoint.

            Query parameters:
            - start_date: Start date (ISO format)
            - end_date: End date (ISO format)
            - model: Filter by model
            - backend: Filter by backend
            """
            # This would typically query a time-series database
            # For now, return current Prometheus metrics summary
            from prometheus_client import Counter as PrometheusCounter

            def get_counter_value(counter: PrometheusCounter, labels: dict = None) -> float:
                """Get current value of a counter metric using proper API."""
                try:
                    if labels:
                        metric = counter.labels(**labels)
                        samples = list(metric.collect())[0].samples
                        return samples[0].value if samples else 0.0
                    else:
                        # Get all samples and sum them
                        samples = list(counter.collect())[0].samples
                        return sum(s.value for s in samples)
                except Exception:
                    return 0.0

            usage_data = {
                "period": {
                    "start": start_date or "last 24 hours",
                    "end": end_date or "now"
                },
                "summary": {
                    "total_requests": int(get_counter_value(request_counter)),
                    "active_requests": int(active_requests._value.get() if hasattr(active_requests, '_value') else 0),
                    "total_prompt_tokens": int(get_counter_value(prompt_tokens)),
                    "total_completion_tokens": int(get_counter_value(completion_tokens)),
                    "estimated_cost_usd": round(float(get_counter_value(cost_tracker)), 4)
                },
                "by_model": {},
                "by_backend": {},
                "errors": {
                    "total": int(get_counter_value(errors_total)),
                    "by_type": {}
                },
                "performance": {
                    "avg_request_duration": "N/A",
                    "avg_tokens_per_second": "N/A",
                    "p95_request_duration": "N/A"
                }
            }

            # Add per-model breakdown
            try:
                for model_name in [selected_model]:
                    if model_name and (not model or model == model_name):
                        usage_data["by_model"][model_name] = {
                            "requests": int(get_counter_value(request_counter, {"model": model_name})),
                            "prompt_tokens": int(get_counter_value(prompt_tokens, {"model": model_name})),
                            "completion_tokens": int(get_counter_value(completion_tokens, {"model": model_name}))
                        }
            except Exception:
                pass

            return JSONResponse(usage_data)

        # ============================================================================
        # SEMANTIC CACHE MANAGEMENT ENDPOINTS
        # ============================================================================

        @app.get("/cache/stats")
        async def cache_stats():
            """Get semantic cache statistics."""
            if not semantic_cache or not semantic_cache.enabled:
                return JSONResponse({"enabled": False, "message": "Semantic cache not enabled"})

            stats = await semantic_cache.get_stats()

            # Get cache metrics using proper Prometheus API
            def get_metric_value(metric, labels_dict):
                try:
                    labeled_metric = metric.labels(**labels_dict)
                    samples = list(labeled_metric.collect())[0].samples
                    return int(samples[0].value) if samples else 0
                except Exception:
                    return 0

            stats["metrics"] = {
                "hits": get_metric_value(cache_hits, {"cache_type": "semantic"}),
                "misses": get_metric_value(cache_misses, {"cache_type": "semantic"})
            }
            if stats["metrics"]["hits"] or stats["metrics"]["misses"]:
                stats["hit_rate"] = stats["metrics"]["hits"] / (stats["metrics"]["hits"] + stats["metrics"]["misses"])
            else:
                stats["hit_rate"] = 0.0

            return JSONResponse(stats)

        @app.post("/cache/invalidate")
        async def cache_invalidate(
            model: str = None,
            older_than: int = None
        ):
            """Invalidate cache entries.

            Parameters:
            - model: Only invalidate entries for this model
            - older_than: Invalidate entries older than this many seconds
            """
            if not semantic_cache or not semantic_cache.enabled:
                raise HTTPException(status_code=400, detail="Semantic cache not enabled")

            await semantic_cache.invalidate(model=model, older_than=older_than)

            return JSONResponse({
                "status": "success",
                "invalidated": {
                    "model": model or "all",
                    "older_than_seconds": older_than or "all"
                }
            })

        @app.get("/metrics")
        async def metrics():
            """Prometheus metrics."""
            models_cache_age.set(model_cache.age())
            backend_health.labels(backend_type=BACKEND_TYPE).set(1 if backend_client.circuit_breaker.is_healthy() else 0)
            return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)

        # ============================================================================
        # MODELS ENDPOINT
        # ============================================================================

        @app.get("/v1/models")
        async def list_models():
            """List available models."""
            models = await model_cache.get()

            if not models:
                # Try to refresh
                await model_cache.refresh(backend_client)
                models = await model_cache.get()

            return JSONResponse({
                "object": "list",
                "data": models,
                "gateway": {
                    "backend_type": BACKEND_TYPE,
                    "cache_age_seconds": model_cache.age(),
                    "routing_enabled": ROUTING_ENABLED
                }
            })

        # ============================================================================
        # CHAT COMPLETIONS WITH ROUTING
        # ============================================================================

        async def verify_auth(request: Request) -> Optional[dict]:
            if AUTH_MODE == "none":
                return {"tier": "personal", "allowed": True}
            client_ip = request.client.host
            if AUTH_MODE == "tailscale":
                is_tailscale = client_ip.startswith("100.") or client_ip.startswith("fd7a:") or client_ip == "127.0.0.1"
                if is_tailscale:
                    return {"tier": "trusted", "allowed": True}
                raise HTTPException(status_code=403, detail="Access restricted to Tailscale network")
            if AUTH_MODE == "api-key":
                auth_header = request.headers.get("Authorization", "")
                if not auth_header.startswith("Bearer "):
                    raise HTTPException(status_code=401, detail="Missing API key")
                # Validate API key against LM Studio API key
                provided_key = auth_header.replace("Bearer ", "").strip()
                if LM_STUDIO_API_KEY and provided_key != LM_STUDIO_API_KEY:
                    raise HTTPException(status_code=403, detail="Invalid API key")
                return {"tier": "api", "allowed": True}
            return {"tier": "unknown", "allowed": False}

        @app.post("/v1/chat/completions")
        async def chat_completions(request: Request):
            """Chat completions with routing, security, failover, RAG, structured output, and tools."""
            active_requests.inc()
            start_time = time.time()
            request_id = hashlib.md5(str(time.time()).encode()).hexdigest()[:16]

            # Initialize prediction stats
            prediction_stats = PredictionStats(start_time=start_time)
            active_predictions[request_id] = prediction_stats

            try:
                # Authentication
                auth_result = await verify_auth(request)
                if not auth_result.get("allowed"):
                    request_counter.labels(model="unknown", status="unauthorized", backend="none", auth_mode=AUTH_MODE).inc()
                    raise HTTPException(status_code=403, detail="Authentication failed")

                # Rate limiting
                client_ip = request.client.host
                allowed, limit_msg = await rate_limiter.check(client_ip)
                if not allowed:
                    request_counter.labels(model="unknown", status="rate_limited", backend="none", auth_mode=AUTH_MODE).inc()
                    raise HTTPException(status_code=429, detail=limit_msg)

                # Parse request
                body = await request.json()

                # Security check (can be disabled for local development)
                if SECURITY_PROXY_ENABLED:
                    security_check = security_proxy.check_request(body)
                    if security_check.level == SecurityLevel.BLOCKED:
                        security_blocks.labels(reason=security_check.reason).inc()
                        request_counter.labels(model="unknown", status="blocked", backend="none", auth_mode=AUTH_MODE).inc()
                        raise HTTPException(status_code=400, detail=f"Request blocked: {security_check.reason}")

                # Process structured output (response_format)
                body, structured_metadata = structured_output_handler.process_request(body)

                # Process tools/function calling
                body, tools_metadata = tools_handler.process_request(body)

                # Model routing
                messages = body.get("messages", [])
                requested_model = body.get("model")

                if ROUTING_ENABLED:
                    route_decision = router.select_model(messages, requested_model)
                    selected_model = route_decision.model
                    target_backend = route_decision.backend
                else:
                    selected_model = requested_model or DEFAULT_MODEL
                    target_backend = "lm-studio"  # Default to local

                # Update request with selected model
                body["model"] = selected_model

                # Determine which backend to use
                if target_backend == "zai" and backend.fallback:
                    # User requested non-local model, go directly to fallback
                    effective_backend = backend.fallback
                elif target_backend == "lm-studio":
                    # Use local backend
                    effective_backend = backend.primary
                else:
                    # Default behavior: try primary with fallback
                    effective_backend = backend.primary if not backend.fallback_used else backend.fallback

                # RAG: Check if we should augment with retrieved context
                rag_context = ""
                rag_used = False
                if RAG_ENABLED and messages:
                    # Get the last user message
                    last_user_msg = None
                    for msg in reversed(messages):
                        if msg.get("role") == "user":
                            last_user_msg = msg.get("content", "")
                            break

                    if last_user_msg:
                        auth_token = rag_engine._get_token_from_request(request)
                        collection = body.get("rag_collection", "default")

                        # Check if RAG should be used
                        use_rag = body.get("use_rag")  # Explicit request
                        if use_rag is None:
                            # Auto-detect
                            use_rag = rag_engine.should_use_rag(last_user_msg, auth_token)

                        if use_rag:
                            retrieval_result = await rag_engine.hybrid_search(
                                query=last_user_msg,
                                collection=collection,
                                top_k=body.get("rag_top_k", RAG_TOP_K),
                                token=auth_token
                            )

                            if retrieval_result.chunks:
                                rag_context = rag_engine.format_context(retrieval_result)

                # Semantic Caching: Check for similar cached responses
                use_cache = body.get("use_cache", True)  # Enable by default
                cache_result = None

                if use_cache and semantic_cache is not None and semantic_cache.enabled:
                    # Generate query embedding from messages
                    query_text = " ".join(["{}: {}".format(msg.get("role", ""), msg.get("content", "")) for msg in messages[-3:]])
                    query_embedding = await rag_engine.embed_text(query_text)

                    if query_embedding:
                        # Check cache
                        cache_result = await semantic_cache.get(
                            query_embedding=query_embedding,
                            model=selected_model,
                            threshold=0.75  # Lower threshold for more cache hits
                        )

                        if cache_result and cache_result.get("hit"):
                            logger.info("Cache hit", extra={"score": cache_result["score"], "cache_type": "semantic"})

                            # Return cached response
                            cached_response = cache_result["response"]

                            # Update metadata
                            cached_response.setdefault("usage", {})["cache_hit"] = True
                            cached_response.setdefault("usage", {})["cache_score"] = cache_result["score"]
                            cached_response.setdefault("usage", {})["cached_at"] = cache_result["cached_at"]

                            request_counter.labels(
                                model=selected_model,
                                status="cache_hit",
                                backend="semantic_cache",
                                auth_mode=auth_result["tier"]
                            ).inc()

                            return JSONResponse(cached_response, status_code=200)

                # RAG: Inject retrieved context into messages
                if rag_context:
                    rag_used = True

                    # Inject context into messages
                    system_prompt = body.get("rag_system_prompt",
                        "Use the following retrieved context to answer the user's question. " +
                        "If the context doesn't contain relevant information, say so.")

                    context_message = {
                        "role": "system",
                        "content": "{}\n\nRetrieved Context:\n{}".format(system_prompt, rag_context)
                    }

                    # Insert context before user messages
                    body["messages"] = [context_message] + messages

                # Make request with fallback
                stream = body.get("stream", False)

                if stream:
                    async def generate():
                        first_chunk = True
                        try:
                            async with effective_backend.client.stream(
                                "POST", "/v1/chat/completions",
                                json=body,
                                headers={"Content-Type": "application/json"}
                            ) as backend_resp:
                                async for chunk_bytes in backend_resp.aiter_bytes():
                                    if first_chunk:
                                        prediction_stats.first_token_time = time.time()
                                        first_chunk = False
                                    yield chunk_bytes

                            # Record final stats
                            prediction_stats.end_time = time.time()
                            time_to_first_token.labels(model=selected_model, backend=effective_backend.url).observe(
                                prediction_stats.time_to_first_token
                        )
                        except HTTPException as e:
                            logger.exception("Stream error during response", exc_info=True)
                        finally:
                            if request_id in active_predictions:
                                del active_predictions[request_id]

                    return StreamingResponse(generate(), media_type="text/event-stream")
                else:
                    backend_resp = await effective_backend.request("POST", "/v1/chat/completions", json=body)
                    result = backend_resp.json()

                    # Record completion time
                    prediction_stats.end_time = time.time()

                    # Extract choices from result
                    choices = result.get("choices", [])

                    # Process structured output response
                    if structured_metadata.get("structured_output"):
                        if choices:
                            content = choices[0].get("message", {}).get("content", "")
                            processed_content, is_valid = structured_output_handler.process_response(content, structured_metadata)
                            if choices[0].get("message"):
                                choices[0]["message"]["content"] = processed_content

                    # Track metrics
                    if backend_resp.status_code == 200:
                        usage = result.get("usage", {})
                        prediction_stats.prompt_tokens = usage.get("prompt_tokens", 0)
                        prediction_stats.completion_tokens = usage.get("completion_tokens", 0)
                        prediction_stats.total_tokens = usage.get("total_tokens", 0)
                        prediction_stats.stop_reason = choices[0].get("finish_reason", "unknown") if choices else "unknown"

                        if usage:
                            tokens_generated.labels(model=selected_model, backend=effective_backend.type).inc(
                                usage.get("completion_tokens", 0)
                            )
                            prompt_tokens.labels(model=selected_model, backend=effective_backend.type).inc(
                                usage.get("prompt_tokens", 0)
                            )
                            completion_tokens.labels(model=selected_model, backend=effective_backend.type).inc(
                                usage.get("completion_tokens", 0)
                            )

                            # Enhanced usage analytics (re-enabled with low-cardinality backend.type labels)
                            total_tokens.labels(
                                model=selected_model,
                                backend=effective_backend.type,
                                token_type="prompt"
                            ).inc(usage.get("prompt_tokens", 0))

                            total_tokens.labels(
                                model=selected_model,
                                backend=effective_backend.type,
                                token_type="completion"
                            ).inc(usage.get("completion_tokens", 0))

                            tokens_per_request.labels(model=selected_model).observe(
                                usage.get("total_tokens", 0)
                            )

                            # Cost estimation
                            cost_per_million = 0.0
                            if effective_backend.type == "zai":
                                cost_per_million = 2.0

                            total_prompt_tokens = usage.get("prompt_tokens", 0)
                            total_completion_tokens = usage.get("completion_tokens", 0)
                            estimated_cost = (
                                (total_prompt_tokens / 1_000_000) * cost_per_million +
                                (total_completion_tokens / 1_000_000) * cost_per_million * 2
                            )
                            cost_tracker.labels(
                                model=selected_model,
                                backend=effective_backend.type
                            ).inc(estimated_cost)

                    duration = time.time() - start_time
                    request_duration.labels(model=selected_model, backend=effective_backend.type).observe(duration)
                    request_counter.labels(
                        model=selected_model,
                        status="success" if backend_resp.status_code == 200 else "error",
                        backend=effective_backend.type,
                        auth_mode=auth_result["tier"]
                    ).inc()

                    # Add enhanced metadata to response
                    if isinstance(result, dict):
                        # RAG metadata
                        if rag_used:
                            result.setdefault("usage", {})["rag_sources_used"] = len(rag_context.split("[Source")) if rag_context else 0
                            result["rag_metadata"] = {
                                "enabled": True,
                                "retrieval_method": "hybrid" if HYBRID_SEARCH_ENABLED else "vector",
                                "context_length": len(rag_context)
                            }

                        # Routing metadata
                        result["gateway_routing"] = {
                            "backend": "zai" if effective_backend == backend.fallback else "lm-studio",
                            "backend_url": effective_backend.url,
                            "model": selected_model,
                            "routing_reason": route_decision.reason if ROUTING_ENABLED else "default"
                        }

                        # Structured output metadata
                        if structured_metadata.get("structured_output"):
                            result["structured_output"] = {
                                "enabled": True,
                                "type": structured_metadata.get("type"),
                                "validated": True
                            }

                        # Tools metadata
                        if tools_metadata.get("has_tools"):
                            result["tools_metadata"] = {
                                "tools_count": tools_metadata.get("tools_count", 0),
                                "tool_choice": tools_metadata.get("tool_choice", "auto")
                            }

                        # Prediction statistics
                        result["prediction_stats"] = prediction_stats.to_dict()

                    # Semantic Caching: Store successful responses
                    if use_cache and semantic_cache is not None and semantic_cache.enabled and backend_resp.status_code == 200:
                        # Generate query embedding for caching
                        query_text = " ".join(["{}: {}".format(msg.get("role", ""), msg.get("content", "")) for msg in messages[-3:]])
                        query_embedding = await rag_engine.embed_text(query_text)

                        if query_embedding:
                            # Store in cache asynchronously (don't block response)
                            import asyncio
                            asyncio.create_task(
                                semantic_cache.set(
                                    query_embedding=query_embedding,
                                    response=result,
                                    model=selected_model,
                                    metadata={
                                        "prompt_tokens": prediction_stats.prompt_tokens,
                                        "completion_tokens": prediction_stats.completion_tokens,
                                        "request_id": request_id
                                    }
                                )
                            )

                    return JSONResponse(result, status_code=backend_resp.status_code)

            except HTTPException:
                raise
            except Exception as e:
                request_counter.labels(
                    model=selected_model if 'selected_model' in locals() else "unknown",
                    status="error",
                    backend=BACKEND_URL,
                    auth_mode=AUTH_MODE
                ).inc()
                return JSONResponse({"error": str(e)}, status_code=500)
            finally:
                active_requests.dec()

        # ============================================================================
        # OTHER ENDPOINTS (passthrough with security)
        # ============================================================================

        @app.post("/v1/completions")
        async def completions(request: Request):
            active_requests.inc()
            try:
                await verify_auth(request)
                client_ip = request.client.host
                allowed, _ = await rate_limiter.check(client_ip)
                if not allowed:
                    raise HTTPException(status_code=429, detail="Rate limited")

                body = await request.json()
                if SECURITY_PROXY_ENABLED:
                    security_check = security_proxy.check_request(body)
                    if security_check.level == SecurityLevel.BLOCKED:
                        raise HTTPException(status_code=400, detail=security_check.reason)

                backend_resp = await backend_client.request("POST", "/v1/completions", json=body)
                return JSONResponse(backend_resp.json(), status_code=backend_resp.status_code)
            except HTTPException:
                raise
            except Exception as e:
                return JSONResponse({"error": str(e)}, status_code=500)
            finally:
                active_requests.dec()

        @app.post("/v1/embeddings")
        async def embeddings(request: Request):
            active_requests.inc()
            try:
                await verify_auth(request)
                body = await request.json()
                backend_resp = await backend_client.request("POST", "/v1/embeddings", json=body)
                return JSONResponse(backend_resp.json(), status_code=backend_resp.status_code)
            except HTTPException:
                raise
            except Exception as e:
                return JSONResponse({"error": str(e)}, status_code=500)
            finally:
                active_requests.dec()

        # ============================================================================
        # MCP BROKERAGE
        # ============================================================================

        # MCP server configuration (from environment)
        MCP_SERVERS_JSON = os.getenv("MCP_SERVERS", "{}")

        @dataclass
        class MCPServer:
            name: str
            url: str
            headers: Dict[str, str] = None
            enabled: bool = True
            transport: str = "http"

        class MCPBroker:
            """MCP broker for aggregating and proxying MCP server requests."""

            def __init__(self):
                self.servers: Dict[str, MCPServer] = {}
                self.tools_cache: Dict[str, List[Dict]] = {}
                self.client_cache: Dict[str, httpx.AsyncClient] = {}
                self._load_servers()

            def _load_servers(self):
                """Load MCP servers from environment configuration."""
                try:
                    config = json.loads(MCP_SERVERS_JSON)
                    for name, server_config in config.items():
                        if server_config.get("enabled", True):
                            self.servers[name] = MCPServer(
                                name=name,
                                url=server_config["url"],
                                headers=server_config.get("headers", {}),
                                transport=server_config.get("transport", "http")
                            )
                    if self.servers:
                        logger.info("MCP servers loaded", extra={"count": len(self.servers)})
                except Exception as e:
                    logger.error("Failed to load MCP servers", exc_info=True)

            async def get_client(self, server: MCPServer) -> httpx.AsyncClient:
                """Get or create HTTP client for MCP server."""
                if server.name not in self.client_cache:
                    self.client_cache[server.name] = httpx.AsyncClient(
                        base_url=server.url,
                        headers=server.headers,
                        timeout=30.0
                    )
                return self.client_cache[server.name]

            async def list_tools(self, server_name: str = None) -> List[Dict]:
                """List tools from MCP server(s)."""
                tools = []
                servers_to_query = [self.servers[server_name]] if server_name else self.servers.values()

                for server in servers_to_query:
                    if not server.enabled:
                        continue
                    try:
                        client = await self.get_client(server)
                        resp = await client.get("/tools")
                        if resp.status_code == 200:
                            server_tools = resp.json().get("tools", [])
                            for tool in server_tools:
                                tool["mcp_server"] = server.name
                            tools.extend(server_tools)
                            self.tools_cache[server.name] = server_tools
                        else:
                            if server.name in self.tools_cache:
                                tools.extend(self.tools_cache[server.name])
                    except Exception as e:
                        logger.error("MCP server request failed", extra={"server": server.name, "error": str(e)})
                        if server.name in self.tools_cache:
                            tools.extend(self.tools_cache[server.name])
                return tools

            async def call_tool(self, server_name: str, tool_name: str, arguments: Dict) -> Dict:
                """Call a tool on an MCP server."""
                if server_name not in self.servers:
                    raise HTTPException(status_code=404, detail=f"MCP server '{server_name}' not found")
                server = self.servers[server_name]
                if not server.enabled:
                    raise HTTPException(status_code=503, detail=f"MCP server '{server_name}' is disabled")
                try:
                    client = await self.get_client(server)
                    resp = await client.post(f"/tools/{tool_name}", json=arguments)
                    if resp.status_code == 200:
                        return resp.json()
                    else:
                        return {"error": resp.json().get("error", "Unknown error"), "status_code": resp.status_code}
                except Exception as e:
                    return {"error": str(e)}

            async def health_check(self) -> Dict[str, str]:
                """Check health of all MCP servers."""
                health = {}
                for name, server in self.servers.items():
                    try:
                        client = await self.get_client(server)
                        resp = await client.get("/health", timeout=5.0)
                        health[name] = "healthy" if resp.status_code == 200 else "degraded"
                    except:
                        health[name] = "unreachable"
                return health

            async def close(self):
                """Close all clients."""
                for client in self.client_cache.values():
                    await client.aclose()
                self.client_cache.clear()

        mcp_broker = MCPBroker()

        # Initialize tools handler after MCP broker is defined
        tools_handler = ToolsHandler(mcp_broker)

        # ============================================================================
        # RAG ENGINE WITH HYBRID SEARCH
        # ============================================================================

        @dataclass
        class DocumentChunk:
            text: str
            metadata: Dict[str, Any]
            embedding: Optional[List[float]] = None
            chunk_id: str = ""

        @dataclass
        class RetrievalResult:
            chunks: List[DocumentChunk]
            scores: List[float]
            sources: List[str]
            query: str
            retrieval_method: str

        class RAGEngine:
            """RAG engine with hybrid vector + BM25 search and token-scoped collections."""

            def __init__(self):
                self.enabled = RAG_ENABLED
                self.qdrant_url = QDRANT_URL
                self.embedding_model_name = EMBEDDING_MODEL
                self.embedding_model = None
                self.qdrant_client = None
                self.bm25_index: Dict[str, Any] = {}  # token -> {collection -> BM25 index}
                self.document_store: Dict[str, List[DocumentChunk]] = {}  # token -> {collection -> chunks}
                self._lock = asyncio.Lock()
                self._initialize()

            def _initialize(self):
                """Initialize embedding model and Qdrant client."""
                if not self.enabled:
                    return

                try:
                    from sentence_transformers import SentenceTransformer
                    from qdrant_client import QdrantClient
                    from qdrant_client.models import Distance, VectorParams, PointStruct

                    logger.info("Initializing RAG engine")

                    self.embedding_model = SentenceTransformer(self.embedding_model_name)
                    logger.info("Embedding model loaded", extra={"model": self.embedding_model_name})

                    self.qdrant_client = QdrantClient(url=self.qdrant_url)
                    self.PointStruct = PointStruct
                    logger.info("Connected to Qdrant", extra={"url": self.qdrant_url})

                    logger.info("RAG engine initialized successfully")

                except ImportError as e:
                    logger.warning("RAG dependencies not available", extra={"error": str(e)})
                    self.enabled = False
                except Exception as e:
                    logger.error("RAG engine initialization failed", exc_info=True)
                    self.enabled = False

            def _get_collection_name(self, token: str, collection: str = "default") -> str:
                """Get scoped collection name for token."""
                if TOKEN_SCOPED_COLLECTIONS:
                    # Hash token for privacy, use as prefix
                    token_hash = hashlib.sha256(token.encode()).hexdigest()[:16]
                    return f"{token_hash}_{collection}"
                return collection

            def _get_token_from_request(self, request: Request) -> str:
                """Extract API token from request for scoping."""
                if AUTH_MODE == "api-key":
                    auth_header = request.headers.get("Authorization", "")
                    return auth_header.replace("Bearer ", "").strip()
                # For non-api-key auth, use client IP as scope
                return f"ip_{request.client.host}"

            async def embed_text(self, text: str) -> List[float]:
                """Generate embedding for text."""
                if not self.embedding_model:
                    return []
                import numpy as np
                embedding = self.embedding_model.encode(text, convert_to_numpy=True)
                return embedding.tolist()

            def chunk_document(self, text: str, metadata: Dict[str, Any] = None) -> List[DocumentChunk]:
                """Split document into overlapping chunks."""
                chunks = []
                text_len = len(text)

                for i in range(0, text_len, CHUNK_SIZE - CHUNK_OVERLAP):
                    chunk_text = text[i:i + CHUNK_SIZE]
                    chunk_id = hashlib.md5(f"{metadata.get('doc_id', 'unknown')}_{i}".encode()).hexdigest()
                    chunks.append(DocumentChunk(
                        text=chunk_text,
                        metadata={**(metadata or {}), "chunk_index": len(chunks)},
                        chunk_id=chunk_id
                    ))

                    if i + CHUNK_SIZE >= text_len:
                        break

                return chunks

            async def index_bm25(self, collection_name: str, chunks: List[DocumentChunk]):
                """Build BM25 index for a collection."""
                from rank_bm25 import BM25Okapi

                # Simple tokenization by splitting on whitespace
                tokenized_chunks = [chunk.text.lower().split() for chunk in chunks]

                bm25 = BM25Okapi(tokenized_chunks)

                async with self._lock:
                    if collection_name not in self.bm25_index:
                        self.bm25_index[collection_name] = {}
                    self.bm25_index[collection_name] = {
                        "bm25": bm25,
                        "chunks": chunks,
                        "tokenized": tokenized_chunks
                    }

            async def add_document(
                self,
                text: str,
                doc_id: str,
                collection: str = "default",
                metadata: Dict[str, Any] = None,
                token: str = None
            ) -> Dict[str, Any]:
                """Add a document to the RAG store."""
                if not self.enabled:
                    return {"error": "RAG not enabled"}

                metadata = metadata or {}
                metadata["doc_id"] = doc_id
                metadata["collection"] = collection

                # Chunk document
                chunks = self.chunk_document(text, metadata)

                # Generate embeddings
                for chunk in chunks:
                    if not chunk.embedding:
                        chunk.embedding = await self.embed_text(chunk.text)

                # Get scoped collection name
                scoped_collection = self._get_collection_name(token or "default", collection)

                # Store in Qdrant
                try:
                    from qdrant_client.models import Distance, VectorParams, PointStruct

                    # Check if collection exists
                    collections = self.qdrant_client.get_collections().collections
                    collection_names = [c.name for c in collections]

                    if scoped_collection not in collection_names:
                        self.qdrant_client.create_collection(
                            collection_name=scoped_collection,
                            vectors_config=VectorParams(size=384, distance=Distance.COSINE)  # MiniLM-L6 uses 384 dims
                        )
                        logger.info("Created Qdrant collection", extra={"collection": scoped_collection})

                    # Upsert points
                    points = [
                        self.PointStruct(
                            id=hash(chunk.chunk_id) % (2**64),
                            vector=chunk.embedding,
                            payload={
                                "text": chunk.text,
                                "chunk_id": chunk.chunk_id,
                                "doc_id": doc_id,
                                "collection": collection,
                                **{k: v for k, v in chunk.metadata.items() if k not in ["doc_id", "collection"]}
                            }
                        )
                        for chunk in chunks
                    ]

                    self.qdrant_client.upsert(
                        collection_name=scoped_collection,
                        points=points
                    )

                except Exception as e:
                    logger.error("Qdrant upsert failed", exc_info=True)

                # Update BM25 index
                await self.index_bm25(scoped_collection, chunks)

                # Store in memory
                async with self._lock:
                    if scoped_collection not in self.document_store:
                        self.document_store[scoped_collection] = []
                    self.document_store[scoped_collection].extend(chunks)

                return {
                    "success": True,
                    "doc_id": doc_id,
                    "collection": collection,
                    "chunks_added": len(chunks),
                    "scoped_collection": scoped_collection
                }

            async def hybrid_search(
                self,
                query: str,
                collection: str = "default",
                top_k: int = 5,
                token: str = None
            ) -> RetrievalResult:
                """Hybrid search combining vector and BM25 scores."""
                if not self.enabled:
                    return RetrievalResult([], [], [], query, "none")

                scoped_collection = self._get_collection_name(token or "default", collection)

                # Generate query embedding
                query_embedding = await self.embed_text(query)

                # Vector search via Qdrant
                vector_results = []
                try:
                    from qdrant_client.models import Filter, PointIdsList, QueryRequest

                    # Try query_points API (newer Qdrant versions)
                    search_result = self.qdrant_client.query_points(
                        collection_name=scoped_collection,
                        query=query_embedding,
                        limit=top_k * 2,  # Get more for reranking
                    ).points

                    for hit in search_result:
                        vector_results.append({
                            "text": hit.payload.get("text", ""),
                            "score": hit.score,
                            "chunk_id": hit.payload.get("chunk_id", ""),
                            "doc_id": hit.payload.get("doc_id", ""),
                            "metadata": hit.payload
                        })

                except Exception as e:
                    logger.error("Vector search failed", exc_info=True)

                # BM25 search
                bm25_results = []
                if HYBRID_SEARCH_ENABLED and scoped_collection in self.bm25_index:
                    index_data = self.bm25_index[scoped_collection]
                    bm25 = index_data["bm25"]
                    chunks = index_data["chunks"]

                    import numpy as np
                    tokenized_query = query.lower().split()
                    scores = bm25.get_scores(tokenized_query)

                    # Get top BM25 results
                    top_indices = np.argsort(scores)[::-1][:top_k * 2]
                    for idx in top_indices:
                        if idx < len(chunks):
                            bm25_results.append({
                                "text": chunks[idx].text,
                                "score": float(scores[idx]),
                                "chunk_id": chunks[idx].chunk_id,
                                "doc_id": chunks[idx].metadata.get("doc_id", ""),
                                "metadata": chunks[idx].metadata
                            })

                # Combine scores (hybrid search)
                combined = {}
                all_results = vector_results + bm25_results

                for result in all_results:
                    chunk_id = result["chunk_id"]
                    if chunk_id not in combined:
                        combined[chunk_id] = {
                            "text": result["text"],
                            "doc_id": result["doc_id"],
                            "metadata": result.get("metadata", {}),
                            "vector_score": 0.0,
                            "bm25_score": 0.0
                        }

                    # Normalize and weight scores
                    if result in vector_results:
                        combined[chunk_id]["vector_score"] = result["score"]
                    if result in bm25_results:
                        # Normalize BM25 score to 0-1 range
                        combined[chunk_id]["bm25_score"] = min(1.0, result["score"] / 10.0)

                # Calculate final scores
                for chunk_id, data in combined.items():
                    final_score = (
                        VECTOR_WEIGHT * data["vector_score"] +
                        BM25_WEIGHT * data["bm25_score"]
                    )
                    data["final_score"] = final_score

                # Sort by final score and take top_k
                sorted_results = sorted(combined.items(), key=lambda x: x[1]["final_score"], reverse=True)[:top_k]

                chunks = [
                    DocumentChunk(
                        text=data["text"],
                        metadata=data["metadata"],
                        chunk_id=chunk_id
                    )
                    for chunk_id, data in sorted_results
                ]

                scores = [data["final_score"] for _, data in sorted_results]
                sources = list(set([data["doc_id"] for _, data in sorted_results]))

                return RetrievalResult(
                    chunks=chunks,
                    scores=scores,
                    sources=sources,
                    query=query,
                    retrieval_method="hybrid" if HYBRID_SEARCH_ENABLED else "vector"
                )

            def should_use_rag(self, query: str, auth_token: str) -> bool:
                """Determine if RAG should be used for this query."""
                if not self.enabled or not AUTO_RAG_ENABLED:
                    return False

                query_lower = query.lower()

                # Check for RAG-triggering keywords
                rag_keywords = os.getenv("RAG_KEYWORDS", "what,how,explain,describe,tell me about,find,search,lookup,who,when,where,why").split(",")
                if any(keyword.strip() in query_lower for keyword in rag_keywords):
                    return True

                # Check if query is asking for specific information
                question_words = ["what", "how", "why", "when", "where", "who", "which", "explain", "describe"]
                if any(word in query_lower.split() for word in question_words):
                    return True

                return False

            async def get_collections(self, token: str = None) -> List[Dict[str, Any]]:
                """List collections available to a token."""
                if not self.enabled:
                    return []

                try:
                    collections = self.qdrant_client.get_collections().collections

                    if TOKEN_SCOPED_COLLECTIONS and token:
                        # Filter to token-scoped collections
                        token_hash = hashlib.sha256(token.encode()).hexdigest()[:16]
                        return [
                            {
                                "name": c.name,
                                "count": getattr(c, "points_count", getattr(c, "vectors_count", 0))
                            }
                            for c in collections
                            if c.name.startswith(token_hash)
                        ]
                    else:
                        return [
                            {
                                "name": c.name,
                                "count": getattr(c, "points_count", getattr(c, "vectors_count", 0))
                            }
                            for c in collections
                        ]
                except Exception as e:
                    logger.error("Failed to list collections", exc_info=True)
                    return []

            async def delete_collection(self, collection: str, token: str = None) -> bool:
                """Delete a collection."""
                if not self.enabled:
                    return False

                scoped_collection = self._get_collection_name(token or "default", collection)

                try:
                    self.qdrant_client.delete_collection(scoped_collection)

                    # Clean up indexes
                    async with self._lock:
                        if scoped_collection in self.bm25_index:
                            del self.bm25_index[scoped_collection]
                        if scoped_collection in self.document_store:
                            del self.document_store[scoped_collection]

                    return True
                except Exception as e:
                    logger.error("Failed to delete collection", exc_info=True)
                    return False

            def format_context(self, result: RetrievalResult) -> str:
                """Format retrieved chunks as context for LLM."""
                if not result.chunks:
                    return ""

                context_parts = []
                for i, chunk in enumerate(result.chunks):
                    source = chunk.metadata.get("doc_id", "unknown")
                    context_parts.append(f"[Source {i+1}: {source}]\n{chunk.text}")

                return "\n\n".join(context_parts)

        class SemanticCache:
            """Semantic caching layer for LLM responses using Qdrant."""

            def __init__(self, qdrant_url: str, embedding_model_name: str):
                self.qdrant_url = qdrant_url
                self.embedding_model_name = embedding_model_name
                self.embedding_model = None
                self.qdrant_client = None
                self.cache_collection = "semantic_cache"
                self.enabled = True
                self._initialize()

            def _initialize(self):
                """Initialize semantic cache."""
                try:
                    from sentence_transformers import SentenceTransformer
                    from qdrant_client import QdrantClient
                    from qdrant_client.models import Distance, VectorParams, PointStruct

                    logger.info("Initializing semantic cache")

                    # Share embedding model with RAG
                    self.embedding_model = SentenceTransformer(self.embedding_model_name)
                    self.qdrant_client = QdrantClient(url=self.qdrant_url)

                    # Create cache collection if it doesn't exist
                    collections = self.qdrant_client.get_collections().collections
                    collection_names = [c.name for c in collections]

                    if self.cache_collection not in collection_names:
                        self.qdrant_client.create_collection(
                            collection_name=self.cache_collection,
                            vectors_config=VectorParams(size=768, distance=Distance.COSINE)
                        )
                        logger.info("Created cache collection", extra={"collection": self.cache_collection})

                    logger.info("Semantic cache initialized successfully")

                except Exception as e:
                    logger.error("Semantic cache initialization failed", exc_info=True)
                    self.enabled = False

            async def get_cache_key(self, messages: List[Dict], model: str, params: Dict) -> str:
                """Generate a cache key from request parameters."""
                # Include messages, model, and key params in the key
                key_data = {
                    "model": model,
                    "temperature": params.get("temperature", 1.0),
                    "max_tokens": params.get("max_tokens", 4096),
                    "messages": messages
                }
                return hashlib.sha256(json.dumps(key_data, sort_keys=True).encode()).hexdigest()

            async def get(self, query_embedding: List[float], model: str, threshold: float = 0.85) -> Dict:
                """Retrieve cached response if semantically similar query exists."""
                if not self.enabled:
                    return None

                try:
                    from qdrant_client.models import Filter, FieldCondition, MatchValue

                    # Use query_points with proper filter syntax
                    search_results = self.qdrant_client.query_points(
                        collection_name=self.cache_collection,
                        query=query_embedding,
                        limit=1,
                        with_payload=True,
                        score_threshold=threshold
                    )

                    # Check if we got results and filter by model in Python
                    if search_results.points:
                        for point in search_results.points:
                            # Check if this point matches our model
                            if point.payload.get("model") == model and point.score >= threshold:
                                cache_hits.labels(cache_type="semantic").inc()

                                return {
                                    "hit": True,
                                    "score": point.score,
                                    "response": json.loads(point.payload.get("response", "{}")),
                                    "cached_at": point.payload.get("cached_at"),
                                    "cache_id": point.id
                                }

                    cache_misses.labels(cache_type="semantic").inc()
                    return {"hit": False}

                except Exception as e:
                    logger.error(
                        "Semantic cache get failed",
                        extra={"error": str(e), "cache_type": "semantic"}
                    )
                    import traceback
                    logger.debug(
                        "Exception traceback",
                        extra={"traceback": traceback.format_exc()}
                    )
                    cache_misses.labels(cache_type="semantic").inc()
                    return {"hit": False}

            async def set(self, query_embedding: List[float], response: Dict, model: str, metadata: Dict = None):
                """Store response in semantic cache."""
                if not self.enabled:
                    return

                try:
                    from qdrant_client.models import PointStruct
                    import time
                    import uuid

                    # Create cache point with UUID (Qdrant requires UUID or int IDs)
                    point_id = str(uuid.uuid4())

                    cache_point = PointStruct(
                        id=point_id,
                        vector=query_embedding,
                        payload={
                            "response": json.dumps(response),
                            "model": model,
                            "cached_at": time.time(),
                            **(metadata or {})
                        }
                    )

                    self.qdrant_client.upsert(
                        collection_name=self.cache_collection,
                        points=[cache_point]
                    )

                    logger.info("Cached response", extra={"cache_id": point_id[:8]})
                    
                except Exception as e:
                    logger.error("Semantic cache set failed", exc_info=True, extra={"error": str(e)})
                    import traceback
                    logger.debug("Exception traceback", extra={"traceback": traceback.format_exc()})

            async def invalidate(self, model: str = None, older_than: int = None):
                """Invalidate cache entries."""
                if not self.enabled:
                    return

                try:
                    from qdrant_client.models import Filter, FieldCondition, MatchValue, Range

                    filters = []
                    if model:
                        filters.append(FieldCondition(key="model", match=MatchValue(value=model)))

                    if older_than:
                        cutoff_time = time.time() - older_than
                        filters.append(
                            FieldCondition(key="cached_at", range=Range(lt=cutoff_time))
                        )

                    if filters:
                        self.qdrant_client.delete(
                            collection_name=self.cache_collection,
                            points_selector=Filter(must=filters)
                        )
                        logger.info("Cache entries invalidated")

                except Exception as e:
                    logger.error("Cache invalidation failed", exc_info=True, extra={"error": str(e)})

            async def get_stats(self) -> Dict:
                """Get cache statistics."""
                if not self.enabled:
                    return {"enabled": False}

                try:
                    collection_info = self.qdrant_client.get_collection(self.cache_collection)
                    return {
                        "enabled": True,
                        "total_entries": collection_info.points_count,
                        "collection": self.cache_collection
                    }
                except Exception as e:
                    return {"enabled": True, "error": str(e)}

        # Initialize semantic cache with updated Qdrant API
        semantic_cache = SemanticCache(QDRANT_URL, EMBEDDING_MODEL) if RAG_ENABLED else None

        rag_engine = RAGEngine()

        # ============================================================================
        # MODEL MANAGEMENT ENDPOINTS (Admin API)
        # ============================================================================

        @app.post("/admin/models/load")
        async def load_model(request: Request):
            """Load a model in the backend (LM Studio specific)."""
            await verify_auth(request)

            try:
                body = await request.json()
                model_path = body.get("model_path")
                if not model_path:
                    raise HTTPException(status_code=400, detail="Missing 'model_path'")

                # LM Studio specific endpoint to load model
                if BACKEND_TYPE == "lm-studio":
                    try:
                        load_resp = await backend_client.request("POST", "/v1/internal/models/load", json={
                            "model_path": model_path,
                            "no_hup": body.get("no_hup", False),
                            "identifier": body.get("identifier"),
                            "config": body.get("config", {})
                        })

                        # Refresh model cache after loading
                        await model_cache.refresh_multi(backend_client, backend.fallback)

                        return JSONResponse({
                            "success": True,
                            "model_path": model_path,
                            "message": "Model loaded successfully"
                        })
                    except HTTPException as e:
                        return JSONResponse({"error": str(e.detail)}, status_code=e.status_code)
                else:
                    return JSONResponse({
                        "error": "Model loading not supported for this backend type"
                    }, status_code=501)

            except HTTPException:
                raise
            except Exception as e:
                return JSONResponse({"error": str(e)}, status_code=500)

        @app.post("/admin/models/unload")
        async def unload_model(request: Request):
            """Unload a model from the backend (LM Studio specific)."""
            await verify_auth(request)

            try:
                body = await request.json()
                identifier = body.get("identifier") or body.get("model")
                if not identifier:
                    raise HTTPException(status_code=400, detail="Missing 'identifier' or 'model'")

                # LM Studio specific endpoint to unload model
                if BACKEND_TYPE == "lm-studio":
                    try:
                        unload_resp = await backend_client.request("POST", "/v1/internal/models/unload", json={
                            "identifier": identifier
                        })

                        # Refresh model cache after unloading
                        await model_cache.refresh_multi(backend_client, backend.fallback)

                        return JSONResponse({
                            "success": True,
                            "identifier": identifier,
                            "message": "Model unloaded successfully"
                        })
                    except HTTPException as e:
                        return JSONResponse({"error": str(e.detail)}, status_code=e.status_code)
                else:
                    return JSONResponse({
                        "error": "Model unloading not supported for this backend type"
                    }, status_code=501)

            except HTTPException:
                raise
            except Exception as e:
                return JSONResponse({"error": str(e)}, status_code=500)

        @app.get("/admin/models/loaded")
        async def list_loaded_models(request: Request):
            """List currently loaded models in the backend."""
            await verify_auth(request)

            try:
                # Try LM Studio's internal endpoint first
                if BACKEND_TYPE == "lm-studio":
                    try:
                        loaded_resp = await backend_client.request("GET", "/v1/internal/models/loaded")
                        loaded_data = loaded_resp.json()
                        return JSONResponse({
                            "loaded_models": loaded_data.get("loaded_models", []),
                            "backend_type": BACKEND_TYPE
                        })
                    except HTTPException:
                        # Fallback to returning all models as potentially loaded
                        pass

                # Fallback: return cached models
                models = await model_cache.get()
                return JSONResponse({
                    "loaded_models": models,
                    "backend_type": BACKEND_TYPE,
                    "note": "Exact loaded status not available, returning cached models"
                })

            except HTTPException:
                raise
            except Exception as e:
                return JSONResponse({"error": str(e)}, status_code=500)

        # ============================================================================
        # RAG ENDPOINTS
        # ============================================================================

        @app.post("/rag/documents")
        async def add_document(request: Request):
            """Add a document to the RAG store."""
            await verify_auth(request)

            if not RAG_ENABLED:
                raise HTTPException(status_code=503, detail="RAG not enabled")

            try:
                body = await request.json()
                text = body.get("text")
                doc_id = body.get("doc_id")
                collection = body.get("collection", "default")
                metadata = body.get("metadata", {})

                if not text or not doc_id:
                    raise HTTPException(status_code=400, detail="Missing 'text' or 'doc_id'")

                token = rag_engine._get_token_from_request(request)

                result = await rag_engine.add_document(
                    text=text,
                    doc_id=doc_id,
                    collection=collection,
                    metadata=metadata,
                    token=token
                )

                return JSONResponse(result)

            except HTTPException:
                raise
            except Exception as e:
                return JSONResponse({"error": str(e)}, status_code=500)

        @app.post("/rag/search")
        async def rag_search(request: Request):
            """Search the RAG store."""
            await verify_auth(request)

            if not RAG_ENABLED:
                raise HTTPException(status_code=503, detail="RAG not enabled")

            try:
                body = await request.json()
                query = body.get("query")
                collection = body.get("collection", "default")
                top_k = body.get("top_k", RAG_TOP_K)

                if not query:
                    raise HTTPException(status_code=400, detail="Missing 'query'")

                token = rag_engine._get_token_from_request(request)

                result = await rag_engine.hybrid_search(
                    query=query,
                    collection=collection,
                    top_k=top_k,
                    token=token
                )

                return JSONResponse({
                    "query": query,
                    "retrieval_method": result.retrieval_method,
                    "sources": result.sources,
                    "results": [
                        {
                            "text": chunk.text,
                            "score": score,
                            "doc_id": chunk.metadata.get("doc_id", ""),
                            "metadata": chunk.metadata
                        }
                        for chunk, score in zip(result.chunks, result.scores)
                    ],
                    "context": rag_engine.format_context(result)
                })

            except HTTPException:
                raise
            except Exception as e:
                return JSONResponse({"error": str(e)}, status_code=500)

        @app.get("/rag/collections")
        async def list_collections(request: Request):
            """List RAG collections for this token."""
            await verify_auth(request)

            if not RAG_ENABLED:
                raise HTTPException(status_code=503, detail="RAG not enabled")

            token = rag_engine._get_token_from_request(request)
            collections = await rag_engine.get_collections(token)

            return JSONResponse({
                "collections": collections,
                "count": len(collections),
                "token_scoped": TOKEN_SCOPED_COLLECTIONS
            })

        @app.delete("/rag/collections/{collection}")
        async def delete_collection_endpoint(collection: str, request: Request):
            """Delete a RAG collection."""
            await verify_auth(request)

            if not RAG_ENABLED:
                raise HTTPException(status_code=503, detail="RAG not enabled")

            token = rag_engine._get_token_from_request(request)
            success = await rag_engine.delete_collection(collection, token)

            if success:
                return JSONResponse({"success": True, "collection": collection})
            else:
                return JSONResponse({"error": "Failed to delete collection"}, status_code=500)

        # ============================================================================
        # MCP BROKERAGE
        # ============================================================================
        async def list_mcp_tools(server: str = None):
            """List available tools from MCP servers."""
            await verify_auth(Request)
            tools = await mcp_broker.list_tools(server)
            return JSONResponse({"tools": tools, "count": len(tools)})

        @app.post("/mcp/call")
        async def call_mcp_tool(request: Request):
            """Call a tool on an MCP server."""
            await verify_auth(request)
            body = await request.json()
            server_name = body.get("server")
            tool_name = body.get("tool")
            arguments = body.get("arguments", {})
            if not server_name or not tool_name:
                raise HTTPException(status_code=400, detail="Missing 'server' or 'tool'")
            result = await mcp_broker.call_tool(server_name, tool_name, arguments)
            return JSONResponse(result)

        @app.get("/mcp/health")
        async def mcp_health():
            """Check health of MCP servers."""
            health = await mcp_broker.health_check()
            return JSONResponse({
                "servers": health,
                "total": len(mcp_broker.servers),
                "healthy": sum(1 for h in health.values() if h == "healthy")
            })

        # ============================================================================
        # ANTHROPIC MESSAGES API (Claude Code Compatibility)
        # ============================================================================

        @app.post("/v1/messages")
        async def anthropic_messages(request: Request):
            """
            Anthropic Messages API endpoint for Claude Code compatibility.

            This endpoint accepts Anthropic's Messages API format and translates it
            to OpenAI format for the backend, then translates responses back.

            Claude Code can use this endpoint to access the gateway with full
            Anthropic API compatibility while the gateway routes to LM Studio or ZAI.
            """
            start_time = time.time()

            try:
                # Validate Anthropic headers
                anthropic_version = request.headers.get("anthropic-version", "2023-06-01")

                # Authentication (use same auth as gateway)
                auth_result = await verify_auth(request)
                if not auth_result.get("allowed"):
                    request_counter.labels(
                        model="claude-code",
                        status="unauthorized",
                        backend="none",
                        auth_mode=AUTH_MODE
                    ).inc()
                    raise HTTPException(
                        status_code=401,
                        detail={
                            "type": "authentication_error",
                            "message": "Invalid authentication"
                        }
                    )

                # Rate limiting
                client_ip = request.client.host
                allowed, limit_msg = await rate_limiter.check(client_ip)
                if not allowed:
                    request_counter.labels(
                        model="claude-code",
                        status="rate_limited",
                        backend="none",
                        auth_mode=AUTH_MODE
                    ).inc()
                    raise HTTPException(
                        status_code=429,
                        detail={
                            "type": "rate_limit_error",
                            "message": limit_msg
                        }
                    )

                # Parse Anthropic request
                body = await request.json()

                # Validate required fields
                if "model" not in body:
                    raise HTTPException(
                        status_code=400,
                        detail={
                            "type": "invalid_request_error",
                            "message": "Missing required field: model"
                        }
                    )

                if "max_tokens" not in body:
                    raise HTTPException(
                        status_code=400,
                        detail={
                            "type": "invalid_request_error",
                            "message": "Missing required field: max_tokens"
                        }
                    )

                if "messages" not in body or not body["messages"]:
                    raise HTTPException(
                        status_code=400,
                        detail={
                            "type": "invalid_request_error",
                            "message": "Missing required field: messages"
                        }
                    )

                # Map Claude model names to available models
                claude_model = body.get("model", "")
                model_mapping = {
                    "claude-sonnet-4-20250514": "magnum-opus-35b-a3b-i1",
                    "claude-opus-4-20250514": "magnum-opus-35b-a3b-i1",
                    "claude-sonnet-4": "glm-5",
                    "claude-3-5-sonnet-20250514": "qwen3.5-35b-a3b@q4_k_m",
                }

                # Get the actual model to use
                selected_model = model_mapping.get(claude_model, claude_model)

                # Translate Anthropic format to OpenAI format
                messages = body.get("messages", [])
                system_prompt = body.get("system", None)
                tools = body.get("tools", [])
                tool_choice = body.get("tool_choice", "auto")

                # Convert Anthropic tools format to OpenAI format
                openai_tools = []
                if tools:
                    for tool in tools:
                        openai_tool = {
                            "type": "function",
                            "function": {
                                "name": tool.get("name", ""),
                                "description": tool.get("description", ""),
                                "parameters": tool.get("input_schema", {})
                            }
                        }
                        openai_tools.append(openai_tool)

                # Convert tool_choice from Anthropic to OpenAI format
                # Anthropic: {"type": "auto"} or {"type": "any"} or {"type": "tool", "name": "tool_name"}
                # OpenAI: "auto" or "any" or {"type": "function", "function": {"name": "tool_name"}}
                openai_tool_choice = tool_choice
                if isinstance(tool_choice, dict):
                    choice_type = tool_choice.get("type", "auto")
                    if choice_type == "auto":
                        openai_tool_choice = "auto"
                    elif choice_type == "any":
                        openai_tool_choice = "required"
                    elif choice_type == "tool" and "name" in tool_choice:
                        openai_tool_choice = {
                            "type": "function",
                            "function": {"name": tool_choice["name"]}
                        }

                # Convert messages - handle tool_result content blocks
                openai_messages = []
                if system_prompt:
                    openai_messages.append({
                        "role": "system",
                        "content": system_prompt
                    })

                for msg in messages:
                    role = msg.get("role")
                    content = msg.get("content")

                    # Handle tool_result blocks (Anthropic) → tool messages (OpenAI)
                    if isinstance(content, list):
                        tool_results = []
                        text_content = []

                        for block in content:
                            if block.get("type") == "tool_result":
                                tool_results.append({
                                    "tool_call_id": block.get("tool_use_id", ""),
                                    "role": "tool",
                                    "content": json.dumps(block.get("content", {}))
                                })
                            elif block.get("type") == "text":
                                text_content.append(block.get("text", ""))

                        # Add text content if any
                        if text_content:
                            openai_messages.append({
                                "role": role,
                                "content": "\n".join(text_content)
                            })

                        # Add tool results
                        for tr in tool_results:
                            openai_messages.append(tr)

                    elif isinstance(content, str):
                        # Regular text message
                        openai_messages.append({
                            "role": role,
                            "content": content
                        })
                    else:
                        # Fallback for other content types
                        openai_messages.append({
                            "role": role,
                            "content": str(content)
                        })

                openai_body = {
                    "model": selected_model,
                    "messages": openai_messages,
                    "max_tokens": body.get("max_tokens", 4096),
                    "temperature": body.get("temperature", 1.0),
                    "stream": body.get("stream", False)
                }

                # Add tools if present
                if openai_tools:
                    openai_body["tools"] = openai_tools
                    openai_body["tool_choice"] = openai_tool_choice

                # Model routing
                if ROUTING_ENABLED:
                    route_decision = router.select_model(openai_messages, selected_model)
                    selected_model = route_decision.model
                    target_backend = route_decision.backend
                else:
                    target_backend = "lm-studio" if selected_model in ["magnum-opus-35b-a3b-i1", "qwen3.5-35b-a3b@q4_k_m"] else "zai"

                # Update request with selected model
                openai_body["model"] = selected_model

                # Determine backend
                if target_backend == "zai" and backend.fallback:
                    effective_backend = backend.fallback
                elif target_backend == "lm-studio":
                    effective_backend = backend.primary
                else:
                    effective_backend = backend.primary if not backend.fallback_used else backend.fallback

                # Make request to backend
                stream = openai_body.get("stream", False)

                if stream:
                    # Streaming response with proper Anthropic SSE format conversion
                    import uuid
                    import json

                    # Generate message ID upfront
                    message_id = f"msg_{uuid.uuid4().hex[:24]}"

                    # Estimate input tokens from messages (rough approximation)
                    input_text = " ".join([m.get("content", "") for m in openai_messages])
                    estimated_input_tokens = max(1, len(input_text) // 4)

                    async def generate_anthropic_stream():
                        """Convert OpenAI SSE format to Anthropic SSE format."""
                        nonlocal estimated_input_tokens
                        content_buffer = ""
                        output_tokens = 0
                        message_started = False
                        content_block_started = False

                        try:
                            async with effective_backend.client.stream(
                                "POST", "/v1/chat/completions",
                                json=openai_body,
                                headers={"Content-Type": "application/json"}
                            ) as backend_resp:
                                # Send message_start event first
                                message_start_event = {
                                    "type": "message_start",
                                    "message": {
                                        "id": message_id,
                                        "type": "message",
                                        "role": "assistant",
                                        "content": [],
                                        "model": claude_model,
                                        "stop_reason": None,
                                        "stop_sequence": None,
                                        "usage": {
                                            "input_tokens": estimated_input_tokens,
                                            "output_tokens": 0
                                        }
                                    }
                                }
                                yield f"event: message_start\n"
                                yield f"data: {json.dumps(message_start_event)}\n\n"

                                # Send content_block_start event
                                content_block_start_event = {
                                    "type": "content_block_start",
                                    "index": 0,
                                    "content_block": {
                                        "type": "text",
                                        "text": ""
                                    }
                                }
                                yield f"event: content_block_start\n"
                                yield f"data: {json.dumps(content_block_start_event)}\n\n"
                                content_block_started = True
                                message_started = True

                                # Process OpenAI SSE stream
                                async for chunk_bytes in backend_resp.aiter_bytes():
                                    chunk_str = chunk_bytes.decode("utf-8", errors="ignore")

                                    # Parse OpenAI SSE format
                                    for line in chunk_str.split("\n"):
                                        if line.startswith("data: "):
                                            data_str = line[6:]  # Remove "data: " prefix

                                            # Check for stream end
                                            if data_str.strip() == "[DONE]":
                                                continue

                                            try:
                                                data = json.loads(data_str)
                                                choices = data.get("choices", [])

                                                if choices:
                                                    delta = choices[0].get("delta", {})
                                                    content = delta.get("content", "")

                                                    if content:
                                                        # Send content_block_delta event
                                                        content_block_delta_event = {
                                                            "type": "content_block_delta",
                                                            "index": 0,
                                                            "delta": {
                                                                "type": "text_delta",
                                                                "text": content
                                                            }
                                                        }
                                                        yield f"event: content_block_delta\n"
                                                        yield f"data: {json.dumps(content_block_delta_event)}\n\n"

                                                        content_buffer += content
                                                        # Approximate token count (rough estimate: ~4 chars per token)
                                                        output_tokens = len(content_buffer) // 4

                                            except json.JSONDecodeError:
                                                # Skip invalid JSON lines
                                                continue

                                # Send content_block_stop event
                                content_block_stop_event = {
                                    "type": "content_block_stop",
                                    "index": 0
                                }
                                yield f"event: content_block_stop\n"
                                yield f"data: {json.dumps(content_block_stop_event)}\n\n"

                                # Send message_delta event with usage
                                message_delta_event = {
                                    "type": "message_delta",
                                    "delta": {
                                        "stop_reason": "end_turn",
                                        "stop_sequence": None
                                    },
                                    "usage": {
                                        "output_tokens": output_tokens
                                    }
                                }
                                yield f"event: message_delta\n"
                                yield f"data: {json.dumps(message_delta_event)}\n\n"

                                # Send message_stop event
                                message_stop_event = {
                                    "type": "message_stop"
                                }
                                yield f"event: message_stop\n"
                                yield f"data: {json.dumps(message_stop_event)}\n\n"

                        except Exception as e:
                            logger.exception("Stream error during response", exc_info=True)
                            # Send error event if stream fails
                            if message_started:
                                error_event = {
                                    "type": "error",
                                    "error": {
                                        "type": "internal_error",
                                        "message": str(e)
                                    }
                                }
                                yield f"event: error\n"
                                yield f"data: {json.dumps(error_event)}\n\n"
                        finally:
                            duration = time.time() - start_time
                            latency_ms = duration * 1000
                            await latency_tracker.record_latency(selected_model, latency_ms)

                    return StreamingResponse(generate_anthropic_stream(), media_type="text/event-stream")

                else:
                    # Non-streaming response
                    backend_resp = await effective_backend.request("POST", "/v1/chat/completions", json=openai_body)
                    openai_response = backend_resp.json()

                    duration = time.time() - start_time

                    # Track latency
                    latency_ms = duration * 1000
                    await latency_tracker.record_latency(selected_model, latency_ms)

                    # Translate OpenAI response to Anthropic format
                    choices = openai_response.get("choices", [])
                    if choices:
                        message = choices[0].get("message", {})
                        content = message.get("content", "")
                        tool_calls = message.get("tool_calls", [])

                        # Generate Anthropic-style message ID
                        import uuid
                        message_id = f"msg_{uuid.uuid4().hex[:24]}"

                        # Detect and handle tool calls
                        if tool_calls:
                            # Convert OpenAI tool_calls to Anthropic content blocks with tool_use
                            anthropic_content = []
                            if content:
                                # Add text content first
                                anthropic_content.append({
                                    "type": "text",
                                    "text": content
                                })

                            # Convert each tool call to tool_use block
                            for tool_call in tool_calls:
                                tool_call_id = tool_call.get("id", f"toolu_{uuid.uuid4().hex[:24]}")
                                function = tool_call.get("function", {})
                                tool_name = function.get("name", "")
                                arguments_str = function.get("arguments", "{}")

                                # Parse arguments if they're a string
                                try:
                                    if isinstance(arguments_str, str):
                                        arguments = json.loads(arguments_str)
                                    else:
                                        arguments = arguments_str
                                except:
                                    arguments = {}

                                anthropic_content.append({
                                    "type": "tool_use",
                                    "id": tool_call_id,
                                    "name": tool_name,
                                    "input": arguments
                                })

                                # Track tool calls in metrics
                                tool_calls.labels(model=selected_model, tool_name=tool_name).inc()

                            anthropic_response = {
                                "id": message_id,
                                "type": "message",
                                "role": "assistant",
                                "content": anthropic_content,
                                "model": claude_model,
                                "stop_reason": "tool_calls",
                                "usage": openai_response.get("usage", {}),
                                "_gateway": openai_response.get("gateway_routing", {
                                    "backend": "zai" if effective_backend == backend.fallback else "lm-studio",
                                    "backend_url": effective_backend.url,
                                    "model": selected_model,
                                    "routing_reason": f"Claude model '{claude_model}' mapped to {selected_model}",
                                    "tool_calls_detected": len(tool_calls),
                                    "tool_names": [tc.get("function", {}).get("name", "") for tc in tool_calls]
                                })
                            }
                        else:
                            # Regular text response
                            anthropic_response = {
                                "id": message_id,
                                "type": "message",
                                "role": "assistant",
                                "content": content,
                                "model": claude_model,
                                "stop_reason": choices[0].get("finish_reason", "end_turn"),
                                "usage": openai_response.get("usage", {}),
                                "_gateway": openai_response.get("gateway_routing", {
                                    "backend": "zai" if effective_backend == backend.fallback else "lm-studio",
                                    "backend_url": effective_backend.url,
                                    "model": selected_model,
                                    "routing_reason": f"Claude model '{claude_model}' mapped to {selected_model}"
                                })
                            }
                    else:
                        # Error response
                        anthropic_response = {
                            "type": "error",
                            "error": {
                                "type": "internal_error",
                                "message": "No response from backend"
                            }
                        }

                    request_counter.labels(
                        model=selected_model,
                        status="success" if backend_resp.status_code == 200 else "error",
                        backend=effective_backend.url,
                        auth_mode=auth_result["tier"]
                    ).inc()

                    return JSONResponse(anthropic_response, status_code=backend_resp.status_code)

            except HTTPException as e:
                raise e
            except Exception as e:
                logger.exception("Anthropic API error", exc_info=True)
                request_counter.labels(
                    model="claude-code",
                    status="error",
                    backend="none",
                    auth_mode=AUTH_MODE
                ).inc()
                return JSONResponse({
                    "type": "error",
                    "error": {
                        "type": "internal_error",
                        "message": str(e)
                    }
                }, status_code=500)

        @app.on_event("shutdown")
        async def shutdown_mcp():
            await mcp_broker.close()
  '';

  # Gateway __init__.py
  gatewayInit = pkgs.writeText "ai-inference-gateway-init.py" ''
    """AI Inference Gateway Package"""
    __version__ = "2.0.0"
  '';

  # Gateway package directory (OLD - monolithic)
  # Kept for rollback if needed
  gatewayPkgOld =
    pkgs.runCommand "ai-inference-gateway-pkg-old"
      {
        preferLocalBuild = true;
      }
      ''
        mkdir -p $out/ai_inference
        # Remove leading 4 spaces from gatewayMain (Nix indentation)
        sed 's/^    //' < ${gatewayMain} > $out/ai_inference/main.py
        cp ${gatewayInit} $out/ai_inference/__init__.py
      '';

  # Modular gateway package (NEW - with middleware pipeline architecture)
  # Production-ready with rate limiting, circuit breaker, security, observability
  # Now using OpenAI SDK for better backend communication
  modularGatewayPkg =
    let
      gatewaySrc = ./ai_inference_gateway;
    in
    pkgs.runCommand "ai-inference-gateway-modular-pkg"
      {
        preferLocalBuild = true;
        passAsFile = [ "buildScript" ];
        buildScript = ''
          mkdir -p $out/ai_inference_gateway
          # Copy the entire modular gateway package
          cp -r ${gatewaySrc}/. $out/ai_inference_gateway/
          # Fix permissions
          chmod -R u+w $out/ai_inference_gateway
          # Remove compiled Python files
          find $out -name "*.pyc" -delete
          find $out -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
        '';
      }
      ''
        . $buildScriptPath
      '';

  # Use modular gateway by default (set to false to use old monolithic version)
  gatewayPkg = modularGatewayPkg;

in
{
  config = mkIf (cfg.enable && cfg.gateway.enable) {
    systemd.services.ai-inference-gateway = {
      description = "AI Inference API Gateway v2";
      after = [
        "network.target"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        BACKEND_URL = cfg.backend.url;
        BACKEND_TYPE = cfg.backend.type;
        BACKEND_FALLBACK_URLS = lib.strings.concatMapStringsSep "," (url: url) (
          lib.optional (cfg.backend.zai.enable) cfg.backend.zai.baseUrl
        );
        GATEWAY_HOST = cfg.gateway.host;
        PORT = toString cfg.gateway.port;
        AUTH_MODE = cfg.auth.mode;
        LM_STUDIO_API_KEY =
          if cfg.backend.lmStudio.apiKeyFile != null then
            "" # Will be loaded from file by gateway
          else
            cfg.backend.lmStudio.apiKey;
        LM_STUDIO_API_KEY_FILE = lib.optionalString (
          cfg.backend.lmStudio.apiKeyFile != null
        ) cfg.backend.lmStudio.apiKeyFile;
        # ZAI backend configuration
        ZAI_API_KEY =
          if cfg.backend.zai.apiKeyFile != null then
            "" # Will be loaded from file by gateway
          else
            cfg.backend.zai.apiKey;
        ZAI_API_KEY_FILE = lib.optionalString (
          cfg.backend.zai.apiKeyFile != null
        ) cfg.backend.zai.apiKeyFile;
        ZAI_BASE_URL = cfg.backend.zai.baseUrl;
        ZAI_MODELS = lib.generators.toJSON { } cfg.backend.zai.models;
        PYTHONUNBUFFERED = "1";
        ROUTING_ENABLED = lib.boolToString cfg.routing.enable;
        DEFAULT_MODEL = cfg.routing.defaultModel;
        RATE_LIMIT_ENABLED = lib.boolToString cfg.rateLimit.enable;
        RATE_LIMIT_RPM = toString cfg.rateLimit.requestsPerMinute;
        MAX_REQUEST_SIZE = toString cfg.security.maxRequestSize;
        SECURITY_PROXY_ENABLED = lib.boolToString cfg.security.enableProxy;
        MCP_ENABLED = lib.boolToString cfg.mcp.enable;
        MCP_SERVERS = lib.generators.toJSON { } cfg.mcp.servers;
        # RAG configuration
        RAG_ENABLED = lib.boolToString cfg.rag.enable;
        QDRANT_URL = cfg.rag.qdrantUrl;
        EMBEDDING_MODEL = cfg.rag.embeddingModel;
        CHUNK_SIZE = toString cfg.rag.chunkSize;
        CHUNK_OVERLAP = toString cfg.rag.chunkOverlap;
        RAG_TOP_K = toString cfg.rag.topK;
        HYBRID_SEARCH_ENABLED = lib.boolToString cfg.rag.hybridSearch.enable;
        VECTOR_WEIGHT = builtins.toString cfg.rag.hybridSearch.vectorWeight;
        BM25_WEIGHT = builtins.toString cfg.rag.hybridSearch.bm25Weight;
        AUTO_RAG_ENABLED = lib.boolToString cfg.rag.autoRag.enable;
        TOKEN_SCOPED_COLLECTIONS = lib.boolToString cfg.rag.tokenScopedCollections;
        # Reranker configuration
        RERANKER_ENABLED = lib.boolToString cfg.rag.reranker.enable;
        RERANKER_MODEL = cfg.rag.reranker.model;
        # Cache directories for sentence-transformers
        TRANSFORMERS_CACHE = "/var/cache/ai-inference";
        HF_HOME = "/var/cache/ai-inference";
      };

      serviceConfig = {
        ExecStart = "${gatewayPython}/bin/uvicorn ai_inference_gateway.main:app --host ${cfg.gateway.host} --port ${toString cfg.gateway.port} --workers ${toString cfg.gateway.workers} --log-level info --app-dir ${gatewayPkg}";
        ExecReload = "/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = "10s";
        User = "ai-inference";
        Group = "ai-inference";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          "/tmp"
          "/var/cache/ai-inference"
        ]
        ++ lib.optional (cfg.backend.lmStudio.apiKeyFile != null) (dirOf cfg.backend.lmStudio.apiKeyFile)
        ++ lib.optional (cfg.backend.zai.apiKeyFile != null) (dirOf cfg.backend.zai.apiKeyFile)
        ++ lib.optional (cfg.mcp.enable) (dirOf "/run/agenix/zai-api-key");
        MemoryMax = "2G";
        CPUWeight = 100;
        IOWeight = 100;
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "ai-gateway";
      };
    };

    users.users.ai-inference = {
      isSystemUser = true;
      group = "ai-inference";
      description = "AI Inference Gateway";
    };
    users.groups.ai-inference = { };

    # Create cache directory
    systemd.tmpfiles.rules = [
      "d /var/cache/ai-inference 0755 ai-inference ai-inference - -"
    ];
  };
}
