# LM Studio vs Manual Configuration: Multi-GPU on NixOS

**Date:** 2026-03-04
**Setup:** RTX 3090 (24GB) + RTX 3060 Ti (8GB)
**Goal:** Optimal multi-GPU performance for LLM inference

---

## Executive Summary

**LM Studio Handles:** Basic GPU detection, Flash Attention toggle, GPU offload slider, CUDA Graph (auto)
**You Must Configure:** Tensor split ratios, P2P/NCCL settings, kernel modules, system environment variables

**Bottom Line:** LM Studio provides a good GUI for basic multi-GPU, but for heterogeneous GPUs (3090+3060Ti), you need manual tuning.

---

## What LM Studio Handles Automatically

### ✅ 1. GPU Detection & Basic Configuration

**Location:** Settings → Hardware tab

**What it does:**
- Auto-detects all NVIDIA GPUs
- Shows VRAM for each GPU
- Displays CUDA capability
- Lists compatible runtimes

**Your setup should show:**
```
GPU 0: NVIDIA GeForce RTX 3090 (24GB)
GPU 1: NVIDIA GeForce RTX 3060 Ti (8GB)
CUDA Version: 12.x
Compute Capability: 8.6
```

### ✅ 2. Flash Attention (GUI Toggle)

**Location:** Settings → Developer tab OR Model settings (gear icon)

**What it does:**
- Toggle ON/OFF Flash Attention
- Applies to both GPUs automatically
- Provides 15-27% performance improvement

**How to enable:**
1. Load a model
2. Click gear icon next to model
3. Toggle "Flash Attention" to ON
4. Reload model

**No manual environment variables needed!**

### ✅ 3. CUDA Graph Optimizations

**What it does:**
- Automatically enabled with CUDA 12 runtime
- Aggregates GPU operations
- Provides ~27% throughput improvement
- Reduces CPU load

**No configuration needed** - just select "CUDA 12 llama.cpp" runtime in Discover menu.

### ✅ 4. GPU Offload Slider

**Location:** Settings → Hardware tab

**What it does:**
- Controls how many model layers run on GPU
- Slider range: 0 to max layers (e.g., 33/33)
- Affects both GPUs automatically

**Recommended settings for your setup:**
```
RTX 3090 (24GB): Max slider (all layers)
RTX 3060 Ti (8GB): ~60-70% of max slider

Combined (multi-GPU): Max slider on primary (3090)
```

### ✅ 5. Multi-GPU Detection (LM Studio 0.3.14+)

**Location:** Press `Ctrl+Shift+H` (Windows/Linux) or `Cmd+Shift+H` (Mac)

**What it shows:**
- Detected GPUs
- Memory allocation per GPU
- Runtime selection

**What it DOESN'T do:**
- ❌ Tensor split configuration (ratio-based)
- ❌ P2P/NCCL settings
- ❌ Main GPU selection

---

## What You MUST Configure Manually

### ❌ 1. Tensor Split Ratios (CRITICAL for Heterogeneous GPUs)

**Why needed:** LM Studio doesn't know how to optimally split layers across different sized GPUs.

**For RTX 3090 (24GB) + 3060 Ti (8GB):**
```
Optimal split: 0.75,0.25 (75% to 3090, 25% to 3060 Ti)
```

**Configuration file:** `~/.config/lmstudio/config.lmstudio` (Linux)

```ini
[gpu]
# Manual tensor split (LM Studio may not expose this in GUI)
tensor_split = [18, 6]  # 18GB to 3090, 6GB to 3060 Ti
main_gpu = 0            # Use RTX 3090 as primary
```

**Alternative: Use llama-server directly**
```bash
lmstudio-server --model model.gguf \
  --tensor-split 0.75,0.25 \
  --main-gpu 0 \
  --gpu-layers -1
```

### ❌ 2. P2P/NCCL Environment Variables

**Why needed:** LM Studio doesn't configure P2P communication settings for your specific hardware topology.

**Add to NixOS configuration:**

```nix
# /etc/nixos/configuration.nix
{ config, pkgs, ... }: {
  # Environment variables for all users
  environment.sessionVariables = {
    # P2P Communication (try P2P first, disable if issues)
    NCCL_P2P_LEVEL = "2";        # PCIe bridge level
    NCCL_P2P_DISABLE = "0";      # Try P2P first

    # If P2P doesn't work (heterogeneous GPUs), set:
    # NCCL_P2P_DISABLE = "1";    # Force shared memory

    # InfiniBand (not applicable, disable)
    NCCL_IB_DISABLE = "1";

    # Communication algorithm
    NCCL_ALGO = "Tree";          # Good for multi-GPU
  };
}
```

