# Grafana Dashboard Server - Modular Version
# Uses declarative dashboard system from ./dashboards/
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.monitoring.grafana;
  cluster = config.networking.cluster;

  # Import dashboard library
  dashboardLib = import ./dashboards/lib.nix {inherit lib;};
  # Import dashboard registry
  dashboards = import ./dashboards/default.nix {inherit lib;};

  grafanaPasswordFile = "/var/lib/grafana/admin-password";
  dashboardsDir = "/var/lib/grafana/dashboards";

  # Extend lib with dashboard helpers
  libExt = lib.extend (self: super: {
    dashboard = dashboardLib;
  });

in {
  options.services.monitoring.grafana = {
    enable = lib.mkEnableOption "Grafana dashboard server";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "sentry.tigris-ule.ts.net";
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

    # Provision dashboards declaratively
    systemd.services.grafana-dashboard-provision = {
      description = "Provision Grafana dashboards";
      wantedBy = ["multi-user.target"];
      before = ["grafana.service"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = lib.concatLines (dashboards.provisionDashboards pkgs dashboardsDir);
    };

    # Open firewall
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [cluster.ports.grafana];
  };
}
