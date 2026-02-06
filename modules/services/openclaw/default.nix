{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.openclaw;
  openclawPkg = pkgs.openclaw-gateway or pkgs.openclaw;

  # Define the lobster user (standard across OpenClaw services)
  lobsterUser = "lobster";
  lobsterGroup = "lobster";
in {
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw Gateway Service";

    package = lib.mkOption {
      type = lib.types.package;
      default = openclawPkg;
      defaultText = "pkgs.openclaw-gateway or pkgs.openclaw";
      description = "OpenClaw package to use for the service";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 18788;
      description = "Port for OpenClaw Gateway service";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host for OpenClaw Gateway service (127.0.0.1 for secure loopback-only)";
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the OpenClaw gateway token file (should be an agenix secret)";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to automatically start the OpenClaw service on boot";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Environment file with API keys and other configuration";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--dev"];
      description = "Extra arguments to pass to the OpenClaw service";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create necessary directories
    systemd.tmpfiles.rules = [
      "d /var/lib/lobster/openclaw 0750 ${lobsterUser} ${lobsterGroup} -"
      "d /var/lib/openclaw 0750 ${lobsterUser} ${lobsterGroup} -"
    ];

    # OpenClaw Gateway Service
    systemd.services.openclaw = {
      description = "OpenClaw Gateway Service";
      after = ["network.target" "network-online.target"];
      wants = ["network-online.target"];
      
      wantedBy = if cfg.autoStart then ["multi-user.target"] else [];

      preStart = ''
        # Ensure the workspace directory exists with proper permissions
        mkdir -p /var/lib/lobster/openclaw
        chown ${lobsterUser}:${lobsterGroup} /var/lib/lobster/openclaw
      '';

      serviceConfig = {
        Type = "exec";
        User = lobsterUser;
        Group = lobsterGroup;
        Restart = "always";
        RestartSec = "5s";
        TimeoutStartSec = "300";
        WorkingDirectory = "/var/lib/lobster/openclaw";

        # Environment variables
        Environment = [
          "OPENCLAW_STATE_DIR=/var/lib/lobster/openclaw"
          "OPENCLAW_CONFIG_PATH=/var/lib/lobster/openclaw/openclaw.json"
          "PORT=${toString cfg.port}"
          "HOST=${cfg.host}"
        ];

        # Load secrets if provided
        EnvironmentFile = lib.mkIf (cfg.tokenFile != null || cfg.environmentFile != null) (
          (lib.optionals (cfg.tokenFile != null) cfg.tokenFile)
          ++ (lib.optionals (cfg.environmentFile != null) cfg.environmentFile)
        );

        # Construct the command
        ExecStart = lib.concatStringsSep " " (
          [ "${cfg.package}/bin/openclaw" "gateway" "--port" (toString cfg.port) "--bind" cfg.host ]
          ++ cfg.extraArgs
        );

        # Full system access - no security restrictions
        # NoNewPrivileges = false;
        # PrivateTmp = false;
        # ProtectSystem = false;
        # ProtectHome = false;
        # ReadOnlyPaths = [];
        # Removed all network restrictions for full system access

        # Allow full filesystem access
        ProtectSystem = "off";
        ReadOnlyPaths = [];

        # Allow access to /run for socket communication
        RuntimeDirectory = "openclaw";
        StateDirectory = "openclaw";
      };
    };

    # Health check service
    systemd.services.openclaw-health = {
      description = "OpenClaw Gateway Health Check";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = pkgs.writeShellScript "openclaw-health-check" ''
          # Check if OpenClaw is responding
          if ! timeout 10s curl -sf "http://${cfg.host}:${toString cfg.port}/health" >/dev/null 2>&1; then
            echo "OpenClaw Gateway health check failed, attempting restart"
            systemctl restart openclaw.service || true
            exit 1
          fi
          exit 0
        '';
      };
    };

    # Health check timer
    systemd.timers.openclaw-health = {
      description = "Periodic health check for OpenClaw Gateway";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*:*:0/60"; # Every minute
        Persistent = true;
      };
    };

    # Firewall configuration
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.host == "0.0.0.0") [cfg.port];
    networking.firewall.interfaces.lo.allowedTCPPorts = [cfg.port]; # Always allow localhost
  };
}