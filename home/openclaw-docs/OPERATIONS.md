# OpenClaw Operations Guide

## Verification Commands

### Check Service Status

```bash
# On any host
systemctl status ollama
systemctl --user status openclaw-gateway

# Check logs
journalctl -u ollama -f
journalctl --user -u openclaw-gateway -f
```

### Test Ollama API

```bash
# List available models
curl http://localhost:11434/api/tags | jq

# Test model inference
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2:3b",
  "prompt": "Hello, how are you?"
}'
```

### Test OpenClaw via Telegram

1. Send "/start" to your Telegram bot
2. Send "Hello" - should respond using local Ollama model
3. Send "Summarize this: [text]" - should use summarize plugin

## Rollback Procedures

### Rollback OpenClaw Configuration

```bash
# View previous generations
home-manager generations

# Rollback to previous generation
home-manager switch --rollback

# Or switch to specific generation
home-manager switch --generation 42
```

### Rollback System Configuration

```bash
# List system generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Or boot into specific generation from bootloader
```

### Rollback Flake Changes

```bash
# Reset to last committed state
git checkout -- .

# Or reset to specific commit
git reset --hard HEAD~1

# Then rebuild
sudo nixos-rebuild switch --flake .#hostname
```

## Troubleshooting

### OpenClaw Gateway Not Starting

```bash
# Check if Ollama is running first
systemctl status ollama

# If not, start it
sudo systemctl start ollama

# Then restart OpenClaw
systemctl --user restart openclaw-gateway

# Check for errors
journalctl --user -u openclaw-gateway -n 50
```

### Model Not Responding

```bash
# Check if model is downloaded
ollama list

# If not, download it
ollama pull llama3.2:3b

# Test directly
ollama run llama3.2:3b
```

### Telegram Bot Not Responding

1. Check bot token is correct in `/run/agenix/openclaw-telegram-token`
2. Verify Telegram user ID is in `allowFrom` list
3. Check logs: `journalctl --user -u openclaw-gateway -f`
4. Ensure bot has no pending updates: https://api.telegram.org/bot<TOKEN>/getUpdates

### GPU Not Being Used (zephyr)

```bash
# Check NVIDIA driver
nvidia-smi

# Check Ollama is using GPU
nvidia-smi | grep ollama

# If not, restart Ollama
sudo systemctl restart ollama
```

## Model Management

### Per-Host Model Recommendations

**zephyr (GPU - RTX 3090)**:
```bash
# Large models for quality
ollama pull llama3.2:8b
ollama pull qwen3:8b
ollama pull phi4

# Fast models for quick tasks
ollama pull llama3.2:3b
```

**nexus (CPU)**:
```bash
# Small, efficient models
ollama pull qwen3:1.8b
ollama pull gemma2:2b
```

**forge, sentry (CPU)**:
```bash
# Lightweight models
ollama pull qwen3:0.6b
ollama pull phi3:3.8b
```

### Switching Models

Edit your host's `configuration.nix`:

```nix
programs.openclaw.model = "qwen3:1.8b";
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#hostname
```

## Quick Reference

| Command | Purpose |
|---------|---------|
| `ollama list` | Show downloaded models |
| `ollama pull <model>` | Download a model |
| `ollama run <model>` | Interactive chat with model |
| `systemctl status ollama` | Check Ollama service |
| `systemctl --user status openclaw-gateway` | Check OpenClaw service |
| `home-manager switch --rollback` | Rollback user config |
| `sudo nixos-rebuild switch --rollback` | Rollback system config |

## Security Notes

- Telegram bot token is stored in Agenix-encrypted file
- Ollama only listens on localhost (127.0.0.1:11434)
- OpenClaw runs as user service (not root)
- All LLM processing is local - no data sent to cloud
