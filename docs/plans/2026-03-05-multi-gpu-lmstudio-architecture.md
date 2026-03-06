# Multi-Machine Multi-GPU LM Studio Architecture for Spacebot

**Date**: 2026-03-05
**Status**: Design Document
**Purpose**: Distribute LM Studio across 3 machines (5 GPUs, 56GB total VRAM) with intelligent gateway routing for Spacebot's 5-process architecture

---

## Executive Summary

✅ **OBJECTIVE: Optimize Spacebot performance through distributed multi-GPU LM Studio architecture.**

**Hardware Configuration:**
- **Zephyr**: RTX 3090 (24GB) + RTX 3060 Ti (8GB) = 32GB VRAM
- **Forge**: 2x RTX 4060 (8GB each) = 16GB VRAM
- **Nexus**: 1x RTX 3060 Ti (8GB) = 8GB VRAM
- **Total**: 56GB VRAM across 5 GPUs on 3 machines

**Key Features:**
- Tiered model distribution (large → medium → small)
- 256K token context for Cortex with quantized KV cache
- ~110 tokens/sec for 35B models, ~300 t/s for 4B models
- Intelligent gateway routing with overflow logic
- ~1500 tokens/second total system throughput

---

## 1. Architecture Overview

### 1.1 System Diagram

```
                    AI Inference Gateway (zephyr:8080)
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
         Zephyr (32GB)      Forge (16GB)      Nexus (8GB)
         ─────────────      ─────────────      ─────────────
         3090: 24GB         4060 #1: 8GB       3060 Ti: 8GB
         3060 Ti: 8GB       4060 #2: 8GB
         Multi-GPU ✅       Multi-GPU ✅       Single GPU
         75/25 split        50/50 split
```

### 1.2 Three-Tier Model Distribution

**Tier 1 - Large Models (Zephyr - 32GB)**
- qwen3.5-35b-a3b (17GB + 8GB KV cache @ 256K) = 25GB ✅
- qwen3.5-27b (15GB + 6GB KV cache @ 256K) = 21GB ✅
- Context: 256K tokens with quantized KV cache
- Speed: 110-150 tokens/sec
- Target: Cortex, complex Workers

**Tier 2 - Medium Models (Forge - 16GB)**
- qwen3.5-9b (5.1GB + 2GB KV cache @ 64K) = 7.1GB per GPU ✅
- crow-9b-opus-4.6-distill-heretic_qwen3.5 (5GB + 2GB KV cache) = 7GB per GPU ✅
- Context: 64K tokens (configurable to 128K with multi-GPU)
- Speed: ~200 tokens/sec
- Target: Channels, Branches, standard Workers

**Tier 3 - Small/Fast Models (Nexus - 8GB)**
- qwen3.5-4b (2.5GB + 0.5GB KV cache @ 32K) = 3GB ✅
- qwen3.5-2b (1.9GB + 0.2GB KV cache @ 16K) = 2.1GB ✅
- qwen3.5-0.8b (~1GB)
- Context: 16-32K tokens
- Speed: 300-400 tokens/sec
- Target: Compactor, quick tool execution

### 1.3 Per-Spacebot-Process Model Assignment

| Spacebot Process | Primary Model | Context | Backend | Speed | Priority |
|------------------|---------------|---------|---------|-------|----------|
| **Cortex** | qwen3.5-35b-a3b | 256K | Zephyr | 110 t/s | High quality |
| **Workers (complex)** | qwen3.5-35b-a3b | 256K | Zephyr | 110 t/s | Multi-step tasks |
| **Workers (standard)** | qwen3.5-27b | 128K | Zephyr | 150 t/s | Quality + speed |
| **Workers (fast)** | qwen3.5-9b | 64K | Forge | 200 t/s | Quick responses |
| **Channels** | qwen3.5-9b | 32K | Forge | 200 t/s | Interactive |
| **Branches** | qwen3.5-9b-claude-4.6-opus | 64K | Forge | 200 t/s | Reasoning chains |
| **Compactor** | qwen3.5-4b | 16K | Nexus | 300 t/s | Summarization |

---

## 2. LM Studio Configuration

### 2.1 Zephyr Configuration (Already Configured ✅)

