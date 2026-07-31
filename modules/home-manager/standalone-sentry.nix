{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    alacritty
    btop
    glances
    gron
    jq
    tcpdump
    wireshark-cli
  ];

  # Optional monitoring-tool config seeds — only applied when the source file
  # exists in the flake tree (pre-existing gap: monitoring/ dir not committed).
  # Resilient so the standalone HM layer builds regardless.
  xdg.configFile."grafana/grafana.ini" = lib.mkIf (builtins.pathExists ../../monitoring/grafana.ini) {
    source = ../../monitoring/grafana.ini;
  };
  xdg.configFile."prometheus/prometheus.yml" = lib.mkIf (builtins.pathExists ../../monitoring/prometheus.yml) {
    source = ../../monitoring/prometheus.yml;
  };
  xdg.configFile."loki/config.yml" = lib.mkIf (builtins.pathExists ../../monitoring/loki.yml) {
    source = ../../monitoring/loki.yml;
  };
  xdg.configFile."alertmanager/config.yml" = lib.mkIf (builtins.pathExists ../../monitoring/alertmanager.yml) {
    source = ../../monitoring/alertmanager.yml;
  };

  home.file.".local/bin/check-alerts.sh" = lib.mkIf (builtins.pathExists ../../monitoring/check-alerts.sh) {
    source = ../../monitoring/check-alerts.sh;
  };
  home.file.".local/bin/cluster-health.sh" = lib.mkIf (builtins.pathExists ../../monitoring/cluster-health.sh) {
    source = ../../monitoring/cluster-health.sh;
  };
}
