# modules/services/ai-inference/ai_inference_gateway/main.py
import logging
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse, Response, StreamingResponse
import httpx

from ai_inference_gateway.config import GatewayConfig
from ai_inference_gateway.pipeline import MiddlewarePipeline
from ai_inference_gateway.utils.redis_client import RedisClient

# Import middleware
from ai_inference_gateway.middleware.observability import ObservabilityMiddleware
from ai_inference_gateway.middleware.security_filter import SecurityFilterMiddleware
from ai_inference_gateway.middleware.rate_limiter import RateLimiterMiddleware
from ai_inference_gateway.middleware.circuit_breaker import CircuitBreaker

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


logger = logging.getLogger(__name__)


GATEWAY_VERSION = "2.0.0"


class GatewayState:
    """
    Gateway application state.

    Stores shared state across the application including config,
    Redis client, and middleware pipeline.
    """

    def __init__(
        self,
        config: GatewayConfig,
        redis_client: Optional[RedisClient] = None,
        pipeline: Optional[MiddlewarePipeline] = None,
    ):
        self.config = config
        self.redis_client = redis_client
        self.pipeline = pipeline


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

    # Startup complete
    logger.info("Gateway startup complete")

    yield

    # Shutdown cleanup
    logger.info("Shutting down gateway")

    if state.redis_client:
        await state.redis_client.close()
        logger.info("Redis connection closed")

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

    # Initialize gateway state
    gateway_state = GatewayState(config=config)

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
        """Health check endpoint."""
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
                "healthy": True,  # TODO: Implement actual health check
            },
        }

    # Add models endpoint
    @app.get("/v1/models")
    async def list_models(request: Request):
        """List available models from backend with automatic failover."""
        state: GatewayState = app.state.gateway

        # Build headers with authentication (include original request headers)
        backend_headers = build_backend_headers(state.config, dict(request.headers))

        try:
            # Try backends in order (primary + fallbacks)
            response, actual_backend_url = await try_backends_with_failover(
                config=state.config,
                request_headers=backend_headers,
                endpoint="/v1/models",
                method="GET",
                timeout=30.0,
            )

            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as e:
            logger.error(f"Error fetching models: {e}")
            raise HTTPException(
                status_code=503, detail=f"Backend unavailable: {str(e)}"
            )

    # Add chat completions endpoint
    @app.post("/v1/chat/completions")
    async def chat_completions(request: Request):
        """
        Chat completions endpoint with middleware processing.

        Supports both streaming and non-streaming requests.
        """
        state: GatewayState = app.state.gateway

        # Read request body
        body = await request.json()

        # Check if streaming is requested
        stream = body.get("stream", False)

        # Create context for middleware
        context = {"request_body": body, "request_headers": dict(request.headers)}

        # Process request through middleware pipeline
        should_continue, error = await state.pipeline.process_request(request, context)

        if not should_continue:
            # Middleware blocked the request
            if error:
                raise error
            raise HTTPException(status_code=403, detail="Request blocked by middleware")

        # Forward to backend
        # Build headers with authentication
        backend_headers = build_backend_headers(state.config, dict(request.headers))

        if stream:
            # Handle streaming response
            return StreamingResponse(
                stream_backend_response(
                    state.config.backend_url,
                    body,
                    backend_headers,
                    state.pipeline,
                    context,
                    state.config,
                ),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                },
            )
        else:
            # Handle non-streaming response
            return await handle_non_streaming_request(
                state.config.backend_url,
                body,
                backend_headers,
                state.pipeline,
                context,
                state.config,
            )

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
    backend_url: str,
    body: dict,
    headers: dict,
    pipeline: MiddlewarePipeline,
    context: dict,
    config: GatewayConfig,
):
    """
    Stream backend response line by line.

    Args:
        backend_url: Backend URL
        body: Request body
        headers: Request headers
        pipeline: Middleware pipeline
        context: Request context
        config: Gateway configuration

    Yields:
        SSE formatted response chunks
    """
    async with httpx.AsyncClient(timeout=300.0) as client:
        try:
            async with client.stream(
                "POST", f"{backend_url}/v1/chat/completions", json=body, headers=headers
            ) as response:
                # Check for HTTP errors
                if response.status_code >= 400:
                    error_text = await response.aread()
                    error_detail = f"Backend error {response.status_code}: {error_text.decode()[:200]}"

                    # Notify circuit breaker of failure
                    if config.middleware.circuit_breaker.enabled:
                        for middleware in pipeline.middleware:
                            if isinstance(middleware, CircuitBreaker):
                                await middleware.on_failure()

                    # Yield error as SSE comment
                    yield f" data: {{'error': '{error_detail}'}}\n\n"
                    return

                # Stream response line by line
                async for line in response.aiter_lines():
                    if line:
                        # Pass through SSE format
                        yield f"{line}\n"

                # Notify circuit breaker of success
                if config.middleware.circuit_breaker.enabled:
                    for middleware in pipeline.middleware:
                        if isinstance(middleware, CircuitBreaker):
                            await middleware.on_success()

        except httpx.HTTPError as e:
            logger.error(f"Network error in streaming request: {e}")

            # Notify circuit breaker of failure
            if config.middleware.circuit_breaker.enabled:
                for middleware in pipeline.middleware:
                    if isinstance(middleware, CircuitBreaker):
                        await middleware.on_failure()

            yield f" data: {{'error': 'Network error: {str(e)}'}}\n\n"


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

            # Build headers for this backend
            headers = {k: v for k, v in request_headers.items()
                      if k.lower() not in {"host", "content-length", "content-encoding", "transfer-encoding"}}

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

                logger.info(f"Making request to {backend_type_name} backend: {url}")

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
    backend_url: str,
    body: dict,
    headers: dict,
    pipeline: MiddlewarePipeline,
    context: dict,
    config: GatewayConfig,
):
    """
    Handle non-streaming request.

    Args:
        backend_url: Backend URL
        body: Request body
        headers: Request headers
        pipeline: Middleware pipeline
        context: Request context
        config: Gateway configuration

    Returns:
        JSON response
    """
    try:
        # Try backends in order (primary + fallbacks)
        response, actual_backend_url = await try_backends_with_failover(
            config=config,
            request_headers=headers,
            endpoint="/v1/chat/completions",
            method="POST",
            content=body,
            timeout=300.0,
        )

        # Check for HTTP errors
        if response.status_code >= 400:
                error_detail = f"Backend error {response.status_code}"

                # Try to extract error details from response
                try:
                    error_json = response.json()
                    if "error" in error_json:
                        error_msg = error_json["error"].get(
                            "message", str(error_json["error"])
                        )
                        error_detail = f"{error_detail}: {error_msg}"
                    else:
                        error_detail = f"{error_detail}: {error_json}"
                except Exception:
                    # If response isn't JSON, use text
                    if response.text:
                        error_detail = f"{error_detail}: {response.text[:200]}"

                logger.error(f"Backend error: {error_detail}")

                # Notify circuit breaker of failure
                if config.middleware.circuit_breaker.enabled:
                    for middleware in pipeline.middleware:
                        if isinstance(middleware, CircuitBreaker):
                            await middleware.on_failure()

                # Return appropriate status code
                status_code = (
                    503 if response.status_code >= 500 else response.status_code
                )
                raise HTTPException(status_code=status_code, detail=error_detail)

        # Parse JSON response
        try:
            response_data = response.json()
        except Exception as e:
            logger.error(f"Failed to parse backend response as JSON: {e}")
            logger.error(f"Response text: {response.text[:500]}")
            raise HTTPException(
                status_code=502, detail=f"Invalid response from backend: {str(e)}"
            )

        # Process response through middleware pipeline (reverse order)
        response_data = await pipeline.process_response(response_data, context)

        # Notify circuit breaker of success
        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_success()

        return JSONResponse(content=response_data, status_code=response.status_code)

    except httpx.HTTPError as e:
        logger.error(f"Network error after all backends failed: {e}")

        # Notify circuit breaker of failure
        if config.middleware.circuit_breaker.enabled:
            for middleware in pipeline.middleware:
                if isinstance(middleware, CircuitBreaker):
                    await middleware.on_failure()

        raise HTTPException(status_code=503, detail=f"All backends unavailable: {str(e)}")

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
