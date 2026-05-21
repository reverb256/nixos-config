#!/usr/bin/env python3
"""
Unified AI Model Registry Validator
Reads /etc/nixos/ai-models.toml and validates consistency across all AI tools.

Phase 1: Validates TOML is parseable and contains expected sections
Phase 2: Cross-references models against backends and ensures consistency
Phase 3: Validates against actual consumer configs (Claude, OpenCode, Hermes, etc.)

Usage:
  python3 /etc/nixos/scripts/validate-ai-models-registry.py [--verbose] [--check-consumers]

Exit codes:
  0 = OK (all checks pass)
  1 = WARNING (non-critical inconsistencies)
  2 = ERROR (TOML parse failure or missing required sections)
"""

import sys
import tomllib
from pathlib import Path
import json

REQUIRED_SECTIONS = {
    "defaults": ["primary", "fallback"],
    "models": None,  # must have at least one model entry
    "backends": None,  # must have at least one backend entry
    "disabled_models": None,  # optional
}

def validate_toml_structure(data):
    """Validate basic TOML structure and required sections."""
    warnings = []
    errors = []

    for section, required_keys in REQUIRED_SECTIONS.items():
        if section not in data:
            errors.append(f"Missing required top-level section: [{section}]")
            continue

        if required_keys:
            for key in required_keys:
                if key not in data.get(section, {}):
                    errors.append(f"[{section}].{key} is missing")

    return errors, warnings

def validate_models(data):
    """Validate model definitions and cross-reference with backends."""
    warnings = []
    errors = []

    models = data.get("models", {})
    backends = data.get("backends", {})

    if not models:
        errors.append("[models] section has no model entries")
        return errors, warnings

    if not backends:
        errors.append("[backends] section has no backend entries")
        return errors, warnings

    # Check each model has required fields
    for model_id, model_info in models.items():
        if not isinstance(model_info, dict):
            errors.append(f"[models].\"{model_id}\" must be a table")
            continue

        for field in ["name", "description", "context_length", "capabilities", "backends"]:
            if field not in model_info:
                errors.append(f"[models].\"{model_id}\" missing '{field}'")

        # Check backends exist
        if "backends" in model_info:
            for backend_ref in model_info["backends"]:
                if backend_ref not in backends:
                    errors.append(f"[models].\"{model_id}\" references non-existent backend: {backend_ref}")

    # Check each backend has required fields
    for backend_id, backend_info in backends.items():
        if not isinstance(backend_info, dict):
            errors.append(f"[backends].\"{backend_id}\" must be a table")
            continue

        for field in ["type", "url", "host"]:
            if field not in backend_info:
                errors.append(f"[backends].\"{backend_id}\" missing '{field}'")

    # Verify default and fallback models exist
    defaults = data.get("defaults", {})
    for key in ["primary", "fallback"]:
        model_name = defaults.get(key)
        if model_name:
            if not any(model.get("name") == model_name for model in models.values()):
                errors.append(f"[defaults].{key} references non-existent model: {model_name}")

    return errors, warnings

def validate_consumer_configs(data, check_consumers=False):
    """Cross-reference against actual consumer configs if requested."""
    warnings = []
    errors = []

    if not check_consumers:
        return errors, warnings

    consumer_files = [
        ("OpenCode", "/home/j_kro/.opencode/config.json"),
        ("Claude", "/home/j_kro/.claude/settings.json"),
        ("Hermes", "/home/j_kro/.hermes/config.yaml"),
    ]

    models_in_registry = set()
    for model_info in data.get("models", {}).values():
        model_name = model_info.get("name")
        if model_name:
            models_in_registry.add(model_name)

    for tool_name, config_path in consumer_files:
        try:
            path = Path(config_path)
            if not path.exists():
                warnings.append(f"{tool_name} config not found: {config_path}")
                continue

            if config_path.endswith(".json"):
                with open(path, "r") as f:
                    config = json.load(f)
            else:
                warnings.append(f"{tool_name} config format not yet validated: {config_path}")
                continue

            # Check if config uses registry models (basic validation)
            if "model" in config:
                if config["model"] not in models_in_registry:
                    warnings.append(f"{tool_name} uses non-registry model: {config['model']}")

        except Exception as e:
            warnings.append(f"Cannot validate {tool_name} config: {e}")

    return errors, warnings

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

    all_errors = []
    all_warnings = []

    # Phase 1: Structure validation
    errors, warnings = validate_toml_structure(data)
    all_errors.extend(errors)
    all_warnings.extend(warnings)

    # Phase 2: Model validation
    errors, warnings = validate_models(data)
    all_errors.extend(errors)
    all_warnings.extend(warnings)

    # Phase 3: Consumer validation (optional)
    check_consumers = "--check-consumers" in sys.argv
    errors, warnings = validate_consumer_configs(data, check_consumers)
    all_errors.extend(errors)
    all_warnings.extend(warnings)

    # Report results
    if all_errors:
        print("FAIL")
        for e in all_errors:
            print(f"  ERROR: {e}")
        sys.exit(2)

    if all_warnings:
        print("OK (with warnings)")
        for w in all_warnings:
            print(f"  WARNING: {w}")
        sys.exit(1)

    model_count = len(data.get("models", {}))
    backend_count = len(data.get("backends", {}))
    print(f"OK — {model_count} models, {backend_count} backends, {len(data.get('defaults', {}))} defaults")
    sys.exit(0)


if __name__ == "__main__":
    validate()