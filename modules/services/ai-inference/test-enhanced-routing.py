#!/usr/bin/env python3
"""
Test script for enhanced routing features.
This demonstrates the new model specialization, latency-aware routing, and reranking.
"""

import asyncio
from dataclasses import dataclass
from typing import Dict, List, Any, Optional
from enum import Enum


class TaskSpecialization(Enum):
    """Task specialization types for intelligent routing."""

    CODING = "coding"
    AGENTIC = "agentic"
    GENERAL = "general"
    FAST = "fast"
    LARGE_CONTEXT = "large_context"


@dataclass
class ModelInfo:
    id: str
    name: str
    context_length: int = 32768
    priority: int = 0
    specializations: List[TaskSpecialization] = None
    cost_tier: int = 1
    estimated_tokens_per_second: float = 50.0

    def __post_init__(self):
        if self.specializations is None:
            self.specializations = []


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
                self.latencies[model] = self.latencies[model][-self.window_size :]

    async def get_avg_latency(self, model: str) -> Optional[float]:
        """Get average latency for a model."""
        async with self._lock:
            if model not in self.latencies or not self.latencies[model]:
                return None
            return sum(self.latencies[model]) / len(self.latencies[model])

    async def is_model_overloaded(
        self, model: str, threshold_ms: float = 5000.0
    ) -> bool:
        """Check if a model is experiencing high latency."""
        avg = await self.get_avg_latency(model)
        return avg is not None and avg > threshold_ms


class Reranker:
    """Rank multiple model candidates and select the best."""

    def __init__(self, latency_tracker: LatencyTracker):
        self.latency_tracker = latency_tracker

    async def rank_candidates(
        self,
        candidates: List[ModelCandidate],
        task_type: TaskSpecialization,
        urgency: str = "normal",
    ) -> List[ModelCandidate]:
        """Rank candidates based on multiple factors."""
        scored = []

        for candidate in candidates:
            score = candidate.score

            # Boost for specialization match
            if candidate.specialization == task_type:
                score *= 1.5

            # Adjust for urgency
            if urgency == "fast":
                # Penalize high latency
                avg_latency = await self.latency_tracker.get_avg_latency(
                    candidate.model
                )
                if avg_latency:
                    if avg_latency > 3000:
                        score *= 0.5
                    elif avg_latency > 1000:
                        score *= 0.7
            elif urgency == "quality":
                # Boost high-tier models
                if candidate.specialization in [
                    TaskSpecialization.CODING,
                    TaskSpecialization.AGENTIC,
                ]:
                    score *= 1.2

            # Small penalty for high cost when urgency is fast
            if (
                urgency == "fast"
                and candidate.specialization == TaskSpecialization.LARGE_CONTEXT
            ):
                score *= 0.9

            scored.append(
                ModelCandidate(
                    model=candidate.model,
                    backend=candidate.backend,
                    score=score,
                    reason=candidate.reason,
                    specialization=candidate.specialization,
                    expected_latency_ms=candidate.expected_latency_ms,
                )
            )

        return sorted(scored, key=lambda x: x.score, reverse=True)


