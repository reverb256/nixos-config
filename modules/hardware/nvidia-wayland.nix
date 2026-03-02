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
  environment.sessionVariables = {
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    __GL_THREADED_OPTIMIZATIONS = "1";
  };
}
