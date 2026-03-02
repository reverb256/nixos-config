# NVIDIA GPU Configuration Module
# Common settings for NVIDIA hosts - enables the wayland module
{config, ...}: {
  hardware.nvidia = {
    # Use beta driver (rolling release, latest features)
    # Previous stable 580.x series had some issues with newer models
    package = config.boot.kernelPackages.nvidiaPackages.beta;

    # Use PROPRIETARY kernel modules (fixes Plasma 6 Wayland crash loop)
    # Open modules have known bugs with Qt6 notification system causing cascading crashes
    # Reference: https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1008
    open = false;  # ← CRITICAL FIX: Switch to proprietary driver

    # CRITICAL: Proprietary driver also needs firmware!
    # The GSP firmware is included in the driver package and loaded automatically
    # No explicit firmware configuration needed for proprietary driver (unlike open modules)

    # Enable comprehensive wayland module
    wayland = {
      enable = true;
      openModules = false;  # ← CHANGED: Disable for proprietary driver
      sddmWayland = false;  # Disabled - using plasma-login-manager (Plasma 6.6)
      # DISABLED - powerManagement causes freezes with multi-GPU + Wayland
      powerManagement = false;  # ← FIXED: Keep disabled for multi-GPU stability
    };
  };

  services.xserver.videoDrivers = ["nvidia"];

  # Note: nvidia_drm.modeset=1 is set in nvidia-wayland.nix to avoid duplicates
  # The open-source modules require this param with underscore format
}
