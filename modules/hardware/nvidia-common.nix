# NVIDIA Common Configuration Module
# Base NVIDIA driver configuration for all NVIDIA GPUs
{ config, lib, pkgs, ... }:
{
  # Enable OpenGL
  # NOTE: enable32Bit is disabled because it breaks Wayland on multi-GPU NVIDIA systems
  # KWin cannot open DRM devices when 32-bit OpenGL is enabled with multiple GPUs
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Modesetting is required for Wayland
    modesetting.enable = true;

    # Power management (optional, can cause suspend issues)
    powerManagement.enable = false;

    # Use beta drivers (560+) for best Wayland/Plasma 6 support
    # RTX 30 series (Ampere) is fully supported
    package = config.boot.kernelPackages.nvidiaPackages.beta;

    # Open source kernel module (optional for Turing+)
    # Set to false for proprietary (recommended for gaming/CUDA)
    open = false;

    # Enable nvidia-settings
    nvidiaSettings = true;
  };
}
