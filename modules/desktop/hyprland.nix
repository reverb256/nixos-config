# Hyprland Module
# Wayland compositor with full ecosystem (from XNM1)
# Can be used alongside Plasma 6 - choose in display manager
{pkgs, ...}: {
  # ============================================================================
  # HYPRLAND WAYLAND COMPOSITOR
  # ============================================================================
  programs.hyprland = {
    enable = true;
    withUWSM = true; # uwsd-based session management
  };

  # Wayland environment variables
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1"; # Ozone Wayland support
    WLR_NO_HARDWARE_CURSORS = "1"; # Software cursor rendering
  };

  # ============================================================================
  # HYPRLAND ECOSYSTEM
  # ============================================================================
  programs.hyprlock.enable = true; # Screen lock

  environment.systemPackages = with pkgs; [
    # Python scripting for Hyprland
    pyprland

    # Core Hyprland tools
    hyprpicker # Color picker
    hyprcursor # Custom cursor support
    hyprlock # Screen locker
    hyprpaper # Wallpaper utility
    hyprsunset # Blue light filter
    hyprpolkitagent # Polkit agent for Hyprland

    # Wayland utilities
    waybar # Status bar
    rofi # Application launcher (Wayland support merged)
    wayvnc # VNC server for Wayland
  ];

  # ============================================================================
  # NOTES
  # ============================================================================
  # To use Hyprland instead of Plasma, select the "Hyprland" session in SDDM.
  #
  # Your Plasma 6 setup remains available - just choose:
  #   - "Plasma" session for KDE Plasma 6 Wayland
  #   - "Hyprland" session for Hyprland Wayland
  #
  # Both use the same Wayland optimizations from nvidia-wayland.nix or amdgpu-wayland.nix
}
