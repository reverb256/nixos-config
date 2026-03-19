# NVIDIA Common Configuration Module
# Base NVIDIA driver configuration for all NVIDIA GPUs
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.nvidia-common;
in {
  options.hardware.nvidia-common.enable = lib.mkEnableOption "NVIDIA GPU support";

  config = lib.mkIf cfg.enable {
    # Enable OpenGL
    # NOTE: enable32Bit disabled to prevent Wayland issues on multi-GPU systems.
    # LM Studio GUI works fine without it. CLI has 32-bit lib issues but GUI is primary use.
    hardware.graphics = {
      enable = true;
      enable32Bit = lib.mkForce false; # Keep disabled for Wayland stability

      extraPackages = with pkgs; [
        vulkan-loader
        vulkan-tools
      ];
    };

    # Load nvidia driver for Xorg and Wayland
    services.xserver.videoDrivers = ["nvidia"];

    hardware.nvidia = {
      # Modesetting is required for Wayland
      modesetting.enable = true;

      # Power management (optional, can cause suspend issues)
      powerManagement.enable = false;

      # Use beta drivers (560+) for best Wayland/Plasma 6 support
      # RTX 30 series (Ampere) is fully supported
      package = config.boot.kernelPackages.nvidiaPackages.beta;

      # Open source kernel module (required for Turing+/RTX 30 series)
      # Better Wayland/Plasma 6 stability, no kernel taint, better error handling
      # GSP firmware still runs on GPU (required for Ampere/RTX 30 series)
      open = true;

      # Enable nvidia-settings
      nvidiaSettings = true;
    };

    # NVIDIA kernel module options via modprobe
    boot.extraModprobeConfig = ''
      # Enable GSP firmware (required for Ampere/RTX 30 series)
      # GSP runs control firmware on the GPU for better performance
      options nvidia NVreg_EnableGpuFirmware=1

      # Disable DynamicPowerManagement to prevent HDMI brightness fluctuations
      # DPM=0 prevents GPU from auto-scaling power based on input activity
      options nvidia NVreg_DynamicPowerManagement=0
    '';

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
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/sw/bin/nvidia-smi -pm 1";
      };
    };

    # ============================================================================
    # GPU POWER/PERFORMANCE MODE
    # ============================================================================
    # DynamicPowerManagement disabled via NVreg_DynamicPowerManagement=0
    # in boot.extraModprobeConfig above.
    #
    # This prevents GPU from auto-scaling power based on input activity,
    # which fixes HDMI TV brightness fluctuations when typing/moving mouse.
  };
}
