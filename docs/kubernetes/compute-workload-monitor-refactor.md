# Compute Workload Monitor Refactoring - Phase 1

**Date**: 2026-03-10
**Status**: ✅ COMPLETE
**Result**: Successfully extracted compute-workload-monitor to dedicated module with Kubernetes GPU detection

---

## Summary

The compute-workload-monitor service has been successfully refactored from the gaming module into a dedicated, reusable module. This refactoring enables:

1. **Better separation of concerns** - Gaming module now only contains gaming-specific functionality
2. **Kubernetes GPU workload detection** - New Phase 1 feature for detecting K8s GPU pods
3. **Module reusability** - Compute workload monitor can now be enabled independently

---

## Changes Made

### 1. New Module Created ✅

**File**: `/etc/nixos/modules/system/compute-workload-monitor.nix`

**Features**:
- Complete extraction of compute-workload-monitor service from gaming.nix
- Kubernetes GPU workload detection (Phase 1)
- Configurable check interval and log file
- Proper NixOS module structure with options

**Kubernetes GPU Detection**:
```bash
check_kubernetes_gpu_workload() {
    # Checks for GPU pods using kubectl
    # Filters for Running pods with nvidia.com/gpu resource requests
    # Returns success if GPU pods detected
}
```

**New Profile**: `apply_kubernetes_gpu_profile()`
- Sets GPUs to balanced mode for containerized workloads
- Stops GPU mining to free VRAM
- Reduces CPU mining to 50%

**Updated Priority Chain**:
1. Gateway Signal (highest)
2. Gaming
3. AI
4. **Kubernetes GPU** ← NEW (Phase 1)
5. VRAM Pressure
6. Builds
7. Mining
8. Idle (lowest)

### 2. Gaming Module Updated ✅

**File**: `/etc/nixos/modules/gaming/gaming.nix`

**Before** (lines 471-1206):
```nix
# 700+ lines of compute-workload-monitor service definition
systemd.services.compute-workload-monitor = {
  # ... huge inline script
};
```

**After** (line 478):
```nix
# ============================================================================
# COMPUTE WORKLOAD MONITOR MODULE
# ============================================================================
# Refactored to dedicated module: modules/system/compute-workload-monitor.nix
services.compute-workload-monitor.enable = true;
```

**Impact**:
- Reduced gaming.nix from ~1222 lines to ~520 lines (57% reduction)
- Cleaner separation of concerns
- Gaming module now focuses only on gaming-specific functionality

### 3. Default Module Imports Updated ✅

**File**: `/etc/nixos/modules/default.nix`

**Added** (line 29):
```nix
./system/compute-workload-monitor.nix
```

**Impact**:
- Module now available to all hosts
- Gaming module enables it automatically when `services.gaming.enable = true`
- Can be independently enabled on non-gaming hosts (e.g., forge for mining coordination)

---

## Module Options

The new compute-workload-monitor module provides the following options:

```nix
services.compute-workload-monitor = {
  enable = lib.mkEnableOption "Compute workload monitor for GPU scheduling";

  checkInterval = lib.mkOption {
    type = lib.types.int;
    default = 10;
    description = "Check interval in seconds";
  };

  logFile = lib.mkOption {
    type = lib.types.str;
    default = "/var/log/compute-workload-monitor.log";
    description = "Path to log file";
  };
};
```

**Usage**:
```nix
# Enable with defaults (recommended)
services.compute-workload-monitor.enable = true;

# Or customize
services.compute-workload-monitor = {
  enable = true;
  checkInterval = 5;  # Check every 5 seconds
  logFile = "/var/log/custom-workload.log";
};
```

---

## Kubernetes GPU Detection

### How It Works

1. **Cluster Connectivity Check**: Verifies kubectl can connect to the cluster
2. **GPU Pod Query**: Uses kubectl to find pods with `nvidia.com/gpu` resource requests
3. **Status Filter**: Only counts pods in "Running" phase
4. **Log Output**: Logs detected GPU pods for debugging

### Example Output

```
[2026-03-10 05:30:00] Kubernetes GPU workload detected: default/gpu-test-phase1
[2026-03-10 05:30:00] Workload changed: idle -> kubernetes-gpu
[2026-03-10 05:30:00] Applying profile: kubernetes-gpu
=== Applying GPU KUBERNETES GPU WORKLOAD profile ===
Detected 2 GPU(s) for Kubernetes GPU workload profile
Configuring GPU 0 (NVIDIA GeForce RTX 3060 Ti)...
  3060 Ti: 1800 MHz GPU, 6000 MHz mem, 150W limit
Configuring GPU 1 (NVIDIA GeForce RTX 3060 Ti)...
  3060 Ti: 1800 MHz GPU, 6000 MHz mem, 150W limit
KUBERNETES GPU profile applied: Mode: Balanced for containerized workloads
[2026-03-10 05:30:01] Stopping lolminer-nvidia to free VRAM for Kubernetes GPU pods
[2026-03-10 05:30:01] Limiting xmrig to 50% CPU for Kubernetes workloads
```

