{ pkgs, ... }:
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

  xdg.configFile."grafana/grafana.ini".source = ../../monitoring/grafana.ini;
  xdg.configFile."prometheus/prometheus.yml".source = ../../monitoring/prometheus.yml;
  xdg.configFile."loki/config.yml".source = ../../monitoring/loki.yml;
  xdg.configFile."alertmanager/config.yml".source = ../../monitoring/alertmanager.yml;

  home.file.".local/bin/check-alerts.sh".source = ../../monitoring/check-alerts.sh;
  home.file.".local/bin/cluster-health.sh".source = ../../monitoring/cluster-health.sh;
}
