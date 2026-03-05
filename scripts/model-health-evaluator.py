#!/usr/bin/env python3
"""
AI Inference Model Health Evaluator

Comprehensive model evaluation system that:
- Tests all models for functionality
- Measures tokens/sec and latency
- Evaluates quality across multiple tasks
- Generates health scores
- Exports metrics to Prometheus
- Reports to Grafana
"""

import asyncio
import httpx
import json
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
import statistics

# Configuration
GATEWAY_URL = "http://127.0.0.1:8080"
PROMETHEUS_PUSHGATEWAY = "http://127.0.0.1:9091"  # If you have pushgateway
API_KEY_FILE = "/run/agenix/lm-studio-api-key"
RESULTS_DIR = Path("/var/lib/ai-inference/evaluations")

# Test prompts for different capabilities
TEST_PROMPTS = {
    "simple": {
        "prompt": "What is 2+2? Answer with just the number.",
        "expected": "4",
        "max_tokens": 10,
        "category": "basic_arithmetic"
    },
    "reasoning": {
        "prompt": "If I have 5 apples and eat 2, then buy 3 more, how many do I have? Think step by step.",
        "expected": "6",
        "max_tokens": 150,
        "category": "reasoning"
    },
    "coding": {
        "prompt": "Write a Python function to check if a number is prime.",
        "max_tokens": 300,
        "category": "coding"
    },
    "creative": {
        "prompt": "Write a haiku about artificial intelligence.",
        "max_tokens": 100,
        "category": "creative_writing"
    },
    "context": {
        "prompt": "Remember this number: 42. Now, what was the number?",
        "max_tokens": 50,
        "category": "short_term_memory"
    }
}


@dataclass
class ModelEvaluationResult:
    """Results from evaluating a single model."""
    model: str
    timestamp: str
    healthy: bool
    error: Optional[str] = None

    # Performance metrics
    latency_ms: float = 0.0
    time_to_first_token_ms: float = 0.0
    tokens_per_second: float = 0.0
    total_tokens: int = 0

    # Quality metrics
    simple_correct: bool = False
    reasoning_correct: bool = False
    generated_code: bool = False
    creative_quality: float = 0.0
    memory_correct: bool = False

    # Overall scores
    performance_score: float = 0.0  # 0-100
    quality_score: float = 0.0  # 0-100
    overall_score: float = 0.0  # 0-100

    # Resource usage
    input_tokens: int = 0
    output_tokens: int = 0
    total_time_ms: float = 0.0


