# NVIDIA GPU Configuration Module
# Common settings for NVIDIA hosts (zephyr, nexus, forge)
# Provides sensible defaults that can be overridden per-host
{config, ...}: {
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    open = false;
  };

  services.xserver.videoDrivers = ["nvidia"];

  # Minimal kernel params - only enable modesetting
  boot.kernelParams = [
    "nvidia_drm.modeset=1"
  ];
}
