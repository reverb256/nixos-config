# Llamafile Integration Guide

## Overview

llamafile is a Mozilla project that lets you distribute and run LLMs with a single file. This integration provides a **standalone fallback LLM service** that runs independently of LM Studio.

## Why Llamafile?

| Feature | llamafile | LM Studio |
|---------|-----------|-----------|
| Installation | Single executable | AppImage + GUI |
| Portability | Runs on 6 OSes | Linux/macOS/Windows |
| Dependencies | None (self-contained) | Qt, system libraries |
| Distribution | Single file to share | Manual model downloads |
| GPU support | Metal, CUDA, ROCm | CUDA, Metal |
| API | OpenAI-compatible | OpenAI-compatible |

## Chosen Model: Qwen3.5-9B-Unredacted-MAX

### Specifications

| Property | Value |
|----------|-------|
| **Parameters** | 9 billion |
| **Quantization** | Q4_K_S |
| **File Size** | 5.0 GB |
| **Context Window** | 32K tokens |
| **Fit on 3060Ti** | ✅ (12GB VRAM) |
| **Fit on 5600XT** | ✅ (8GB VRAM) |

### Why This Model?

1. **Fits both GPUs** - 5GB fits comfortably on both 3060Ti and 5600XT
2. **Unredacted** - Less filtered responses for more creative output
3. **Good balance** - 9B parameters offer quality without excessive resource usage
4. **Fast inference** - Quantized to Q4_K_S for efficient GPU inference

## NixOS Configuration

### Basic Setup

Add to your host configuration (e.g., `hosts/zephyr/configuration.nix`):

```nix
{ config, ... }: {
  services.llamafile = {
    enable = true;

    # Model path (GGUF format)
    modelPath = /home/j_kro/.lmstudio/models/mradermacher/Qwen3.5-9B-Unredacted-MAX-i1-GGUF/Qwen3.5-9B-Unredacted-MAX.i1-Q4_K_S.gguf;

    # Server settings
    host = "127.0.0.1";  # Change to "0.0.0.0" for cluster access
    port = 8081;         # Different from gateway (8080)

    # GPU settings
    gpuLayers = 999;     # Offload all layers to GPU
    # gpu = "nvidia";     # Force NVIDIA (auto-detect by default)

    # Performance
    ctxSize = 8192;      # Context window
    threads = 8;         # CPU threads
  };
}
```

### Per-Host Configuration

**Zephyr (3060Ti - NVIDIA):**
```nix
services.llamafile = {
  enable = true;
  modelPath = "/home/j_kro/.lmstudio/models/mradermacher/Qwen3.5-9B-Unredacted-MAX-i1-GGUF/Qwen3.5-9B-Unredacted-MAX.i1-Q4_K_S.gguf";
  gpu = "nvidia";
  gpuLayers = 999;
  ctxSize = 8192;
};
```

**Sentry (5600XT - AMD):**
```nix
services.llamafile = {
  enable = true;
  modelPath = "/home/j_kro/.lmstudio/models/mradermacher/Qwen3.5-9B-Unredacted-MAX-i1-GGUF/Qwen3.5-9B-Unredacted-MAX.i1-Q4_K_S.gguf";
  gpu = "amd";
  gpuLayers = 32;  # Conservative for 8GB VRAM
  ctxSize = 4096;  # Smaller context for AMD
};
```

## Usage

### Start/Stop Service

```bash
# Start llamafile
systemctl start llamafile

# Stop llamafile
systemctl stop llamafile

# Check status
systemctl status llamafile

# View logs
journalctl -u llamafile -f
```

### Test API

```bash
# Using the test script
llamafile-test

# Or manually with curl
curl http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer no-key" \
  -d '{
    "model": "LLaMA_CPP",
    "messages": [{"role": "user", "content": "Say hi in 3 words"}]
  }'
```

### Chat from CLI

```bash
llamafile-chat "Explain quantum computing in simple terms"
```

### OpenAI Python Client

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8081/v1",
    api_key="sk-no-key-required"
)

response = client.chat.completions.create(
    model="LLaMA_CPP",
    messages=[{"role": "user", "content": "Write a haiku about NixOS"}]
)

print(response.choices[0].message.content)
```

## Creating a Standalone Llamafile

To create a single-file executable with embedded model:

```bash
/etc/nixos/scripts/create-llamafile.sh \
  ~/.lmstudio/models/mradermacher/Qwen3.5-9B-Unredacted-MAX-i1-GGUF/Qwen3.5-9B-Unredacted-MAX.i1-Q4_K_S.gguf \
  qwen-9b-unredacted.llamafile \
  --host 0.0.0.0 --port 8081
