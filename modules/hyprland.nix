# Hyprland Module - Wayland Compositor with Tiling
# Optimized for gaming and VR on NVIDIA
{pkgs, lib, config, ...}: {
  options.programs.hyprland = {
    enable = lib.mkEnableOption "Hyprland Wayland compositor";
  };

  config = lib.mkIf config.programs.hyprland.enable {
    # Hyprland package
    programs.hyprland = {
      enable = true;
      xwayland.enable = true; # Enable XWayland for legacy app support
      package = pkgs.hyprland;
    };

    # Required packages for Hyprland
    environment.systemPackages = with pkgs; [
      waybar # Status bar
      rofi-wayland # Application launcher
      grim # Screenshot tool
      slurp # Region selection tool
      wl-clipboard # Clipboard utilities
      wlogout # Logout menu
      swww # Wallpaper utility
      pywalcolor # Color scheme generator
      xdg-desktop-portal-hyprland # XDG portal for Hyprland
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
  };
}
