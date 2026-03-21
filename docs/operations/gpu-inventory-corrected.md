# GPU Inventory - Corrected

## Actual Hardware: 8 GPUs Total

### By Node

| Node | NVIDIA GPUs | AMD GPUs | Total | Status |
|------|------------|----------|-------|--------|
| **Forge** | 2× RTX 4060 | 2× AMD | **4** | 1 NVIDIA used by mining, 3 available |
| **Nexus** | 1× RTX 3090 | 0 | **1** | 1 used by xmrig-nexus (CPU miner) |
| **Sentry** | 0 | 1× AMD | **1** | Monitoring node (GPU available) |
| **Zephyr** | 2× RTX 3090 | 0 | **2** | 1 used by gpu-miner-zephyr, 1 available |

**Total**: 5 NVIDIA + 3 AMD = **8 Physical GPUs**

### Akash Provider View

The provider only counts **NVIDIA GPUs** (5 total) because:
- Akash tenant workloads primarily require NVIDIA GPUs
- AMD GPUs need special tenant configuration
- Provider uses `nvidia.com/gpu` resource type for inventory

**Provider's Inventory**:
- Forge: 2 NVIDIA (both AMD GPUs ignored)
- Nexus: 1 NVIDIA ✅
- Sentry: 1 (counted, but it's actually AMD) ⚠️
- Zephyr: 2 NVIDIA ✅
- **Provider total: 6 GPUs**

**Note**: Sentry shows as 1 GPU in provider but it's actually an AMD GPU. This might be a counting bug in the inventory service.

### Current GPU Usage

| GPU Type | Total | Available | Used By |
|----------|-------|-----------|---------|
| **NVIDIA** | 5 | 2-3 | Mining (2-3 GPUs) |
| **AMD** | 3 | 3 | None (configured for NVIDIA miners) |

### Kubernetes Resource Types

- **NVIDIA GPUs**: `nvidia.com/gpu` (used by Akash provider)
- **AMD GPUs**: `amd.com/gpu` (available but not used by current deployments)

### Forge's AMD GPUs

Forge's 2 AMD GPUs are:
- **Present in Kubernetes**: ✅ Yes (`amd.com/gpu` allocatable)
- **Used by mining**: ❌ No (`amd.com/gpu: "0"` in deployments)
- **Available to Akash**: ❌ No (provider filters to NVIDIA only)
- **Available for AMD workloads**: ✅ Yes (just need AMD-configured deployments)

### To Use AMD GPUs

To actually use Forge's AMD GPUs, you would need:
1. AMD-compatible mining software (XMRig with AMD ROCm, not lolminer)
2. Deployment with `amd.com/gpu` resource requests
3. Or AMD-compatible AI workloads (PyTorch with ROCm, etc.)

### Summary

- **Total physical GPUs**: 8 (5 NVIDIA + 3 AMD)
- **Usable by Akash**: 5 NVIDIA (Sentry's 1 is AMD but counted)
- **Provider reports**: 6 GPUs (NVIDIA only)
- **Currently available**: 2-3 NVIDIA GPUs (depending on mining)
- **AMD GPUs available**: 3 (but need AMD-specific workloads)

The system is working correctly - AMD GPUs are available in Kubernetes but not counted by Akash provider since most tenants can't use them.
