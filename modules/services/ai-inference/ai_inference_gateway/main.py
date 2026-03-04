# modules/services/ai-inference/ai_inference_gateway/main.py
import logging
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
import httpx

from ai_inference_gateway.config import GatewayConfig
from ai_inference_gateway.pipeline import MiddlewarePipeline
from ai_inference_gateway.utils.redis_client import RedisClient

# Import middleware
from ai_inference_gateway.middleware.observability import ObservabilityMiddleware
from ai_inference_gateway.middleware.security_filter import SecurityFilterMiddleware
from ai_inference_gateway.middleware.rate_limiter import RateLimiterMiddleware
from ai_inference_gateway.middleware.circuit_breaker import CircuitBreaker


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
        pipeline: Optional[MiddlewarePipeline] = None
    ):
        self.config = config
        self.redis_client = redis_client
        self.pipeline = pipeline


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
        "Middleware pipeline initialized with %d middleware",
        state.pipeline.count
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
    config: GatewayConfig,
    redis_client: Optional[RedisClient]
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
            config=config.middleware.rate_limiting,
            redis_client=redis_client
        )
        pipeline.add(rate_limiter)
        logger.info("Added RateLimiterMiddleware")

    # Add circuit breaker
    if config.middleware.circuit_breaker.enabled:
        circuit_breaker = CircuitBreaker(
            service_id="backend",
            config=config.middleware.circuit_breaker,
            redis_client=redis_client
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
        config = GatewayConfig.load_from_env()

    # Initialize gateway state
    gateway_state = GatewayState(config=config)

    # Create FastAPI app
    app = FastAPI(
        title="AI Inference Gateway",
        description="Advanced gateway for AI inference backends with middleware",
        version=GATEWAY_VERSION,
        lifespan=lifespan
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
                "port": config.gateway_port
            },
            "backend": {
                "url": config.backend_url,
                "type": config.backend_type,
                "healthy": True  # TODO: Implement actual health check
            }
        }

    # Add models endpoint
    @app.get("/v1/models")
    async def list_models():
        """List available models from backend."""
        state: GatewayState = app.state.gateway

        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    f"{state.config.backend_url}/v1/models",
                    timeout=30.0
                )
                response.raise_for_status()
                return response.json()
            except httpx.HTTPError as e:
                logger.error(f"Error fetching models: {e}")
                raise HTTPException(
                    status_code=503,
                    detail=f"Backend unavailable: {str(e)}"
                )

    # Add chat completions endpoint
    @app.post("/v1/chat/completions")
    async def chat_completions(request: Request):
        """
        Chat completions endpoint with middleware processing.

        Forwards requests to the backend after processing through
        the middleware pipeline.
        """
        state: GatewayState = app.state.gateway

        # Read request body
        body = await request.json()

        # Create context for middleware
        context = {
            "request_body": body,
            "request_headers": dict(request.headers)
        }

        # Process request through middleware pipeline
        should_continue, error = await state.pipeline.process_request(request, context)

        if not should_continue:
            # Middleware blocked the request
            if error:
                raise error
            raise HTTPException(status_code=403, detail="Request blocked by middleware")

        # Forward to backend
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    f"{state.config.backend_url}/v1/chat/completions",
                    json=body,
                    headers={k: v for k, v in request.headers.items() if k.lower() != "host"},
                    timeout=300.0  # 5 minute timeout for inference
                )
                response.raise_for_status()

                # Get response data
                response_data = response.json()

                # Process response through middleware pipeline (reverse order)
                response_data = await state.pipeline.process_response(response_data, context)

                return JSONResponse(content=response_data, status_code=response.status_code)

            except httpx.HTTPError as e:
                logger.error(f"Error forwarding request: {e}")

                # Notify circuit breaker of failure
                if state.config.middleware.circuit_breaker.enabled:
                    for middleware in state.pipeline.middleware:
                        if isinstance(middleware, CircuitBreaker):
                            await middleware.on_failure()

                raise HTTPException(
                    status_code=503,
                    detail=f"Backend error: {str(e)}"
                )

    # Add messages endpoint (Anthropic-compatible)
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
                text_blocks = [block.get("text", "") for block in content if block.get("type") == "text"]
                combined_content = "\n".join(text_blocks)
                openai_messages.append({"role": role, "content": combined_content})

        # Build OpenAI-format request
        openai_request = {
            "model": model,
            "messages": openai_messages,
            "max_tokens": max_tokens,
            "stream": stream
        }

        if system:
            openai_request["messages"].insert(0, {"role": "system", "content": system})

        # Create context for middleware
        context = {
            "request_body": openai_request,
            "request_headers": dict(request.headers),
            "original_format": "anthropic"
        }

        # Process request through middleware pipeline
        should_continue, error = await state.pipeline.process_request(request, context)

        if not should_continue:
            if error:
                raise error
            raise HTTPException(status_code=403, detail="Request blocked by middleware")

        # Forward to backend
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    f"{state.config.backend_url}/v1/chat/completions",
                    json=openai_request,
                    headers={k: v for k, v in request.headers.items() if k.lower() != "host"},
                    timeout=300.0
                )
                response.raise_for_status()

                response_data = response.json()

                # Process response through middleware pipeline
                response_data = await state.pipeline.process_response(response_data, context)

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
                            "input_tokens": response_data.get("usage", {}).get("prompt_tokens", 0),
                            "output_tokens": response_data.get("usage", {}).get("completion_tokens", 0)
                        }
                    }

                    return JSONResponse(content=anthropic_response, status_code=response.status_code)

                return JSONResponse(content=response_data, status_code=response.status_code)

            except httpx.HTTPError as e:
                logger.error(f"Error forwarding request: {e}")

                # Notify circuit breaker of failure
                if state.config.middleware.circuit_breaker.enabled:
                    for middleware in state.pipeline.middleware:
                        if isinstance(middleware, CircuitBreaker):
                            await middleware.on_failure()

                raise HTTPException(
                    status_code=503,
                    detail=f"Backend error: {str(e)}"
                )

    return app


def main():
    """Main entry point for running the gateway."""
    import uvicorn

    config = GatewayConfig.load_from_env()
    app = create_app(config)

    uvicorn.run(
        app,
        host=config.gateway_host,
        port=config.gateway_port,
        log_level="info"
    )


if __name__ == "__main__":
    main()
