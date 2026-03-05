"""
Intelligent Router for AI Inference Gateway.

Routes requests to appropriate models based on:
- Token count estimation
- Task type detection (coding, agentic, general, fast, large_context)
- Latency tracking and overload detection
- Model specialization matching
- Cost tier considerations
"""

import logging
import re
import asyncio
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple
from enum import Enum

logger = logging.getLogger(__name__)


class TaskSpecialization(Enum):
    """Task specialization types for intelligent routing."""
    CODING = "coding"
    AGENTIC = "agentic"
    GENERAL = "general"
    FAST = "fast"
    LARGE_CONTEXT = "large_context"


@dataclass
class ModelInfo:
    """Information about an available model."""
    id: str
    name: str
    context_length: int = 262144  # Qwen3.5 supports 256K!
    priority: int = 0
    specializations: List[TaskSpecialization] = field(default_factory=list)
    cost_tier: int = 1
    estimated_tokens_per_second: float = 50.0
    backend: str = "lm-studio"  # lm-studio or zai


@dataclass
class ModelCandidate:
    """Candidate model for reranking."""
    model: str
    backend: str
    score: float
    reason: str
    specialization: TaskSpecialization
    expected_latency_ms: float


@dataclass
class RouteDecision:
    """Routing decision with metadata."""
    model: str
    confidence: float
    reason: str
    estimated_tokens: int
    backend: str
    specialization: Optional[TaskSpecialization] = None
    expected_latency_ms: Optional[float] = None


class LatencyTracker:
    """Track model response times for latency-aware routing."""

    def __init__(self, window_size: int = 100):
        self.window_size = window_size
        self.latencies: Dict[str, List[float]] = {}
        self._lock = asyncio.Lock()

    async def record_latency(self, model: str, latency_ms: float):
        """Record a latency measurement."""
        async with self._lock:
            if model not in self.latencies:
                self.latencies[model] = []
            self.latencies[model].append(latency_ms)
            if len(self.latencies[model]) > self.window_size:
                self.latencies[model] = self.latencies[model][-self.window_size:]

    async def get_avg_latency(self, model: str) -> Optional[float]:
        """Get average latency for a model."""
        async with self._lock:
            if model not in self.latencies or not self.latencies[model]:
                return None
            return sum(self.latencies[model]) / len(self.latencies[model])

    async def is_overloaded(self, model: str, threshold_ms: float = 5000.0) -> bool:
        """Check if a model is overloaded based on recent latencies."""
        avg = await self.get_avg_latency(model)
        return avg is not None and avg > threshold_ms


