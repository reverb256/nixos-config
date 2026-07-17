# Compute Workload Monitor Refactoring - Phase 1 Complete

## Summary

Successfully split the 1665-line monolithic `compute-workload-monitor.nix` module into 3 focused, single-responsibility modules:

1. **gaming-detection.nix** (~380 lines) - Pure gaming detection
2. **gpu-profile-manager.nix** (~600 lines) - Host-level GPU power management
3. **mining-coordinator.nix** (~450 lines) - K8s-aware workload coordination

**Total:** 1430 lines (14% reduction) with significantly improved maintainability.

## Key Architectural Changes

### Before: Monolithic Module
```
compute-workload-monitor.nix (1665 lines)
├── Gaming detection (GameMode + GPU fallback)
├── GPU profile management (nvidia-smi commands)
├── PSI-based build detection
├── Service control (24 systemctl calls)
├── K8s manual scaling (4 kubectl scale commands)
└── YuniKorn ConfigMap patching
```

### After: Modular Design
```
gaming-detection.nix (380 lines)
├── GameMode daemon detection
├── GPU pattern fallback
├── Hysteresis countdown (3 checks)
└── Prometheus metric export

gpu-profile-manager.nix (600 lines)
├── GPU profile functions (6 profiles)
├── nvidia-smi power management
├── Workload detection loop
└── Host-level hardware control

mining-coordinator.nix (450 lines)
├── PSI-based build detection
├── K8s GPU workload detection
├── Profile request system
└── Volcano placeholder scaling (ONLY K8s interaction)
```

## Critical Design Decisions

### 1. GPU Profiles Remain Host-Level
**Rationale:** `nvidia-smi` commands cannot be moved to K8s because container runtimes don't expose this level of hardware control.

**Impact:** `gpu-profile-manager.nix` is a host-level module that will run on all nodes with NVIDIA GPUs.

### 2. Service Control Removed
**Before:** 24 `systemctl` calls managed mining services directly
**After:** K8s Volcano scheduler handles all pod preemption via priority classes

**Impact:** New modules are K8s-native and don't interfere with Volcano's preemption logic.

### 3. Inter-Module Communication
**Mechanism:** File-based state sharing (no IPC/sockets required)
- `/run/gaming-detection/gaming_state` - Gaming state for consumers
- `/run/mining-coordinator/requested-profile` - Profile requests from coordinator
- `/run/gpu-profile-manager/` - GPU state storage

**Rationale:** Simple, reliable, and works across systemd services without dependencies.

## Module Responsibilities

### gaming-detection.nix
**Purpose:** Detect gaming activity and export state

**Inputs:**
- GameMode daemon (`gamemoded -s`)
- GPU utilization patterns (nvidia-smi fallback)

**Outputs:**
- State file: `/run/gaming-detection/gaming_state`
- Prometheus metrics: `/var/lib/node_exporter/textfile_collector/gaming.prom`

**Key Features:**
- GameMode primary detection (authoritative)
- GPU pattern fallback (utilization variance)
- Hysteresis countdown (3 checks before resume)
- Zero service control (read-only monitoring)

### gpu-profile-manager.nix
**Purpose:** Apply GPU power profiles based on workload

**Inputs:**
- Gaming state (from `gaming-detection.nix`)
- Profile requests (from `mining-coordinator.nix`)
- K8s GPU workload detection

**Outputs:**
- `nvidia-smi` commands (host-level hardware control)

**Key Features:**
- 6 GPU profiles (gaming, AI, K8s, builds, mining, idle)
- Automatic profile switching based on workload
- Original power limit storage/restoration
- Zero service control (only nvidia-smi)

### mining-coordinator.nix
**Purpose:** Detect build workloads and coordinate with K8s

**Inputs:**
- PSI metrics (CPU, memory, I/O pressure)
- Gaming state (from `gaming-detection.nix`)
- nix-daemon activity

**Outputs:**
- Profile requests (for `gpu-profile-manager.nix`)
- Volcano placeholder scaling (ONLY K8s interaction)

**Key Features:**
- PSI-based build detection (kernel-level)
- K8s GPU workload detection (excludes mining namespace)
- Profile request system (writes to file)
- Volcano gaming placeholder scaling
- NO systemctl calls
- NO kubectl scale for mining deployments

