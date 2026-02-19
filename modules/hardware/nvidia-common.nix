# NVIDIA GPU Configuration Module
# Common settings for NVIDIA hosts (zephyr, nexus, forge)
# Provides sensible defaults that can be overridden per-host
{config, ...}: {
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    wayland = {
      enable = true;
      openModules = true;
      sddmWayland = true;
    };
    powerManagement = {
      enable = true;
      finegrained = false;
    };
  };

  services.xserver.videoDrivers = ["nvidia"];

  # Common kernel params for NVIDIA Wayland support
  # These can be extended per-host with additional params
  boot.kernelParams = [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "nvidia.NVreg_EnableResizableBar=1" # Enable Resizable BAR for better performance
    "nvidia.NVreg_EnableGpuFirmware=1" # Enable GPU firmware loading
  ];
}
