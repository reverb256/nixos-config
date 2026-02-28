# Hyprland Module - Wayland Compositor with Tiling
# Optimized for gaming and VR on NVIDIA
# Import this module and enable with: programs.hyprland.enable = true;
{pkgs, ...}: {
  # Required packages for Hyprland
  environment.systemPackages = with pkgs; [
    waybar # Status bar
    rofi # Application launcher
    grim # Screenshot tool
    slurp # Region selection tool
    wlogout # Logout menu
    swww # Wallpaper utility
    # pywalcolor - removed, package no longer exists
    xdg-desktop-portal-hyprland # XDG portal for Hyprland
    gtkgreet # Graphical greeter for stand-alone Hyprland
  ];

  # XDG Portal configuration for Hyprland
  xdg.portal = {
    config = {
      hyprland = {
        default = ["hyprland" "gtk"];
      };
    };
  };

  # Polkit agent (for Hyprland)
  security.polkit.enable = true;
}