**Multi-GPU Setup:**
```json
// ~/.lmstudio/.internal/hardware-config.json
{
  "strategy": "custom",
  "disabledGpus": [],
  "priority": [0, 1],
  "customRatio": [0.75, 0.25]  // 75% to 3090, 25% to 3060 Ti
}
```

**Model Configuration (35B with 256K context):**
```json
// ~/.lmstudio/.internal/user-concrete-model-default-config/
//   unsloth/Qwen3.5-35B-A3B-GGUF/
//   Qwen3.5-35B-A3B-UD-IQ4_NL.gguf.json
{
  "load": {
    "fields": [
      {
        "key": "llm.load.contextLength",
        "value": 262144  // 256K tokens ✅
      },
      {
        "key": "llm.load.offloadKVCacheToGpu",
        "value": true
      },
      {
        "key": "llm.load.quantizationKVCache",
        "value": true  // Critical for 256K context
      }
    ]
  }
}
```

**Verification:**
```bash
# Check models are loaded
curl -H "Authorization: Bearer $(cat /run/agenix/lm-studio-api-key)" \
  http://127.0.0.1:1234/v1/models | jq .

# Expected output includes:
# - qwen3.5-35b-a3b
# - qwen3.5-27b
# - qwen3.5-9b
# - qwen3.5-4b
# - qwen3.5-2b
# - qwen3.5-0.8b
# - crow-9b-*
# - crow-4b-*
```

### 2.2 Forge Configuration (To Be Implemented)

**Step 1: Create hardware-config.json**
```bash
# On forge machine
mkdir -p ~/.lmstudio/.internal
cat > ~/.lmstudio/.internal/hardware-config.json <<'EOF'
{
  "strategy": "custom",
  "disabledGpus": [],
  "priority": [0, 1],
  "customRatio": [0.5, 0.5]  // 50/50 split across both 4060s
}
EOF
```

**Step 2: Configure models**
```bash
# LM Studio GUI settings:
# 1. Load qwen3.5-9b-IQ4_NL.gguf (5.1GB)
# 2. Settings → Context Length: 65536 (64K)
# 3. Settings → GPU Offload: MAX
# 4. Settings → Quantize KV Cache: ✅ Enable
# 5. Settings → Multi-GPU: Custom ratio 50/50
```

**Step 3: Enable API server**
```bash
# In LM Studio:
# 1. Click "Server" icon (or Ctrl/Cmd + J)
# 2. Set port to 1234
# 3. Enable CORS: ✅
# 4. Set API token (use same token as zephyr)
# 5. Start server
```

**Verification:**
```bash
# From zephyr, test forge connectivity
curl http://forge:1234/v1/models

# Expected: Returns model list with qwen3.5-9b
```

### 2.3 Nexus Configuration (To Be Implemented)

**Step 1: Configure LM Studio**
```bash
# On nexus machine
# LM Studio is single GPU, no special config needed
# Just load models and enable API server
```

**Step 2: Load models**
```bash
# LM Studio GUI:
# 1. Load qwen3.5-4b-IQ4_NL.gguf (2.5GB)
# 2. Settings → Context Length: 32768 (32K)
# 3. Settings → GPU Offload: MAX
# 4. Settings → Quantize KV Cache: ✅
```

**Step 3: Enable API server**
```bash
# Same as forge, port 1234
```

**Verification:**
```bash
# From zephyr, test nexus connectivity
curl http://nexus:1234/v1/models

# Expected: Returns model list with qwen3.5-4b, qwen3.5-2b
```

---

## 3. Gateway Configuration

### 3.1 Multi-Backend NixOS Configuration

