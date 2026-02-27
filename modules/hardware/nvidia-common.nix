# NVIDIA GPU Configuration Module
# MINIMAL working configuration for Plasma Wayland
{config, ...}: {
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    modesetting.enable = true;
    # powerManagement.enable = true;  # DISABLED - causes freezes
    # powerManagement.finegrained = false;
    open = false;
  };

  services.xserver.videoDrivers = ["nvidia"];

  # Kernel params for Wayland
  boot.kernelParams = [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
  ];
}
