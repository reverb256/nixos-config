#!/usr/bin/env python3
"""
LM Studio v1 REST API Client

Comprehensive implementation of all LM Studio REST API endpoints:
- POST /api/v1/chat - Stateful chat with MCP support
- GET /api/v1/models - List loaded models
- POST /api/v1/models/load - Load model with configuration
- POST /api/v1/models/unload - Unload model by instance_id
- POST /api/v1/models/download - Download models
- GET /api/v1/models/download/status/:job_id - Download status
"""

import httpx
from typing import Optional, List, Dict, Any, Union, Literal
from pydantic import BaseModel, Field
from datetime import datetime


# ============================================================================
# REQUEST MODELS
# ============================================================================

class TextInput(BaseModel):
    """Text input for messages."""
    type: Literal["message"] = "message"
    content: str


class ImageInput(BaseModel):
    """Image input for multimodal models."""
    type: Literal["image"] = "image"
    data_url: str  # base64-encoded data URL


class IntegrationPlugin(BaseModel):
    """Plugin integration specification."""
    type: Literal["plugin"] = "plugin"
    id: str  # Plugin ID (e.g., "mcp/playwright")
    allowed_tools: Optional[List[str]] = None  # If None, all tools allowed


class EphemeralMCP(BaseModel):
    """Ephemeral MCP server specification."""
    type: Literal["ephemeral_mcp"] = "ephemeral_mcp"
    server_label: str
    server_url: str
    allowed_tools: Optional[List[str]] = None
    headers: Optional[Dict[str, str]] = None


Integration = Union[str, IntegrationPlugin, EphemeralMCP]


class ChatRequest(BaseModel):
    """Request for /api/v1/chat endpoint."""
    model: str
    input: Union[str, List[Union[TextInput, ImageInput]]]
    system_prompt: Optional[str] = None
    integrations: Optional[List[Integration]] = None
    stream: Optional[bool] = False
    temperature: Optional[float] = None
    top_p: Optional[float] = None
    top_k: Optional[int] = None
    min_p: Optional[float] = None
    repeat_penalty: Optional[float] = None
    max_output_tokens: Optional[int] = None
    reasoning: Optional[Literal["off", "low", "medium", "high", "on"]] = None
    context_length: Optional[int] = None  # Dynamic context window!
    store: Optional[bool] = True
    previous_response_id: Optional[str] = None


# ============================================================================
# RESPONSE MODELS
# ============================================================================

class ProviderInfo(BaseModel):
    """Tool provider information."""
    type: Literal["plugin", "ephemeral_mcp"]
    plugin_id: Optional[str] = None
    server_label: Optional[str] = None


class ToolCall(BaseModel):
    """A tool call made by the model."""
    type: Literal["tool_call"] = "tool_call"
    tool: str
    arguments: Dict[str, Any]
    output: str
    provider_info: ProviderInfo


class MessageOutput(BaseModel):
    """A text message from the model."""
    type: Literal["message"] = "message"
    content: str


class ReasoningOutput(BaseModel):
    """Reasoning content from the model."""
    type: Literal["reasoning"] = "reasoning"
    content: str


class InvalidToolCall(BaseModel):
    """An invalid tool call made by the model."""
    type: Literal["invalid_tool_call"] = "invalid_tool_call"
    reason: str
    metadata: Dict[str, Any]
    tool_name: str
    arguments: Optional[Dict[str, Any]] = None
    provider_info: Optional[ProviderInfo] = None


OutputItem = Union[ToolCall, MessageOutput, ReasoningOutput, InvalidToolCall]


class ChatStats(BaseModel):
    """Token usage and performance metrics."""
    input_tokens: float
    total_output_tokens: float
    reasoning_output_tokens: float = 0
    tokens_per_second: float
    time_to_first_token_seconds: float
    model_load_time_seconds: Optional[float] = None


class ChatResponse(BaseModel):
    """Response from /api/v1/chat endpoint."""
    model_instance_id: str
    output: List[OutputItem]
    stats: ChatStats
    response_id: Optional[str] = None  # Present when store=True


# ============================================================================
# MODELS ENDPOINT
# ============================================================================

class ModelInfo(BaseModel):
    """Information about a loaded model."""
    id: str
    instance_id: str
    loaded_at: datetime
    # Additional fields may be present


class ModelsResponse(BaseModel):
    """Response from GET /api/v1/models."""
    models: List[ModelInfo]


# ============================================================================
# LOAD MODEL
# ============================================================================

class LoadModelRequest(BaseModel):
    """Request for POST /api/v1/models/load."""
    model: str
    # Configuration options vary by backend
    # For llama.cpp/GGUF:
    quantization: Optional[str] = None  # e.g., "Q4_K_M"
    context_length: Optional[int] = None  # Context window size
    gpu_split: Optional[str] = None  # "auto", "gpu_0", "gpu_1", etc.
    num_threads: Optional[int] = None
    # Additional backend-specific options
    options: Optional[Dict[str, Any]] = None


class LoadModelResponse(BaseModel):
    """Response from POST /api/v1/models/load."""
    instance_id: str
    model: str
    loaded_at: datetime


