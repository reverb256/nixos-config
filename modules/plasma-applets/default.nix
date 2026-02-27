# Plasma Applets
# Custom KDE Plasma widgets for desktop monitoring
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.monitoring.plasma-applets;
in {
  options.services.monitoring.plasma-applets = {
    enable = lib.mkEnableOption "Plasma monitoring applets";

    clusterMonitor = {
      enable = lib.mkEnableOption "Cluster Monitor plasmoid";

      prometheusUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:9090";
        description = "Prometheus API URL for metrics";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable additional KDE/Plasma packages
    environment.systemPackages = with pkgs; [
      # KDE Plasma workspace
      plasma-workspace
      # Additional Plasma components
      kdeplasma-addons
      # Network monitoring tools
      ksysguard
    ];

    # Install plasmoids to user directory
    systemd.user.tmpfiles.rules = [
      "d ~/.local/share/plasma/plasmoids 0775 ${config.users.users.j_kro.name} ${config.users.users.j_kro.name} -"
    ];

    # Copy cluster monitor plasmoid
    systemd.tmpfiles.rules = [
      "C+ ~/.local/share/plasma/plasmoids/cluster-monitor - - - - - ${config.users.users.j_kro.name} ${config.users.users.j_kro.name} - -"
      "L+ ~/.local/share/plasma/plasmoids/cluster-monitor - - - - - ${config.users.users.j_kro.name} ${config.users.users.j_kro.name} - -"
    ];
  };
}
