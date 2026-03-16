#!/usr/bin/env python3
"""
OpenCode Model Auto-Update Script

Queries the AI inference gateway for available models and updates the
OpenCode configuration with proper provider settings.

Usage:
    python3 update-opencode-models.py [--dry-run] [--list]
"""

import argparse
import json
import sys
import urllib.request
import urllib.error
from datetime import datetime
from typing import Dict, List, Any, Optional
from pathlib import Path

# Configuration
GATEWAY_URL = "http://127.0.0.1:8080"
LM_STUDIO_API_KEY = Path("/run/agenix/lm-studio-api-key")
OPENCODE_USER_CONFIG = Path.home() / ".config" / "opencode" / "opencode.json"
OPENCODE_ROOT_CONFIG = Path("/root/.config/opencode/opencode.json")

# Model categorization based on oh-my-opencode built-in categories
# Built-in categories: quick, unspecified-low, unspecified-high, visual-engineering, artistry, ultrabrain, deep, writing
# Source: https://github.com/code-yeongyu/oh-my-opencode

CATEGORY_DESCRIPTIONS = {
    "quick": "Simple, fast tasks (config, scaffolding, simple implementation)",
    "unspecified-low": "Medium complexity tasks with clear requirements",
    "unspecified-high": "High uncertainty tasks requiring high quality models",
    "visual-engineering": "Frontend UI/UX, design systems",
    "artistry": "Creative work, copywriting, documentation",
    "ultrabrain": "Strategic thinking, complex problem solving",
    "deep": "Complex business logic, algorithms, architecture",
    "writing": "Documentation, prose, technical writing",
}

# Pattern matching for categories
MODEL_PATTERNS = {
    # ultrabrain - highest reasoning capability for strategic thinking
    "ultrabrain": ["35b", "27b", "a3b", "opus", "reasoning"],

    # deep - complex architecture and algorithms
    "deep": ["18b", "14b", "reap", "coding", "heretic"],

    # unspecified-high - high quality for uncertain tasks
    "unspecified-high": ["9b-opus", "crow-9b-opus"],

    # quick - fast, lightweight tasks
    "quick": ["4b", "2b", "0.8b", "tiny", "fast"],

    # writing - documentation and prose
    "writing": ["unredacted", "writing", "prose"],

    # visual-engineering - UI/UX (requires vision models - use ZAI)
    "visual-engineering": ["vision", "multimodal", "vl"],

    # artistry - creative work (requires creative models - use ZAI)
    "artistry": ["creative", "artistic"],
}

# Model output token limits based on parameter count
PARAMETER_OUTPUT_LIMITS = {
    # 35B models - highest output
    "35b": 32000,
    # 27B models
    "27b": 24000,
    # 18B models
    "18b": 20000,
    # 14B models
    "14b": 18000,
    # 9B models
    "9b": 16000,
    # 4B models
    "4b": 8000,
    # 2B models
    "2b": 4000,
    # 0.8B models
    "0.8b": 4000,
}


def categorize_model(model_id: str) -> str:
    """Categorize a model for oh-my-opencode.

    Built-in oh-my-opencode categories:
    - quick: Simple, fast tasks (config, scaffolding)
    - unspecified-low: Medium complexity with clear requirements
    - unspecified-high: High uncertainty, needs high quality
    - ultrabrain: Strategic thinking, complex problems
    - deep: Complex logic, algorithms, architecture
    - visual-engineering: UI/UX, design (requires vision models)
    - artistry: Creative work (requires creative models)
    - writing: Documentation, prose

    Note: Local LM Studio models don't have vision capabilities,
    so visual-engineering/artistry should use ZAI remote models.
    """
    model_lower = model_id.lower()

    # Check for ultrabrain (strategic reasoning, highest capability)
    for pattern in MODEL_PATTERNS["ultrabrain"]:
        if pattern in model_lower:
            return "ultrabrain"

    # Check for deep (complex algorithms, coding specialization)
    for pattern in MODEL_PATTERNS["deep"]:
        if pattern in model_lower:
            return "deep"

    # Check for unspecified-high (high quality, 9B Opus variants)
    for pattern in MODEL_PATTERNS["unspecified-high"]:
        if pattern in model_lower:
            return "unspecified-high"

    # Check for writing (unredacted = less filtered, better for prose)
    for pattern in MODEL_PATTERNS["writing"]:
        if pattern in model_lower:
            return "writing"

    # Check for quick (small, fast models)
    for pattern in MODEL_PATTERNS["quick"]:
        if pattern in model_lower:
            return "quick"

    # Default: 9B+ general models get unspecified-low
    for size in ["9b", "14b", "18b"]:
        if size in model_lower:
            return "unspecified-low"

    # Fallback to quick for anything else
    return "quick"


