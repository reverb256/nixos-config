# llama.cpp Cache Types Research

## Executive Summary

**Issue**: Different llama.cpp builds support different KV cache compression types. The `turbo4` cache type is only available in TurboQuant builds, not standard llama.cpp.

**Current Status**: All deployments use `iq4_nl` cache type (compatible with both standard and TurboQuant builds).

---

## Build Types and Cache Support

### 1. Standard llama.cpp (b8781)

**Location**: `/nix/store/my0by0xlv2a1ss9bqz9z5fkr34p306dx-llama-cpp-b8781`

**Build Flags**:
```nix
GGML_CUDA = ON
GGML_CUDA_F16 = ON
GGML_NATIVE = OFF
BUILD_SHARED_LIBS = ON
CMAKE_CUDA_ARCHITECTURES = "86;89"  # RTX 3090 (sm_86) + RTX 3060 Ti (sm_89)
```

**Supported Cache Types**:
- `f16` - Full precision (default, highest quality)
- `f8_e4m3` - 8-bit floating point
- `f8_e5m2` - 8-bit floating point (alternative)
- `q8_0` - 8-bit integer quantization
- `q6_k` - 6-bit k-quantization
- `q5_k` - 5-bit k-quantization
- `q4_k` - 4-bit k-quantization
- `iq4_nl` - 4-bit non-linear quantization (recommended for RTX 30-series)
- `iq4_xs` - 4-bit extra-small quantization

**❌ NOT SUPPORTED**: `turbo4`, `tbq4`, `tcq` (TurboQuant-only)

### 2. TurboQuant llama.cpp (v1.7.0)

**Location**: `/data/projects/own/llama-cpp-turboquant` (source), built as Nix package

**Build Flags**:
```nix
GGML_CUDA = ON
GGML_CUDA_F16 = ON
GGML_CUDA_FA = ON           # Flash Attention
GGML_CUDA_FA_ALL_QUANTS = ON  # Flash Attention for all quantization types
GGML_AVX2 = ON              # x86-64-v2 CPU optimizations
GGML_FMA = ON
GGML_F16C = ON
CMAKE_CUDA_ARCHITECTURES = "86;89"
```

**Additional Features**:
- TriAttention integration
- Polar Derotate + Tangent Residual
- TCQ (Trellis-Coded Quantization) for KV cache

**Supported Cache Types** (includes all standard types plus):
- `turbo4` / `t4` - TurboQuant TCQ compression (4-bit, ~70% VRAM savings)
- `tbq4` - Alternative TurboQuant quantization
- `iq4_nl` - 4-bit non-linear (standard compatibility mode)

**Performance**:
- Compresses KV cache from 4-6GB → 1.2GB at 65K context
- Enables dense models (Qwen 3.5 27B, Gemma 4 31B) with 130K+ context on RTX 3090
- Zero-loss compression quality

---

## Current Deployments

### Zephyr RTX 3090 (GPU 1) - Qwen3.6-35B-A3B

**Build**: TurboQuant v1.7.0
**Cache Type**: `iq4_nl` (K and V)
**Context**: 262,144 tokens
**VRAM Usage**: ~16.6GB model + KV cache (turbo4 compressed)

```nix
--cache-type-k iq4_nl
--cache-type-v iq4_nl
```

**Why iq4_nl instead of turbo4?**
- Comment in config says "turbo4 compressed" but actual flags use `iq4_nl`
- Possible reasons:
  1. Compatibility testing (iq4_nl works in both builds)
  2. Turbo4 may have issues with this specific model
  3. Configuration may not have been updated after testing

### Zephyr RTX 3060 Ti (GPU 0) - Qwen3.5-9B

**Build**: TurboQuant v1.7.0
**Cache Type**: `iq4_nl` (K and V)
**Context**: 262,144 tokens

```nix
--cache-type-k iq4_nl
--cache-type-v iq4_nl
```

### Sentry AMD RX 5600 XT - Qwen3.5-4B

**Build**: Standard llama.cpp (ROCm)
**Cache Type**: `iq4_nl` (K and V)
**Context**: 262,144 tokens

```nix
--cache-type-k iq4_nl
--cache-type-v iq4_nl
```

---

## Cache Type Performance Comparison

### VRAM Usage (per 1K tokens, approximate)

| Cache Type | VRAM per 1K tokens | Relative to f16 |
|------------|-------------------|-----------------|
| f16        | 512 KB            | 100% (baseline) |
| q8_0       | 256 KB            | 50%             |
| q4_k       | 128 KB            | 25%             |
| iq4_nl     | 128 KB            | 25%             |
| turbo4     | 128 KB            | 25%             |
| **tbq4**   | **64 KB**         | **12.5%**       |

### Quality Impact

| Cache Type | Quality Loss | Recommended For |
|------------|--------------|-----------------|
| f16        | None         | Maximum quality |
| q8_0       | Negligible   | General use     |
| iq4_nl     | Minimal      | RTX 30-series, best value |
| turbo4     | Minimal      | Long context, TurboQuant builds only |
| tbq4       | Low          | Maximum VRAM savings, TurboQuant only |

