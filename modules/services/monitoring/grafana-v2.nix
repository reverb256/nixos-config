{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.monitoring.grafana;
  inherit (config.networking) cluster;

  dashboards = import ./dashboards/default.nix {inherit lib;};

  grafanaPasswordFile = "/var/lib/grafana/admin-password";
  dashboardsDir = "/var/lib/grafana/dashboards";
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
    systemd.tmpfiles.settings = {
      "grafana-password" = {
        "${grafanaPasswordFile}" = {
          f = {
            user = "grafana";
            group = "grafana";
            mode = "0400";
          };
        };
        "${grafanaPasswordFile}.secret" = {
          f = {
            user = "grafana";
            group = "grafana";
            mode = "0400";
          };
        };
      };
      "grafana-setup" = {
        "${dashboardsDir}" = {
          d = {
            user = "grafana";
            group = "grafana";
            mode = "0755";
          };
        };
      };
    };

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
          secret_key = "$__file{${grafanaPasswordFile}.secret}";
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
        datasources.settings.datasources = let
          prometheusDs = {
            name = "Prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:${toString cluster.ports.prometheus}";
            isDefault = true;
            access = "proxy";
            editable = false;
            uid = "prometheus";
          };
          lokiDs = lib.optional config.services.monitoring.loki.enable {
            name = "Loki";
            type = "loki";
            url = "http://127.0.0.1:3100";
            access = "proxy";
            editable = false;
            uid = "loki";
          };
        in
          [prometheusDs] ++ lokiDs;

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

    users = {
      users.grafana = {
        isSystemUser = true;
        group = "grafana";
      };
      groups.grafana = {};
    };

    systemd.services = {
      grafana-init-secrets = {
        description = "Generate Grafana admin password and secret key";
        wantedBy = ["multi-user.target"];
        before = ["grafana.service"];
        after = ["local-fs.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "grafana";
        };
        script = ''
          if [ ! -f "${grafanaPasswordFile}" ]; then
            tr -dc A-Za-z0-9 < /dev/urandom | head -c 32 > "${grafanaPasswordFile}"
            echo "Generated Grafana admin password in ${grafanaPasswordFile}"
          fi

          if [ ! -f "${grafanaPasswordFile}.secret" ]; then
            tr -dc A-Za-z0-9 < /dev/urandom | head -c 64 > "${grafanaPasswordFile}.secret"
            echo "Generated Grafana secret key in ${grafanaPasswordFile}.secret"
          fi

          chmod 0400 "${grafanaPasswordFile}" "${grafanaPasswordFile}.secret"
        '';
      };

      grafana-dashboard-provision = {
        description = "Provision Grafana dashboards";
        wantedBy = ["multi-user.target"];
        before = ["grafana.service"];
        after = ["grafana-init-secrets.service" "local-fs.target"];
        requires = ["grafana-init-secrets.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = lib.concatLines (dashboards.provisionDashboards pkgs dashboardsDir);
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [cluster.ports.grafana];
  };
}
