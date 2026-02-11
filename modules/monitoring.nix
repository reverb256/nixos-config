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
    alertmanagerPort = mkOption {
      type = types.port;
      default = 9093;
      description = "Alertmanager web UI port";
    };
    enableAlertmanager = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Alertmanager service";
    };
    alertmanagerWebhookUrl = mkOption {
      type = types.str;
      default = "";
      description = "Alertmanager webhook URL (for Slack/Discord notifications)";
    };
    alertmanagerEmail = mkOption {
      type = types.str;
      default = "";
      description = "Alertmanager email address for notifications";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.prometheus pkgs.grafana pkgs.prometheus-node-exporter pkgs.nvidia-smi pkgs.nvidia-dcgm-exporter pkgs.prometheus-alertmanager pkgs.prometheus-pushgateway pkgs.curl];

    # Prometheus configuration
    environment.etc."prometheus/prometheus.yml".text = ''
      global:
        scrape_interval: 15s
        evaluation_interval: 15s

      alertmanagers:
        - static_configs:
            - targets: ${lib.optionalString cfg.enableAlertmanager ["localhost:${toString cfg.alertmanagerPort}"]}

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

        - job_name: "mining"
          static_configs:
            - targets: ["localhost:4068"]

        - job_name: "nvidia-smi"
          static_configs:
            - targets: ["localhost:9200"]

        - job_name: "blackbox"
          static_configs:
            - targets: ["localhost:9115"]

      alerting:
        alertmanagers:
          - static_configs:
              - targets: ${lib.optionalString cfg.enableAlertmanager ["localhost:${toString cfg.alertmanagerPort}"]}
        rules:
          # Resource alerts
          - alert: HighCPU
            expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
            for: 5m
            labels:
              severity: warning
              category: resource
            annotations:
              summary: "High CPU usage on {{ $labels.instance }}"

          - alert: HighMemory
            expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
            for: 5m
            labels:
              severity: warning
              category: resource
            annotations:
              summary: "High memory usage on {{ $labels.instance }}"

          - alert: DiskFull
            expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 90
            for: 5m
            labels:
              severity: critical
              category: infrastructure
            annotations:
              summary: "Disk almost full on {{ $labels.instance }}"

          # Service alerts
          - alert: MiningServiceDown
            expr: up{job="mining"} == 0
            for: 1m
            labels:
              severity: critical
              category: mining
            annotations:
              summary: "Mining service is down on {{ $labels.instance }}"

          # Security KPIs - MTTD & MTTR
          - alert: HighMTTD
            expr: avg(increase(prometheus_alerts{alertstate="firing"}[5m])) > 300
            for: 5m
            labels:
              severity: warning
              category: security
            annotations:
              summary: "Mean Time to Detection (MTTD) exceeds 5 minutes: {{ $value }}s"

          - alert: HighMTTR
            expr: avg(prometheus_alerts{alertstate="firing"} - prometheus_alerts{alertstate="firing"} offset 5m)[5m]) > 900
            for: 5m
            labels:
              severity: critical
              category: security
            annotations:
              summary: "Mean Time to Response (MTTR) exceeds 15 minutes: {{ $value }}s"

          # Mining specific alerts
          - alert: MiningHashrateDrop
            expr: rate(mining_shares_total[10m]) < 1
            for: 10m
            labels:
              severity: warning
              category: mining
            annotations:
              summary: "Mining hashrate dropped significantly on {{ $labels.instance }}"

          # GPU alerts
          - alert: GPUHighTemperature
            expr: nvidia_gpu_temperature_celsius > 85
            for: 2m
            labels:
              severity: warning
              category: hardware
            annotations:
              summary: "GPU temperature exceeds 85°C on {{ $labels.instance }}"

          - alert: GPUMemoryHigh
            expr: nvidia_gpu_memory_used_bytes / nvidia_gpu_memory_total_bytes > 0.9
            for: 2m
            labels:
              severity: warning
              category: hardware
            annotations:
              summary: "GPU memory usage exceeds 90% on {{ $labels.instance }}"
    '';

    # Grafana provisioning
    systemd.tmpfiles.rules = [
      "d /var/lib/prometheus 0750 prometheus prometheus -"
      "d /var/log/prometheus 0750 prometheus prometheus -"
      "d /etc/prometheus/rules 0750 prometheus prometheus -"
      "d /etc/grafana/provisioning/dashboards 0750 grafana grafana -"
      "d /etc/grafana/provisioning/dashboards/security-kpis.json 0750 grafana grafana -"
      "d /etc/grafana/provisioning/dashboards/cluster-overview.json 0750 grafana grafana -"
      "d /etc/grafana/provisioning/dashboards/hardware-mining.json 0750 grafana grafana -"
      "d /etc/prometheus/templates 0750 alertmanager alertmanager -"
    ];

    # NVIDIA DCGM exporter
    systemd.services.nvidia-dcgm = lib.mkIf (cfg.enableAlertmanager && config.hardware.nvidia.enable) {
      description = "NVIDIA DCGM Exporter for GPU metrics";
      after = ["network.target" "prometheus.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        User = "prometheus";
        Group = "prometheus";
        ExecStart = "${pkgs.nvidia-dcgm-exporter}/bin/dcgm-exporter -f -n -p 9200 -d localhost:9200 -c GPU";
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadOnlyPaths = "/";
      };
    };

    # Node exporter blackbox for network monitoring
    systemd.services.prometheus-blackbox = {
      description = "Prometheus Blackbox Exporter for network latency";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        User = "prometheus";
        ExecStart = "${pkgs.prometheus-blackbox-exporter}/bin/prometheus-blackbox-exporter --config.file=/etc/prometheus/blackbox.yml";
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadOnlyPaths = "/";
      };
    };

    # Blackbox configuration
    environment.etc."prometheus/blackbox.yml".text = ''
      modules:
        http_2xx:
          prober: http
          timeout: 5s
          http:
            valid_http_versions: ["HTTP/1.1", "HTTP/2"]
            valid_status_codes: []
            method: GET

        icmp:
          prober: icmp
          timeout: 5s
          preferred_ip_protocol: ip4

        dns:
          prober: dns
          timeout: 5s
          dns_over_tcp: true
          dns_query_name: "A"

      targets:
        - name: Google DNS
          url: "8.8.8.8"

        - name: Quad9 DNS
          url: "9.9.9.9"

        - name: Cloudflare DNS
          url: "1.1.1.1"

        - name: Tailscale DNS
          url: "100.100.100.100"

        - name: Localhost
          url: "127.0.0.1"

        - name: zephyr
          url: "10.1.1.110"

        - name: nexus
          url: "10.1.1.120"

        - name: forge
          url: "10.1.1.130"

        - name: sentry
          url: "10.1.1.140"
    '';

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
      dashboards = /etc/grafana/provisioning/dashboards

      [users]
      disable_signout_menu = true

      [database]
      type = sqlite3
      path = /var/lib/grafana
    '';

    # Grafana service
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

    # Alertmanager configuration
    systemd.services.alertmanager = lib.mkIf cfg.enableAlertmanager {
      description = "Prometheus Alertmanager";
      after = ["prometheus.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        User = "alertmanager";
        Group = "alertmanager";
        ExecStart = "${pkgs.prometheus-alertmanager}/bin/amtool --config.file=/etc/prometheus/alertmanager.yml";
        Restart = "always";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
      };
    };

    # Alertmanager configuration file
    environment.etc."prometheus/alertmanager.yml".text = ''
      global:
        resolve_timeout: 5m

      route:
        group_by: [alertname, cluster, instance]
        group_wait: 10s
        group_interval: 10s
        repeat_interval: 12h
        receiver: 'default'

      receivers:
        - name: 'default'
          email_configs:
            - to: '${cfg.alertmanagerEmail}'
              from: 'alertmanager@nixos-cluster'
              headers:
                Subject: '[{{ .Status }}] {{ .GroupLabels.alertname }}: {{ .CommonAnnotations.summary }}'

        - name: 'webhook'
          webhook_configs:
            - url: '${cfg.alertmanagerWebhookUrl}'
              send_resolved: true
              send_firing: true

      inhibit_rules:
        # Do not send alerts if alerting is disabled
        - target_match_re:
            source_re: 'alertmanager'
            match_re:
              disabled: 'true'

       templates:
         - '/etc/prometheus/templates/*.tmpl'
    '';

    # Alertmanager email templates
    environment.etc."prometheus/templates/default.tmpl".text = ''
      {{ define "subject" }}[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:Firing{{ end }}] {{ .GroupLabels.alertname }}]{{ end }}

      {{ define "slack_message" }}Alert: {{ .GroupLabels.alertname }}
      Description: {{ .CommonAnnotations.summary }}

      Labels:
      {{ range .CommonLabels.SortedPairs }}{{ .Name }}: {{ .Value }}{{ end }}

      {{ range .Alerts.SortedPairs }}{{ .Name }}: {{ .Value }}{{ end }}

      {{ end }}

      {{ define "email_body" }}Alert: {{ .GroupLabels.alertname }}
      {{ if gt (len .Alerts.Firing) 0 }}Firing:{{ end }}
      {{ if gt (len .Alerts.Resolved) 0 }}Resolved:{{ end }}
      Description: {{ .CommonAnnotations.summary }}

      Labels:
      {{ range .CommonLabels.SortedPairs }}{{ .Name }}: {{ .Value }}{{ end }}

      {{ range .Alerts.SortedPairs }}{{ .Name }}: {{ .Value }}{{ end }}

      {{ if gt (len .Alerts.Firing) 0 }}
      Starts: {{ .Alerts.Firing | len }} alert(s)
      {{ end }}
      {{ if gt (len .Alerts.Resolved) 0 }}
      Ends: {{ .Alerts.Resolved | len }} alert(s)
      {{ end }}
      {{ end }}
    '';

    # Firewall: Only localhost access
    networking.firewall.interfaces.lo.allowedTCPPorts = [
      cfg.prometheusPort
      cfg.grafanaPort
      9100 # Node exporter
      14445 # NVIDIA DCGM
    ];
  };
}
