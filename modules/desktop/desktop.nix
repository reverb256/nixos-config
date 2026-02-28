# Desktop Module - Minimal Plasma Desktop Environment
{pkgs, lib, ...}: {
  # SDDM is the default display manager (used by Hyprland, Niri, Sway)
  services.displayManager.sddm = {
    enable = lib.mkDefault true;  # Can be overridden for plasma-login-manager
    wayland.enable = lib.mkDefault true;
  };

  # Plasma 6 desktop (primary DE for zephyr)
  services.desktopManager.plasma6.enable = true;

  # X11 server is required for both Wayland and X11 sessions
  services.xserver.enable = true;
}