def get_output_limit(model_id: str) -> int:
    """Determine output token limit based on model size."""
    model_lower = model_id.lower()

    # Find matching parameter size
    for size, limit in PARAMETER_OUTPUT_LIMITS.items():
        if size in model_lower:
            return limit

    # Default fallback
    if "35b" in model_lower or "27b" in model_lower:
        return 24000
    elif "9b" in model_lower or "14b" in model_lower or "18b" in model_lower:
        return 16000
    elif "4b" in model_lower:
        return 8000
    else:
        return 4000


def get_model_description(model_id: str, category: str) -> str:
    """Generate a human-readable description for a model based on its category."""
    model_lower = model_id.lower()
    base_name = model_id.replace("mradermacher/", "").replace("qwen3.5-", "Qwen 3.5 ")
    base_name = base_name.replace("-", " ").replace("@", " (").strip()

    # Category-specific descriptions
    if category == "ultrabrain":
        if "35b" in model_lower or "a3b" in model_lower:
            return f"{base_name} - Strategic thinking and complex problem solving"
        return f"{base_name} - Strategic reasoning"

    elif category == "deep":
        if "reap" in model_lower or "coding" in model_lower:
            return f"{base_name} - Code generation and architecture"
        if "18b" in model_lower:
            return f"{base_name} - Complex algorithms and logic"
        return f"{base_name} - Deep technical work"

    elif category == "unspecified-high":
        return f"{base_name} - High quality for complex tasks"

    elif category == "unspecified-low":
        if "9b" in model_lower:
            return f"{base_name} - Medium complexity tasks"
        return f"{base_name} - General development"

    elif category == "writing":
        if "unredacted" in model_lower:
            return f"{base_name} - Documentation and prose (less filtered)"
        return f"{base_name} - Writing and documentation"

    elif category == "quick":
        if "0.8b" in model_lower or "2b" in model_lower:
            return f"{base_name} - Ultra-fast for simple queries"
        return f"{base_name} - Fast for quick tasks"

    # Fallback
    return f"{base_name} - Local LM Studio model"


def generate_model_config(model_id: str) -> Dict[str, Any]:
    """Generate OpenCode configuration for a single model."""
    category = categorize_model(model_id)
    output_limit = get_output_limit(model_id)
    description = get_model_description(model_id, category)

    # Most modern Qwen models support 256K context
    context_limit = 262144

    # Generate a clean name
    clean_name = model_id
    clean_name = clean_name.replace("mradermacher/", "")
    clean_name = clean_name.replace("qwen3.5-", "Qwen 3.5 ")
    clean_name = clean_name.replace("-", " ")
    clean_name = clean_name.replace("@", " (")
    clean_name = clean_name.replace("q4_k_m", "Q4_K_M")
    clean_name = clean_name.replace("q4_k_s", "Q4_K_S")
    clean_name = clean_name.replace("q8_0", "Q8_0")

    return {
        "name": clean_name.title(),
        "description": description,
        "limit": {
            "context": context_limit,
            "output": output_limit,
        },
        "category": category,
    }


def select_default_model(model_ids: List[str]) -> str:
    """Select the best default model from available models."""
    if not model_ids:
        return "gateway/qwen3.5-9b"

    # Priority order for default model
    priorities = []

    for model_id in model_ids:
        model_lower = model_id.lower()
        priority = 0

        # 35B A3B Opus - highest priority
        if "35b" in model_lower and "a3b" in model_lower and "opus" in model_lower:
            priority = 100
        # 27B Opus
        elif "27b" in model_lower and "opus" in model_lower:
            priority = 95
        # 35B A3B
        elif "35b" in model_lower and "a3b" in model_lower:
            priority = 90
        # 18B Reap
        elif "18b" in model_lower and "reap" in model_lower:
            priority = 85
        # 14B Opus
        elif "14b" in model_lower and "opus" in model_lower:
            priority = 80
        # 9B Opus
        elif "9b" in model_lower and "opus" in model_lower:
            priority = 75
        # 9B general
        elif "9b" in model_lower:
            priority = 60
        # 4B
        elif "4b" in model_lower:
            priority = 40

        priorities.append((priority, model_id))

    if priorities:
        priorities.sort(reverse=True)
        return f"gateway/{priorities[0][1]}"

    return f"gateway/{model_ids[0]}"


