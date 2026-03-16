# modules/services/ai-inference/ai_inference_gateway/config.py
"""
Configuration module for AI Inference Gateway using Pydantic for validation.

This module provides production-grade configuration with:
- Automatic environment variable loading
- Runtime validation
- Type coercion
- Secret field protection
- Schema generation
"""

from __future__ import annotations

from typing import Optional, List, Dict
from pydantic import BaseModel, Field, field_validator, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class RateLimitingConfig(BaseModel):
    """Rate limiting configuration with validation"""

    enabled: bool = Field(default=False, description="Enable rate limiting")
    backend: str = Field(
        default="memory", pattern="^(memory|redis)$", description="Rate limit backend"
    )
    tokens_per_minute: int = Field(
        default=10000, ge=0, description="Tokens per minute limit"
    )
    tokens_per_hour: int = Field(
        default=50000, ge=0, description="Tokens per hour limit"
    )
    tokens_per_day: int = Field(
        default=500000, ge=0, description="Tokens per day limit"
    )
    rpm: int = Field(default=60, ge=1, le=10000, description="Requests per minute")

    @field_validator("backend")
    @classmethod
    def validate_backend(cls, v: str) -> str:
        """Validate rate limit backend"""
        if v not in ["memory", "redis"]:
            raise ValueError('backend must be "memory" or "redis"')
        return v


class SecurityConfig(BaseModel):
    """Security filter configuration with validation"""

    enabled: bool = Field(default=True, description="Enable security filtering")
    pii_redaction: bool = Field(default=True, description="Enable PII redaction")
    max_request_size: int = Field(
        default=10485760,  # 10MB
        ge=1,
        le=104857600,  # Max 100MB
        description="Maximum request size in bytes",
    )

    @field_validator("max_request_size")
    @classmethod
    def validate_size(cls, v: int) -> int:
        """Ensure reasonable size limits"""
        if v < 1024:  # 1KB minimum
            raise ValueError("max_request_size must be at least 1KB")
        return v


class CacheConfig(BaseModel):
    """Cache configuration with validation"""

    enabled: bool = Field(default=False, description="Enable caching")
    backend: str = Field(
        default="memory", pattern="^(memory|redis)$", description="Cache backend"
    )
    default_ttl: int = Field(
        default=3600,  # 1 hour
        ge=1,
        le=86400,  # Max 24 hours
        description="Default cache TTL in seconds",
    )


class CircuitBreakerConfig(BaseModel):
    """Circuit breaker configuration with validation"""

    enabled: bool = Field(default=True, description="Enable circuit breaker")
    failure_threshold: int = Field(
        default=5, ge=1, le=100, description="Number of failures before opening circuit"
    )
    success_threshold: int = Field(
        default=2, ge=1, le=10, description="Number of successes before closing circuit"
    )
    timeout_seconds: int = Field(
        default=60,
        ge=10,
        le=600,
        description="Seconds to wait before trying half-open state",
    )
    health_check_interval: int = Field(
        default=10, ge=5, le=60, description="Seconds between health checks"
    )


class RequestQueueConfig(BaseModel):
    """Request queue configuration with validation"""

    enabled: bool = Field(default=False, description="Enable request queuing")
    max_concurrent: int = Field(
        default=10, ge=1, le=1000, description="Maximum concurrent requests"
    )


class LoadBalancerConfig(BaseModel):
    """Load balancer configuration"""

    enabled: bool = Field(default=False, description="Enable load balancing")
    # Backend weights are configured dynamically


class ConcurrencyLimiterConfig(BaseModel):
    """Concurrency limiter configuration"""

    enabled: bool = Field(default=False, description="Enable concurrency limiting")
    max_concurrency: int = Field(
        default=1, ge=1, le=100, description="Maximum concurrent requests per model"
    )


