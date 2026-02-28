# Niri Module - Scrollable-Tiling Wayland Compositor
# Rust-based compositor with unique scrollable tiling approach
# Import this module and enable with: programs.niri.enable = true;
{pkgs, ...}: {
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
    greetd.gtkgreet

    # Notifications
    mako
  ];

  # XDG Portal configuration for Niri
  xdg.portal = {
    config = {
      niri = {
        default = ["niri" "gtk"];
      };
    };
  };

  # Polkit agent (for Niri)
  security.polkit.enable = true;
}