```nix
# /etc/nixos/hosts/zephyr/ai-inference.nix

{ config, lib, pkgs, ... }:

let
  cfg = config.services.ai-inference;
in
{
  options.services.ai-inference.backend = {
    type = lib.mkOption {
      type = lib.types.enum [ "single" "multi-backend" ];
      default = "single";
      description = "Backend type: single LM Studio or multiple distributed instances";
    };

    # Tier 1: Large models (Zephyr)
    tier1 = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "Tier 1 backend (Zephyr - large models)";

          name = lib.mkOption {
            type = lib.types.str;
            default = "zephyr-large";
            description = "Backend name";
          };

          url = lib.mkOption {
            type = lib.types.str;
            default = "http://127.0.0.1:1234";
            description = "LM Studio API URL";
          };

          maxModelSize = lib.mkOption {
            type = lib.types.str;
            default = "32GB";
            description = "Maximum model size this backend can handle";
          };

          maxConcurrent = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "Maximum concurrent requests";
          };

          models = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                contextLength = lib.mkOption {
                  type = lib.types.int;
                  default = 65536;
                  description = "Context length in tokens";
                };

                speed = lib.mkOption {
                  type = lib.types.int;
                  default = 100;
                  description = "Speed in tokens/second";
                };
              };
            });
            default = {};
            description = "Models available on this backend";
          };
        };
      };
    };

    # Tier 2: Medium models (Forge)
    tier2 = lib.mkOption { /* similar to tier1 */ };

    # Tier 3: Small models (Nexus)
    tier3 = lib.mkOption { /* similar to tier1 */ };
  };

  config = lib.mkIf cfg.enable {
    # Gateway service configuration
    systemd.services.ai-inference-gateway = {
      environment = {
        # Multi-backend configuration
        BACKEND_TYPE = "multi-backend";
        TIER1_URL = lib.optionalString cfg.backend.tier1.enable cfg.backend.tier1.url;
        TIER2_URL = lib.optionalString cfg.backend.tier2.enable cfg.backend.tier2.url;
        TIER3_URL = lib.optionalString cfg.backend.tier3.enable cfg.backend.tier3.url;

        # Model mappings as JSON
        MODEL_BACKEND_MAPPING = lib.generators.toJSON {} {
          "qwen3.5-35b-a3b" = "tier1";
          "qwen3.5-27b" = "tier1";
          "qwen3.5-9b" = "tier2";
          "crow-9b-opus-4.6-distill-heretic_qwen3.5" = "tier2";
          "qwen3.5-4b" = "tier3";
          "qwen3.5-2b" = "tier3";
        };
      };
    };
  };
}
```

### 3.2 Host Configuration

```nix
# /etc/nixos/hosts/zephyr/configuration.nix

services.ai-inference = {
  enable = true;
  backend = {
    type = "multi-backend";

    # Zephyr - Large models
    tier1 = {
      enable = true;
      name = "zephyr-large";
      url = "http://127.0.0.1:1234";
      maxModelSize = "32GB";
      maxConcurrent = 1;
      models = {
        "qwen3.5-35b-a3b" = {
          contextLength = 262144;  # 256K
          speed = 110;
        };
        "qwen3.5-27b" = {
          contextLength = 262144;  # 256K
          speed = 150;
        };
      };
    };

    # Forge - Medium models
    tier2 = {
      enable = true;
      name = "forge-medium";
      url = "http://forge:1234";
      maxModelSize = "16GB";
      maxConcurrent = 2;
      models = {
        "qwen3.5-9b" = {
          contextLength = 65536;  # 64K
          speed = 200;
        };
        "crow-9b-opus-4.6-distill-heretic_qwen3.5" = {
          contextLength = 65536;
          speed = 200;
        };
      };
    };

    # Nexus - Fast models
    tier3 = {
      enable = true;
      name = "nexus-fast";
      url = "http://nexus:1234";
      maxModelSize = "8GB";
      maxConcurrent = 3;
      models = {
        "qwen3.5-4b" = {
          contextLength = 32768;  # 32K
          speed = 300;
        };
        "qwen3.5-2b" = {
          contextLength = 16384;  # 16K
          speed = 400;
        };
      };
    };

    # Fallback to Z.ai
    zai = {
      enable = true;
      apiKeyFile = "/run/agenix/zai-api-key";
    };
  };

  gateway = {
    enable = true;
    host = "127.0.0.1";
    port = 8080;
    logLevel = "INFO";
  };
};
```

---

## 4. Gateway Routing Logic

### 4.1 Model-to-Backend Mapping

