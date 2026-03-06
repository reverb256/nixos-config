# AMD GPU Wayland Module - Best Practices for AMD + Wayland + Plasma 6
# Based on NixOS community best practices
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.amdgpu.wayland;
in {
  options.hardware.amdgpu.wayland = {
    enable = lib.mkEnableOption "AMD GPU Wayland optimizations for Plasma 6";

    enable32Bit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable 32-bit graphics support for Steam and games";
    };

    opencl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable OpenCL support via ROCm";
    };

    sddmWayland = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SDDM Wayland support";
    };
  };

  config = lib.mkIf cfg.enable {
    # ============================================================================
    # AMD GPU CONFIGURATION
    # ============================================================================
    hardware.amdgpu = {
      # Enable OpenCL if requested
      opencl.enable = cfg.opencl;

      # Load AMD GPU driver
      initrd.enable = true;
    };

    # ============================================================================
    # GRAPHICS CONFIGURATION
    # ============================================================================
    hardware.graphics = {
      enable = true;
      inherit (cfg) enable32Bit;

      extraPackages = with pkgs; [
        # Mesa drivers (default, usually sufficient)
        mesa
      ];

      extraPackages32 = lib.optionals cfg.enable32Bit (with pkgs.pkgsi686Linux; [
        mesa
      ]);
    };

    # ============================================================================
    # DISPLAY MANAGER (SDDM with Wayland)
    # ============================================================================
    services.displayManager.sddm.wayland.enable = cfg.sddmWayland;

    # ============================================================================
    # ENVIRONMENT VARIABLES (AMD + Wayland)
    # ============================================================================
    environment.sessionVariables = {
      # Force Wayland backend for Qt applications (Plasma 6)
      QT_QPA_PLATFORM = "wayland";

      # Enable Wayland for Ozone-based applications (Chrome, Electron, etc.)
      NIXOS_OZONE_WL = "1";

      # Enable Wayland for Firefox
      MOZ_ENABLE_WAYLAND = "1";

      # AMD-specific: Enable ROCm if using OpenCL
      ROC_ENABLE_PRE_VEGA = lib.mkIf cfg.opencl "1";
    };

    # ============================================================================
    # ADDITIONAL WAYLAND PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [
      # Wayland utilities
      wayland-utils

      # Display management
      kanshi

      # GPU monitoring (supports AMD)
      nvtopPackages.full
    ];
  };
}
