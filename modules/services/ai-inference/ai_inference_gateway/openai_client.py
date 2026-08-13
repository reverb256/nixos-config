"""OpenAI-compatible client wrapper for configured inference backends."""

import logging
import os
from pathlib import Path
from typing import Any, Dict, Optional

from openai import AsyncOpenAI, AsyncStream
from openai.types.chat import ChatCompletion, ChatCompletionChunk

logger = logging.getLogger(__name__)


class OpenAIBackendError(Exception):
    """Exception raised when all configured backend requests fail."""


def _normalise_base_url(url: str) -> str:
    """Return an OpenAI SDK base URL with one ``/v1`` suffix."""
    value = url.rstrip("/")
    return value if value.endswith("/v1") else f"{value}/v1"


def _read_api_key_from_environment() -> Optional[str]:
    """Read a fallback API key without placing its value in generated config."""
    for name in ("NVIDIA_NIM_API_KEY", "NVIDIA_API_KEY"):
        value = os.environ.get(name, "").strip()
        if value:
            return value

    for name in ("NVIDIA_NIM_API_KEY_FILE", "NVIDIA_API_KEY_FILE"):
        path = os.environ.get(name, "").strip()
        if path:
            try:
                value = Path(path).read_text().strip()
            except OSError:
                continue
            if value:
                return value

    return None


class OpenAIClientWrapper:
    """Provide one primary client and optional configured fallback clients."""

    def __init__(
        self,
        primary_url: str,
        primary_api_key: Optional[str],
        fallback_url: Optional[str] = None,
        fallback_api_key: Optional[str] = None,
        fallback_urls: Optional[list[str]] = None,
        fallback_model: Optional[str] = None,
        timeout: float = 60.0,
        **_ignored: Any,
    ):
        urls = [url for url in (fallback_urls or []) if url]
        if fallback_url:
            urls.insert(0, fallback_url)

        self.primary_url = primary_url.rstrip("/")
        self.primary_api_key = primary_api_key.strip() if primary_api_key else "not-needed"
        self.primary_client = AsyncOpenAI(
            base_url=_normalise_base_url(self.primary_url),
            api_key=self.primary_api_key,
            timeout=timeout,
        )

        api_key = fallback_api_key or _read_api_key_from_environment()
        self.fallback_model = fallback_model or os.environ.get("NIM_FALLBACK_MODEL", "").strip()
        self.fallback_clients = [
            AsyncOpenAI(
                base_url=_normalise_base_url(url),
                api_key=api_key or "not-needed",
                timeout=timeout,
            )
            for url in dict.fromkeys(urls)
        ]

    def _clients_for_backend(self, backend: Optional[str], model: str):
        """Select client/model pairs without guessing incompatible model IDs."""
        nvidia_route = backend and backend.lower() in {"nvidia", "nvidia-nim", "nim"}
        if nvidia_route:
            return [
                *((client, model) for client in self.fallback_clients),
                (self.primary_client, model),
            ]

        attempts = [(self.primary_client, model)]
        if self.fallback_model:
            attempts.extend(
                (client, self.fallback_model) for client in self.fallback_clients
            )
        return attempts

    async def chat_completion(
        self,
        messages: list[Dict[str, Any]],
        model: str,
        stream: bool = False,
        backend: Optional[str] = None,
        **kwargs: Any,
    ) -> ChatCompletion | AsyncStream[ChatCompletionChunk]:
        """Create a completion and try configured fallbacks after backend errors."""
        kwargs.pop("stream", None)
        for param in (
            "top_k",
            "repeat_penalty",
            "thinking",
            "thinking_enabled",
            "supports_thinking_toggle",
            "backend",
        ):
            kwargs.pop(param, None)

        errors = []
        for client, attempt_model in self._clients_for_backend(backend, model):
            try:
                return await client.chat.completions.create(
                    messages=messages,
                    model=attempt_model,
                    stream=stream,
                    **kwargs,
                )
            except Exception as error:
                errors.append(str(error))
                logger.warning("Inference backend request failed: %s", error)

        detail = "; ".join(errors[-3:]) or "no configured backend"
        raise OpenAIBackendError(f"All inference backends failed: {detail}")

    async def stream_chat_completion(
        self,
        messages: list[Dict[str, Any]],
        model: str,
        backend: Optional[str] = None,
        **kwargs: Any,
    ) -> AsyncStream[ChatCompletionChunk]:
        """Compatibility method for callers that explicitly request a stream."""
        return await self.chat_completion(
            messages=messages,
            model=model,
            stream=True,
            backend=backend,
            **kwargs,
        )

    async def close(self) -> None:
        """Close all backend client connections."""
        clients = [self.primary_client, *self.fallback_clients]
        for client in clients:
            await client.close()


def create_openai_client(config) -> OpenAIClientWrapper:
    """Create a client from the gateway configuration."""
    primary_api_key = None
    if config.backend_type == "pollinations":
        primary_api_key = config.get_pollinations_api_key()

    return OpenAIClientWrapper(
        primary_url=config.backend_url,
        primary_api_key=primary_api_key,
        fallback_urls=config.get_backend_fallback_urls(),
        fallback_model=os.environ.get("NIM_FALLBACK_MODEL"),
    )