class KnowledgeFabricConfig(BaseModel):
    """Knowledge Fabric middleware configuration"""

    enabled: bool = Field(
        default=False, description="Enable Knowledge Fabric middleware"
    )
    rrf_k: int = Field(default=60, ge=1, le=100, description="RRF constant for fusion")
    rag_enabled: bool = Field(default=False, description="Enable RAG source")
    code_search_enabled: bool = Field(
        default=True, description="Enable code search source"
    )
    searxng_enabled: bool = Field(default=False, description="Enable SearXNG source")
    web_search_enabled: bool = Field(
        default=False, description="Enable MCP web search source"
    )
    code_search_paths: List[str] = Field(
        default_factory=lambda: ["/etc/nixos"], description="Paths to search for code"
    )
    rag_top_k: int = Field(default=5, ge=1, le=20, description="RAG top-K results")
    searxng_url: str = Field(default="http://127.0.0.1:7777", description="SearXNG URL")
    mcp_url: str = Field(
        default="http://127.0.0.1:8080/mcp/call", description="MCP broker URL"
    )
    web_max_results: int = Field(
        default=5, ge=1, le=20, description="Web search max results"
    )
    searxng_max_results: int = Field(
        default=5, ge=1, le=20, description="SearXNG max results"
    )
    code_max_results: int = Field(
        default=5, ge=1, le=20, description="Code search max results"
    )


class MCPServerConfig(BaseModel):
    """Configuration for an MCP server."""

    name: str = Field(..., description="Server name")
    type: str = Field(
        default="local",
        pattern="^(local|remote)$",
        description="Server type (local or remote)",
    )
    command: Optional[List[str]] = Field(
        default=None, description="Command for local servers"
    )
    url: Optional[str] = Field(default=None, description="URL for remote servers")
    headers: Dict[str, str] = Field(
        default_factory=dict, description="HTTP headers for remote servers"
    )
    environment: Dict[str, str] = Field(
        default_factory=dict, description="Environment variables for local servers"
    )


class MCPConfig(BaseModel):
    """MCP broker configuration."""

    enabled: bool = Field(default=False, description="Enable MCP broker")
    servers: List[MCPServerConfig] = Field(
        default_factory=list, description="Configured MCP servers"
    )


class SystemPromptsConfig(BaseModel):
    """System prompts configuration for different request types."""

    enabled: bool = Field(default=False, description="Enable custom system prompts")
    default: str = Field(
        default="", description="Default system prompt for all requests"
    )
    coding: str = Field(
        default="You are an expert coding assistant. Write clean, efficient, and well-documented code.",
        description="System prompt for coding-related requests",
    )
    reasoning: str = Field(
        default="You are an expert reasoning assistant. Think step-by-step and provide clear explanations.",
        description="System prompt for reasoning-related requests",
    )
    analysis: str = Field(
        default="You are an expert analysis assistant. Provide thorough and structured analysis.",
        description="System prompt for analysis-related requests",
    )
    agentic: str = Field(
        default="You are an autonomous agent capable of multi-step planning and execution.",
        description="System prompt for agentic/workflow requests",
    )
    fast: str = Field(
        default="You are a fast and efficient assistant. Provide concise, direct answers.",
        description="System prompt for fast response requests",
    )
    custom: Dict[str, str] = Field(
        default_factory=dict, description="Custom system prompts by name"
    )

    def get_prompt(self, category: str) -> Optional[str]:
        """
        Get system prompt for a specific category.

        Args:
            category: One of 'default', 'coding', 'reasoning', 'analysis', 'agentic', 'fast', or custom name

        Returns:
            System prompt string or None if not found
        """
        if not self.enabled:
            return None

        # Check built-in categories
        if hasattr(self, category):
            value = getattr(self, category)
            if value:
                return value

        # Check custom prompts
        if category in self.custom and self.custom[category]:
            return self.custom[category]

        # Fall back to default
        if self.default:
            return self.default

        return None


