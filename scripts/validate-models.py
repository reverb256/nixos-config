#!/usr/bin/env python3
"""
Model Registry Validator
Reads /etc/nixos/ai-models.toml and checks consistency across consumers.

Phase 1: Validates TOML is parseable and contains expected sections.
Phase 2+: Will cross-reference against all consumer files.

Usage:
  python3 /etc/nixos/scripts/validate-models.py [--verbose]

Exit codes:
  0 = OK (all checks pass)
  1 = WARNING (non-critical inconsistencies)
  2 = ERROR (TOML parse failure or missing required sections)
"""

import sys
import tomllib
from pathlib import Path

REQUIRED_SECTIONS = {
    "defaults": ["primary", "chat", "fast", "vision", "embedding"],
    "curated": None,  # must have 'cloud' sub-key with entries
}

def validate():
    path = Path("/etc/nixos/ai-models.toml")
    if not path.exists():
        print(f"ERROR: {path} not found")
        sys.exit(2)

    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        print(f"ERROR: TOML parse failed: {e}")
        sys.exit(2)
    except Exception as e:
        print(f"ERROR: Cannot read {path}: {e}")
        sys.exit(2)

    warnings = []
    errors = []

    # Check required top-level sections
    for section in ["defaults", "llama-cpp", "vllm", "gateway", "cloud-providers", "curated", "agents", "maplespike"]:
        if section not in data:
            warnings.append(f"Missing recommended top-level section: [{section}]")

    # Check defaults have all expected keys
    defaults = data.get("defaults", {})
    for key in ["primary", "chat", "fast", "vision", "embedding"]:
        if key not in defaults or not defaults[key]:
            errors.append(f"[defaults].{key} is missing or empty")

    # Check curated cloud models exist
    curated = data.get("curated", {})
    cloud_models = curated.get("cloud", {})
    if not cloud_models:
        errors.append("[curated.cloud] has no model entries")
    else:
        # Verify each curated model has required fields
        for model_id, info in cloud_models.items():
            if not isinstance(info, dict):
                errors.append(f"[curated.cloud].\"{model_id}\" must be a table (inline or full)")
                continue
            for field in ["category", "description", "provider"]:
                if field not in info:
                    errors.append(f"[curated.cloud].\"{model_id}\" missing '{field}'")

    # Check llama-cpp backends have ports
    for name, backend in data.get("llama-cpp", {}).items():
        if not isinstance(backend, dict):
            continue
        if "model" not in backend:
            errors.append(f"[llama-cpp.{name}] missing 'model'")
        if "port" not in backend:
            warnings.append(f"[llama-cpp.{name}] missing 'port'")

    # Check vllm backends
    for name, backend in data.get("vllm", {}).items():
        if not isinstance(backend, dict):
            continue
        if "model" not in backend:
            errors.append(f"[vllm.{name}] missing 'model'")

    # Check cloud providers
    for name, provider in data.get("cloud-providers", {}).items():
        if not isinstance(provider, dict):
            continue
        if "base_url" not in provider:
            errors.append(f"[cloud-providers.{name}] missing 'base_url'")

    # Report
    if errors:
        print("FAIL")
        for e in errors:
            print(f"  ERROR: {e}")
        sys.exit(2)

    if warnings:
        print("OK (with warnings)")
        for w in warnings:
            print(f"  WARNING: {w}")
        sys.exit(1)

    model_count = len(cloud_models)
    backend_count = len(data.get("llama-cpp", {})) + len(data.get("vllm", {}))
    print(f"OK — {model_count} curated cloud models, {backend_count} local backends, "
          f"{len(data.get('cloud-providers', {}))} cloud providers")
    sys.exit(0)


if __name__ == "__main__":
    verbose = "--verbose" in sys.argv
    validate()