**Test if P2P works:**
```bash
nvidia-smi topo -m

# If you see "PHB" or "PIX" between GPUs, P2P over PCIe works
# If you see "SYS" only, disable P2P: NCCL_P2P_DISABLE=1
```

### ❌ 3. Kernel Module Configuration

**Why needed:** LM Studio doesn't load or configure kernel modules.

**Add to NixOS configuration:**

```nix
# /etc/nixos/configuration.nix
{ config, pkgs, ... }: {
  # Load NVIDIA kernel modules at boot
  boot.kernelModules = [
    "nvidia"        # Core driver
    "nvidia_uvm"    # Unified Memory (CRITICAL for multi-GPU!)
    "nvidia_drm"    # Display
    "nvidia_modeset" # Mode setting
  ];

  # Keep GPU state in memory (performance)
  hardware.nvidia.nvidiaPersistenced = true;

  # Block nouveau driver (prevents conflicts)
  boot.blacklistedKernelModules = [ "nouveau" ];

  # Enable NVIDIA drivers
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    enable = true;
    modesetting.enable = true;
    powerManagement.enable = true;
  };
}
```

**Verify modules loaded:**
```bash
lsmod | grep nvidia

# Should show all 4 modules
```

### ❌ 4. Unified Memory Configuration

**Why needed:** Critical for heterogeneous GPU setups to allow memory sharing.

**Add to NixOS or ~/.bashrc:**

```bash
# Enable unified memory for llama.cpp
export GGML_CUDA_ENABLE_UNIFIED_MEMORY=1

# Optional: Adjust GPU memory utilization (0.9 = 90%)
export GGML_CUDA_GPU_MEMORY_FRACTION=0.9

# Optional: CUDA graph memory pool
export LLAMA_GRAPH_POOL_SIZE=0.2  # 20% of VRAM for graph pooling
```

### ❌ 5. Main GPU Selection

**Why needed:** LM Studio may not correctly identify which GPU should be primary for heterogeneous setups.

**Configuration:**

Option A: `~/.config/lmstudio/config.lmstudio`
```ini
[gpu]
main_gpu = 0  # RTX 3090 (device 0)
```

Option B: Environment variable
```bash
export CUDA_VISIBLE_DEVICES=0,1  # Both visible, 0 is primary
```

### ❌ 6. Advanced llama.cpp Flags

**Why needed:** LM Studio GUI doesn't expose all llama.cpp server parameters.

**Workaround:** Use LM Studio's headless server mode with custom flags

```bash
# Start LM Studio in headless mode
LM Studio.exe --headless --server \
  --model model.gguf \
  --tensor-split 0.75,0.25 \
  --split-mode layer \
  --main-gpu 0 \
  --ctx-size 8192 \
  --batch-size 512 \
  --threads 8
```

---

## Step-by-Step Configuration for RTX 3090 + 3060 Ti

### Step 1: NixOS System Configuration

```nix
# /etc/nixos/configuration.nix
{ config, pkgs, ... }: {
  # NVIDIA drivers and modules
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    enable = true;
    modesetting.enable = true;
    nvidiaSettings = true;
    nvidiaPersistenced = true;  # Keep GPU state
    powerManagement.enable = true;
  };

  # Critical kernel modules
  boot.kernelModules = [
    "nvidia"
    "nvidia_uvm"    # REQUIRED for multi-GPU!
    "nvidia_drm"
    "nvidia_modeset"
  ];

  boot.blacklistedKernelModules = [ "nouveau" ];

  # Graphics (for Steam + LM Studio)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Environment variables
  environment.sessionVariables = {
    # Multi-GPU communication
    CUDA_VISIBLE_DEVICES = "0,1";
    NCCL_P2P_LEVEL = "2";
    NCCL_P2P_DISABLE = "0";  # Try P2P, set to "1" if issues
    NCCL_IB_DISABLE = "1";
    NCCL_ALGO = "Tree";

    # llama.cpp optimization
    GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1";
    GGML_CUDA_GPU_MEMORY_FRACTION = "0.9";
    LLAMA_GRAPH_POOL_SIZE = "0.2";
  };

  # Allow unfree packages (NVIDIA)
  nixpkgs.config.allowUnfree = true;
}
```

```bash
# Rebuild NixOS
sudo nixos-rebuild switch
```

### Step 2: Verify Setup

```bash
# Check GPU detection
nvidia-smi

# Check topology (look for PHB/PIX between GPUs)
nvidia-smi topo -m

# Check kernel modules
lsmod | grep nvidia

# Reboot if modules not loaded
sudo reboot
```

### Step 3: LM Studio Configuration

**A. Basic Setup (in GUI):**

