# NVIDIA Common Configuration Module
# Base NVIDIA driver configuration for all NVIDIA GPUs
{ config, lib, pkgs, ... }:
{
  # Enable OpenGL
  # NOTE: enable32Bit must be explicitly disabled because the gaming module
  # sets extraPackages32 which auto-enables enable32Bit. This breaks Wayland
  # on multi-GPU NVIDIA systems (KWin cannot open /dev/dri/card1).
  hardware.graphics = {
    enable = true;
    enable32Bit = lib.mkForce false;  # Force override steam module
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