# ============================================================================
# UNLOAD MODEL
# ============================================================================

class UnloadModelRequest(BaseModel):
    """Request for POST /api/v1/models/unload."""
    instance_id: str


class UnloadModelResponse(BaseModel):
    """Response from POST /api/v1/models/unload."""
    instance_id: str


# ============================================================================
# DOWNLOAD MODEL
# ============================================================================

DownloadStatus = Literal["downloading", "paused", "completed", "failed", "already_downloaded"]


class DownloadResponse(BaseModel):
    """Response from POST /api/v1/models/download."""
    job_id: Optional[str] = None  # Absent when status is "already_downloaded"
    status: DownloadStatus
    completed_at: Optional[datetime] = None
    total_size_bytes: Optional[int] = None  # Absent when status is "already_downloaded"
    started_at: Optional[datetime] = None  # Absent when status is "already_downloaded"


class DownloadStatusResponse(BaseModel):
    """Response from GET /api/v1/models/download/status/:job_id."""
    job_id: str
    status: DownloadStatus
    bytes_per_second: Optional[float] = None  # Present when status is "downloading"
    estimated_completion: Optional[datetime] = None  # Present when status is "downloading"
    completed_at: Optional[datetime] = None
    total_size_bytes: Optional[int] = None
    downloaded_bytes: Optional[int] = None
    started_at: Optional[datetime] = None


# ============================================================================
# CLIENT
# ============================================================================

