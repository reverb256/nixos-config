# OpenCode Gateway Reliability - Complete Setup

## Overview

This document describes how OpenCode connects to your local AI Inference Gateway and how to ensure it always has a working endpoint.

**Date**: 2026-03-05
**Gateway URL**: `http://127.0.0.1:8080/v1`
**Status**: ✅ Working

---

## Current Architecture

```
OpenCode (Editor)
    ↓
opencode.json (config)
    ↓
AI Inference Gateway (127.0.0.1:8080)
    ↓
LM Studio (127.0.0.1:1234)
    ↓
20 Models (256K context windows)
```

---

## OpenCode Configuration

### Location
`/home/j_kro/.config/opencode/opencode.json`

### Gateway Provider

**Configuration**:
```json
{
  "provider": {
    "gateway": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "AI Gateway v2 (Local)",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "{env:LM_STUDIO_API_KEY}",
        "timeout": 300000,
        "maxRetries": 3,
        "retryDelay": 1000
      }
    }
  }
}
```

**Available Models** (updated with all 20 models):

| Model ID | Name | Context | Best For |
|----------|------|---------|----------|
| `magnum-opus-35b-a3b-i1` | Magnum Opus 35B | 256K | Complex tasks, reasoning |
| `qwen/qwen3.5-9b` | Qwen 3.5 9B | 256K | General coding, balanced |
| `qwen3.5-27b` | Qwen 3.5 27B | 256K | Complex reasoning |
| `qwen3.5-4b` | Qwen 3.5 4B | 256K | Quick tasks, code completion |
| `qwen3.5-2b` | Qwen 3.5 2B | 256K | Ultra-fast simple queries |
| `crow-9b-opus-4.6-distill` | Crow 9B Opus | 256K | Complex tasks with reasoning |
| `qwen3.5-9b-claude-opus` | Qwen 9B Claude Opus | 256K | Claude-style reasoning |
| `qwen3.5-4b-claude-opus` | Qwen 4B Claude Opus | 256K | Fast Claude-style reasoning |

**Plus 12 more models** automatically discovered from LM Studio!

---

## Environment Setup

### API Key Configuration

**API Key File**: `/run/agenix/lm-studio-api-key`

**Auto-loaded for new sessions**:
- Bash: `/home/j_kro/.bashrc.d/opencode-gateway.sh`
- Fish: `/home/j_kro/.config/fish/conf.d/opencode-gateway.fish`

**Verify setup**:
```bash
# Check API key is loaded
echo $LM_STUDIO_API_KEY | head -c 20

# Should show first 20 characters of the key
```

**For current session**:
```bash
source /home/j_kro/.bashrc.d/opencode-gateway.sh
```

---

## Service Status

### Gateway Service

**Check status**:
```bash
systemctl status ai-inference-gateway
```

**Current status**:
- ✅ Active (running)
- URL: `http://127.0.0.1:8080/v1`
- Workers: 1
- Memory: 1.9G / 2G max

**Restart if needed**:
```bash
systemctl restart ai-inference-gateway
```

### LM Studio Backend

**Check if running**:
```bash
ps aux | grep -i "lm.*studio" | grep -v grep
```

**Check models loaded**:
```bash
curl -s -H "Authorization: Bearer $LM_STUDIO_API_KEY" \
  http://127.0.0.1:1234/v1/models | jq -r '.data[].id'
```

---

## Health Monitoring

### Quick Health Check

**Test gateway is responding**:
```bash
curl -s http://127.0.0.1:8080/health | jq .
```

**Expected output**:
```json
{
  "status": "healthy",
  "gateway": {
    "version": "2.0.0",
    "host": "127.0.0.1",
    "port": 8080
  }
}
```

**Test models are available**:
```bash
curl -s http://127.0.0.1:8080/v1/models | jq -r '.data[].id' | wc -l
```

**Should show**: 20 models

**Test inference**:
```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen/qwen3.5-9b",
    "messages": [{"role": "user", "content": "Say OK"}],
    "max_tokens": 10
  }' | jq -r '.choices[0].message.content'
```

**Should return**: A response from the model

---

## Troubleshooting

