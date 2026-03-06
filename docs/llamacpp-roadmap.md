# llama.cpp Integration Roadmap

**Status**: Planned for Phase 2
**Priority**: Medium (alternative to LM Studio)
**Timeline**: Q2 2025

---

## Current State

### LM Studio Status
- ✅ **Version**: 0.4.6-1 (latest available)
- ✅ **GUI**: Works on NixOS
- ❌ **CLI**: Broken due to 32-bit library incompatibility
- ✅ **GPU Selection**: Via `CUDA_VISIBLE_DEVICES` environment variable

### Why llama.cpp?
1. **Native NixOS support** - No AppImage compatibility issues
2. **CLI-first** - Built for command-line operations
3. **Lightweight** - No GUI overhead
4. **Performance** - Direct llama.cpp backend, optimized inference
5. **OpenAI-compatible API** - Drop-in replacement for LM Studio backend

---

## Phase 1: Research & Planning

### Tasks
- [x] Research llama.cpp capabilities
- [x] Identify NixOS packaging options
- [ ] Review llama.cpp vs LM Studio feature parity
- [ ] Determine hardware requirements
- [ ] Plan integration with AI Inference Gateway

### Key Questions
1. **Model Support**: Which Qwen3.5 models are compatible?
2. **Vision Support**: Does llama.cpp support mmproj files?
3. **Multi-GPU**: Can it use 3090 + 3060Ti simultaneously?
4. **API Compatibility**: Drop-in for LM Studio's OpenAI API?

### Resources
- **GitHub**: https://github.com/ggerganov/llama.cpp
- **Docs**: https://llama-cpp.github.io/llama.cpp/
- **NixOS Package**: `llama-cpp` in nixpkgs
- **Discord**: https://discord.gg/5k7rS5pUWx

---

## Phase 2: Basic Setup

### 2.1 Install llama.cpp

```nix
# Add to configuration.nix
environment.systemPackages = with pkgs; [
  llama-cpp
];
```

Or build from source for latest nightly:

```nix
# Custom package for bleeding-edge
{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    (pkgs.llama-cpp.overrideAttrs (oldAttrs: {
      version = "nightly";
      src = pkgs.fetchFromGitHub {
        owner = "ggerganov";
        repo = "llama.cpp";
        rev = "master";  # Or specific commit
        sha256 = "";
      };
    }))
  ];
}
```

### 2.2 Verify Installation

```bash
# Check version
llama-cli --version

# List supported models
llama-cli --help | grep -A 20 "model"

# Test basic inference
llama-cli -m /path/to/model.gguf -p "Hello, world!"
```

---

## Phase 3: Model Compatibility

### 3.1 Convert Qwen Models to GGUF

LM Studio uses GGUF format. Need to verify:

```bash
# Check if Qwen models are already GGUF
# LM Studio stores models in: ~/.cache/lm-studio/models/

# Find Qwen models
find ~/.cache/lm-studio/models/ -name "*qwen*gguf*"

# If not GGUF, need conversion:
# llama.cpp doesn't directly support all LM Studio formats
```

### 3.2 Supported Models

| Model | LM Studio | llama.cpp | Status |
|-------|-----------|-----------|--------|
| qwen3.5-35b-a3b | ✅ GGUF | ⚠️ May need conversion | Test |
| qwen3.5-27b | ✅ GGUF | ⚠️ May need conversion | Test |
| qwen3.5-9b | ✅ GGUF | ⚠️ May need conversion | Test |
| qwen3.5-4b | ✅ GGUF | ⚠️ May need conversion | Test |
| qwen3.5-2b | ✅ GGUF | ⚠️ May need conversion | Test |
| qwen3.5-0.8b | ✅ GGUF | ⚠️ May need conversion | Test |

### 3.3 Vision Support

**Critical Question**: Does llama.cpp support Qwen3.5 vision (mmproj)?

- **Research**: Check llama.cpp documentation for CLIP/Vision support
- **Test**: Load qwen3.5-9b with mmproj file
- **Fallback**: Use LM Studio GUI for vision, llama.cpp for text-only

---

## Phase 4: Multi-GPU Support

### 4.1 GPU Configuration

```bash
# Check available GPUs
nvidia-smi --list-gpus

# Test multi-GPU with llama.cpp
llama-cli -m model.gguf \
  -ngl 99 \
  -sm row \
  --split-mode layer \
  --gpu-layers 30 \
  --n-gpu-layers 30 \
  --tensor-split 3090:24,3060Ti:8
```

### 4.2 GPU Selection Strategy

**Single GPU (3090)**:
```bash
CUDA_VISIBLE_DEVICES=1 llama-cli -m model.gguf
```

**Multi-GPU (3090 + 3060Ti)**:
```bash
llama-cli -m model.gguf \
  --tensor-split 3090:24,3060Ti:8 \
  --split-mode layer
```

---

## Phase 5: Server Mode

### 5.1 Start OpenAI-Compatible Server

```bash
llama-server --model model.gguf \
  --host 127.0.0.1 \
  --port 8081 \
  --ctx-size 8192 \
  --ngl 99 \
  --n-gpu-layers 30
```

### 5.2 Gateway Integration

**Option A**: Separate port (8081)
```python
# Router sends llama.cpp requests to port 8081
# LM Studio continues on port 8080
BACKEND_PORTS = {
    "lm-studio": 8080,
    "llama-cpp": 8081
}
```

