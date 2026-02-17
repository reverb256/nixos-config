# Kvantum Theming Module
# Enables Kvantum Qt style for Plasma 6

{ config, pkgs, ... }:

{
  options.kvantum = {
    enable = lib.mkEnableOption "Enable Kvantum theming";
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
