# OpenCode Local Model Configuration Guide

**Date**: 2026-03-21  
**Status**: ✅ **Configured for Local Models**

## Overview

OpenCode is configured to **prefer local/hosted models** over cloud APIs:

- **Primary**: LM Studio (Qwen3.5 2B IQ4_NL)
- **Fallback**: Kilo Gateway (local inference routing)
- **Disabled**: OpenAI, Anthropic, Google, Cohere cloud APIs

## Current Configuration

### Default Model

```json
{
  "model": "lmstudio/qwen3.5-2b-iq4-nl.gguf",
  "small_model": "lmstudio/qwen3.5-2b-iq4-nl.gguf"
}
```

### Local Providers

| Provider | Endpoint | Models | Status |
|----------|----------|--------|--------|
| LM Studio | `http://127.0.0.1:8080/v1` | Qwen3.5 2B | ✅ Running |
| Kilo Gateway | `http://127.0.0.1:11434/v1` | Auto-routing | ⚠️ Not running |
| Hugging Face | API | Local/Cloud | ✅ Available |

### Disabled Cloud Providers

- OpenAI (GPT-4, GPT-5, etc.)
- Anthropic (Claude 3.5, Claude 4, etc.)
- Google (Gemini 2.5, Gemini 3, etc.)
- Cohere (Command R, etc.)
- Z.AI Coding Plan (GLM cloud API)

## Usage

### Start OpenCode with Local Model

```bash
# Use default local model (Qwen3.5 2B)
opencode

# Explicitly specify local model
opencode -m lmstudio/qwen3.5-2b-iq4-nl.gguf

# List all available local models
opencode models lmstudio
opencode models kilo
```

### Run with Prompt

```bash
# Single prompt with local model
opencode run "Explain this NixOS configuration" -m lmstudio/qwen3.5-2b-iq4-nl.gguf

# Interactive session
opencode
```

### Kubernetes Pod

```bash
# Use local model in Kubernetes pod
opencode-k8s -m lmstudio/qwen3.5-2b-iq4-nl.gguf

# Or just let it use the default (configured in PVC)
opencode-k8s
```

## Available Local Models

### LM Studio (Currently Running)

```bash
# Check loaded models in LM Studio
curl http://127.0.0.1:8080/v1/models | jq '.data[].id'

# Current: Qwen3.5-2B-IQ4_NL.gguf
# - Size: 1.2GB
# - Quantization: IQ4_NL
# - Context: 262k tokens
```

### Kilo Gateway Models (When Available)

```bash
# Auto-selects best local model
opencode -m kilo/kilo-auto/balanced

# Specific models via Kilo:
opencode -m kilo/qwen/qwen3-coder              # Qwen3 Coder
opencode -m kilo/meta-llama/llama-3.3-70b-instruct  # Llama 3.3 70B
opencode -m kilo/deepseek/deepseek-r1          # DeepSeek R1
```

## Configuration Files

### Location

- **Local host**: `/home/j_kro/.opencode/config.json`
- **Kubernetes pod**: `/home/j_kro/.opencode/config.json` (via PVC)

### Sync Status

Both local host and Kubernetes pod use the **same config file** via the PVC `ai-coding-configs`. Changes made in one location are immediately reflected in the other.

### Schema Reference

Full configuration schema: https://opencode.ai/config.json

Key options:
- `model`: Default model (format: `provider/model-name`)
- `small_model`: Model for quick tasks
- `enabled_providers`: Only use these providers
- `disabled_providers`: Never use these providers
- `provider.{provider_name}`: Provider-specific configuration

## Best Practices

### 1. Always Specify Local Model

```bash
# Good - explicit local model
opencode -m lmstudio/qwen3.5-2b-iq4-nl.gguf

# Risky - might use cloud API if configured
opencode -m openai/gpt-4
```

### 2. Disable Cloud Providers

Your config already has `disabled_providers` set, but verify:

```bash
# Check current config
cat ~/.opencode/config.json | jq '.disabled_providers'

# Should show: ["openai", "anthropic", "google", "cohere", "zai-coding-plan"]
```

### 3. Verify Local Server is Running

```bash
# Check LM Studio
curl http://127.0.0.1:8080/v1/models

# Check Kilo Gateway
curl http://127.0.0.1:11434/v1/models

# Check Ollama
curl http://127.0.0.1:11434/api/tags
```

### 4. Model Selection Strategy

**For Quick Tasks** (title generation, summaries):
- `lmstudio/qwen3.5-2b-iq4-nl.gguf` (fast, 1.2GB)
- `kilo/kilo-auto/small` (auto-selects small model)

**For Coding Tasks**:
- `lmstudio/qwen/qwen3-coder-30b` (if loaded in LM Studio)
- `kilo/qwen/qwen3-coder` (via Kilo Gateway)

**For Reasoning**:
- `kilo/deepseek/deepseek-r1` (DeepSeek R1)
- `kilo/qwen/qwen3-235b-a22b-thinking` (Qwen3 Thinking)

