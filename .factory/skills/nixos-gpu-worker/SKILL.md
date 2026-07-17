---
name: nixos-gpu-worker
description: Fixes GPU profile scripts, deduplicates NixOS GPU modules, adds file locking for GPU state management, and ensures RTX 4060 support.
---

# NixOS GPU Infrastructure Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features involving GPU profile scripts, GPU NixOS module changes, device node permissions, or any changes to `modules/system/gpu-profile-manager.nix`, `modules/system/compute-workload-monitor.nix`, or `scripts/gpu-profiles/`.

## Required Skills

None. All work is file editing and shell commands.

## Context

This NixOS cluster has 7 GPUs across 4 hosts. Two NixOS modules (`compute-workload-monitor.nix` at 1716 lines and `gpu-profile-manager.nix` at 569 lines) contain nearly identical GPU profile functions that are fighting for control. GPU profile scripts (`ai-inference.sh`, `mining.sh`) source a `_gpu-common.sh` file that doesn't exist. Only RTX 3060/3090 GPUs have profiles — Forge's RTX 4060 GPUs (Ada architecture) fall through to generic defaults.

**Critical safety rules:**
- Use `lib.mkOptionDefault` for ALL list/attr options in shared modules
- NEVER use `nixos-rebuild switch` or deploy during mission — validate via `nix flake check` only
- NEVER edit `hardware-configuration.nix` or `flake.lock`

## Work Procedure

### Step 1: Read and understand all files before editing

Read these files completely before making any changes:
- `/etc/nixos/scripts/gpu-profiles/ai-inference.sh`
- `/etc/nixos/scripts/gpu-profiles/mining.sh`
- `/etc/nixos/modules/system/gpu-profile-manager.nix`
- `/etc/nixos/modules/system/compute-workload-monitor.nix`
- `/etc/nixos/modules/hardware/nvidia-wayland.nix`

Map out: which functions are duplicated, what each script expects from `_gpu-common.sh`, what GPU models need profiles.

### Step 2: Create `_gpu-common.sh`

Create `/etc/nixos/scripts/gpu-profiles/_gpu-common.sh` with the shared functions that both `ai-inference.sh` and `mining.sh` need:
- `get_gpu_list()` — enumerate NVIDIA GPUs
- `get_gpu_count()` — count GPUs
- `get_gpu_name(id)` — get GPU model name
- `set_power_limit(id, watts)` — set power limit via nvidia-smi
- `set_clock_offset(id, type, offset)` — set clock offset via nvidia-smi (NOT nvidia-settings)
- `nvidia_safe(id)` — safe GPU reset function
- `store_original_power_limits()` — save current power limits
- `restore_original_power_limits()` — restore saved limits

All functions MUST use `nvidia-smi` instead of `nvidia-settings` for headless compatibility.

### Step 3: Update GPU profile scripts

Update `ai-inference.sh` and `mining.sh` to:
- Source `_gpu-common.sh` (already have the source line)
- Remove any duplicated functions now in `_gpu-common.sh`
- Add `*"4060"*)` case with Ada-appropriate power/clock values
- Replace any `nvidia-settings` calls with `nvidia-smi` equivalents
- Ensure the scripts are self-contained (no external dependencies beyond _gpu-common.sh)

### Step 4: Deduplicate GPU NixOS modules

Decide the ownership model:
- **Recommended:** `gpu-profile-manager.nix` owns GPU power/clock profiles. `compute-workload-monitor.nix` owns workload detection and delegates to gpu-profile-manager for actual profile application.
- Remove duplicated profile functions from one module.
- Add `flock`-based locking to all GPU state file writes in both modules.

### Step 5: Fix nvidia-wayland.nix issues

- Change `DXVK_HUD = "1"` to `DXVK_HUD = "0"` (or remove)
- Change `mknod -m 666` to `mknod -m 660` for NVIDIA device nodes
- Add appropriate group ownership (e.g., `chown root:render`)

### Step 6: Validate

Run in order:
1. `cd /etc/nixos && nix flake check` — must pass
2. `deadnix modules/system/compute-workload-monitor.nix modules/system/gpu-profile-manager.nix modules/hardware/nvidia-wayland.nix` — must have zero findings
3. `statix check modules/system/compute-workload-monitor.nix modules/system/gpu-profile-manager.nix modules/hardware/nvidia-wayland.nix` — must have zero findings
4. Verify `_gpu-common.sh` is syntactically valid: `bash -n scripts/gpu-profiles/_gpu-common.sh`

## Example Handoff

```json
{
  "salientSummary": "Created _gpu-common.sh shared library with 8 GPU helper functions. Deduplicated GPU profiles by making gpu-profile-manager.nix the single profile owner (removed ~400 lines of duplication from compute-workload-monitor.nix). Added RTX 4060 support to all profiles. Added flock-based locking to GPU state writes. Fixed DXVK_HUD and mknod permissions in nvidia-wayland.nix.",
  "whatWasImplemented": "Shared GPU library, profile deduplication, RTX 4060 support, flock locking, nvidia-wayland fixes",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      { "command": "cd /etc/nixos && nix flake check", "exitCode": 0, "observation": "All 4 host configs build successfully" },
      { "command": "deadnix modules/system/compute-workload-monitor.nix modules/system/gpu-profile-manager.nix modules/hardware/nvidia-wayland.nix", "exitCode": 0, "observation": "Zero findings" },
      { "command": "statix check modules/system/compute-workload-monitor.nix modules/system/gpu-profile-manager.nix modules/hardware/nvidia-wayland.nix", "exitCode": 0, "observation": "Zero findings" },
      { "command": "bash -n scripts/gpu-profiles/_gpu-common.sh", "exitCode": 0, "observation": "Syntax valid" }
    ],
    "interactiveChecks": []
  },
  "tests": { "added": [] },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- `nix flake check` fails and the error is not in files you modified (pre-existing issue)
- Ambiguity about which module should own GPU profiles
- Changes needed outside the scope of this feature (e.g., new NixOS options needed from other modules)
