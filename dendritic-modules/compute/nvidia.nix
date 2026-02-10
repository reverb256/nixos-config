# NVIDIA GPU Module
# NVIDIA Wayland driver configuration with best practices
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; {
  # ============================================================================
  # NVIDIA WAYLAND CONFIGURATION
  # ============================================================================

  # Enable NVIDIA video driver
  services.xserver.videoDrivers = ["nvidia"];

  # NVIDIA driver package selection (default: stable)
  # Can be overridden per-host for beta or production branches
  hardware.nvidia.package = mkDefault config.boot.kernelPackages.nvidiaPackages.stable;

  # NVIDIA Wayland optimizations
  hardware.nvidia.wayland = {
    enable = true;
    enable32Bit = mkDefault true;
    openModules = mkDefault true; # Use open-source kernel modules with proprietary userspace
    powerManagement = mkDefault true;
    sddmWayland = mkDefault true;
  };

  # NVIDIA power management
  hardware.nvidia.powerManagement = {
    enable = mkDefault true;
    finegrained = mkDefault false;
  };

  # NVIDIA kernel parameters for optimal performance
  # Can be extended per-host with specific tuning
  boot.kernelParams = mkOptionDefault [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
  ];

  # NVIDIA environment variables for CUDA/Vulkan access
  # Set in host config for package availability
  environment.variables = {
    NVIDIA_DRIVER_PATH = mkDefault "/run/opengl-driver";
    NVIDIA_LIB_PATH = mkDefault "/run/opengl-driver/lib";
    NVIDIA_ICD_PATH = mkDefault "/run/opengl-driver/share/vulkan/icd.d";
    CUDA_PATH = mkDefault "/run/opengl-driver";
    CUDA_HOME = mkDefault "/run/opengl-driver";
    VK_ICD_FILENAMES = mkDefault "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json";
  };
}
