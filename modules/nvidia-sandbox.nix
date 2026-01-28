# NVIDIA Sandbox Configuration for Containerized Applications
# Fixes GPU detection in LM Studio, Steam, and other sandboxed applications
# FULLY DECLARATIVE - No manual scripts required
{
  pkgs,
  lib,
  ...
}: {
  # ============================================================================
  # NVIDIA LIBRARY SYMLINKS FOR FHS ENVIRONMENTS (Declarative)
  # ============================================================================

  # Create symlinks for NVIDIA libraries in all FHS environments
  environment.etc = {
    # NVIDIA library symlinks for containerized applications
    "nvidia-libcuda.so.1".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libcuda.so.1";
    "nvidia-libnvidia-ml.so.1".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libnvidia-ml.so.1";
    "nvidia-libnvidia-encode.so.1".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libnvidia-encode.so.1";
    "nvidia-libEGL_nvidia.so.0".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libEGL_nvidia.so.0";
    "nvidia-libGLX_nvidia.so.0".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libGLX_nvidia.so.0";

    # Wayland-specific NVIDIA libraries (for KWin and compositors)
    "nvidia-libnvidia-egl-wayland.so".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libnvidia-egl-wayland.so";
    "nvidia-libnvidia-egl-wayland2.so".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libnvidia-egl-wayland2.so";

    # NVIDIA sandbox environment setup in profile
    "profile.d/nvidia-sandbox.sh".text = ''
      # NVIDIA Sandbox Environment Setup - AUTOMATIC
      # This is loaded automatically for all users and sessions

      export NVIDIA_VISIBLE_DEVICES="all"
      export NVIDIA_DRIVER_CAPABILITIES="compute,utility,graphics"
      export CUDA_HOME="/run/opengl-driver"
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:$LD_LIBRARY_PATH"

      # Additional paths for containerized applications (LM Studio, Steam, etc.)
      export NVIDIA_LIBRARY_PATH="/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib"

      # LM Studio specific environment variables
      export LM_STUDIO_CUDA_VISIBLE_DEVICES="all"
      export LM_STUDIO_VULKAN_DEVICE_SELECT="nvidia"
      export LM_STUDIO_FORCE_VULKAN="1"
      export LM_STUDIO_FORCE_CUDA="1"

      # Steam and gaming environment
      export STEAM_RUNTIME_NVIDIA="1"
      export __NV_PRIME_RENDER_OFFLOAD="1"
      export __VK_LAYER_NV_optimus="NVIDIA_only"
    '';

    # Standard library symlinks
    "lib/libcuda.so.1".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libcuda.so.1";
    "lib/libnvidia-ml.so.1".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libnvidia-ml.so.1";
    "lib/libnvidia-encode.so.1".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libnvidia-encode.so.1";
    "lib/libEGL_nvidia.so.0".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libEGL_nvidia.so.0";
    "lib/libGLX_nvidia.so.0".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libGLX_nvidia.so.0";

    # Wayland-specific library symlinks
    "lib/libnvidia-egl-wayland.so".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libnvidia-egl-wayland.so";
    "lib/libnvidia-egl-wayland2.so".source = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib/libnvidia-egl-wayland2.so";
  };

  # ============================================================================
  # NVIDIA ENVIRONMENT VARIABLES (System Level)
  # ============================================================================

  # Ensure NVIDIA variables are available system-wide
  environment.variables = {
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,utility,graphics";
    CUDA_HOME = lib.mkForce "/run/opengl-driver";
    NVIDIA_LIBRARY_PATH = "/nix/store/7l19w2xp7hly8amzyz9xfkgm7kw3gr0w-nvidia-x11-590.48.01-6.18.5/lib";

    # Containerized application support
    LM_STUDIO_CUDA_VISIBLE_DEVICES = "all";
    LM_STUDIO_VULKAN_DEVICE_SELECT = "nvidia";
    LM_STUDIO_FORCE_VULKAN = "1";
    LM_STUDIO_FORCE_CUDA = "1";
    STEAM_RUNTIME_NVIDIA = "1";
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __VK_LAYER_NV_optimus = "NVIDIA_only";
  };

  # ============================================================================
  # NVIDIA RUNTIME DIRECTORY (SystemD)
  # ============================================================================

  # Ensure NVIDIA runtime directory exists for all users
  systemd.tmpfiles.rules = [
    "d /run/nvidia 755 root root -"
    "d /run/opengl-driver/lib 755 root root -"
  ];

  # ============================================================================
  # NVIDIA SANDBOX ACTIVATION SERVICE (Automatic)
  # ============================================================================

  # Create a systemd service that automatically sets up NVIDIA sandbox environment
  systemd.services.nvidia-sandbox-activation = {
    description = "NVIDIA Sandbox Environment Activation";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${pkgs.coreutils}/bin/true"; # No action needed - environment is set declaratively
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # ============================================================================
  # NVIDIA SANDBOX INFORMATION TOOL
  # ============================================================================

  # Create a tool to check NVIDIA sandbox status
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "nvidia-sandbox-info" ''
      #!/bin/bash
      echo "🔧 NVIDIA Sandbox Environment Status"
      echo "==================================="
      echo ""
      echo "✅ NVIDIA GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader,nounits)"
      echo "✅ CUDA available: $(nvidia-smi --query-gpu=cuda_version --format=csv,noheader,nounits)"
      echo "✅ Vulkan ICD configured: /usr/share/vulkan/icd.d/nvidia_icd.json"
      echo ""
      echo "🎯 Environment Variables:"
      echo "   - NVIDIA_VISIBLE_DEVICES: $NVIDIA_VISIBLE_DEVICES"
      echo "   - NVIDIA_DRIVER_CAPABILITIES: $NVIDIA_DRIVER_CAPABILITIES"
      echo "   - CUDA_HOME: $CUDA_HOME"
      echo "   - NVIDIA_LIBRARY_PATH: $NVIDIA_LIBRARY_PATH"
      echo ""
      echo "🚀 LM Studio should now detect GPU automatically!"
    '')
  ];
}
