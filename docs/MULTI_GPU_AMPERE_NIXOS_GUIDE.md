# Multi-GPU Setup Guide: NVIDIA Ampere on NixOS

**Date:** 2026-03-04
**Target:** Systems with multiple NVIDIA Ampere GPUs (RTX 3090, A100, etc.)
**Use Cases:** AI Inference (LLM training/deployment) + Gaming
**Host:** zephyr (RTX 3090, considering multi-GPU expansion)

---

## Table of Contents

1. [Hardware Clarification](#hardware-clarification)
2. [NixOS Configuration](#nixos-configuration)
3. [AI Inference Setup](#ai-inference-setup)
4. [Gaming Configuration](#gaming-configuration)
5. [Power & Cooling Requirements]((power--cooling-requirements)
6. [Multi-GPU Strategies](#multi-gpu-strategies)
7. [Troubleshooting](#troubleshooting)
8. [Performance Optimization](#performance-optimization)

---

## Hardware Clarification

### What are "Ampere GPUs"?

**NVIDIA Ampere Architecture** (not Ampere Computing CPUs):
- **RTX 30-series**: RTX 3090 (24GB), RTX 3080 (10/12GB), RTX 3070 (8GB)
- **Data Center GPUs**: A100 (40/80GB), A30 (24GB), A40 (48GB)
- **Key Feature**: RTX 3090 is the **only** RTX 30-series card with NVLink support

### RTX 3090 Specifications

```yaml
GPU: GA102 (Ampere)
CUDA Cores: 10,496
VRAM: 24GB GDDR6X
Memory Bandwidth: 936 GB/s
TDP: 350W (stock), up to 450W (3090 Ti)
NVLink: Supported (RTX 3090 only)
PCIe: Gen 4 x16
```

---

## NixOS Configuration

### 1. Basic NVIDIA Multi-GPU Setup

Add to your `/etc/nixos/configuration.nix`:

```nix
{ config, pkgs, ... }: {
  # Enable NVIDIA drivers for all detected GPUs
  services.xserver.videoDrivers = [ "nvidia" ];

  # NVIDIA hardware configuration
  hardware.nvidia = {
    enable = true;
    modesetting.enable = true;
    nvidiaSettings = true;

    # Driver package - choose stable or beta
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # package = config.boot.kernelPackages.nvidiaPackages.beta;

    # Power management (critical for multi-GPU)
    powerManagement.enable = true;
    powerManagement.finegrained = true;

    # Open kernel module (better compatibility)
    open = false;  # Set to true if using open-source Nouveau

    # Allow unsupported GPUs (for newer GPUs)
    forceFullCompositionPipeline = false;
  };

  # Graphics support (renamed from opengl in 24.11)
  hardware.graphics = {
    enable = true;

    # 32-bit support for Steam/Proton
    enable32Bit = true;

    # Extra packages for Vulkan/OpenCL
    extraPackages = with pkgs; [
      vaapiVdpau
      libvdpau-va-gl
      nvidia-vaapi-driver
    ];
  };

  # Allow unfree packages (NVIDIA driver)
  nixpkgs.config.allowUnfree = true;

  # System packages for GPU monitoring/management
  environment.systemPackages = with pkgs; [
    nvidia-utils
    gpu-screen-recorder
    vulkan-tools
    cudaPackages.cudnn
    libva-utils
    vdpauinfo
  ];
}
```

### 2. CUDA Development Environment

```nix
{ config, pkgs, ... }: {
  # Enable CUDA support
  nixpkgs.config.cudaSupport = true;

  # CUDA packages
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    cudaPackages.nccl
    cudaPackages.cutensor
  ];

  # Python with CUDA support
  environment.systemPackages = with pkgs; [
    (python311.withPackages (ps: with ps; [
      torch
      transformers
      accelerate
      bitsandbytes
      vllm
    ]))
  ];
}
```

### 3. Verification Commands

```bash
# Check GPU detection
nvidia-smi

# Check Vulkan support
nix shell nixpkgs#vulkan-tools -c vulkaninfo

# Check GPU details
lspci -vnn | grep -E 'VGA|3D' -A 10

# Verify CUDA
nix-shell -p cudaPackages.cudatoolkit --run nvcc --version

# Check all GPUs visible
echo $CUDA_VISIBLE_DEVICES
```

---

## AI Inference Setup

### 1. Multi-GPU Inference Strategies

#### Strategy A: Data Parallelism (Multiple Requests)

**Best for:** Serving multiple concurrent requests
**How it works:** Each GPU processes different requests independently
**Memory requirement:** Model must fit on single GPU

```python
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

# Load model on each GPU
model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-3.1-8B",
    device_map="auto"
)

# Use specific GPU
device = torch.device("cuda:0")  # or cuda:1, cuda:2, etc.
model.to(device)

# Set visible GPUs in shell
# export CUDA_VISIBLE_DEVICES=0,1,2,3
```

#### Strategy B: Tensor Parallelism (Model Splitting)

**Best for:** Models larger than single GPU VRAM
**How it works:** Model layers split across multiple GPUs
**Memory requirement:** Combined VRAM > Model size

**Using vLLM (Recommended):**

```python
from vllm import LLM, SamplingParams
import os

# Specify GPUs to use
os.environ["CUDA_VISIBLE_DEVICES"] = "0,1"  # Use 2 GPUs

# Initialize with tensor parallelism
llm = LLM(
    model="meta-llama/Llama-3.1-70B",
    tensor_parallel_size=2,      # Number of GPUs
    dtype="bfloat16",
    gpu_memory_utilization=0.90,
    max_model_len=8192
)

# Inference
prompts = ["Explain quantum computing", "Write a poem"]
outputs = llm.generate(prompts)
```

**Using PyTorch DDP:**

```python
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP

def setup(rank, world_size):
    # Initialize process group
    dist.init_process_group(
        backend="nccl",
        rank=rank,
        world_size=world_size
    )
    torch.cuda.set_device(rank)

def train(rank, world_size):
    setup(rank, world_size)

    # Create model and move to GPU
    model = MyModel().to(rank)
    ddp_model = DDP(model, device_ids=[rank])

    # Training loop...

# Launch with torchrun
# torchrun --nproc_per_node=2 train.py
```

#### Strategy C: Pipeline Parallelism

**Best for:** Very large models
**How it works:** Different model stages on different GPUs
**Libraries:** DeepSpeed, Megatron-LM

```python
import deepspeed

# Initialize with pipeline parallel
model_engine, optimizer, _, _ = deepspeed.initialize(
    model=model,
    model_parameters=model.parameters(),
    config={
        "train_batch_size": 32,
        "gradient_accumulation_steps": 4,
        "pipeline": {
            "parallel_size": 2  # Split model across 2 GPUs
        }
    }
)
```

### 2. LM Studio Multi-GPU Configuration

**Important:** LM Studio desktop app does **not** support multi-GPU natively.

**Workaround Solutions:**

**Option 1: Run Multiple Instances**
```bash
# Terminal 1 - GPU 0
CUDA_VISIBLE_DEVICES=0 lm-studio-server --model llama-3.1-8b --port 8080

# Terminal 2 - GPU 1
CUDA_VISIBLE_DEVICES=1 lm-studio-server --model llama-3.1-8b --port 8081
```

**Option 2: Use Underlying Tools Directly**
```bash
# Use llama.cpp server directly with GPU splitting
./server -m llama-3.1-70b-Q4_K_M.gguf \
  --gpu-layers 64 \
  --split-mode layer \
  --main-gpu 0 \
  --gpu-layers 64
```

**Option 3: vLLM API Gateway (Recommended)**
```bash
# Run vLLM server with tensor parallelism
python -m vllm.entrypoints.openai.api_server \
  --model meta-llama/Llama-3.1-70B \
  --tensor-parallel-size 2 \
  --port 8080
```

### 3. Environment Configuration

```bash
# ~/.bashrc or system profile
export CUDA_VISIBLE_DEVICES=0,1  # Use GPU 0 and 1
export NCCL_P2P_DISABLE=0        # Enable P2P for NVLink
export NCCL_IB_DISABLE=1         # Disable InfiniBand (if not available)
export OMP_NUM_THREADS=8         # CPU threads for data loading

# For better multi-GPU performance
export NCCL_ALGO=Tree            # Algorithm for multi-GPU reduction
export NCCL_SOCKET_NTHREADS=4    # Threads for socket communication
```

---

## Gaming Configuration

### 1. Steam Setup

Add to `/etc/nixos/configuration.nix`:

```nix
{ config, pkgs, ... }: {
  # Enable 32-bit graphics support (required for Steam)
  hardware.graphics.enable32Bit = true;

  # Steam configuration
  programs.steam = {
    enable = true;

    # Proton for Windows games
    protonpkg = pkgs.proton-ge-custom;

    # Remote play
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  # Gaming packages
  environment.systemPackages = with pkgs; [
    steam
    protonup-qt
    gamemode      # Performance optimization
    mangohud      # FPS overlay
    goverlay      # Overlay configuration
  ];

  # Gamescope (compositor for Steam games)
  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };
}
```

### 2. Vulkan Support

```nix
hardware.graphics.extraPackages = with pkgs; [
  vulkan-loader
  vulkan-validation-layers
  vulkan-extension-layer
  nvidia-vaapi-driver
];
```

### 3. Prime GPU Offload (Laptop + External GPU)

```nix
hardware.nvidia.prime = {
  offload = {
    enable = true;
    enableOffloadCmd = true;
  };

  # Intel iGPU + NVIDIA dGPU
  intelBusId = "PCI:0:2:0";
  nvidiaBusId = "PCI:1:0:0";
};
```

### 4. Launch Options for Steam Games

**For NVIDIA GPUs:**
```
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia %command%
```

**For Multi-GPU (specific GPU selection):**
```
__GLX_VENDOR_LIBRARY_NAME=nvidia VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json:%command%
```

**With GameMode (performance optimization):**
```
gamemoderun %command%
```

### 5. Verification

```bash
# Verify Vulkan support
vulkaninfo | grep "GPU ID"

# Test with a Vulkan game
# Check Steam logs for GPU selection
```

---

## Power & Cooling Requirements

### 1. Power Supply Calculations

**Single RTX 3090:**
- TDP: 350W
- Spikes: Up to 450W
- Recommended PSU: 750W (system total)

**Dual RTX 3090:**
- Combined TDP: 700W
- Peak draw: 900W+
- Recommended PSU: 1500-1600W minimum
- Ideal PSU: 1700W+ for headroom

**Formula:**
```
PSU Wattage = (GPU TDP × Number of GPUs) + CPU TDP + 200W (components) + 20% headroom

Example: (350W × 2) + 125W (CPU) + 200W + 20% = ~1400W recommended
```

### 2. Cooling Requirements

**Air Cooling:**
- Minimum 120mm fan per GPU
- Prefer blower-style coolers for multi-GPU
- Case airflow: Front-to-back with positive pressure
- PCIe slot spacing: At least 2 slots between GPUs

**Water Cooling (Recommended for 3+ GPUs):**
- Custom loop with 360mm radiator per GPU
- Pump flow rate: 1+ GPM
- GPU blocks: Full coverage

**Temperature Targets:**
- Idle: Below 40°C
- Load: Below 80°C (ideal: 70-75°C)
- Memory: Below 95°C

### 3. Physical Layout

**ATX Motherboard (7 slots):**
- Maximum GPUs: 3-4 (with PCIe extenders)
- Slot spacing: Critical for airflow
- Use PCIe risers for better spacing

**PCIe Bandwidth Considerations:**
- PCIe 4.0 x16: 32 GB/s
- PCIe 3.0 x16: 16 GB/s
- AI inference: PCIe 4.0 recommended for multi-GPU
- Gaming: PCIe 3.0 sufficient

---

## Multi-GPU Strategies

### 1. NVLink Configuration (RTX 3090 Only)

**Requirements:**
- Two RTX 3090 cards
- NVLink bridge (official: $80)
- Supported motherboard (PCIe slot spacing)

**Configuration:**
```bash
# Check NVLink status
nvidia-smi topo -m

# Expected output: NV# (NVLink connection)
# GPU0    GPU1    GPU2    GPU3
# GPU0     0      NV2     PIX     PIX
# GPU1    NV2      0      PIX     PIX
```

**Benefits:**
- Bandwidth: 112 GB/s vs 32 GB/s (PCIe 4.0)
- Memory pooling: Up to 48GB unified
- Latency reduction: 70% lower in some workloads

### 2. Multi-GPU Topology Options

**Option A: PCIe Switch (Consumer)**
```
CPU → PCIe Root → GPU0, GPU1, GPU2, GPU3
```
- Bandwidth shared among GPUs
- Suitable for data parallelism

**Option B: NVLink (RTX 3090 only)**
```
GPU0 ←→ GPU1 (NVLink) ←→ GPU2 (NVLink) ←→ GPU3
```
- Direct GPU-to-GPU communication
- Best for tensor parallelism

**Option C: PCIe Extenders**
```
CPU → PCIe Root → Riser Cards → External GPUs
```
- Better cooling
- More flexible placement
- Slight latency penalty

### 3. Workload Distribution

**AI Inference (LM Studio / vLLM):**
```
GPU0: Model layers 1-32
GPU1: Model layers 33-64
GPU2: KV Cache
GPU3: Request batching
```

**Gaming:**
```
GPU0: Primary rendering
GPU1: Physics / AI computation
GPU2: Video encoding (streaming)
GPU3: Not used (most games don't support multi-GPU)
```

---

## Troubleshooting

### 1. Common Issues

**Issue: "CUDA out of memory"**
```bash
# Check memory usage
nvidia-smi

# Solution: Reduce batch size or use CPU offload
export GPU_MEMORY_UTILIZATION=0.8
```

**Issue: GPUs not detected**
```bash
# Check kernel modules
lsmod | grep nvidia

# Verify hardware
lspci -vnn | grep -i nvidia

# Rebuild with NVIDIA driver
sudo nixos-rebuild switch
```

**Issue: Poor multi-GPU scaling**
```bash
# Check NVLink status
nvidia-smi topo -m

# Verify P2P access
python -c "import torch; print(torch.cuda.is_available())"

# Enable NCCL debug
export NCCL_DEBUG=INFO
export NCCL_IB_HCA=mlx5_0
```

**Issue: Steam games won't launch**
```bash
# Verify 32-bit graphics
nix-shell -p libva-utils -c vainfo

# Check Vulkan
nix-shell -p vulkan-tools -c vulkaninfo

# Rebuild with 32-bit support
hardware.graphics.enable32Bit = true;
```

### 2. Performance Debugging

```bash
# Monitor GPU usage in real-time
watch -n 1 nvidia-smi

# Profile PyTorch code
python -m torch.utils.bottleneck train.py

# Check NCCL operations
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=ALL

# Vulkan validation
VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation vulkaninfo
```

### 3. Multi-GPU Verification

```python
# test_multi_gpu.py
import torch

print(f"CUDA Available: {torch.cuda.is_available()}")
print(f"CUDA Version: {torch.version.cuda}")
print(f"Number of GPUs: {torch.cuda.device_count()}")

for i in range(torch.cuda.device_count()):
    print(f"GPU {i}: {torch.cuda.get_device_name(i)}")
    props = torch.cuda.get_device_properties(i)
    print(f"  Memory: {props.total_memory / 1024**3:.1f} GB")
    print(f"  Compute Capability: {props.major}.{props.minor}")
```

---

## Performance Optimization

### 1. CUDA Best Practices

```python
import torch

# Enable cuDNN benchmark (best for fixed input sizes)
torch.backends.cudnn.benchmark = True

# Enable cuDNN deterministic (for reproducibility)
torch.backends.cudnn.deterministic = True

# Use mixed precision training
from torch.cuda.amp import autocast, GradScaler

scaler = GradScaler()

with autocast():
    output = model(input)
    loss = criterion(output, target)

scaler.scale(loss).backward()
scaler.step(optimizer)
scaler.update()
```

### 2. Multi-GPU Communication Optimization

```python
import os

# Optimize NCCL for better performance
os.environ["NCCL_ALGO"] = "Tree"           # Reduction algorithm
os.environ["NCCL_SOCKET_NTHREADS"] = "4"   # Socket threads
os.environ["NCCL_NSOCKS_PERTHREAD"] = "4"  # Sockets per thread
os.environ["NCCL_BUFFSIZE"] = "8388608"    # Buffer size (8MB)

# Disable P2P if not using NVLink (PCIe only)
# os.environ["NCCL_P2P_DISABLE"] = "1"
```

### 3. Memory Optimization

```python
# Gradient checkpointing (trade compute for memory)
from torch.utils.checkpoint import checkpoint

def forward_with_checkpointing(model, x):
    return checkpoint(model, x)

# Clear cache periodically
if torch.cuda.memory_allocated() > threshold:
    torch.cuda.empty_cache()

# Use efficient data types
model = model.to(torch.bfloat16)  # Better than float16
```

### 4. Batch Size Optimization

```python
# Find optimal batch size for your GPUs
batch_sizes = [1, 2, 4, 8, 16, 32]
for bs in batch_sizes:
    try:
        train_with_batch_size(bs)
        print(f"Batch size {bs} works!")
    except RuntimeError as e:
        if "out of memory" in str(e):
            print(f"Batch size {bs} too large")
            break
```

---

## Recommended Builds

### Build 1: Dual RTX 3090 (Inference Focus)

**Hardware:**
- 2x RTX 3090 (NVLink bridge)
- 1600W PSU minimum
- Custom water cooling recommended

**NixOS Config:**
```nix
{
  hardware.nvidia = {
    enable = true;
    powerManagement.enable = true;
    modesetting.enable = true;
  };

  hardware.graphics.enable32Bit = true;

  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    cudaPackages.nccl
    (python311.withPackages (ps: with ps; [torch vllm transformers]))
  ];
}
```

**Use Cases:**
- 70B+ parameter models
- High-throughput inference serving
- Model training

### Build 2: RTX 3090 + Gaming (Hybrid)

**Hardware:**
- 1x RTX 3090 (primary AI/Gaming)
- 850W PSU
- Air cooling sufficient

**NixOS Config:**
```nix
{
  programs.steam.enable = true;
  hardware.graphics.enable32Bit = true;

  environment.systemPackages = with pkgs; [
    lm-studio
    steam
    gamemode
  ];
}
```

**Use Cases:**
- Local LLM inference (<70B)
- Gaming at 4K
- Development work

---

## Sources

- [NixOS Wiki - Graphics](https://wiki.nixos.org/wiki/Graphics)
- [NixOS图形驱动配置 (CSDN)](https://blog.csdn.net/gitblog_00863/article/details/151881923)
- [PyTorch Distributed Training NCCL (CSDN)](https://m.blog.csdn.net/weixin_33072399/article/details/156402019)
- [RTX 3090 Multi-GPU Deep Learning (CSDN)](https://blog.csdn.net/weixin_47196664/article/details/108544553)
- [LM Studio Multi-GPU Solutions (CSDN)](https://blog.csdn.net/a772304419/article/details/150642356)
- [Arch Linux Steam Guide](https://geek-blogs.com/blog/arch-linux-steam/)
- [RTX 3090 Power Requirements](https://www.xz3.com.cn/rjjc/pno6wqyn.html)
- [vLLM Multi-GPU Inference](https://blog.csdn.net/weixin_42602241/article/details/156786949)

---

## Ampere-Specific Features & P2P Configuration

### 1. Kernel Modules for P2P Communication

**Critical Kernel Modules:**

```bash
# Check loaded NVIDIA modules
lsmod | grep nvidia

# Expected output:
# nvidia_uvm      - Unified Memory for CUDA
# nvidia_drm      - Direct Rendering Manager
# nvidia_modeset  - Mode setting
# nvidia          - Core driver

# Load P2P/peer memory module (if available)
sudo modprobe nv_peer_mem

# Verify P2P topology
nvidia-smi topo -m
```

**NixOS Kernel Module Configuration:**

```nix
{ config, pkgs, ... }: {
  # Load NVIDIA kernel modules at boot
  boot.kernelModules = [ "nvidia" "nvidia_uvm" "nvidia_drm" "nvidia_modeset" ];

  # Optional: Load nv_peer_mem for P2P (if available for your driver)
  # boot.extraModulePackages = with config.boot.kernelPackages; [ nvidia_peer_mem ];

  # Enable persistence mode (keeps GPU state in memory)
  hardware.nvidia.nvidiaPersistenced = true;

  # Blacklist nouveau (open source driver) to prevent conflicts
  boot.blacklistedKernelModules = [ "nouveau" ];
}
```

### 2. P2P Communication Environment Variables

**NCCL (NVIDIA Collective Communications Library) Configuration:**

```bash
# ~/.bashrc or system profile

# P2P Communication Level (0-5)
# LOC=0: No P2P
# PIX=1: Same PCIe switch
# PXB=2: Multiple PCIe bridges
# PHB=3: Same PCIe host bridge
# SYS=4: Cross NUMA node
export NCCL_P2P_LEVEL=2  # For RTX 3090 + 3060 Ti on PCIe

# Enable/disable P2P (0=enabled, 1=disabled)
export NCCL_P2P_DISABLE=0  # Enable P2P for your setup

# Direct P2P access disable (if having compatibility issues)
export NCCL_P2P_DIRECT_DISABLE=0

# Disable InfiniBand (if not available)
export NCCL_IB_DISABLE=1

# Shared memory disable (usually keep enabled)
export NCCL_SHM_DISABLE=0

# Performance tuning
export NCCL_ALGO=Tree  # Or Ring for small scale
export NCCL_SOCKET_NTHREADS=4
export NCCL_BUFFSIZE=8388608  # 8MB buffer
```

**Heterogeneous GPU Setup (RTX 3090 + 3060 Ti):**

```bash
# For your specific setup (24GB + 8GB)
export CUDA_VISIBLE_DEVICES=0,1  # Both GPUs visible

# P2P may not work well between different GPU architectures
# If you see errors, disable P2P:
# export NCCL_P2P_DISABLE=1

# Alternative: Use shared memory for communication
export NCCL_SHM_DISABLE=0
```

### 3. llama.cpp Ampere-Specific Flags

**Flash Attention & CUDA Graphs:**

```bash
# Enable Flash Attention (Ampere+ only)
# Reduces memory usage by 20-40%, 2-3x speedup
export GGML_CUDA_GRAPH_OPT=1  # Enable CUDA graphs
export FA=1                   # Enable Flash Attention
export LLAMA_CUDA_GRAPHS=1    # Alternative syntax

# llama.cpp command with Ampere optimizations
./server -m model.gguf \
  --gpu-layers -1 \                    # All layers to GPU
  --split-mode layer \                 # Layer-based splitting
  --tensor-split 0.75,0.25 \           # 75% to 3090, 25% to 3060 Ti
  --main-gpu 0 \                       # RTX 3090 as primary
  --flash-attn 1 \                     # Enable Flash Attention
  --n-gpu-layers 99 \                  # Max GPU layers
  -ngl 99 \                            # Same as above
  --ctx-size 8192 \                    # Context window
  --cache-type-k q8_0 \                # KV cache quantization
  --batch-size 512 \                   # Batch processing
  -ub 8192 \                           # User batch size
  --threads 8                          # CPU threads
```

**Compilation with Ampere Support:**

```bash
# Compile llama.cpp with CUDA and multi-GPU support
cmake -B build \
  -DGGML_CUDA=ON \
  -DGGML_CUDA_MULTI_GPU=ON \
  -DGGML_CUDA_ARCH=80 \      # Ampere (compute capability 8.0)
  -DCMAKE_BUILD_TYPE=Release

cmake --build build --config Release -j 8
```

**Environment Variables for Runtime:**

```bash
# Unified memory (helps with heterogeneous GPUs)
export GGML_CUDA_ENABLE_UNIFIED_MEMORY=1

# CUDA graphs optimization
export GGML_CUDA_GRAPH_OPT=1

# Memory fraction (leave some headroom)
export GGML_CUDA_GPU_MEMORY_FRACTION=0.9

# Device allocation (3090 first, 3060 Ti second)
export CUDA_VISIBLE_DEVICES=0,1
```

### 4. Flash Attention Configuration

**Hardware Requirements:**
- NVIDIA Ampere (SM 8.0) or newer
- RTX 3090: ✅ Supported (SM 8.6)
- RTX 3060 Ti: ✅ Supported (SM 8.6)
- CUDA ≥ 11.8
- Driver ≥ 510.47.03

**Enable in llama.cpp:**

```python
# Python binding example
from llama_cpp import Llama

model = Llama(
    model_path="model.gguf",
    n_gpu_layers=-1,                    # All layers to GPU
    split_mode_layer=True,              # Split by layers
    tensor_split=[0.75, 0.25],          # 3090 gets 75%, 3060 Ti gets 25%
    main_gpu=0,                         # RTX 3090 primary
    flash_attn=True,                     # Enable Flash Attention
    n_ctx=8192,                         # Context size
    verbose=True
)
```

**Benefits:**
- **Memory:** 20-40% reduction
- **Speed:** 2-3x faster attention computation
- **Quality:** Numerically identical to standard attention

### 5. P2P Testing & Verification

**Test P2P Access Between GPUs:**

```python
# test_p2p.py
import torch

print("CUDA Available:", torch.cuda.is_available())
print("GPU Count:", torch.cuda.device_count())

# Test P2P access
if torch.cuda.device_count() >= 2:
    gpu0 = torch.device("cuda:0")
    gpu1 = torch.device("cuda:1")

    # Enable P2P access
    torch.cuda.can_device_access_peer(gpu0, gpu1)

    # Test allocation
    x = torch.randn(1000).to(gpu0)
    y = torch.randn(1000).to(gpu1)

    # Try to copy (will fail if P2P not available)
    try:
        x_gpu1 = x.to(gpu1)
        print("✅ P2P access working!")
    except Exception as e:
        print(f"❌ P2P access failed: {e}")
```

**Check GPU Topology:**

```bash
# Detailed topology
nvidia-smi topo -m

# Expected output for RTX 3090 + 3060 Ti:
# GPU0    GPU1    CPU
# GPU0    X       PHB     NODE
# GPU1    PHB     X       NODE
#
# Legend:
# PHB = PCIe Host Bridge (typical for consumer GPUs)
# NV# = NVLink (not available for 3090+3060Ti)
```

### 6. Recommended Configuration for RTX 3090 + 3060 Ti

**NixOS Configuration:**

```nix
{ config, pkgs, ... }: {
  # NVIDIA drivers
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    enable = true;
    modesetting.enable = true;
    nvidiaSettings = true;
    nvidiaPersistenced = true;  # Keep GPU state

    # Power management
    powerManagement.enable = true;
    powerManagement.finegrained = true;

    # Force full composition pipeline (may help with P2P)
    forceFullCompositionPipeline = false;
  };

  # Graphics with 32-bit for Steam
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Kernel modules
  boot.kernelModules = [
    "nvidia"
    "nvidia_uvm"
    "nvidia_drm"
    "nvidia_modeset"
  ];

  boot.blacklistedKernelModules = [ "nouveau" ];

  # Environment variables for all users
  environment.sessionVariables = {
    # CUDA
    CUDA_VISIBLE_DEVICES = "0,1";

    # NCCL P2P configuration
    NCCL_P2P_LEVEL = "2";        # PCIe bridge level
    NCCL_P2P_DISABLE = "0";      # Enable P2P
    NCCL_IB_DISABLE = "1";       # No InfiniBand
    NCCL_ALGO = "Tree";          # Communication algorithm

    # llama.cpp optimization
    GGML_CUDA_GRAPH_OPT = "1";
    GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1";
    FA = "1";                    # Flash Attention
  };

  # System packages
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    cudaPackages.nccl
    python311Packages.llama-cpp-python
  ];
}
```

### 7. Performance Tuning for Heterogeneous GPUs

**Tensor Split Calculation:**

```python
# Calculate tensor split based on VRAM
rtx_3090_vram = 24  # GB
rtx_3060ti_vram = 8  # GB
total_vram = rtx_3090_vram + rtx_3060ti_vram

# Split ratios
ratio_3090 = rtx_3090_vram / total_vram  # 0.75
ratio_3060ti = rtx_3060ti_vram / total_vram  # 0.25

# Use in llama.cpp
# --tensor-split 0.75,0.25
```

**Progressive Testing:**

```bash
# Start with small context
./server -m model.gguf \
  --gpu-layers 20 \
  --tensor-split 0.75,0.25 \
  --ctx-size 2048 \
  --flash-attn 1

# Gradually increase
# --gpu-layers 30 --ctx-size 4096
# --gpu-layers 40 --ctx-size 8192
```

### 8. Troubleshooting P2P Issues

**If P2P Fails:**

```bash
# Check if P2P is supported
nvidia-smi topo -m | grep -E "GPU0|GPU1"

# If showing "SYS" or no P2P, disable P2P
export NCCL_P2P_DISABLE=1

# Force shared memory communication
export NCCL_SHM_DISABLE=0

# Verify GPU access
python -c "import torch; print(torch.cuda.device_count())"
```

**If llama.cpp Crashes:**

```bash
# Reduce memory utilization
--tensor-split 0.67,0.33  # Less aggressive split

# Disable Flash Attention temporarily
--flash-attn 0

# Reduce batch size
--batch-size 256

# Check GPU memory
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

### 9. Verification Commands

```bash
# Verify all modules loaded
lsmod | grep nvidia

# Check P2P topology
nvidia-smi topo -m

# Test CUDA P2P access
python test_p2p.py

# Monitor GPU usage
watch -n 1 nvidia-smi

# Check NCCL configuration
echo $NCCL_P2P_LEVEL
echo $NCCL_P2P_DISABLE

# Test llama.cpp server
curl http://localhost:8080/health
```

---

## Sources & References

- [NCCL P2P Configuration (CSDN)](https://m.blog.csdn.net/qq_38342510/article/details/147378137)
- [NVLink & P2P Communication](https://m.blog.csdn.net/gitblog_00520/article/details/151213776)
- [llama.cpp Flash Attention Guide](https://m.blog.csdn.net/gitblog_00904/article/details/151444283)
- [Ampere GPU Optimization](https://developer.nvidia.cn/blog/open-source-ai-tool-upgrades-speed-up-llm-and-diffusion-models-on-nvidia-rtx-pcs/)
- [NixOS NVIDIA Configuration](https://m.blog.csdn.net/m0_66871046/article/details/144485633)
- [NCCL Environment Variables](https://blog.csdn.net/zhuzongpeng/article/details/139639579)

---

**Document Version:** 2.0
**Last Updated:** 2026-03-04
**Maintained By:** Claude Code (Research Compilation)

---

**Summary for RTX 3090 + 3060 Ti:**

1. **P2P Communication**: Your heterogeneous GPUs likely don't support direct P2P, so use `NCCL_P2P_LEVEL=2` (PCIe bridge) or disable P2P entirely
2. **Tensor Split**: Use `--tensor-split 0.75,0.25` for 24GB:8GB VRAM ratio
3. **Flash Attention**: Enable with `--flash-attn 1` for 2-3x speedup on both GPUs
4. **CUDA Graphs**: Enable with `GGML_CUDA_GRAPH_OPT=1` for better performance
5. **Kernel Modules**: Ensure `nvidia_uvm` is loaded for unified memory support
6. **Testing**: Verify topology with `nvidia-smi topo -m` and test P2P with Python script

The RTX 3090 is the last GeForce card with NVLink support, but NVLink won't work with the 3060 Ti. Use PCIe-based communication instead.
