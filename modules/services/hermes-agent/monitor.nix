# Hermes Agent Monitoring
# Exposes Hermes operations metrics to Prometheus
{ config, lib, pkgs, ... }:
let
  cfg = config.services.hermes-agent;
in lib.mkIf cfg.enable {
  # Text file metrics for Prometheus node_exporter
  # The default textfile collector directory is /var/lib/node_exporter/textfile_collector
  systemd.tmpfiles.settings."hermes-metrics" = {
    "/var/lib/node_exporter/textfile_collector/hermes.prom".L = {
      argument = "/etc/hermes-metrics.prom";
    };
  };

  environment.etc."hermes-metrics.prom" = {
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

  # Ensure textfile collector is enabled
  services.prometheus.exporters.node.enabledCollectors = [ "textfile" ];
}