```

This creates a ~5GB executable containing both the LLM engine and model weights.

## GPU Offloading (`-ngl`)

The `-ngl` flag controls how many transformer layers run on GPU:

| Flag | VRAM Usage | Speed |
|------|------------|-------|
| `-ngl 0` | Minimal (CPU only) | Slowest |
| `-ngl 32` | ~3-4 GB | Medium |
| `-ngl 999` | All layers | Fastest (if VRAM allows) |

**For 9B model on your GPUs:**
- **3060Ti (12GB)**: `-ngl 999` (all layers ~5GB)
- **5600XT (8GB)**: `-ngl 32-40` (partial, safer for 8GB)

## Integration with AI Gateway

To use llamafile as a fallback backend for the AI gateway:

```nix
services.ai-inference = {
  enable = true;
  routing.fallbackChain = [
    "lm-studio"    # Try LM Studio first
    "llamafile"    # Then llamafile
    "zai"          # Finally ZAI cloud
  ];
};
```

The gateway will automatically route to llamafile if LM Studio is unavailable.

## Cluster Deployment

### Zephyr (Primary)

```nix
services.llamafile = {
  enable = true;
  modelPath = "/home/j_kro/.lmstudio/models/mradermacher/Qwen3.5-9B-Unredacted-MAX-i1-GGUF/Qwen3.5-9B-Unredacted-MAX.i1-Q4_K_S.gguf";
  host = "0.0.0.0";  # Accept cluster connections
  port = 8081;
  gpu = "nvidia";
  gpuLayers = 999;
};
```

### Sentry (Secondary)

```nix
services.llamafile = {
  enable = true;
  modelPath = "/home/j_kro/.lmstudio/models/mradermacher/Qwen3.5-9B-Unredacted-MAX-i1-GGUF/Qwen3.5-9B-Unredacted-MAX.i1-Q4_K_S.gguf";
  host = "0.0.0.0";
  port = 8081;
  gpu = "amd";
  gpuLayers = 32;
};
```

### Access from Other Nodes

```bash
# From forge or nexus
curl http://zephyr:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"LLaMA_CPP","messages":[{"role":"user","content":"Hi"}]}'
```

## Troubleshooting

### Permission Denied on Executable

```bash
chmod +x /path/to/llamafile
```

### GPU Not Detected

```bash
# Check GPU is visible
nvidia-smi  # NVIDIA
rocminfo   # AMD

# Check llamafile logs
journalctl -u llamafile -n 50

# Try forcing specific GPU
services.llamafile.gpu = "nvidia";  # or "amd"
```

### Out of Memory

```bash
# Reduce GPU layers
services.llamafile.gpuLayers = 16;  # Reduce from 999

# Or reduce context size
services.llamafile.ctxSize = 4096;  # Reduce from 8192
```

### Model File Not Found

```bash
# Check model exists
ls -lh ~/.lmstudio/models/mradermacher/Qwen3.5-9B-Unredacted-MAX-i1-GGUF/

# Update path in config if different
services.llamafile.modelPath = /path/to/your/model.gguf;
```

## Performance Benchmarks

Expected performance on **Qwen3.5-9B Q4_K_S**:

| Hardware | Tokens/sec | Time/100 tokens |
|----------|-------------|-----------------|
| 3060Ti (12GB) -ngl 999 | ~40-50 t/s | ~2-2.5s |
| 5600XT (8GB) -ngl 32 | ~15-20 t/s | ~5-6s |
| CPU only -ngl 0 | ~3-5 t/s | ~20-30s |

## Advanced Configuration

### Custom Arguments

Add custom arguments via `ExecStart` override:

```nix
systemd.services.llamafile.serviceConfig.ExecStart = lib.mkForce [
  ""${llamafilePackage}/bin/llamafile \
    --server --v2 \
    -m ${cfg.modelPath} \
    --temp 0.7 \           # Temperature
    --top-k 40 \            # Top-k sampling
    --top-p 0.9 \           # Top-p sampling
    --repeat-penalty 1.1 \ # Repeat penalty
    -ngl ${toString cfg.gpuLayers}"
];
```

### Multiple Models

Create separate services for different models:

```nix
services.llamafile-fast = {
  enable = true;
  modelPath = "/path/to/4b-model.gguf";
  port = 8081;
};

services.llamafile-quality = {
  enable = true;
  modelPath = "/path/to/9b-model.gguf";
  port = 8082;
};
```

## References

- **GitHub**: https://github.com/Mozilla-Ocho/llamafile
- **Announcement**: https://justine.lol/llamafile.html
- **llama.cpp**: https://github.com/ggerganov/llama.cpp
- **Cosmopolitan Libc**: https://github.com/jart/cosmopolitan
