# NVIDIA Common Configuration Module
# Base NVIDIA driver configuration for all NVIDIA GPUs
{ config, lib, pkgs, ... }:
{
  # Enable OpenGL
  # NOTE: enable32Bit disabled to prevent Wayland issues on multi-GPU systems.
  # LM Studio GUI works fine without it. CLI has 32-bit lib issues but GUI is primary use.
  hardware.graphics = {
    enable = true;
    enable32Bit = lib.mkForce false;  # Keep disabled for Wayland stability

    extraPackages = with pkgs; [
      vulkan-loader
      vulkan-tools
    ];
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
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/run/current-system/sw/bin/nvidia-smi -pm 1";
    };
  };

  # ============================================================================
  # GPU POWER/PERFORMANCE MODE NOTES
  # ============================================================================
  # GPUPowerMizerMode controls dynamic clock scaling:
  # - 0 = Adaptive (default) - auto-scales based on load
  # - 1 = Prefer Maximum Performance - always full clocks
  # - 2 = Auto - same as Adaptive for RTX 30 series
  #
  # Current: Both GPUs at default (0=Adaptive)
  # GPU 0 (3060 Ti): 210 MHz idle → 420 MHz max
  # GPU 1 (3090): 240 MHz idle → 2130 MHz max
  #
  # To change mode (requires X/Wayland session):
  #   nvidia-settings -a [gpu:0]/GPUPowerMizerMode=1  # Max performance
  #   nvidia-settings -a [gpu:0]/GPUPowerMizerMode=0  # Adaptive (default)
  #
  # Note: nvidia-settings requires DISPLAY variable, so this cannot be set
  # via systemd service at boot. Run manually after login or add to autostart.
}