def select_small_model(model_ids: List[str]) -> str:
    """Select the best small/fast model from available models."""
    if not model_ids:
        return "gateway/qwen3.5-4b"

    # For small model, prefer fast lightweight models
    priorities = []

    for model_id in model_ids:
        model_lower = model_id.lower()
        priority = 0

        # 0.8B - fastest
        if "0.8b" in model_lower:
            priority = 100
        # 2B
        elif "2b" in model_lower:
            priority = 90
        # 4B
        elif "4b" in model_lower:
            priority = 80

        priorities.append((priority, model_id))

    if priorities:
        priorities.sort(reverse=True)
        return f"gateway/{priorities[0][1]}"

    return f"gateway/{model_ids[0]}"


def fetch_gateway_models() -> List[str]:
    """Fetch available models from the AI inference gateway."""
    try:
        url = f"{GATEWAY_URL}/v1/models"
        with urllib.request.urlopen(url, timeout=10) as response:
            data = json.loads(response.read().decode())
            models = data.get("data", [])
            model_ids = [m.get("id", "") for m in models]
            # Filter out embedding models and special models
            model_ids = [
                m for m in model_ids
                if not m.startswith("text-embedding-")
                and not m.startswith("bge-")
                and not m.startswith("nomic-")
            ]
            return model_ids
    except urllib.error.HTTPError as e:
        print(f"✗ Gateway returned status: {e.code}")
        return []
    except Exception as e:
        print(f"✗ Failed to fetch gateway models: {e}")
        return []


def read_api_key() -> Optional[str]:
    """Read LM Studio API key from file."""
    try:
        return LM_STUDIO_API_KEY.read_text().strip()
    except Exception:
        return None


def generate_opencode_config(
    model_ids: List[str],
    existing_config: Optional[Dict] = None,
    zai_api_key: Optional[str] = None,
) -> Dict[str, Any]:
    """Generate complete OpenCode configuration."""

    # Generate models configuration
    models_config = {}
    for model_id in model_ids:
        models_config[model_id] = generate_model_config(model_id)

    # Build base configuration
    config = {
        "$schema": "https://opencode.ai/config.json",
        "provider": {
            "gateway": {
                "npm": "@ai-sdk/openai-compatible",
                "name": "AI Gateway v2 (Local)",
                "options": {
                    "baseURL": f"{GATEWAY_URL}/v1",
                    "apiKey": "{env:LM_STUDIO_API_KEY}",
                    "timeout": 300000,
                    "maxRetries": 3,
                },
                "models": models_config,
            }
        },
    }

    # Add ZAI provider if API key is available or exists in current config
    if zai_api_key or (existing_config and "zai-coding-plan" in existing_config.get("provider", {})):
        config["provider"]["zai-coding-plan"] = {
            "options": {
                "apiKey": "{env:ZAI_API_KEY}",
            }
        }

    # Select default and small models
    default_model = select_default_model(model_ids)
    small_model = select_small_model(model_ids)

    config["model"] = default_model
    config["small_model"] = small_model

    # Preserve existing configurations
    if existing_config:
        # Preserve MCP servers if they exist
        if "mcp" in existing_config:
            config["mcp"] = existing_config["mcp"]

        # Preserve plugins if they exist
        if "plugin" in existing_config:
            config["plugin"] = existing_config["plugin"]

        # Preserve agent configurations if they exist
        if "agent" in existing_config:
            config["agent"] = existing_config["agent"]

    return config


