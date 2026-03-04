# modules/services/ai-inference/ai_inference_gateway/config.py
import os
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class RateLimitingConfig:
    """Rate limiting configuration"""
    enabled: bool = False
    backend: str = "memory"  # "redis" or "memory"
    tokens_per_minute: int = 10000
    tokens_per_hour: int = 50000
    tokens_per_day: int = 500000
    rpm: int = 60  # Legacy request-based rate limit


@dataclass
class SecurityConfig:
    """Security filter configuration"""
    enabled: bool = True
    pii_redaction: bool = True
    max_request_size: int = 10485760  # 10MB


@dataclass
class CacheConfig:
    """Cache configuration"""
    enabled: bool = False
    backend: str = "memory"  # "redis" or "memory"
    default_ttl: int = 3600  # 1 hour


@dataclass
class CircuitBreakerConfig:
    """Circuit breaker configuration"""
    enabled: bool = True
    failure_threshold: int = 5
    success_threshold: int = 2
    timeout_seconds: int = 60
    health_check_interval: int = 10


@dataclass
class RequestQueueConfig:
    """Request queue configuration"""
    enabled: bool = False
    max_concurrent: int = 10


@dataclass
class LoadBalancerConfig:
    """Load balancer configuration"""
    enabled: bool = False
    # Will be populated from backends list


@dataclass
class ObservabilityConfig:
    """Observability configuration"""
    enabled: bool = True
    structured_logging: bool = True
    request_id_header: str = "X-Request-ID"


@dataclass
class MiddlewareConfig:
    """All middleware configuration"""
    rate_limiting: RateLimitingConfig = field(default_factory=RateLimitingConfig)
    security: SecurityConfig = field(default_factory=SecurityConfig)
    cache: CacheConfig = field(default_factory=CacheConfig)
    circuit_breaker: CircuitBreakerConfig = field(default_factory=CircuitBreakerConfig)
    request_queue: RequestQueueConfig = field(default_factory=RequestQueueConfig)
    load_balancer: LoadBalancerConfig = field(default_factory=LoadBalancerConfig)
    observability: ObservabilityConfig = field(default_factory=ObservabilityConfig)


@dataclass
class GatewayConfig:
    """Main gateway configuration"""
    gateway_host: str = "127.0.0.1"
    gateway_port: int = 8080
    backend_url: str = "http://127.0.0.1:1234"
    backend_type: str = "lm-studio"
    middleware: MiddlewareConfig = field(default_factory=MiddlewareConfig)

    @classmethod
    def load_from_env(cls) -> "GatewayConfig":
        """Load configuration from environment variables"""
        middleware = MiddlewareConfig()

        # Rate limiting
        middleware.rate_limiting.enabled = os.getenv("RATE_LIMIT_ENABLED", "false").lower() == "true"
        middleware.rate_limiting.backend = os.getenv("RATE_LIMIT_BACKEND", "memory")
        middleware.rate_limiting.tokens_per_minute = int(os.getenv("RATE_LIMIT_TPM", "10000"))
        middleware.rate_limiting.tokens_per_hour = int(os.getenv("RATE_LIMIT_TPH", "50000"))
        middleware.rate_limiting.tokens_per_day = int(os.getenv("RATE_LIMIT_TPD", "500000"))
        middleware.rate_limiting.rpm = int(os.getenv("RATE_LIMIT_RPM", "60"))

        # Security
        middleware.security.enabled = os.getenv("SECURITY_ENABLED", "true").lower() == "true"
        middleware.security.pii_redaction = os.getenv("PII_REDACTION", "true").lower() == "true"
        middleware.security.max_request_size = int(os.getenv("MAX_REQUEST_SIZE", "10485760"))

        # Cache
        middleware.cache.enabled = os.getenv("CACHE_ENABLED", "false").lower() == "true"
        middleware.cache.backend = os.getenv("CACHE_BACKEND", "memory")
        middleware.cache.default_ttl = int(os.getenv("CACHE_TTL", "3600"))

        # Circuit breaker
        middleware.circuit_breaker.enabled = os.getenv("CIRCUIT_BREAKER_ENABLED", "true").lower() == "true"
        middleware.circuit_breaker.failure_threshold = int(os.getenv("CIRCUIT_FAILURE_THRESHOLD", "5"))
        middleware.circuit_breaker.timeout_seconds = int(os.getenv("CIRCUIT_TIMEOUT", "60"))

        # Request queue
        middleware.request_queue.enabled = os.getenv("REQUEST_QUEUE_ENABLED", "false").lower() == "true"
        middleware.request_queue.max_concurrent = int(os.getenv("REQUEST_QUEUE_MAX_CONCURRENT", "10"))

        # Observability
        middleware.observability.enabled = os.getenv("OBSERVABILITY_ENABLED", "true").lower() == "true"
        middleware.observability.structured_logging = os.getenv("STRUCTURED_LOGGING", "true").lower() == "true"

        return cls(
            gateway_host=os.getenv("GATEWAY_HOST", "127.0.0.1"),
            gateway_port=int(os.getenv("GATEWAY_PORT", "8080")),
            backend_url=os.getenv("BACKEND_URL", "http://127.0.0.1:1234"),
            backend_type=os.getenv("BACKEND_TYPE", "lm-studio"),
            middleware=middleware
        )
