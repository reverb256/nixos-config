# LM Studio Headless Setup on NixOS

Complete guide for running LM Studio in headless mode using the `llmster` daemon on NixOS.

## Overview

The `llmster` daemon is LM Studio's headless mode that provides:
- **HTTP API server** on port 1234 (OpenAI-compatible)
- **Model management** via `lms` CLI commands
- **JIT loading** - models load on-demand, or preload at startup
- **Daemon lifecycle** - proper startup/shutdown with `lms daemon up/down`

**Official docs**: https://lmstudio.ai/docs/developer/core/headless_llmster

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  NixOS Configuration                        │
│  services.lm-studio-headless.enable = true;                 │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              systemd service (lm-studio-headless)           │
│  ExecStartPre: lms daemon up                                │
│  ExecStartPre: lms load <model> --yes (optional)            │
│  ExecStart:    lms server start --port 1234                 │
│  ExecStop:     lms daemon down                              │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    llmster daemon                            │
│  - HTTP API server on :1234                                 │
│  - Model management (load/unload)                           │
│  - JIT model loading from ~/.lmstudio/models               │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Install the lms CLI

The `lms` CLI is installed **per-user** (not system-wide via Nix):

```bash
# Run the installer script
sudo /etc/nixos/scripts/install-lmstudio-headless.sh j_kro

# Or manually:
su - j_kro -c 'curl -fsSL https://lmstudio.ai/install.sh | bash'
```

**Note**: This installs outside of Nix store to `~/.lmstudio/bin/lms`.

### 2. (Optional) Download a Model

Models can be downloaded via CLI or will auto-download when first used:

```bash
# Download manually
su - j_kro -c 'lms get qwen/qwen3.5-9b-instruct'

# Or let JIT loading download on first request
```

### 3. Configure NixOS

Add to your configuration (e.g., `hosts/zephyr/configuration.nix`):

```nix
# Basic configuration (JIT model loading)
services.lm-studio-headless = {
  enable = true;
  user = "j_kro";
  port = 1234;
  host = "127.0.0.1";
  # No preloadModel = JIT loading (downloads on first use)
};

# Or with model preloading
services.lm-studio-headless = {
  enable = true;
  user = "j_kro";
  port = 1234;
  host = "127.0.0.1";
  preloadModel = "qwen/qwen3.5-9b-instruct";  # Preload at startup
  modelLoadArgs = [
    "--context-length" "32768"
    "--gpu-split" "auto"
  ];
};
```

### 4. Rebuild and Start

```bash
# Rebuild NixOS
sudo nixos-rebuild switch

# Enable and start the service
sudo systemctl enable lm-studio-headless
sudo systemctl start lm-studio-headless

# Check status
sudo systemctl status lm-studio-headless
```

### 5. Verify

```bash
# Check API is responding
curl http://localhost:1234/v1/models | jq .

# Test completion
curl -X POST http://localhost:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen/qwen3.5-9b-instruct",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 10
  }' | jq .
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable the service |
| `port` | int | 1234 | HTTP API server port |
| `host` | string | "127.0.0.1" | Bind address |
| `user` | string | "j_kro" | User to run as |
| `openFirewall` | bool | false | Open firewall port |
| `gpuDevice` | null or int | null | CUDA GPU ID (0, 1, etc.) |
| `gpuSplit` | null or string | null | Multi-GPU split ("auto", "gpu_0") |
| `preloadModel` | null or string | null | Model to preload at startup |
| `modelLoadArgs` | list of string | [] | Args for `lms load` |
| `contextLength` | null or int | null | Default context length |
| `modelsPath` | string | ~/.lmstudio/models | Model storage path |

## Model Examples

Common models to use:

```nix
# Small, fast
preloadModel = "qwen/qwen3.5-0.8b-instruct";

# General purpose
preloadModel = "qwen/qwen3.5-9b-instruct";

# Long context
preloadModel = "qwen/qwen3.5-35b-a3b-instruct";
modelLoadArgs = ["--context-length" "262144"];  # 256K tokens
```

## Multi-GPU Configuration

For systems with multiple GPUs:

```nix
services.lm-studio-headless = {
  enable = true;
  # Use specific GPU
  gpuDevice = 1;  # Use second GPU

  # Or use GPU split
  gpuSplit = "auto";  # Auto-split across all GPUs
  # gpuSplit = "gpu_0";  # Use only first GPU
  # gpuSplit = "gpu_0,gpu_1";  # Split across two GPUs
};
```

## Service Management

```bash
# Start/stop/restart
sudo systemctl start lm-studio-headless
sudo systemctl stop lm-studio-headless
sudo systemctl restart lm-studio-headless

# Enable/disable auto-start
sudo systemctl enable lm-studio-headless
sudo systemctl disable lm-studio-headless

# View logs
sudo journalctl -u lm-studio-headless -f
sudo journalctl -u lm-studio-headless -n 100

# Check service status
sudo systemctl status lm-studio-headless
```

## Troubleshooting

### Service fails to start

```bash
# Check logs
sudo journalctl -u lm-studio-headless -n 50

# Verify lms CLI is installed
sudo -u j_kro which lms
sudo -u j_kro lms --version

# Check if port is already in use
sudo lsof -i :1234
```

### Model loading issues

```bash
# List available models
sudo -u j_kro lms list

# Check model storage
ls -la ~/.lmstudio/models/

# Load model manually to test
sudo -u j_kro lms load qwen/qwen3.5-9b-instruct --yes
```

### Permission issues

Ensure the user has proper permissions:

```bash
# Check home directory ownership
ls -la /home/j_kro/.lmstudio/

# Fix if needed
sudo chown -R j_kro:users /home/j_kro/.lmstudio/
```

## Integration with AI Gateway

The headless service integrates with the existing AI inference gateway:

```nix
services.ai-inference = {
  enable = true;
  backend = {
    type = "lm-studio";
    url = "http://127.0.0.1:1234";
  };
};

services.lm-studio-headless = {
  enable = true;
  # Gateway will connect to this
};
```

## Differences from Desktop App

| Feature | Desktop App | Headless (llmster) |
|---------|-------------|-------------------|
| GUI | Yes | No |
| CLI | `lmstudio` | `lms` |
| Model management | GUI only | CLI + API |
| Startup | User login | systemd boot |
| API port | Configurable | Default 1234 |
| MCP support | GUI + API | API only |

## Upgrading

To upgrade the lms CLI:

```bash
# Re-run the installer
su - j_kro -c 'curl -fsSL https://lmstudio.ai/install.sh | bash'

# Restart the service
sudo systemctl restart lm-studio-headless
```

## References

- [Official LM Studio Headless Docs](https://lmstudio.ai/docs/developer/core/headless_llmster)
- [LM Studio CLI Reference](https://lmstudio.ai/docs/developer/core/cli)
- [Model Catalog](https://lmstudio.ai/models)
