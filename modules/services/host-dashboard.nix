# Host Dashboard - Web interface for cluster host status
# Shows system info, services, and Prometheus metrics with auto-refresh
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.services.host-dashboard;
  hostname = config.networking.hostName or "localhost";

  # JavaScript for dashboard (external file to avoid Nix parsing issues)
  dashboardJS = pkgs.writeText "dashboard.js" ''
    // Host Dashboard JavaScript
    // Safe DOM manipulation to avoid XSS

    function setTextContent(id, text) {
      const el = document.getElementById(id);
      if (el) el.textContent = text;
    }

    function loadServices() {
      const services = /* SERVICES_PLACEHOLDER */;

      const servicesList = document.getElementById('services');
      if (servicesList && Object.keys(services).length > 0) {
        servicesList.innerHTML = "";
        for (const key in services) {
          const service = services[key];
          const li = document.createElement('li');
          li.className = 'service-item';

          const nameSpan = document.createElement('span');
          nameSpan.className = 'service-name';
          nameSpan.textContent = service.name;

          const statusSpan = document.createElement('span');
          statusSpan.className = 'service-status ' + (service.active ? 'active' : 'inactive');
          statusSpan.textContent = service.active ? '● Running' : '○ Stopped';

          li.appendChild(nameSpan);
          li.appendChild(statusSpan);
          servicesList.appendChild(li);
        }
      } else {
        if (servicesList) {
          servicesList.innerHTML = '<li class="service-item"><span class="service-name">No services configured</span></li>';
        }
      }
    }

    function updateUptime() {
      fetch('/api/uptime')
        .then(function(r) { return r.text(); })
        .then(function(text) { setTextContent('uptime', text); })
        .catch(function() { setTextContent('uptime', 'Unknown'); });
    }

    // Initialize
    document.addEventListener('DOMContentLoaded', function() {
      loadServices();
      updateUptime();
      setInterval(updateUptime, 30000);
    });
  '';

  # CSS for dark theme dashboard
  dashboardCSS = pkgs.writeText "dashboard.css" ''
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    :root {
      --bg-primary: #0d1117;
      --bg-secondary: #161b22;
      --bg-tertiary: #21262d;
      --text-primary: #f0f6fc;
      --text-secondary: #8b949e;
      --accent-primary: #58a6ff;
      --accent-secondary: #238636;
      --accent-danger: #f85149;
      --accent-warning: #d29922;
      --border-color: #30363d;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: var(--bg-primary);
      color: var(--text-primary);
      line-height: 1.6;
      min-height: 100vh;
    }

    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 20px;
    }

    header {
      background: var(--bg-secondary);
      border-bottom: 1px solid var(--border-color);
      padding: 20px 0;
      margin-bottom: 30px;
    }

    .header-content {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    h1 {
      font-size: 1.8rem;
      font-weight: 600;
    }

    .cluster-info {
      display: flex;
      gap: 20px;
      font-size: 0.9rem;
      color: var(--text-secondary);
    }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 12px;
      border-radius: 20px;
      font-size: 0.8rem;
      font-weight: 500;
    }

    .badge-role {
      background: rgba(88, 166, 255, 0.15);
      color: var(--accent-primary);
    }

    .badge-status {
      background: rgba(35, 134, 54, 0.15);
      color: var(--accent-secondary);
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 20px;
      margin-bottom: 30px;
    }

    .card {
      background: var(--bg-secondary);
      border: 1px solid var(--border-color);
      border-radius: 8px;
      padding: 20px;
    }

    .card-title {
      font-size: 1rem;
      font-weight: 600;
      margin-bottom: 15px;
      color: var(--text-secondary);
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .stat-grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 15px;
    }

    .stat-item {
      background: var(--bg-tertiary);
      padding: 12px;
      border-radius: 6px;
    }

    .stat-label {
      font-size: 0.75rem;
      color: var(--text-secondary);
      margin-bottom: 4px;
    }

    .stat-value {
      font-size: 1.2rem;
      font-weight: 600;
    }

    .service-list {
      list-style: none;
    }

    .service-item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 10px 0;
      border-bottom: 1px solid var(--border-color);
    }

    .service-item:last-child {
      border-bottom: none;
    }

    .service-name {
      font-weight: 500;
    }

    .service-status {
      font-size: 0.8rem;
    }

    .service-status.active {
      color: var(--accent-secondary);
    }

    .service-status.inactive {
      color: var(--accent-danger);
    }

    .link-list {
      list-style: none;
    }

    .link-item a {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 10px;
      color: var(--text-primary);
      text-decoration: none;
      border-radius: 6px;
      transition: background 0.2s;
    }

    .link-item a:hover {
      background: var(--bg-tertiary);
    }

    .loading {
      text-align: center;
      padding: 20px;
      color: var(--text-secondary);
    }

    .error {
      color: var(--accent-danger);
      padding: 10px;
      background: rgba(248, 81, 73, 0.1);
      border-radius: 6px;
    }

    .query-examples {
      font-family: "SF Mono", "Monaco", "Inconsolata", "Fira Mono", monospace;
      font-size: 0.85rem;
    }

    .query-examples code {
      display: block;
      padding: 8px;
      margin: 4px 0;
      background: var(--bg-tertiary);
      border-radius: 4px;
      color: var(--accent-primary);
    }

    footer {
      text-align: center;
      padding: 30px 0;
      color: var(--text-secondary);
      font-size: 0.85rem;
    }

    @media (max-width: 768px) {
      .grid {
        grid-template-columns: 1fr;
      }

      .stat-grid {
        grid-template-columns: 1fr;
      }
    }
  '';

  # Generate HTML dashboard
  dashboardHTML = pkgs.writeText "dashboard.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>${hostname} - Cluster Host Dashboard</title>
      <link rel="stylesheet" href="/style.css">
      <script src="/dashboard.js"></script>
      <meta http-equiv="refresh" content="30">
    </head>
    <body>
      <header>
        <div class="container">
          <div class="header-content">
            <h1>${hostname}</h1>
            <div class="cluster-info">
              <span class="badge badge-role">
                <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
                  <path d="M8 0a8 8 0 100 16A8 8 0 008 0zM4.5 7.5a.5.5 0 011 0-1h5.793L8.146 4.354a.5.5 0 11-.708-.708l2 2a.5.5 0 010 .708l-2 2a.5.5 0 01-.708-.708L10.293 7.5H4.5z"/>
                </svg>
                ${cfg.role}
              </span>
              <span class="badge badge-status">● Cluster Online</span>
            </div>
          </div>
        </div>
      </header>

      <main class="container">
        <div class="grid">
          <div class="card">
            <h2 class="card-title">
              <svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor">
                <path d="M8 15A7 7 0 118 1a7 7 0 011 14zm0 1A8 8 0 108 0a8 8 0 000 16z"/>
                <path d="M8 4a.5.5 0 01.5.5v3h3a.5.5 0 010 1H8a.5.5 0 01-.5-.5v-4A.5.5 0 018 4z"/>
              </svg>
              System Info
            </h2>
            <div class="stat-grid">
              <div class="stat-item">
                <div class="stat-label">Hostname</div>
                <div class="stat-value" id="hostname">${hostname}</div>
              </div>
              <div class="stat-item">
                <div class="stat-label">Uptime</div>
                <div class="stat-value" id="uptime">Loading...</div>
              </div>
              <div class="stat-item">
                <div class="stat-label">CPU Load</div>
                <div class="stat-value" id="cpu">Loading...</div>
              </div>
              <div class="stat-item">
                <div class="stat-label">Memory</div>
                <div class="stat-value" id="memory">Loading...</div>
              </div>
            </div>
          </div>

          <div class="card">
            <h2 class="card-title">
              <svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor">
                <path d="M1 11.5a.5.5 0 01.5-.5h11.793l-3.147-3.146a.5.5 0 01.708-.708l4 4a.5.5 0 010 .708l-4 4a.5.5 0 01-.708-.708L13.293 12H1.5a.5.5 0 01-.5-.5z"/>
                <path d="M8.5 4.5a.5.5 0 01.5-.5h11a.5.5 0 010 1H9a.5.5 0 01-.5-.5z"/>
              </svg>
              Featured Services
            </h2>
            <ul class="link-list">
              ${lib.concatMapStrings (s: ''
                <li class="link-item">
                  <a href="${s.url}">
                    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
                      <path d="M8.636 3.5a.5.5 0 00-.5-.5H1.5A1.5 1.5 0 000 4.5v7A1.5 1.5 0 001.5 13h6.636a.5.5 0 000-1H1.5a.5.5 0 01-.5-.5v-7a.5.5 0 01.5-.5h6.636a.5.5 0 00.5-.5z"/>
                      <path d="M14.5 3h-6a.5.5 0 00-.5.5v9a.5.5 0 00.5.5h6a.5.5 0 00.5-.5v-9a.5.5 0 00-.5-.5zm-6 1h6v9h-6V4z"/>
                    </svg>
                    ${s.name}
                  </a>
                </li>
              '') cfg.featuredServices}
            </ul>
          </div>
        </div>

        <div class="grid">
          <div class="card">
            <h2 class="card-title">
              <svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor">
                <path d="M8 16A8 8 0 108 0a8 8 0 000 16zm.93-9.412-1 4.705c-.07.34.029.533.304.533.194 0 .487-.07.686-.246l-.088.416c-.287.346-.92.598-1.465.598-.703 0-1.002-.422-.808-1.319l.738-3.468c.064-.293.006-.399-.287-.47l-.451-.081.082-.381 2.29-.287zM8 5.5a1 1 0 110-2 1 1 0 010 2z"/>
              </svg>
              Running Services
            </h2>
            <ul class="service-list" id="services">
              <li class="loading">Loading services...</li>
            </ul>
          </div>

          <div class="card">
            <h2 class="card-title">
              <svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor">
                <path d="M8 15A7 7 0 118 1a7 7 0 011 14zm0 1A8 8 0 108 0a8 8 0 000 16z"/>
                <path d="M4.285 12.433a.5.5 0 00.683-.183A3.498 3.498 0 008 10.5c1.295 0 2.426-.703 3.032-1.75a.5.5 0 00.5-.866A3.498 3.498 0 015.5 5.5c0-1.033-.497-1.96-1.284-2.534a.5.5 0 01-.183-.683A4.498 4.498 0 008 2.5c0 1.496-.735 2.816-1.867 3.655a.5.5 0 01-.683-.183A3.498 3.498 0 014.285 12.433z"/>
              </svg>
              Prometheus Queries
            </h2>
            <div class="query-examples">
              <code>node_load1{instance="${hostname}.*"}</code>
              <code>node_memory_MemAvailable_bytes{instance="${hostname}.*"}</code>
              <code>rate(node_cpu_seconds_total{instance="${hostname}.*"}[5m])</code>
              <code>node_filesystem_avail_bytes{instance="${hostname}.*"}</code>
            </div>
          </div>
        </div>
      </main>

      <footer>
        <p>Cluster Dashboard • Auto-refreshes every 30 seconds</p>
        <p>Powered by NixOS + Kubernetes + Prometheus</p>
      </footer>
    </body>
    </html>
  '';

  # Simple HTTP server for dashboard
  httpServer = pkgs.writeShellScriptBin "host-dashboard-server" ''
    PORT="$${1:-${toString cfg.port}}"
    DATA_DIR="$${2:-${cfg.dataDir}}"

    echo "Starting host dashboard on port $PORT"

    # Ensure data directory exists
    mkdir -p "$DATA_DIR"

    # Simple Python HTTP server with proper headers
    ${pkgs.python3}/bin/python3 -m http.server "$PORT" \
      --directory "$DATA_DIR" \
      --bind 127.0.0.1
  '';

  # Update script for fetching metrics
  updateScript = pkgs.writeShellScriptBin "host-dashboard-update" ''
    set -euo pipefail

    DATA_DIR="${cfg.dataDir}"
    PROMETHEUS_URL="${cfg.prometheusUrl}"

    # Fetch uptime
    uptime -p | sed 's/up //' > "$DATA_DIR/api/uptime"

    # Fetch basic metrics
    curl -s "$PROMETHEUS_URL/api/v1/query?query=node_load1{instance=\"${hostname}\"}" \
      | ${pkgs.jq}/bin/jq -r '.data.result[0].value[1]' \
      > "$DATA_DIR/api/load1" 2>/dev/null || echo "N/A" > "$DATA_DIR/api/load1"
  '';

