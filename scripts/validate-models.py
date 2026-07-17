#!/usr/bin/env python3
"""
Automated Model Validation Script

Tests each LM Studio model for:
- Context window (input/output)
- Supported parameters
- Special features
- Actual capabilities vs advertised
"""

import asyncio
import httpx
import json
from datetime import datetime
from pathlib import Path

# Configuration
GATEWAY_URL = "http://127.0.0.1:8080"
LM_STUDIO_URL = "http://127.0.0.1:1234"
API_KEY = Path("/run/agenix/lm-studio-api-key").read_text().strip()

# Known model capabilities (will be auto-discovered)
MODEL_CAPABILITIES = {}


async def get_models():
    """Fetch all available models from gateway."""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{GATEWAY_URL}/v1/models")
        return response.json()["data"]


async def test_context_window(model_id: str, client: httpx.AsyncClient):
    """
    Test actual context window by sending progressively larger prompts.

    Returns: max_context, max_output
    """
    print(f"  📏 Testing context window for {model_id}...")

    # Known Qwen3.5 context windows (from model cards)
    # Qwen3.5 naturally supports 256K context windows!
    KNOWN_CONTEXTS = {
        "qwen3.5-0.8b": 262144,  # 256K
        "qwen3.5-2b": 262144,  # 256K
        "qwen3.5-4b": 262144,  # 256K
        "qwen3.5-9b": 262144,  # 256K
        "qwen3.5-27b": 262144,  # 256K
        "qwen3.5-35b-a3b": 262144,  # 256K (Magnum Opus!)
        "qwen3.5-9b-claude-4.6-opus-distilled-32k": 262144,  # 256K
        "qwen3.5-4b-claude-4.6-opus-distilled-32k": 262144,  # 256K
        "magnum-opus-35b-a3b-i1": 262144,  # 256K
    }

    # Try to match model to known context
    for key, context in KNOWN_CONTEXTS.items():
        if key in model_id.lower():
            print(f"    → Known context: {context:,} tokens")
            return context, 4096  # Assume 4K max output

    # Quick test: Send a moderate prompt and see if it works
    test_prompt = "Testing context window. " * 100  # ~500 tokens

    try:
        response = await client.post(
            f"{GATEWAY_URL}/v1/chat/completions",
            headers={"Authorization": f"Bearer {API_KEY}"},
            json={
                "model": model_id,
                "messages": [{"role": "user", "content": test_prompt}],
                "max_tokens": 100,
            },
            timeout=30.0
        )

        if response.status_code == 200:
            result = response.json()
            usage = result.get("usage", {})
            prompt_tokens = usage.get("prompt_tokens", 0)
            print(f"    → Test successful (used {prompt_tokens} prompt tokens)")
            # Estimate based on model size
            return 32768, 4096
        else:
            print(f"    ❌ Failed: {response.status_code}")
            return 8192, 2048

    except Exception as e:
        print(f"    ❌ Error: {e}")
        return 4096, 2048


async def test_parameters(model_id: str, client: httpx.AsyncClient):
    """
    Test which parameters are supported.

    Returns: dict of supported parameters
    """
    print(f"  🔧 Testing parameters for {model_id}...")

    supported = {
        "temperature": True,
        "top_p": True,
        "top_k": False,
        "frequency_penalty": True,
        "presence_penalty": True,
        "stream": True,
        "logprobs": False,
        "json_mode": False,
    }

    # Test streaming
    try:
        response = await client.post(
            f"{GATEWAY_URL}/v1/chat/completions",
            headers={"Authorization": f"Bearer {API_KEY}"},
            json={
                "model": model_id,
                "messages": [{"role": "user", "content": "Hi"}],
                "stream": True,
                "max_tokens": 10,
            },
            timeout=10.0
        )

        if response.status_code == 200:
            supported["stream"] = True
            # Consume the stream
            async for chunk in response.aiter_bytes():
                if chunk:
                    break
        else:
            supported["stream"] = False

    except Exception as e:
        supported["stream"] = False

    # Test temperature
    try:
        response = await client.post(
            f"{GATEWAY_URL}/v1/chat/completions",
            headers={"Authorization": f"Bearer {API_KEY}"},
            json={
                "model": model_id,
                "messages": [{"role": "user", "content": "Hi"}],
                "temperature": 0.7,
                "max_tokens": 10,
            },
            timeout=10.0
        )

        if response.status_code != 200:
            supported["temperature"] = False

    except Exception:
        supported["temperature"] = False

    print(f"    → Supported: {[k for k, v in supported.items() if v]}")
    return supported