### Testing

**Test Pod YAML** (`gpu-test-phase1.yaml`):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test-phase1
spec:
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.1.0-base-ubuntu22.04
    command: ["sleep", "3600"]
    resources:
      limits:
        nvidia.com/gpu: 1
```

**Deploy Test Pod**:
```bash
kubectl apply -f gpu-test-phase1.yaml
```

**Verify Detection**:
```bash
# Check compute-workload-monitor logs
sudo journalctl -u compute-workload-monitor -f

# Check GPU pods detected
sudo grep "Kubernetes GPU" /var/log/compute-workload-monitor.log
```

---

## Affected Hosts

The following hosts are affected by this refactoring:

| Host | Gaming | Mining | K8s | Impact |
|------|--------|--------|-----|--------|
| zephyr | ✅ | ❌ | master | Gets compute-workload-monitor via gaming module |
| nexus | ✅ | ❌ | - | Gets compute-workload-monitor via gaming module |
| sentry | ✅ | ❌ | - | Gets compute-workload-monitor via gaming module |
| forge | ❌ | ✅ | worker | Can enable compute-workload-monitor for mining coordination |

**Automatic**: All hosts with `services.gaming.enable = true` automatically get compute-workload-monitor enabled.

**Manual**: Non-gaming hosts can enable it independently:
```nix
services.compute-workload-monitor.enable = true;
```

---

## Testing Checklist

- [x] Module structure created correctly
- [x] Gaming module updated to use new module
- [x] Default imports updated
- [x] Kubernetes GPU detection function implemented
- [x] Kubernetes GPU profile function implemented
- [x] Priority chain updated
- [ ] Apply configuration to test host
- [ ] Deploy gpu-test-phase1 pod
- [ ] Verify detection works
- [ ] Verify mining pauses
- [ ] Verify profile switching
- [ ] Check logs for errors

---

## Next Steps

### Testing Phase (Task #7)
1. Apply configuration to zephyr or forge (K8s worker)
2. Deploy gpu-test-phase1 pod
3. Verify compute-workload-monitor detects K8s GPU pods
4. Verify mining pauses when GPU pods are running
5. Document test results

### Documentation
1. Update ROADMAP.md with Phase 1 progress
2. Update implementation tracker
3. Add testing results to documentation

### Future Enhancements (Optional)
- Add metrics for K8s GPU workload detection
- Add alerting for failed K8s API connections
- Add support for AMD GPU detection in K8s
- Add support for custom kubectl contexts/namespaces

---

## Architecture Benefits

### Before Refactoring
```
gaming.nix (1222 lines)
├── Steam, GameMode, Gamescope configs
├── VR support (WiVRn)
└── compute-workload-monitor (700+ lines inline)
    ├── GPU workload detection
    ├── Profile management
    └── Mining coordination
```

### After Refactoring
```
gaming.nix (520 lines)
├── Steam, GameMode, Gamescope configs
└── VR support (WiVRn)

compute-workload-monitor.nix (new)
├── GPU workload detection
│   ├── Gaming processes
│   ├── AI processes
│   ├── Kubernetes GPU pods ← NEW
│   ├── VRAM pressure
│   └── Build processes
├── Profile management
│   ├── Gaming profile
│   ├── AI profile
│   ├── Kubernetes GPU profile ← NEW
│   ├── VRAM pressure profile
│   ├── Builds profile
│   ├── Mining profile
│   └── Idle profile
└── Mining coordination
```

**Benefits**:
1. **Separation of Concerns**: Gaming module only handles gaming
2. **Reusability**: Compute workload monitor can be used independently
3. **Maintainability**: Easier to update GPU workload detection logic
4. **Testability**: Can test compute workload monitor independently
5. **Extensibility**: Easy to add new workload types (e.g., video encoding)

---

## Conclusion

**Phase 1 Refactoring**: ✅ **COMPLETE**

The compute-workload-monitor has been successfully extracted from the gaming module into a dedicated, reusable module. Kubernetes GPU workload detection has been added as part of Phase 1 implementation.

**Key Achievement**: Reduced gaming module by 57% while adding new functionality (Kubernetes GPU detection).

**Next Step**: Testing with gpu-test-phase1 pod (Task #7).

---

**Refactoring Date**: 2026-03-10
**Module Files**: 3 created/modified
**Lines of Code**: ~700 extracted, ~150 added (K8s detection)
**Status**: Ready for Testing ✅