in {
  options.services.host-dashboard = {
    enable = lib.mkEnableOption "Host Dashboard - web interface for cluster host status";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for the dashboard web server";
    };

    prometheusUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:9090";
      description = "Prometheus API URL for metrics";
    };

    role = lib.mkOption {
      type = lib.types.str;
      default = "worker";
      description = "Host role for display (e.g., 'control-plane', 'worker', 'storage')";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/host-dashboard";
      description = "Directory for dashboard data";
    };

    featuredServices = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Service name";
          };
          url = lib.mkOption {
            type = lib.types.str;
            description = "Service URL";
          };
        };
      });
      default = [];
      description = "Featured services to display with quick links";
    };

    services = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Service name";
          };
          active = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether the service is active";
          };
        };
      });
      default = [];
      description = "Services to display in the running services list";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall port for dashboard access";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create data directory structure
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/api 0755 root root -"
    ];

    # Copy dashboard files to data directory
    systemd.services.host-dashboard-setup = {
      description = "Setup host dashboard files";
      wantedBy = [ "multi-user.target" ];
      before = [ "host-dashboard.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "host-dashboard-setup" ''
          mkdir -p ${cfg.dataDir}/api
          cp ${dashboardHTML} ${cfg.dataDir}/index.html
          cp ${dashboardCSS} ${cfg.dataDir}/style.css

          # Generate JS file with services data embedded
          sed 's|/* SERVICES_PLACEHOLDER */|${lib.strings.toJSON cfg.services}|' \
            ${dashboardJS} > ${cfg.dataDir}/dashboard.js
        '';
      };
    };

    # Main dashboard service
    systemd.services.host-dashboard = {
      description = "Host Dashboard Web Server";
      after = [ "network.target" "host-dashboard-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${httpServer} ${toString cfg.port} ${cfg.dataDir}";
        Restart = "on-failure";
        RestartSec = "5s";
        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = cfg.dataDir;
        NoNewPrivileges = true;
      };
    };

    # Update timer for metrics refresh
    systemd.services.host-dashboard-update = {
      description = "Update dashboard metrics";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = updateScript;
      };
    };

    systemd.timers.host-dashboard-update = {
      description = "Timer for dashboard metrics update";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/5";  # Every 5 minutes
        Unit = "host-dashboard-update.service";
      };
    };

    # Firewall
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

    # Service gateway integration
    services.service-gateway = lib.mkIf config.services.service-gateway.enable {
      services.host-dashboard = {
        description = "Host Dashboard - Cluster Status";
        port = cfg.port;
      };
    };
  };
}
