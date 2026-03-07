---
name: lm-studio-manager
description: Manage LM Studio models, ports, and configuration for local LLM inference. Use when user asks to: download models, check LM Studio status, configure models, or troubleshoot LM Studio connection.
---

# LM Studio Manager

Manage LM Studio as the local LLM backend for the AI inference gateway.

## When to Use This Skill

Use this skill when the user:
- Asks to "check LM Studio", "is LM Studio running?", "LM Studio status"
- Wants to "download model", "load model", "configure model"
- Needs to change "LM Studio port", "server settings"
- Asks about "local LLM", "local models", "offline inference"
- Troubleshootes "LM Studio connection", "backend unavailable"

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       AI Inference Gateway                  │
│                      (127.0.0.1:8080)                       │
├─────────────────────────────────────────────────────────────┤
│  OpenAI-compatible API                                     │
│  /v1/chat/completions, /v1/models                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    LM Studio Server                        │
│                      (127.0.0.1:1234)                       │
├─────────────────────────────────────────────────────────────┤
│  Model Loading                                             │
│  Inference Engine                                          │
│  Model Management                                          │
└─────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                      Loaded Models                         │
│  • qwen/qwen2.5-7b-instruct                                │
│  • microsoft/Phi-3-medium-4k-instruct                      │
│  • mistralai/Mistral-7B-Instruct-v0.3                      │
└─────────────────────────────────────────────────────────────┘
```

## LM Studio Status

### Check if Running
```bash
# Check if LM Studio server is responding
curl http://127.0.0.1:1234/v1/models

# Check via gateway backend health
curl http://127.0.0.1:8080/health | jq .backend

# Check if process is running
ps aux | grep -i "lm-studio"

# Check port
lsof -i :1234
```

### View Available Models
```bash
# Via LM Studio API
curl http://127.0.0.1:1234/v1/models | jq .

# Via gateway
curl http://127.0.0.1:8080/v1/models | jq .
```

### Test Inference
```bash
# Direct to LM Studio
curl -X POST http://127.0.0.1:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-7b-instruct",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'

# Via gateway
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen/qwen2.5-7b-instruct",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'
```

## Model Management

### Download Models (LM Studio GUI)

1. Open LM Studio application
2. Go to "Models" tab
3. Search for model (e.g., "qwen2.5", "phi-3", "mistral")
4. Click "Download"

### Recommended Models

| Model | Size | Use Case | VRAM |
|-------|------|----------|------|
| `qwen/qwen2.5-7b-instruct` | ~4.7GB | General purpose | 8GB |
| `microsoft/Phi-3-medium-4k-instruct` | ~7GB | Balanced | 10GB |
| `mistralai/Mistral-7B-Instruct-v0.3` | ~4.7GB | Chat | 8GB |
| `meta-llama/Llama-3.1-8B-Instruct` | ~4.7GB | High quality | 8GB |
| `google/gemma-2-9b-it` | ~5.5GB | Fast | 10GB |

### Load Model in Server

1. Open LM Studio
2. Go to "Local Server" tab
3. Select model from dropdown
4. Configure settings (see below)
5. Click "Start Server"

## Server Configuration

### Server Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Port | 1234 | Server port |
| Host | 127.0.0.1 | Bind address |
| Context Length | 2048+ | Token context window |
| GPU Layers | -1 | Offload layers to GPU (-1 = all) |
| Thread Count | 8 | CPU threads |
| Batch Size | 512 | Prompt batch size |
| Chat Format | Auto | Template format |

### Recommended Settings

**For RTX 3090 (24GB VRAM):**
```
Model: qwen/qwen2.5-7b-instruct
Context Length: 8192
GPU Layers: -1 (all)
GPU Offload: ON
Thread Count: 8
Batch Size: 512
```

**For RTX 3060 Ti (8GB VRAM):**
```
Model: microsoft/Phi-3-mini-4k-instruct
Context Length: 4096
GPU Layers: -1
GPU Offload: ON
Thread Count: 6
Batch Size: 512
```

**For CPU-only (fallback):**
```
Model: phi-3-mini-4k-instruct (quantized)
Context Length: 2048
GPU Layers: 0
Thread Count: 16
Batch Size: 512
```

## Gateway Integration

The gateway connects to LM Studio via configuration:

```python
# In modules/services/ai-inference/ai_inference_gateway/backends/lm_studio.py

