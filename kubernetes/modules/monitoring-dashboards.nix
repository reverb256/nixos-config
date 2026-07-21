_: let
  dashboardProvider = builtins.toJSON {
    apiVersion = 1;
    providers = [
      {
        name = "default";
        orgId = 1;
        folder = "";
        type = "file";
        disableDeletion = false;
        editable = true;
        updateIntervalSeconds = 30;
        options.path = "/var/lib/grafana/dashboards";
      }
    ];
  };

  nodeDashboard = builtins.toJSON {
    annotations = {list = [];};
    editable = true;
    graphTooltip = 1;
    id = null;
    links = [];
    panels = [
      {
        title = "CPU Usage (%)";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 0;
        };
        targets = [
          {
            expr = ''100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'';
            legendFormat = "{{instance}}";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
      {
        title = "Memory Usage (%)";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 0;
        };
        targets = [
          {
            expr = ''(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100'';
            legendFormat = "{{instance}}";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
      {
        title = "Disk Usage (%)";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 8;
        };
        targets = [
          {
            expr = ''(1 - node_filesystem_avail_bytes{fstype=~"ext4|btrfs|xfs"} / node_filesystem_size_bytes) * 100'';
            legendFormat = "{{instance}} {{mountpoint}}";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
      {
        title = "Network (bytes/sec)";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 8;
        };
        targets = [
          {
            expr = ''rate(node_network_receive_bytes_total{device=~"eth.*|enp.*"}[5m])'';
            legendFormat = "{{instance}} RX";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
          {
            expr = ''rate(node_network_transmit_bytes_total{device=~"eth.*|enp.*"}[5m])'';
            legendFormat = "{{instance}} TX";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
    ];
    schemaVersion = 39;
    tags = ["node" "infrastructure"];
    templating = {list = [];};
    time = {
      from = "now-1h";
      to = "now";
    };
    title = "Node Infrastructure";
    uid = "node-infra";
    version = 1;
  };

  gpuDashboard = builtins.toJSON {
    annotations = {list = [];};
    editable = true;
    graphTooltip = 1;
    id = null;
    panels = [
      {
        title = "GPU Utilization";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 0;
        };
        targets = [
          {
            expr = "nvidia_smi_utilization_gpu_ratio";
            legendFormat = "{{instance}}";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
      {
        title = "VRAM Usage (%)";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 0;
        };
        targets = [
          {
            expr = "nvidia_smi_memory_used_bytes / nvidia_smi_memory_total_bytes * 100";
            legendFormat = "{{instance}}";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
      {
        title = "GPU Temperature";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 8;
        };
        targets = [
          {
            expr = "nvidia_smi_temperature_gpu";
            legendFormat = "{{instance}}";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
      {
        title = "Power Draw (W)";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 8;
        };
        targets = [
          {
            expr = "nvidia_smi_power_draw_watts";
            legendFormat = "{{instance}}";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
    ];
    schemaVersion = 39;
    tags = ["gpu" "nvidia"];
    time = {
      from = "now-1h";
      to = "now";
    };
    title = "GPU Overview";
    uid = "gpu-overview";
    version = 1;
  };

  miningDashboard = builtins.toJSON {
    annotations = {list = [];};
    editable = true;
    graphTooltip = 1;
    id = null;
    panels = [
      {
        type = "timeseries";
        gridPos = {h = 8; w = 24; x = 0; y = 0;};
        targets = [{
          legendFormat = "{{instance}}";
          datasource = {type = "prometheus"; uid = "mimir";};
        }];
      }
      {
        title = "Total Good Shares";
        type = "stat";
        gridPos = {h = 4; w = 8; x = 0; y = 8;};
        targets = [{
          datasource = {type = "prometheus"; uid = "mimir";};
        }];
      }
    ];
    schemaVersion = 39;
    tags = ["mining"];
    time = {
      from = "now-6h";
      to = "now";
    };
    title = "Mining Operations";
    uid = "mining-ops";
    version = 1;
  };

  k8sDashboard = builtins.toJSON {
    annotations = {list = [];};
    editable = true;
    graphTooltip = 1;
    id = null;
    panels = [
      {
        title = "Pods by Namespace";
        type = "piechart";
        gridPos = {
          h = 8;
          w = 8;
          x = 0;
          y = 0;
        };
        targets = [
          {
            expr = "sum by(namespace)(kube_pod_info)";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
      {
        title = "Pod Restarts (1h)";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 16;
          x = 8;
          y = 0;
        };
        targets = [
          {
            expr = "sum by(namespace)(increase(kube_pod_container_status_restarts_total[1h]))";
            legendFormat = "{{namespace}}";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
      {
        title = "Node CPU (%)";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 8;
        };
        targets = [
          {
            expr = ''100 - (avg by(node)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'';
            legendFormat = "{{node}}";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
      {
        title = "Node Memory (%)";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 8;
        };
        targets = [
          {
            expr = ''(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100'';
            legendFormat = "{{instance}}";
            datasource = {
              type = "prometheus";
              uid = "mimir";
            };
          }
        ];
      }
    ];
    schemaVersion = 39;
    tags = ["kubernetes"];
    time = {
      from = "now-1h";
      to = "now";
    };
    title = "Kubernetes Cluster";
    uid = "k8s-cluster";
    version = 1;
  };

  nixCacheDashboard = builtins.toJSON {
    annotations = {list = [];};
    editable = true;
    graphTooltip = 1;
    id = null;
    panels = [
      {
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
      {
        title = "Requests / Second";
        type = "timeseries";
        gridPos = {h = 8; w = 9; x = 6; y = 0;};
        fieldConfig.defaults.unit = "reqps";
        targets = [{
          expr = "rate(nix_cache_requests_total[5m])";
          legendFormat = "req/s";
        }];
      }
      {
        title = "Hits vs Misses";
        type = "timeseries";
        gridPos = {h = 8; w = 9; x = 15; y = 0;};
        targets = [
          {expr = "rate(nix_cache_hits_total[5m])"; legendFormat = "hits/s";}
          {expr = "rate(nix_cache_misses_total[5m])"; legendFormat = "misses/s";}
        ];
      }
      {
        title = "Cache Fills";
        type = "timeseries";
        gridPos = {h = 8; w = 8; x = 0; y = 8;};
        targets = [
          {expr = "rate(nix_cache_fills_total[5m])"; legendFormat = "fills/s";}
          {expr = "rate(nix_cache_fill_errors_total[5m])"; legendFormat = "errors/s";}
        ];
      }
      {
        title = "Throughput";
        type = "timeseries";
        gridPos = {h = 8; w = 8; x = 8; y = 8;};
        fieldConfig.defaults.unit = "Bps";
        targets = [{
          expr = "rate(nix_cache_bytes_served_total[5m])";
          legendFormat = "bytes/s";
        }];
      }
      {
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
    schemaVersion = 39;
    tags = ["nix" "cache" "infrastructure"];
    time = {from = "now-1h"; to = "now";};
    title = "Nix Cache";
    uid = "nix-cache";
    version = 1;
  };
in {
  config.kubernetes.objects = {
    monitoring.ConfigMap.grafana-dashboards-provider.data."provider.yaml" = dashboardProvider;
    monitoring.ConfigMap.grafana-dashboards.data = {
      "node-infra.json" = nodeDashboard;
      "gpu-overview.json" = gpuDashboard;
      "mining-ops.json" = miningDashboard;
      "k8s-cluster.json" = k8sDashboard;
      "nix-cache.json" = nixCacheDashboard;
    };
  };
}
