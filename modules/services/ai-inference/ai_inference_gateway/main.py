# modules/services/ai-inference/ai_inference_gateway/main.py
import logging
import os
from contextlib import asynccontextmanager
from typing import Optional
from datetime import datetime

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse, Response, StreamingResponse
import httpx

from ai_inference_gateway.config import GatewayConfig
from ai_inference_gateway.pipeline import MiddlewarePipeline
from ai_inference_gateway.utils.redis_client import RedisClient
from ai_inference_gateway.openai_client import create_openai_client, OpenAIBackendError
from ai_inference_gateway.router import (
    create_default_router,
    RouteDecision,
    get_qwen_model_config,
    get_optimal_qwen_params,
)
from ai_inference_gateway.mcp_broker import create_mcp_broker_from_config
from ai_inference_gateway.metrics import ModelMetricsTracker
from ai_inference_gateway.response_format import transform_request
from ai_inference_gateway.claude_client import (
    create_claude_client,
    ClaudeClient,
    ClaudeRequest,
)

# Initialize logger early (needed for import error handling)
logger = logging.getLogger(__name__)

# Import semantic cache
try:
    from ai_inference_gateway.semantic_cache import (
        SemanticCache,
        CacheConfig,
    )

    SEMANTIC_CACHE_AVAILABLE = True
except ImportError as e:
    logger.warning(f"Semantic cache not available: {e}")
    SEMANTIC_CACHE_AVAILABLE = False
    SemanticCache = None
    CacheConfig = None

# Import SearXNG integration
try:
    from ai_inference_gateway.searxng_integration import (
        SearxngIntegration,
        get_searxng,
    )

    SEARXNG_AVAILABLE = True
except ImportError as e:
    logger.warning(f"SearXNG integration not available: {e}")
    SEARXNG_AVAILABLE = False
    SearxngIntegration = None

# Import RAG ingestion
try:
    from ai_inference_gateway.rag.ingestion import (
        URLIngestionService,
        IngestionConfig,
        IngestionSource,
        create_ingestion_service,
    )

    RAG_INGESTION_AVAILABLE = True
except ImportError as e:
    logger.warning(f"RAG ingestion not available: {e}")
    RAG_INGESTION_AVAILABLE = False
    URLIngestionService = None
    IngestionConfig = None
    IngestionSource = None

# Import PII redactor
try:
    from ai_inference_gateway.pii_redactor import (
        PIIRedactor,
        RedactionMode,
        get_default_redactor,
    )

    PII_REDACTOR_AVAILABLE = True
except ImportError as e:
    logger.warning(f"PII redactor not available: {e}")
    PII_REDACTOR_AVAILABLE = False
    PIIRedactor = None
    RedactionMode = None

# Import content moderation
try:
    from ai_inference_gateway.moderation import (
        ContentModerator,
        ModerationResult,
        ModerationCategory,
        get_default_moderator,
    )

    MODERATION_AVAILABLE = True
except ImportError as e:
    logger.warning(f"Content moderation not available: {e}")
    MODERATION_AVAILABLE = False
    ContentModerator = None
    ModerationResult = None
    ModerationCategory = None


# GPU scheduler integration (for signaling workload state)
from ai_inference_gateway import gpu_scheduler

# RAG imports
try:
    from ai_inference_gateway.rag import RAGConfig
    from ai_inference_gateway.rag.embeddings import create_embedding_service
    from ai_inference_gateway.rag.qdrant_client import get_qdrant_manager
    from ai_inference_gateway.rag.search import create_search_service

    RAG_AVAILABLE = True
except ImportError as e:
    logger.warning(f"RAG module not available: {e}")
    RAG_AVAILABLE = False
    RAGConfig = None
    get_qdrant_manager = None

# Import middleware (placed here after conditional imports)
from ai_inference_gateway.middleware.observability import ObservabilityMiddleware  # noqa: E402
from ai_inference_gateway.middleware.security_filter import SecurityFilterMiddleware  # noqa: E402
from ai_inference_gateway.middleware.rate_limiter import RateLimiterMiddleware  # noqa: E402
from ai_inference_gateway.middleware.circuit_breaker import CircuitBreaker  # noqa: E402
from ai_inference_gateway.middleware.concurrency_limiter import ConcurrencyLimiter  # noqa: E402

# Try to import prometheus_client for metrics endpoint
try:
    from prometheus_client import (
        generate_latest,
        CONTENT_TYPE_LATEST,
    )

    PROMETHEUS_AVAILABLE = True
except ImportError:
    PROMETHEUS_AVAILABLE = False
    generate_latest = None
    CONTENT_TYPE_LATEST = None


GATEWAY_VERSION = "2.0.0"


async def check_backend_health(
    url: str,
    timeout: float = 5.0,
    api_key: Optional[str] = None,
    backend_type: str = "unknown",
) -> bool:
    """
    Check if backend is healthy by querying the models endpoint.

    Args:
        url: Backend URL
        timeout: Request timeout in seconds
        api_key: Optional API key for authentication
        backend_type: Type of backend (lm-studio, zai, etc.)

    Returns:
        True if backend is healthy, False otherwise
    """
    try:
        headers = {}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"

        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(f"{url}/v1/models", headers=headers)
            return response.status_code == 200
    except Exception:
        return False


class GatewayState:
    """
    Gateway application state.

    Stores shared state across the application including config,
    Redis client, middleware pipeline, OpenAI client wrapper, and router.
    """

    def __init__(
        self,
        config: GatewayConfig,
        redis_client: Optional[RedisClient] = None,
        pipeline: Optional[MiddlewarePipeline] = None,
        openai_client=None,
        router=None,
    ):
        self.config = config
        self.redis_client = redis_client
        self.pipeline = pipeline
        self.openai_client = openai_client
        self.router = router
        # Backend health cache to avoid checking on every request
        self.backend_health_cache = {
            "healthy": True,
            "last_check": 0,
            "ttl": 30,  # Cache health status for 30 seconds
        }
        # RAG service (initialized if enabled)
        self.rag_search = None
        self.rag_config = None
        # Semantic cache (initialized if enabled)
        self.semantic_cache = None
        # MCP broker (initialized if enabled)
        self.mcp_broker = None
        # RAG ingestion service (initialized if enabled)
        self.rag_ingestion = None
        # SearXNG integration (initialized if enabled)
        self.searxng = None


