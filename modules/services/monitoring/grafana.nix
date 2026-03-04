# Grafana Dashboard Server
# Visualization platform for Prometheus metrics
# Uses auto-generated admin password (no manual setup required)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.monitoring.grafana;
  cluster = {
    ports = {
      prometheus = 9090;
      grafana = 3001;
    };
    tailscale.domain = "ts.krogh.dev";
  };
  grafanaPasswordFile = "/var/lib/grafana/admin-password";
  dashboardsDir = "/var/lib/grafana/dashboards";

  # Helper function to create a panel
  mkPanel =
    {
      type,
      title,
      expr,
      legendFormat ? "{{instance}}",
      unit ? "short",
      gridPos,
      ...
    }@args:
    {
      datasource = {
        type = "prometheus";
        uid = "prometheus";
      };
      fieldConfig = {
        defaults = {
          color = {
            mode = args.colorMode or "palette-classic";
          };
          unit = unit;
          min = args.min or null;
          max = args.max or null;
          thresholds =
            args.thresholds or {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
        };
      };
      gridPos = gridPos;
      id = args.id or 100;
      options =
        args.options or {
          legend = {
            calcs = [
              "mean"
              "max"
            ];
            displayMode = "table";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
      targets = [
        {
          inherit expr legendFormat;
          refId = "A";
        }
      ];
      title = title;
      type = type;
    }
    // (builtins.removeAttrs args [
      "type"
      "title"
      "expr"
      "legendFormat"
      "unit"
      "gridPos"
      "id"
      "options"
      "colorMode"
      "min"
      "max"
      "thresholds"
    ]);

  # Comprehensive cluster dashboard
  clusterDashboard = builtins.toJSON {
    annotations = {
      list = [ ];
    };
    description = "Reverb-OS NixOS Cluster - Complete Infrastructure Monitoring";
    editable = true;
    fiscalYearStartMonth = 0;
    graphTooltip = 1;
    id = null;
    links = [ ];
    liveNow = false;
    panels = [
      # ========== ROW: CLUSTER STATUS ==========
      {
        collapsed = false;
        gridPos = {
          h = 1;
          w = 24;
          x = 0;
          y = 0;
        };
        id = 1;
        panels = [ ];
        title = "📊 Cluster Status";
        type = "row";
      }
      # Online Hosts
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "thresholds";
            };
            mappings = [ ];
            thresholds = {
              steps = [
                {
                  color = "red";
                  value = null;
                }
                {
                  color = "yellow";
                  value = 1;
                }
                {
                  color = "green";
                  value = 3;
                }
              ];
            };
            unit = "none";
          };
        };
        gridPos = {
          h = 4;
          w = 4;
          x = 0;
          y = 1;
        };
        id = 100;
        options = {
          colorMode = "background";
          graphMode = "none";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
        };
        targets = [
          {
            expr = "count(up{job=\"node\"} == 1)";
            legendFormat = "Online";
            refId = "A";
          }
        ];
        title = "🖥️ Nodes Online";
        type = "stat";
      }
      # CPU Cores
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig.defaults = {
          color = {
            mode = "thresholds";
          };
          thresholds = {
            steps = [
              {
                color = "blue";
                value = null;
              }
            ];
          };
          unit = "none";
        };
        gridPos = {
          h = 4;
          w = 4;
          x = 4;
          y = 1;
        };
        id = 101;
        options = {
          colorMode = "background";
          graphMode = "none";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
        };
        targets = [
          {
            expr = "count(node_cpu_seconds_total{mode=\"idle\"}) by (host)";
            legendFormat = "{{host}}";
            refId = "A";
          }
        ];
        title = "⚡ CPU Cores";
        type = "stat";
      }
      # Total RAM
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig.defaults = {
          color = {
            mode = "thresholds";
          };
          thresholds = {
            steps = [
              {
                color = "purple";
                value = null;
              }
            ];
          };
          unit = "decbytes";
        };
        gridPos = {
          h = 4;
          w = 4;
          x = 8;
          y = 1;
        };
        id = 102;
        options = {
          colorMode = "background";
          graphMode = "none";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
        };
        targets = [
          {
            expr = "sum(node_memory_MemTotal_bytes)";
            legendFormat = "Total";
            refId = "A";
          }
        ];
        title = "🧠 Total RAM";
        type = "stat";
      }
      # Memory Used %
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "thresholds";
            };
            max = 100;
            min = 0;
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
                {
                  color = "yellow";
                  value = 70;
                }
                {
                  color = "red";
                  value = 90;
                }
              ];
            };
            unit = "percent";
          };
        };
        gridPos = {
          h = 4;
          w = 4;
          x = 12;
          y = 1;
        };
        id = 103;
        options = {
          colorMode = "background";
          graphMode = "area";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
        };
        targets = [
          {
            expr = "(1 - (sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))) * 100";
            legendFormat = "Used";
            refId = "A";
          }
        ];
        title = "💾 Cluster Memory";
        type = "stat";
      }
      # NVIDIA GPUs
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig.defaults = {
          color = {
            mode = "thresholds";
          };
          thresholds = {
            steps = [
              {
                color = "orange";
                value = null;
              }
            ];
          };
          unit = "none";
        };
        gridPos = {
          h = 4;
          w = 4;
          x = 16;
          y = 1;
        };
        id = 104;
        options = {
          colorMode = "background";
          graphMode = "none";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
        };
        targets = [
          {
            expr = "count(nvidia_smi_count) or vector(0)";
            legendFormat = "GPUs";
            refId = "A";
          }
        ];
        title = "🎮 NVIDIA GPUs";
        type = "stat";
      }
      # XMRig Hashrate
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig.defaults = {
          color = {
            mode = "thresholds";
          };
          thresholds = {
            steps = [
              {
                color = "green";
                value = null;
              }
            ];
          };
          unit = "H/s";
        };
        gridPos = {
          h = 4;
          w = 4;
          x = 20;
          y = 1;
        };
        id = 105;
        options = {
          colorMode = "value";
          graphMode = "area";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
        };
        targets = [
          {
            expr = "sum(mining_xmrig_hashrate_total) or vector(0)";
            legendFormat = "Total";
            refId = "A";
          }
        ];
        title = "⛏️ CPU Hashrate";
        type = "stat";
      }

      # ========== ROW: CPU MONITORING ==========
      {
        collapsed = false;
        gridPos = {
          h = 1;
          w = 24;
          x = 0;
          y = 5;
        };
        id = 2;
        panels = [ ];
        title = "🖥️ CPU Monitoring";
        type = "row";
      }
      # CPU Usage
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "line";
              fillOpacity = 10;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "smooth";
              lineWidth = 2;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = true;
              stacking = {
                group = "A";
                mode = "none";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            max = 100;
            min = 0;
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
            unit = "percent";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 6;
        };
        id = 10;
        options = {
          legend = {
            calcs = [
              "mean"
              "max"
            ];
            displayMode = "table";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)";
            legendFormat = "{{host}}";
            refId = "A";
          }
        ];
        title = "CPU Usage by Host";
        type = "timeseries";
      }
      # Load Average
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "line";
              fillOpacity = 10;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "smooth";
              lineWidth = 2;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = true;
              stacking = {
                group = "A";
                mode = "none";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
            unit = "short";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 6;
        };
        id = 11;
        options = {
          legend = {
            calcs = [
              "mean"
              "max"
            ];
            displayMode = "table";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "node_load1";
            legendFormat = "{{host}} 1m";
            refId = "A";
          }
          {
            expr = "node_load5";
            legendFormat = "{{host}} 5m";
            refId = "B";
          }
        ];
        title = "Load Average";
        type = "timeseries";
      }

      # ========== ROW: MEMORY MONITORING ==========
      {
        collapsed = false;
        gridPos = {
          h = 1;
          w = 24;
          x = 0;
          y = 14;
        };
        id = 3;
        panels = [ ];
        title = "💾 Memory Monitoring";
        type = "row";
      }
      # Memory Usage %
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "line";
              fillOpacity = 20;
              gradientMode = "opacity";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "smooth";
              lineWidth = 2;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = true;
              stacking = {
                group = "A";
                mode = "none";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            max = 100;
            min = 0;
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
            unit = "percent";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 15;
        };
        id = 20;
        options = {
          legend = {
            calcs = [
              "mean"
              "max"
            ];
            displayMode = "table";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100";
            legendFormat = "{{host}}";
            refId = "A";
          }
        ];
        title = "Memory Usage % by Host";
        type = "timeseries";
      }
      # Memory Bytes
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "line";
              fillOpacity = 10;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "smooth";
              lineWidth = 2;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = true;
              stacking = {
                group = "A";
                mode = "normal";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
            unit = "decbytes";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 15;
        };
        id = 21;
        options = {
          legend = {
            calcs = [ "mean" ];
            displayMode = "table";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes";
            legendFormat = "{{host}} Used";
            refId = "A";
          }
        ];
        title = "Memory Used by Host";
        type = "timeseries";
      }

      # ========== ROW: DISK & STORAGE ==========
      {
        collapsed = false;
        gridPos = {
          h = 1;
          w = 24;
          x = 0;
          y = 23;
        };
        id = 4;
        panels = [ ];
        title = "💿 Disk & Storage";
        type = "row";
      }
      # Disk Usage Bar Gauge
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "thresholds";
            };
            custom = {
              fillOpacity = 80;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              lineWidth = 1;
            };
            max = 100;
            min = 0;
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
                {
                  color = "yellow";
                  value = 70;
                }
                {
                  color = "red";
                  value = 90;
                }
              ];
            };
            unit = "percent";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 24;
        };
        id = 30;
        options = {
          barRadius = 0.1;
          barWidth = 0.6;
          fullHighlight = false;
          groupWidth = 0.7;
          legend = {
            calcs = [ ];
            displayMode = "list";
            placement = "bottom";
            showLegend = true;
          };
          orientation = "horizontal";
          showValue = "always";
          stacking = "none";
          text = {
            titleSize = 12;
            valueSize = 14;
          };
          tooltip = {
            mode = "single";
          };
        };
        targets = [
          {
            expr = "(1 - (node_filesystem_avail_bytes{mountpoint=\"/\",fstype!=\"tmpfs\"} / node_filesystem_size_bytes{mountpoint=\"/\",fstype!=\"tmpfs\"})) * 100";
            legendFormat = "{{host}}";
            refId = "A";
          }
        ];
        title = "Disk Usage % by Host";
        type = "bargauge";
      }
      # Disk I/O
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "line";
              fillOpacity = 10;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "smooth";
              lineWidth = 2;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = true;
              stacking = {
                group = "A";
                mode = "none";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
            unit = "Bps";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 24;
        };
        id = 31;
        options = {
          legend = {
            calcs = [ "mean" ];
            displayMode = "list";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "sum by(instance) (rate(node_disk_read_bytes_total[5m]))";
            legendFormat = "{{instance}} read";
            refId = "A";
          }
          {
            expr = "sum by(instance) (rate(node_disk_written_bytes_total[5m]))";
            legendFormat = "{{instance}} write";
            refId = "B";
          }
        ];
        title = "Disk I/O by Host";
        type = "timeseries";
      }

      # ========== ROW: NETWORK ==========
      {
        collapsed = false;
        gridPos = {
          h = 1;
          w = 24;
          x = 0;
          y = 32;
        };
        id = 5;
        panels = [ ];
        title = "🌐 Network";
        type = "row";
      }
      # Network Traffic
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "line";
              fillOpacity = 10;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "smooth";
              lineWidth = 2;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = true;
              stacking = {
                group = "A";
                mode = "none";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
            unit = "Bps";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 33;
        };
        id = 40;
        options = {
          legend = {
            calcs = [ "mean" ];
            displayMode = "table";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "sum by(instance) (rate(node_network_receive_bytes_total{interface!~\"lo|tailscale0|docker.*|veth.*|br-.*\"}[5m]))";
            legendFormat = "{{instance}} RX";
            refId = "A";
          }
          {
            expr = "sum by(instance) (rate(node_network_transmit_bytes_total{interface!~\"lo|tailscale0|docker.*|veth.*|br-.*\"}[5m]))";
            legendFormat = "{{instance}} TX";
            refId = "B";
          }
        ];
        title = "Network Traffic by Host";
        type = "timeseries";
      }
      # Network Errors
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "bars";
              fillOpacity = 80;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "linear";
              lineWidth = 1;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = false;
              stacking = {
                group = "A";
                mode = "none";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
                {
                  color = "red";
                  value = 1;
                }
              ];
            };
            unit = "short";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 33;
        };
        id = 41;
        options = {
          legend = {
            calcs = [ "sum" ];
            displayMode = "list";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "sum by(instance) (rate(node_network_receive_errs_total[5m]))";
            legendFormat = "{{instance}} RX err";
            refId = "A";
          }
          {
            expr = "sum by(instance) (rate(node_network_transmit_errs_total[5m]))";
            legendFormat = "{{instance}} TX err";
            refId = "B";
          }
        ];
        title = "Network Errors";
        type = "timeseries";
      }

      # ========== ROW: GPU MONITORING ==========
      {
        collapsed = false;
        gridPos = {
          h = 1;
          w = 24;
          x = 0;
          y = 41;
        };
        id = 6;
        panels = [ ];
        title = "🎮 NVIDIA GPU Monitoring";
        type = "row";
      }
      # GPU Utilization
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "line";
              fillOpacity = 10;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "smooth";
              lineWidth = 2;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = true;
              stacking = {
                group = "A";
                mode = "none";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            max = 100;
            min = 0;
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
            unit = "percent";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 42;
        };
        id = 50;
        options = {
          legend = {
            calcs = [
              "mean"
              "max"
            ];
            displayMode = "table";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "nvidia_smi_utilization_gpu_ratio * 100";
            legendFormat = "{{instance}}";
            refId = "A";
          }
        ];
        title = "GPU Utilization %";
        type = "timeseries";
      }
      # GPU Memory
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "line";
              fillOpacity = 10;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "smooth";
              lineWidth = 2;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = true;
              stacking = {
                group = "A";
                mode = "none";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            max = 100;
            min = 0;
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
            unit = "percent";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 42;
        };
        id = 51;
        options = {
          legend = {
            calcs = [
              "mean"
              "max"
            ];
            displayMode = "table";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "nvidia_smi_utilization_memory_ratio * 100";
            legendFormat = "{{instance}}";
            refId = "A";
          }
        ];
        title = "GPU Memory Utilization %";
        type = "timeseries";
      }
      # GPU Temperature
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "thresholds";
            };
            mappings = [ ];
            max = 100;
            min = 0;
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
                {
                  color = "yellow";
                  value = 70;
                }
                {
                  color = "red";
                  value = 85;
                }
              ];
            };
            unit = "celsius";
          };
        };
        gridPos = {
          h = 6;
          w = 12;
          x = 0;
          y = 50;
        };
        id = 52;
        options = {
          colorMode = "value";
          graphMode = "area";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
          displayMode = "gradient";
        };
        targets = [
          {
            expr = "nvidia_smi_temperature_gpu";
            legendFormat = "{{instance}}";
            refId = "A";
          }
        ];
        title = "GPU Temperature";
        type = "stat";
      }
      # GPU Power
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "thresholds";
            };
            thresholds = {
              steps = [
                {
                  color = "blue";
                  value = null;
                }
                {
                  color = "yellow";
                  value = 150;
                }
                {
                  color = "orange";
                  value = 250;
                }
              ];
            };
            unit = "watt";
          };
        };
        gridPos = {
          h = 6;
          w = 12;
          x = 12;
          y = 50;
        };
        id = 53;
        options = {
          colorMode = "value";
          graphMode = "area";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
          displayMode = "gradient";
        };
        targets = [
          {
            expr = "nvidia_smi_power_draw_watts";
            legendFormat = "{{instance}}";
            refId = "A";
          }
        ];
        title = "GPU Power Draw (W)";
        type = "stat";
      }

      # ========== ROW: MINING ==========
      {
        collapsed = false;
        gridPos = {
          h = 1;
          w = 24;
          x = 0;
          y = 56;
        };
        id = 7;
        panels = [ ];
        title = "⛏️ Mining Status";
        type = "row";
      }
      # XMRig Hashrate
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "line";
              fillOpacity = 10;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "smooth";
              lineWidth = 2;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = true;
              stacking = {
                group = "A";
                mode = "none";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
            unit = "H/s";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 57;
        };
        id = 60;
        options = {
          legend = {
            calcs = [
              "mean"
              "max"
            ];
            displayMode = "table";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "mining_xmrig_hashrate_total";
            legendFormat = "{{host}}";
            refId = "A";
          }
        ];
        title = "XMRig CPU Hashrate";
        type = "timeseries";
      }
      # XMRig CPU %
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig = {
          defaults = {
            color = {
              mode = "palette-classic";
            };
            custom = {
              axisBorderShow = false;
              axisCenteredZero = false;
              axisColorMode = "text";
              axisPlacement = "auto";
              barAlignment = 0;
              drawStyle = "line";
              fillOpacity = 10;
              gradientMode = "none";
              hideFrom = {
                legend = false;
                tooltip = false;
                viz = false;
              };
              insertNulls = false;
              lineInterpolation = "smooth";
              lineWidth = 2;
              pointSize = 5;
              scaleDistribution = {
                type = "linear";
              };
              showPoints = "never";
              spanNulls = true;
              stacking = {
                group = "A";
                mode = "none";
              };
              thresholdsStyle = {
                mode = "off";
              };
            };
            max = 100;
            min = 0;
            thresholds = {
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
            unit = "percent";
          };
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 57;
        };
        id = 61;
        options = {
          legend = {
            calcs = [
              "mean"
              "max"
            ];
            displayMode = "table";
            placement = "bottom";
            showLegend = true;
          };
          tooltip = {
            mode = "multi";
            sort = "desc";
          };
        };
        targets = [
          {
            expr = "mining_xmrig_cpu_percent";
            legendFormat = "{{host}}";
            refId = "A";
          }
        ];
        title = "XMRig CPU Usage %";
        type = "timeseries";
      }
      # Mining Shares Accepted
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig.defaults = {
          color = {
            mode = "thresholds";
          };
          thresholds = {
            steps = [
              {
                color = "green";
                value = null;
              }
            ];
          };
          unit = "short";
        };
        gridPos = {
          h = 4;
          w = 8;
          x = 0;
          y = 65;
        };
        id = 62;
        options = {
          colorMode = "value";
          graphMode = "area";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
        };
        targets = [
          {
            expr = "mining_xmrig_shares_accepted";
            legendFormat = "{{host}}";
            refId = "A";
          }
        ];
        title = "XMRig Shares Accepted";
        type = "stat";
      }
      # Mining Shares Rejected
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig.defaults = {
          color = {
            mode = "thresholds";
          };
          thresholds = {
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "red";
                value = 1;
              }
            ];
          };
          unit = "short";
        };
        gridPos = {
          h = 4;
          w = 8;
          x = 8;
          y = 65;
        };
        id = 63;
        options = {
          colorMode = "value";
          graphMode = "area";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
        };
        targets = [
          {
            expr = "mining_xmrig_shares_rejected";
            legendFormat = "{{host}}";
            refId = "A";
          }
        ];
        title = "XMRig Shares Rejected";
        type = "stat";
      }
      # Mining Uptime
      {
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig.defaults = {
          color = {
            mode = "thresholds";
          };
          thresholds = {
            steps = [
              {
                color = "green";
                value = null;
              }
            ];
          };
          unit = "s";
        };
        gridPos = {
          h = 4;
          w = 8;
          x = 16;
          y = 65;
        };
        id = 64;
        options = {
          colorMode = "value";
          graphMode = "none";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
        };
        targets = [
          {
            expr = "mining_xmrig_uptime_seconds";
            legendFormat = "{{host}}";
            refId = "A";
          }
        ];
        title = "XMRig Uptime";
        type = "stat";
      }
    ];
    refresh = "30s";
    schemaVersion = 39;
    style = "dark";
    tags = [
      "cluster"
      "nixos"
      "reverb-os"
    ];
    templating = {
      list = [ ];
    };
    time = {
      from = "now-1h";
      to = "now";
    };
    timepicker = { };
    timezone = "";
    title = "Reverb-OS Cluster Overview";
    uid = "reverb-os-cluster";
    version = 1;
    weekStart = "";
  };