class SentryConfig(BaseModel):
    """Sentry error tracking configuration."""

    enabled: bool = Field(default=False, description="Enable Sentry error tracking")
    dsn: Optional[str] = Field(
        default=None, repr=False, exclude=True, description="Sentry DSN"
    )
    dsn_file: Optional[str] = Field(
        default=None, description="Path to file containing Sentry DSN"
    )
    environment: str = Field(
        default="production",
        pattern="^(development|staging|production)$",
        description="Sentry environment",
    )
    traces_sample_rate: float = Field(
        default=0.1, ge=0.0, le=1.0, description="Sample rate for performance tracing"
    )

    def get_dsn(self) -> Optional[str]:
        """
        Get Sentry DSN value.

        Priority:
        1. Environment variable SENTRY_DSN
        2. File specified in SENTRY_DSN_FILE
        """
        # Try direct value first
        if self.dsn:
            return self.dsn

        # Try file
        if self.dsn_file:
            try:
                with open(self.dsn_file, "r") as f:
                    return f.read().strip()
            except Exception:
                return None

        return None


class ObservabilityConfig(BaseModel):
    """Observability and logging configuration with validation"""

    enabled: bool = Field(default=True, description="Enable observability")
    structured_logging: bool = Field(
        default=True, description="Use structured JSON logging"
    )
    request_id_header: str = Field(
        default="X-Request-ID",
        min_length=1,
        max_length=100,
        description="Header name for request ID tracking",
    )
    log_level: str = Field(
        default="INFO",
        pattern="^(DEBUG|INFO|WARNING|ERROR|CRITICAL)$",
        description="Logging level",
    )
    log_format: str = Field(
        default="json", pattern="^(json|text)$", description="Log output format"
    )

    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, v: str) -> str:
        """Validate and normalize log level"""
        valid_levels = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}
        v_upper = v.upper()
        if v_upper not in valid_levels:
            raise ValueError(f"log_level must be one of {valid_levels}")
        return v_upper


class MiddlewareConfig(BaseModel):
    """Complete middleware configuration"""

    rate_limiting: RateLimitingConfig = Field(
        default_factory=RateLimitingConfig, description="Rate limiting configuration"
    )
    security: SecurityConfig = Field(
        default_factory=SecurityConfig, description="Security filter configuration"
    )
    cache: CacheConfig = Field(
        default_factory=CacheConfig, description="Cache configuration"
    )
    circuit_breaker: CircuitBreakerConfig = Field(
        default_factory=CircuitBreakerConfig,
        description="Circuit breaker configuration",
    )
    request_queue: RequestQueueConfig = Field(
        default_factory=RequestQueueConfig, description="Request queue configuration"
    )
    load_balancer: LoadBalancerConfig = Field(
        default_factory=LoadBalancerConfig, description="Load balancer configuration"
    )
    concurrency_limiter: ConcurrencyLimiterConfig = Field(
        default_factory=ConcurrencyLimiterConfig,
        description="Concurrency limiter configuration",
    )
    observability: ObservabilityConfig = Field(
        default_factory=ObservabilityConfig, description="Observability configuration"
    )
    mcp: MCPConfig = Field(
        default_factory=MCPConfig, description="MCP broker configuration"
    )
    knowledge_fabric: KnowledgeFabricConfig = Field(
        default_factory=KnowledgeFabricConfig,
        description="Knowledge Fabric middleware configuration",
    )

    # RAG configuration (optional - loaded from environment variables)
    # These use the exact env var names from gateway.nix for compatibility
    RAG_ENABLED: bool = Field(default=False, description="Enable RAG functionality")
    QDRANT_URL: str = Field(default="http://127.0.0.1:6333", description="Qdrant URL")
    EMBEDDING_MODEL: str = Field(default="BAAI/bge-m3", description="Embedding model")
    CHUNK_SIZE: int = Field(default=512, description="Chunk size")
    CHUNK_OVERLAP: int = Field(default=50, description="Chunk overlap")
    RAG_TOP_K: int = Field(default=5, description="Default top-K results")
    HYBRID_SEARCH_ENABLED: bool = Field(
        default=True, description="Enable hybrid search"
    )
    RERANKER_ENABLED: bool = Field(default=True, description="Enable reranking")


