{lib, ...}: let
  inherit (lib.dashboard) panels template;
in {
  deepInsights = template {
    title = "🔬 Deep Insights";
    description = "Resource analysis, anomaly detection, and capacity planning";
    tags = ["insights" "analysis" "capacity"];
    panels = [
      (panels.row "🧠 Memory Behavior Analysis" false)
      (panels.gauge {
        title = "Memory Pressure";
        expr = "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes - node_memory_Cached_bytes - node_memory_Buffers_bytes) / node_memory_MemTotal_bytes * 100";
        gridPos = {
          h = 8;
          w = 6;
          x = 0;
          y = 1;
        };
        thresholds = [
          {
            color = "green";
            value = null;
          }
          {
            color = "yellow";
            value = 50;
          }
          {
            color = "orange";
            value = 70;
          }
          {
            color = "red";
            value = 85;
          }
        ];
        unit = "percent";
      })
      (panels.timeseries {
        title = "Swap Activity (I/O Rate)";
        expr = "rate(node_memswap_in_bytes[5m]) + rate(node_memswap_out_bytes[5m])";
        gridPos = {
          h = 8;
          w = 12;
          x = 6;
          y = 1;
        };
        unit = "Bps";
        legendFormat = "{{instance}}";
      })
      (panels.timeseries {
        title = "Page Scan Rate (Memory Pressure)";
        expr = "rate(node_vmstat_pgfault[5m])";
        gridPos = {
          h = 8;
          w = 6;
          x = 18;
          y = 1;
        };
        legendFormat = "{{instance}}";
      })

      (panels.row "🔍 Memory Leak Detection" true)
      {
        datasource = lib.dashboard.prometheusDatasource;
        gridPos = {
          h = 10;
          w = 24;
          x = 0;
          y = 9;
        };
        options = {
          legend = {
            calcs = ["last" "max"];
            displayMode = "table";
            placement = "right";
          };
          tooltip.mode = "multi";
        };
        targets = [
          {
            expr = "topk(10, rate(process_resident_memory_bytes[1h]))";
            legendFormat = "{{comm}} ({{instance}})";
            refId = "A";
          }
        ];
        title = "Top 10 Process Memory Growth Rates";
        type = "timeseries";
      }

      (panels.row "💾 Disk I/O Patterns" true)
      (panels.timeseries {
        title = "Disk I/O Queue Depth";
        expr = "rate(node_disk_io_time_weighted_seconds[5m])";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 19;
        };
        legendFormat = "{{device}} ({{instance}})";
      })
      (panels.timeseries {
        title = "Disk Throughput";
        expr = "rate(node_disk_read_bytes_total[5m]) + rate(node_disk_written_bytes_total[5m])";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 19;
        };
        unit = "Bps";
        legendFormat = "{{device}} ({{instance}})";
      })
      (panels.timeseries {
        title = "IOPS (Read + Write)";
        expr = "rate(node_disk_reads_completed_total[5m]) + rate(node_disk_writes_completed_total[5m])";
        gridPos = {
          h = 8;
          w = 24;
          x = 0;
          y = 27;
        };
        legendFormat = "{{device}} ({{instance}})";
      })

      (panels.row "📈 Capacity Planning" true)
      {
        datasource = lib.dashboard.prometheusDatasource;
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 35;
        };
        options = {
          legend = {
            calcs = ["last" "mean"];
            displayMode = "table";
            placement = "bottom";
          };
          tooltip.mode = "multi";
        };
        targets = [
          {
            expr = "predict_linear(node_filesystem_size_bytes{mountpoint=\"/\"} - node_filesystem_avail_bytes{mountpoint=\"/\"}[7d], 7*24*3600)";
            legendFormat = "{{instance}} {{mountpoint}} (7d projection)";
            refId = "A";
          }
        ];
        title = "Disk Usage Projection (7 days)";
        type = "timeseries";
      }
      {
        datasource = lib.dashboard.prometheusDatasource;
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 35;
        };
        options = {
          legend = {
            calcs = ["last" "mean" "max"];
            displayMode = "table";
            placement = "bottom";
          };
          tooltip.mode = "multi";
        };
        targets = [
          {
            expr = "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100";
            legendFormat = "{{instance}}";
            refId = "A";
          }
        ];
        title = "Memory Usage Trend (24h)";
        type = "timeseries";
      }

      (panels.row "🌐 Network Analysis" true)
      (panels.timeseries {
        title = "Network Connections";
        expr = "node_netstat_Tcp_CurrEstab";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 43;
        };
        legendFormat = "{{instance}}";
      })
      (panels.timeseries {
        title = "Network Error Rate";
        expr = "rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m])";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 43;
        };
        legendFormat = "{{device}} ({{instance}})";
      })

      (panels.row "⚙️ System Behavior" true)
      (panels.timeseries {
        title = "Context Switch Rate";
        expr = "rate(node_context_switches_total[5m])";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 51;
        };
        legendFormat = "{{instance}}";
      })
      (panels.timeseries {
        title = "Process Fork Rate";
        expr = "rate(node_forks_total[5m])";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 51;
        };
        legendFormat = "{{instance}}";
      })
    ];
  };
}
