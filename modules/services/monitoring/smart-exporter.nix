# SMART Exporter for Prometheus
# Collects S.M.A.R.T. metrics from disk drives for health monitoring
# Provides early warning of disk failures
{
  config,
  lib,
  pkgs,
  ...
}: let
    cfg = config.services.monitoring.smart-exporter;
in {
  options.services.monitoring.smart-exporter = {
    enable = lib.mkEnableOption "S.M.A.R.T. metrics exporter for Prometheus";

    devices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of devices to monitor (e.g., [\"/dev/nvme0n1\" \"/dev/sda\"]). Empty = auto-detect all.";
    };

    collectPeriod = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Collection interval in seconds";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.smart = {
      enable = true;
      inherit (cfg) devices;
      inherit (cfg) collectPeriod;
      port = 9633;
    };

    # Open firewall for Prometheus scraping
    networking.firewall.allowedTCPPorts = [9633];
  };
}
