#!/usr/bin/env python3
"""Debug script to test different GLM models."""

import json
import os
from pathlib import Path
from openai import OpenAI

# Configuration
ZAI_API_KEY_FILE = Path("/run/agenix/zai-api-key")
ZAI_API_KEY = ZAI_API_KEY_FILE.read_text().strip() if ZAI_API_KEY_FILE.exists() else ""

client = OpenAI(
    api_key=ZAI_API_KEY,
    base_url="https://api.z.ai/api/coding/paas/v4"
)

# Ultra-simple test prompt
EVAL_PROMPT = """Return JSON: {"score": 50}"""

# Test different models
models_to_test = ["glm-4.6", "glm-4.7", "glm-5"]

for model in models_to_test:
    print(f"\n{'='*60}")
    print(f"Testing: {model}")
    print(f"{'='*60}")

    try:
        response = client.chat.completions.create(
            model=model,
            max_tokens=100,
            messages=[{"role": "user", "content": EVAL_PROMPT}]
        )

        print(f"finish_reason: {response.choices[0].finish_reason}")
        content = response.choices[0].message.content if response.choices[0].message.content else ""
        print(f"content: '{content}'")

        if content:
            print(f"✅ {model} WORKS!")
            break
        else:
            print(f"❌ {model} returns empty response")

    except Exception as e:
        print(f"❌ {model} ERROR: {e}")
