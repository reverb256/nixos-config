# Steam + Wayland + NVIDIA Configuration Module
# Robust configuration for Steam gaming on Wayland with NVIDIA
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options = {
    services.steamWayland.enable = mkEnableOption "Enable Steam with Wayland support";
    services.steamWayland.protonVersion = mkOption {
      type = types.str;
      description = "Proton version to use for Steam";
    };
    services.steamWayland.extraCompatPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional Steam compatibility packages";
    };
  };

  config = mkIf config.services.steamWayland.enable {
    # ============================================================================
    # STEAM CONFIGURATION - Wayland Optimized
    # ============================================================================

    programs.steam = {
      enable = true;

      # Use GE-Proton via extraCompatPackages instead of manual paths
      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];

      # Enable Gamescope session for better game compatibility
      # This allows running games in an optimized micro-compositor
      gamescopeSession.enable = true;
    };

    # ============================================================================
    # SYSTEMD SERVICES - Gaming Optimization
    # ============================================================================

    # Steam runtime service
    systemd.services.steam-runtime = {
      description = "Steam Runtime Service";
      wantedBy = ["graphical-session.target"];
      after = ["graphical-session.target"];
      script = ''
        # Wait for Steam to be ready
        sleep 5

        # Start Steam services
        /run/current-system/sw/bin/steam -silent &
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # ============================================================================
    # PACKAGES - Steam + Gaming Ecosystem
    # ============================================================================

    environment.systemPackages = with pkgs; [
      # Core Steam packages
      steam
      steam-run

      # Gaming utilities
      gamescope
      mangohud
      goverlay
      protonup-ng # Easy Proton-GE management (renamed from protonup)

      # NVIDIA VA-API driver for hardware video acceleration
      nvidia-vaapi-driver

      # Wayland gaming support
      wlroots

      # Debugging tools
      vulkan-tools
    ];

    # ============================================================================
    # UDEV RULES - Steam Controller and VR Support
    # ============================================================================

    services.udev.extraRules = ''
      # uinput device for gamepad and controller support
      KERNEL=="uinput", MODE="0660", GROUP="plugdev", TAG+="uaccess"

      # Steam Controller
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", MODE="0666", GROUP="plugdev"

      # HTC Vive
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2000", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2101", MODE="0666", GROUP="plugdev"

      # Valve Index
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2000", MODE="0666", GROUP="plugdev"

      # Quest/Quest Pro (when connected via USB)
      SUBSYSTEM=="usb", ATTRS{idVendor}=="2833", MODE="0666", GROUP="plugdev"
    '';

    # ============================================================================
    # ASSERTIONS - Configuration Validation
    # ============================================================================

    # Assertion removed - NVIDIA is not strictly required for this module
    # The module works with any GPU that supports Steam
  };
}
