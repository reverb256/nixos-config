# Hyprland Module
# Wayland compositor with Noctalia shell ecosystem
# Can be used alongside Plasma 6 - choose in display manager
{pkgs, ...}: {
  # ============================================================================
  # HYPRLAND WAYLAND COMPOSITOR
  # ============================================================================
  programs.hyprland = {
    enable = true;
    withUWSM = true; # uwsd-based session management
  };

  # ============================================================================
  # HYPRLAND ECOSYSTEM
  # ============================================================================
  programs.hyprlock.enable = true; # Screen lock

  environment.systemPackages = with pkgs; [
    # Desktop shell (bar, notifications, launcher, dock, wallpapers)
    noctalia-shell

    # Core Hyprland tools
    hyprpicker # Color picker
    hyprcursor # Custom cursor support
    hyprlock # Screen locker
    hyprsunset # Blue light filter
    hyprpolkitagent # Polkit agent for Hyprland

    # Wayland utilities
    wayvnc # VNC server for Wayland

    # Cursor theme
    adwaita-icon-theme
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
