# modules/services/ai-inference/ai_inference_gateway/main.py
import logging
import json
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
from ai_inference_gateway.router import create_default_router, RouteDecision
from ai_inference_gateway.mcp_broker import create_mcp_broker_from_config
from ai_inference_gateway.metrics import ModelMetricsTracker, RoutingMetricsTracker
from ai_inference_gateway.response_format import transform_request, validate_response

# Initialize logger early (needed for import error handling)
logger = logging.getLogger(__name__)

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

# Import middleware
from ai_inference_gateway.middleware.observability import ObservabilityMiddleware
from ai_inference_gateway.middleware.security_filter import SecurityFilterMiddleware
from ai_inference_gateway.middleware.rate_limiter import RateLimiterMiddleware
from ai_inference_gateway.middleware.circuit_breaker import CircuitBreaker
from ai_inference_gateway.middleware.concurrency_limiter import ConcurrencyLimiter

# Try to import prometheus_client for metrics endpoint
try:
    from prometheus_client import (
        Counter,
        Histogram,
        Gauge,
        generate_latest,
        CONTENT_TYPE_LATEST,
    )

    PROMETHEUS_AVAILABLE = True
except ImportError:
    PROMETHEUS_AVAILABLE = False
    generate_latest = None
    CONTENT_TYPE_LATEST = None


GATEWAY_VERSION = "2.0.0"


async def check_backend_health(url: str, timeout: float = 5.0) -> bool:
    """
    Check if backend is healthy by querying the models endpoint.

    Args:
        url: Backend URL
        timeout: Request timeout in seconds

    Returns:
        True if backend is healthy, False otherwise
    """
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(f"{url}/v1/models")
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
            "ttl": 30  # Cache health status for 30 seconds
        }
        # RAG service (initialized if enabled)
        self.rag_search = None
        self.rag_config = None


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
        k: v
        for k, v in request_headers.items()
        if k.lower() not in excluded_headers
    }

    # Only add backend authentication if client didn't provide one
    if "authorization" not in {k.lower() for k in headers.keys()}:
        if config.backend_type == "lm-studio":
            api_key = config.get_lm_studio_api_key()
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

    # Initialize router
    state.router = create_default_router()
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
            from ai_inference_gateway.rag.config import RAGConfig, EmbeddingConfig, ChunkingConfig, SearchConfig, RerankerConfig

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
                    device="cuda"  # Use CUDA by default
                ),
                chunking=ChunkingConfig(
                    chunk_size=chunk_size,
                    chunk_overlap=chunk_overlap
                ),
                search=SearchConfig(
                    default_top_k=top_k,
                    hybrid_search=hybrid_search
                ),
                reranker=RerankerConfig(
                    enable=reranker_enabled,
                    model=reranker_model
                )
            )

            # Initialize components
            embedder = await create_embedding_service(state.rag_config.embedding)
            qdrant = await get_qdrant_manager(state.rag_config)
            state.rag_search = await create_search_service(
                state.rag_config,
                embedder,
                qdrant
            )

            logger.info("RAG service initialized successfully")
        except Exception as e:
            logger.error(f"RAG initialization failed: {e}")
            import traceback
            traceback.print_exc()
            state.rag_search = None

    # Startup complete
    logger.info("Gateway startup complete")

    yield

    # Shutdown cleanup
    logger.info("Shutting down gateway")

    if state.redis_client:
        await state.redis_client.close()
        logger.info("Redis connection closed")

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
        logger.info(f"Added ConcurrencyLimiter (max_concurrency={config.middleware.concurrency_limiter.max_concurrency})")

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


