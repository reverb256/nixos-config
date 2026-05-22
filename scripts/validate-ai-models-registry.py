#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""
Unified AI Models Registry Validator
Validates the Nix-based model registry (curated-models.nix) by importing it
via Nix and checking consistency against the TOML registry.

Phase 1: Import and parse the Nix registry
Phase 2: Validate structure and cross-references
Phase 3: Cross-reference against TOML registry for consistency
Phase 4: Check model → backend consistency

Usage:
  python3 /etc/nixos/scripts/validate-ai-models-registry.py [--verbose] [--check-consumers]
"""

import sys
import json
import subprocess
import tomllib
from pathlib import Path

REGISTRY_PATH = Path("/etc/nixos/kubernetes/curated-models.nix")
TOML_PRIMARY_PATH = Path("/etc/nixos/ai-models.toml")
TOML_K8S_PATH = Path("/etc/nixos/kubernetes/ai-models.toml")

REQUIRED_MODEL_FIELDS = ["id", "name", "category", "provider"]
OPTIONAL_MODEL_FIELDS = ["contextWindow", "url", "gpu", "host", "vision", "reasoning",
                         "quotaMultiplier", "priority", "capabilities"]
REQUIRED_CATEGORIES = ["primary", "fast", "reasoning", "code", "free"]
REQUIRED_PROVIDER_FIELDS = ["type", "url", "host"]


def import_nix_registry():
    """Import the Nix registry by evaluating it with nix-instantiate."""
    if not REGISTRY_PATH.exists():
        print(f"ERROR: Nix registry not found: {REGISTRY_PATH}")
        sys.exit(2)

    try:
        # Use nix eval to import the Nix file as JSON
        result = subprocess.run(
            ["nix", "eval", "--impure", "--expr",
             f"builtins.toJSON (import {REGISTRY_PATH})",
             "--json"],
            capture_output=True, text=True, timeout=60
        )
        if result.returncode != 0:
            print(f"ERROR: Failed to import Nix registry: {result.stderr}")
            sys.exit(2)
        return json.loads(result.stdout.strip())
    except subprocess.TimeoutExpired:
        print("ERROR: Nix evaluation timed out")
        sys.exit(2)
    except json.JSONDecodeError as e:
        print(f"ERROR: Failed to parse Nix registry JSON: {e}")
        sys.exit(2)


def validate_nix_structure(data):
    """Validate the Nix registry structure."""
    errors = []
    warnings = []

    # Check top-level sections
    for section in ["defaults", "models", "roles", "providers", "hosts"]:
        if section not in data:
            errors.append(f"Missing top-level section: {section}")

    return errors, warnings


def validate_defaults(data):
    """Validate defaults section."""
    errors = []
    warnings = []
    defaults = data.get("defaults", {})

    # Collect all model IDs for cross-reference
    model_ids = {m.get("id") for m in data.get("models", {}).values() if isinstance(m, dict)}

    for role, model_id in defaults.items():
        if model_id not in model_ids:
            warnings.append(f"Default role '{role}' references unknown model: '{model_id}'")

    return errors, warnings


def validate_models(data):
    """Validate model definitions."""
    errors = []
    warnings = []
    models = data.get("models", {})
    providers = data.get("providers", {})

    if not models:
        errors.append("No models defined")
        return errors, warnings

    for model_key, model in models.items():
        if not isinstance(model, dict):
            errors.append(f"Model '{model_key}' must be a table")
            continue

        # Check required fields
        for field in REQUIRED_MODEL_FIELDS:
            if field not in model:
                errors.append(f"Model '{model_key}' missing required field: '{field}'")

        # Check provider reference
        provider = model.get("provider")
        if provider and provider not in providers:
            errors.append(f"Model '{model_key}' references non-existent provider: '{provider}'")

        # Check category
        category = model.get("category")
        if category and category not in REQUIRED_CATEGORIES:
            warnings.append(f"Model '{model_key}' has non-standard category: '{category}'")

    return errors, warnings


def validate_providers(data):
    """Validate provider configurations."""
    errors = []
    warnings = []
    providers = data.get("providers", {})

    if not providers:
        errors.append("No providers defined")
        return errors, warnings

    for prov_key, provider in providers.items():
        if not isinstance(provider, dict):
            errors.append(f"Provider '{prov_key}' must be a table")
            continue

        for field in REQUIRED_PROVIDER_FIELDS:
            if field not in provider:
                errors.append(f"Provider '{prov_key}' missing required field: '{field}'")

    return errors, warnings


def validate_vs_toml(nix_data):
    """Cross-reference Nix registry against the main TOML registry."""
    errors = []
    warnings = []

    if not TOML_PRIMARY_PATH.exists():
        warnings.append(f"TOML registry not found: {TOML_PRIMARY_PATH}")
        return errors, warnings

    try:
        with open(TOML_PRIMARY_PATH, "rb") as f:
            toml_data = tomllib.load(f)
    except Exception as e:
        warnings.append(f"Cannot load TOML registry: {e}")
        return errors, warnings

    # Compare model counts
    nix_model_count = len(nix_data.get("models", {}))
    toml_model_count = len(toml_data.get("models", {}))

    if nix_model_count != toml_model_count:
        warnings.append(
            f"Model count mismatch: Nix={nix_model_count}, TOML={toml_model_count}"
        )

    # Check TOML default references against Nix model IDs
    toml_defaults = toml_data.get("defaults", {})
    nix_model_ids = {m.get("id") for m in nix_data.get("models", {}).values() if isinstance(m, dict)}

    for key, model_name in toml_defaults.items():
        if isinstance(model_name, str) and model_name not in nix_model_ids:
            warnings.append(f"TOML default '{key}' references model not in Nix registry: '{model_name}'")

    return errors, warnings


def main():
    verbose = "--verbose" in sys.argv
    check_consumers = "--check-consumers" in sys.argv

    all_errors = []
    all_warnings = []

    # Phase 1: Import Nix registry
    if verbose:
        print("Phase 1: Importing Nix registry...")
    nix_data = import_nix_registry()

    # Phase 2: Validate structure
    if verbose:
        print("Phase 2: Validating structure...")
    errors, warnings = validate_nix_structure(nix_data)
    all_errors.extend(errors)
    all_warnings.extend(warnings)

    # Phase 3: Validate defaults
    if verbose:
        print("Phase 3: Validating defaults...")
    errors, warnings = validate_defaults(nix_data)
    all_errors.extend(errors)
    all_warnings.extend(warnings)

    # Phase 4: Validate models
    if verbose:
        print("Phase 4: Validating models...")
    errors, warnings = validate_models(nix_data)
    all_errors.extend(errors)
    all_warnings.extend(warnings)

    # Phase 5: Validate providers
    if verbose:
        print("Phase 5: Validating providers...")
    errors, warnings = validate_providers(nix_data)
    all_errors.extend(errors)
    all_warnings.extend(warnings)

    # Phase 6: Compare with TOML registry
    if verbose:
        print("Phase 6: Cross-referencing with TOML registry...")
    errors, warnings = validate_vs_toml(nix_data)
    all_errors.extend(errors)
    all_warnings.extend(warnings)

    # Report
    model_count = len(nix_data.get("models", {}))
    provider_count = len(nix_data.get("providers", {}))
    role_count = len(nix_data.get("roles", {}))

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

    print(f"OK — {model_count} models, {provider_count} providers, {role_count} roles")
    sys.exit(0)


if __name__ == "__main__":
    main()