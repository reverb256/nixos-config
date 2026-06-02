# Sentry Home-Manager Configuration
# Monitoring, logging — shared config (fish, starship, git, etc.) handled by modules/system/home-manager.nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf;
in {
  home-manager.users.j_kro = {pkgs, ...}: {
    home.stateVersion = "26.05";

    # Monitoring tools
    home.packages = with pkgs; [
      # Terminal
      alacritty

      # Monitoring
      btop
      glances

      # Log analysis
      gron
      jq

      # Network tools
      tcpdump
      wireshark-cli
    ];

    # Monitoring dashboards
    xdg.configFile."grafana/grafana.ini".source = ../../monitoring/grafana.ini;
    xdg.configFile."prometheus/prometheus.yml".source = ../../monitoring/prometheus.yml;

    # Log aggregation
    xdg.configFile."loki/config.yml".source = ../../monitoring/loki.yml;

    # Alert configuration
    xdg.configFile."alertmanager/config.yml".source = ../../monitoring/alertmanager.yml;

    # Monitoring scripts
    home.file.".local/bin/check-alerts.sh".source = ../../monitoring/check-alerts.sh;
    home.file.".local/bin/cluster-health.sh".source = ../../monitoring/cluster-health.sh;

    # CRITICAL: Zen Browser NOT managed here - see preservation.nix
    # Backup: /data/backups/sentry-20260531/zen-browser-profile.tar.gz (1.3 GB)
  };
}
