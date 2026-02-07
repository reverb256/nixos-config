{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.monitoring;
in {
  options.services.monitoring = {
    enable = mkEnableOption "Prometheus + Grafana Monitoring";
    grafanaPort = mkOption {
      type = types.port;
      default = 3001;
      description = "Grafana web UI port";
    };
    prometheusPort = mkOption {
      type = types.port;
      default = 9090;
      description = "Prometheus metrics port";
    };
    alertingEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable alerting rules";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.prometheus pkgs.grafana];

    # Prometheus configuration
    environment.etc."prometheus/prometheus.yml".text = ''
      global:
        scrape_interval: 15s
        evaluation_interval: 15s

      alertmanagers:
        - static_configs:
            - targets: []

      rule_files:
        - /etc/prometheus/rules/*.yml

      scrape_configs:
        - job_name: "prometheus"
          static_configs:
            - targets: ["localhost:${toString cfg.prometheusPort}"]

        - job_name: "node"
          static_configs:
            - targets: ["localhost:9100"]

        - job_name: "nvidia"
          static_configs:
            - targets: ["localhost:14445"]

        - job_name: "openclaw"
          static_configs:
            - targets: ["localhost:18789"]

        - job_name: "mining"
          static_configs:
            - targets: ["localhost:4068"]

      alerting:
        alertmanagers:
          - static_configs:
              - targets: []
        rules:
          - alert: HighCPU
            expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High CPU usage on {{ $labels.instance }}"

          - alert: HighMemory
            expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High memory usage on {{ $labels.instance }}"

          - alert: DiskFull
            expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 90
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Disk almost full on {{ $labels.instance }}"
    '';

    # Create prometheus directories
    systemd.tmpfiles.rules = [
      "d /var/lib/prometheus 0750 prometheus prometheus - -"
      "d /var/log/prometheus 0750 prometheus prometheus - -"
      "d /etc/prometheus/rules 0750 prometheus prometheus - -"
    ];

    # Prometheus service
    systemd.services.prometheus = {
      description = "Prometheus Monitoring";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        User = "prometheus";
        Group = "prometheus";
        ExecStart = "${pkgs.prometheus}/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --web.enable-lifecycle --web.listen-address=:${toString cfg.prometheusPort}";
        Restart = "always";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadOnlyPaths = "/";
        ReadWritePaths = ["/var/lib/prometheus" "/var/log/prometheus"];
      };
    };

    # Grafana configuration
    environment.etc."grafana/grafana.ini".text = ''
      [server]
      http_port = ${toString cfg.grafanaPort}
      root_url = http://localhost:${toString cfg.grafanaPort}
      enable_gzip = true

      [security]
      admin_user = admin
      admin_password = ${config.secrets.grafanaPassword or (lib.throwError "Grafana password must be set in config.secrets.grafanaPassword. Run: openssl rand -base64 32 | nix-shell -p age --run 'age -r <AGE_PUBLIC_KEY> -o /etc/nixos/secrets/grafana-password.age /dev/stdin'\nThen add grafana-password entry to secrets/age-secrets.nix.\nSee docs/INCIDENT_RESPONSE_PLAN.md for security procedures.")}
      disable_admin_auth = false

      [paths]
      provisioning = /etc/grafana/provisioning

      [dashboards]
      default_home_dashboard_path = /etc/grafana/dashboards/node-exporter.json
    '';

    systemd.services.grafana = {
      description = "Grafana Visualization";
      after = ["prometheus.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = "${pkgs.grafana}/bin/grafana-server --config=/etc/grafana/grafana.ini";
        Restart = "always";
        User = "grafana";
        Group = "grafana";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadOnlyPaths = "/";
        ReadWritePaths = ["/var/lib/grafana"];
      };
    };

    # Firewall: Only localhost access
    networking.firewall.interfaces.lo.allowedTCPPorts = [
      cfg.prometheusPort
      cfg.grafanaPort
      9100 # Node exporter
      14445 # NVIDIA DCGM
    ];
  };
}