LM_STUDIO_BASE_URL = "http://127.0.0.1:1234"
```

### Model Name Mapping

The gateway normalizes model names:

| LM Studio Name | Gateway Name |
|----------------|--------------|
| `qwen2.5-7b-instruct` | `qwen/qwen2.5-7b-instruct` |
| `Phi-3-medium-4k-instruct` | `microsoft/Phi-3-medium-4k-instruct` |
| `Mistral-7B-Instruct-v0.3` | `mistralai/Mistral-7B-Instruct-v0.3` |

## Troubleshooting

### LM Studio Not Running

```bash
# Check if application is open
ps aux | grep -i lm-studio

# Start LM Studio
# (Launch from application menu or terminal)
lm-studio &

# Or start headless server (if supported)
lm-studio-server --port 1234
```

### Port Already in Use

```bash
# Check what's using port 1234
sudo lsof -i :1234

# Or
sudo netstat -tulpn | grep 1234

# Change port in LM Studio:
# Local Server → Settings → Port → 1235
```

### Model Not Loading

```bash
# Check VRAM usage
nvidia-smi

# Check if model file exists
ls -la ~/.cache/lm-studio/models/

# Try loading smaller model
# Or reduce context length in LM Studio settings
```

### Gateway Can't Connect

```bash
# Test direct connection
curl -v http://127.0.0.1:1234/v1/models

# Check gateway logs
journalctl -u ai-inference-gateway -f | grep -i lm

# Check gateway configuration
cat /etc/nixos/modules/services/ai-inference/ai_inference_gateway/backends/lm_studio.py
```

### Out of Memory

```bash
# Check GPU memory
nvidia-smi

# Options:
# 1. Reduce context length in LM Studio
# 2. Use smaller model
# 3. Reduce GPU Layers (offload fewer layers)
# 4. Stop mining: sudo systemctl stop xmrig@*
```

## Auto-Start LM Studio

### Via Systemd User Service

Create `~/.config/systemd/user/lm-studio.service`:
```ini
[Unit]
Description=LM Studio Server
After=network.target

[Service]
ExecStart=/usr/bin/lm-studio --server
Restart=on-failure

[Install]
WantedBy=default.target
```

Enable:
```bash
systemctl --user enable lm-studio.service
systemctl --user start lm-studio.service
```

### Via NixOS Configuration

Add to startup applications:
```nix
# In user configuration or host config
systemd.user.services.lm-studio = {
  description = "LM Studio Server";
  serviceConfig = {
    ExecStart = "${pkgs.lm-studio}/bin/lm-studio --server";
    Restart = "on-failure";
  };
  wantedBy = [ "default.target" ];
};
```

## Performance Tips

### Maximize GPU Utilization
```bash
# Stop mining before running LM Studio
sudo systemctl stop xmrig@*

# Set GPU Layers to -1 (all layers to GPU)
# In LM Studio: Local Server → Settings → GPU Layers = -1
```

### Optimize Context Length
- Start with 2048 tokens
- Increase only if needed for long conversations
- Longer context = more VRAM usage

### Use Quantized Models
- Q4_K_M / Q5_K_M: Good balance
- Q8_0: Better quality, more VRAM
- Q2_K: Lowest quality, least VRAM

## Monitoring

### Monitor Requests
```bash
# Watch gateway logs for LM Studio requests
journalctl -u ai-inference-gateway -f | grep -i "lm\|backend"

# Monitor GPU usage during inference
watch -n 1 nvidia-smi
```

### Check Response Times
```bash
# Time a request
time curl -X POST http://127.0.0.1:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5-7b-instruct","messages":[{"role":"user","content":"Hi"}],"max_tokens":50}'
```

## Quick Reference

| Task | Command |
|------|---------|
| Check status | `curl http://127.0.0.1:1234/v1/models` |
| List models | `curl http://127.0.0.1:1234/v1/models \| jq .` |
| Test inference | `curl -X POST http://127.0.0.1:1234/v1/chat/completions -d '{...}'` |
| Check GPU | `nvidia-smi` |
| Stop mining | `sudo systemctl stop xmrig@*` |
| View gateway logs | `journalctl -u ai-inference-gateway -f` |

## Related Skills
- **ai-gateway-manager**: For managing the AI inference gateway
- **hardware-control**: For managing GPU resources and mining
- **nix-rebuild**: For applying configuration changes

## Model Locations

LM Studio stores models in:
```
~/.cache/lm-studio/models/
├── qwen/
│   └── qwen2.5-7b-instruct/
│       └── [model files]
├── microsoft/
│   └── Phi-3-medium-4k-instruct/
│       └── [model files]
└── ...
```

Backup or restore models from this directory.