class LMStudioClient:
    """
    Comprehensive LM Studio v1 REST API client.

    Usage:
        client = LMStudioClient(
            base_url="http://localhost:1234",
            api_token="your-token-here"
        )

        # Chat with MCP integration
        response = await client.chat(
            model="ibm/granite-4-micro",
            input="Search for trending models",
            integrations=[{
                "type": "ephemeral_mcp",
                "server_label": "huggingface",
                "server_url": "https://huggingface.co/mcp",
                "allowed_tools": ["model_search"]
            }],
            context_length=8000
        )

        # List loaded models
        models = await client.list_models()

        # Load model with configuration
        await client.load_model(
            model="qwen3.5-35b-a3b",
            context_length=262144,  # 256K context!
            gpu_split="gpu_1"
        )

        # Unload model
        await client.unload_model(instance_id="qwen3.5-35b-a3b")
    """

    def __init__(
        self,
        base_url: str = "http://localhost:1234",
        api_token: Optional[str] = None,
        timeout: float = 120.0
    ):
        self.base_url = base_url.rstrip("/")
        self.api_token = api_token
        self.timeout = timeout

    def _get_headers(self) -> Dict[str, str]:
        """Get request headers with authentication."""
        headers = {"Content-Type": "application/json"}
        if self.api_token:
            headers["Authorization"] = f"Bearer {self.api_token}"
        return headers

    async def chat(
        self,
        model: str,
        input: Union[str, List[Union[TextInput, ImageInput]]],
        system_prompt: Optional[str] = None,
        integrations: Optional[List[Integration]] = None,
        stream: bool = False,
        temperature: Optional[float] = None,
        top_p: Optional[float] = None,
        top_k: Optional[int] = None,
        min_p: Optional[float] = None,
        repeat_penalty: Optional[float] = None,
        max_output_tokens: Optional[int] = None,
        reasoning: Optional[Literal["off", "low", "medium", "high", "on"]] = None,
        context_length: Optional[int] = None,
        store: bool = True,
        previous_response_id: Optional[str] = None,
    ) -> ChatResponse:
        """
        Send a message to a model with MCP integration support.

        Args:
            model: Model identifier
            input: Text or list of input items (text/images)
            system_prompt: Optional system message
            integrations: MCP plugins or ephemeral servers
            stream: Enable SSE streaming
            temperature: Randomness [0-1]
            top_p: Minimum cumulative probability [0-1]
            top_k: Limit to top-k tokens
            min_p: Minimum base probability [0-1]
            repeat_penalty: Penalty for repetition (1 = no penalty)
            max_output_tokens: Maximum tokens to generate
            reasoning: Reasoning mode (off/low/medium/high/on)
            context_length: Dynamic context window size
            store: Store chat for continuation
            previous_response_id: Continue from previous response

        Returns:
            ChatResponse with output, stats, and response_id
        """
        request = ChatRequest(
            model=model,
            input=input,
            system_prompt=system_prompt,
            integrations=integrations,
            stream=stream,
            temperature=temperature,
            top_p=top_p,
            top_k=top_k,
            min_p=min_p,
            repeat_penalty=repeat_penalty,
            max_output_tokens=max_output_tokens,
            reasoning=reasoning,
            context_length=context_length,
            store=store,
            previous_response_id=previous_response_id,
        )

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/api/v1/chat",
                headers=self._get_headers(),
                content=request.model_dump_json(exclude_none=True),
            )
            response.raise_for_status()
            return ChatResponse.model_validate_json(response.content)

    async def list_models(self) -> ModelsResponse:
        """List all loaded models."""
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/api/v1/models",
                headers=self._get_headers(),
            )
            response.raise_for_status()
            return ModelsResponse.model_validate_json(response.content)

    async def load_model(
        self,
        model: str,
        quantization: Optional[str] = None,
        context_length: Optional[int] = None,
        gpu_split: Optional[str] = None,
        num_threads: Optional[int] = None,
        options: Optional[Dict[str, Any]] = None,
    ) -> LoadModelResponse:
        """
        Load a model with configuration.

        Args:
            model: Model identifier
            quantization: Quantization level (e.g., "Q4_K_M")
            context_length: Context window size (e.g., 262144 for 256K)
            gpu_split: GPU allocation ("auto", "gpu_0", "gpu_1", etc.)
            num_threads: Number of CPU threads
            options: Additional backend-specific options

        Returns:
            LoadModelResponse with instance_id
        """
        request = LoadModelRequest(
            model=model,
            quantization=quantization,
            context_length=context_length,
            gpu_split=gpu_split,
            num_threads=num_threads,
            options=options,
        )

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/api/v1/models/load",
                headers=self._get_headers(),
                content=request.model_dump_json(exclude_none=True),
            )
            response.raise_for_status()
            return LoadModelResponse.model_validate_json(response.content)

    async def unload_model(self, instance_id: str) -> UnloadModelResponse:
        """
        Unload a model from memory.

        Args:
            instance_id: Model instance identifier

        Returns:
            UnloadModelResponse
        """
        request = UnloadModelRequest(instance_id=instance_id)

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/api/v1/models/unload",
                headers=self._get_headers(),
                content=request.model_dump_json(),
            )
            response.raise_for_status()
            return UnloadModelResponse.model_validate_json(response.content)

    async def download_model(
        self,
        model: str,
        quantization: Optional[str] = None,
    ) -> DownloadResponse:
        """
        Download a model from catalog or Hugging Face.

        Args:
            model: Model catalog ID or Hugging Face URL
            quantization: Quantization for Hugging Face links

        Returns:
            DownloadResponse with job_id for tracking
        """
        payload = {"model": model}
        if quantization:
            payload["quantization"] = quantization

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/api/v1/models/download",
                headers=self._get_headers(),
                json=payload,
            )
            response.raise_for_status()
            return DownloadResponse.model_validate_json(response.content)

    async def get_download_status(self, job_id: str) -> DownloadStatusResponse:
        """
        Get download status for a job.

        Args:
            job_id: Download job identifier

        Returns:
            DownloadStatusResponse with progress
        """
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.get(
                f"{self.base_url}/api/v1/models/download/status/{job_id}",
                headers=self._get_headers(),
            )
            response.raise_for_status()
            return DownloadStatusResponse.model_validate_json(response.content)

    async def chat_with_mcp(
        self,
        model: str,
        message: str,
        mcp_servers: List[Dict[str, Any]],
        context_length: int = 8000,
        **kwargs
    ) -> ChatResponse:
        """
        Convenience method for chat with MCP integration.

        Args:
            model: Model identifier
            message: User message
            mcp_servers: List of MCP server configurations
            context_length: Recommended context length for MCP usage
            **kwargs: Additional chat parameters

        Returns:
            ChatResponse
        """
        integrations = []
        for server in mcp_servers:
            if "url" in server:
                integrations.append(EphemeralMCP(
                    server_label=server.get("label", "mcp"),
                    server_url=server["url"],
                    allowed_tools=server.get("allowed_tools"),
                    headers=server.get("headers"),
                ))
            elif "plugin_id" in server:
                integrations.append(IntegrationPlugin(
                    id=server["plugin_id"],
                    allowed_tools=server.get("allowed_tools"),
                ))

        return await self.chat(
            model=model,
            input=message,
            integrations=integrations,
            context_length=context_length,
            **kwargs
        )


# ============================================================================
# SYNC CLIENT WRAPPER
# ============================================================================

class LMStudioClientSync:
    """Synchronous wrapper for LMStudioClient."""

    def __init__(self, base_url: str = "http://localhost:1234", api_token: Optional[str] = None):
        self.async_client = LMStudioClient(base_url=base_url, api_token=api_token)

    def chat(self, *args, **kwargs) -> ChatResponse:
        import asyncio
        return asyncio.run(self.async_client.chat(*args, **kwargs))

    def list_models(self) -> ModelsResponse:
        import asyncio
        return asyncio.run(self.async_client.list_models())

    def load_model(self, *args, **kwargs) -> LoadModelResponse:
        import asyncio
        return asyncio.run(self.async_client.load_model(*args, **kwargs))

    def unload_model(self, *args, **kwargs) -> UnloadModelResponse:
        import asyncio
        return asyncio.run(self.async_client.unload_model(*args, **kwargs))

    def download_model(self, *args, **kwargs) -> DownloadResponse:
        import asyncio
        return asyncio.run(self.async_client.download_model(*args, **kwargs))

    def get_download_status(self, *args, **kwargs) -> DownloadStatusResponse:
        import asyncio
        return asyncio.run(self.async_client.get_download_status(*args, **kwargs))
