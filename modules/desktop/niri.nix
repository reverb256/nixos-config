# Niri Module - Scrollable-Tiling Wayland Compositor
# Rust-based compositor with unique scrollable tiling approach
# Import this module and enable with: programs.niri.enable = true;
{pkgs, config, ...}: {
  # Required packages for Niri
  environment.systemPackages = with pkgs; [
    # Core Niri
    niri

    # XDG portals
    xdg-utils
    xdg-desktop-portal
    xdg-desktop-portal-gtk

    # Wayland essentials
    waybar # Status bar
    rofi # Application launcher
    grim # Screenshot tool
    slurp # Region selection tool
    wlogout # Logout menu
    swww # Wallpaper utility

    # Screenshots and recording
    wl-clipboard
    wl-clip-persist
    cliphist

    # Input tools
    wtype
    wlrctl

    # Gtkgreet for graphical login
    gtkgreet
  ] ++ lib.optionals config.programs.niri.enable [
    # Notifications - only when Niri is enabled
    # Note: This module should only be imported in Niri-specific configurations
    # (e.g., hyprland-niri specialization) to avoid conflicts with Plasma
    mako
  ];

  # XDG Portal configuration for Niri (uses upstream defaults)
  xdg.portal = {
    config = {
      niri = {
        default = ["gnome" "gtk"];
      };
    };
  };

  # Polkit agent (for Niri)
  security.polkit.enable = true;
}