### Problem: OpenCode can't connect to gateway

**Symptoms**:
- OpenCode shows connection errors
- Requests timeout
- "Failed to fetch" errors

**Solutions**:

1. **Check gateway is running**:
   ```bash
   systemctl status ai-inference-gateway
   ```

2. **Check gateway is listening**:
   ```bash
   curl -s http://127.0.0.1:8080/health
   ```

3. **Restart gateway**:
   ```bash
   systemctl restart ai-inference-gateway
   ```

4. **Check logs**:
   ```bash
   journalctl -u ai-inference-gateway -f
   ```

---

### Problem: Gateway returns errors

**Symptoms**:
- 500 Internal Server Error
- "Backend unavailable"
- "Model not loaded"

**Solutions**:

1. **Check LM Studio is running**:
   ```bash
   ps aux | grep -i "lm.*studio" | grep -v grep
   ```

2. **Check API key**:
   ```bash
   ls -la /run/agenix/lm-studio-api-key
   cat /run/agenix/lm-studio-api-key | head -c 20
   ```

3. **Check models are loaded in LM Studio**:
   ```bash
   curl -s -H "Authorization: Bearer $LM_STUDIO_API_KEY" \
     http://127.0.0.1:1234/v1/models | jq -r '.data | length'
   ```

4. **Restart LM Studio** (if needed):
   ```bash
   systemctl restart --user lm-studio
   ```

---

### Problem: Slow responses

**Symptoms**:
- Requests take >10 seconds
- OpenCode hangs
- Timeout errors

**Solutions**:

1. **Check GPU memory**:
   ```bash
   nvidia-smi
   ```

2. **Unload unused models**:
   ```bash
   python3 /etc/nixos/scripts/manage-models.py unload <model-id>
   ```

3. **Use smaller/faster models**:
   - Try `qwen3.5-2b` or `qwen3.5-4b` instead of 35B
   - Configure in OpenCode settings

---

### Problem: Out of memory

**Symptoms**:
- Gateway crashes
- "Cannot allocate memory"
- OOM killed

**Solutions**:

1. **Increase gateway memory limit** (in `default.nix`):
   ```nix
   services.ai-inference.gateway.memoryLimit = "4G";  # Increase from 2G
   ```

2. **Reduce worker count**:
   ```nix
   services.ai-inference.gateway.workers = 1;  # Already set
   ```

3. **Unload large models**:
   ```bash
   # Unload 35B model if not needed
   curl -s -H "Authorization: Bearer $LM_STUDIO_API_KEY" \
     -X POST http://127.0.0.1:1234/api/v1/models/unload \
     -H "Content-Type: application/json" \
     -d '{"instance_id": "qwen3.5-35b-a3b"}'
   ```

---

## Auto-Healing Configuration

### Health Monitor Module

**Location**: `/etc/nixos/modules/services/ai-inference/health-monitor.nix`

**Enable**:
```nix
services.ai-inference.health-monitor.enable = true;
services.ai-inference.health-monitor.interval = "5min";  # Check every 5 minutes
```

**What it does**:
- Runs health checks every 5 minutes
- Automatically restarts gateway if unhealthy
- Logs all checks and actions
- Sends notifications if available

**Manual health check**:
```bash
/etc/nixos/scripts/ensure-opencode-gateway.sh check
```

**Manual repair**:
```bash
/etc/nixos/scripts/ensure-opencode-gateway.sh repair
```

**Continuous monitoring**:
```bash
/etc/nixos/scripts/ensure-opencode-gateway.sh watch
```

---

## Performance Optimization

### Gateway Configuration

**Current settings** (optimized):
```nix
services.ai-inference = {
  gateway = {
    enable = true;
    host = "127.0.0.1";  # Local only
    port = 8080;
    workers = 1;  # Single worker to save memory
    middleware.redis.enable = false;  # Disabled to save memory
  };
};
```

### Model Selection Guide

**For OpenCode agents**:

