# Grafana Alloy - Log shipper to Loki
# Modern replacement for Promtail (which was EOL'd in nixpkgs 26.05)
# Deploy on EVERY host to ship systemd journal + container logs to central Loki
{
  config,
  lib,
  ...
}: let
  cfg = config.services.monitoring.grafana-alloy;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.monitoring.grafana-alloy = {
    enable = mkEnableOption "Grafana Alloy log shipper to Loki";
    lokiUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:3100/loki/api/v1/push";
      description = "Loki push URL (use sentry:3100 for remote hosts)";
    };
  };

  config = mkIf cfg.enable {
    services.alloy = {
      enable = true;
      # Declarative config via Nix, not River file
      # Using the NixOS module's built-in config support
      configPath = "/etc/alloy/config.alloy";
    };

    environment.etc."alloy/config.alloy".text = ''
      // Log collection from the systemd journal
      loki.source.journal "journal" {
        forward_to = [loki.write.endpoint.receiver]
        labels = {job = "systemd-journal"}
      }

      // Log collection from Kubernetes/Podman container log files
      local.file_match "containers" {
        path_targets = [{__path__ = "/var/log/pods/*/*/*.log"}]
      }

      loki.source.file "containers" {
        targets = local.file_match.containers.targets
        forward_to = [loki.write.endpoint.receiver]
      }

      // Ship to central Loki
      loki.write "endpoint" {
        endpoint {
          url = "${cfg.lokiUrl}"
        }
        external_labels = {
          instance = "${config.networking.hostName}",
        }
      }
    '';
  };
}