```python
# modules/services/ai-inference/ai_inference_gateway/router.py

MODEL_BACKENDS = {
    # Large models - Zephyr only
    "qwen3.5-35b-a3b": {
        "backend": "tier1",
        "url": "http://127.0.0.1:1234",
        "max_concurrent": 1,
        "context": 262144,
        "speed": 110,
    },
    "qwen3.5-27b": {
        "backend": "tier1",
        "url": "http://127.0.0.1:1234",
        "max_concurrent": 1,
        "context": 262144,
        "speed": 150,
    },

    # Medium models - Forge primary, Zephyr overflow
    "qwen3.5-9b": {
        "backend": "tier2",
        "url": "http://forge:1234",
        "overflow_backend": "tier1",
        "max_concurrent": 2,
        "context": 65536,
        "speed": 200,
    },
    "crow-9b-opus-4.6-distill-heretic_qwen3.5": {
        "backend": "tier2",
        "url": "http://forge:1234",
        "overflow_backend": "tier1",
        "max_concurrent": 2,
        "context": 65536,
        "speed": 200,
    },

    # Small models - Nexus primary, Forge overflow
    "qwen3.5-4b": {
        "backend": "tier3",
        "url": "http://nexus:1234",
        "overflow_backend": "tier2",
        "max_concurrent": 3,
        "context": 32768,
        "speed": 300,
    },
    "qwen3.5-2b": {
        "backend": "tier3",
        "url": "http://nexus:1234",
        "overflow_backend": "tier2",
        "max_concurrent": 3,
        "context": 16384,
        "speed": 400,
    },
}

# Process type preferences
PROCESS_PREFERENCES = {
    "cortex": ["tier1"],  # Only large models
    "workers_complex": ["tier1"],
    "workers_standard": ["tier1", "tier2"],
    "workers_fast": ["tier2", "tier3"],
    "channels": ["tier2", "tier3"],  # Prefer medium/fast for interactivity
    "branches": ["tier2"],
    "compactor": ["tier3"],  # Fast summarization
}
```

### 4.2 Routing Algorithm

```python
async def route_request(
    model_id: str,
    process_type: Optional[str] = None,
    priority: str = "balanced"  # "latency", "quality", "balanced"
) -> Backend:
    """
    Route request to optimal backend based on:
    1. Model availability
    2. Current load
    3. Process type preferences
    4. Priority (latency vs quality)
    """

    # Get model config
    model_config = MODEL_BACKENDS.get(model_id)
    if not model_config:
        logger.warning(f"Unknown model: {model_id}, falling back to Z.ai")
        return fallback_to_zai()

    # Get primary backend
    backend_name = model_config["backend"]
    backend = backends[backend_name]

    # Check if backend has capacity
    if backend.active_requests < backend.max_concurrent:
        return backend

    # Try overflow backend
    if "overflow_backend" in model_config:
        overflow_name = model_config["overflow_backend"]
        overflow_backend = backends[overflow_name]

        if overflow_backend.available:
            logger.info(f"Routing {model_id} to overflow backend {overflow_name}")
            return overflow_backend

    # All backends at capacity, queue or return error
    logger.warning(f"All backends at capacity for {model_id}")
    raise BackendUnavailableError(
        f"No available backend for model {model_id}",
        retry_after=5  # Suggest retry in 5 seconds
    )
```

---

## 5. Network Configuration

### 5.1 Cluster Hosts

```nix
# /etc/nixos/modules/network/cluster-hosts.nix

{ config, lib, pkgs, ... }:

{
  options.services.cluster-hosts = {
    enable = lib.mkEnableOption "Cluster hostname resolution";

    hosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          ip = lib.mkOption {
            type = lib.types.str;
            description = "IP address";
          };
          aliases = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Hostname aliases";
          };
        };
      });
      default = {};
      description = "Cluster hosts mapping";
    };
  };

  config = lib.mkIf config.services.cluster-hosts.enable {
    networking.extraHosts = lib.concatStringsSep "\n" (
      lib.mapAttrsToList (hostname: host:
        "${host.ip} ${hostname} ${lib.concatStringsSep " " host.aliases}"
      ) config.services.cluster-hosts.hosts
    );
  };
}
```

### 5.2 Host Configuration

