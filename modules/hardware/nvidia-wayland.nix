# NVIDIA Wayland-Specific Configuration
{ config, lib, pkgs, ... }:
{
  # Wayland-specific kernel parameters for NVIDIA
  boot.kernelParams = [
    "nvidia_drm.fbdev=1"
    "nvidia_drm.modeset=1"
  ];

  # Enable DRM kernel mode setting
  boot.kernelModules = [ "nvidia_drm" ];

  # NVIDIA environment variables for Wayland
  # NOTE: __NV_PRIME_RENDER_OFFLOAD is NOT set because:
  # - This system has multiple discrete NVIDIA GPUs (not hybrid graphics)
  # - PRIME offload is for iGPU + dGPU setups (Intel + NVIDIA)
  # - Setting this breaks EGL initialization on multi-NVIDIA systems
  environment.sessionVariables = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    __GL_THREADED_OPTIMIZATIONS = "1";
  };
}
