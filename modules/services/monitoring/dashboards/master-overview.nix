# Master Overview Dashboard
# High-level cluster health, alerts summary, and navigation hub
{lib, ...}: let
  inherit (lib.dashboard) panels template grid thresholds;
in {
  masterOverview = template {
    title = "🏠 Master Overview";
    description = "Cluster health at a glance - quick status of all systems";
    tags = ["overview" "cluster"];
    panels = [
      # ========== ROW: CLUSTER STATUS ==========
      (panels.row "🖥️ Cluster Status" false)
      # Node Health Stat
      (panels.stat {
        title = "Nodes Online";
        expr = "count(up{job=\"node\"} == 1)";
        gridPos = {h = 4; w = 6; x = 0; y = 1;};
        thresholds = thresholds.binary;
        colorMode = "background";
      })
      # Services Health Stat
      (panels.stat {
        title = "Services Healthy";
        expr = "count(up == 1)";
        gridPos = {h = 4; w = 6; x = 6; y = 1;};
        thresholds = thresholds.binary;
        colorMode = "background";
      })
      # Active Alerts Stat
      (panels.stat {
        title = "Active Alerts";
        expr = "count(ALERTS{alertstate=\"firing\"})";
        gridPos = {h = 4; w = 6; x = 12; y = 1;};
        thresholds = [
          {color = "green"; value = null;}
          {color = "yellow"; value = 1;}
          {color = "orange"; value = 5;}
          {color = "red"; value = 10;}
        ];
        colorMode = "background";
      })
      # Total Hashrate
      (panels.stat {
        title = "Total Hashrate";
        expr = "sum(mining_worker_hashrate)";
        gridPos = {h = 4; w = 6; x = 18; y = 1;};
        unit = "hertz";
        colorMode = "value";
      })

      # ========== ROW: RESOURCES OVERVIEW ==========
      (panels.row "📊 Resource Overview" false)
      # Cluster CPU Usage
      (panels.gauge {
        title = "Cluster CPU Usage";
        expr = "avg(100 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)";
        gridPos = {h = 8; w = 6; x = 0; y = 5;};
        thresholds = thresholds.percentage;
        unit = "percent";
      })
      # Cluster Memory Usage
      (panels.gauge {
        title = "Cluster Memory Usage";
        expr = "avg((1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)";
        gridPos = {h = 8; w = 6; x = 6; y = 5;};
        thresholds = thresholds.percentage;
        unit = "percent";
      })
      # Cluster Disk Usage
      (panels.gauge {
        title = "Cluster Disk Usage";
        expr = "avg((1 - node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"}) * 100)";
        gridPos = {h = 8; w = 6; x = 12; y = 5;};
        thresholds = thresholds.percentage;
        unit = "percent";
      })
      # GPU Utilization
      (panels.gauge {
        title = "GPU Utilization (Avg)";
        expr = "avg(nvidia_smi_utilization_gpu_ratio) * 100";
        gridPos = {h = 8; w = 6; x = 18; y = 5;};
        thresholds = [
          {color = "red"; value = null;}
          {color = "yellow"; value = 20;}
          {color = "orange"; value = 50;}
          {color = "green"; value = 80;}
        ];
        unit = "percent";
      })

      # ========== ROW: NODE GRID ==========
      (panels.row "🖥️ Per-Node Status" false)
      # Node CPU Table
      {
        datasource = lib.dashboard.prometheusDatasource;
        gridPos = {h = 8; w = 12; x = 0; y = 13;};
        options = {showHeader = true;};
        targets = [
          {
            expr = "100 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100";
            format = "table";
            instant = true;
            refId = "A";
          }
        ];
        title = "CPU Usage by Node";
        type = "table";
        transformations = [
          {id = "organize"; options = {excludeByName = {"__name__" = true; "job" = true; "mode" = true;}; indexByName = {}; renameByName = {};};}
        ];
      }
      # Node Memory Table
      {
        datasource = lib.dashboard.prometheusDatasource;
        gridPos = {h = 8; w = 12; x = 12; y = 13;};
        options = {showHeader = true;};
        targets = [
          {
            expr = "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100";
            format = "table";
            instant = true;
            refId = "A";
          }
        ];
        title = "Memory Usage by Node";
        type = "table";
        transformations = [
          {id = "organize"; options = {excludeByName = {"__name__" = true; "job" = true;}; indexByName = {}; renameByName = {};};}
        ];
      }

      # ========== ROW: ALERTS & ACTIVITY ==========
      (panels.row "🚨 Recent Alerts" true)
      # Recent Firing Alerts
      {
        datasource = lib.dashboard.prometheusDatasource;
        fieldConfig.defaults = {
          color.mode = "thresholds";
          thresholds.mode = "absolute";
          thresholds.steps = [
            {color = "red"; value = null;}
          ];
          unit = "short";
        };
        gridPos = {h = 8; w = 24; x = 0; y = 21;};
        options = {
          showHeader = true;
        };
        targets = [
          {
            expr = "ALERTS{alertstate=\"firing\"}";
            format = "table";
            instant = true;
            refId = "A";
          }
        ];
        title = "Firing Alerts";
        type = "table";
      }
    ];
  };
}