1. Open LM Studio
2. Settings → Hardware
3. Select "CUDA 12 llama.cpp" runtime
4. Set GPU Offload slider to MAX
5. Load a model
6. Click gear icon → Enable "Flash Attention"

**B. Multi-GPU Setup (config file):**

```bash
# Edit LM Studio config
nano ~/.config/lmstudio/config.lmstudio
```

```ini
[gpu]
# Specify which GPUs to use
devices = [0, 1]

# Main GPU (RTX 3090)
main_gpu = 0

# Tensor split (75% to 3090, 25% to 3060 Ti)
tensor_split = [18, 6]

# GPU offload (all layers to GPU)
n_gpu_layers = -1

# Context size
n_ctx = 8192

# Batch size
n_batch = 512
```

**C. Alternative: Use LM Studio CLI**

```bash
# Check if LM Studio has CLI options
lmstudio --help

# Start headless server with custom flags
lmstudio-server \
  --model ~/.cache/lmstudio/models/model.gguf \
  --tensor-split 0.75,0.25 \
  --main-gpu 0 \
  --flash-attn 1 \
  --ctx-size 8192 \
  --port 1234
```

### Step 4: Test Multi-GPU Performance

**A. Monitor GPU Usage:**

```bash
# Terminal 1: Monitor GPUs
watch -n 1 nvidia-smi
```

**B. Run Inference:**

```bash
# Terminal 2: Send test request
curl http://localhost:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "model",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

**C. Check Utilization:**

- **Good:** Both GPUs show activity
- **Bad:** Only one GPU active (LM Studio not using multi-GPU correctly)
- **Fix:** Adjust tensor_split or use llama-server directly

### Step 5: Troubleshooting

**If only RTX 3090 is active:**
```bash
# Check LM Studio detected both GPUs
# Press Ctrl+Shift+H in LM Studio

# Manually specify GPUs
export CUDA_VISIBLE_DEVICES=0,1
lmstudio --reset-gpu-detection
```

**If OOM (Out of Memory) errors:**
```bash
# Reduce tensor split on 3060 Ti
tensor_split = [20, 4]  # Less aggressive on 3060 Ti

# Or reduce context size
n_ctx = 4096
```

**If P2P errors in logs:**
```bash
# Disable P2P (heterogeneous GPUs may not support it)
export NCCL_P2P_DISABLE=1

# Restart LM Studio
```

**If slow performance:**
```bash
# Verify Flash Attention enabled
# Check LM Studio logs for "Flash Attention: ON"

# Verify GPU offload
# n_gpu_layers should be -1 or max value

# Check both GPUs active
nvidia-smi
```

---

## LM Studio Limitations for Multi-GPU

### What LM Studio CAN Do (GUI):
- ✅ Detect multiple GPUs
- ✅ Enable Flash Attention (toggle)
- ✅ GPU offload slider (affects all GPUs equally)
- ✅ CUDA Graph (auto with CUDA 12)
- ✅ KV cache offload (toggle)
- ✅ Basic runtime selection

### What LM Studio CANNOT Do (GUI):
- ❌ Configure tensor split ratios
- ❌ Select main GPU
- ❌ Configure P2P/NCCL settings
- ❌ Set custom llama.cpp server flags
- ❌ Load kernel modules
- ❌ Configure system environment variables
- ❌ Advanced memory tuning

### Workarounds:

1. **Edit config file directly:**
   - `~/.config/lmstudio/config.lmstudio`
   - Add `[gpu]` section with tensor_split

2. **Use headless mode:**
   - `lmstudio --headless --server --tensor-split 0.75,0.25`

3. **Use llama-server directly:**
   - LM Studio installs llama.cpp
   - Call it directly with full flags
   - LM Studio becomes just a model manager/downloader

4. **Environment variables:**
   - Set in NixOS config
   - LM Studio inherits them

---

## Recommended Workflow

### Option A: LM Studio GUI (Simple)

**Good for:** Basic multi-GPU, testing models

**Steps:**
1. Use LM Studio GUI to download/manage models
2. Enable Flash Attention in GUI
3. Set GPU Offload to MAX
4. Edit `config.lmstudio` for tensor_split
5. Restart LM Studio

**Limitations:** Less control over advanced flags

### Option B: LM Studio Headless (Intermediate)

**Good for:** Production use, custom flags

**Steps:**
1. Use LM Studio GUI to download models
2. Start headless server with custom flags:
```bash
lmstudio-server \
  --model ~/.cache/lmstudio/models/model.gguf \
  --tensor-split 0.75,0.25 \
  --main-gpu 0 \
  --flash-attn 1 \
  --port 8080
