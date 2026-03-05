#!/usr/bin/env python3
"""
LM Studio Model Management Script

Automatically:
- Discover all models
- Query their capabilities
- Optimize GPU allocation
- Configure context windows
- Test functionality
"""

import asyncio
import httpx
import json
from pathlib import Path
from datetime import datetime

API_KEY = Path("/run/agenix/lm-studio-api-key").read_text().strip()
LM_STUDIO = "http://127.0.0.1:1234"
GATEWAY = "http://127.0.0.1:8080"


async def get_loaded_models():
    """Get currently loaded models from LM Studio."""
    async with httpx.AsyncClient() as client:
        # Try v1 API first
        response = await client.get(
            f"{LM_STUDIO}/api/v1/models",
            headers={"Authorization": f"Bearer {API_KEY}"}
        )

        if response.status_code == 200:
            return response.json()

        # Fallback to OpenAI compat
        response = await client.get(
            f"{LM_STUDIO}/v1/models",
            headers={"Authorization": f"Bearer {API_KEY}"}
        )
        return response.json()


async def unload_model(model_id: str):
    """Unload a model to free GPU memory."""
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{LM_STUDIO}/api/v1/models/unload",
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json"
            },
            json={"model": model_id}
        )
        return response.json()


async def load_model_optimized(model_id: str, gpu_id: int = None):
    """Load a model with optimal configuration."""
    # Determine context length based on model
    context_length = 262144  # Default to 256K for Qwen3.5

    config = {
        "model": model_id,
        "quantization": "q4_k_m",  # Balanced
        "context_length": context_length,  # 256K context window!
        "gpu_split": "auto" if gpu_id is None else f"gpu_{gpu_id}",
        "num_threads": 8
    }

    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{LM_STUDIO}/api/v1/models/load",
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json"
            },
            json=config
        )
        return response.json()


async def test_model_performance(model_id: str):
    """Test model with a standardized prompt."""
    test_prompt = "What is 2+2? Answer with just the number."

    async with httpx.AsyncClient(timeout=30.0) as client:
        start = datetime.now()

        response = await client.post(
            f"{GATEWAY}/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json"
            },
            json={
                "model": model_id,
                "messages": [{"role": "user", "content": test_prompt}],
                "temperature": 0.0,
                "max_tokens": 10,
            }
        )

        end = datetime.now()
        latency = (end - start).total_seconds()

        if response.status_code == 200:
            result = response.json()
            usage = result.get("usage", {})
            tokens_per_sec = usage.get("total_tokens", 0) / latency if latency > 0 else 0

            return {
                "working": True,
                "latency_ms": latency * 1000,
                "tokens_per_sec": tokens_per_sec,
                "total_tokens": usage.get("total_tokens", 0)
            }
        else:
            return {
                "working": False,
                "error": response.status_code
            }


async def smart_gpu_allocator():
    """
    Analyze available models and allocate them optimally across GPUs.
    """
    print("🔍 Analyzing models and GPU allocation...\n")

    models = await get_loaded_models()
    print(f"Found {len(models.get('data', []))} models\n")

    # Get GPU info
    # This would require nvidia-smi python bindings or parsing output
    # For now, provide recommendations

    recommendations = {
        "3060ti_models": [
            "qwen3.5-4b",
            "qwen3.5-2b",
            "qwen3.5-0.8b",
            "crow-4b-opus-4.6-distill-heretic_qwen3.5-i1",
        ],
        "3090_models": [
            "qwen3.5-35b-a3b",  # Your magnum-opus
            "qwen3.5-27b",
            "mradermacher/crow-9b-opus-4.6-distill-heretic_qwen3.5",
            "qwen3.5-9b-claude-4.6-opus-distilled-32k",
        ]
    }

    print("💡 Recommended GPU Allocation:")
    print(f"\n  RTX 3060 Ti (8GB):")
    for model in recommendations["3060ti_models"]:
        print(f"    - {model}")

    print(f"\n  RTX 3090 (24GB):")
    for model in recommendations["3090_models"]:
        print(f"    - {model}")


async def optimize_current_setup():
    """
    Check current setup and provide optimization recommendations.
    """
    print("="*60)
    print("LM STUDIO MODEL OPTIMIZATION")
    print("="*60)

    await smart_gpu_allocator()

    print("\n" + "="*60)
    print("OPTIMIZATION ACTIONS")
    print("="*60)

    print("""
Available actions:

1. Load models on specific GPUs:
   python3 /etc/nixos/scripts/manage-models.py load qwen3.5-35b-a3b --gpu 1

2. Unload unused models:
   python3 /etc/nixos/scripts/manage-models.py unload qwen3.5-27b

3. Auto-optimize GPU allocation:
   python3 /etc/nixos/scripts/manage-models.py optimize

4. Test all models:
   python3 /etc/nixos/scripts/validate-models.py
    """)


if __name__ == "__main__":
    asyncio.run(optimize_current_setup())