def build_backend_headers(config: GatewayConfig, request_headers: dict) -> dict:
    """
    Build backend headers including authentication.

    Args:
        config: Gateway configuration
        request_headers: Original request headers

    Returns:
        Headers dictionary for backend request
    """
    # Headers to exclude from forwarding (they'll be regenerated)
    excluded_headers = {
        "host",
        "content-length",
        "content-encoding",
        "transfer-encoding",
    }

    # Start with client headers (excluding problematic headers)
    headers = {
        k: v for k, v in request_headers.items() if k.lower() not in excluded_headers
    }

    # Only add backend authentication if client didn't provide one
    if "authorization" not in {k.lower() for k in headers.keys()}:
        if config.backend_type == "lm-studio":
            api_key = config.get_lm_studio_api_key()
            # DEBUG: Log what we got
            logger.info(
                f"[DEBUG] LM Studio API key: repr={repr(api_key)}, len={len(api_key) if api_key else 0}, auth_mode={os.getenv('AUTH_MODE', 'not-set')}"
            )
            if api_key:
                headers["Authorization"] = f"Bearer {api_key}"
        elif config.backend_type == "zai":
            api_key = config.get_zai_api_key()
            if api_key:
                headers["Authorization"] = f"Bearer {api_key}"

    return headers


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Manage application lifespan.

    Handles startup (initialize connections) and shutdown (cleanup).
    """
    # Get gateway state from app state
    state: GatewayState = app.state.gateway

    logger.info("Starting AI Inference Gateway v%s", GATEWAY_VERSION)

    # Initialize Sentry if enabled
    if state.config.sentry.enabled:
        sentry_dsn = state.config.sentry.get_dsn()
        if sentry_dsn:
            try:
                import sentry_sdk

                sentry_sdk.init(
                    dsn=sentry_dsn,
                    environment=state.config.sentry.environment,
                    traces_sample_rate=state.config.sentry.traces_sample_rate,
                    # FastAPI integration
                    integrations=[
                        sentry_sdk.integrations.fastapi.FastApiIntegration(),
                        sentry_sdk.integrations.httpx.HttpxIntegration(),
                    ],
                    # Filter out common errors
                    ignore_errors=[
                        "KeyboardInterrupt",
                        "httpx.ConnectError",
                    ],
                    # Send PII data (disabled by default, enable if needed)
                    send_default_pii=False,
                )
                logger.info(
                    "Sentry initialized (environment=%s, traces_sample_rate=%.2f)",
                    state.config.sentry.environment,
                    state.config.sentry.traces_sample_rate,
                )
            except ImportError:
                logger.warning(
                    "sentry-sdk not available, skipping Sentry initialization"
                )
            except Exception as e:
                logger.warning(f"Sentry initialization failed: {e}")
        else:
            logger.info("Sentry enabled but no DSN configured")

    # Initialize Redis client
    redis_url = "redis://localhost:6379"
    state.redis_client = RedisClient(redis_url=redis_url)
    redis_connected = await state.redis_client.connect()

    if redis_connected:
        logger.info("Connected to Redis")
    else:
        logger.warning("Redis unavailable, using in-memory fallback")

    # Build middleware pipeline
    state.pipeline = build_middleware_pipeline(state.config, state.redis_client)

    logger.info(
        "Middleware pipeline initialized with %d middleware", state.pipeline.count
    )

    # Initialize router with LM Studio API key for health checks
    lm_studio_key = None
    if state.config.backend_type == "lm-studio":
        lm_studio_key = state.config.get_lm_studio_api_key()
    state.router = create_default_router(lm_studio_api_key=lm_studio_key)
    logger.info("Router initialized with %d models", len(state.router.models))

    # Initialize MCP broker if enabled
    state.mcp_broker = None
    try:
        state.mcp_broker = await create_mcp_broker_from_config(state.config)
        if state.mcp_broker:
            logger.info("MCP broker initialized")
    except Exception as e:
        logger.warning(f"MCP broker initialization failed: {e}")

    # Initialize RAG if enabled
    state.rag_search = None
    state.rag_config = None

    # Check if RAG is enabled via environment variable
    import os

    rag_enabled = os.getenv("RAG_ENABLED", "false").lower() == "true"

    if RAG_AVAILABLE and rag_enabled:
        try:
            logger.info("Initializing RAG service...")

            # Build RAG config from environment variables
            from ai_inference_gateway.rag.config import (
                RAGConfig,
                EmbeddingConfig,
                ChunkingConfig,
                SearchConfig,
                RerankerConfig,
            )
            from ai_inference_gateway.rag.qdrant_client import get_qdrant_manager
            from ai_inference_gateway.rag.embeddings import create_embedding_service
            from ai_inference_gateway.rag.search import create_search_service

            # Get environment variables
            qdrant_url = os.getenv("QDRANT_URL", "http://127.0.0.1:6333")
            embedding_model = os.getenv("EMBEDDING_MODEL", "BAAI/bge-m3")
            chunk_size = int(os.getenv("CHUNK_SIZE", "512"))
            chunk_overlap = int(os.getenv("CHUNK_OVERLAP", "50"))
            top_k = int(os.getenv("RAG_TOP_K", "5"))
            hybrid_search = os.getenv("HYBRID_SEARCH_ENABLED", "true").lower() == "true"
            reranker_enabled = os.getenv("RERANKER_ENABLED", "true").lower() == "true"
            reranker_model = os.getenv("RERANKER_MODEL", "BAAI/bge-reranker-v2-m3")

            state.rag_config = RAGConfig(
                enable=True,
                qdrant_url=qdrant_url,
                embedding=EmbeddingConfig(
                    model=embedding_model,
                    device="cuda",  # Use CUDA by default
                ),
                chunking=ChunkingConfig(
                    chunk_size=chunk_size, chunk_overlap=chunk_overlap
                ),
                search=SearchConfig(default_top_k=top_k, hybrid_search=hybrid_search),
                reranker=RerankerConfig(enable=reranker_enabled, model=reranker_model),
            )

            # Initialize components
            embedder = await create_embedding_service(state.rag_config.embedding)
            qdrant = await get_qdrant_manager(state.rag_config)  # noqa: F823
            state.rag_search = await create_search_service(
                state.rag_config, embedder, qdrant
            )

            logger.info("RAG service initialized successfully")

            # Initialize RAG ingestion service if enabled
            rag_ingestion_enabled = (
                os.getenv("RAG_INGESTION_ENABLED", "false").lower() == "true"
            )

            if RAG_INGESTION_AVAILABLE and rag_ingestion_enabled:
                try:
                    logger.info("Initializing RAG ingestion service...")

                    # Get environment variables
                    allowed_domains_str = os.getenv("RAG_ALLOWED_DOMAINS", "")
                    blocked_domains_str = os.getenv("RAG_BLOCKED_DOMAINS", "")

                    allowed_domains = [
                        d.strip() for d in allowed_domains_str.split(",") if d.strip()
                    ]
                    blocked_domains = [
                        d.strip() for d in blocked_domains_str.split(",") if d.strip()
                    ]

                    # Get RAG components
                    from ai_inference_gateway.rag.chunker import DocumentChunker
                    from ai_inference_gateway.rag.qdrant_client import (
                        get_qdrant_manager,
                    )

                    chunker = DocumentChunker(state.rag_config.chunking)
                    qdrant_manager = get_qdrant_manager(state.rag_config.qdrant_url)

                    # Create ingestion service
                    state.rag_ingestion = create_ingestion_service(
                        rag_config=state.rag_config,
                        embedder=embedder,
                        chunker=chunker,
                        qdrant=qdrant_manager,
                        mcp_broker=state.mcp_broker,
                        allowed_domains=allowed_domains,
                        blocked_domains=blocked_domains,
                    )

                    logger.info(
                        f"RAG ingestion service initialized: "
                        f"allowed_domains={len(allowed_domains)}, "
                        f"blocked_domains={len(blocked_domains)}"
                    )
                except Exception as e:
                    logger.warning(f"RAG ingestion service initialization failed: {e}")
                    state.rag_ingestion = None
            else:
                logger.info(
                    "RAG ingestion service disabled (set RAG_INGESTION_ENABLED=true to enable)"
                )
        except Exception as e:
            logger.error(f"RAG initialization failed: {e}")
            import traceback

            traceback.print_exc()
            state.rag_search = None

    # Initialize semantic cache if enabled
    if SEMANTIC_CACHE_AVAILABLE:
        try:
            # Check if semantic cache is enabled via environment variable
            semantic_cache_enabled = (
                os.getenv("SEMANTIC_CACHE_ENABLED", "false").lower() == "true"
            )

            if semantic_cache_enabled:
                logger.info("Initializing semantic cache...")

                # Get environment variables
                redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
                qdrant_url = os.getenv("QDRANT_URL", "http://127.0.0.1:6333")
                similarity_threshold = float(
                    os.getenv("SEMANTIC_CACHE_SIMILARITY_THRESHOLD", "0.85")
                )
                exact_ttl = int(os.getenv("EXACT_CACHE_TTL_SECONDS", "3600"))
                semantic_ttl = int(os.getenv("SEMANTIC_CACHE_TTL_SECONDS", "86400"))

                cache_config = CacheConfig(
                    redis_url=redis_url,
                    qdrant_url=qdrant_url,
                    similarity_threshold=similarity_threshold,
                    exact_ttl_seconds=exact_ttl,
                    semantic_ttl_seconds=semantic_ttl,
                    enable_exact_cache=True,
                    enable_semantic_cache=True,
                )

                state.semantic_cache = SemanticCache(config=cache_config)
                logger.info("Semantic cache initialized (Redis + Qdrant)")
            else:
                logger.info(
                    "Semantic cache disabled (set SEMANTIC_CACHE_ENABLED=true to enable)"
                )
        except Exception as e:
            logger.warning(f"Semantic cache initialization failed: {e}")
            state.semantic_cache = None
    else:
        logger.info("Semantic cache not available (install redis, qdrant-client)")

    # Initialize SearXNG integration if enabled
    if SEARXNG_AVAILABLE:
        try:
            searxng_enabled = os.getenv("SEARXNG_ENABLED", "true").lower() == "true"
            cache_ttl = int(os.getenv("SEARXNG_CACHE_TTL", "300"))

            if searxng_enabled:
                logger.info("Initializing SearXNG integration...")
                state.searxng = get_searxng(cache_ttl=cache_ttl)
                logger.info("SearXNG integration initialized (auto-improving features enabled)")
            else:
                logger.info("SearXNG integration disabled (set SEARXNG_ENABLED=true to enable)")
        except Exception as e:
            logger.warning(f"SearXNG initialization failed: {e}")
            state.searxng = None

    # Initialize GPU scheduler communication
    try:
        gpu_scheduler.init_scheduler_comms()
        logger.info("GPU scheduler communication initialized")
    except Exception as e:
        logger.warning(f"GPU scheduler initialization failed: {e}")

    # Startup complete
    logger.info("Gateway startup complete")

    yield

    # Shutdown cleanup
    logger.info("Shutting down gateway")

    if state.redis_client:
        await state.redis_client.close()
        logger.info("Redis connection closed")

    if state.semantic_cache:
        await state.semantic_cache.close()
        logger.info("Semantic cache connections closed")

    if state.searxng:
        await state.searxng.close()
        logger.info("SearXNG integration closed")

    if state.rag_ingestion:
        await state.rag_ingestion.close()
        logger.info("RAG ingestion service closed")

    if state.openai_client:
        await state.openai_client.close()
        logger.info("OpenAI clients closed")

    logger.info("Gateway shutdown complete")


def build_middleware_pipeline(
    config: GatewayConfig, redis_client: Optional[RedisClient]
) -> MiddlewarePipeline:
    """
    Build the middleware pipeline from configuration.

    Args:
        config: Gateway configuration
        redis_client: Optional Redis client

    Returns:
        Configured middleware pipeline
    """
    pipeline = MiddlewarePipeline()

    # Add observability middleware (should always be first)
    if config.middleware.observability.enabled:
        pipeline.add(ObservabilityMiddleware(config.middleware.observability))
        logger.info("Added ObservabilityMiddleware")

    # Add security filter
    if config.middleware.security.enabled:
        pipeline.add(SecurityFilterMiddleware(config.middleware.security))
        logger.info("Added SecurityFilterMiddleware")

    # Add rate limiter
    if config.middleware.rate_limiting.enabled:
        rate_limiter = RateLimiterMiddleware(
            config=config.middleware.rate_limiting, redis_client=redis_client
        )
        pipeline.add(rate_limiter)
        logger.info("Added RateLimiterMiddleware")

    # Add concurrency limiter
    if config.middleware.concurrency_limiter.enabled:
        concurrency_limiter = ConcurrencyLimiter(
            max_concurrency=config.middleware.concurrency_limiter.max_concurrency
        )
        pipeline.add(concurrency_limiter)
        logger.info(
            f"Added ConcurrencyLimiter (max_concurrency={config.middleware.concurrency_limiter.max_concurrency})"
        )

    # Add circuit breaker
    if config.middleware.circuit_breaker.enabled:
        circuit_breaker = CircuitBreaker(
            service_id="backend",
            config=config.middleware.circuit_breaker,
            redis_client=redis_client,
        )
        pipeline.add(circuit_breaker)
        logger.info("Added CircuitBreaker")

    return pipeline


def is_reasoning_model(model_id: str) -> bool:
    """Check if a model is a reasoning model that uses reasoning_content field.

    These models have issues with LM Studio's /v1/messages endpoint,
    so we need to use /v1/chat/completions and translate the response.
    """
    reasoning_indicators = [
        "claude-4.6-opus-reasoning-distilled",
        "claude-4.6-opus-distilled",
        "claude-opus-reasoning",
        "claude-opus-distilled",
        "reasoning",
        "deepseek-r1",
    ]
    model_lower = model_id.lower()
    return any(indicator in model_lower for indicator in reasoning_indicators)


def translate_openai_to_anthropic(openai_response: dict, original_model: str) -> dict:
    """
    Translate OpenAI chat/completions response to Anthropic messages format.

    Handles reasoning_content field which is used by reasoning models.
    Maps OpenAI's separate reasoning_content + content to Anthropic's content blocks.
    """
    choice = openai_response.get("choices", [{}])[0]
    message = choice.get("message", {})

    # Extract content from OpenAI response
    reasoning_content = message.get("reasoning_content", "")
    content_text = message.get("content", "")

    # Build Anthropic content blocks
    anthropic_content = []

    # Add thinking block if reasoning_content exists
    if reasoning_content:
        anthropic_content.append({"type": "thinking", "thinking": reasoning_content})

    # Add text block if content exists
    if content_text:
        anthropic_content.append({"type": "text", "text": content_text})

    # If both are empty but we have output_tokens, something went wrong
    # Put a placeholder text
    if not anthropic_content:
        usage = openai_response.get("usage", {})
        if usage.get("completion_tokens", 0) > 0:
            logger.warning(
                f"Model {original_model} generated tokens but no content returned"
            )
            anthropic_content.append({"type": "text", "text": ""})

    return {
        "id": openai_response.get("id", f"msg_{openai_response.get('created', '')}"),
        "type": "message",
        "role": "assistant",
        "content": anthropic_content,
        "model": original_model,  # Use the originally requested Claude model ID
        "stop_reason": choice.get("finish_reason", "stop"),
        "stop_sequence": None,
        "usage": {
            "input_tokens": openai_response.get("usage", {}).get("prompt_tokens", 0),
            "output_tokens": openai_response.get("usage", {}).get(
                "completion_tokens", 0
            ),
            "cache_creation_input_tokens": openai_response.get("usage", {}).get(
                "cache_creation_tokens", 0
            ),
            "cache_read_input_tokens": openai_response.get("usage", {}).get(
                "cache_read_tokens", 0
            ),
        },
    }


def create_app(config: Optional[GatewayConfig] = None) -> FastAPI:
    """
    Create and configure the FastAPI application.

    Args:
        config: Optional gateway configuration. If not provided, loads from environment.

    Returns:
        Configured FastAPI application
    """
    import sys

    print("[DEBUG] create_app: Starting...", file=sys.stderr, flush=True)

    if config is None:
        print(
            "[DEBUG] create_app: Loading config from environment...",
            file=sys.stderr,
            flush=True,
        )
        config = GatewayConfig()
        print(
            f"[DEBUG] create_app: Config loaded, backend_url={config.backend_url}",
            file=sys.stderr,
            flush=True,
        )

    # Initialize gateway state with OpenAI client wrapper
    print(
        "[DEBUG] create_app: Creating OpenAI client wrapper...",
        file=sys.stderr,
        flush=True,
    )
    openai_client = create_openai_client(config)
    print("[DEBUG] create_app: OpenAI client created", file=sys.stderr, flush=True)

    print("[DEBUG] create_app: Creating GatewayState...", file=sys.stderr, flush=True)
    gateway_state = GatewayState(
        config=config,
        openai_client=openai_client,
    )
    print("[DEBUG] create_app: GatewayState created", file=sys.stderr, flush=True)

    # Create FastAPI app
    print("[DEBUG] create_app: Creating FastAPI app...", file=sys.stderr, flush=True)
    app = FastAPI(
        title="AI Inference Gateway",
        description="Advanced gateway for AI inference backends with middleware",
        version=GATEWAY_VERSION,
        lifespan=lifespan,
    )
    print("[DEBUG] create_app: FastAPI app created", file=sys.stderr, flush=True)

    # Store gateway state in app
    print("[DEBUG] create_app: Storing gateway state...", file=sys.stderr, flush=True)
    app.state.gateway = gateway_state
    print("[DEBUG] create_app: Gateway state stored", file=sys.stderr, flush=True)

    print("[DEBUG] create_app: Adding health endpoint...", file=sys.stderr, flush=True)

    # Add health endpoint
    @app.get("/health")
    async def health_check():
        """
        Health check endpoint with actual backend health status.

        Returns comprehensive health information including:
        - Gateway status
        - Backend health (with cached status)
        - Circuit breaker state
        - Qdrant status (if RAG is enabled)
        - Redis status (if semantic cache is enabled)
        """
        import time

        state: GatewayState = app.state.gateway

        # Check if cached health status is still valid
        now = time.time()
        cache_age = now - state.backend_health_cache["last_check"]

        if cache_age > state.backend_health_cache["ttl"]:
            # Cache expired, check actual backend health
            api_key = (
                state.config.get_lm_studio_api_key()
                if state.config.backend_type == "lm-studio"
                else None
            )
            is_healthy = await check_backend_health(
                state.config.backend_url,
                api_key=api_key,
                backend_type=state.config.backend_type,
            )
            state.backend_health_cache = {
                "healthy": is_healthy,
                "last_check": now,
                "ttl": 30,
            }
            logger.info(f"Backend health check: {is_healthy}")
            # Recalculate cache_age after updating
            cache_age = 0

        backend_healthy = state.backend_health_cache["healthy"]

        # Build health response
        health_response = {
            "status": "healthy" if backend_healthy else "degraded",
            "gateway": {
                "version": GATEWAY_VERSION,
                "host": config.gateway_host,
                "port": config.gateway_port,
            },
            "backend": {
                "url": config.backend_url,
                "type": config.backend_type,
                "healthy": backend_healthy,
                "cache_age_seconds": int(cache_age),
            },
        }

        # Add circuit breaker state if enabled
        if config.middleware.circuit_breaker.enabled:
            try:
                # Get circuit breaker from middleware pipeline
                for middleware in state.pipeline.middleware:
                    if hasattr(middleware, "_state"):
                        state_name = (
                            middleware._state.name
                            if hasattr(middleware._state, "name")
                            else str(middleware._state)
                        )
                        health_response["circuit_breaker"] = {
                            "state": state_name,
                            "service_id": getattr(middleware, "service_id", "backend"),
                        }
                        break
            except Exception as e:
                logger.warning(f"Failed to get circuit breaker state: {e}")

        # Add Qdrant status if RAG is enabled
        if SEMANTIC_CACHE_AVAILABLE and state.semantic_cache:
            try:
                # Check Qdrant connection
                qdrant_healthy = await state.semantic_cache._check_qdrant_health()
                health_response["qdrant"] = {
                    "healthy": qdrant_healthy,
                    "url": state.semantic_cache.config.qdrant_url,
                    "collection": state.semantic_cache.config.qdrant_collection,
                }
            except Exception as e:
                logger.warning(f"Failed to check Qdrant health: {e}")
                health_response["qdrant"] = {"healthy": False, "error": str(e)}

        # Add Redis status if semantic cache is enabled
        if SEMANTIC_CACHE_AVAILABLE and state.semantic_cache:
            try:
                # Check Redis connection
                redis_healthy = await state.semantic_cache._check_redis_health()
                health_response["redis"] = {
                    "healthy": redis_healthy,
                    "url": state.semantic_cache.config.redis_url,
                }
            except Exception as e:
                logger.warning(f"Failed to check Redis health: {e}")
                health_response["redis"] = {"healthy": False, "error": str(e)}

        # Add RAG ingestion service status if enabled
        if RAG_INGESTION_AVAILABLE and state.rag_ingestion:
            try:
                health_response["rag_ingestion"] = {"healthy": True, "enabled": True}
            except Exception as e:
                logger.warning(f"Failed to check RAG ingestion health: {e}")
                health_response["rag_ingestion"] = {"healthy": False, "error": str(e)}

        return health_response

    print("[DEBUG] create_app: Health endpoint added", file=sys.stderr, flush=True)

    # Add models endpoint
    @app.get("/v1/models")
    async def list_models(request: Request):
        """List available models from backend with automatic failover."""
        state: GatewayState = app.state.gateway

        try:
            # Use OpenAI SDK to list models with automatic failover
            models = await state.openai_client.primary_client.models.list()

            # Update model availability metrics
            try:
                from ai_inference_gateway.metrics import update_model_availability

                model_ids = [m.id for m in models.data]
                update_model_availability(model_ids)
            except Exception as metrics_error:
                logger.warning(
                    f"Failed to update model availability metrics: {metrics_error}"
                )

            # Convert to dict for JSON response
            return JSONResponse(content=models.model_dump())

        except OpenAIBackendError as e:
            logger.error(f"Error fetching models: {e}")
            raise HTTPException(
                status_code=503, detail=f"Backend unavailable: {str(e)}"
            )
        except Exception as e:
            logger.error(f"Unexpected error fetching models: {e}")
            raise HTTPException(
                status_code=500, detail=f"Error fetching models: {str(e)}"
            )

    print("[DEBUG] create_app: Models endpoint added", file=sys.stderr, flush=True)
    # Add chat completions endpoint
    print(
        "[DEBUG] create_app: Adding chat completions endpoint...",
        file=sys.stderr,
        flush=True,
    )

    @app.post("/v1/chat/completions")
    async def chat_completions(request: Request):
        """
        Chat completions endpoint with middleware processing and intelligent routing.

        Supports both streaming and non-streaming requests.
        Uses router for intelligent model selection based on request analysis.
        """
        import time

        _request_start = time.time()  # noqa: F841

        # Signal GPU scheduler that AI workload is starting
        gpu_scheduler.notify_ai_starting()

        state: GatewayState = app.state.gateway

        # Read request body
        body = await request.json()

        # Transform response_format to LM Studio instructions
        # (OpenAI JSON mode -> LM Studio system prompts)
        if "response_format" in body:
            body = await transform_request(body)
            logger.debug(
                f"Transformed response_format request for model: {body.get('model')}"
            )

        # Check if streaming is requested
        stream = body.get("stream", False)

        # Get messages for routing
        messages = body.get("messages", [])

        # Use router to select best model
        requested_model = body.get("model", None)
        route_decision: RouteDecision = await state.router.route(
            messages=messages,
            requested_model=requested_model,
            urgency="normal",  # Could be made configurable
        )

        # Update model in body based on routing decision
        body["model"] = route_decision.model

        # Detect if this is a vision request
        is_vision_request = False
        try:
            from ai_inference_gateway.vision import detect_vision_content

            is_vision_request = detect_vision_content(messages)
        except ImportError:
            pass  # Vision module not available, continue without detection

        # Apply model-specific defaults for optimal parameters
        try:
            from ai_inference_gateway.model_defaults import apply_model_defaults

            body = apply_model_defaults(
                model_id=route_decision.model,
                request_params=body,
                override=False,  # Only fill missing values, don't override user params
                is_vision_request=is_vision_request,
            )
        except Exception as defaults_error:
            logger.warning(f"Failed to apply model defaults: {defaults_error}")
            # Continue without defaults - not critical

        # Apply Qwen3.5 optimal parameters automatically
        # This enhances Qwen models with proper temperature, top_p, etc.
        if "qwen" in route_decision.model.lower():
            try:
                # Determine if thinking is enabled (check for thinking params in request)
                thinking_enabled = False
                if "thinking" in body:
                    thinking = body.get("thinking", {})
                    if isinstance(thinking, dict):
                        thinking_enabled = (
                            thinking.get("type", "disabled") != "disabled"
                        )
                    elif isinstance(thinking, bool):
                        thinking_enabled = thinking

                # Detect task type from messages for better param selection
                task_type = "general"
                messages_text = " ".join([m.get("content", "") for m in messages])
                if any(
                    keyword in messages_text.lower()
                    for keyword in ["code", "function", "debug", "fix"]
                ):
                    task_type = "coding"
                elif any(
                    keyword in messages_text.lower()
                    for keyword in ["tool", "search", "call", "execute"]
                ):
                    task_type = "agentic"
                elif len(messages_text) > 10000:  # Long conversation, prioritize speed
                    task_type = "fast"

                # Get optimal Qwen parameters
                qwen_params = get_optimal_qwen_params(
                    model_id=route_decision.model,
                    thinking_enabled=thinking_enabled,
                    task_type=task_type,
                )

                # Apply optimal params only if not explicitly set by user
                for param, value in qwen_params.items():
                    if param not in body:
                        body[param] = value
                        logger.debug(
                            f"Applied Qwen optimal param: {param}={value} "
                            f"(model={route_decision.model}, task={task_type})"
                        )
            except Exception as qwen_error:
                logger.warning(f"Failed to apply Qwen optimal params: {qwen_error}")
                # Continue without Qwen params - not critical

        # Track request start for smart load balancing
        import uuid

        request_id = str(uuid.uuid4())
        state.router.track_request_start(
            request_id=request_id,
            model=route_decision.model,
            backend=route_decision.backend,
            stream=stream,
        )

        logger.info(
            f"Routed request to model: {route_decision.model} "
            f"(backend: {route_decision.backend}, "
            f"specialization: {route_decision.specialization})"
        )

        # Create metrics tracker for this request
        metrics_tracker = ModelMetricsTracker(
            model=route_decision.model,
            backend=route_decision.backend,
            requested_model=requested_model,
        )

        # Record routing decision metadata
        metrics_tracker.record_routing_decision(
            confidence=route_decision.confidence,
            reason=route_decision.reason,
            specialization=(
                route_decision.specialization.value
                if route_decision.specialization
                else None
            ),
        )

        # Create context for middleware
        context = {
            "request_id": request_id,
            "start_time": _request_start,  # Track request start for observability
            "request_body": body,
            "request_headers": dict(request.headers),
            "model": route_decision.model,  # Use routed model for concurrency limiter
            "route_decision": route_decision,  # Store routing decision
            "metrics_tracker": metrics_tracker,  # Metrics tracker
        }

        # Process request through middleware pipeline
        should_continue, error = await state.pipeline.process_request(request, context)

        if not should_continue:
            # Middleware blocked the request
            if error:
                raise error
            raise HTTPException(status_code=403, detail="Request blocked by middleware")

        # Forward to backend using OpenAI SDK
        if stream:
            # Handle streaming response
            return StreamingResponse(
                stream_backend_response(
                    state.openai_client,
                    body,
                    state.pipeline,
                    context,
                    state.config,
                    state.router,
                    request_id,
                    metrics_tracker,
                ),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                },
            )
        else:
            # Handle non-streaming response
            try:
                response = await handle_non_streaming_request(
                    state.openai_client,
                    body,
                    state.pipeline,
                    context,
                    state.config,
                    metrics_tracker,
                )
                return response
            finally:
                # Always clean up request tracking
                state.router.track_request_end(request_id)
                # Signal GPU scheduler that AI workload is stopping
                gpu_scheduler.notify_ai_stopping()

    print(
        "[DEBUG] create_app: Adding /v1/messages endpoint...",
        file=sys.stderr,
        flush=True,
    )

    @app.post("/v1/messages")
    async def messages(request: Request):
        """
        Anthropic Messages API endpoint - proxies to LM Studio's native Anthropic API.

        LM Studio provides native Anthropic compatibility at /v1/messages.
        This endpoint adds:
        - Model selection by Claude model ID (haiku, sonnet, opus variants)
        - Thinking effort levels (low/medium/high) that map to budget_tokens
        - ZAI fallback when LM Studio unavailable
        - Extended thinking support through LM Studio's native API

        Model mapping (5 Claude options → 3 underlying local models):
        - claude-haiku-4 → qwen3.5-0.8b-claude-4.6-opus-reasoning-distilled
        - claude-sonnet-4-20250514 → qwen3.5-9b-claude-4.6-opus-reasoning-distilled
        - claude-sonnet-4-20250514-1m → qwen3.5-9b-claude-4.6-opus-reasoning-distilled (extended)
        - claude-opus-4-20250514 → qwen3.5-35b-a3b
        - claude-opus-4-20250514-1m → qwen3.5-35b-a3b (extended)

        Thinking effort levels (map to budget_tokens):
        - low → 5,000 tokens (quick responses)
        - medium → 15,000 tokens (balanced reasoning)
        - high → 50,000 tokens (deep analysis)
        """
        import time
        import uuid

        # Signal GPU scheduler that AI workload is starting
        gpu_scheduler.notify_ai_starting()

        state: GatewayState = app.state.gateway
        _request_start = time.time()

        # Read request body
        body = await request.json()

        # Extract parameters
        model = body.get("model", "")
        max_tokens = body.get("max_tokens", 4096)
        messages = body.get("messages", [])
        system = body.get("system", None)
        stream = body.get("stream", False)

        # Extended thinking / thinking intensity parameters
        # Effort levels (low/medium/high) map to budget_tokens, NOT model selection
        thinking_budget = None
        thinking_intensity = None
        thinking_type = None  # LM Studio expects: "enabled" | "disabled" | "adaptive"

        if "thinking" in body:
            thinking = body["thinking"]
            if isinstance(thinking, dict):
                thinking_intensity = thinking.get("intensity", None)
                thinking_budget = thinking.get("budget_tokens", None)
                thinking_type = thinking.get("type", "enabled")
            elif isinstance(thinking, str):
                # String form like "low", "medium", "high" maps to intensity
                thinking_intensity = thinking
                thinking_type = "enabled"  # Default to enabled for string form
        elif "thinking_intensity" in body:
            thinking_intensity = body["thinking_intensity"]
            thinking_type = "enabled"

        # Map effort levels to budget_tokens if not explicitly set
        if thinking_intensity and not thinking_budget:
            effort_budget_map = {
                "low": 5000,  # Quick responses, minimal reasoning
                "medium": 15000,  # Balanced reasoning
                "high": 50000,  # Deep analysis, extensive reasoning
                "auto": None,  # Let backend decide
            }
            thinking_budget = effort_budget_map.get(thinking_intensity)
            logger.info(
                f"Thinking intensity '{thinking_intensity}' → budget_tokens={thinking_budget}"
            )

        # Build/update thinking dict in body for LM Studio compatibility
        # LM Studio expects: {"type": "enabled"|"disabled"|"adaptive", "budget_tokens": int}
        if thinking_budget is not None or thinking_type:
            if "thinking" not in body or not isinstance(body["thinking"], dict):
                body["thinking"] = {}
            if thinking_type:
                body["thinking"]["type"] = thinking_type
            if thinking_budget is not None:
                body["thinking"]["budget_tokens"] = thinking_budget
            # Store original intensity for logging/metadata
            if thinking_intensity:
                body["thinking"]["intensity"] = thinking_intensity

        # Use router to determine the best model (based on model name only, not intensity)
        route_decision: RouteDecision = await state.router.route(
            messages=messages,
            requested_model=model,
            urgency="normal",
        )

        # Apply prefill optimization limits based on model variant
        # Base models get aggressive limits for faster TTFT, extended models get full context
        trimmed_messages = state.router.apply_prefill_limits(messages, model)
        body["messages"] = trimmed_messages

        if len(trimmed_messages) != len(messages):
            logger.info(
                f"Prefill optimization: {len(messages)} → {len(trimmed_messages)} messages "
                f"for model {model}"
            )

        # Update model in request
        body["model"] = route_decision.model

        # Create request ID for tracking
        request_id = str(uuid.uuid4())
        state.router.track_request_start(
            request_id=request_id,
            model=route_decision.model,
            backend=route_decision.backend,
            stream=stream,
        )

        logger.info(
            f"Anthropic API request: original={model} → {route_decision.model} "
            f"(intensity={thinking_intensity}, budget={thinking_budget}, backend={route_decision.backend})"
        )

        # Create metrics tracker
        metrics_tracker = ModelMetricsTracker(
            model=route_decision.model,
            backend=route_decision.backend,
            requested_model=model,
        )

        # Record routing decision
        metrics_tracker.record_routing_decision(
            confidence=route_decision.confidence,
            reason=route_decision.reason,
            specialization=(
                route_decision.specialization.value
                if route_decision.specialization
                else None
            ),
        )

        # Build headers with authentication
        backend_headers = build_backend_headers(state.config, dict(request.headers))

        # Determine if we should use OpenAI format (for reasoning models)
        # Reasoning models have issues with /v1/messages but work with /v1/chat/completions
        use_openai_format = is_reasoning_model(route_decision.model)

        # Try LM Studio backend
        if route_decision.backend == "lm-studio":
            try:
                if use_openai_format:
                    # Use /v1/chat/completions (OpenAI format) for reasoning models
                    # This properly returns reasoning_content which we'll translate to Anthropic format
                    lm_studio_url = f"{state.config.backend_url}/v1/chat/completions"
                    endpoint_type = "OpenAI-compatible (for reasoning model)"

                    # Translate Anthropic request to OpenAI format
                    openai_request = {
                        "model": route_decision.model,
                        "messages": body.get("messages", []),
                        "max_tokens": body.get("max_tokens", 4096),
                        "temperature": body.get("temperature", 1.0),
                        "stream": stream,
                    }

                    # Add system prompt if present
                    if system:
                        openai_request["messages"] = [
                            {"role": "system", "content": system}
                        ] + openai_request["messages"]

                    # Add tools if present
                    if "tools" in body:
                        openai_request["tools"] = body["tools"]
                    if "tool_choice" in body:
                        openai_request["tool_choice"] = body["tool_choice"]

                    logger.info(
                        f"Using OpenAI format for reasoning model {route_decision.model}"
                    )

                else:
                    # Use /v1/messages (Anthropic format) for non-reasoning models
                    lm_studio_url = f"{state.config.backend_url}/v1/messages"
                    endpoint_type = "Anthropic-compatible"
                    openai_request = None

                async with httpx.AsyncClient(timeout=300.0) as client:
                    response = await client.post(
                        lm_studio_url,
                        json=openai_request if openai_request else body,
                        headers=backend_headers,
                    )
                    response.raise_for_status()

                    if use_openai_format:
                        # Translate OpenAI response to Anthropic format
                        openai_response = response.json()
                        response_data = translate_openai_to_anthropic(
                            openai_response, model
                        )
                    else:
                        response_data = response.json()

                    # Add gateway metadata
                    response_data["gateway_metadata"] = {
                        "processing_time_ms": (time.time() - _request_start) * 1000,
                        "router": {
                            "model": route_decision.model,
                            "backend": "lm-studio",
                            "reason": f"LM Studio {endpoint_type}",
                            "specialization": (
                                route_decision.specialization.value
                                if route_decision.specialization
                                else None
                            ),
                        },
                        "thinking": {
                            "intensity": thinking_intensity,
                            "budget_tokens": thinking_budget,
                        },
                    }

                    # Record success metrics
                    usage = response_data.get("usage", {})
                    metrics_tracker.record_success(
                        input_tokens=usage.get("input_tokens", 0),
                        output_tokens=usage.get("output_tokens", 0),
                        total_tokens=usage.get("total_tokens", 0),
                        latency_ms=response_data.get("gateway_metadata", {}).get(
                            "processing_time_ms", 0
                        ),
                    )

                    state.router.track_request_end(request_id)

                    # Notify circuit breaker of success
                    if state.config.middleware.circuit_breaker.enabled:
                        for middleware in state.pipeline.middleware:
                            if isinstance(middleware, CircuitBreaker):
                                await middleware.on_success()

                    return JSONResponse(
                        content=response_data, status_code=response.status_code
                    )

            except httpx.HTTPStatusError as e:
                logger.error(
                    f"LM Studio API error: {e.response.status_code} - {e.response.text}"
                )

                # Fall through to ZAI if enabled (check via backend_fallback_urls)
                fallback_urls = state.config.get_backend_fallback_urls()
                if fallback_urls:
                    logger.info("Falling back to ZAI for Anthropic request")
                    try:
                        # Try ZAI fallback (uses OpenAI format)
                        for fallback_url in fallback_urls:
                            try:
                                # Convert Anthropic request to OpenAI format for ZAI
                                openai_request = {
                                    "model": route_decision.model,
                                    "messages": messages,
                                    "max_tokens": max_tokens,
                                    "stream": stream,
                                }
                                # Add system prompt if present
                                if system:
                                    openai_request["messages"] = [
                                        {"role": "system", "content": system}
                                    ] + openai_request["messages"]

                                # Build headers for ZAI
                                zai_headers = {
                                    "Content-Type": "application/json",
                                }
                                zai_api_key = state.config.get_zai_api_key()
                                if zai_api_key:
                                    zai_headers["Authorization"] = f"Bearer {zai_api_key}"

                                # ZAI uses /chat/completions (no /v1/ prefix)
                                zai_endpoint = f"{fallback_url}/chat/completions"

                                async with httpx.AsyncClient(timeout=300.0) as client:
                                    if stream:
                                        # Streaming response - would need translation
                                        # For now, return error for streaming fallback
                                        logger.warning(
                                            "ZAI fallback for streaming Anthropic requests not yet implemented"
                                        )
                                        raise HTTPException(
                                            status_code=501,
                                            detail="Streaming fallback not yet supported",
                                        )
                                    else:
                                        response = await client.post(
                                            zai_endpoint,
                                            json=openai_request,
                                            headers=zai_headers,
                                        )
                                        response.raise_for_status()
                                        openai_response = response.json()

                                        # Translate OpenAI response to Anthropic format
                                        response_data = translate_openai_to_anthropic(
                                            openai_response, route_decision.model
                                        )

                                        # Add gateway metadata
                                        response_data["gateway_metadata"] = {
                                            "processing_time_ms": (
                                                time.time() - _request_start
                                            )
                                            * 1000,
                                            "router": {
                                                "model": route_decision.model,
                                                "backend": "zai-fallback",
                                                "reason": "ZAI fallback after LM Studio failure",
                                            },
                                        }

                                        # Record metrics
                                        usage = response_data.get("usage", {})
                                        metrics_tracker.record_success(
                                            input_tokens=usage.get("input_tokens", 0),
                                            output_tokens=usage.get("output_tokens", 0),
                                            total_tokens=usage.get("total_tokens", 0),
                                            latency_ms=response_data["gateway_metadata"].get(
                                                "processing_time_ms", 0
                                            ),
                                        )

                                        state.router.track_request_end(request_id)
                                        gpu_scheduler.notify_ai_stopping()

                                        return JSONResponse(content=response_data)

                            except httpx.HTTPStatusError as zai_error:
                                logger.warning(
                                    f"ZAI fallback also failed: {zai_error.response.status_code}"
                                )
                                continue
                            except Exception as zai_exc:
                                logger.warning(f"ZAI fallback failed: {zai_exc}")
                                continue

                        # All fallbacks failed
                        logger.error("All backends (LM Studio and ZAI) failed")

                    except Exception as fallback_error:
                        logger.error(f"Error during ZAI fallback: {fallback_error}")

                # No fallback available or fallback failed - return original error
                state.router.track_request_end(request_id)
                gpu_scheduler.notify_ai_stopping()
                raise HTTPException(
                    status_code=e.response.status_code,
                    detail=f"LM Studio error: {e.response.text}",
                )
            except Exception as e:
                logger.error(f"Error calling LM Studio API: {e}")
                state.router.track_request_end(request_id)
                gpu_scheduler.notify_ai_stopping()
                raise HTTPException(status_code=503, detail=f"Backend error: {str(e)}")

    # ============================================================================
    # MCP Broker Endpoints
    # ============================================================================

    print("[DEBUG] create_app: Adding MCP endpoints...", file=sys.stderr, flush=True)

    @app.get("/mcp/servers")
    async def list_mcp_servers():
        """List all configured MCP servers."""
        state: GatewayState = app.state.gateway

        if not state.mcp_broker:
            return {"servers": [], "message": "MCP broker not enabled"}

        servers = await state.mcp_broker.list_servers()
        return {"servers": servers}

    @app.get("/mcp/tools")
    async def list_mcp_tools(server: Optional[str] = None):
        """List available MCP tools from all servers or a specific server."""
        state: GatewayState = app.state.gateway

        if not state.mcp_broker:
            raise HTTPException(status_code=501, detail="MCP broker not enabled")

        tools = await state.mcp_broker.get_tools(server)
        return {"tools": tools}

    @app.post("/mcp/cache/invalidate")
    async def invalidate_mcp_cache(request: Request):
        """
        Invalidate cached MCP tool schemas.

        Body: {"server": "optional_server_name"}
        If server is omitted, invalidates all caches.
        """
        state: GatewayState = app.state.gateway

        if not state.mcp_broker:
            raise HTTPException(status_code=501, detail="MCP broker not enabled")

        body = await request.json()
        server_name = body.get("server")

        result = await state.mcp_broker.invalidate_cache(server_name)
        return result

    @app.get("/mcp/cache/metrics")
    async def get_mcp_cache_metrics():
        """Get MCP cache performance metrics."""
        state: GatewayState = app.state.gateway

        if not state.mcp_broker:
            raise HTTPException(status_code=501, detail="MCP broker not enabled")

        metrics = state.mcp_broker.get_cache_metrics()

        if metrics is None:
            return {"error": "Cache is not enabled"}

        return metrics

    @app.post("/mcp/cache/warmup")
    async def warmup_mcp_cache():
        """
        Trigger cache warm-up for all MCP servers.

        Pre-fetches tool schemas from all remote servers.
        """
        state: GatewayState = app.state.gateway

        if not state.mcp_broker:
            raise HTTPException(status_code=501, detail="MCP broker not enabled")

        result = await state.mcp_broker.warm_up_cache()
        return result

    @app.get("/retry/metrics")
    async def get_retry_metrics():
        """
        Get retry handler metrics.

        Returns retry statistics including attempts, successes,
        failures, and breakdown by failure reason.
        """
        state: GatewayState = app.state.gateway

        # Collect metrics from all router clients
        all_metrics = {}

        for model_id, model_info in state.router.models.items():
            client = getattr(model_info, "client", None)
            if client and hasattr(client, "get_retry_metrics"):
                metrics = client.get_retry_metrics()
                if metrics:
                    all_metrics[model_id] = metrics

        if not all_metrics:
            return {
                "message": "No retry metrics available (retry may be disabled)",
                "models": {},
            }

        return {
            "models": all_metrics,
            "summary": {
                "total_models_with_retries": len(all_metrics),
                "total_retry_attempts": sum(
                    m.get("total_retries", 0) for m in all_metrics.values()
                ),
                "total_success_after_retry": sum(
                    m.get("total_success", 0) for m in all_metrics.values()
                ),
                "total_failures_after_retry": sum(
                    m.get("total_failures", 0) for m in all_metrics.values()
                ),
            },
        }

    @app.post("/retry/reset-metrics")
    async def reset_retry_metrics():
        """Reset all retry metrics across all model clients."""
        state: GatewayState = app.state.gateway

        reset_count = 0
        for model_id, model_info in state.router.models.items():
            client = getattr(model_info, "client", None)
            if client and hasattr(client, "reset_retry_metrics"):
                client.reset_retry_metrics()
                reset_count += 1

        return {
            "message": f"Reset metrics for {reset_count} model clients",
            "models_reset": reset_count,
        }

    @app.get("/cache/metrics")
    async def get_cache_metrics():
        """
        Get semantic cache metrics.

        Returns cache performance statistics including
        hit rates for exact and semantic cache layers.
        """
        state: GatewayState = app.state.gateway

        if not hasattr(state, "semantic_cache") or not state.semantic_cache:
            return {
                "error": "Semantic cache not enabled",
                "message": "Enable Redis and Qdrant for semantic caching",
            }

        metrics = state.semantic_cache.get_metrics()

        if metrics is None:
            return {"error": "Cache metrics not available"}

        return metrics

    @app.post("/cache/invalidate")
    async def invalidate_cache(request: Request):
        """
        Invalidate semantic cache entries.

        Body: {"model": "optional_model_name"}
        If model is omitted, invalidates all cache entries.
        """
        state: GatewayState = app.state.gateway

        if not hasattr(state, "semantic_cache") or not state.semantic_cache:
            raise HTTPException(status_code=501, detail="Semantic cache not enabled")

        body = await request.json()
        model = body.get("model")

        count = await state.semantic_cache.invalidate(model)

        return {
            "message": f"Invalidated {count} cache entries",
            "model": model or "all",
        }

    @app.post("/cache/reset-metrics")
    async def reset_cache_metrics():
        """Reset semantic cache metrics."""
        state: GatewayState = app.state.gateway

        if not hasattr(state, "semantic_cache") or not state.semantic_cache:
            raise HTTPException(status_code=501, detail="Semantic cache not enabled")

        state.semantic_cache.reset_metrics()

        return {"message": "Cache metrics reset"}

    print(
        "[DEBUG] create_app: Adding RAG ingestion endpoint...",
        file=sys.stderr,
        flush=True,
    )

    @app.post("/rag/ingest")
    async def ingest_rag_url(request: Request):
        """
        Ingest document from URL into RAG system.

        Body: {
            "url": "https://example.com/document",
            "collection": "default",  // optional
            "source": "mcp_web_reader" | "http_direct"  // optional
        }

        Returns ingestion result with chunks stored.
        """
        state: GatewayState = app.state.gateway

        if not hasattr(state, "rag_ingestion") or not state.rag_ingestion:
            raise HTTPException(
                status_code=501, detail="RAG ingestion service not enabled"
            )

        body = await request.json()
        url = body.get("url")
        collection = body.get("collection", "default")
        source_str = body.get("source", "mcp_web_reader")

        if not url:
            raise HTTPException(status_code=400, detail="Missing required field: url")

        # Parse source preference
        try:
            source = (
                IngestionSource(source_str)
                if RAG_INGESTION_AVAILABLE
                else IngestionSource.HTTP_DIRECT
            )
        except ValueError:
            source = IngestionSource.HTTP_DIRECT

        # Ingest URL
        result = await state.rag_ingestion.ingest_url(url, collection, source)

        return {
            "url": result.url,
            "success": result.success,
            "source": result.source.value,
            "title": result.title,
            "content_length": len(result.content),
            "chunks_count": len(result.chunks),
            "ingested_at": result.ingested_at.isoformat(),
            "error": result.error,
        }

    @app.post("/rag/ingest/batch")
    async def ingest_rag_urls(request: Request):
        """
        Ingest multiple documents from URLs into RAG system.

        Body: {
            "urls": ["https://example.com/doc1", "https://example.com/doc2"],
            "collection": "default",  // optional
            "source": "mcp_web_reader" | "http_direct"  // optional
        }

        Returns batch ingestion results.
        """
        state: GatewayState = app.state.gateway

        if not hasattr(state, "rag_ingestion") or not state.rag_ingestion:
            raise HTTPException(
                status_code=501, detail="RAG ingestion service not enabled"
            )

        body = await request.json()
        urls = body.get("urls", [])
        collection = body.get("collection", "default")
        source_str = body.get("source", "mcp_web_reader")

        if not urls:
            raise HTTPException(status_code=400, detail="Missing required field: urls")

        # Parse source preference
        try:
            source = (
                IngestionSource(source_str)
                if RAG_INGESTION_AVAILABLE
                else IngestionSource.HTTP_DIRECT
            )
        except ValueError:
            source = IngestionSource.HTTP_DIRECT

        # Ingest URLs
        results = await state.rag_ingestion.ingest_urls(urls, collection, source)

        return {
            "total": len(results),
            "successful": sum(1 for r in results if r.success),
            "failed": sum(1 for r in results if not r.success),
            "results": [
                {
                    "url": r.url,
                    "success": r.success,
                    "source": r.source.value,
                    "title": r.title,
                    "chunks_count": len(r.chunks),
                    "error": r.error,
                }
                for r in results
            ],
        }

    @app.post("/pii/redact")
    async def redact_pii(request: Request):
        """
        Redact PII from text.

        Body: {
            "text": "User input with PII",
            "mode": "redact" | "hash" | "mask" | "remove",  // optional
            "enabled_patterns": ["email", "phone", "ssn", ...]  // optional
        }

        Returns text with PII redacted.
        """
        if not PII_REDACTOR_AVAILABLE:
            raise HTTPException(status_code=501, detail="PII redactor not available")

        body = await request.json()
        text = body.get("text", "")
        mode_str = body.get("mode", "redact")
        enabled_patterns = body.get("enabled_patterns")

        # Parse mode
        try:
            mode = RedactionMode(mode_str) if mode_str else None
        except ValueError:
            mode = None

        # Create redactor with custom patterns if specified
        if enabled_patterns:
            redactor = PIIRedactor(enabled_patterns=enabled_patterns)
        else:
            redactor = get_default_redactor()

        # Redact text
        redacted_text = redactor.redact(text, mode=mode)

        return {
            "original": text,
            "redacted": redacted_text,
            "mode": mode_str,
            "patterns_used": [p["name"] for p in redactor.get_patterns()],
        }

    @app.post("/pii/detect")
    async def detect_pii(request: Request):
        """
        Detect PII in text without redacting.

        Body: {
            "text": "User input to analyze",
            "enabled_patterns": ["email", "phone", "ssn", ...]  // optional
        }

        Returns detected PII instances.
        """
        if not PII_REDACTOR_AVAILABLE:
            raise HTTPException(status_code=501, detail="PII redactor not available")

        body = await request.json()
        text = body.get("text", "")
        enabled_patterns = body.get("enabled_patterns")

        # Create redactor with custom patterns if specified
        if enabled_patterns:
            redactor = PIIRedactor(enabled_patterns=enabled_patterns)
        else:
            redactor = get_default_redactor()

        # Detect PII
        detections = redactor.detect(text)

        return {
            "text": text,
            "detections": detections,
            "total_count": sum(len(matches) for matches in detections.values()),
        }

    @app.get("/pii/patterns")
    async def get_pii_patterns():
        """Get available PII patterns."""
        if not PII_REDACTOR_AVAILABLE:
            raise HTTPException(status_code=501, detail="PII redactor not available")

        redactor = get_default_redactor()

        return {
            "patterns": redactor.get_patterns(),
            "total_count": len(redactor.get_patterns()),
        }

    @app.post("/moderation/check")
    async def check_content_moderation(request: Request):
        """
        Check content for policy violations.

        Body: {
            "text": "Content to check",
            "strictness": "low" | "medium" | "high",  // optional
            "threshold": 0.7  // optional, overrides strictness
        }

        Returns moderation results.
        """
        if not MODERATION_AVAILABLE:
            raise HTTPException(
                status_code=501, detail="Content moderation not available"
            )

        body = await request.json()
        text = body.get("text", "")
        strictness = body.get("strictness", "medium")
        threshold = body.get("threshold")

        # Create moderator with specified settings
        moderator = ContentModerator(strictness=strictness, threshold=threshold)

        # Check content
        result = moderator.moderate(text)

        return {
            "flagged": result.flagged,
            "safe": result.safe,
            "categories": [c.value for c in result.categories],
            "scores": result.scores,
            "strictness": strictness,
            "threshold": moderator.threshold,
        }

    @app.post("/moderation/check-messages")
    async def check_messages_moderation(request: Request):
        """
        Check chat messages for policy violations.

        Body: {
            "messages": [
                {"role": "user", "content": "..."},
                {"role": "assistant", "content": "..."}
            ],
            "strictness": "low" | "medium" | "high"  // optional
        }

        Returns filtered messages and moderation result.
        """
        if not MODERATION_AVAILABLE:
            raise HTTPException(
                status_code=501, detail="Content moderation not available"
            )

        body = await request.json()
        messages = body.get("messages", [])
        strictness = body.get("strictness", "medium")

        # Create moderator
        moderator = ContentModerator(strictness=strictness)

        # Check messages
        filtered_messages, result = moderator.moderate_messages(messages)

        return {
            "flagged": result.flagged,
            "safe": result.safe,
            "categories": [c.value for c in result.categories],
            "scores": result.scores,
            "original_count": len(messages),
            "filtered_count": len(filtered_messages),
            "messages": filtered_messages,
            "strictness": strictness,
        }

    @app.get("/moderation/categories")
    async def get_moderation_categories():
        """Get available moderation categories."""
        if not MODERATION_AVAILABLE:
            raise HTTPException(
                status_code=501, detail="Content moderation not available"
            )

        moderator = get_default_moderator()

        return {
            "categories": moderator.get_categories(),
            "total_count": len(moderator.get_categories()),
        }

    @app.post("/mcp/call")
    async def call_mcp_tool(request: Request):
        """Call an MCP tool on a specific server."""
        state: GatewayState = app.state.gateway

        if not state.mcp_broker:
            raise HTTPException(status_code=501, detail="MCP broker not enabled")

        body = await request.json()
        server_name = body.get("server")
        tool_name = body.get("tool")
        arguments = body.get("arguments", {})

        if not server_name or not tool_name:
            raise HTTPException(
                status_code=400, detail="Missing required fields: server, tool"
            )

        result = await state.mcp_broker.call_tool(
            server_name=server_name, tool_name=tool_name, arguments=arguments
        )
        return result

    @app.get("/mcp/health/{server_name}")
    async def mcp_server_health(server_name: str):
        """Check MCP server health."""
        state: GatewayState = app.state.gateway

        if not state.mcp_broker:
            raise HTTPException(status_code=501, detail="MCP broker not enabled")

        is_healthy = await state.mcp_broker.health_check(server_name)
        return {
            "server": server_name,
            "healthy": is_healthy,
            "exists": server_name in state.mcp_broker.servers,
        }

    # ============================================================================
    # SEARXNG SEARCH ENDPOINTS
    # ============================================================================
    if SEARXNG_AVAILABLE:

        @app.post("/search")
        async def searxng_search(request: Request):
            """
            Perform web search using SearXNG with auto-improving features.

            Body: {
                "query": str (required),
                "category": str (optional, default="general"),
                "language": str (optional, default="all"),
                "max_results": int (optional, default=10),
                "time_range": str (optional, values: day, week, month, year),
                "use_cache": bool (optional, default=true)
            }

            Categories: general, images, videos, news, science, it, files, map, music
            """
            state: GatewayState = app.state.gateway

            if not state.searxng:
                raise HTTPException(
                    status_code=501,
                    detail="SearXNG integration not enabled. Set SEARXNG_ENABLED=true."
                )

            body = await request.json()
            query = body.get("query", "").strip()

            if not query:
                raise HTTPException(status_code=400, detail="Query cannot be empty")

            # Extract parameters
            category = body.get("category", "general")
            language = body.get("language", "all")
            max_results = min(body.get("max_results", 10), 50)
            time_range = body.get("time_range")
            use_cache = body.get("use_cache", True)

            # Perform search
            result = await state.searxng.search(
                query=query,
                category=category,
                language=language,
                max_results=max_results,
                time_range=time_range,
                use_cache=use_cache,
                learning_enabled=True,
            )

            return result

        @app.get("/search/stats")
        async def searxng_stats():
            """Get SearXNG learning statistics and search patterns."""
            state: GatewayState = app.state.gateway

            if not state.searxng:
                raise HTTPException(
                    status_code=501,
                    detail="SearXNG integration not enabled"
                )

            stats = await state.searxng.get_learning_stats()
            return stats

        @app.post("/search/cache/clear")
        async def searxng_clear_cache():
            """Clear SearXNG response cache."""
            state: GatewayState = app.state.gateway

            if not state.searxng:
                raise HTTPException(
                    status_code=501,
                    detail="SearXNG integration not enabled"
                )

            state.searxng.clear_cache()
            return {"success": True, "message": "SearXNG cache cleared"}

        @app.get("/search/ping")
        async def searxng_ping():
            """Check if SearXNG service is accessible."""
            import httpx

            try:
                async with httpx.AsyncClient(timeout=5.0) as client:
                    response = await client.get(
                        "http://127.0.0.1:7777/search",
                        params={"q": "test"}
                    )
                    if response.status_code == 200:
                        return {
                            "status": "healthy",
                            "service": "SearXNG",
                            "url": "http://127.0.0.1:7777"
                        }
                    else:
                        return {
                            "status": "unhealthy",
                            "service": "SearXNG",
                            "code": response.status_code
                        }
            except Exception as e:
                return {
                    "status": "error",
                    "service": "SearXNG",
                    "error": str(e)
                }

    # ============================================================================
    # RAG ENDPOINTS
    # ============================================================================
    if RAG_AVAILABLE:

        @app.post("/rag/documents")
        async def ingest_document(request: Request):
            """Ingest document into RAG knowledge base."""
            state: GatewayState = app.state.gateway

            if not state.rag_search:
                raise HTTPException(status_code=501, detail="RAG service not enabled")

            body = await request.json()
            collection = body.get("collection", "default")
            documents = body.get("documents", [])

            if not documents:
                raise HTTPException(status_code=400, detail="No documents provided")

            # Ingest each document
            results = []
            for doc in documents:
                content = doc.get("content", "")
                metadata = doc.get("metadata", {})
                document_id = doc.get("document_id")

                result = await state.rag_search.ingest_document(
                    collection=collection,
                    content=content,
                    metadata=metadata,
                    document_id=document_id,
                )
                results.append(result)

            # Return summary
            total_chunks = sum(
                r.get("chunks_created", 0) for r in results if r.get("success")
            )
            return {
                "success": True,
                "documents_ingested": len(results),
                "chunks_created": total_chunks,
                "collection": collection,
                "results": results,
            }

        @app.get("/rag/search")
        async def search_knowledge_base(request: Request):
            """Search RAG knowledge base."""
            state: GatewayState = app.state.gateway

            if not state.rag_search:
                raise HTTPException(status_code=501, detail="RAG service not enabled")

            query = request.query_params.get("query", "")
            if not query:
                raise HTTPException(
                    status_code=400, detail="Missing required parameter: query"
                )

            collection = request.query_params.get("collection", "default")
            top_k = int(request.query_params.get("top_k", 5))
            rerank = request.query_params.get("rerank", "true").lower() == "true"

            result = await state.rag_search.search(
                query=query, collection=collection, top_k=top_k, rerank=rerank
            )

            return result

        @app.get("/rag/collections")
        async def list_collections(request: Request):
            """List all RAG collections."""
            state: GatewayState = app.state.gateway

            if not state.rag_search:
                raise HTTPException(status_code=501, detail="RAG service not enabled")

            collections = await state.rag_search.get_collections()
            return {"collections": collections}

        @app.delete("/rag/documents")
        async def delete_document(request: Request):
            """Delete document from RAG knowledge base."""
            state: GatewayState = app.state.gateway

            if not state.rag_search:
                raise HTTPException(status_code=501, detail="RAG service not enabled")

            body = await request.json()
            collection = body.get("collection", "default")
            document_id = body.get("document_id")

            if not document_id:
                raise HTTPException(
                    status_code=400, detail="Missing required field: document_id"
                )

            result = await state.rag_search.delete_document(
                collection=collection, document_id=document_id
            )

            return result

    # Ollama-compatible API endpoints for Spacebot integration
    @app.get("/api/tags")
    async def ollama_list_models():
        """
        List available models (Ollama-compatible).

        Compatible with: GET /api/tags
        Ollama equivalent: ollama list
        """
        state: GatewayState = app.state.gateway

        # Get models from backend
        try:
            models = await state.openai_client.primary_client.models.list()
        except Exception as e:
            logger.error(f"Failed to list models: {e}")
            # Return default models list
            return {
                "models": [
                    {
                        "name": "qwen/qwen3.5-9b",
                        "modified_at": "2024-01-01T00:00:00Z",
                        "size": 0,
                        "digest": "gateway-proxy",
                    }
                ]
            }

        # Transform to Ollama format
        ollama_models = []
        for model in models.data:
            # Extract base name without organization prefix
            _model_name = model.id.split("/")[-1] if "/" in model.id else model.id  # noqa: F841

            ollama_models.append(
                {
                    "name": model.id,
                    "modified_at": "2024-01-01T00:00:00Z",
                    "size": 0,  # Not tracked
                    "digest": "gateway-proxy",
                    "details": {
                        "parent_model": "",
                        "format": "gguf",
                        "family": "gateway-proxy",
                        "families": None,
                        "parameter_size": "unknown",
                        "quantization_level": "unknown",
                    },
                }
            )

        return {"models": ollama_models}

    @app.post("/api/generate")
    async def ollama_generate(request: Request):
        """
        Generate text completion (Ollama-compatible).

        Compatible with: POST /api/generate
        Transforms to OpenAI format and forwards to backend.
        """
        state: GatewayState = app.state.gateway

        # Parse Ollama request
        body = await request.json()
        model = body.get("model", "qwen/qwen3.5-9b")
        prompt = body.get("prompt", "")
        stream = body.get("stream", False)

        # Extract options
        options = body.get("options", {})
        max_tokens = options.get("num_predict", options.get("max_tokens", 2048))
        temperature = options.get("temperature", 0.7)

        # Transform to OpenAI format
        openai_request = {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "stream": stream,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }

        if stream:
            # Streaming response
            async def generate_stream():
                async for chunk in stream_backend_response(
                    state.openai_client,
                    openai_request,
                    state.pipeline,
                    {"ollama": True},
                    state.config,
                    state.router,
                    "ollama-gen",
                ):
                    # Transform SSE to Ollama format
                    try:
                        chunk_str = (
                            chunk.decode("utf-8") if isinstance(chunk, bytes) else chunk
                        )
                        if '"content"' in chunk_str:
                            import json

                            # Parse and transform
                            lines = chunk_str.split("\n")
                            for line in lines:
                                if line.startswith("data: ") and line != "data: [DONE]":
                                    try:
                                        data = json.loads(line[6:])
                                        if (
                                            "choices" in data
                                            and len(data["choices"]) > 0
                                        ):
                                            delta = data["choices"][0].get("delta", {})
                                            content = delta.get("content", "")
                                            if content:
                                                ollama_chunk = {
                                                    "model": model,
                                                    "created_at": datetime.now().isoformat(),
                                                    "response": content,
                                                    "done": False,
                                                }
                                                yield f"data: {json.dumps(ollama_chunk)}\n\n"
                                    except Exception:
                                        pass
                    except Exception:
                        # If transformation fails, pass through as-is
                        if isinstance(chunk, bytes):
                            yield chunk
                        else:
                            yield (
                                chunk.encode("utf-8")
                                if isinstance(chunk, str)
                                else chunk
                            )

                # Send final done signal
                done_chunk = {
                    "model": model,
                    "created_at": datetime.now().isoformat(),
                    "response": "",
                    "done": True,
                    "context": [0, 1],  # Placeholder
                }
                yield f"data: {json.dumps(done_chunk)}\n\n"

            return StreamingResponse(
                generate_stream(),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                },
            )
        else:
            # Non-streaming response
            response = await state.openai_client.chat_completion(
                messages=openai_request["messages"],
                model=openai_request["model"],
                max_tokens=openai_request["max_tokens"],
                temperature=openai_request["temperature"],
                stream=False,
            )

            # Transform to Ollama format
            content = response.choices[0].message.content

            return {
                "model": model,
                "created_at": datetime.now().isoformat(),
                "response": content,
                "done": True,
            }

    @app.post("/api/chat")
    async def ollama_chat(request: Request):
        """
        Chat completion endpoint (Ollama-compatible).

        Compatible with: POST /api/chat
        This is the main endpoint used by Spacebot.
        """
        state: GatewayState = app.state.gateway

        # Parse Ollama request
        body = await request.json()
        model = body.get("model", "qwen/qwen3.5-9b")
        messages = body.get("messages", [])
        stream = body.get("stream", False)

        # Extract options
        options = body.get("options", {})
        max_tokens = options.get("num_predict", options.get("max_tokens", 2048))
        temperature = options.get("temperature", 0.7)

        # Transform to OpenAI format (already compatible)
        openai_request = {
            "model": model,
            "messages": messages,
            "stream": stream,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }

        if stream:
            # Streaming response
            async def chat_stream():
                async for chunk in stream_backend_response(
                    state.openai_client,
                    openai_request,
                    state.pipeline,
                    {"ollama": True},
                    state.config,
                    state.router,
                    "ollama-chat",
                ):
                    # Transform SSE to Ollama format
                    try:
                        chunk_str = (
                            chunk.decode("utf-8") if isinstance(chunk, bytes) else chunk
                        )
                        if '"content"' in chunk_str:
                            import json

                            lines = chunk_str.split("\n")
                            for line in lines:
                                if line.startswith("data: ") and line != "data: [DONE]":
                                    try:
                                        data = json.loads(line[6:])
                                        if (
                                            "choices" in data
                                            and len(data["choices"]) > 0
                                        ):
                                            delta = data["choices"][0].get("delta", {})
                                            content = delta.get("content", "")
                                            if content:
                                                role = delta.get("role", "assistant")
                                                ollama_chunk = {
                                                    "model": model,
                                                    "created_at": datetime.now().isoformat(),
                                                    "message": {
                                                        "role": role,
                                                        "content": content,
                                                    },
                                                    "done": False,
                                                }
                                                yield f"data: {json.dumps(ollama_chunk)}\n\n"
                                    except Exception:
                                        pass
                    except Exception:
                        # If transformation fails, pass through as-is
                        if isinstance(chunk, bytes):
                            yield chunk
                        else:
                            yield (
                                chunk.encode("utf-8")
                                if isinstance(chunk, str)
                                else chunk
                            )

                # Send final done signal
                done_chunk = {
                    "model": model,
                    "created_at": datetime.now().isoformat(),
                    "message": {"role": "assistant", "content": ""},
                    "done": True,
                    "context": [0, 1],  # Placeholder
                }
                yield f"data: {json.dumps(done_chunk)}\n\n"

            return StreamingResponse(
                chat_stream(),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                },
            )
        else:
            # Non-streaming response - use existing endpoint logic
            response = await state.openai_client.chat_completion(
                messages=openai_request["messages"],
                model=openai_request["model"],
                max_tokens=openai_request["max_tokens"],
                temperature=openai_request["temperature"],
                stream=False,
            )

            # Transform to Ollama format
            message = response.choices[0].message

            return {
                "model": model,
                "created_at": datetime.now().isoformat(),
                "message": {"role": message.role, "content": message.content},
                "done": True,
            }

    @app.get("/api/version")
    async def ollama_version():
        """
        Get Ollama version information (gateway-compatible).

        Compatible with: GET /api/version
        """
        return {
            "version": "2.0.0-gateway",
            "details": {
                "backend": "gateway-proxy",
                "committed": True,
                "features": ["ollama-api", "openai-api", "rag", "mcp"],
            },
        }

    @app.post("/api/embeddings")
    async def ollama_embeddings(request: Request):
        """
        Generate embeddings (Ollama-compatible).

        Compatible with: POST /api/embeddings
        Uses RAG embedding service if available.
        """
        state: GatewayState = app.state.gateway

        if not state.rag_search or not state.rag_search.embedder:
            raise HTTPException(
                status_code=501, detail="Embeddings not enabled. Set RAG_ENABLED=true"
            )

        body = await request.json()
        _model = body.get("model", "BAAI/bge-m3")  # noqa: F841
        prompt = body.get("prompt", "")

        # Generate embedding
        embedding = await state.rag_search.embedder.embed_single(prompt)

        return {"embedding": embedding}

    print("[DEBUG] create_app: Adding metrics endpoint...", file=sys.stderr, flush=True)
    # Add metrics endpoint for Prometheus
    if PROMETHEUS_AVAILABLE:

        @app.get("/metrics")
        async def metrics():
            """Prometheus metrics endpoint."""
            return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

    else:

        @app.get("/metrics")
        async def metrics():
            """Prometheus metrics endpoint (not available)."""
            raise HTTPException(
                status_code=501,
                detail="Prometheus metrics not available. Install prometheus-client package.",
            )

    print("[DEBUG] create_app: About to return app", file=sys.stderr, flush=True)
    return app


async def stream_backend_response(
    openai_client,
    body: dict,
    pipeline: MiddlewarePipeline,
    context: dict,
    config: GatewayConfig,
    router,
    request_id: str,
    metrics_tracker: ModelMetricsTracker,
):
    """
    Stream backend response using OpenAI SDK with automatic failover.

    Args:
        openai_client: OpenAI client wrapper
        body: Request body
        pipeline: Middleware pipeline
        context: Request context
        config: Gateway configuration
        router: Router instance for tracking requests
        request_id: Request ID for tracking
        metrics_tracker: Metrics tracker for this request

    Yields:
        SSE formatted response chunks
    """
    try:
        # Extract parameters from request body
        messages = body.get("messages", [])
        model = body.get("model", "default")
        extra_params = {
            k: v for k, v in body.items() if k not in ["messages", "model", "stream"]
        }

        # Get backend from route decision if available
        route_decision = context.get("route_decision")
        backend = route_decision.backend if route_decision else None

        # Create streaming chat completion with automatic failover
        stream = await openai_client.chat_completion(
            messages=messages,
            model=model,
            stream=True,
            backend=backend,
            **extra_params,
        )

        # Stream response chunks
        input_tokens = 0
        output_tokens = 0
        first_chunk = True
        async for chunk in stream:
            # Record first token time
            if first_chunk:
                metrics_tracker.record_first_token()
                first_chunk = False

            # Track tokens if usage info available
            if hasattr(chunk, "usage") and chunk.usage:
                if chunk.usage.prompt_tokens:
                    input_tokens = max(input_tokens, chunk.usage.prompt_tokens)
                if chunk.usage.completion_tokens:
                    output_tokens = max(output_tokens, chunk.usage.completion_tokens)

            # Format as SSE
            chunk_str = chunk.model_dump_json()
            yield f"data: {chunk_str}\n\n"

        # Record success metrics (streaming complete)
        total_tokens = input_tokens + output_tokens
        if total_tokens > 0:
            # Calculate latency from the tracker's start time
            import time

            latency_ms = (time.time() - metrics_tracker.start_time) * 1000
            metrics_tracker.record_success(
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                total_tokens=total_tokens,
                latency_ms=latency_ms,
            )

        # Notify circuit breaker of success
        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_success()

    except OpenAIBackendError as e:
        logger.error(f"Backend error in streaming request: {e}")

        # Record error metrics
        metrics_tracker.record_error("backend_error")

        # Notify circuit breaker of failure
        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_failure()

        # Yield error as SSE event (proper JSON with escaped single quotes)
        yield f"data: {json.dumps({'error': str(e).replace("'", '&#39;')})}\n\n"
    except Exception as e:
        logger.error(f"Unexpected error in streaming request: {e}")

        # Record error metrics
        metrics_tracker.record_error("unexpected_error")

        # Notify circuit breaker of failure
        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_failure()

        yield f"data: {json.dumps({'error': f'Unexpected error: {str(e)}'})}\n\n"
    finally:
        # Always clean up request tracking
        router.track_request_end(request_id)
        # Signal GPU scheduler that AI workload is stopping
        gpu_scheduler.notify_ai_stopping()


async def try_backends_with_failover(
    config: GatewayConfig,
    request_headers: dict,
    endpoint: str,
    method: str = "POST",
    content: dict = None,
    timeout: float = 300.0,
) -> tuple[httpx.Response, str]:
    """
    Try primary and fallback backends in order until one succeeds.

    Args:
        config: Gateway configuration
        request_headers: Original request headers
        endpoint: API endpoint (e.g., "/v1/chat/completions")
        method: HTTP method
        content: Request body for POST requests
        timeout: Request timeout in seconds

    Returns:
        Tuple of (response, backend_url_used)

    Raises:
        httpx.HTTPError: If all backends fail
    """
    # Build list of backends to try
    backends_to_try = [("primary", config.backend_url, config.backend_type)]

    # Add fallback backends (assuming they're ZAI for now)
    for i, fallback_url in enumerate(config.get_backend_fallback_urls()):
        backends_to_try.append(("fallback", fallback_url, "zai"))

    last_error = None

    for backend_type_name, backend_url, backend_api_type in backends_to_try:
        try:
            logger.info(f"Attempting {backend_type_name} backend: {backend_url}")

            # Build headers for this backend, preserving User-Agent
            headers = {
                k: v
                for k, v in request_headers.items()
                if k.lower()
                not in {
                    "host",
                    "content-length",
                    "content-encoding",
                    "transfer-encoding",
                }
            }

            # Log User-Agent for debugging (only at DEBUG level)
            if "user-agent" in {k.lower(): k for k in headers.keys()}:
                ua_key = next(k for k in headers.keys() if k.lower() == "user-agent")
                logger.debug(f"Forwarding User-Agent: {headers[ua_key][:100]}")

            # Add authentication for this backend
            if "authorization" not in {k.lower() for k in headers.keys()}:
                if backend_api_type == "lm-studio":
                    api_key = config.get_lm_studio_api_key()
                    if api_key:
                        headers["Authorization"] = f"Bearer {api_key}"
                elif backend_api_type == "zai":
                    api_key = config.get_zai_api_key()
                    if api_key:
                        headers["Authorization"] = f"Bearer {api_key}"
                    else:
                        logger.warning("ZAI API key not found for fallback backend")

            logger.info(
                f"Request headers for {backend_type_name} backend: Authorization={'Bearer ' + (headers.get('Authorization', 'NO-AUTH')[:20] + '...' if 'Authorization' in headers else 'NOT SET')}"
            )

            async with httpx.AsyncClient(timeout=timeout) as client:
                # For ZAI, convert OpenAI-style endpoints to ZAI format
                if backend_api_type == "zai":
                    # ZAI uses /chat/completions instead of /v1/chat/completions
                    zai_endpoint = (
                        endpoint.replace("/v1/", "/")
                        if endpoint.startswith("/v1/")
                        else endpoint
                    )
                    url = f"{backend_url}{zai_endpoint}"
                else:
                    url = f"{backend_url}{endpoint}"

                # Debug logging for ZAI (only at DEBUG level)
                if backend_api_type == "zai" and logger.isEnabledFor(logging.DEBUG):
                    logger.debug(f"ZAI URL: {url}")
                    logger.debug(
                        f"ZAI Headers: Authorization={headers.get('Authorization', 'MISSING')[:30]}..."
                    )
                    logger.debug(f"ZAI Body model: {content.get('model', 'NO_MODEL')}")

                if method.upper() == "POST":
                    response = await client.post(
                        url,
                        json=content,
                        headers=headers,
                    )
                else:  # GET
                    response = await client.get(
                        url,
                        headers=headers,
                    )

                # Log response status
                logger.info(
                    f"{backend_type_name} backend response: HTTP {response.status_code}"
                )

                # Debug logging for ZAI responses (only at DEBUG level)
                if backend_api_type == "zai" and logger.isEnabledFor(logging.DEBUG):
                    logger.debug(f"ZAI Response status: {response.status_code}")
                    if response.status_code != 200:
                        try:
                            logger.debug(f"ZAI Response body: {response.text[:500]}")
                        except Exception:
                            pass

                # If we got here, the request succeeded (connected, even if 4xx/5xx)
                return response, backend_url

        except (httpx.ConnectError, httpx.TimeoutException, httpx.ConnectTimeout) as e:
            logger.warning(
                f"{backend_type_name} backend {backend_url} failed: {str(e)}"
            )
            last_error = e
            continue
        except Exception as e:
            logger.warning(
                f"{backend_type_name} backend {backend_url} failed with unexpected error: {str(e)}"
            )
            last_error = e
            continue

    # All backends failed
    logger.error(f"All backends failed. Last error: {last_error}")
    raise last_error or httpx.ConnectError("All backends unavailable")


async def handle_non_streaming_request(
    openai_client,
    body: dict,
    pipeline: MiddlewarePipeline,
    context: dict,
    config: GatewayConfig,
    metrics_tracker: ModelMetricsTracker,
):
    """
    Handle non-streaming request using OpenAI SDK with automatic failover.

    Args:
        openai_client: OpenAI client wrapper
        body: Request body
        pipeline: Middleware pipeline
        context: Request context
        config: Gateway configuration
        metrics_tracker: Metrics tracker for this request

    Returns:
        JSON response
    """
    import time

    start_time = time.time()

    try:
        # Extract parameters from request body
        messages = body.get("messages", [])
        model = body.get("model", "default")
        extra_params = {
            k: v for k, v in body.items() if k not in ["messages", "model", "stream"]
        }

        # Get backend from route decision if available
        route_decision = context.get("route_decision")
        backend = route_decision.backend if route_decision else None

        # Create chat completion with automatic failover
        response = await openai_client.chat_completion(
            messages=messages,
            model=model,
            stream=False,
            backend=backend,
            **extra_params,
        )

        # Convert OpenAI response object to dict for JSON serialization
        response_data = response.model_dump()

        # Calculate actual processing time
        processing_time_ms = (time.time() - start_time) * 1000

        # Record success metrics
        # Extract token usage from response
        usage = response_data.get("usage", {})
        input_tokens = usage.get("prompt_tokens", 0)
        output_tokens = usage.get("completion_tokens", 0)
        total_tokens = usage.get("total_tokens", input_tokens + output_tokens)

        metrics_tracker.record_success(
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            total_tokens=total_tokens,
            latency_ms=processing_time_ms,
        )

        # Add gateway metadata including routing information
        route_decision = context.get("route_decision")
        if route_decision:
            response_data["gateway_metadata"] = {
                "processing_time_ms": round(processing_time_ms, 2),
                "router": {
                    "model": route_decision.model,
                    "backend": route_decision.backend,
                    "reason": route_decision.reason,
                    "specialization": (
                        route_decision.specialization.value
                        if route_decision.specialization
                        else None
                    ),
                    "estimated_tokens": route_decision.estimated_tokens,
                    "expected_latency_ms": route_decision.expected_latency_ms,
                },
            }
            # Remove route_decision from context to avoid serialization issues
            context.pop("route_decision", None)

        # Process response through middleware pipeline (reverse order)
        response_data = await pipeline.process_response(response_data, context)

        # Notify circuit breaker of success
        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_success()

        return JSONResponse(content=response_data, status_code=200)

    except OpenAIBackendError as e:
        logger.error(f"Backend error: {e}")

        # Record error metrics
        metrics_tracker.record_error("backend_error")

        # Notify circuit breaker of failure
        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_failure()

        # Extract status code from error message if possible
        error_str = str(e)
        status_code = 503
        if "401" in error_str:
            status_code = 401
        elif "429" in error_str:
            status_code = 429

        raise HTTPException(status_code=status_code, detail=str(e))

    except Exception as e:
        logger.error(f"Unexpected error: {e}")

        # Record error metrics
        metrics_tracker.record_error("unexpected_error")

        # Notify circuit breaker of failure
        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_failure()

        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")


async def stream_anthropic_response(
    openai_client,
    body: dict,
    pipeline: MiddlewarePipeline,
    context: dict,
    config: GatewayConfig,
    original_model: str,
    thinking_intensity: Optional[str],
    request_id: str,
    metrics_tracker: ModelMetricsTracker,
):
    """
    Handle streaming Anthropic API response.

    Converts OpenAI streaming chunks to Anthropic format.
    """
    import time
    import json

    start_time = time.time()
    first_chunk_sent = False

    try:
        # Extract parameters
        messages = body.get("messages", [])
        model = body.get("model", "default")
        extra_params = {
            k: v for k, v in body.items() if k not in ["messages", "model", "stream"]
        }

        route_decision = context.get("route_decision")
        backend = route_decision.backend if route_decision else None

        # Get the streaming response from OpenAI client
        async for chunk in await openai_client.stream_chat_completion(
            messages=messages,
            model=model,
            backend=backend,
            **extra_params,
        ):
            if not first_chunk_sent:
                first_chunk_sent = True
                # Send initial event with request metadata
                event_data = {
                    "type": "message_start",
                    "message": {
                        "id": f"msg_{request_id[:8]}",
                        "type": "message",
                        "role": "assistant",
                        "content": [],
                        "model": original_model,
                        "stop_reason": None,
                    },
                }
                yield f"event: message_start\ndata: {json.dumps(event_data)}\n\n"

            # Convert OpenAI chunk to Anthropic format
            if chunk.get("choices"):
                choice = chunk["choices"][0]
                delta = choice.get("message", {})

                # Content block
                if "content" in delta and delta["content"]:
                    content_event = {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {"type": "text", "text": delta["content"]},
                    }
                    yield f"event: content_block_delta\ndata: {json.dumps(content_event)}\n\n"

                # Tool calls
                if "tool_calls" in delta:
                    for tool_call in delta["tool_calls"]:
                        tool_event = {
                            "type": "content_block_delta",
                            "index": 0,
                            "delta": {
                                "type": "tool_use",
                                "id": tool_call.get("id", ""),
                                "name": tool_call.get("function", {}).get("name", ""),
                                "input": tool_call.get("function", {}).get(
                                    "arguments", "{}"
                                ),
                            },
                        }
                        yield f"event: content_block_delta\ndata: {json.dumps(tool_event)}\n\n"

                # Finish reason
                if "finish_reason" in delta:
                    stop_event = {
                        "type": "content_block_stop",
                        "index": 0,
                    }
                    yield f"event: content_block_stop\ndata: {json.dumps(stop_event)}\n\n"

                    # Send message_stop event
                    final_event = {
                        "type": "message_stop",
                        "message": {
                            "id": f"msg_{request_id[:8]}",
                            "type": "message",
                            "role": "assistant",
                            "content": [],
                            "model": original_model,
                            "stop_reason": delta["finish_reason"],
                        },
                    }
                    yield f"event: message_stop\ndata: {json.dumps(final_event)}\n\n"

        # Record metrics
        processing_time_ms = (time.time() - start_time) * 1000
        metrics_tracker.record_success(
            input_tokens=0,  # Would need to accumulate from chunks
            output_tokens=0,
            total_tokens=0,
            latency_ms=processing_time_ms,
        )

    except Exception as e:
        logger.error(f"Error in Anthropic streaming: {e}")
        metrics_tracker.record_error("streaming_error")

        # Send error event
        error_event = {
            "type": "error",
            "error": {
                "type": "api_error",
                "message": str(e),
            },
        }
        yield f"event: error\ndata: {json.dumps(error_event)}\n\n"


async def handle_anthropic_non_streaming(
    openai_client,
    body: dict,
    pipeline: MiddlewarePipeline,
    context: dict,
    config: GatewayConfig,
    original_model: str,
    thinking_intensity: Optional[str],
    metrics_tracker: ModelMetricsTracker,
):
    """
    Handle non-streaming Anthropic API request.

    Converts OpenAI response to Anthropic format with thinking support.
    """
    import time

    start_time = time.time()

    try:
        # Extract parameters
        messages = body.get("messages", [])
        model = body.get("model", "default")
        extra_params = {
            k: v for k, v in body.items() if k not in ["messages", "model", "stream"]
        }

        route_decision = context.get("route_decision")
        backend = route_decision.backend if route_decision else None

        # Get response from OpenAI client
        response = await openai_client.chat_completion(
            messages=messages,
            model=model,
            stream=False,
            backend=backend,
            **extra_params,
        )

        # Convert to dict for processing
        response_data = response.model_dump()

        # Process through middleware pipeline
        response_data = await pipeline.process_response(response_data, context)

        # Calculate processing time
        processing_time_ms = (time.time() - start_time) * 1000

        # Extract usage for metrics
        usage = response_data.get("usage", {})
        metrics_tracker.record_success(
            input_tokens=usage.get("prompt_tokens", 0),
            output_tokens=usage.get("completion_tokens", 0),
            total_tokens=usage.get("total_tokens", 0),
            latency_ms=processing_time_ms,
        )

        # Convert to Anthropic format
        choice = response_data.get("choices", [{}])[0]
        message = choice.get("message", {})

        # Build content blocks array
        content_blocks = []

        # Main text content
        text_content = message.get("content", "")

        # Handle reasoning_content - some models use this instead of content
        if not text_content:
            text_content = message.get("reasoning_content", "")

        if text_content:
            content_blocks.append({"type": "text", "text": text_content})

        # Tool calls
        if message.get("tool_calls"):
            for tool_call in message["tool_calls"]:
                content_blocks.append(
                    {
                        "type": "tool_use",
                        "id": tool_call.get("id", ""),
                        "name": tool_call.get("function", {}).get("name", ""),
                        "input": tool_call.get("function", {}).get("arguments", "{}"),
                    }
                )

        # Handle extended thinking metadata (for Anthropic compatibility)
        thinking_content = None
        reasoning_text = message.get("reasoning_content", "")
        if reasoning_text:
            thinking_content = {
                "thinking": reasoning_text,
                "tokens": response_data.get(
                    "reasoning_tokens", len(reasoning_text) // 4
                ),  # Rough estimate
            }

        # Build Anthropic response
        anthropic_response = {
            "id": response_data.get("id", f"msg_{time.time()}"),
            "type": "message",
            "role": "assistant",
            "content": content_blocks,
            "model": original_model,
            "stop_reason": choice.get("finish_reason", "stop"),
            "stop_sequence": None,
            "usage": {
                "input_tokens": usage.get("prompt_tokens", 0),
                "output_tokens": usage.get("completion_tokens", 0),
            },
            "gateway_metadata": {
                "processing_time_ms": round(processing_time_ms, 2),
                "router": {
                    "model": route_decision.model if route_decision else model,
                    "backend": route_decision.backend if route_decision else "unknown",
                    "reason": route_decision.reason
                    if route_decision
                    else "Anthropic API",
                    "specialization": (
                        route_decision.specialization.value
                        if route_decision and route_decision.specialization
                        else None
                    ),
                    "estimated_tokens": route_decision.estimated_tokens
                    if route_decision
                    else 0,
                    "expected_latency_ms": route_decision.expected_latency_ms
                    if route_decision
                    else 0,
                },
                "thinking": {
                    "intensity": thinking_intensity,
                    "budget": context.get("thinking_budget"),
                }
                if thinking_intensity
                else None,
            },
        }

        # Add extended thinking if present
        if thinking_content:
            anthropic_response["extended_thinking"] = thinking_content

        # Notify circuit breaker of success
        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_success()

        return JSONResponse(content=anthropic_response, status_code=200)

    except OpenAIBackendError as e:
        logger.error(f"Backend error in Anthropic request: {e}")
        metrics_tracker.record_error("backend_error")

        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_failure()

        raise HTTPException(status_code=503, detail=str(e))

    except Exception as e:
        logger.error(f"Unexpected error in Anthropic request: {e}")
        metrics_tracker.record_error("unexpected_error")

        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_failure()

        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")


def main():
    """Main entry point for running the gateway."""
    import uvicorn

    config = GatewayConfig()
    app = create_app(config)

    uvicorn.run(
        app, host=config.gateway_host, port=config.gateway_port, log_level="info"
    )


if __name__ == "__main__":
    main()

# Create app for uvicorn when imported as module
# This is needed when uvicorn imports with: ai_inference_gateway.main:app
try:
    app = create_app()
    if app is None:
        raise RuntimeError("Failed to create FastAPI app - check logs for errors")
except Exception as e:
    print(f"ERROR: Failed to create app: {e}")
    import traceback

    traceback.print_exc()
    raise