### Speed Impact

- **f16**: Slowest (highest memory bandwidth)
- **q8_0**: ~10% faster than f16
- **iq4_nl**: ~20% faster than f16
- **turbo4**: ~20% faster than f16 (similar to iq4_nl)

---

## GPU-Specific Recommendations

### RTX 3090 (24GB VRAM, sm_86)

**Recommended Cache Types**:
1. **turbo4** - Best for long context (130K+ tokens), requires TurboQuant build
2. **iq4_nl** - Best compatibility, works with all builds
3. **f16** - Use only if VRAM is not a constraint (<32K context)

**Configuration**:
```nix
# For TurboQuant build
--cache-type-k turbo4
--cache-type-v turbo4

# For standard build (or compatibility testing)
--cache-type-k iq4_nl
--cache-type-v iq4_nl
```

### RTX 3060 Ti (8GB VRAM, sm_89)

**Recommended Cache Types**:
1. **iq4_nl** - Best balance of quality and VRAM usage
2. **q4_k** - Alternative if iq4_nl not available
3. **f8_e4m3** - For models <4B parameters

**Configuration**:
```nix
--cache-type-k iq4_nl
--cache-type-v iq4_nl
```

### AMD RX 5600 XT (6GB VRAM, ROCm)

**Recommended Cache Types**:
1. **iq4_nl** - Best supported option
2. **q4_k** - Fallback option

**Configuration**:
```nix
--cache-type-k iq4_nl
--cache-type-v iq4_nl
```

---

## How to Query Available Cache Types

### Method 1: Check Binary Strings

```bash
strings /nix/store/<hash>-llama-cpp-*/bin/llama-server | grep "cache.*type"
```

### Method 2: Test Cache Type at Runtime

```bash
# Test if cache type is supported
llama-server --model /path/to/model.gguf --cache-type-k turbo4 --cache-type-v turbo4
# If unsupported, will print: "Unsupported cache type: turbo4"
```

### Method 3: Check Build Configuration

```bash
# For standard llama.cpp
cmake -LA /path/to/llama.cpp/build | grep -i cache

# For TurboQuant
# Check for GGML_CUDA_FA_ALL_QUANTS flag
```

---

## Migration Path

### From Standard llama.cpp to TurboQuant

1. **Build TurboQuant package** (already done in `/data/projects/own/llama-cpp-turboquant`)

2. **Update NixOS configuration** to use TurboQuant build:
```nix
# In kubernetes/modules/llama-servers.nix
command = [ "${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server" ]
```

3. **Update cache type flags**:
```nix
# Before (standard build)
--cache-type-k iq4_nl
--cache-type-v iq4_nl

# After (TurboQuant build)
--cache-type-k turbo4
--cache-type-v turbo4
```

4. **Deploy**:
```bash
just deploy zephyr
```

### Rollback Plan

If turbo4 causes issues, rollback to iq4_nl:
```nix
--cache-type-k iq4_nl
--cache-type-v iq4_nl
```

---

## Troubleshooting

### Error: "Unsupported cache type: turbo4"

**Cause**: Using standard llama.cpp build with TurboQuant-only cache type

**Solution**: Either:
1. Use `iq4_nl` cache type instead
2. Switch to TurboQuant build: `${pkgsWithOverlay.llama-cpp-turboquant}/bin/llama-server`

### Error: "symbol lookup error: libggml-cpu.so.0"

**Cause**: Library version mismatch between llama-cli and libggml

**Solution**: Rebuild system or use llama-server instead of llama-cli

### Poor Generation Quality with turbo4

**Cause**: Possible incompatibility with specific model architecture

**Solution**: Try `iq4_nl` or `f16` cache types

---

## Recommendations

### Immediate Actions

1. **Verify current cache type usage**:
```bash
kubectl get pods -n ai-inference -o yaml | grep -A 2 "cache-type"
```

2. **Test turbo4 on non-production**:
```bash
# Create test deployment with turbo4
kubectl apply -f kubernetes-manifests/ai-inference/turboquant-test.yaml
```

3. **Benchmark VRAM savings**:
```bash
# Monitor VRAM usage with iq4_nl
nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -l 1

# Compare with turbo4 after migration
```

### Long-term Strategy

1. **Migrate all NVIDIA deployments to TurboQuant** for better VRAM efficiency
2. **Keep AMD deployments on standard llama.cpp** with `iq4_nl`
3. **Use `iq4_nl` as default** for new deployments (maximum compatibility)
4. **Consider `turbo4` for long-context workloads** (>100K tokens)

---

## References

- **llama.cpp**: https://github.com/ggerganov/llama.cpp
- **TurboQuant**: https://github.com/AmesianX/TurboQuant
- **NixOS Configuration**: `/etc/nixos/kubernetes/modules/llama-servers.nix`
- **TurboQuant Package**: `/data/projects/own/llama-cpp-turboquant/package.nix`

---

**Last Updated**: 2026-04-23
**Status**: Research complete, awaiting migration decision
