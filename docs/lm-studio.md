# LM Studio AI Inference

**Status**: ✅ Active | **Updated**: 2026-03-19

---

## Overview

LM Studio provides local LLM inference with automatic GPU selection and multi-GPU support. This cluster uses LM Studio for AI workloads alongside llama.cpp for production deployments.

### Quick Start

```bash
# Start LM Studio
lm-studio

# Load model (e.g., Llama 3 8B)
# Model → Download → Llama 3 → 8B Instruct

# Start server
# ☸️ Dev → Server API → Start Server
```

### API Endpoint

```
http://localhost:1234/v1
```

OpenAI-compatible API - use with any OpenAI client.

---

## Configuration

### Multi-GPU Setup

For models that don't fit on single GPU, enable multi-GPU:

```nix
# In modules/services/ai-inference/lm-studio.nix
services.lm-studio = {
  enable = true;
  multiGpu = true;  # Enable multi-GPU
  gpus = [ "0" "1" ];  # GPU indices
};
```

### Model Storage

Models stored in:
```
/home/j_kro/.lmstudio/models/
```

Available models:
- Llama 3 8B Instruct (Q4_K_M)
- Llama 3 70B Instruct (Q4_K_M, multi-GPU)
- Qwen 2.5 7B Instruct (Q4_K_M)
- Mixtral 8x7B Instruct (Q4_K_M)

---

## Troubleshooting

### Out of Memory

```bash
# Check GPU memory
nvidia-smi

# Use smaller model or reduce context
# LM Studio UI → Settings → Context Size → 4096
```

### Slow Inference

```bash
# Verify GPU is being used
nvidia-smi dmon -s u

# Check CUDA is working
lm-studio --check-cuda
```

### Multi-GPU Not Working

```bash
# Check GPU visibility
echo $CUDA_VISIBLE_DEVICES

# Should be: 0,1 (for example)
# If not, set in NixOS config
```

---

## References

- [LM Studio Documentation](https://lmstudio.ai/)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)

---

## History

- **2026-03-19**: Consolidated from 4 separate setup guides
- **2026-03-10**: Multi-GPU configuration completed
- **2026-03-05**: Initial deployment
