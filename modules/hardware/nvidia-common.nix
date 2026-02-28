# NVIDIA GPU Configuration Module
# Common settings for NVIDIA hosts - enables the wayland module
{config, ...}: {
  hardware.nvidia = {
    # Use stable driver (580+ series)
    # Previous beta 590.48 was used to work around "Flip event timeout" bug in 570.x
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # Use open source kernel modules (required for driver 560+)
    # Recommended for Turing or later GPUs (RTX series, GTX 16xx)
    open = true;

    # Enable the comprehensive wayland module
    wayland = {
      enable = true;
      openModules = true; # Required for driver 560+
      sddmWayland = true;
      # DISABLED - powerManagement causes freezes with multi-GPU + Wayland
      # powerManagement = true;
    };
  };

  services.xserver.videoDrivers = ["nvidia"];
}