```nix
# /etc/nixos/hosts/zephyr/configuration.nix

services.cluster-hosts = {
  enable = true;
  hosts = {
    "forge" = {
      ip = "192.168.1.100";  # Replace with actual IP
      aliases = ["forge.local"];
    };
    "nexus" = {
      ip = "192.168.1.101";  # Replace with actual IP
      aliases = ["nexus.local"];
    };
    "zephyr" = {
      ip = "127.0.0.1";
      aliases = ["zephyr.local"];
    };
  };
};
```

### 5.3 Firewall Configuration

```nix
# /etc/nixos/hosts/zephyr/configuration.nix

networking.firewall = {
  enable = true;
  allowedTCPPorts = [8080];  # Gateway port

  # Allow cluster network
  extraCommands = ''
    iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 1234 -j ACCEPT
    iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 8080 -j ACCEPT
  '';
};
```

---

## 6. Implementation Plan

### Phase 1: Configure Forge (1-2 hours)
- [ ] Install LM Studio on forge
- [ ] Configure hardware-config.json (50/50 split)
- [ ] Download qwen3.5-9b-IQ4_NL.gguf (5.1GB)
- [ ] Configure context length (64K), KV cache quantization
- [ ] Enable API server on port 1234
- [ ] Test connectivity from zephyr: `curl http://forge:1234/v1/models`
- [ ] Verify model loading: `nvidia-smi` on forge

### Phase 2: Configure Nexus (1-2 hours)
- [ ] Install LM Studio on nexus
- [ ] Download qwen3.5-4b-IQ4_NL.gguf (2.5GB)
- [ ] Configure context length (32K), KV cache quantization
- [ ] Enable API server on port 1234
- [ ] Test connectivity from zephyr: `curl http://nexus:1234/v1/models`
- [ ] Verify model loading: `nvidia-smi` on nexus

### Phase 3: Update Gateway Configuration (2-3 hours)
- [ ] Create multi-backend NixOS module
- [ ] Update gateway.nix with tier1/tier2/tier3 backends
- [ ] Implement model-to-backend mapping in router.py
- [ ] Add overflow logic for tier2/tier3 models
- [ ] Add health checks for all backends
- [ ] Test gateway rebuild: `sudo nixos-rebuild test`

### Phase 4: Testing & Validation (2-3 hours)
- [ ] Test Cortex → Zephyr (35B, 256K context)
- [ ] Test Workers → Zephyr (27B)
- [ ] Test Channels → Forge (9B, 32K context)
- [ ] Test Compactor → Nexus (4B, 16K context)
- [ ] Measure throughput for each backend
- [ ] Test overflow scenarios (forge full → zephyr)
- [ ] Monitor VRAM usage during peak load
- [ ] Validate failover to Z.ai

### Phase 5: Spacebot Integration (1 hour)
- [ ] Update Spacebot configuration for new routing
- [ ] Test each Spacebot process with gateway
- [ ] Monitor performance metrics
- [ ] Validate end-to-end workflows

**Total Estimated Time: 7-11 hours**

---

## 7. Performance Expectations

### 7.1 Throughput by Backend

| Backend | Model | Context | Speed | Concurrent | Total Throughput |
|---------|-------|---------|-------|------------|------------------|
| **Zephyr** | qwen3.5-35b-a3b | 256K | 110 t/s | 1 | 110 t/s |
| **Zephyr** | qwen3.5-27b | 256K | 150 t/s | 1 | 150 t/s |
| **Forge** | qwen3.5-9b | 64K | 200 t/s | 2 | 400 t/s |
| **Nexus** | qwen3.5-4b | 32K | 300 t/s | 3 | 900 t/s |
| **Total** | - | - | - | - | **~1500 t/s** |

### 7.2 Latency by Process Type

| Process Type | Backend | First Token | Total Response | Notes |
|--------------|---------|-------------|----------------|-------|
| **Cortex** | Zephyr (35B) | 2-3s | Variable | 256K context, high quality |
| **Workers (complex)** | Zephyr (35B) | 2-3s | Variable | Multi-step tasks |
| **Workers (standard)** | Zephyr (27B) | 1-2s | Variable | Good balance |
| **Channels** | Forge (9B) | 0.5-1s | Fast | Interactive |
| **Compactor** | Nexus (4B) | 0.3-0.5s | Very fast | Summarization |

### 7.3 VRAM Utilization