class EnhancedRouter:
    """Enhanced intelligent router with model specialization, latency-aware routing, and reranking."""

    CHARS_PER_TOKEN = 4

    # Claude model mappings
    CLAUDE_MODEL_MAPPING = {
        "claude-sonnet-4-20250514": (
            "magnum-opus-35b-a3b-i1",
            "lm-studio",
            TaskSpecialization.LARGE_CONTEXT,
        ),
        "claude-opus-4-20250514": (
            "magnum-opus-35b-a3b-i1",
            "lm-studio",
            TaskSpecialization.LARGE_CONTEXT,
        ),
        "claude-sonnet-4": ("glm-5", "zai", TaskSpecialization.AGENTIC),
        "claude-sonnet-4-20250514-simplified": (
            "glm-4.7",
            "zai",
            TaskSpecialization.CODING,
        ),
        "claude-haiku-4-20250514": ("glm-4.5-air", "zai", TaskSpecialization.FAST),
    }

    def __init__(self):
        self.models: Dict[str, ModelInfo] = {}
        self._setup_available_models()

    def _setup_available_models(self):
        """Setup available models with specializations."""
        # Local LM Studio models
        self.models["magnum-opus-35b-a3b-i1"] = ModelInfo(
            id="magnum-opus-35b-a3b-i1",
            name="Magnum Opus 35B A3B",
            context_length=256000,
            priority=150,
            specializations=[
                TaskSpecialization.LARGE_CONTEXT,
                TaskSpecialization.GENERAL,
            ],
            cost_tier=2,
            estimated_tokens_per_second=60.0,
        )

        self.models["qwen3.5-35b-a3b@q4_k_m"] = ModelInfo(
            id="qwen3.5-35b-a3b@q4_k_m",
            name="Qwen3.5 35B A3B",
            context_length=256000,
            priority=100,
            specializations=[TaskSpecialization.GENERAL],
            cost_tier=2,
            estimated_tokens_per_second=50.0,
        )

        # ZAI models (simulated)
        self.models["glm-5"] = ModelInfo(
            id="glm-5",
            name="GLM-5",
            context_length=200000,
            priority=120,
            specializations=[TaskSpecialization.AGENTIC],
            cost_tier=5,
            estimated_tokens_per_second=40.0,
        )

        self.models["glm-4.7"] = ModelInfo(
            id="glm-4.7",
            name="GLM-4.7",
            context_length=200000,
            priority=110,
            specializations=[TaskSpecialization.CODING],
            cost_tier=3,
            estimated_tokens_per_second=50.0,
        )

        self.models["glm-4.5-air"] = ModelInfo(
            id="glm-4.5-air",
            name="GLM-4.5 Air",
            context_length=128000,
            priority=80,
            specializations=[TaskSpecialization.FAST],
            cost_tier=1,
            estimated_tokens_per_second=100.0,
        )

    def estimate_tokens(self, text: str) -> int:
        """Estimate token count for text."""
        return max(1, len(text) // self.CHARS_PER_TOKEN)

    def analyze_prompt(self, messages: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Enhanced prompt analysis with task type detection."""
        analysis = {
            "estimated_tokens": 0,
            "complexity": "medium",
            "has_code": False,
            "task_type": TaskSpecialization.GENERAL,
            "urgency": "normal",
        }

        all_text = " ".join([msg.get("content", "") for msg in messages])
        analysis["estimated_tokens"] = sum(
            self.estimate_tokens(msg.get("content", "")) for msg in messages
        )

        # Detect code
        code_indicators = ["```", "def ", "class ", "function", "import ", "async def"]
        analysis["has_code"] = any(
            indicator in all_text for indicator in code_indicators
        )

        # Detect agentic task patterns
        agentic_patterns = ["agent", "workflow", "multi-step", "plan", "execute"]
        is_agentic = any(pattern in all_text.lower() for pattern in agentic_patterns)

        # Detect urgency
        fast_patterns = ["quickly", "asap", "fast", "urgent", "simple"]
        quality_patterns = ["careful", "detailed", "thorough", "comprehensive"]

        if any(pattern in all_text.lower() for pattern in fast_patterns):
            analysis["urgency"] = "fast"
        elif any(pattern in all_text.lower() for pattern in quality_patterns):
            analysis["urgency"] = "quality"

        # Determine task type
        if is_agentic:
            analysis["task_type"] = TaskSpecialization.AGENTIC
        elif analysis["has_code"]:
            analysis["task_type"] = TaskSpecialization.CODING
        elif analysis["estimated_tokens"] > 200000:
            analysis["task_type"] = TaskSpecialization.LARGE_CONTEXT
        elif analysis["urgency"] == "fast":
            analysis["task_type"] = TaskSpecialization.FAST

        if analysis["estimated_tokens"] > 10000 or analysis["has_code"]:
            analysis["complexity"] = "high"
        elif analysis["estimated_tokens"] < 1000:
            analysis["complexity"] = "low"

        return analysis

    async def select_model(
        self,
        messages: List[Dict[str, Any]],
        requested_model: Optional[str] = None,
        latency_tracker: Optional[LatencyTracker] = None,
    ) -> RouteDecision:
        """Select best model for given request with enhanced routing."""
        analysis = self.analyze_prompt(messages)
        estimated_tokens = analysis["estimated_tokens"]
        task_type = analysis["task_type"]

        # Check Claude model mapping
        if requested_model and requested_model.startswith("claude-"):
            if requested_model in self.CLAUDE_MODEL_MAPPING:
                mapped_model, backend, specialization = self.CLAUDE_MODEL_MAPPING[
                    requested_model
                ]
                avg_latency = None
                if latency_tracker:
                    avg_latency = await latency_tracker.get_avg_latency(mapped_model)

                return RouteDecision(
                    model=mapped_model,
                    confidence=1.0,
                    reason=f"Claude model '{requested_model}' mapped to {mapped_model} ({specialization.value})",
                    estimated_tokens=estimated_tokens,
                    backend=backend,
                    specialization=specialization,
                    expected_latency_ms=avg_latency,
                )

        # User-specified model
        if requested_model and requested_model in self.models:
            model_info = self.models[requested_model]
            return RouteDecision(
                model=requested_model,
                confidence=1.0,
                reason=f"User specified model ({', '.join([s.value for s in model_info.specializations])})",
                estimated_tokens=estimated_tokens,
                backend=(
                    "lm-studio"
                    if "35b" in requested_model or "qwen" in requested_model
                    else "zai"
                ),
                specialization=(
                    model_info.specializations[0]
                    if model_info.specializations
                    else None
                ),
            )

        # Generate candidates
        candidates = await self._generate_candidates(
            messages, analysis, latency_tracker
        )

        if not candidates:
            return RouteDecision(
                model="magnum-opus-35b-a3b-i1",
                confidence=0.5,
                reason="No suitable candidates, using default",
                estimated_tokens=estimated_tokens,
                backend="lm-studio",
            )

        # Select best candidate
        best = candidates[0]
        return RouteDecision(
            model=best.model,
            confidence=min(1.0, best.score / 100),
            reason=best.reason,
            estimated_tokens=estimated_tokens,
            backend=best.backend,
            specialization=best.specialization,
            expected_latency_ms=best.expected_latency_ms,
        )

    async def _generate_candidates(
        self,
        messages: List[Dict[str, Any]],
        analysis: Dict[str, Any],
        latency_tracker: Optional[LatencyTracker] = None,
    ) -> List[ModelCandidate]:
        """Generate model candidates based on request analysis."""
        candidates = []
        estimated_tokens = analysis["estimated_tokens"]
        task_type = analysis["task_type"]

        for model_id, model_info in sorted(
            self.models.items(), key=lambda x: x[1].priority, reverse=True
        ):
            if estimated_tokens > model_info.context_length:
                continue

            score = float(model_info.priority)

            if task_type in model_info.specializations:
                score *= 1.5
            elif TaskSpecialization.GENERAL in model_info.specializations:
                score *= 1.1

            if (
                task_type == TaskSpecialization.LARGE_CONTEXT
                and model_info.context_length >= 256000
            ):
                score *= 2.0

            avg_latency = None
            if latency_tracker:
                avg_latency = await latency_tracker.get_avg_latency(model_id)
            expected_latency = (
                avg_latency
                if avg_latency
                else (
                    1000
                    / model_info.estimated_tokens_per_second
                    * estimated_tokens
                    / 100
                )
            )

            candidates.append(
                ModelCandidate(
                    model=model_id,
                    backend=(
                        "lm-studio"
                        if "35b" in model_id or "qwen" in model_id
                        else "zai"
                    ),
                    score=score,
                    reason=f"Model with {model_info.context_length} context, specializations: {[s.value for s in model_info.specializations]}",
                    specialization=(
                        model_info.specializations[0]
                        if model_info.specializations
                        else TaskSpecialization.GENERAL
                    ),
                    expected_latency_ms=expected_latency,
                )
            )

        return candidates


async def test_routing():
    """Test the enhanced routing system."""
    print("=" * 80)
    print("Enhanced Routing Test Suite")
    print("=" * 80)
    print()

    # Initialize components
    latency_tracker = LatencyTracker()
    reranker = Reranker(latency_tracker)
    router = EnhancedRouter()

    # Test scenarios
    test_scenarios = [
        {
            "name": "Coding Task",
            "messages": [
                {
                    "role": "user",
                    "content": "Write a Python function to parse JSON and handle errors with try/except blocks",
                }
            ],
            "expected_specialization": TaskSpecialization.CODING,
        },
        {
            "name": "Agentic Task",
            "messages": [
                {
                    "role": "user",
                    "content": "Create a multi-step workflow agent that coordinates multiple API calls to process user data",
                }
            ],
            "expected_specialization": TaskSpecialization.AGENTIC,
        },
        {
            "name": "Fast Task",
            "messages": [
                {
                    "role": "user",
                    "content": "Quickly summarize what NixOS is in one sentence",
                }
            ],
            "expected_specialization": TaskSpecialization.FAST,
        },
        {
            "name": "Large Context Task",
            "messages": [
                {
                    "role": "user",
                    "content": "Analyze this 250,000 token document about machine learning architecture..."
                    + (" " * 250000),
                }
            ],
            "expected_specialization": TaskSpecialization.LARGE_CONTEXT,
        },
        {
            "name": "Claude Sonnet Request",
            "messages": [
                {"role": "user", "content": "Help me write a FastAPI endpoint"}
            ],
            "requested_model": "claude-sonnet-4-20250514",
            "expected_specialization": TaskSpecialization.LARGE_CONTEXT,
        },
    ]

    for scenario in test_scenarios:
        print(f"\n{'─' * 80}")
        print(f"Test: {scenario['name']}")
        print(f"{'─' * 80}")

        decision = await router.select_model(
            scenario["messages"], scenario.get("requested_model"), latency_tracker
        )

        print(f"Selected Model: {decision.model}")
        print(f"Backend: {decision.backend}")
        print(
            f"Specialization: {decision.specialization.value if decision.specialization else 'N/A'}"
        )
        print(f"Confidence: {decision.confidence:.2f}")
        print(f"Reason: {decision.reason}")
        print(f"Estimated Tokens: {decision.estimated_tokens}")
        print(
            f"Expected Latency: {decision.expected_latency_ms:.2f}ms"
            if decision.expected_latency_ms
            else "Expected Latency: N/A"
        )

        # Simulate request and record latency
        simulated_latency = 500 + (decision.estimated_tokens / 100)
        print(f"Simulated Latency: {simulated_latency:.2f}ms")
        await latency_tracker.record_latency(decision.model, simulated_latency)

    # Test latency-aware routing
    print(f"\n{'─' * 80}")
    print("Test: Latency-Aware Routing")
    print(f"{'─' * 80}")

    # Simulate high latency on Magnum Opus
    print("\nSimulating high load on magnum-opus-35b-a3b-i1...")
    for _ in range(10):
        await latency_tracker.record_latency(
            "magnum-opus-35b-a3b-i1", 6000
        )  # 6 seconds

    # Request that would normally go to Magnum Opus
    decision = await router.select_model(
        [{"role": "user", "content": "Generate a comprehensive analysis"}],
        "claude-sonnet-4-20250514",
        latency_tracker,
    )

    print(f"Selected Model: {decision.model}")
    print(
        f"Average Latency: {decision.expected_latency_ms:.2f}ms"
        if decision.expected_latency_ms
        else "Average Latency: N/A"
    )
    avg_latency = await latency_tracker.get_avg_latency("magnum-opus-35b-a3b-i1")
    print(f"Magnum Opus Average Latency: {avg_latency:.2f}ms (overloaded!)")

    print(f"\n{'=' * 80}")
    print("All tests completed!")
    print(f"{'=' * 80}")


if __name__ == "__main__":
    asyncio.run(test_routing())
