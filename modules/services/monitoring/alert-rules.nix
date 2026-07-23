# Cluster Alert Rules
# Deployed on Sentry alongside Prometheus
# After adding a new rule, run: just deploy sentry
{ config, lib, ... }: let
  inherit (lib) mkIf;
  cfg = config.services.monitoring.prometheus;
in mkIf cfg.enableAlertRules {
  services.prometheus.alertmanagers = [{
    static_configs = [{
      targets = [ "127.0.0.1:${toString config.networking.cluster.ports.alertmanager}" ];
    }];
  }];

  services.prometheus.rules = let
    mkRule = name: alert: ''
      groups:
        - name: ${name}
          interval: 30s
          rules:
${builtins.concatStringsSep "\n" (map (a: "            ${builtins.toJSON a}") alert)}
    '';
  in [
    # ── Host health ──────────────────────────────────────────────
    (mkRule "host" [
      {
        alert = "HostDown";
        expr = "up{job='node'} == 0";
        for = "2m";
        labels = { severity = "critical"; };
        annotations = {
          summary = "Host {{ $labels.instance }} is unreachable";
          description = "Prometheus target {{ $labels.instance }} has been down for over 2 minutes.";
        };
      }
      {
        alert = "HostDiskSpaceWarning";
        expr = "node_filesystem_avail_bytes{mountpoint='/'} / node_filesystem_size_bytes{mountpoint='/'} * 100 < 15";
        for = "5m";
        labels = { severity = "warning"; };
        annotations = {
          summary = "Disk space low on {{ $labels.instance }}";
          description = "Less than 15% free on root partition ({{ $value | humanizePercentage }} available).";
        };
      }
      {
        alert = "HostDiskSpaceCritical";
        expr = "node_filesystem_avail_bytes{mountpoint='/'} / node_filesystem_size_bytes{mountpoint='/'} * 100 < 5";
        for = "1m";
        labels = { severity = "critical"; };
        annotations = {
          summary = "Disk space critical on {{ $labels.instance }}";
          description = "Less than 5% free on root partition ({{ $value | humanizePercentage }} available).";
        };
      }
    ])

    # ── GPU health ───────────────────────────────────────────────
    (mkRule "gpu" [
      {
        alert = "NvidiaGpuTempWarning";
        expr = "nvidia_smi_temperature_gpu > 85";
        for = "5m";
        labels = { severity = "warning"; };
        annotations = {
          summary = "GPU {{ $labels.gpu }} on {{ $labels.instance }} exceeds 85°C";
          description = "GPU temperature at {{ $value }}°C. Check cooling and airflow.";
        };
      }
      {
        alert = "NvidiaGpuTempCritical";
        expr = "nvidia_smi_temperature_gpu > 92";
        for = "1m";
        labels = { severity = "critical"; };
        annotations = {
          summary = "GPU {{ $labels.gpu }} on {{ $labels.instance }} near throttle threshold";
          description = "GPU temperature at {{ $value }}°C. Throttling imminent at 95°C.";
        };
      }
      {
        alert = "GpuMemoryTempHot";
        expr = "gputemps_vram_temperature_celsius > 100";
        for = "2m";
        labels = { severity = "critical"; };
        annotations = {
          summary = "GDDR6X VRAM on GPU {{ $labels.gpu }} exceeds 100°C";
          description = "VRAM temperature at {{ $value }}°C. Throttles at 110°C. Check thermal pads.";
        };
      }
    ])

    # ── Service health ───────────────────────────────────────────
    (mkRule "service" [
      {
        alert = "K3sNodeNotReady";
        expr = "kube_node_status_condition{condition='Ready',status='true'} == 0";
        for = "5m";
        labels = { severity = "critical"; };
        annotations = {
          summary = "K3s node {{ $labels.node }} is NotReady";
          description = "K3s node has been NotReady for 5 minutes.";
        };
      }
      {
        alert = "ServiceDown";
        expr = "up{job=~'grafana|prometheus|alertmanager'} == 0";
        for = "1m";
        labels = { severity = "critical"; };
        annotations = {
          summary = "{{ $labels.job }} is down";
          description = "Monitoring service {{ $labels.job }} (instance {{ $labels.instance }}) has been down for 1 minute.";
        };
      }
    ])

    # ── Temperature ──────────────────────────────────────────────
    (mkRule "temperature" [
      {
        alert = "CpuTempHot";
        expr = "node_hwmon_temp_celsius{sensor='coretemp'} > 80";
        for = "5m";
        labels = { severity = "warning"; };
        annotations = {
          summary = "CPU on {{ $labels.instance }} at {{ $value }}°C";
          description = "CPU temperature exceeds 80°C on instance {{ $labels.instance }}.";
        };
      }
      {
        alert = "NvmeTempHot";
        expr = "node_hwmon_temp_celsius{sensor='nvme'} > 65";
        for = "5m";
        labels = { severity = "warning"; };
        annotations = {
          summary = "NVMe drive hot on {{ $labels.instance }}";
          description = "NVMe temperature at {{ $value }}°C. Throttles at 70°C.";
        };
      }
    ])
  ];
}
