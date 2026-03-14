# Promtail log aggregation client
# Sends journald logs to Loki on Sentry
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.monitoring.promtail;
in {
  options.services.monitoring.promtail = {
    enable = lib.mkEnableOption "Promtail log agent for Loki";

    lokiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://10.1.1.140:3100/loki/api/v1/push";
      description = "Loki server push URL";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.promtail];

    systemd.services.promtail = {
      description = "Promtail Log Agent";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "systemd-journald.service"];
      requires = ["systemd-journald.service"];
      wants = ["network-online.target"];  # Fix ordering warning

      serviceConfig = {
        ExecStart = ''
          ${pkgs.promtail}/bin/promtail \
            --config.file=/etc/promtail/config.yml \
            --config.expand-env=true
        '';
        Restart = "always";
        RestartSec = "5s";
        DynamicUser = true;
        # Add to systemd-journal group for journal access
        SupplementaryGroups = ["systemd-journal"];

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = "/";
        ReadWritePaths = ["/var/lib/promtail" "/var/log" "/var/cache/promtail"];

        # Log access
        LogsDirectory = "promtail";
        StateDirectory = "promtail";
        # CacheDirectory for positions file
        CacheDirectory = "promtail";
      };
    };

    # Promtail configuration
    environment.etc."promtail/config.yml".text = ''
      server:
        http_listen_address: "127.0.0.1"
        http_listen_port: 9080
        grpc_listen_port: 0

      positions:
        filename: /var/cache/promtail/positions.yaml

      clients:
        - url: ${cfg.lokiUrl}
          tenant_id: fake

      scrape_configs:
        - job_name: journal
          journal:
            max_age: 12h
            labels:
              host: ${config.networking.hostName}
              cluster: nixos-cluster
          relabel_configs:
            - source_labels: ["__journal__systemd_unit"]
              target_label: unit
            - source_labels: ["__journal__hostname"]
              target_label: host
            - source_labels: ["__journal__priority"]
              target_label: priority
            - source_labels: ["__journal__transport"]
              target_label: transport
    '';
  };
}