**Option B**: Replace LM Studio entirely
```python
# Update router to prefer llama.cpp for CLI workloads
# Keep LM Studio GUI for model management
```

### 5.3 Performance Comparison

| Backend | Startup | Throughput | Memory | Notes |
|----------|---------|------------|---------|-------|
| LM Studio | ~10s | 73 t/s (35B) | 18GB | GUI overhead |
| llama.cpp | ~2s | TBD | TBD | CLI-native |

---

## Phase 6: Automation

### 6.1 Model Management

Create helper scripts for:
- Model conversion (if needed)
- Model loading/unloading
- GPU switching
- Performance benchmarking

### 6.2 NixOS Service

```nix
# llama-server service
systemd.services.llama-server = {
  description = "llama.cpp inference server";
  after = [ "network.target" ];
  wantedBy = [ "multi-user.target" ];

  serviceConfig = {
    Type = "simple";
    User = "j_kro";
    WorkingDirectory = "/home/j_kro/.cache/lm-studio/models";
    Environment = [
      "CUDA_VISIBLE_DEVICES=1"  # 3090 only
    ];
    ExecStart = "${pkgs.llama-cpp}/bin/llama-server \
      --model qwen3.5-9b.gguf \
      --host 127.0.0.1 \
      --port 8081 \
      --ctx-size 8192";
    Restart = "on-failure";
  };
};
```

---

## Phase 7: Benchmarking

### 7.1 Comparison Tests

Run same benchmark on both backends:

```bash
# LM Studio (baseline)
python3 /tmp/benchmark_single_model.py qwen3.5-9b

# llama.cpp (new)
# Modify benchmark script to use port 8081
python3 /tmp/benchmark_single_model_llamacpp.py qwen3.5-9b
```

### 7.2 Metrics to Track

- **TTFT** (Time to First Token)
- **Throughput** (tokens/second)
- **VRAM Usage**
- **CPU Usage**
- **Startup Time**
- **Model Loading Time**

---

## Phase 8: Production Readiness

### 8.1 Reliability Features

- [ ] Automatic model reloading
- [ ] Request queuing
- [ ] Error handling
- [ ] Health checks
- [ ] Metrics/Prometheus integration
- [ ] Graceful shutdown

### 8.2 Integration Testing

- [ ] Test with AI Inference Gateway
- [ ] Test with existing Spacebot workflows
- [ ] Test vision support (if available)
- [ ] Test multi-model routing
- [ ] Load testing

---

## Decision Criteria

### Use LM Studio GUI When:
- ✅ Managing model downloads
- ✅ Visual model inspection
- ✅ Casual testing
- ✅ Vision/multimodal tasks

### Use llama.cpp When:
- ✅ CLI automation required
- ✅ Production API server
- ✅ Maximum performance needed
- ✅ Scriptable operations
- ✅ CI/CD integration

### Hybrid Approach:
- **LM Studio**: Model management, GUI tasks, vision
- **llama.cpp**: Production API server, CLI workloads, automation

---

## Risks & Mitigations

### Risk 1: Model Conversion Complexity
**Mitigation**: Use LM Studio to download models, check if GGUF format works directly

### Risk 2: Missing Vision Support
**Mitigation**: Keep LM Studio GUI for vision tasks, use llama.cpp for text-only

### Risk 3: Multi-GPU Complexity
**Mitigation**: Start with single GPU, test multi-GPU after basic setup works

### Risk 4: Performance Regression
**Mitigation**: Benchmark thoroughly before replacing LM Studio in production

---

## Next Steps

### Immediate (Today)
1. ✅ Restore LM Studio GUI working state
2. ✅ Continue benchmarking with LM Studio + CUDA_VISIBLE_DEVICES
3. ✅ Create llama.cpp roadmap (this document)

### Short-term (This Week)
1. Install llama-cpp from nixpkgs
2. Test basic inference with one model
3. Compare performance with LM Studio
4. Test multi-GPU support

### Medium-term (This Month)
1. Integrate with AI Inference Gateway
2. Set up llama-server service
3. Benchmark all models
4. Decision: LM Studio + llama.cpp hybrid or llama.cpp only?

### Long-term (Q2 2025)
1. Full production deployment
2. Documentation updates
3. Automated model management
4. Performance optimization

---

## References

- [llama.cpp GitHub](https://github.com/ggerganov/llama.cpp)
- [llama.cpp Documentation](https://llama-cpp.github.io/llama.cpp/)
- [GGUF Model Format](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)
- [NixOS llama-cpp Package](https://search.nixos.org/packages?query=llama-cpp)
- [Qwen Models on HuggingFace](https://huggingface.co/Qwen)

---

## Appendix: Quick Reference Commands

```bash
# Start llama-server on 3090 only
CUDA_VISIBLE_DEVICES=1 llama-server \
  --model ~/.cache/lm-studio/models/qwen3.5-9b/ggml-model-q5_k_m.gguf \
  --host 127.0.0.1 \
  --port 8081 \
  --ctx-size 8192

# Test with curl
curl -X POST http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.5-9b","messages":[{"role":"user","content":"test"}]}'

# Monitor GPU usage
watch -n 1 nvidia-smi

# Check server logs
journalctl -u llama-server -f
```
