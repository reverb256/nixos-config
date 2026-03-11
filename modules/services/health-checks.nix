# Service Health Check Module
# Provides health check endpoints for critical services
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.health-checks;
in {
  options.services.health-checks = {
    enable = lib.mkEnableOption "Service health check monitoring";

    services = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Service name for health check";
          };

          port = lib.mkOption {
            type = lib.types.port;
            description = "Port to check";
          };

          path = lib.mkOption {
            type = lib.types.str;
            default = "/health";
            description = "Health check path";
          };

          interval = lib.mkOption {
            type = lib.types.int;
            default = 30;
            description = "Check interval in seconds";
          };

          timeout = lib.mkOption {
            type = lib.types.int;
            default = 5;
            description = "Timeout in seconds";
          };

          description = lib.mkOption {
            type = lib.types.str;
            example = "AI Inference Gateway health check";
            description = "Description of this health check";
          };
        };
      });
      default = [];
      description = "List of services to health check";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create a simple health check service
    systemd.services.health-checker = {
      description = "Service Health Checker";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "health-check-initial" ''
          # Run initial health checks
          ${pkgs.curl}/bin/curl -f -s http://127.0.0.1:8080/health || echo "AI Gateway: DOWN"
        '';

        # Create monitoring script for ongoing checks
        ExecStartPost = pkgs.writeShellScript "health-check-setup" ''
          # Setup health check scripts
          mkdir -p /var/lib/health-checks
        '';
      };

      # Timer for periodic health checks
      timers.health-checker = {
        description = "Periodic Service Health Checks";
        partOf = ["health-checker.service"];
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "*:*:0/5";  # Every 5 minutes
          Unit = "health-checker.service";
        };
      };
    };

    # Export health check metrics for Prometheus
    services.prometheus.exporters.textfile = {
      enable = true;
      directories = [
        "/var/lib/node_exporter/textfile_collector/health_checks"
      ];
    };

    # Health check script for AI Gateway
    environment.etc."health-checks/ai-gateway.sh".text = ''
      #!/bin/sh
      # Health check for AI Inference Gateway
      GATEWAY_URL="http://127.0.0.1:8080/health"
      TIMEOUT=5

      if ${pkgs.curl}/bin/curl -f -s --max-time "$TIMEOUT" "$GATEWAY_URL" >/dev/null 2>&1; then
        echo "ai_gateway_health 1"
        exit 0
      else
        echo "ai_gateway_health 0"
        exit 1
      fi
    '';

    # Health check script for Mining Proxy
    environment.etc."health-checks/mining-proxy.sh".text = ''
      #!/bin/sh
      # Health check for Mining Proxy
      PROXY_URL="http://127.0.0.1:3334/api/health"
      TIMEOUT=5

      if ${pkgs.curl}/bin/curl -f -s --max-time "$TIMEOUT" "$PROXY_URL" >/dev/null 2>&1; then
        echo "mining_proxy_health 1"
        exit 0
      else
        echo "mining_proxy_health 0"
        exit 1
      fi
    '';
  };
}
