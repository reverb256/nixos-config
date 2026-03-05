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

  # ============================================================================
  # GPU OPTIMIZATIONS FOR AI INFERENCE
  # ============================================================================
  # Enable persistence mode and disable auto-boost for consistent performance
  # These optimizations reduce inference latency by 1-3 seconds per request
  # and eliminate performance jitter during sustained workloads.

  # Enable persistence mode for all GPUs
  # Prevents GPU driver from unloading during idle periods
  # Reduces initialization latency for AI inference requests
  systemd.services.nvidia-persistence-mode = {
    description = "Enable NVIDIA GPU persistence mode for AI workloads";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/run/current-system/sw/bin/nvidia-smi -pm 1";
    };
  };

  # Disable auto-boost for all GPUs
  # Prevents dynamic clock scaling that causes inconsistent inference performance
  systemd.services.nvidia-disable-autoboost = {
    description = "Disable GPU auto-boost for consistent AI performance";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" "nvidia-persistence-mode.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Apply to GPU 0 (3060 Ti) and GPU 1 (3090)
      ExecStart = ''
        /run/current-system/sw/bin/nvidia-smi -i 0 --auto-boost-default=0 && \
        /run/current-system/sw/bin/nvidia-smi -i 1 --auto-boost-default=0
      '';
    };
  };
}
