"""
OpenAI SDK client wrapper for AI Gateway.

This module provides OpenAI client instances configured for different backends:
- LM Studio (local OpenAI-compatible server)
- ZAI (cloud OpenAI-compatible API)

The OpenAI SDK handles:
- Automatic header management (User-Agent, etc.)
- Proper authentication (Bearer tokens)
- Request/response formatting
- Streaming support
- Error handling
"""

import logging
from typing import Optional, AsyncIterator, Dict, Any
from openai import AsyncOpenAI, AsyncStream
from openai.types.chat import ChatCompletion, ChatCompletionChunk

logger = logging.getLogger(__name__)


class OpenAIBackendError(Exception):
    """Exception raised when backend request fails."""
    pass


class OpenAIClientWrapper:
    """
    Wrapper for OpenAI SDK clients with automatic backend failover.

    Manages multiple OpenAI clients for different backends and provides
    a unified interface for chat completions with automatic failover.
    """

    def __init__(
        self,
        primary_url: str,
        primary_api_key: Optional[str],
        fallback_url: Optional[str] = None,
        fallback_api_key: Optional[str] = None,
        timeout: float = 300.0,
    ):
        """
        Initialize OpenAI client wrapper.

        Args:
            primary_url: Primary backend URL (e.g., LM Studio)
            primary_api_key: API key for primary backend (optional for local)
            fallback_url: Fallback backend URL (e.g., ZAI)
            fallback_api_key: API key for fallback backend
            timeout: Request timeout in seconds
        """
        self.primary_url = primary_url.rstrip("/")
        self.primary_api_key = primary_api_key or "not-needed"  # LM Studio doesn't need key
        self.fallback_url = fallback_url.rstrip("/") if fallback_url else None
        self.fallback_api_key = fallback_api_key
        self.timeout = timeout

        # Initialize primary client
        self.primary_client = AsyncOpenAI(
            base_url=f"{self.primary_url}/v1",
            api_key=self.primary_api_key,
            timeout=timeout,
        )

        # Initialize fallback client if configured
        self.fallback_client: Optional[AsyncOpenAI] = None
        if self.fallback_url and self.fallback_api_key:
            # ZAI uses /api/coding/paas/v4 without /v1 prefix
            self.fallback_client = AsyncOpenAI(
                base_url=self.fallback_url,
                api_key=self.fallback_api_key,
                timeout=timeout,
            )
            logger.info(f"Initialized ZAI fallback client: {self.fallback_url}")

    async def chat_completion(
        self,
        messages: list[Dict[str, Any]],
        model: str,
        stream: bool = False,
        **kwargs,
    ) -> ChatCompletion | AsyncStream[ChatCompletionChunk]:
        """
        Create chat completion with automatic failover.

        Args:
            messages: Chat messages
            model: Model name
            stream: Whether to stream response
            **kwargs: Additional OpenAI parameters

        Returns:
            ChatCompletion or AsyncStream of ChatCompletionChunk

        Raises:
            OpenAIBackendError: If all backends fail
        """
        # Remove 'stream' from kwargs to avoid duplicate parameter error
        kwargs.pop('stream', None)

        # Try primary backend first
        try:
            logger.info(f"Attempting primary backend: {self.primary_url}")
            response = await self.primary_client.chat.completions.create(
                messages=messages,
                model=model,
                stream=stream,
                **kwargs,
            )
            logger.info(f"Primary backend succeeded")
            return response

        except Exception as e:
            error_msg = str(e)
            logger.warning(f"Primary backend failed: {error_msg}")

            # Check if it's a connection error (should failover)
            # or an application error (should not failover)
            if self._should_failover(error_msg):
                if self.fallback_client:
                    try:
                        logger.info(f"Attempting fallback backend: {self.fallback_url}")
                        response = await self.fallback_client.chat.completions.create(
                            messages=messages,
                            model=model,
                            stream=stream,
                            **kwargs,
                        )
                        logger.info(f"Fallback backend succeeded")
                        return response
                    except Exception as fallback_error:
                        logger.error(f"Fallback backend failed: {str(fallback_error)}")
                        raise OpenAIBackendError(f"All backends failed. Last error: {str(fallback_error)}")
                else:
                    logger.warning("No fallback backend configured")
                    raise OpenAIBackendError(f"Primary backend failed: {error_msg}")
            else:
                # Application error (4xx/5xx) - don't failover
                raise OpenAIBackendError(f"Backend error: {error_msg}")

    def _should_failover(self, error_message: str) -> bool:
        """
        Determine if an error should trigger failover.

        Only connection errors should trigger failover, not application errors.
        This prevents cascading bad requests across all backends.

        Args:
            error_message: Error message string

        Returns:
            True if error should trigger failover
        """
        # Connection errors - should failover
        connection_errors = [
            "connect",
            "timeout",
            "connection refused",
            "connection reset",
            "host unreachable",
            "network unreachable",
            "all connection attempts failed",
        ]

        error_lower = error_message.lower()
        return any(err in error_lower for err in connection_errors)

    async def close(self):
        """Close all client connections."""
        await self.primary_client.close()
        if self.fallback_client:
            await self.fallback_client.close()


def create_openai_client(config) -> OpenAIClientWrapper:
    """
    Create OpenAI client wrapper from gateway configuration.

    Args:
        config: GatewayConfig instance

    Returns:
        OpenAIClientWrapper instance
    """
    # Get primary backend credentials
    primary_api_key = None
    if config.backend_type == "lm-studio":
        primary_api_key = config.get_lm_studio_api_key()
    elif config.backend_type == "zai":
        primary_api_key = config.get_zai_api_key()

    # Get fallback backend credentials
    fallback_url = None
    fallback_api_key = None
    fallback_urls = config.get_backend_fallback_urls()
    if fallback_urls:
        fallback_url = fallback_urls[0]
        fallback_api_key = config.get_zai_api_key()

    return OpenAIClientWrapper(
        primary_url=config.backend_url,
        primary_api_key=primary_api_key,
        fallback_url=fallback_url,
        fallback_api_key=fallback_api_key,
    )