def update_opencode_config(
    dry_run: bool = False,
) -> bool:
    """Update OpenCode configuration with gateway models."""

    print("=" * 60)
    print("OPENCODE MODEL AUTO-UPDATE")
    print("=" * 60)
    print(f"Started at: {datetime.now().isoformat()}")

    # Fetch available models
    print("\n📡 Fetching models from gateway...")
    model_ids = fetch_gateway_models()

    if not model_ids:
        print("✗ No models found in gateway")
        return False

    print(f"✓ Found {len(model_ids)} models in gateway")

    # Read existing configuration
    existing_config = None
    if OPENCODE_USER_CONFIG.exists():
        try:
            with open(OPENCODE_USER_CONFIG, "r") as f:
                existing_config = json.load(f)
            print(f"✓ Read existing configuration from {OPENCODE_USER_CONFIG}")
        except Exception as e:
            print(f"⚠ Could not read existing config: {e}")

    # Read ZAI API key (for reference only - we use env var in config)
    zai_api_key = read_api_key()

    # Generate new configuration
    print("\n🔧 Generating OpenCode configuration...")
    new_config = generate_opencode_config(model_ids, existing_config, zai_api_key)

    # Print summary
    print("\n📊 Configuration Summary:")
    print(f"  Gateway models: {len(model_ids)}")
    print(f"  Default model: {new_config['model']}")
    print(f"  Small model: {new_config.get('small_model', 'N/A')}")
    print(f"  Providers: {', '.join(new_config['provider'].keys())}")

    if dry_run:
        print("\n📄 Dry run - configuration that would be written:")
        print(json.dumps(new_config, indent=2))
        return True

    # Write configurations
    print("\n💾 Writing configuration files...")

    success = True

    # User config
    try:
        OPENCODE_USER_CONFIG.parent.mkdir(parents=True, exist_ok=True)
        with open(OPENCODE_USER_CONFIG, "w") as f:
            json.dump(new_config, f, indent=2)
        print(f"✓ Updated: {OPENCODE_USER_CONFIG}")
    except Exception as e:
        print(f"✗ Failed to write user config: {e}")
        success = False

    # Root config
    try:
        OPENCODE_ROOT_CONFIG.parent.mkdir(parents=True, exist_ok=True)
        with open(OPENCODE_ROOT_CONFIG, "w") as f:
            json.dump(new_config, f, indent=2)
        print(f"✓ Updated: {OPENCODE_ROOT_CONFIG}")
    except Exception as e:
        print(f"✗ Failed to write root config: {e}")
        success = False

    # Sync to cluster nodes
    if success:
        print("\n🔄 Syncing to cluster nodes...")
        sync_to_cluster(new_config)

    return success


def sync_to_cluster(config: Dict[str, Any]) -> None:
    """Sync configuration to cluster nodes (forge, nexus, sentry)."""
    import subprocess
    import tempfile

    nodes = ["forge", "nexus", "sentry"]

    for node in nodes:
        try:
            # Write config to a temporary file
            with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp_file:
                json.dump(config, tmp_file, indent=2)
                tmp_path = tmp_file.name

            # Copy to user directory
            result = subprocess.run(
                [
                    "scp",
                    "-o",
                    "ConnectTimeout=5",
                    "-q",
                    tmp_path,
                    f"j_kro@{node}:/home/j_kro/.config/opencode/opencode.json",
                ],
                capture_output=True,
                timeout=10,
            )

            # Clean up temp file
            try:
                Path(tmp_path).unlink()
            except:
                pass

            if result.returncode == 0:
                # Copy to root directory via sudo
                subprocess.run(
                    [
                        "ssh",
                        "-o",
                        "ConnectTimeout=5",
                        f"j_kro@{node}",
                        "sudo",
                        "cp",
                        "/home/j_kro/.config/opencode/opencode.json",
                        "/root/.config/opencode/opencode.json",
                    ],
                    capture_output=True,
                    timeout=10,
                )
                print(f"  ✓ {node} synced")
            else:
                print(f"  ⚠ {node} sync failed")
        except Exception as e:
            print(f"  ⚠ {node} sync error: {e}")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Update OpenCode configuration with gateway models"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show configuration without writing files",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available models from gateway",
    )

    args = parser.parse_args()

    # List mode
    if args.list:
        print("GATEWAY MODELS:")
        print("=" * 60)
        model_ids = fetch_gateway_models()
        for model_id in sorted(model_ids):
            config = generate_model_config(model_id)
            print(f"\n{model_id}")
            print(f"  Name: {config['name']}")
            print(f"  Category: {config['category']}")
            print(f"  Context: {config['limit']['context']:,} tokens")
            print(f"  Output: {config['limit']['output']:,} tokens")
        return

    # Update mode
    success = update_opencode_config(dry_run=args.dry_run)

    if success:
        print("\n✓ OpenCode configuration updated successfully")
        sys.exit(0)
    else:
        print("\n✗ Failed to update OpenCode configuration")
        sys.exit(1)


if __name__ == "__main__":
    main()
