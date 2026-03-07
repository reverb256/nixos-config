# Grafana Dashboard Server
# Visualization platform for Prometheus metrics
# Uses auto-generated admin password (no manual setup required)
{
  config,
  lib,
  pkgs,
  ...
}: let
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

  # Unified Cluster Dashboard
  # Combines cluster monitoring, mining, AI inference, and hardware metrics
  # Uses correct metric names from actual Prometheus exporters
  unifiedDashboard = builtins.toJSON {
    annotations.list = [];
    description = "Reverb-OS NixOS Cluster - Unified Monitoring Dashboard";
    editable = true;
    fiscalYearStartMonth = 0;
    graphTooltip = 1;
    id = null;
    links = [];
    liveNow = false;
    panels = [
      # ========== ROW: CLUSTER HEALTH ==========
      {
        collapsed = false;
        gridPos = { h = 1; w = 24; x = 0; y = 0; };
        id = 100;
        panels = [];
        title = "🖥️ Cluster Health";
        type = "row";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "thresholds";
          mappings = [];
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "red"; value = null; }
              { color = "green"; value = 1; }
            ];
          };
        };
        gridPos = { h = 4; w = 24; x = 0; y = 1; };
        id = 1;
        options = {
          colorMode = "background";
          graphMode = "none";
          reduceOptions = {
            calcs = ["lastNotNull"];
            fields = "";
            values = false;
          };
        };
        targets = [
          { expr = "up{job=\"node\"}"; legendFormat = "{{instance}} - Node"; refId = "A"; }
          { expr = "up{job=\"nvidia\"}"; legendFormat = "{{instance}} - NVIDIA"; refId = "B"; }
          { expr = "up{job=\"mining\"}"; legendFormat = "{{instance}} - Mining"; refId = "C"; }
          { expr = "ai_inference_backend_healthy"; legendFormat = "AI Gateway {{backend}}"; refId = "D"; }
        ];
        title = "Service Health";
        type = "stat";
      }

      # ========== ROW: CPU & MEMORY ==========
      {
        collapsed = false;
        gridPos = { h = 1; w = 24; x = 0; y = 5; };
        id = 200;
        panels = [];
        title = "💻 CPU & Memory";
        type = "row";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            gradientMode = "scheme";
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          max = 100;
          min = 0;
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "green"; value = null; }
              { color = "yellow"; value = 70; }
              { color = "red"; value = 90; }
            ];
          };
          unit = "percent";
        };
        gridPos = { h = 8; w = 12; x = 0; y = 6; };
        id = 2;
        options = {
          legend = { calcs = ["mean" "last" "max"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "100 * (1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) by (instance))"; legendFormat = "{{instance}}"; refId = "A"; }
        ];
        title = "CPU Usage";
        type = "timeseries";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            gradientMode = "scheme";
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          max = 100;
          min = 0;
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "green"; value = null; }
              { color = "yellow"; value = 70; }
              { color = "red"; value = 90; }
            ];
          };
          unit = "percent";
        };
        gridPos = { h = 8; w = 12; x = 12; y = 6; };
        id = 3;
        options = {
          legend = { calcs = ["mean" "last" "max"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))"; legendFormat = "{{instance}}"; refId = "A"; }
        ];
        title = "Memory Usage";
        type = "timeseries";
      }

      # ========== ROW: THERMAL & HARDWARE ==========
      {
        collapsed = false;
        gridPos = { h = 1; w = 24; x = 0; y = 14; };
        id = 300;
        panels = [];
        title = "🌡️ Thermal & Hardware";
        type = "row";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "continuous-GrYlRd";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            gradientMode = "scheme";
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "green"; value = null; }
              { color = "yellow"; value = 70; }
              { color = "red"; value = 85; }
            ];
          };
          unit = "celsius";
        };
        gridPos = { h = 8; w = 12; x = 0; y = 15; };
        id = 4;
        options = {
          legend = { calcs = ["mean" "last" "max"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "node_hwmon_temp_celsius{sensor=\"coretemp\"}"; legendFormat = "{{chip}} {{label}}"; refId = "A"; }
        ];
        title = "CPU Temperatures";
        type = "timeseries";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "continuous-GrYlRd";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            gradientMode = "scheme";
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "green"; value = null; }
              { color = "yellow"; value = 75; }
              { color = "red"; value = 85; }
            ];
          };
          unit = "celsius";
        };
        gridPos = { h = 8; w = 12; x = 12; y = 15; };
        id = 5;
        options = {
          legend = { calcs = ["mean" "last" "max"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "nvidia_smi_temperature_gpu"; legendFormat = "NVIDIA {{instance}} gpu{{index}}"; refId = "A"; }
          { expr = "amdgpu_temperature_celsius"; legendFormat = "AMD {{instance}} {{gpu}}"; refId = "B"; }
        ];
        title = "GPU Temperatures";
        type = "timeseries";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          max = 100;
          min = 0;
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "green"; value = null; }
              { color = "yellow"; value = 80; }
              { color = "red"; value = 95; }
            ];
          };
          unit = "percent";
        };
        gridPos = { h = 8; w = 12; x = 0; y = 23; };
        id = 6;
        options = {
          legend = { calcs = ["mean" "last" "max"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "100 * nvidia_smi_utilization_gpu_ratio"; legendFormat = "NVIDIA {{instance}} gpu{{index}}"; refId = "A"; }
          { expr = "amdgpu_utilization_percent"; legendFormat = "AMD {{instance}} {{gpu}}"; refId = "B"; }
        ];
        title = "GPU Utilization";
        type = "timeseries";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds.mode = "absolute";
          thresholds.steps = [{ color = "green"; value = null; }];
          unit = "watt";
        };
        gridPos = { h = 8; w = 12; x = 12; y = 23; };
        id = 7;
        options = {
          legend = { calcs = ["mean" "last" "max"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "nvidia_smi_power_draw_watts"; legendFormat = "NVIDIA {{instance}} gpu{{index}}"; refId = "A"; }
          { expr = "amdgpu_power_watts"; legendFormat = "AMD {{instance}} {{gpu}}"; refId = "B"; }
        ];
        title = "GPU Power Draw";
        type = "timeseries";
      }

      # ========== ROW: MINING ==========
      {
        collapsed = false;
        gridPos = { h = 1; w = 24; x = 0; y = 31; };
        id = 400;
        panels = [];
        title = "⛏️ Mining";
        type = "row";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds.mode = "absolute";
          thresholds.steps = [{ color = "green"; value = null; }];
          unit = "hashrate";
        };
        gridPos = { h = 8; w = 12; x = 0; y = 32; };
        id = 8;
        options = {
          legend = { calcs = ["mean" "last" "max"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "mining_lolminer_hashrate_total"; legendFormat = "LolMiner {{instance}}"; refId = "A"; }
          { expr = "mining_xmrig_hashrate_total"; legendFormat = "XMRig {{instance}}"; refId = "B"; }
        ];
        title = "Total Hashrate";
        type = "timeseries";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds.mode = "absolute";
          thresholds.steps = [{ color = "green"; value = null; }];
          unit = "short";
        };
        gridPos = { h = 8; w = 12; x = 12; y = 32; };
        id = 9;
        options = {
          legend = { calcs = ["sum"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "rate(mining_lolminer_shares_accepted[5m])"; legendFormat = "LolMiner Accepted {{instance}}"; refId = "A"; }
          { expr = "rate(mining_xmrig_shares_accepted[5m])"; legendFormat = "XMRig Accepted {{instance}}"; refId = "B"; }
          { expr = "rate(mining_lolminer_shares_rejected[5m])"; legendFormat = "LolMiner Rejected {{instance}}"; refId = "C"; }
          { expr = "rate(mining_xmrig_shares_rejected[5m])"; legendFormat = "XMRig Rejected {{instance}}"; refId = "D"; }
        ];
        title = "Share Rate";
        type = "timeseries";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds.mode = "absolute";
          thresholds.steps = [{ color = "green"; value = null; }];
          unit = "percent";
        };
        gridPos = { h = 8; w = 12; x = 0; y = 40; };
        id = 10;
        options = {
          legend = { calcs = ["mean" "last"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "mining_xmrig_cpu_percent"; legendFormat = "XMRig {{instance}}"; refId = "A"; }
        ];
        title = "XMRig CPU Usage";
        type = "timeseries";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds.mode = "absolute";
          thresholds.steps = [{ color = "green"; value = null; }];
          unit = "short";
        };
        gridPos = { h = 8; w = 12; x = 12; y = 40; };
        id = 11;
        options = {
          legend = { calcs = ["last"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "mining_xmrig_threads"; legendFormat = "Threads {{instance}}"; refId = "A"; }
        ];
        title = "XMRig Threads";
        type = "timeseries";
      }

      # ========== ROW: AI INFERENCE ==========
      {
        collapsed = false;
        gridPos = { h = 1; w = 24; x = 0; y = 48; };
        id = 500;
        panels = [];
        title = "🤖 AI Inference Gateway";
        type = "row";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds.mode = "absolute";
          thresholds.steps = [{ color = "green"; value = null; }];
          unit = "short";
        };
        gridPos = { h = 8; w = 8; x = 0; y = 49; };
        id = 12;
        options = {
          legend = { calcs = ["last"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "ai_inference_backend_healthy"; legendFormat = "{{backend}}"; refId = "A"; }
        ];
        title = "Backend Health";
        type = "timeseries";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "continuous-GrYlRd";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            gradientMode = "scheme";
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "green"; value = null; }
              { color = "yellow"; value = 70; }
              { color = "red"; value = 85; }
            ];
          };
          unit = "celsius";
        };
        gridPos = { h = 8; w = 8; x = 8; y = 49; };
        id = 13;
        options = {
          legend = { calcs = ["mean" "last" "max"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "ai_inference_gpu_temperature_c"; legendFormat = "{{backend}}"; refId = "A"; }
        ];
        title = "AI GPU Temperature";
        type = "timeseries";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          max = 100;
          min = 0;
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "green"; value = null; }
              { color = "yellow"; value = 80; }
              { color = "red"; value = 95; }
            ];
          };
          unit = "percent";
        };
        gridPos = { h = 8; w = 8; x = 16; y = 49; };
        id = 14;
        options = {
          legend = { calcs = ["mean" "last" "max"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "ai_inference_gpu_utilization_percent"; legendFormat = "{{backend}}"; refId = "A"; }
        ];
        title = "AI GPU Utilization";
        type = "timeseries";
      }

      # ========== ROW: STORAGE & NETWORK ==========
      {
        collapsed = false;
        gridPos = { h = 1; w = 24; x = 0; y = 57; };
        id = 600;
        panels = [];
        title = "💾 Storage & Network";
        type = "row";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds.mode = "absolute";
          thresholds.steps = [{ color = "green"; value = null; }];
          unit = "bytes";
        };
        gridPos = { h = 8; w = 12; x = 0; y = 58; };
        id = 15;
        options = {
          legend = { calcs = ["last"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "node_filesystem_avail_bytes{fstype!=\"tmpfs\"}"; legendFormat = "{{mountpoint}} - {{instance}}"; refId = "A"; }
        ];
        title = "Disk Space Available";
        type = "timeseries";
      }
      {
        datasource = { type = "prometheus"; uid = "prometheus"; };
        fieldConfig.defaults = {
          color.mode = "palette-classic";
          custom = {
            axisCenteredZero = false;
            axisColorMode = "text";
            drawStyle = "line";
            fillOpacity = 10;
            lineInterpolation = "smooth";
            lineWidth = 2;
            scaleDistribution.type = "linear";
            spanNulls = true;
          };
          thresholds.mode = "absolute";
          thresholds.steps = [{ color = "green"; value = null; }];
          unit = "Bps";
        };
        gridPos = { h = 8; w = 12; x = 12; y = 58; };
        id = 16;
        options = {
          legend = { calcs = ["mean" "last"]; displayMode = "table"; placement = "bottom"; };
          tooltip.mode = "multi";
        };
        targets = [
          { expr = "rate(node_network_receive_bytes_total[5m])"; legendFormat = "RX {{device}} {{instance}}"; refId = "A"; }
          { expr = "rate(node_network_transmit_bytes_total[5m])"; legendFormat = "TX {{device}} {{instance}}"; refId = "B"; }
        ];
        title = "Network Traffic";
        type = "timeseries";
      }
    ];
    refresh = "5s";
    schemaVersion = 38;
    tags = ["cluster" "mining" "ai" "unified"];
    templating.list = [];
    time = { from = "now-1h"; to = "now"; };
    timepicker = {};
    timezone = "";
    title = "Reverb-OS Cluster";
    uid = "reverb-os-unified";
    version = 1;
    weekStart = "";
  };

in {
  options.services.monitoring.grafana = {
    enable = lib.mkEnableOption "Grafana dashboard server";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "sentry.${cluster.tailscale.domain}";
      description = "Domain for Grafana access";
    };
    adminUser = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Grafana admin username";
    };
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = cluster.ports.grafana;
          root_url = "https://${cfg.domain}";
          serve_from_sub_path = false;
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

        "auth.anonymous".enabled = false;

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
    users.groups.grafana = {};

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

    # Provision unified dashboard
    systemd.services.grafana-dashboard-provision = {
      description = "Provision Grafana dashboards";
      wantedBy = ["multi-user.target"];
      before = ["grafana.service"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p ${dashboardsDir}
        cp ${pkgs.writeText "reverb-os-unified.json" unifiedDashboard} ${dashboardsDir}/reverb-os-unified.json
        chown grafana:grafana ${dashboardsDir}/reverb-os-unified.json
        chmod 644 ${dashboardsDir}/reverb-os-unified.json
      '';
    };

    # Open firewall
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [cluster.ports.grafana];
  };
}
