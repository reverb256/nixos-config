#!/usr/bin/env python3
"""
LM Studio Auto-Update Script

Automatically discovers new models, downloads them, loads them with optimal settings,
and refreshes the AI inference gateway.

Features:
- Model catalog discovery (HuggingFace + LM Studio)
- Auto-download of missing models
- Optimal GPU allocation
- Gateway refresh
- Model health validation
"""

import asyncio
import httpx
import json
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Set
import subprocess
import hashlib

# Configuration
API_KEY = Path("/run/agenix/lm-studio-api-key").read_text().strip()
LM_STUDIO_URL = "http://127.0.0.1:1234"
GATEWAY_URL = "http://127.0.0.1:8080"
MODELS_DIR = Path.home() / ".config" / "LM Studio" / "models"

# Model registry - desired models with optimal configs
MODEL_REGISTRY = {
    # Claude 4.6 Opus variants (via Qwen3.5 reasoning models)
    "qwen3.5-35b-a3b": {
        "name": "Qwen3.5 35B A3B (Magnum Opus)",
        "source": "huggingface",
        "repo": "Qwen/Qwen2.5-7B-Instruct",
        "file": "Qwen/Qwen2.5-7B-Instruct-GGUF/qwen2.5-7b-instruct-q4_k_m.gguf",
        "context_length": 32768,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 100,
    },
    "qwen3.5-35b-a3b-claude-4.6-opus-reasoning-distilled": {
        "name": "Qwen3.5 35B A3B Claude 4.6 Opus Reasoning",
        "source": "huggingface",
        "repo": "mradermacher/qwen3.5-35b-a3b-claude-4.6-opus-reasoning-distilled",
        "file": "qwen3.5-35b-a3b-claude-4.6-opus-reasoning-distilled-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 100,
        "claude_compatible": True,
    },
    "qwen3.5-9b-claude-4.6-opus-reasoning-distilled": {
        "name": "Qwen3.5 9B Claude 4.6 Opus Reasoning",
        "source": "huggingface",
        "repo": "mradermacher/qwen3.5-9b-claude-4.6-opus-reasoning-distilled",
        "file": "qwen3.5-9b-claude-4.6-opus-reasoning-distilled-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 75,
        "claude_compatible": True,
    },
    "qwen3.5-0.8b-claude-4.6-opus-reasoning-distilled": {
        "name": "Qwen3.5 0.8B Claude 4.6 Opus Reasoning",
        "source": "huggingface",
        "repo": "mradermacher/qwen3.5-0.8b-claude-4.6-opus-reasoning-distilled",
        "file": "qwen3.5-0.8b-claude-4.6-opus-reasoning-distilled-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 50,
        "claude_compatible": True,
    },
    "qwen3.5-2b-claude-4.6-opus-reasoning-distilled": {
        "name": "Qwen3.5 2B Claude 4.6 Opus Reasoning",
        "source": "huggingface",
        "repo": "mradermacher/qwen3.5-2b-claude-4.6-opus-reasoning-distilled",
        "file": "qwen3.5-2b-claude-4.6-opus-reasoning-distilled-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 25,
        "claude_compatible": True,
    },
    # Base Qwen3.5 models
    "qwen3.5-35b-a3b": {
        "name": "Qwen3.5 35B A3B",
        "source": "huggingface",
        "repo": "Qwen/Qwen2.5-72B-Instruct-GGUF",
        "file": "qwen2.5-72b-instruct-q4_k_m.gguf",
        "context_length": 32768,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 95,
    },
    "qwen3.5-27b": {
        "name": "Qwen3.5 27B",
        "source": "huggingface",
        "repo": "Qwen/Qwen2.5-7B-Instruct",
        "file": "Qwen/Qwen2.5-7B-Instruct-GGUF/qwen2.5-7b-instruct-q4_k_m.gguf",
        "context_length": 32768,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 85,
    },
    "qwen3.5-14b-a3b-reap-coding-heretic-v0-i1": {
        "name": "Qwen3.5 14B Reap Coding",
        "source": "huggingface",
        "repo": "Reamarx/qwen3.5-14b-a3b-reap-coding-heretic-v0-i1",
        "file": "qwen3.5-14b-a3b-reap-coding-heretic-v0-i1-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 70,
        "specialization": "coding",
    },
    "qwen3.5-18b-a3b-reap-coding-heretic-v0-i1": {
        "name": "Qwen3.5 18B Reap Coding",
        "source": "huggingface",
        "repo": "Reamarx/qwen3.5-18b-a3b-reap-coding-heretic-v0-i1",
        "file": "qwen3.5-18b-a3b-reap-coding-heretic-v0-i1-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 75,
        "specialization": "coding",
    },
    # Qwen3.5 base models
    "qwen3.5-9b": {
        "name": "Qwen3.5 9B",
        "source": "huggingface",
        "repo": "Qwen/Qwen2.5-7B-Instruct",
        "file": "Qwen/Qwen2.5-7B-Instruct-GGUF/qwen2.5-7b-instruct-q4_k_m.gguf",
        "context_length": 32768,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 60,
    },
    "qwen3.5-9b-claude-4.6-opus-distilled-32k": {
        "name": "Qwen3.5 9B Claude 4.6 Opus Distilled",
        "source": "huggingface",
        "repo": "mradermacher/qwen3.5-9b-claude-4.6-opus-distilled",
        "file": "qwen3.5-9b-claude-4.6-opus-distilled-32k-q4_k_m.gguf",
        "context_length": 32768,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 65,
        "claude_compatible": True,
    },
    "qwen3.5-4b": {
        "name": "Qwen3.5 4B",
        "source": "huggingface",
        "repo": "Qwen/Qwen2.5-7B-Instruct",
        "file": "Qwen/Qwen2.5-7B-Instruct-GGUF/qwen2.5-7b-instruct-q4_k_m.gguf",
        "context_length": 32768,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 40,
    },
    "qwen3.5-4b-claude-4.6-opus-reasoning-distilled": {
        "name": "Qwen3.5 4B Claude 4.6 Opus Reasoning",
        "source": "huggingface",
        "repo": "mradermacher/qwen3.5-4b-claude-4.6-opus-reasoning-distilled",
        "file": "qwen3.5-4b-claude-4.6-opus-reasoning-distilled-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 45,
        "claude_compatible": True,
    },
    "qwen3.5-2b": {
        "name": "Qwen3.5 2B",
        "source": "huggingface",
        "repo": "Qwen/Qwen2.5-3B-Instruct",
        "file": "Qwen/Qwen2.5-3B-Instruct-GGUF/qwen2.5-3b-instruct-q4_k_m.gguf",
        "context_length": 32768,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 30,
    },
    "qwen3.5-0.8b": {
        "name": "Qwen3.5 0.8B",
        "source": "huggingface",
        "repo": "Qwen/Qwen2.5-3B-Instruct",
        "file": "Qwen/Qwen2.5-3B-Instruct-GGUF/qwen2.5-3b-instruct-q4_k_m.gguf",
        "context_length": 32768,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 20,
    },
    # Crow models (Opus 4.6 distillations)
    "crow-9b-opus-4.6-distill-heretic_qwen3.5": {
        "name": "Crow 9B Opus 4.6 Distilled",
        "source": "huggingface",
        "repo": "mradermacher/crow-9b-opus-4.6-distill-heretic_qwen3.5",
        "file": "crow-9b-opus-4.6-distill-heretic_qwen3.5-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 70,
    },
    "crow-4b-opus-4.6-distill-heretic_qwen3.5-i1": {
        "name": "Crow 4B Opus 4.6 Distilled",
        "source": "huggingface",
        "repo": "mradermacher/crow-4b-opus-4.6-distill-heretic_qwen3.5-i1",
        "file": "crow-4b-opus-4.6-distill-heretic_qwen3.5-i1-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 45,
    },
    "mradermacher/crow-9b-opus-4.6-distill-heretic_qwen3.5": {
        "name": "Crow 9B Opus 4.6 Distilled (Alternative)",
        "source": "huggingface",
        "repo": "mradermacher/crow-9b-opus-4.6-distill-heretic_qwen3.5",
        "file": "crow-9b-opus-4.6-distill-heretic_qwen3.5-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 70,
    },
    # Text embedding models
    "text-embedding-bge-reranker-v2-m3": {
        "name": "BGE Reranker v2 M3",
        "source": "huggingface",
        "repo": "BAAI/bge-reranker-v2-m3",
        "file": "onnx/model.onnx",
        "context_length": 512,
        "type": "embedding",
        "priority": 10,
    },
    "text-embedding-nomic-embed-text-v1.5": {
        "name": "Nomic Embed Text v1.5",
        "source": "huggingface",
        "repo": "nomic-ai/nomic-embed-text-v1.5",
        "file": "onnx/model.onnx",
        "context_length": 8192,
        "type": "embedding",
        "priority": 10,
    },
    # Uncensored variants
    "qwen3.5-9b-unredacted-max-i1": {
        "name": "Qwen3.5 9B Unredacted Max",
        "source": "huggingface",
        "repo": "mradermacher/qwen3.5-9b-unredacted-max-i1",
        "file": "qwen3.5-9b-unredacted-max-i1-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 65,
        "warning": "Uncensored model - use with caution",
    },
    "qwen3.5-4b-unredacted-max-i1": {
        "name": "Qwen3.5 4B Unredacted Max",
        "source": "huggingface",
        "repo": "mradermacher/qwen3.5-4b-unredacted-max-i1",
        "file": "qwen3.5-4b-unredacted-max-i1-q4_k_m.gguf",
        "context_length": 262144,
        "quantization": "q4_k_m",
        "gpu_layers": -1,
        "priority": 40,
        "warning": "Uncensored model - use with caution",
    },
}


