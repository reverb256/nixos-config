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

  # Qt Wayland - REQUIRED for Plasma 6 Wayland sessions
  # Icon themes
  environment.systemPackages = with pkgs; [
    qt6.qtwayland
    tela-circle-icon-theme
  ];

  # NOTE: Plasma 6 startup race condition fix is in hosts/zephyr/configuration.nix
  # using systemd.user.units drop-in override (not systemd.user.services which breaks)
}
