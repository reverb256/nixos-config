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

import os
from typing import Optional
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
    observability: ObservabilityConfig = Field(
        default_factory=ObservabilityConfig, description="Observability configuration"
    )


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
        default="",
        description="Fallback backend URLs (comma-separated)"
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
        return [url.strip() for url in self.backend_fallback_urls.split(",") if url.strip()]

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
