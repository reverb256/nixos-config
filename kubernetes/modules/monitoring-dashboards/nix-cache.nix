{
  config,
  lib,
  ...
}: let
  dashboardJSON = builtins.toJSON {
    title = "Nix Cache";
    uid = "nix-cache";
    tags = ["nix" "cache" "infrastructure"];
    timezone = "browser";
    schemaVersion = 39;
    refresh = "30s";
    panels = [
      # ── Hit Rate Gauge ────────────────────────────────────
      {
        id = 1;
        title = "Cache Hit Rate";
        type = "gauge";
        gridPos = {h = 8; w = 6; x = 0; y = 0;};
        fieldConfig.defaults = {
          unit = "percentunit";
          min = 0;
          max = 1;
          thresholds = {
            mode = "absolute";
            steps = [
              {color = "red"; value = 0;}
              {color = "yellow"; value = 0.5;}
              {color = "green"; value = 0.8;}
            ];
          };
        };
        targets = [{
          expr = "rate(nix_cache_hits_total[5m]) / (rate(nix_cache_hits_total[5m]) + rate(nix_cache_misses_total[5m]))";
          legendFormat = "hit rate";
        }];
      }
      # ── Requests per second ───────────────────────────────
      {
        id = 2;
        title = "Requests / Second";
        type = "timeseries";
        gridPos = {h = 8; w = 9; x = 6; y = 0;};
        fieldConfig.defaults.unit = "reqps";
        targets = [
          {
            expr = "rate(nix_cache_requests_total[5m])";
            legendFormat = "req/s";
          }
        ];
      }
      # ── Cache Hits vs Misses ──────────────────────────────
      {
        id = 3;
        title = "Hits vs Misses";
        type = "timeseries";
        gridPos = {h = 8; w = 9; x = 15; y = 0;};
        targets = [
          {
            expr = "rate(nix_cache_hits_total[5m])";
            legendFormat = "hits/s";
          }
          {
            expr = "rate(nix_cache_misses_total[5m])";
            legendFormat = "misses/s";
          }
        ];
      }
      # ── Cache Fills ───────────────────────────────────────
      {
        id = 4;
        title = "Cache Fills";
        type = "timeseries";
        gridPos = {h = 8; w = 8; x = 0; y = 8;};
        targets = [
          {
            expr = "rate(nix_cache_fills_total[5m])";
            legendFormat = "fills/s";
          }
          {
            expr = "rate(nix_cache_fill_errors_total[5m])";
            legendFormat = "errors/s";
          }
        ];
      }
      # ── Bytes Served ──────────────────────────────────────
      {
        id = 5;
        title = "Throughput";
        type = "timeseries";
        gridPos = {h = 8; w = 8; x = 8; y = 8;};
        fieldConfig.defaults.unit = "Bps";
        targets = [{
          expr = "rate(nix_cache_bytes_served_total[5m])";
          legendFormat = "bytes/s";
        }];
      }
      # ── Uptime ────────────────────────────────────────────
      {
        id = 6;
        title = "Uptime";
        type = "stat";
        gridPos = {h = 8; w = 8; x = 16; y = 8;};
        fieldConfig.defaults.unit = "s";
        targets = [{
          expr = "nix_cache_uptime_seconds";
          legendFormat = "uptime";
        }];
      }
    ];
  };
in {
  config.kubernetes.objects.monitoring.ConfigMap.grafana-dashboard-nix-cache = {
    metadata.labels = {
      grafana_dashboard = "1";
      "app.kubernetes.io/managed-by" = "easykubenix";
    };
    data."nix-cache.json" = dashboardJSON;
  };
}
