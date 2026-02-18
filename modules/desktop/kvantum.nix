# Kvantum Theming Module
# Enables Kvantum Qt style for Plasma 6
#
# NOTE: Kvantum can cause issues with Plasma 6 Wayland on NVIDIA:
# - "module 'kvantum' is not installed" QML errors
# - EGL context creation failures for decorations
# 
# For stability, use Breeze (KDE's native style) instead:
#   qt.style = "breeze";
# Or leave qt.style = null to let Plasma manage styling

{ config, lib, pkgs, ... }:

{
  options.kvantum = {
    enable = lib.mkEnableOption "Enable Kvantum theming (may cause issues with Plasma 6 Wayland)";
  };

  config = lib.mkIf config.kvantum.enable {
    # Install Kvantum packages
    environment.systemPackages = with pkgs; [
      kdePackages.qtstyleplugin-kvantum
      kdePackages.qt6ct
    ];

    # Set Qt style to Kvantum via environment
    environment.sessionVariables = {
      QT_STYLE_OVERRIDE = "kvantum";
    };
  };
}