| Task | Recommended Model | Why |
|------|-------------------|-----|
| Quick edits | `qwen3.5-2b` | Fastest, low latency |
| Code completion | `qwen3.5-4b` | Fast, capable |
| General coding | `qwen/qwen3.5-9b` | Balanced speed/capability |
| Complex refactoring | `magnum-opus-35b-a3b-i1` | Best reasoning |
| Documentation | `qwen3.5-9b-claude-opus` | Good writing style |

**Configure in oh-my-opencode.json**:
```json
{
  "agents": {
    "quick-agent": {
      "model": "gateway/qwen3.5-2b"
    },
    "coding-agent": {
      "model": "gateway/qwen/qwen3.5-9b"
    },
    "architect-agent": {
      "model": "gateway/magnum-opus-35b-a3b-i1"
    }
  }
}
```

---

## Testing OpenCode Integration

### Verify Configuration

1. **OpenCode recognizes gateway**:
   - Check OpenCode settings
   - Should show "AI Gateway v2 (Local)" as a provider
   - Should list all models

2. **Test in OpenCode**:
   - Open a file in OpenCode
   - Use AI chat feature
   - Select a gateway model
   - Ask a simple question

3. **Expected behavior**:
   - Response within 2-5 seconds
   - No connection errors
   - Model responds correctly

---

## Fallback Strategy

### If gateway is unavailable

**OpenCode will automatically use**:
- Z.AI Coding Plan (cloud fallback)
- Configured in `opencode.json` as secondary provider

**To prioritize gateway**:
1. Set gateway as default in OpenCode settings
2. Use Z.AI only as emergency fallback
3. Or disable Z.AI entirely to force local-only

---

## Monitoring and Logs

### Gateway Logs

**View live logs**:
```bash
journalctl -u ai-inference-gateway -f
```

**View recent errors**:
```bash
journalctl -u ai-inference-gateway --since "5 minutes ago" | grep -i error
```

**View startup logs**:
```bash
journalctl -u ai-inference-gateway --since today | head -50
```

### Metrics

**Prometheus metrics** (if enabled):
```bash
curl -s http://127.0.0.1:9190/metrics
```

**Key metrics to monitor**:
- `gateway_requests_total` - Total requests
- `gateway_request_duration_seconds` - Request latency
- `gateway_backend_errors_total` - Backend errors
- `gateway_cache_hits_total` - Cache hits

---

## Best Practices

### For Development

1. **Use fast models for iteration**:
   - `qwen3.5-2b` or `qwen3.5-4b`
   - Get quick feedback

2. **Use large models for complex tasks**:
   - `magnum-opus-35b-a3b-i1`
   - Better reasoning for refactoring

3. **Keep models loaded**:
   - Avoid frequent load/unload
   - Uses more GPU memory but faster responses

### For Production

1. **Enable health monitoring**:
   ```nix
   services.ai-inference.health-monitor.enable = true;
   ```

2. **Set up alerts**:
   - Monitor gateway uptime
   - Alert on backend failures
   - Track response times

3. **Have fallback plan**:
   - Z.AI as emergency fallback
   - Or multiple local gateways

---

## Summary

✅ **OpenCode is configured to use local gateway**
✅ **All 20 models are available**
✅ **256K context windows enabled**
✅ **API key auto-loaded in environment**
✅ **Health monitoring available**
✅ **Auto-repair can be enabled**

**Current Status**: Working and reliable!

**Next Steps**:
1. Enable health monitor for auto-repair
2. Test all models in OpenCode
3. Configure agent preferences in oh-my-opencode.json
4. Monitor logs for any issues

---

## Quick Reference Commands

```bash
# Check gateway status
systemctl status ai-inference-gateway

# Check gateway health
curl -s http://127.0.0.1:8080/health | jq .

# List available models
curl -s http://127.0.0.1:8080/v1/models | jq -r '.data[].id'

# Test inference
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen/qwen3.5-9b", "messages": [{"role": "user", "content": "Hi"}]}' | jq .

# Restart gateway
systemctl restart ai-inference-gateway

# View logs
journalctl -u ai-inference-gateway -f

# Health check
/etc/nixos/scripts/ensure-opencode-gateway.sh check

# Manage models
python3 /etc/nixos/scripts/manage-models.py

# Validate models
python3 /etc/nixos/scripts/validate-models.py
```