class GatewayConfig(BaseSettings):
    """
    Main gateway configuration with automatic environment variable loading.

    Environment variables are automatically loaded:
    - GATEWAY_HOST: Gateway listen host
    - GATEWAY_PORT: Gateway listen port
    - BACKEND_URL: Backend service URL
    - BACKEND_TYPE: Backend type (lm-studio, vllm, llama-cpp, sglang, zai)
    - LM_STUDIO_API_KEY: LM Studio API key (or LM_STUDIO_API_KEY_FILE)
    - ZAI_API_KEY: ZAI API key (or ZAI_API_KEY_FILE)
    - LOG_LEVEL: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    - STRUCTURED_LOGGING: Enable structured logging (true/false)
    """

    model_config = SettingsConfigDict(
        env_prefix="",  # No prefix for env vars
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",  # Ignore extra env vars
    )

    # Core settings with validation
    gateway_host: str = Field(default="127.0.0.1", description="Gateway listen host")
    gateway_port: int = Field(
        default=8080, ge=1, le=65535, description="Gateway listen port"
    )

    # Backend settings with validation
    backend_url: str = Field(
        default="http://127.0.0.1:1234", description="Primary backend service URL"
    )
    backend_fallback_urls: str = Field(
        default="", description="Fallback backend URLs (comma-separated)"
    )
    backend_type: str = Field(
        default="lm-studio",
        pattern="^(lm-studio|vllm|llama-cpp|sglang|zai)$",
        description="Primary backend type",
    )

    def get_backend_fallback_urls(self) -> list[str]:
        """Get backend fallback URLs as a list."""
        if not self.backend_fallback_urls:
            return []
        return [
            url.strip() for url in self.backend_fallback_urls.split(",") if url.strip()
        ]

    # API Keys (marked as secrets - won't appear in logs or repr)
    lm_studio_api_key: Optional[SecretStr] = Field(
        default=None, repr=False, exclude=True, description="LM Studio API key"
    )
    lm_studio_api_key_file: Optional[str] = Field(
        default=None, description="Path to file containing LM Studio API key"
    )

    zai_api_key: Optional[SecretStr] = Field(
        default=None, repr=False, exclude=True, description="ZAI API key"
    )
    zai_api_key_file: Optional[str] = Field(
        default=None, description="Path to file containing ZAI API key"
    )

    # Middleware configuration
    middleware: MiddlewareConfig = Field(
        default_factory=MiddlewareConfig, description="Middleware configuration"
    )

    # Sentry error tracking configuration
    sentry: SentryConfig = Field(
        default_factory=SentryConfig, description="Sentry error tracking configuration"
    )

    # System prompts configuration
    system_prompts: SystemPromptsConfig = Field(
        default_factory=SystemPromptsConfig, description="System prompts configuration"
    )

    @field_validator("backend_url")
    @classmethod
    def validate_backend_url(cls, v: str) -> str:
        """Ensure backend URL is valid"""
        if not v.startswith(("http://", "https://")):
            raise ValueError("backend_url must start with http:// or https://")
        return v

    @field_validator("gateway_host")
    @classmethod
    def validate_host(cls, v: str) -> str:
        """Validate host address"""
        if not v:
            raise ValueError("gateway_host cannot be empty")
        return v

    def get_lm_studio_api_key(self) -> Optional[str]:
        """
        Get LM Studio API key value.

        Priority:
        1. Environment variable LM_STUDIO_API_KEY
        2. File specified in LM_STUDIO_API_KEY_FILE
        """
        # Try secret field first
        if self.lm_studio_api_key:
            return self.lm_studio_api_key.get_secret_value()

        # Try file
        if self.lm_studio_api_key_file:
            try:
                with open(self.lm_studio_api_key_file, "r") as f:
                    return f.read().strip()
            except Exception:
                return None

        return None

    def get_zai_api_key(self) -> Optional[str]:
        """
        Get ZAI API key value.

        Priority:
        1. Environment variable ZAI_API_KEY
        2. File specified in ZAI_API_KEY_FILE
        """
        # Try secret field first
        if self.zai_api_key:
            return self.zai_api_key.get_secret_value()

        # Try file
        if self.zai_api_key_file:
            try:
                with open(self.zai_api_key_file, "r") as f:
                    return f.read().strip()
            except Exception:
                return None

        return None
