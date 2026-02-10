# AMD GPU Module
# AMD GPU driver configuration with Wayland and OpenCL support
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; {
  # ============================================================================
  # AMD GPU DRIVER CONFIGURATION
  # ============================================================================

  # Enable AMD video driver
  services.xserver.videoDrivers = ["amdgpu"];

  # AMD GPU configuration
  hardware.amdgpu = {
    wayland = {
      enable = mkDefault true;
      enable32Bit = mkDefault true;
      opencl = mkDefault false; # Can be enabled per-host for GPU mining
      sddmWayland = mkDefault true;
    };

    # OpenCL support (for mining and compute)
    opencl = mkDefault false;
  };

  # Ensure AMDGPU kernel modules are loaded
  boot.kernelModules = mkDefault [
    "amdgpu"
  ];

  # Add AMDGPU to initrd modules for early loading
  boot.initrd.kernelModules = mkDefault [
    "amdgpu"
  ];

  # AMD environment variables for ROCm/OpenCL access
  environment.variables = {
    ROC_ENABLE_PRE_VEGA = mkDefault "1";
    OCL_ICD_VENDORS = mkDefault "/etc/OpenCL/vendors";
  };
}