**Normal Load:**
```
Zephyr: 25GB / 32GB (78%)
├─ Model: 17GB (35B A3B)
└─ KV cache: 8GB (256K quantized)

Forge: 14GB / 16GB (87%)
├─ GPU #1: 7GB (9B model)
└─ GPU #2: 7GB (9B model)

Nexus: 3GB / 8GB (37%)
└─ Model: 3GB (4B model)

Total: 42GB / 56GB (75%)
```

**Peak Load:**
```
All backends at capacity
Total: ~50GB / 56GB (89%)
Headroom: 6GB for KV cache growth
```

---

## 8. Monitoring & Metrics

### 8.1 Gateway Metrics

```python
# Prometheus metrics for multi-backend setup

# Backend health
backend_up{backend="zephyr", tier="tier1"} 1
backend_up{backend="forge", tier="tier2"} 1
backend_up{backend="nexus", tier="tier3"} 1

# Backend load
backend_active_requests{backend="zephyr"} 1
backend_active_requests{backend="forge"} 2
backend_active_requests{backend="nexus"} 3

# Model routing
model_requests_total{model="qwen3.5-35b-a3b", backend="zephyr"} 1234
model_requests_total{model="qwen3.5-9b", backend="forge"} 5678
model_requests_total{model="qwen3.5-4b", backend="nexus"} 9012

# Overflow routing
model_overflow_total{model="qwen3.5-9b", primary="forge", overflow="zephyr"} 45

# Latency by backend
backend_latency_ms{backend="zephyr", p50="500"} 500
backend_latency_ms{backend="forge", p50="300"} 300
backend_latency_ms{backend="nexus", p50="150"} 150

# Throughput
backend_tokens_per_second{backend="zephyr"} 110
backend_tokens_per_second{backend="forge"} 400
backend_tokens_per_second{backend="nexus"} 900
```

### 8.2 Health Check Endpoints

```bash
# Overall health
curl http://127.0.0.1:8080/health | jq .

# Expected output:
{
  "status": "healthy",
  "backends": {
    "zephyr": {
      "status": "healthy",
      "url": "http://127.0.0.1:1234",
      "active_requests": 1,
      "loaded_model": "qwen3.5-35b-a3b",
      "vram_used": "25GB / 32GB"
    },
    "forge": {
      "status": "healthy",
      "url": "http://forge:1234",
      "active_requests": 2,
      "loaded_model": "qwen3.5-9b",
      "vram_used": "14GB / 16GB"
    },
    "nexus": {
      "status": "healthy",
      "url": "http://nexus:1234",
      "active_requests": 3,
      "loaded_model": "qwen3.5-4b",
      "vram_used": "3GB / 8GB"
    }
  }
}
```

---

## 9. Troubleshooting

### 9.1 Common Issues

**Issue: Forge/Nexus unreachable from zephyr**
```bash
# Check network connectivity
ping forge
ping nexus

# Check port accessibility
nc -zv forge 1234
nc -zv nexus 1234

# Check firewall rules
sudo iptables -L -n | grep 1234
```

**Issue: Model not loading on forge/nexus**
```bash
# Check LM Studio is running on target machine
ssh forge "ps aux | grep -i lmstudio"

# Check model is downloaded
ssh forge "ls -lh ~/.lmstudio/models/"

# Check LM Studio logs
ssh forge "tail -f ~/.lmstudio/server-logs/*.log"
```

**Issue: Gateway routing to wrong backend**
```bash
# Check model-to-backend mapping
curl http://127.0.0.1:8080/metrics | grep model_requests

# Check gateway logs
journalctl -u ai-inference-gateway -f | grep -i routing
```

**Issue: Overflow routing not working**
```bash
# Check overflow metrics
curl http://127.0.0.1:8080/metrics | grep model_overflow

# Verify backend capacity
curl http://127.0.0.1:8080/health | jq .backends
```

### 9.2 Debug Commands