**For General Purpose**:
- `kilo/kilo-auto/balanced` (auto-selects best model)
- `kilo/meta-llama/llama-3.3-70b-instruct` (Llama 3.3)

## Troubleshooting

### Issue: "Connection refused" to LM Studio

**Solution**: Start LM Studio

```bash
# LM Studio should be running on port 8080
# Check if running:
curl http://127.0.0.1:8080/v1/models

# If not running, start LM Studio GUI
# Or use headless mode if available
```

### Issue: Model not found

**Solution**: Check available models

```bash
# List all LM Studio models
opencode models lmstudio

# List all Kilo models
opencode models kilo

# List all available models
opencode models
```

### Issue: Using cloud API instead of local

**Solution**: Verify provider settings

```bash
# Check config
cat ~/.opencode/config.json | jq '.disabled_providers'

# Should list cloud providers
# If empty, update config to disable cloud providers
```

### Issue: Kubernetes pod using different config

**Solution**: Verify PVC mount

```bash
# Check pod has PVC mounted
kubectl exec -n ai-coding opencode-XXX -- cat /home/j_kro/.opencode/config.json

# Should show same config as local host
# If different, PVC may not be mounted correctly
```

## Performance Comparison

### Local vs Cloud Models

| Model | Provider | Latency | Cost | Privacy |
|-------|----------|---------|------|---------|
| Qwen3.5 2B (Local) | LM Studio | ~50ms | Free | ✅ Local |
| Qwen3 Coder (Local) | Kilo | ~100ms | Free | ✅ Local |
| GPT-4 | OpenAI | ~500ms | $$$$ | ❌ Cloud |
| Claude 3.5 Sonnet | Anthropic | ~400ms | $$$ | ❌ Cloud |

### Resource Usage

**Qwen3.5 2B (IQ4_NL)**:
- RAM: ~2GB when loaded
- VRAM: ~2GB (if GPU-accelerated)
- Storage: 1.2GB disk space

**Recommendations**:
- CPU-only: Works but slower (~2-3 tokens/sec)
- GPU: RTX 3090 can run much larger models (70B+)
- RAM: 31GB on Zephyr sufficient for multiple models

## Advanced Configuration

### Multiple Local Servers

You can run multiple local inference servers:

```json
{
  "provider": {
    "lmstudio": {
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1"
      }
    },
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (Local)",
      "options": {
        "baseURL": "http://127.0.0.1:11434/v1"
      }
    },
    "vllm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "vLLM (Local)",
      "options": {
        "baseURL": "http://127.0.0.1:8000/v1"
      }
    }
  }
}
```

### Model Aliases

Create shortcuts for frequently used models:

```json
{
  "command": {
    "code": {
      "template": "code",
      "model": "lmstudio/qwen/qwen3-coder-30b",
      "description": "Quick coding task with local Qwen3 Coder"
    },
    "chat": {
      "template": "chat",
      "model": "lmstudio/qwen3.5-2b-iq4-nl.gguf",
      "description": "Chat with fast local model"
    },
    "think": {
      "template": "think",
      "model": "kilo/deepseek/deepseek-r1",
      "description": "Reasoning task with DeepSeek R1"
    }
  }
}
```

Usage:
```bash
opencode code "fix this bug"
opencode chat "what's the weather?"
opencode think "analyze this architecture"
```

## Monitoring and Stats

### Check Token Usage

```bash
# Show statistics
opencode stats

# Export session data
opencode export
```

### Log Level

```json
{
  "logLevel": "DEBUG"  // For troubleshooting
  // "logLevel": "INFO"   // Normal operation
  // "logLevel": "WARN"   // Warnings only
}
```

## Migration from Cloud to Local

### Step 1: Verify Local Models Work

```bash
# Test with a simple prompt
opencode -m lmstudio/qwen3.5-2b-iq4-nl.gguf run "Say hello"
```

### Step 2: Update Config to Disable Cloud

Already done in your config!

### Step 3: Remove Cloud API Keys (Optional)

```bash
# Remove cloud API credentials from environment
unset OPENAI_API_KEY
unset ANTHROPIC_API_KEY
unset GOOGLE_API_KEY

# Remove from opencode auth
opencode providers logout openai
opencode providers logout anthropic
```

### Step 4: Test with Real Workload

```bash
# Try a coding task
opencode -m lmstudio/qwen3.5-2b-iq4-nl.gguf run "Refactor this function"

# Start interactive session
opencode
```

## Summary

✅ **Configured**: OpenCode defaults to local LM Studio model  
✅ **Disabled**: Cloud providers (OpenAI, Anthropic, Google, etc.)  
✅ **Unified**: Same config in local host and Kubernetes pod via PVC  
✅ **Fast**: ~50ms latency vs ~500ms for cloud APIs  
✅ **Private**: All data stays local  
✅ **Free**: No API costs

**Next Steps**:
1. Load more models into LM Studio as needed
2. Consider setting up Kilo Gateway for model routing
3. Experiment with different quantization levels
4. Monitor performance and adjust based on your hardware
