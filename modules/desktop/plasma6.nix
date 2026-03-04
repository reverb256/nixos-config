# KDE Plasma 6 Desktop Environment
{ config, lib, pkgs, ... }:
{
  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Enable auto-login for j_kro
  services.displayManager.autoLogin = {
    enable = true;
    user = "j_kro";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
}