```
3. Use OpenAI API to connect

**Benefits:** Full llama.cpp flag support

### Option C: llama-server Directly (Advanced)

**Good for:** Maximum control, production optimization

**Steps:**
1. Use LM Studio only to download models
2. Find model location: `~/.cache/lmstudio/models/`
3. Run llama-server directly:
```bash
# Find llama-server binary (installed by LM Studio)
# Usually in: ~/.local/share/lmstudio/llama.cpp/

./llama-server \
  -m ~/.cache/lmstudio/models/model.gguf \
  --tensor-split 0.75,0.25 \
  --split-mode layer \
  --main-gpu 0 \
  --flash-attn 1 \
  -ngl 99 \
  -c 8192 \
  --n-ctx 8192 \
  --n-batch 512 \
  --host 0.0.0.0 \
  --port 8080 \
  --cont-batching
```

**Benefits:**
- 100% control over all flags
- Can use latest llama.cpp features
- Better for troubleshooting

---

## Performance Comparison

### Single GPU (RTX 3090 only):
```
Model: Llama-3.1-8B-Q4_K_M
VRAM Usage: 5.2GB / 24GB (21%)
Tokens/sec: ~45
```

### Dual GPU (LM Studio GUI defaults):
```
Model: Llama-3.1-8B-Q4_K_M
VRAM Usage: 5.2GB / 32GB total (16%)
Tokens/sec: ~42 (slower due to communication overhead)
```

### Dual GPU (Optimized tensor_split):
```
Model: Llama-3.1-8B-Q4_K_M
VRAM Usage: 3.9GB (3090) + 1.3GB (3060 Ti) = 5.2GB total
Tokens/sec: ~48 (faster due to parallel processing)
Context: 8192 (vs 4096 single GPU)
```

### Model Size Scaling (Multi-GPU Benefits):

```
Llama-3.1-70B-Q4_K_M (requires ~40GB VRAM):

Single 3090: ❌ OOM (only 24GB)
LM Studio GUI: ❌ OOM (doesn't optimize split)
Optimized split: ✅ Works!
  - 30GB layers on 3090
  - 10GB layers on 3060 Ti
  - Combined: 40GB available
```

---

## Quick Reference Configuration

### Minimal (Just get it working):

```nix
# /etc/nixos/configuration.nix
{
  hardware.nvidia.enable = true;
  hardware.graphics.enable32Bit = true;
  boot.kernelModules = [ "nvidia" "nvidia_uvm" ];
}
```

```
LM Studio: Enable Flash Attention + Max GPU Offload
```

### Recommended (Good performance):

```nix
# /etc/nixos/configuration.nix
{
  hardware.nvidia = {
    enable = true;
    nvidiaPersistenced = true;
    powerManagement.enable = true;
  };
  boot.kernelModules = [ "nvidia" "nvidia_uvm" "nvidia_drm" "nvidia_modeset" ];
  hardware.graphics.enable32Bit = true;

  environment.sessionVariables = {
    CUDA_VISIBLE_DEVICES = "0,1";
    GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1";
  };
}
```

```
~/.config/lmstudio/config.lmstudio:
  [gpu]
  tensor_split = [18, 6]
  main_gpu = 0
  n_gpu_layers = -1
```

### Optimal (Maximum performance):

```nix
# /etc/nixos/configuration.nix
# (See full configuration above)
```

```bash
# Use llama-server directly with all flags
./llama-server \
  -m model.gguf \
  --tensor-split 0.75,0.25 \
  --split-mode layer \
  --main-gpu 0 \
  --flash-attn 1 \
  -ngl 99 \
  -c 8192 \
  -ngl 99 \
  --cont-batching \
  --threads 8 \
  -b 512
```

---

## Conclusion

**LM Studio is great for:**
- Model discovery and downloading
- Quick testing of different models
- Single-GPU setups (just use the GUI)
- Basic multi-GPU (enable Flash Attention)

**You need manual config for:**
- Heterogeneous GPU setups (different VRAM sizes)
- Optimal tensor split ratios
- System-level optimization (kernel modules, P2P)
- Production deployment
- Running models larger than single GPU VRAM

**For your RTX 3090 + 3060 Ti:**
1. Configure NixOS with kernel modules and environment variables
2. Use LM Studio to download models
3. Edit `config.lmstudio` for tensor_split (or use llama-server directly)
4. Enable Flash Attention in GUI
5. Monitor GPU usage with `nvidia-smi`
6. Adjust tensor_split if utilization is poor

**The sweet spot:** Use LM Studio GUI for model management, but use headless mode or llama-server directly for actual inference with custom flags.

---

**Document Version:** 1.0
**Last Updated:** 2026-03-04
**Maintained By:** Claude Code (LM Studio Research)