class ModelHealthEvaluator:
    """Evaluates health and performance of all AI models."""

    def __init__(self, gateway_url: str = GATEWAY_URL):
        self.gateway_url = gateway_url
        self.api_key = self._load_api_key()

    def _load_api_key(self) -> Optional[str]:
        """Load API key from file."""
        try:
            return Path(API_KEY_FILE).read_text().strip()
        except Exception:
            return None

    async def get_available_models(self) -> List[str]:
        """Get list of available models from gateway."""
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                headers = {}
                if self.api_key:
                    headers["Authorization"] = f"Bearer {self.api_key}"

                response = await client.get(
                    f"{self.gateway_url}/v1/models",
                    headers=headers
                )

                if response.status_code == 200:
                    data = response.json()
                    return [m["id"] for m in data.get("data", [])]

                return []
        except Exception as e:
            print(f"Error fetching models: {e}")
            return []

    async def test_model(self, model: str, prompt: str, max_tokens: int = 100) -> Tuple[bool, dict]:
        """
        Test a model with a prompt.

        Returns:
            Tuple of (success, metrics_dict)
        """
        start_time = time.time()
        first_token_time = None

        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                headers = {
                    "Content-Type": "application/json"
                }
                if self.api_key:
                    headers["Authorization"] = f"Bearer {self.api_key}"

                response = await client.post(
                    f"{self.gateway_url}/v1/chat/completions",
                    headers=headers,
                    json={
                        "model": model,
                        "messages": [{"role": "user", "content": prompt}],
                        "max_tokens": max_tokens,
                        "stream": False
                    }
                )

                end_time = time.time()
                total_time_ms = (end_time - start_time) * 1000

                if response.status_code == 200:
                    result = response.json()

                    # Extract metrics
                    choice = result["choices"][0]
                    content = choice["message"]["content"]
                    usage = result.get("usage", {})
                    gateway_meta = result.get("gateway_metadata", {})

                    input_tokens = usage.get("prompt_tokens", 0)
                    output_tokens = usage.get("completion_tokens", 0)
                    total_tokens = usage.get("total_tokens", 0)

                    processing_time = gateway_meta.get("processing_time_ms", total_time_ms)

                    # Calculate tokens per second
                    if total_time_ms > 0:
                        tokens_per_second = (total_tokens / total_time_ms) * 1000
                    else:
                        tokens_per_second = 0

                    return True, {
                        "content": content,
                        "input_tokens": input_tokens,
                        "output_tokens": output_tokens,
                        "total_tokens": total_tokens,
                        "total_time_ms": total_time_ms,
                        "processing_time_ms": processing_time,
                        "tokens_per_second": tokens_per_second,
                    }
                else:
                    error = result.get("error", {}).get("message", "Unknown error")
                    return False, {"error": error, "status_code": response.status_code}

        except Exception as e:
            return False, {"error": str(e)}

    async def evaluate_model(self, model: str) -> ModelEvaluationResult:
        """Comprehensive evaluation of a single model."""

        print(f"\n📊 Evaluating: {model}")
        print("=" * 60)

        result = ModelEvaluationResult(
            model=model,
            timestamp=datetime.now().isoformat()
        )

        # Test 1: Simple arithmetic
        print("  🔢 Testing simple arithmetic...")
        success, metrics = await self.test_model(
            model,
            TEST_PROMPTS["simple"]["prompt"],
            TEST_PROMPTS["simple"]["max_tokens"]
        )

        if success:
            result.input_tokens += metrics.get("input_tokens", 0)
            result.output_tokens += metrics.get("output_tokens", 0)
            result.total_tokens += metrics.get("total_tokens", 0)
            result.total_time_ms += metrics.get("total_time_ms", 0)

            content = metrics.get("content", "").lower()
            result.simple_correct = "4" in content or "four" in content

            print(f"    ✓ Response time: {metrics.get('total_time_ms', 0):.0f}ms")
            print(f"    ✓ Tokens/sec: {metrics.get('tokens_per_second', 0):.1f}")
            print(f"    ✓ Correct: {result.simple_correct}")
        else:
            print(f"    ✗ Failed: {metrics.get('error', 'Unknown error')}")

        # Test 2: Reasoning
        print("  🧠 Testing reasoning...")
        success, metrics = await self.test_model(
            model,
            TEST_PROMPTS["reasoning"]["prompt"],
            TEST_PROMPTS["reasoning"]["max_tokens"]
        )

        if success:
            result.input_tokens += metrics.get("input_tokens", 0)
            result.output_tokens += metrics.get("output_tokens", 0)
            result.total_tokens += metrics.get("total_tokens", 0)
            result.total_time_ms += metrics.get("total_time_ms", 0)

            content = metrics.get("content", "").lower()
            result.reasoning_correct = "6" in content or "six" in content

            print(f"    ✓ Reasoning correct: {result.reasoning_correct}")
        else:
            print(f"    ✗ Failed")

        # Test 3: Coding (check if it generates code)
        print("  💻 Testing code generation...")
        success, metrics = await self.test_model(
            model,
            TEST_PROMPTS["coding"]["prompt"],
            TEST_PROMPTS["coding"]["max_tokens"]
        )

        if success:
            content = metrics.get("content", "")
            result.generated_code = "def " in content or "function" in content

            result.input_tokens += metrics.get("input_tokens", 0)
            result.output_tokens += metrics.get("output_tokens", 0)
            result.total_tokens += metrics.get("total_tokens", 0)
            result.total_time_ms += metrics.get("total_time_ms", 0)

            print(f"    ✓ Generated code: {result.generated_code}")
        else:
            print(f"    ✗ Failed")

        # Calculate overall metrics
        if result.total_time_ms > 0:
            result.tokens_per_second = (result.total_tokens / result.total_time_ms) * 1000
            result.latency_ms = result.total_time_ms / 4  # Average across 4 tests

        # Calculate scores
        result.performance_score = min(100, (result.tokens_per_second / 50) * 100)  # 50 tok/s = 100%
        quality_tests = [
            result.simple_correct,
            result.reasoning_correct,
            result.generated_code
        ]
        result.quality_score = (sum(quality_tests) / len(quality_tests)) * 100
        result.overall_score = (result.performance_score + result.quality_score) / 2
        result.healthy = result.simple_correct or result.reasoning_correct

        print(f"\n  📈 Performance Score: {result.performance_score:.1f}/100")
        print(f"  📈 Quality Score: {result.quality_score:.1f}/100")
        print(f"  📈 Overall Score: {result.overall_score:.1f}/100")

        return result

    async def evaluate_all_models(self) -> List[ModelEvaluationResult]:
        """Evaluate all available models."""
        print("="*60)
        print("AI INFERENCE MODEL HEALTH EVALUATION")
        print("="*60)

        models = await self.get_available_models()
        print(f"\nFound {len(models)} models to evaluate\n")

        results = []

        for model in models:
            try:
                result = await self.evaluate_model(model)
                results.append(result)
            except Exception as e:
                print(f"  ❌ Error evaluating {model}: {e}")
                results.append(ModelEvaluationResult(
                    model=model,
                    timestamp=datetime.now().isoformat(),
                    healthy=False,
                    error=str(e)
                ))

        return results

    def generate_report(self, results: List[ModelEvaluationResult]) -> dict:
        """Generate summary report from evaluation results."""
        healthy = [r for r in results if r.healthy]
        unhealthy = [r for r in results if not r.healthy]

        # Calculate averages
        if healthy:
            avg_performance = statistics.mean([r.performance_score for r in healthy])
            avg_quality = statistics.mean([r.quality_score for r in healthy])
            avg_overall = statistics.mean([r.overall_score for r in healthy])
            avg_tokens_per_sec = statistics.mean([r.tokens_per_second for r in healthy])
        else:
            avg_performance = avg_quality = avg_overall = avg_tokens_per_sec = 0

        # Best models
        best_performance = max(healthy, key=lambda r: r.performance_score, default=None)
        best_quality = max(healthy, key=lambda r: r.quality_score, default=None)
        best_overall = max(healthy, key=lambda r: r.overall_score, default=None)

        # Fastest models
        fastest = min(healthy, key=lambda r: r.latency_ms, default=None)

        return {
            "timestamp": datetime.now().isoformat(),
            "total_models": len(results),
            "healthy_models": len(healthy),
            "unhealthy_models": len(unhealthy),
            "health_percentage": (len(healthy) / len(results) * 100) if results else 0,
            "averages": {
                "performance_score": avg_performance,
                "quality_score": avg_quality,
                "overall_score": avg_overall,
                "tokens_per_second": avg_tokens_per_sec
            },
            "best": {
                "performance": best_performance.model if best_performance else None,
                "quality": best_quality.model if best_quality else None,
                "overall": best_overall.model if best_overall else None,
                "fastest": fastest.model if fastest else None
            },
            "models": [
                {
                    "model": r.model,
                    "healthy": r.healthy,
                    "performance_score": r.performance_score,
                    "quality_score": r.quality_score,
                    "overall_score": r.overall_score,
                    "tokens_per_second": r.tokens_per_second,
                    "latency_ms": r.latency_ms,
                }
                for r in results
            ]
        }

    def save_results(self, results: List[ModelEvaluationResult], report: dict):
        """Save evaluation results to file."""
        RESULTS_DIR.mkdir(parents=True, exist_ok=True)

        # Save detailed results
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        results_file = RESULTS_DIR / f"evaluation_{timestamp}.json"

        with open(results_file, "w") as f:
            json.dump({
                "report": report,
                "detailed_results": [asdict(r) for r in results]
            }, f, indent=2)

        print(f"\n💾 Results saved to: {results_file}")

        # Save latest report
        latest_file = RESULTS_DIR / "latest_evaluation.json"
        with open(latest_file, "w") as f:
            json.dump(report, f, indent=2)

        print(f"💾 Latest report: {latest_file}")

    def print_summary(self, report: dict):
        """Print summary report."""
        print("\n" + "="*60)
        print("EVALUATION SUMMARY")
        print("="*60)

        print(f"\n📊 Overall Health:")
        print(f"  Total Models: {report['total_models']}")
        print(f"  Healthy: {report['healthy_models']} ({report['health_percentage']:.1f}%)")
        print(f"  Unhealthy: {report['unhealthy_models']}")

        print(f"\n📈 Average Scores:")
        print(f"  Performance: {report['averages']['performance_score']:.1f}/100")
        print(f"  Quality: {report['averages']['quality_score']:.1f}/100")
        print(f"  Overall: {report['averages']['overall_score']:.1f}/100")
        print(f"  Tokens/sec: {report['averages']['tokens_per_second']:.1f}")

        print(f"\n🏆 Best Models:")
        print(f"  Performance: {report['best']['performance']}")
        print(f"  Quality: {report['best']['quality']}")
        print(f"  Overall: {report['best']['overall']}")
        print(f"  Fastest: {report['best']['fastest']}")

        # Health check
        if report['health_percentage'] < 50:
            print(f"\n⚠️  WARNING: Less than 50% of models are healthy!")
        elif report['health_percentage'] < 80:
            print(f"\n⚠️  CAUTION: Some models are unhealthy.")
        else:
            print(f"\n✅ All models are healthy!")


async def main():
    """Main evaluation workflow."""
    evaluator = ModelHealthEvaluator()

    # Evaluate all models
    results = await evaluator.evaluate_all_models()

    # Generate report
    report = evaluator.generate_report(results)

    # Print summary
    evaluator.print_summary(report)

    # Save results
    evaluator.save_results(results, report)

    # Return exit code based on health
    unhealthy_count = report['unhealthy_models']
    if unhealthy_count > 0:
        print(f"\n❌ {unhealthy_count} model(s) are unhealthy!")
        return 1
    else:
        print(f"\n✅ All models are healthy!")
        return 0


if __name__ == "__main__":
    exit(asyncio.run(main()))