class Router:
    """
    Intelligent router for model selection.

    Analyzes requests and routes to appropriate models based on
    token count, task type, and current model performance.
    """

    def __init__(
        self,
        models: List[ModelInfo],
        latency_tracker: Optional[LatencyTracker] = None,
    ):
        """
        Initialize router.

        Args:
            models: List of available models
            latency_tracker: Optional latency tracker for performance-based routing
        """
        self.models = {model.id: model for model in models}
        self.latency_tracker = latency_tracker or LatencyTracker()
        self.claude_model_mapping = self._build_claude_mapping()
        # Active request tracking for smart load balancing
        self.active_requests: Dict[str, Dict] = {}  # request_id -> {model, backend, stream, start_time}
        self.max_concurrent_streams = 1  # LM Studio can handle 1 stream at a time

    async def get_backend_load(self, backend: str) -> Dict:
        """
        Get current load on a backend.

        Args:
            backend: Backend name (lm-studio or zai)

        Returns:
            Dict with load information
        """
        active = sum(1 for r in self.active_requests.values() if r.get("backend") == backend)
        is_streaming = any(r.get("stream") for r in self.active_requests.values() if r.get("backend") == backend)
        return {
            "backend": backend,
            "active_requests": active,
            "is_streaming": is_streaming,
            "at_capacity": active >= self.max_concurrent_streams
        }

    def track_request_start(self, request_id: str, model: str, backend: str, stream: bool):
        """Track the start of a request."""
        import time
        self.active_requests[request_id] = {
            "model": model,
            "backend": backend,
            "stream": stream,
            "start_time": time.time()
        }
        logger.debug(f"Tracking request {request_id}: model={model}, backend={backend}, stream={stream}")

    def track_request_end(self, request_id: str):
        """Track the end of a request."""
        if request_id in self.active_requests:
            del self.active_requests[request_id]
            logger.debug(f"Stopped tracking request {request_id}")

    def _build_claude_mapping(self) -> Dict[str, str]:
        """Build mapping from Anthropic Claude model names to available models."""
        return {
            "claude-sonnet-4-20250514": "magnum-opus-35b-a3b-i1",
            "claude-opus-4-20250514": "magnum-opus-35b-a3b-i1",
            "claude-sonnet-4": "glm-5",
            "claude-sonnet-4-20250514-simplified": "glm-4.7",
            "claude-haiku-4-20250514": "glm-4-flash",
        }

    def estimate_tokens(self, messages: List[Dict]) -> int:
        """
        Estimate token count for messages.

        Args:
            messages: List of message dicts with 'content' field

        Returns:
            Estimated token count
        """
        CHARS_PER_TOKEN = 4
        CHARS_PER_TOKEN_CODE = 6

        total_chars = 0
        has_code = False

        for msg in messages:
            content = msg.get("content", "")
            if isinstance(content, str):
                total_chars += len(content)
                # Detect code blocks
                if "```" in content or "def " in content or "function " in content:
                    has_code = True

        divisor = CHARS_PER_TOKEN_CODE if has_code else CHARS_PER_TOKEN
        return max(1, total_chars // divisor)

    def detect_specialization(self, messages: List[Dict]) -> TaskSpecialization:
        """
        Detect task type from messages.

        Args:
            messages: List of message dicts

        Returns:
            Detected task specialization
        """
        # Combine all message content
        text = " ".join(
            msg.get("content", "") for msg in messages if isinstance(msg.get("content", ""), str)
        ).lower()

        # Check for code/programming
        code_patterns = [
            r"```\w*", r"def\s+\w+", r"function\s+\w+",
            r"class\s+\w+", r"import\s+\w+", r"from\s+\w+\s+import",
            r"λ\s*->", r"=>\s*{", r"@\[|for\s+\w+\s+in"
        ]
        if any(re.search(pattern, text) for pattern in code_patterns):
            return TaskSpecialization.CODING

        # Check for agentic/multi-step tasks
        agentic_keywords = ["agent", "workflow", "multi-step", "step by step", "plan", "analyze then"]
        if any(keyword in text for keyword in agentic_keywords):
            return TaskSpecialization.AGENTIC

        # Check for urgency/fast mode
        fast_keywords = ["quickly", "asap", "fast", "brief", "short", "quick"]
        if any(keyword in text for keyword in fast_keywords):
            return TaskSpecialization.FAST

        # Check for large context needs
        if len(text) > 10000:  # Large input
            return TaskSpecialization.LARGE_CONTEXT

        return TaskSpecialization.GENERAL

    async def route(
        self,
        messages: List[Dict],
        requested_model: Optional[str] = None,
        urgency: str = "normal",
    ) -> RouteDecision:
        """
        Route a request to the best model.

        Args:
            messages: List of messages
            requested_model: Optional model requested by client
            urgency: Urgency level (fast, normal, quality)

        Returns:
            Routing decision with model and metadata
        """
        # Check if LM Studio is busy with streaming requests
        lm_studio_load = await self.get_backend_load("lm-studio")

        # If LM Studio is at capacity (processing streams), route to ZAI
        if lm_studio_load["at_capacity"] and lm_studio_load["is_streaming"]:
            logger.info(
                f"LM Studio busy ({lm_studio_load['active_requests']} active requests, "
                f"streaming: {lm_studio_load['is_streaming']}), auto-offloading to ZAI"
            )
            # Find best ZAI model for the request
            estimated_tokens = self.estimate_tokens(messages)

            # If client requested a specific model, check if we can map it to ZAI
            if requested_model:
                # Check if it's a Claude model that maps to ZAI
                if requested_model in self.claude_model_mapping:
                    mapped_model = self.claude_model_mapping[requested_model]
                    model_info = self.models.get(mapped_model)
                    if model_info and model_info.backend == "zai":
                        return RouteDecision(
                            model=mapped_model,
                            confidence=1.0,
                            reason=f"LM Studio at capacity, using ZAI fallback for {requested_model}",
                            estimated_tokens=estimated_tokens,
                            backend="zai",
                            expected_latency_ms=model_info.estimated_tokens_per_second * estimated_tokens / 1000,
                        )

            # Otherwise, find best ZAI model based on specialization
            zai_models = [m for m in self.models.values() if m.backend == "zai"]
            if zai_models:
                # Sort by priority and pick the best one
                best_zai = max(zai_models, key=lambda m: m.priority)
                specialization = self.detect_specialization(messages)
                return RouteDecision(
                    model=best_zai.id,
                    confidence=0.9,
                    reason=f"LM Studio at capacity (auto-failover to ZAI)",
                    estimated_tokens=estimated_tokens,
                    backend="zai",
                    specialization=specialization,
                    expected_latency_ms=best_zai.estimated_tokens_per_second * estimated_tokens / 1000,
                )

        # Estimate tokens
        estimated_tokens = self.estimate_tokens(messages)

        # Check if client requested a specific model
        if requested_model:
            # Check if it's a Claude model name
            if requested_model in self.claude_model_mapping:
                mapped_model = self.claude_model_mapping[requested_model]
                model_info = self.models.get(mapped_model)
                if model_info:
                    return RouteDecision(
                        model=mapped_model,
                        confidence=1.0,
                        reason=f"Claude model mapped to {mapped_model}",
                        estimated_tokens=estimated_tokens,
                        backend=model_info.backend,
                        expected_latency_ms=model_info.estimated_tokens_per_second * estimated_tokens / 1000,
                    )
            # Check if it's a direct model ID
            elif requested_model in self.models:
                model_info = self.models[requested_model]
                return RouteDecision(
                    model=requested_model,
                    confidence=1.0,
                    reason=f"Requested model {requested_model}",
                    estimated_tokens=estimated_tokens,
                    backend=model_info.backend,
                    expected_latency_ms=model_info.estimated_tokens_per_second * estimated_tokens / 1000,
                )

        # Detect task specialization
        specialization = self.detect_specialization(messages)

        # Generate candidates
        candidates = await self._generate_candidates(
            estimated_tokens=estimated_tokens,
            specialization=specialization,
            urgency=urgency,
        )

        # Rank candidates
        ranked_candidates = await self._rank_candidates(
            candidates=candidates,
            specialization=specialization,
            urgency=urgency,
        )

        if not ranked_candidates:
            # Fallback to default model
            default_model = "magnum-opus-35b-a3b-i1"
            model_info = self.models[default_model]
            return RouteDecision(
                model=default_model,
                confidence=0.5,
                reason="No suitable candidates, using default",
                estimated_tokens=estimated_tokens,
                backend=model_info.backend,
            )

        # Select best candidate
        best = ranked_candidates[0]
        return RouteDecision(
            model=best.model,
            confidence=best.score,
            reason=best.reason,
            estimated_tokens=estimated_tokens,
            backend=best.backend,
            specialization=best.specialization,
            expected_latency_ms=best.expected_latency_ms,
        )

    async def _generate_candidates(
        self,
        estimated_tokens: int,
        specialization: TaskSpecialization,
        urgency: str,
    ) -> List[ModelCandidate]:
        """Generate candidate models for the request."""
        candidates = []

        for model_id, model_info in self.models.items():
            # Filter by context length
            if estimated_tokens > model_info.context_length:
                continue

            # Check if model is overloaded
            if await self.latency_tracker.is_overloaded(model_id):
                logger.warning(f"Model {model_id} is overloaded, skipping")
                continue

            # Base score from priority
            score = float(model_info.priority)

            # Boost for specialization match
            if specialization in model_info.specializations:
                score += 1.5

            # Estimate latency
            expected_latency_ms = (estimated_tokens / model_info.estimated_tokens_per_second) * 1000

            candidates.append(
                ModelCandidate(
                    model=model_id,
                    backend=model_info.backend,
                    score=score,
                    reason=f"Priority {model_info.priority}, specialization {specialization.value if specialization in model_info.specializations else 'none'}",
                    specialization=specialization,
                    expected_latency_ms=expected_latency_ms,
                )
            )

        return candidates

    async def _rank_candidates(
        self,
        candidates: List[ModelCandidate],
        specialization: TaskSpecialization,
        urgency: str,
    ) -> List[ModelCandidate]:
        """Rank candidates by multiple factors."""
        for candidate in candidates:
            # Apply specialization boost
            model_info = self.models[candidate.model]
            if specialization in model_info.specializations:
                candidate.score *= 1.5

            # Adjust for latency
            avg_latency = await self.latency_tracker.get_avg_latency(candidate.model)
            if avg_latency:
                if avg_latency > 3000:  # > 3s
                    candidate.score *= 0.5
                elif avg_latency > 1000:  # > 1s
                    candidate.score *= 0.7

            # Urgency adjustment
            if urgency == "fast":
                # Prefer faster models
                candidate.score /= (candidate.expected_latency_ms / 1000)
            elif urgency == "quality":
                # Prefer higher cost tier (better quality)
                candidate.score *= (1 + model_info.cost_tier * 0.1)

        # Sort by score descending
        return sorted(candidates, key=lambda c: c.score, reverse=True)


def create_default_router() -> Router:
    """Create router with default model configuration."""
    models = [
        # LM Studio models
        ModelInfo(
            id="qwen/qwen3.5-9b",
            name="Qwen 3.5 9B",
            context_length=262144,  # 256K
            priority=8,
            specializations=[TaskSpecialization.GENERAL, TaskSpecialization.FAST],
            cost_tier=1,
            estimated_tokens_per_second=60.0,
            backend="lm-studio",
        ),
        ModelInfo(
            id="qwen3.5-35b-a3b",
            name="Qwen 3.5 35B A3B",
            context_length=262144,  # 256K
            priority=9,
            specializations=[TaskSpecialization.GENERAL, TaskSpecialization.AGENTIC],
            cost_tier=2,
            estimated_tokens_per_second=40.0,
            backend="lm-studio",
        ),
        ModelInfo(
            id="magnum-opus-35b-a3b-i1",
            name="Magnum Opus 35B A3B",
            context_length=256000,
            priority=10,
            specializations=[TaskSpecialization.LARGE_CONTEXT, TaskSpecialization.AGENTIC],
            cost_tier=3,
            estimated_tokens_per_second=30.0,
            backend="lm-studio",
        ),
        # ZAI models
        ModelInfo(
            id="glm-5",
            name="GLM-5",
            context_length=200000,
            priority=9,
            specializations=[TaskSpecialization.AGENTIC, TaskSpecialization.GENERAL],
            cost_tier=4,
            estimated_tokens_per_second=40.0,
            backend="zai",
        ),
        ModelInfo(
            id="glm-4.7",
            name="GLM-4.7",
            context_length=200000,
            priority=8,
            specializations=[TaskSpecialization.CODING, TaskSpecialization.GENERAL],
            cost_tier=3,
            estimated_tokens_per_second=50.0,
            backend="zai",
        ),
        ModelInfo(
            id="glm-4.6v",
            name="GLM-4.6v",
            context_length=200000,
            priority=7,
            specializations=[TaskSpecialization.CODING, TaskSpecialization.FAST],
            cost_tier=2,
            estimated_tokens_per_second=60.0,
            backend="zai",
        ),
        ModelInfo(
            id="glm-4.5-air",
            name="GLM-4.5 Air",
            context_length=132000,
            priority=5,
            specializations=[TaskSpecialization.FAST],
            cost_tier=1,
            estimated_tokens_per_second=80.0,
            backend="zai",
        ),
        ModelInfo(
            id="glm-4-flash",
            name="GLM-4 Flash",
            context_length=128000,
            priority=6,
            specializations=[TaskSpecialization.FAST],
            cost_tier=1,
            estimated_tokens_per_second=80.0,
            backend="zai",
        ),
    ]

    return Router(models=models)
