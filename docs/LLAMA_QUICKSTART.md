# llama-cpp Quick Start Guide

## Status
✅ **llama-server is running** on http://127.0.0.1:8080

## GPU Configuration
- **GPU 0**: RTX 3060 Ti (8GB) - Secondary
- **GPU 1**: RTX 3090 (24GB) - Primary (heavier layers)

The RTX 3090 handles most of the workload, with the 3060 Ti assisting with smaller layers.

## Download a Qwen Model

### Option 1: Using huggingface-cli (Recommended)
```bash
# Install
pip install huggingface-hub

# Download Qwen2.5 7B (Fastest - fits on 3090)
huggingface-cli download qwen/Qwen2.5-7B-Instruct-GGUF \
  qwen2.5-7b-instruct-q4_k_m.gguf \
  --local-dir /var/lib/llama/models

# Download Qwen2.5 14B (Balanced - uses both GPUs)
huggingface-cli download qwen/Qwen2.5-14B-Instruct-GGUF \
  qwen2.5-14b-instruct-q4_k_m.gguf \
  --local-dir /var/lib/llama/models

# Download Qwen2.5 32B (Best quality - requires both GPUs)
huggingface-cli download qwen/Qwen2.5-32B-Instruct-GGUF \
  qwen2.5-32b-instruct-q4_k_m.gguf \
  --local-dir /var/lib/llama/models
```

### Option 2: Manual Download
Visit: https://huggingface.co/models?search=Qwen2.5+GGUF
1. Find your model
2. Download the `.gguf` file
3. Save to `/var/lib/llama/models/`

## Change Model

Edit `/etc/nixos/configuration.nix`:
```nix
services.llama.modelName = "your-new-model.gguf";
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#zephyr
```

## Test the API

### Health Check
```bash
curl http://127.0.0.1:8080/health
```

### Simple Completion
```bash
curl -X POST http://127.0.0.1:8080/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "The future of AI is",
    "n_predict": 50
  }'
```

### Chat Completion
```bash
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ]
  }'
```

## Service Management

```bash
# Check status
systemctl status llama-server

# View logs
journalctl -u llama-server -f

# Restart
sudo systemctl restart llama-server

# Stop
sudo systemctl stop llama-server

# Start
sudo systemctl start llama-server
```

## GPU Monitoring

```bash
# Watch GPU usage
watch -n 1 nvidia-smi

# Check which GPU the model is using
nvidia-smi dmon -s u
```

## Performance Tuning

For **7B models** (fits on RTX 3090):
- Fast inference (~30-50 tokens/sec)
- Use for speed-critical applications

For **14B models** (split across GPUs):
- Balanced (~20-30 tokens/sec)
- Better quality reasoning

For **32B models** (requires both GPUs):
- Best quality (~10-15 tokens/sec)
- Best for complex tasks

## Troubleshooting

**Server says "model not found"**
- Make sure the `.gguf` file is in `/var/lib/llama/models/`
- Check the filename matches `services.llama.modelName`

**Out of memory errors**
- Try a smaller quantization (Q4_K_M → Q4_K_S)
- Reduce `gpuLayers` from 99 to 70
- Use a smaller model (32B → 14B → 7B)

**Slow inference**
- Check GPU usage with `nvidia-smi`
- Verify CUDA is working: `nvidia-smi`
- Try increasing `threads` in configuration

**Both GPUs not being used**
- Check that both GPUs are detected: `nvidia-smi -L`
- Verify `gpus = "0,1"` in configuration
- Larger models (>14B) will automatically use both GPUs

## URLs

- **API**: http://127.0.0.1:8080
- **Health**: http://127.0.0.1:8080/health
- **Models**: https://huggingface.co/models?search=Qwen2.5+GGUF