## File Structure

```
/etc/nixos/modules/system/
├── compute-workload-monitor.nix (1665 lines) - LEGACY (to be removed)
├── gaming-detection.nix (380 lines) - NEW
├── gpu-profile-manager.nix (600 lines) - NEW
└── mining-coordinator.nix (450 lines) - NEW
```

## Integration Points

### State Files (Inter-Module Communication)
```
/run/gaming-detection/
├── gaming_state          # Gaming state (0/1, method, hysteresis)
└── gpu-util-history      # GPU utilization for pattern detection

/run/mining-coordinator/
└── requested-profile      # Profile request for gpu-profile-manager

/run/gpu-profile-manager/
├── gpu0_original_power   # Stored power limits
├── gpu1_original_power   # (for restoration)
└── ...
```

### Prometheus Metrics
```
/var/lib/node_exporter/textfile_collector/
└── gaming.prom            # Gaming state for Grafana dashboards
```

### K8s Integration
```
kubectl scale deployment gaming-placeholder-volcano -n mining --replicas=1
```
**NOTE:** This is the ONLY K8s interaction in the new modules.

## Testing Checklist (Phase 2)

### On Zephyr (Test Host)
- [ ] All 3 services start successfully
  ```bash
  systemctl status gaming-detection
  systemctl status gpu-profile-manager
  systemctl status mining-coordinator
  ```
- [ ] Gaming detection works
  - Start a game → Check state file → Check Prometheus metrics
- [ ] GPU profiles apply correctly
  - Request gaming profile → Verify nvidia-smi power limits
- [ ] Volcano preemption works
  - Gaming detected → Placeholder scales → Mining pods preempted
- [ ] Build detection works
  - Run `nixos-rebuild test` → Check profile request file
- [ ] No systemctl calls in new service logs
  ```bash
  journalctl -u gaming-detection | grep systemctl
  journalctl -u gpu-profile-manager | grep systemctl
  journalctl -u mining-coordinator | grep systemctl
  ```
  **Expected:** No matches (new modules don't use systemctl)

## Next Steps (Phase 2-3)

### Phase 2: Integration Testing (Day 2-3)
1. Enable on Zephyr with old module running
2. Validate all functionality
3. Compare metrics with old module
4. Fix any issues discovered

### Phase 3: Gradual Cutover (Day 4-5)
1. **Zephyr & Nexus** (gaming nodes)
   - Disable compute-workload-monitor
   - Enable all 3 new modules
2. **Forge** (mining node)
   - Disable compute-workload-monitor
   - Enable gpu-profile-manager only
3. **Sentry** (monitoring)
   - Disable compute-workload-monitor
   - Enable gaming-detection only

### Phase 4: Cleanup (Day 6)
1. Remove legacy module from all hosts
2. Delete `modules/system/compute-workload-monitor.nix`
3. Remove from `modules/default.nix`
4. Final validation

## Success Metrics

- **Code Quality:** 1665 lines → 1430 lines (14% reduction), 3 focused modules
- **Operational:** Zero downtime, all functionality preserved
- **K8s-Native:** Volcano handles all preemption, no manual kubectl
- **Maintainability:** Single responsibility per module, clear dependencies

## Rollback Plan

If critical issue detected, revert to old module:
```nix
# In hosts/*/configuration.nix
services.compute-workload-monitor.enable = true;
services.gaming-detection.enable = false;
services.mining-coordinator.enable = false;
services.gpu-profile-manager.enable = false;
```

## Files Modified

**Created:**
- `/etc/nixos/modules/system/gaming-detection.nix`
- `/etc/nixos/modules/system/gpu-profile-manager.nix`
- `/etc/nixos/modules/system/mining-coordinator.nix`

**Modified:**
- `/etc/nixos/modules/default.nix` (added new module imports)

**To Be Deleted (Phase 4):**
- `/etc/nixos/modules/system/compute-workload-monitor.nix`

## Validation

✅ **Syntax:** `nix flake check` passed
✅ **Git:** New modules tracked in git
✅ **Structure:** All 3 modules follow NixOS conventions
✅ **Dependencies:** No circular dependencies between modules

---

**Status:** Phase 1 Complete ✅
**Next:** Enable on Zephyr for integration testing (Phase 2)
**Date:** 2026-03-21