```bash
# Test each backend independently
echo "Testing Zephyr..."
curl -H "Authorization: Bearer $(cat /run/agenix/lm-studio-api-key)" \
  http://127.0.0.1:1234/v1/models | jq .

echo "Testing Forge..."
curl -H "Authorization: Bearer $(cat /run/agenix/lm-studio-api-key)" \
  http://forge:1234/v1/models | jq .

echo "Testing Nexus..."
curl -H "Authorization: Bearer $(cat /run/agenix/lm-studio-api-key)" \
  http://nexus:1234/v1/models | jq .

# Test gateway routing
echo "Testing Gateway routing..."
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.5-4b","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' | jq .

# Monitor all GPUs
watch -n 1 'echo "=== Zephyr ===" && nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader'
```

---

## 10. Success Criteria

✅ **Configuration Success:**
- [ ] All three LM Studio instances running (zephyr, forge, nexus)
- [ ] All backends reachable from gateway
- [ ] All models loaded and accessible
- [ ] Gateway routing configured correctly

✅ **Performance Success:**
- [ ] Cortex gets 110 t/s with 256K context
- [ ] Channels get 200 t/s with 32K context
- [ ] Compactor gets 300 t/s with 16K context
- [ ] Total throughput > 1000 t/s
- [ ] No backend exceeds 90% VRAM utilization

✅ **Reliability Success:**
- [ ] Overflow routing works (forge → zephyr, nexus → forge)
- [ ] Health checks detect backend failures
- [ ] Failover to Z.ai when all backends unavailable
- [ ] Zero downtime during model swaps

✅ **Integration Success:**
- [ ] All Spacebot processes route correctly
- [ ] End-to-end workflows functional
- [ ] No regression in Spacebot performance
- [ ] Metrics and monitoring operational

---

## Appendix A: Model Inventory

**Complete list of models in LM Studio:**

| Model ID | Size | File Size | Quantization | Context | Backend |
|----------|------|-----------|--------------|---------|---------|
| qwen3.5-35b-a3b | 35B | 17GB | IQ4_NL | 256K | Zephyr |
| qwen3.5-27b | 27B | 15GB | IQ4_NL | 256K | Zephyr |
| qwen3.5-9b | 9B | 5.1GB | IQ4_NL | 64K | Forge |
| crow-9b-opus-4.6-distill-heretic_qwen3.5 | 9B | 5GB | IQ4_NL | 64K | Forge |
| qwen3.5-9b-claude-4.6-opus-reasoning-distilled | 9B | 5GB | Q4_K_S | 64K | Forge |
| qwen3.5-4b | 4B | 2.5GB | IQ4_NL | 32K | Nexus |
| qwen3.5-4b-claude-4.6-opus-reasoning-distilled | 4B | 2.6GB | Q4_K_M | 32K | Nexus |
| qwen3.5-2b | 2B | 1.9GB | Q8_0 | 16K | Nexus |
| qwen3.5-0.8b | 0.8B | ~1GB | Q8_0 | 8K | Nexus |
| crow-4b-opus-4.6-distill-heretic_qwen3.5 | 4B | 2.4GB | IQ4_NL | 32K | Nexus |

---

## Appendix B: Network Diagram

```
                       ┌──────────────────────────────────────┐
                       │     Cluster Network (192.168.1.0/24)  │
                       └──────────────────────────────────────┘
                                          │
        ┌─────────────────────────────────┼─────────────────────────────────┐
        │                                 │                                 │
   ┌────▼─────┐                     ┌────▼─────┐                     ┌────▼─────┐
   │  Zephyr  │                     │   Forge  │                     │   Nexus  │
   │ 3090+Ti  │                     │  2x4060  │                     │  3060Ti  │
   │ 32GB VRAM│                     │ 16GB VRAM│                     │  8GB VRAM│
   └────┬─────┘                     └────┬─────┘                     └────┬─────┘
        │                                │                                │
        │ 1234 (LM Studio)               │ 1234 (LM Studio)              │ 1234 (LM Studio)
        │ 8080 (Gateway)                 │                                │
        └────────────────────────────────┴────────────────────────────────┘
                                           │
                                    ┌──────▼──────┐
                                    │  Spacebot   │
                                    │  Container  │
                                    │  :19898     │
                                    └─────────────┘
```

---

**Document Version**: 1.0
**Last Updated**: 2026-03-05
**Status**: ✅ Ready for Implementation
**Next Steps**: Begin Phase 1 (Configure Forge)
