# Hermes Agent Monitoring
# Exposes Hermes operations metrics to Prometheus
{ config, lib, pkgs, ... }:
let
  cfg = config.services.hermes-agent;
in lib.mkIf cfg.enable {
  # Text file metrics for Prometheus node_exporter
  environment.etc."hermes-metrics/prometheus" = {
    enable = true;
    text = ''
# HELP hermes_commands_total Total number of Hermes commands executed
# TYPE hermes_commands_total counter
hermes_commands_total{node="${config.networking.hostName}"} 0

# HELP hermes_commands_success_total Number of successful Hermes commands
# TYPE hermes_commands_success_total counter
hermes_commands_success_total{node="${config.networking.hostName}"} 0

# HELP hermes_commands_failed_total Number of failed Hermes commands
# TYPE hermes_commands_failed_total counter
hermes_commands_failed_total{node="${config.networking.hostName}"} 0

# HELP hermes_ai_gateway_calls_total Total calls to AI Gateway from Hermes
# TYPE hermes_ai_gateway_calls_total counter
hermes_ai_gateway_calls_total{node="${config.networking.hostName}"} 0

# HELP hermes_active_skills Number of active skills loaded
# TYPE hermes_active_skills gauge
hermes_active_skills{node="${config.networking.hostName}"} ${toString (lib.length (lib.attrNames cfg.customSkills))}

# HELP hermes_up Whether Hermes is up (1=up, 0=down)
# TYPE hermes_up gauge
hermes_up{node="${config.networking.hostName}"} 1
'';
  };

  # Script to update metrics (called by Hermes wrapper or systemd)
  environment.etc."hermes-metrics/update-metrics.sh" = {
    enable = true;
    executable = true;
    text = ''
#!/usr/bin/env bash
# Update Hermes metrics for Prometheus node_exporter
METRICS_DIR="/etc/hermes-metrics/prometheus"
METRICS_FILE="$METRICS_DIR/.prom"

hermes_command_increment() {
  sed -i "s/hermes_commands_total.*/hermes_commands_total{node=\"$(hostname)\"} $(('hermes_commands_total{node=\"$(hostname)\"}' + 1))/" "$METRICS_FILE"
}

hermes_success_increment() {
  sed -i "s/hermes_commands_success_total.*/hermes_commands_success_total{node=\"$(hostname)\"} $(('hermes_commands_success_total{node=\"$(hostname)\"}' + 1))/" "$METRICS_FILE"
}

hermes_failed_increment() {
  sed -i "s/hermes_commands_failed_total.*/hermes_commands_failed_total{node=\"$(hostname)\"} $(('hermes_commands_failed_total{node=\"$(hostname)\"}' + 1))/" "$METRICS_FILE"
}

# Export functions for use in Hermes wrapper
export -f hermes_command_increment
export -f hermes_success_increment
export -f hermes_failed_increment
'';
  };

  # Prometheus node_exporter textfile collector
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [ "textfile" ];
    extraOpts = [
      "--collector.textfile.directories=${config.environment.etc."hermes-metrics".directory}"
    ];
  };
}
