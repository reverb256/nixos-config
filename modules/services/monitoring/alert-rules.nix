{
  config,
  lib,
  pkgs,
  ...
}: let
  prometheusCfg = config.services.monitoring.prometheus;

  alertRulesContent = ''
    groups:
      - name: cluster_health
        interval: 30s
        rules:
          - alert: NodeDown
            expr: up{job="node"} == 0
            for: 2m
            labels:
              severity: critical
              cluster: reverb-os
            annotations:
              summary: "Node {{ $labels.instance }} is down"
              description: "{{ $labels.instance }} has been unreachable for more than 2 minutes"

          - alert: HighCPUUsage
            expr: '100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90'
            for: 10m
            labels:
              severity: warning
              cluster: reverb-os
            annotations:
              summary: "High CPU usage on {{ $labels.instance }}"
              description: "CPU usage is {{ $value }}% on {{ $labels.instance }}"

          - alert: HighMemoryUsage
            expr: '(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90'
            for: 5m
            labels:
              severity: warning
              cluster: reverb-os
            annotations:
              summary: "High memory usage on {{ $labels.instance }}"
              description: "Memory usage is {{ $value }}% on {{ $labels.instance }}"

          - alert: DiskSpaceLow
            expr: '(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 > 85'
            for: 5m
            labels:
              severity: warning
              cluster: reverb-os
            annotations:
              summary: "Low disk space on {{ $labels.instance }}"
              description: "Disk usage is {{ $value }}% on {{ $labels.instance }}"

          - alert: GPUTemperatureHigh
            expr: nvidia_smi_temperature_gpu > 85
            for: 5m
            labels:
              severity: warning
              cluster: reverb-os
            annotations:
              summary: "High GPU temperature on {{ $labels.instance }}"
              description: "GPU {{ $labels.gpu_id }} is at {{ $value }}°C on {{ $labels.instance }}"

      - name: ai_inference
        interval: 30s
        rules:
          - alert: AIGatewayDown
            expr: 'up{job="ai-inference-zephyr"} == 0'
            for: 2m
            labels:
              severity: critical
              cluster: reverb-os
            annotations:
              summary: "AI Inference Gateway is down"
              description: "The AI Inference Gateway on zephyr is not responding"

          - alert: HighAILatency
            expr: 'histogram_quantile(0.95, sum(rate(gateway_model_request_duration_seconds_bucket[5m])) by (le)) > 30'
            for: 5m
            labels:
              severity: warning
              cluster: reverb-os
            annotations:
              summary: "High AI request latency"
              description: "95th percentile latency is {{ $value }}s"

      - name: prometheus_health
        interval: 30s
        rules:
          - alert: PrometheusTargetMissing
            expr: up == 0
            for: 5m
            labels:
              severity: warning
              cluster: reverb-os
            annotations:
              summary: "Prometheus target missing"
              description: "Target {{ $labels.job }} on {{ $labels.instance }} is down"

  '';

  rulesFile = pkgs.writeText "prometheus-alert-rules.yml" alertRulesContent;
in {
  config = lib.mkIf prometheusCfg.enableAlertRules {
    services.prometheus.ruleFiles = [rulesFile];
  };
}