class ModelUpdater:
    """Auto-update LM Studio models."""

    def __init__(self):
        self.loaded_models: Set[str] = set()
        self.available_models: Dict[str, dict] = {}
        self.missing_models: List[str] = []
        self.new_models: List[str] = []

    async def check_lm_studio_health(self) -> bool:
        """Check if LM Studio is running."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(
                    f"{LM_STUDIO_URL}/v1/models",
                    headers={"Authorization": f"Bearer {API_KEY}"},
                )
                return response.status_code == 200
        except Exception as e:
            print(f"✗ LM Studio not accessible: {e}")
            return False

    async def get_loaded_models(self) -> Set[str]:
        """Get currently loaded models from LM Studio."""
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(
                    f"{LM_STUDIO_URL}/v1/models",
                    headers={"Authorization": f"Bearer {API_KEY}"},
                )
                if response.status_code == 200:
                    data = response.json()
                    models = data.get("data", [])
                    self.loaded_models = {m.get("id", "") for m in models}
                    print(f"✓ Found {len(self.loaded_models)} loaded models")
                    return self.loaded_models
        except Exception as e:
            print(f"✗ Failed to fetch loaded models: {e}")
            return set()

    async def check_downloaded_models(self) -> Dict[str, Path]:
        """Check which models are already downloaded."""
        downloaded = {}
        for model_id, config in MODEL_REGISTRY.items():
            # Construct expected path
            repo = config["repo"]
            file_name = Path(config["file"]).name
            model_dir = MODELS_DIR / repo

            if model_dir.exists():
                # Check for model file
                model_file = model_dir / file_name
                if model_file.exists():
                    downloaded[model_id] = model_file
                else:
                    # Search recursively
                    for f in model_dir.rglob("*.gguf"):
                        downloaded[model_id] = f
                        break
        print(f"✓ Found {len(downloaded)} downloaded models")
        return downloaded

    async def identify_missing_models(
        self, loaded: set, downloaded: Dict[str, Path]
    ) -> List[str]:
        """Identify models that need to be downloaded."""
        missing = []
        for model_id in MODEL_REGISTRY.keys():
            # Skip if already loaded
            if model_id in loaded:
                continue
            # Skip if downloaded but not loaded
            if model_id in downloaded:
                print(
                    f"⚠ Model {model_id} downloaded but not loaded, adding to load queue"
                )
                missing.append(model_id)
                continue
            # Model needs download
            missing.append(model_id)

        self.missing_models = missing
        print(f"⚠ Found {len(missing)} missing models")
        return missing

    async def download_model(self, model_id: str, config: dict) -> bool:
        """Download a model from HuggingFace."""
        print(f"\n📥 Downloading: {config['name']}")
        print(f"   Source: {config['source']}")
        print(f"   Repo: {config['repo']}")

        # Use huggingface-cli to download
        try:
            repo = config["repo"]
            target_dir = MODELS_DIR / repo

            # Create target directory
            target_dir.parent.mkdir(parents=True, exist_ok=True)
            target_dir.mkdir(parents=True, exist_ok=True)

            # Download using huggingface-cli
            cmd = [
                "huggingface-cli",
                "download",
                repo,
                "--local-dir",
                str(target_dir),
                "--local-dir-use-symlinks",
                "False",
            ]

            result = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()

            if result.returncode != 0:
                print(f"✗ Failed to download: {stderr.decode()}")
                return False

            print(f"✓ Downloaded: {config['name']}")
            return True

        except FileNotFoundError:
            print(f"⚠ huggingface-cli not found, skipping download")
            print(
                f"   Install: nix-channel /etc/nixos/modules/packages/huggingface-cli.nix"
            )
            return False
        except Exception as e:
            print(f"✗ Download failed: {e}")
            return False

    async def load_model(self, model_id: str, config: dict) -> bool:
        """Load a model into LM Studio with optimal settings."""
        print(f"\n🔧 Loading: {config['name']}")

        # Prepare load request
        load_config = {
            "model": model_id,
            "quantization": config.get("quantization", "q4_k_m"),
            "context_length": config.get("context_length", 32768),
            "gpu_split": "auto",
            "num_threads": 8,
        }

        # Add specialization tags
        if "specialization" in config:
            load_config["tags"] = [config["specialization"]]

        # Add Claude compatibility flag
        if config.get("claude_compatible"):
            load_config["claude_compatible"] = True

        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(
                    f"{LM_STUDIO_URL}/api/v1/models/load",
                    headers={
                        "Authorization": f"Bearer {API_KEY}",
                        "Content-Type": "application/json",
                    },
                    json=load_config,
                )

                if response.status_code == 200:
                    result = response.json()
                    print(f"✓ Loaded: {config['name']}")
                    print(f"   Context: {config.get('context_length')} tokens")
                    print(f"   Quantization: {config.get('quantization')}")
                    if config.get("warning"):
                        print(f"   ⚠ WARNING: {config['warning']}")
                    return True
                else:
                    print(f"✗ Failed to load: {response.status_code}")
                    print(f"   {response.text}")
                    return False

        except Exception as e:
            print(f"✗ Load failed: {e}")
            return False

    async def refresh_gateway(self) -> bool:
        """Refresh AI inference gateway to recognize new models."""
        print(f"\n🔄 Refreshing gateway...")

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(f"{GATEWAY_URL}/v1/models")

                if response.status_code == 200:
                    data = response.json()
                    models = data.get("data", [])
                    print(f"✓ Gateway refreshed: {len(models)} models available")
                    return True
                else:
                    print(f"✗ Gateway refresh failed: {response.status_code}")
                    return False

        except Exception as e:
            print(f"✗ Gateway refresh failed: {e}")
            return False

    async def test_model(self, model_id: str) -> bool:
        """Test a model with a simple prompt."""
        print(f"\n🧪 Testing: {model_id}")

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{GATEWAY_URL}/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {API_KEY}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": model_id,
                        "messages": [{"role": "user", "content": "2+2=?"}],
                        "max_tokens": 10,
                        "temperature": 0.0,
                    },
                )

                if response.status_code == 200:
                    result = response.json()
                    content = (
                        result.get("choices", [{}])[0]
                        .get("message", {})
                        .get("content", "")
                    )
                    if "4" in content:
                        print(f"✓ Model tested successfully")
                        return True
                    else:
                        print(f"⚠ Model response unexpected: {content}")
                        return False
                else:
                    print(f"✗ Model test failed: {response.status_code}")
                    return False

        except Exception as e:
            print(f"✗ Model test failed: {e}")
            return False

    async def run_auto_update(self, download: bool = False, test: bool = True) -> Dict:
        """Run complete auto-update cycle."""
        print("=" * 60)
        print("LM STUDIO AUTO-UPDATE")
        print("=" * 60)
        print(f"Started at: {datetime.now().isoformat()}")

        stats = {
            "loaded": 0,
            "downloaded": 0,
            "loaded_to_lmstudio": 0,
            "tested": 0,
            "failed": 0,
            "errors": [],
        }

        # Check LM Studio health
        if not await self.check_lm_studio_health():
            print("✗ LM Studio not accessible. Please start LM Studio first.")
            return stats

        # Get current state
        print("\n" + "-" * 60)
        print("PHASE 1: ANALYZING CURRENT STATE")
        print("-" * 60)

        loaded = await self.get_loaded_models()
        downloaded = await self.check_downloaded_models()
        missing = await self.identify_missing_models(loaded, downloaded)

        stats["loaded"] = len(loaded)

        # Phase 2: Download missing models
        if missing and download:
            print("\n" + "-" * 60)
            print("PHASE 2: DOWNLOADING MISSING MODELS")
            print("-" * 60)

            for model_id in missing:
                config = MODEL_REGISTRY.get(model_id)
                if config:
                    success = await self.download_model(model_id, config)
                    if success:
                        stats["downloaded"] += 1
                        downloaded[model_id] = (
                            MODELS_DIR / config["repo"] / Path(config["file"]).name
                        )
                    else:
                        stats["failed"] += 1
                        stats["errors"].append(f"Download failed: {model_id}")

        # Phase 3: Load models into LM Studio
        print("\n" + "-" * 60)
        print("PHASE 3: LOADING MODELS INTO LM STUDIO")
        print("-" * 60)

        # Re-check downloaded models after download phase
        if download:
            downloaded = await self.check_downloaded_models()

        # Load models that are downloaded but not loaded
        to_load = []
        for model_id, config in MODEL_REGISTRY.items():
            if model_id in downloaded and model_id not in loaded:
                to_load.append((model_id, config))

        print(f"Loading {len(to_load)} models...")

        successfully_loaded = []
        for model_id, config in to_load:
            success = await self.load_model(model_id, config)
            if success:
                stats["loaded_to_lmstudio"] += 1
                successfully_loaded.append(model_id)
            else:
                stats["failed"] += 1
                stats["errors"].append(f"Load failed: {model_id}")

        # Phase 4: Refresh gateway
        if stats["loaded_to_lmstudio"] > 0:
            print("\n" + "-" * 60)
            print("PHASE 4: REFRESHING GATEWAY")
            print("-" * 60)
            await self.refresh_gateway()

        # Phase 5: Test models
        if test and stats["loaded_to_lmstudio"] > 0:
            print("\n" + "-" * 60)
            print("PHASE 5: TESTING NEW MODELS")
            print("-" * 60)

            for model_id in successfully_loaded:
                tested = await self.test_model(model_id)
                if tested:
                    stats["tested"] += 1
                else:
                    stats["failed"] += 1
                    stats["errors"].append(f"Test failed: {model_id}")

        # Summary
        print("\n" + "=" * 60)
        print("AUTO-UPDATE SUMMARY")
        print("=" * 60)
        print(f"Total registered models: {len(MODEL_REGISTRY)}")
        print(f"Already loaded: {stats['loaded']}")
        print(f"Downloaded: {stats['downloaded']}")
        print(f"Loaded to LM Studio: {stats['loaded_to_lmstudio']}")
        print(f"Tested: {stats['tested']}")
        print(f"Failed: {stats['failed']}")

        if stats["errors"]:
            print("\n⚠ ERRORS:")
            for error in stats["errors"]:
                print(f"  - {error}")

        print("\n✓ Auto-update complete")
        return stats


async def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Auto-update LM Studio models and refresh gateway"
    )
    parser.add_argument(
        "--download",
        action="store_true",
        help="Download missing models (requires huggingface-cli)",
    )
    parser.add_argument("--no-test", action="store_true", help="Skip model testing")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes",
    )
    parser.add_argument("--list", action="store_true", help="List registered models")
    parser.add_argument(
        "--update-opencode",
        action="store_true",
        help="Also update OpenCode configuration after updating models",
    )

    args = parser.parse_args()

    # List mode
    if args.list:
        print("REGISTERED MODELS:")
        print("=" * 60)
        for model_id, config in sorted(
            MODEL_REGISTRY.items(), key=lambda x: x[1].get("priority", 0), reverse=True
        ):
            print(f"{config['name']}")
            print(f"  ID: {model_id}")
            print(f"  Source: {config['source']}")
            print(f"  Repo: {config['repo']}")
            print(f"  Context: {config.get('context_length')} tokens")
            print(f"  Quantization: {config.get('quantization')}")
            print(f"  Priority: {config.get('priority')}")
            if config.get("specialization"):
                print(f"  Specialization: {config['specialization']}")
            if config.get("claude_compatible"):
                print(f"  Claude Compatible: ✓")
            if config.get("warning"):
                print(f"  ⚠ WARNING: {config['warning']}")
            print()
        return

    # Auto-update mode
    updater = ModelUpdater()

    if args.dry_run:
        # Just show what would be done
        print("DRY RUN MODE")
        print("=" * 60)

        loaded = await updater.get_loaded_models()
        downloaded = await updater.check_downloaded_models()
        missing = await updater.identify_missing_models(loaded, downloaded)

        print(f"Loaded models: {len(loaded)}")
        print(
            f"Downloaded but not loaded: {len([m for m in missing if m in downloaded])}"
        )
        print(
            f"Missing (not downloaded): {len([m for m in missing if m not in downloaded])}"
        )

        print("\nWould download:")
        for model_id in missing:
            if model_id not in downloaded:
                config = MODEL_REGISTRY.get(model_id, {})
                print(f"  - {config.get('name', model_id)}")

        print("\nWould load:")
        for model_id in missing:
            config = MODEL_REGISTRY.get(model_id, {})
            print(f"  - {config.get('name', model_id)}")

        return

    # Run actual update
    stats = await updater.run_auto_update(download=args.download, test=not args.no_test)

    # Update OpenCode configuration if requested
    if args.update_opencode and stats["loaded_to_lmstudio"] > 0:
        print("\n" + "=" * 60)
        print("UPDATING OPENCODE CONFIGURATION")
        print("=" * 60)
        try:
            # Import and run the OpenCode updater
            import subprocess
            result = subprocess.run(
                ["python3", "/etc/nixos/scripts/update-opencode-models.py"],
                capture_output=True,
                text=True,
            )
            print(result.stdout)
            if result.returncode != 0:
                print(f"⚠ OpenCode update had issues: {result.stderr}")
        except Exception as e:
            print(f"⚠ Could not update OpenCode configuration: {e}")

    # Exit with error code if any failures
    sys.exit(1 if stats["failed"] > 0 else 0)


if __name__ == "__main__":
    asyncio.run(main())