in
{
  options.services.monitoring.grafana = {
    enable = lib.mkEnableOption "Grafana dashboard server";

    adminUser = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Grafana admin username";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "grafana.${cluster.tailscale.domain}";
      description = "Domain for Grafana (used in nginx proxy)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable auto-secrets for password generation
    services.auto-secrets = {
      enable = true;
      secrets.grafana-admin-password = {
        owner = "grafana";
        group = "grafana";
        mode = "0400";
        length = 64;
      };
    };

    # Ensure grafana starts after password is generated
    systemd.services.grafana.after = [ "auto-secret-grafana-admin-password.service" ];
    systemd.services.grafana.requires = [ "auto-secret-grafana-admin-password.service" ];

    # Bind mount secret into grafana's directory (avoids /var/lib/secrets traversal issues)
    systemd.services.grafana.serviceConfig.BindPaths = [
      "/var/lib/secrets/grafana-admin-password:/var/lib/grafana/admin-password"
    ];

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = cluster.ports.grafana;
          domain = cfg.domain;
          root_url = "https://%(domain)s/";
        };

        security = {
          admin_user = cfg.adminUser;
          admin_password = "$__file{${grafanaPasswordFile}}";
          disable_initial_admin_creation = false;
          secret_key = "$__file{${grafanaPasswordFile}}";
        };

        database = {
          type = "sqlite3";
          path = "/var/lib/grafana/data/grafana.db";
        };

        users = {
          allow_sign_up = false;
          auto_assign_org = true;
          auto_assign_org_role = "Viewer";
        };

        auth = {
          disable_login_form = false;
          disable_signout_menu = false;
        };

        "auth.anonymous" = {
          enabled = false;
        };

        log = {
          mode = "console";
          level = "info";
        };
      };

      provision = {
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:${toString cluster.ports.prometheus}";
            isDefault = true;
            access = "proxy";
            editable = false;
            uid = "prometheus";
          }
        ];

        dashboards.settings.providers = [
          {
            name = "default";
            orgId = 1;
            folder = "";
            type = "file";
            disableDeletion = false;
            updateIntervalSeconds = 30;
            options.path = dashboardsDir;
          }
        ];
      };
    };

    users.users.grafana = {
      isSystemUser = true;
      group = "grafana";
    };
    users.groups.grafana = { };

    # Create dashboards directory
    systemd.tmpfiles.settings."grafana-setup" = {
      "${dashboardsDir}" = {
        d = {
          user = "grafana";
          group = "grafana";
          mode = "0755";
        };
      };
    };

    # Provision dashboard
    systemd.services.grafana-dashboard-provision = {
      description = "Provision Grafana dashboards";
      wantedBy = [ "multi-user.target" ];
      before = [ "grafana.service" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p ${dashboardsDir}
        cp ${pkgs.writeText "cluster-overview.json" clusterDashboard} ${dashboardsDir}/cluster-overview.json
        chown grafana:grafana ${dashboardsDir}/cluster-overview.json
        chmod 644 ${dashboardsDir}/cluster-overview.json
      '';
    };

    # Open firewall
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cluster.ports.grafana ];
  };
}
