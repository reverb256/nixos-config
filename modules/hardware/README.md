# Hardware Modules

Centralized GPU, monitoring, RGB, and cooling hardware modules. These are
**host-dependent** — each host imports only the modules it needs.

## Module Inventory

| Module | Purpose | Used By |
|--------|---------|---------|
| `gpu-compute.nix` | Universal CUDA/ROCm/Vulkan compute support | All GPU hosts |
| `nvidia-common.nix` | Base NVIDIA driver, OpenGL, nvidia-settings | Zephyr, Nexus, Forge |
| `nvidia-wayland.nix` | NVIDIA + Wayland + Plasma 6 optimizations | Zephyr, Nexus, Forge |
| `amdgpu-wayland.nix` | AMD GPU + Wayland + Plasma 6 optimizations | Forge, Sentry |
| `monitoring.nix` | lm-sensors, fan control, sensor detection | All hosts |
| `rgb-control.nix` | OpenRGB, OpenRAZER, Wraith Prism, temp-reactive RGB | Zephyr, Nexus, Forge, Sentry |
| `corsair.nix` | Corsair AIO cooler (liquidctl), RGB, fan controllers | Zephyr |

## GPU Profile System

GPU support is split into layers:

1. **GPU Compute** (`gpu-compute.nix`) — Installs CUDA/ROCm/Vulkan packages
   for compute workloads (AI inference, mining). Enable per backend:
   ```nix
   hardware.gpu-compute = {
     enable = true;
     cuda.enable = true;   # NVIDIA GPUs
     rocm.enable = true;   # AMD GPUs (pre-RDNA3 needs ROC_ENABLE_PRE_VEGA=1)
     vulkan.enable = true; # Universal fallback
   };
   ```

2. **GPU Display** — Separate driver modules for Wayland compositor support:
   - `nvidia-common.nix` + `nvidia-wayland.nix` for NVIDIA hosts
   - `amdgpu-wayland.nix` for AMD hosts
   - Forge uses BOTH (hybrid AMD + NVIDIA setup)

3. **Node Profiles** — Auto-enable base GPU profiles via
   `profiles.node.<hostname>` (see `modules/profiles/node-profiles.nix`).

### Host GPU Assignments

| Host | GPUs | Compute Module | Display Module |
|------|------|----------------|----------------|
| Zephyr | RTX 3090 + 3060 Ti | CUDA + Vulkan | nvidia-wayland |
| Nexus | RTX 3060 Ti | CUDA + Vulkan | nvidia-wayland |
| Forge | 2× RTX 4060 + 2× RX 5700 XT | CUDA + ROCm + Vulkan | nvidia-wayland + amdgpu-wayland |
| Sentry | RX 5600 XT | ROCm + Vulkan | amdgpu-wayland |

## Hardware Monitoring

The `monitoring.nix` module provides:
- **lm-sensors**: CPU, motherboard, and NVMe temperature readings
- **Fan control**: Optional PWM-based fan curves (disables BIOS fan control)
- **Auto-detection**: `sensors-detect` at boot (disabled on most hosts due to bugs)

Most hosts use `autoDetect = false` and `fanControl = false` (BIOS-managed).
Zephyr is the exception with custom fan curves for the Corsair H115i AIO.

## RGB Control

The `rgb-control.nix` module supports temperature-reactive RGB lighting:
- **OpenRGB**: Motherboard, GPU, and Corsair device control
- **OpenRAZER**: Razer peripherals (Naga Pro mouse on Zephyr/Nexus)
- **Wraith Prism**: AMD stock cooler RGB (Sentry)
- **Temperature Reactive**: Automatically adjusts colors based on CPU/GPU temps

Each host configures different thresholds and sensors based on its cooling
situation (mining rigs run hotter than workstations).

## Adding a New Hardware Module

1. Create `modules/hardware/<name>.nix` with standard NixOS module pattern
2. Import it from the host's `configuration.nix` (NOT `modules/default.nix`)
3. Use `lib.mkOptionDefault` for all list options
4. Document host applicability in this README