def create_app(config: Optional[GatewayConfig] = None) -> FastAPI:
    """
    Create and configure the FastAPI application.

    Args:
        config: Optional gateway configuration. If not provided, loads from environment.

    Returns:
        Configured FastAPI application
    """
    if config is None:
        config = GatewayConfig()

    # Initialize gateway state with OpenAI client wrapper
    openai_client = create_openai_client(config)
    gateway_state = GatewayState(
        config=config,
        openai_client=openai_client,
    )

    # Create FastAPI app
    app = FastAPI(
        title="AI Inference Gateway",
        description="Advanced gateway for AI inference backends with middleware",
        version=GATEWAY_VERSION,
        lifespan=lifespan,
    )

    # Store gateway state in app
    app.state.gateway = gateway_state

    # Add health endpoint
    @app.get("/health")
    async def health_check():
        """Health check endpoint with actual backend health status."""
        import time

        state: GatewayState = app.state.gateway

        # Check if cached health status is still valid
        now = time.time()
        cache_age = now - state.backend_health_cache["last_check"]

        if cache_age > state.backend_health_cache["ttl"]:
            # Cache expired, check actual backend health
            is_healthy = await check_backend_health(state.config.backend_url)
            state.backend_health_cache = {
                "healthy": is_healthy,
                "last_check": now,
                "ttl": 30
            }
            logger.info(f"Backend health check: {is_healthy}")
            # Recalculate cache_age after updating
            cache_age = 0

        backend_healthy = state.backend_health_cache["healthy"]

        return {
            "status": "healthy",
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
                logger.warning(f"Failed to update model availability metrics: {metrics_error}")

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


    # Add chat completions endpoint
    @app.post("/v1/chat/completions")
    async def chat_completions(request: Request):
        """
        Chat completions endpoint with middleware processing and intelligent routing.

        Supports both streaming and non-streaming requests.
        Uses router for intelligent model selection based on request analysis.
        """
        import time
        request_start = time.time()

        state: GatewayState = app.state.gateway

        # Read request body
        body = await request.json()

        # Transform response_format to LM Studio instructions
        # (OpenAI JSON mode -> LM Studio system prompts)
        if "response_format" in body:
            body = await transform_request(body)
            logger.debug(f"Transformed response_format request for model: {body.get('model')}")

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

        # Track request start for smart load balancing
        import uuid
        request_id = str(uuid.uuid4())
        state.router.track_request_start(
            request_id=request_id,
            model=route_decision.model,
            backend=route_decision.backend,
            stream=stream
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
            requested_model=requested_model
        )

        # Record routing decision metadata
        metrics_tracker.record_routing_decision(
            confidence=route_decision.confidence,
            reason=route_decision.reason,
            specialization=route_decision.specialization.value if route_decision.specialization else None
        )

        # Create context for middleware
        context = {
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

    @app.post("/v1/messages")
    async def messages(request: Request):
        """
        Anthropic Messages API compatibility endpoint.

        Translates Anthropic-format requests to OpenAI format
        and forwards to the backend.
        """
        state: GatewayState = app.state.gateway

        # Read request body
        body = await request.json()

        # Translate Anthropic format to OpenAI format
        model = body.get("model", "")
        max_tokens = body.get("max_tokens", 4096)
        messages = body.get("messages", [])
        system = body.get("system", None)
        stream = body.get("stream", False)

        # Convert messages format
        openai_messages = []
        for msg in messages:
            role = msg.get("role", "user")
            content = msg.get("content")

            if isinstance(content, str):
                openai_messages.append({"role": role, "content": content})
            elif isinstance(content, list):
                # Handle content blocks (text, images, etc.)
                text_blocks = [
                    block.get("text", "")
                    for block in content
                    if block.get("type") == "text"
                ]
                combined_content = "\n".join(text_blocks)
                openai_messages.append({"role": role, "content": combined_content})

        # Build OpenAI-format request
        openai_request = {
            "model": model,
            "messages": openai_messages,
            "max_tokens": max_tokens,
            "stream": stream,
        }

        if system:
            openai_request["messages"].insert(0, {"role": "system", "content": system})

        # Create context for middleware
        context = {
            "request_body": openai_request,
            "request_headers": dict(request.headers),
            "original_format": "anthropic",
        }

        # Process request through middleware pipeline
        should_continue, error = await state.pipeline.process_request(request, context)

        if not should_continue:
            if error:
                raise error
            raise HTTPException(status_code=403, detail="Request blocked by middleware")

        # Forward to backend
        # Build headers with authentication
        backend_headers = build_backend_headers(state.config, dict(request.headers))

        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    f"{state.config.backend_url}/v1/chat/completions",
                    json=openai_request,
                    headers=backend_headers,
                    timeout=300.0,
                )
                response.raise_for_status()

                response_data = response.json()

                # Process response through middleware pipeline
                response_data = await state.pipeline.process_response(
                    response_data, context
                )

                # Translate back to Anthropic format if needed
                if context.get("original_format") == "anthropic":
                    # Convert OpenAI response to Anthropic format
                    choice = response_data.get("choices", [{}])[0]
                    message = choice.get("message", {})

                    anthropic_response = {
                        "id": response_data.get("id", "msg-1"),
                        "type": "message",
                        "role": "assistant",
                        "content": message.get("content", ""),
                        "model": response_data.get("model", model),
                        "stop_reason": choice.get("finish_reason", "stop"),
                        "usage": {
                            "input_tokens": response_data.get("usage", {}).get(
                                "prompt_tokens", 0
                            ),
                            "output_tokens": response_data.get("usage", {}).get(
                                "completion_tokens", 0
                            ),
                        },
                    }

                    return JSONResponse(
                        content=anthropic_response, status_code=response.status_code
                    )

                return JSONResponse(
                    content=response_data, status_code=response.status_code
                )

            except httpx.HTTPError as e:
                logger.error(f"Error forwarding request: {e}")

                # Notify circuit breaker of failure
                if state.config.middleware.circuit_breaker.enabled:
                    for middleware in state.pipeline.middleware:
                        if isinstance(middleware, CircuitBreaker):
                            await middleware.on_failure()

                raise HTTPException(status_code=503, detail=f"Backend error: {str(e)}")

    # ============================================================================
    # MCP Broker Endpoints
    # ============================================================================

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
            raise HTTPException(
                status_code=501,
                detail="MCP broker not enabled"
            )

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
            raise HTTPException(
                status_code=501,
                detail="MCP broker not enabled"
            )

        body = await request.json()
        server_name = body.get("server")

        result = await state.mcp_broker.invalidate_cache(server_name)
        return result

    @app.get("/mcp/cache/metrics")
    async def get_mcp_cache_metrics():
        """Get MCP cache performance metrics."""
        state: GatewayState = app.state.gateway

        if not state.mcp_broker:
            raise HTTPException(
                status_code=501,
                detail="MCP broker not enabled"
            )

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
            raise HTTPException(
                status_code=501,
                detail="MCP broker not enabled"
            )

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
                "models": {}
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
                )
            }
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
            "models_reset": reset_count
        }

    @app.post("/mcp/call")
    async def call_mcp_tool(request: Request):
        """Call an MCP tool on a specific server."""
        state: GatewayState = app.state.gateway

        if not state.mcp_broker:
            raise HTTPException(
                status_code=501,
                detail="MCP broker not enabled"
            )

        body = await request.json()
        server_name = body.get("server")
        tool_name = body.get("tool")
        arguments = body.get("arguments", {})

        if not server_name or not tool_name:
            raise HTTPException(
                status_code=400,
                detail="Missing required fields: server, tool"
            )

        result = await state.mcp_broker.call_tool(
            server_name=server_name,
            tool_name=tool_name,
            arguments=arguments
        )
        return result

    @app.get("/mcp/health/{server_name}")
    async def mcp_server_health(server_name: str):
        """Check MCP server health."""
        state: GatewayState = app.state.gateway

        if not state.mcp_broker:
            raise HTTPException(
                status_code=501,
                detail="MCP broker not enabled"
            )

        is_healthy = await state.mcp_broker.health_check(server_name)
        return {
            "server": server_name,
            "healthy": is_healthy,
            "exists": server_name in state.mcp_broker.servers
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
                raise HTTPException(
                    status_code=501,
                    detail="RAG service not enabled"
                )

            body = await request.json()
            collection = body.get("collection", "default")
            documents = body.get("documents", [])

            if not documents:
                raise HTTPException(
                    status_code=400,
                    detail="No documents provided"
                )

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
                    document_id=document_id
                )
                results.append(result)

            # Return summary
            total_chunks = sum(r.get("chunks_created", 0) for r in results if r.get("success"))
            return {
                "success": True,
                "documents_ingested": len(results),
                "chunks_created": total_chunks,
                "collection": collection,
                "results": results
            }

        @app.get("/rag/search")
        async def search_knowledge_base(request: Request):
            """Search RAG knowledge base."""
            state: GatewayState = app.state.gateway

            if not state.rag_search:
                raise HTTPException(
                    status_code=501,
                    detail="RAG service not enabled"
                )

            query = request.query_params.get("query", "")
            if not query:
                raise HTTPException(
                    status_code=400,
                    detail="Missing required parameter: query"
                )

            collection = request.query_params.get("collection", "default")
            top_k = int(request.query_params.get("top_k", 5))
            rerank = request.query_params.get("rerank", "true").lower() == "true"

            result = await state.rag_search.search(
                query=query,
                collection=collection,
                top_k=top_k,
                rerank=rerank
            )

            return result

        @app.get("/rag/collections")
        async def list_collections(request: Request):
            """List all RAG collections."""
            state: GatewayState = app.state.gateway

            if not state.rag_search:
                raise HTTPException(
                    status_code=501,
                    detail="RAG service not enabled"
                )

            collections = await state.rag_search.get_collections()
            return {
                "collections": collections
            }

        @app.delete("/rag/documents")
        async def delete_document(request: Request):
            """Delete document from RAG knowledge base."""
            state: GatewayState = app.state.gateway

            if not state.rag_search:
                raise HTTPException(
                    status_code=501,
                    detail="RAG service not enabled"
                )

            body = await request.json()
            collection = body.get("collection", "default")
            document_id = body.get("document_id")

            if not document_id:
                raise HTTPException(
                    status_code=400,
                    detail="Missing required field: document_id"
                )

            result = await state.rag_search.delete_document(
                collection=collection,
                document_id=document_id
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
                        "digest": "gateway-proxy"
                    }
                ]
            }

        # Transform to Ollama format
        ollama_models = []
        for model in models.data:
            # Extract base name without organization prefix
            model_name = model.id.split('/')[-1] if '/' in model.id else model.id

            ollama_models.append({
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
                    "quantization_level": "unknown"
                }
            })

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
            "temperature": temperature
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
                    "ollama-gen"
                ):
                    # Transform SSE to Ollama format
                    try:
                        chunk_str = chunk.decode('utf-8') if isinstance(chunk, bytes) else chunk
                        if '"content"' in chunk_str:
                            import json
                            # Parse and transform
                            lines = chunk_str.split('\n')
                            for line in lines:
                                if line.startswith('data: ') and line != 'data: [DONE]':
                                    try:
                                        data = json.loads(line[6:])
                                        if 'choices' in data and len(data['choices']) > 0:
                                            delta = data['choices'][0].get('delta', {})
                                            content = delta.get('content', '')
                                            if content:
                                                ollama_chunk = {
                                                    "model": model,
                                                    "created_at": datetime.now().isoformat(),
                                                    "response": content,
                                                    "done": False
                                                }
                                                yield f"data: {json.dumps(ollama_chunk)}\n\n"
                                    except:
                                        pass
                    except:
                        # If transformation fails, pass through as-is
                        if isinstance(chunk, bytes):
                            yield chunk
                        else:
                            yield chunk.encode('utf-8') if isinstance(chunk, str) else chunk

                # Send final done signal
                done_chunk = {
                    "model": model,
                    "created_at": datetime.now().isoformat(),
                    "response": "",
                    "done": True,
                    "context": [0, 1]  # Placeholder
                }
                yield f"data: {json.dumps(done_chunk)}\n\n"

            return StreamingResponse(
                generate_stream(),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                }
            )
        else:
            # Non-streaming response
            response = await state.openai_client.chat_completion(
                messages=openai_request["messages"],
                model=openai_request["model"],
                max_tokens=openai_request["max_tokens"],
                temperature=openai_request["temperature"],
                stream=False
            )

            # Transform to Ollama format
            content = response.choices[0].message.content

            return {
                "model": model,
                "created_at": datetime.now().isoformat(),
                "response": content,
                "done": True
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
            "temperature": temperature
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
                    "ollama-chat"
                ):
                    # Transform SSE to Ollama format
                    try:
                        chunk_str = chunk.decode('utf-8') if isinstance(chunk, bytes) else chunk
                        if '"content"' in chunk_str:
                            import json
                            lines = chunk_str.split('\n')
                            for line in lines:
                                if line.startswith('data: ') and line != 'data: [DONE]':
                                    try:
                                        data = json.loads(line[6:])
                                        if 'choices' in data and len(data['choices']) > 0:
                                            delta = data['choices'][0].get('delta', {})
                                            content = delta.get('content', '')
                                            if content:
                                                role = delta.get('role', 'assistant')
                                                ollama_chunk = {
                                                    "model": model,
                                                    "created_at": datetime.now().isoformat(),
                                                    "message": {
                                                        "role": role,
                                                        "content": content
                                                    },
                                                    "done": False
                                                }
                                                yield f"data: {json.dumps(ollama_chunk)}\n\n"
                                    except:
                                        pass
                    except:
                        # If transformation fails, pass through as-is
                        if isinstance(chunk, bytes):
                            yield chunk
                        else:
                            yield chunk.encode('utf-8') if isinstance(chunk, str) else chunk

                # Send final done signal
                done_chunk = {
                    "model": model,
                    "created_at": datetime.now().isoformat(),
                    "message": {
                        "role": "assistant",
                        "content": ""
                    },
                    "done": True,
                    "context": [0, 1]  # Placeholder
                }
                yield f"data: {json.dumps(done_chunk)}\n\n"

            return StreamingResponse(
                chat_stream(),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                }
            )
        else:
            # Non-streaming response - use existing endpoint logic
            response = await state.openai_client.chat_completion(
                messages=openai_request["messages"],
                model=openai_request["model"],
                max_tokens=openai_request["max_tokens"],
                temperature=openai_request["temperature"],
                stream=False
            )

            # Transform to Ollama format
            message = response.choices[0].message

            return {
                "model": model,
                "created_at": datetime.now().isoformat(),
                "message": {
                    "role": message.role,
                    "content": message.content
                },
                "done": True
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
                "features": ["ollama-api", "openai-api", "rag", "mcp"]
            }
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
                status_code=501,
                detail="Embeddings not enabled. Set RAG_ENABLED=true"
            )

        body = await request.json()
        model = body.get("model", "BAAI/bge-m3")
        prompt = body.get("prompt", "")

        # Generate embedding
        embedding = await state.rag_search.embedder.embed_single(prompt)

        return {
            "embedding": embedding
        }

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
        extra_params = {k: v for k, v in body.items() if k not in ["messages", "model", "stream"]}

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
            if hasattr(chunk, 'usage') and chunk.usage:
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

        # Yield error as SSE comment
        yield f"data: {{'error': '{str(e)}'}}\n\n"
    except Exception as e:
        logger.error(f"Unexpected error in streaming request: {e}")

        # Record error metrics
        metrics_tracker.record_error("unexpected_error")

        # Notify circuit breaker of failure
        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_failure()

        yield f"data: {{'error': 'Unexpected error: {str(e)}'}}\n\n"
    finally:
        # Always clean up request tracking
        router.track_request_end(request_id)


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
            headers = {k: v for k, v in request_headers.items()
                      if k.lower() not in {"host", "content-length", "content-encoding", "transfer-encoding"}}

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
                        logger.warning(f"ZAI API key not found for fallback backend")

            logger.info(f"Request headers for {backend_type_name} backend: Authorization={'Bearer ' + (headers.get('Authorization', 'NO-AUTH')[:20] + '...' if 'Authorization' in headers else 'NOT SET')}")

            async with httpx.AsyncClient(timeout=timeout) as client:
                # For ZAI, convert OpenAI-style endpoints to ZAI format
                if backend_api_type == "zai":
                    # ZAI uses /chat/completions instead of /v1/chat/completions
                    zai_endpoint = endpoint.replace("/v1/", "/") if endpoint.startswith("/v1/") else endpoint
                    url = f"{backend_url}{zai_endpoint}"
                else:
                    url = f"{backend_url}{endpoint}"

                # Debug logging for ZAI (only at DEBUG level)
                if backend_api_type == "zai" and logger.isEnabledFor(logging.DEBUG):
                    logger.debug(f"ZAI URL: {url}")
                    logger.debug(f"ZAI Headers: Authorization={headers.get('Authorization', 'MISSING')[:30]}...")
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
                logger.info(f"{backend_type_name} backend response: HTTP {response.status_code}")

                # Debug logging for ZAI responses (only at DEBUG level)
                if backend_api_type == "zai" and logger.isEnabledFor(logging.DEBUG):
                    logger.debug(f"ZAI Response status: {response.status_code}")
                    if response.status_code != 200:
                        try:
                            logger.debug(f"ZAI Response body: {response.text[:500]}")
                        except:
                            pass

                # If we got here, the request succeeded (connected, even if 4xx/5xx)
                return response, backend_url

        except (httpx.ConnectError, httpx.TimeoutException, httpx.ConnectTimeout) as e:
            logger.warning(f"{backend_type_name} backend {backend_url} failed: {str(e)}")
            last_error = e
            continue
        except Exception as e:
            logger.warning(f"{backend_type_name} backend {backend_url} failed with unexpected error: {str(e)}")
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
        extra_params = {k: v for k, v in body.items() if k not in ["messages", "model", "stream"]}

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
                    "specialization": route_decision.specialization.value if route_decision.specialization else None,
                    "estimated_tokens": route_decision.estimated_tokens,
                    "expected_latency_ms": route_decision.expected_latency_ms,
                }
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


    # Add messages endpoint (Anthropic-compatible)


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
