_: let
  # ── API Dashboard (Quill API Server) ────────────────────────────────
  apiDashboard = builtins.toJSON {
    annotations = {list = [];};
    editable = true;
    graphTooltip = 1;
    id = null;
    links = [];
    schemaVersion = 39;
    tags = ["quill" "api" "maplespike"];
    time = {from = "now-15m"; to = "now";};
    timepicker = {
      refresh_intervals = ["5s" "10s" "30s" "1m" "5m" "15m" "30m" "1h" "2h" "1d"];
      time_options = ["5m" "15m" "1h" "6h" "12h" "24h" "2d" "7d" "30d"];
    };
    title = "Quill API";
    uid = "quill-api";
    version = 1;
    panels = [
      {
        title = "Request Rate";
        type = "timeseries";
        gridPos = {h = 8; w = 8; x = 0; y = 0;};
        targets = [
          {
            expr = ''sum(rate(http_requests_total{service="quill-api"}[5m]))'';
            legendFormat = "req/s";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "reqps";
            color = {mode = "palette-classic";};
          };
        };
      }
      {
        title = "P50 Latency";
        type = "timeseries";
        gridPos = {h = 8; w = 8; x = 8; y = 0;};
        targets = [
          {
            expr = ''histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{service="quill-api"}[5m])) by (le))'';
            legendFormat = "P50";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "s";
            color = {mode = "palette-classic";};
          };
        };
      }
      {
        title = "P95 / P99 Latency";
        type = "timeseries";
        gridPos = {h = 8; w = 8; x = 16; y = 0;};
        targets = [
          {
            expr = ''histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service="quill-api"}[5m])) by (le))'';
            legendFormat = "P95";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
          {
            expr = ''histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service="quill-api"}[5m])) by (le))'';
            legendFormat = "P99";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "s";
            color = {mode = "palette-classic";};
          };
        };
      }
      {
        title = "Error Rate (5xx)";
        type = "timeseries";
        gridPos = {h = 8; w = 8; x = 0; y = 8;};
        targets = [
          {
            expr = ''sum(rate(http_requests_total{service="quill-api",status=~"5.."}[5m])) / sum(rate(http_requests_total{service="quill-api"}[5m])) * 100'';
            legendFormat = "5xx %";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "percent";
            color = {mode = "palette-classic";};
          };
        };
      }
      {
        title = "Top Endpoints (req/s)";
        type = "barchart";
        gridPos = {h = 8; w = 16; x = 8; y = 8;};
        targets = [
          {
            expr = ''topk(10, sum(rate(http_requests_total{service="quill-api"}[5m])) by (endpoint))'';
            legendFormat = "{{endpoint}}";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
      }
    ];
  };

  # ── MCP Dashboard (Quill MCP Server) ───────────────────────────────
  mcpDashboard = builtins.toJSON {
    annotations = {list = [];};
    editable = true;
    graphTooltip = 1;
    id = null;
    links = [];
    schemaVersion = 39;
    tags = ["quill" "mcp" "maplespike"];
    time = {from = "now-15m"; to = "now";};
    timepicker = {
      refresh_intervals = ["5s" "10s" "30s" "1m" "5m" "15m" "30m" "1h" "2h" "1d"];
      time_options = ["5m" "15m" "1h" "6h" "12h" "24h" "2d" "7d" "30d"];
    };
    title = "Quill MCP";
    uid = "quill-mcp";
    version = 1;
    panels = [
      {
        title = "Tool Call Rate";
        type = "timeseries";
        gridPos = {h = 8; w = 12; x = 0; y = 0;};
        targets = [
          {
            expr = ''sum(rate(mcp_tool_calls_total{service="quill-mcp"}[5m]))'';
            legendFormat = "calls/s";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "reqps";
            color = {mode = "palette-classic";};
          };
        };
      }
      {
        title = "Error Rate per Tool";
        type = "timeseries";
        gridPos = {h = 8; w = 12; x = 12; y = 0;};
        targets = [
          {
            expr = ''sum(rate(mcp_tool_errors_total{service="quill-mcp"}[5m])) by (tool)'';
            legendFormat = "{{tool}}";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "errps";
            color = {mode = "palette-classic";};
          };
        };
      }
      {
        title = "Tool Latency (P50/P95/P99)";
        type = "timeseries";
        gridPos = {h = 8; w = 24; x = 0; y = 8;};
        targets = [
          {
            expr = ''histogram_quantile(0.50, sum(rate(mcp_tool_duration_seconds_bucket{service="quill-mcp"}[5m])) by (le))'';
            legendFormat = "P50";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
          {
            expr = ''histogram_quantile(0.95, sum(rate(mcp_tool_duration_seconds_bucket{service="quill-mcp"}[5m])) by (le))'';
            legendFormat = "P95";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
          {
            expr = ''histogram_quantile(0.99, sum(rate(mcp_tool_duration_seconds_bucket{service="quill-mcp"}[5m])) by (le))'';
            legendFormat = "P99";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "s";
            color = {mode = "palette-classic";};
          };
        };
      }
    ];
  };

  # ── Ingestion Dashboard (Pipeline CronJobs) ────────────────────────
  ingestionDashboard = builtins.toJSON {
    annotations = {list = [];};
    editable = true;
    graphTooltip = 1;
    id = null;
    links = [];
    schemaVersion = 39;
    tags = ["quill" "ingestion" "maplespike"];
    time = {from = "now-6h"; to = "now";};
    timepicker = {
      refresh_intervals = ["5s" "10s" "30s" "1m" "5m" "15m" "30m" "1h" "2h" "1d"];
      time_options = ["5m" "15m" "1h" "6h" "12h" "24h" "2d" "7d" "30d"];
    };
    title = "Ingestion Pipeline";
    uid = "quill-ingestion";
    version = 1;
    panels = [
      {
        title = "CronJob Success Rate";
        type = "timeseries";
        gridPos = {h = 8; w = 12; x = 0; y = 0;};
        targets = [
          {
            expr = ''rate(kube_cronjob_status_success{namespace="maplespike"}[5m])'';
            legendFormat = "{{cronjob}}";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "reqps";
            color = {mode = "palette-classic";};
          };
        };
      }
      {
        title = "CronJob Failure Rate";
        type = "timeseries";
        gridPos = {h = 8; w = 12; x = 12; y = 0;};
        targets = [
          {
            expr = ''rate(kube_cronjob_status_failure{namespace="maplespike"}[5m])'';
            legendFormat = "{{cronjob}}";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "reqps";
            color = {mode = "palette-classic";};
          };
        };
      }
      {
        title = "Last Successful Run Age";
        type = "stat";
        gridPos = {h = 8; w = 12; x = 0; y = 8;};
        targets = [
          {
            expr = ''time() - max(kube_cronjob_status_last_success_time{namespace="maplespike"}) by (cronjob)'';
            legendFormat = "{{cronjob}}";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "s";
            color = {mode = "palette-classic";};
          };
        };
      }
      {
        title = "Job Active / Pending";
        type = "timeseries";
        gridPos = {h = 8; w = 12; x = 12; y = 8;};
        targets = [
          {
            expr = ''kube_cronjob_status_active{namespace="maplespike"}'';
            legendFormat = "{{cronjob}}";
            datasource = {type = "prometheus"; uid = "mimir";};
          }
        ];
        fieldConfig = {
          defaults = {
            color = {mode = "palette-classic";};
          };
        };
      }
    ];
  };
in {
  config.kubernetes.objects = {
    monitoring.ConfigMap.quill-api-dashboard = {
      metadata = {
        namespace = "monitoring";
        labels = {
          grafana_dashboard = "1";
        };
      };
      data."quill-api.json" = apiDashboard;
    };
    monitoring.ConfigMap.quill-mcp-dashboard = {
      metadata = {
        namespace = "monitoring";
        labels = {
          grafana_dashboard = "1";
        };
      };
      data."quill-mcp.json" = mcpDashboard;
    };
    monitoring.ConfigMap.quill-ingestion-dashboard = {
      metadata = {
        namespace = "monitoring";
        labels = {
          grafana_dashboard = "1";
        };
      };
      data."quill-ingestion.json" = ingestionDashboard;
    };
  };
}
