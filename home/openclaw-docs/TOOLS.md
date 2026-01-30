# OpenClaw Tools Documentation

## Ollama Integration

OpenClaw uses Ollama for local LLM inference. This provides:
- **Privacy**: All processing happens locally
- **No API costs**: No cloud provider fees
- **Offline capability**: Works without internet
- **Customization**: Choose models based on hardware

### API Endpoint

```
http://localhost:11434/v1
```

This is OpenAI-compatible, so tools expecting OpenAI API work seamlessly.

### Available Models

Models vary by host based on hardware:

**zephyr (GPU - RTX 3090)**:
- `llama3.2:3b` - Fast, good for most tasks
- `llama3.2:8b` - Better quality, slower
- `qwen3:8b` - Excellent for technical tasks
- `phi4` - Microsoft's latest

**nexus, forge, sentry (CPU-only)**:
- `qwen3:0.6b` - Very fast, lightweight
- `qwen3:1.8b` - Good balance (recommended for nexus)
- `phi3:3.8b` - Decent quality on CPU
- `gemma2:2b` - Google's efficient model

### Model Management

```bash
# List available models
ollama list

# Pull a new model
ollama pull llama3.2:3b

# Run interactive chat
ollama run llama3.2:3b

# Check model info
ollama show llama3.2:3b
```

### Switching Models

To change the default model, update the OpenClaw configuration in your host's configuration.nix:

```nix
programs.openclaw.model = "qwen3:1.8b";
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#hostname
```

## Plugin Tools

### summarize
Summarize text, documents, and code.

**Usage**: "Summarize this: [paste text]"

### peekaboo
Take screenshots and describe what's visible.

**Usage**: "What's on my screen?" or "Take a screenshot"

### oracle
Web search and information retrieval.

**Usage**: "Search for [topic]" or "What's the latest on [subject]?"

### poltergeist
System automation and control.

**Usage**: "Restart the Ollama service" or "Check disk space"

### sag
File and directory management.

**Usage**: "List files in ~/Documents" or "Find all .nix files"

### camsnap
Camera capture and analysis.

**Usage**: "Take a photo" or "What's in front of the camera?"

### gogcli
GOG Galaxy integration for gaming.

**Usage**: "Launch Cyberpunk 2077" or "Check for game updates"

### bird
Social media interactions.

**Usage**: "Post to Twitter: [message]"

### sonoscli
Sonos speaker control.

**Usage**: "Play music in the living room" or "Pause all speakers"

### imsg
iMessage integration (macOS only).

**Usage**: "Send message to [contact]: [text]"

## NixOS-Specific Tools

### Rebuild System
```bash
sudo nixos-rebuild switch --flake .#hostname
```

### Update Flake
```bash
nix flake update
sudo nixos-rebuild switch --flake .#hostname
```

### Check Configuration
```bash
nix flake check
```

### Deploy to Cluster
```bash
just cluster-deploy
```

## Troubleshooting

### Ollama Not Responding
```bash
# Check service status
systemctl status ollama

# Restart service
sudo systemctl restart ollama

# Check logs
journalctl -u ollama -f
```

### Model Download Fails
```bash
# Manual download
ollama pull modelname

# Check disk space
df -h /var/lib/ollama
```

### OpenClaw Gateway Issues
```bash
# Check service status
systemctl --user status openclaw-gateway

# Restart gateway
systemctl --user restart openclaw-gateway

# Check logs
journalctl --user -u openclaw-gateway -f
```

## Best Practices

1. **Use appropriate models**: GPU models on zephyr, lightweight models on servers
2. **Keep models cached**: Ollama keeps models loaded for 24h by default
3. **Monitor resources**: Large models use significant RAM/VRAM
4. **Test locally**: Verify commands work before cluster deployment
5. **Document changes**: Update this file when adding new tools