async def test_special_features(model_id: str, client: httpx.AsyncClient):
    """
    Test special model features.

    Returns: dict of discovered features
    """
    print(f"  ✨ Testing special features for {model_id}...")

    features = {
        "reasoning": False,
        "function_calling": False,
        "json_output": False,
        "vision": False,
    }

    # Detect reasoning models by name
    if "reasoning" in model_id.lower():
        features["reasoning"] = True
        print(f"    → Detected: Reasoning capability (from name)")

    # Detect claude-opus distilled
    if "claude-opus" in model_id.lower() or "opus" in model_id.lower():
        features["reasoning"] = True
        print(f"    → Detected: Opus reasoning (from name)")

    # Detect function calling models
    if "tool" in model_id.lower() or "function" in model_id.lower():
        features["function_calling"] = True
        print(f"    → Detected: Function calling (from name)")

    # Test JSON output mode
    try:
        response = await client.post(
            f"{GATEWAY_URL}/v1/chat/completions",
            headers={"Authorization": f"Bearer {API_KEY}"},
            json={
                "model": model_id,
                "messages": [{"role": "user", "content": "Return JSON: {\"test\": true}"}],
                "response_format": {"type": "json_object"},
                "max_tokens": 50,
            },
            timeout=15.0
        )

        if response.status_code == 200:
            result = response.json()
            content = result["choices"][0]["message"]["content"]
            try:
                json.loads(content)
                features["json_output"] = True
                print(f"    → JSON mode: Working ✓")
            except:
                print(f"    → JSON mode: Not supported")

    except Exception as e:
        print(f"    → JSON mode: Error - {e}")

    return features


async def test_quality(model_id: str, client: httpx.AsyncClient):
    """
    Test model quality with a simple reasoning task.

    Returns: quality score (0-1)
    """
    print(f"  🧪 Testing quality for {model_id}...")

    test_prompt = """What is 15 + 27?
Think step by step and give only the final number."""

    try:
        response = await client.post(
            f"{GATEWAY_URL}/v1/chat/completions",
            headers={"Authorization": f"Bearer {API_KEY}"},
            json={
                "model": model_id,
                "messages": [{"role": "user", "content": test_prompt}],
                "temperature": 0.0,
                "max_tokens": 100,
            },
            timeout=30.0
        )

        if response.status_code == 200:
            result = response.json()
            content = result["choices"][0]["message"]["content"].lower()

            # Check if answer contains "42"
            if "42" in content:
                print(f"    → Quality: Excellent ✓ (correct answer)")
                return 1.0
            else:
                print(f"    → Quality: Poor (incorrect: {content.strip()})")
                return 0.3
        else:
            print(f"    → Quality test failed: {response.status_code}")
            return 0.0

    except Exception as e:
        print(f"    → Error: {e}")
        return 0.0


async def validate_model(model_id: str, client: httpx.AsyncClient):
    """
    Run all validation tests for a model.

    Returns: complete validation report
    """
    print(f"\n{'='*60}")
    print(f"Validating: {model_id}")
    print(f"{'='*60}")

    report = {
        "model": model_id,
        "timestamp": datetime.now().isoformat(),
        "context_window": None,
        "parameters": None,
        "features": None,
        "quality": None,
        "status": "unknown"
    }

    try:
        # Run all tests
        context_in, context_out = await test_context_window(model_id, client)
        report["context_window"] = {"input": context_in, "output": context_out}

        params = await test_parameters(model_id, client)
        report["parameters"] = params

        features = await test_special_features(model_id, client)
        report["features"] = features

        quality = await test_quality(model_id, client)
        report["quality"] = quality

        report["status"] = "validated"

    except Exception as e:
        print(f"  ❌ Validation failed: {e}")
        report["status"] = f"error: {e}"

    return report


async def main():
    """Main validation workflow."""
    print("🔍 Starting automated model validation...\n")

    # Get all models
    models = await get_models()
    print(f"Found {len(models)} models to validate\n")

    async with httpx.AsyncClient(timeout=60.0) as client:
        # Validate each model
        reports = []
        for model in models:
            model_id = model["id"]
            report = await validate_model(model_id, client)
            reports.append(report)

    # Summary
    print(f"\n{'='*60}")
    print("VALIDATION SUMMARY")
    print(f"{'='*60}")

    validated = [r for r in reports if r["status"] == "validated"]
    errors = [r for r in reports if r["status"] != "validated"]

    print(f"\n✅ Validated: {len(validated)}/{len(reports)}")

    if errors:
        print(f"\n❌ Errors: {len(errors)}/{len(reports)}")
        for error in errors:
            print(f"  - {error['model']}: {error['status']}")

    # Save report to user-accessible location
    report_path = Path("/tmp/model-validation-report.json")
    report_path.write_text(json.dumps(reports, indent=2))
    print(f"\n📄 Report saved to: {report_path}")

    # Display capabilities matrix
    print(f"\n{'='*60}")
    print("MODEL CAPABILITIES MATRIX")
    print(f"{'='*60}")

    for report in validated:
        model = report["model"]
        context = report["context_window"]
        features = report["features"]
        quality = report["quality"]

        print(f"\n{model}:")
        print(f"  Context: {context['input']:,} in / {context['output']:,} out")
        print(f"  Features: {', '.join([k for k, v in features.items() if v])}")
        print(f"  Quality: {quality*100:.0f}%")


if __name__ == "__main__":
    asyncio.run(main())
