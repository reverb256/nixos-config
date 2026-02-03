# OpenClaw Declarative Container Module
# Implements OpenClaw service using NixOS's built-in declarative container management
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.openclaw.declarative;
  inherit (lib) mkOption mkIf mkEnableOption types;
in {
  options.services.openclaw.declarative = {
    enable = mkEnableOption "OpenClaw AI Agent Gateway (Declarative Container)";

    package = mkOption {
      type = types.package;
      default = pkgs.openclaw or config.services.openclaw.package;
      defaultText = "pkgs.openclaw";
      description = "OpenClaw package to use in the container";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/openclaw/openclaw:latest";
      description = "OpenClaw container image to run";
    };

    port = mkOption {
      type = types.port;
      default = 18789;
      description = "Port for OpenClaw gateway";
    };

    apiPort = mkOption {
      type = types.port;
      default = 18790;
      description = "Port for OpenClaw API";
    };

    user = mkOption {
      type = types.str;
      default = "lobster";
      description = "User to run OpenClaw container as";
    };

    group = mkOption {
      type = types.str;
      default = "lobster";
      description = "Group to run OpenClaw container as";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw";
      description = "Directory for OpenClaw state data";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/data";
      description = "Directory for OpenClaw data";
    };

    configDir = mkOption {
      type = types.str;
      default = "/etc/openclaw";
      description = "Directory for OpenClaw configuration";
    };

    memory = mkOption {
      type = types.str;
      default = "2G";
      description = "Memory limit for the container";
      example = "4G";
    };

    cpuShares = mkOption {
      type = types.int;
      default = 512;
      description = "CPU shares for the container";
      example = 1024;
    };

    gatewayMode = mkOption {
      type = types.str;
      default = "local";
      description = "OpenClaw gateway mode";
    };

    gatewayBind = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "OpenClaw gateway bind address";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Environment file for container secrets";
      example = "/run/agenix/openclaw-env";
    };

    enableLegacyEnv = mkOption {
      type = types.bool;
      default = false;
      description = "Enable legacy MOLTBOT_* and CLAWDBOT_* environment variables for backwards compatibility";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users = mkIf (cfg.user == "lobster") {
      lobster = {
        isSystemUser = true;
        group = cfg.group;
        description = "OpenClaw AI agent bot user (lobster)";
        home = cfg.stateDir;
        createHome = true;
        uid = 982;
      };
    };

    users.groups = mkIf (cfg.group == "lobster") {
      lobster = { gid = 979; };
    };

    # Create directories with proper permissions  
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.configDir} 0750 root ${cfg.group} - -"
      "d ${cfg.stateDir}/workspace 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.stateDir}/workspace/skills 0750 ${cfg.user} ${cfg.group} - -"
    ];


    # Enable container runtime (Docker by default, can be overridden)
    # Note: This should be enabled globally in your host configuration, not in this module
    # This module assumes either Docker or Podman is already available

    # Systemd service to manage the container
    systemd.services.openclaw-container-declarative = {
      description = "OpenClaw AI Agent Gateway (Declarative Container)";
      after = ["network.target" "docker.service"];
      requires = ["docker.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "exec";
        Restart = "always";
        RestartSec = "5s";
        TimeoutStartSec = "5m";
        TimeoutStopSec = "30s";
        RemainAfterExit = true;

        ExecStart = let
          # Build legacy environment variables if enabled
          legacyEnvVars = lib.optionalString cfg.enableLegacyEnv ''
            -e "MOLTBOT_NIX_MODE=1" \
            -e "MOLTBOT_STATE_DIR=${cfg.stateDir}" \
            -e "CLAWDBOT_NIX_MODE=1" \
            -e "CLAWDBOT_STATE_DIR=${cfg.stateDir}" \
          '';

          containerStartScript = pkgs.writeShellScript "openclaw-container-start" ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Start the OpenClaw container with all the right parameters
            # Stop and remove any existing container with the same name
            ${pkgs.docker}/bin/docker stop openclaw-declarative 2>/dev/null || true
            ${pkgs.docker}/bin/docker rm openclaw-declarative 2>/dev/null || true

            # Start the OpenClaw container with all the right parameters
            exec ${pkgs.docker}/bin/docker run \
              --name openclaw-declarative \
              --network host \
              --restart unless-stopped \
              -v "${cfg.stateDir}:/var/lib/openclaw" \
              -v "${cfg.dataDir}:/var/lib/openclaw/data" \
              -v "${cfg.configDir}:/etc/openclaw" \
              -e "OPENCLAW_MODE=${cfg.gatewayMode}" \
              -e "OPENCLAW_BIND=${cfg.gatewayBind}" \
              -e "OPENCLAW_PORT=${toString cfg.port}" \
              -e "OPENCLAW_API_PORT=${toString cfg.apiPort}" \
              -e "OPENCLAW_STATE_DIR=${cfg.stateDir}" \
              -e "OPENCLAW_DATA_DIR=${cfg.dataDir}" \
              -e "OPENCLAW_CONFIG_DIR=${cfg.configDir}" \
              -e "OPENCLAW_GATEWAY_TOKEN=$(cat /run/agenix/openclaw-gateway-token 2>/dev/null || echo 'MISSING_SECRET')" \
              -e "OPENCLAW_NIX_MODE=1" \
              ${legacyEnvVars}\
              --memory=${cfg.memory} \
              --cpu-shares=${toString cfg.cpuShares} \
              --user "982:979" \
              --cap-drop ALL \
              --security-opt "no-new-privileges=true" \
              --health-cmd "${pkgs.curl}/bin/curl -sf http://localhost:${toString cfg.port}/health || exit 1" \
              --health-interval="30s" \
              --health-timeout="10s" \
              --health-retries="3" \
              --health-start-period="30s" \
              --label "managed-by=nixos" \
              --label "component=openclaw-gateway" \
              --label "environment=production" \
              "${cfg.image}" \
              node openclaw.mjs gateway --port ${toString cfg.port} --allow-unconfigured
          '';
        in "${containerStartScript}";

        ExecStop = pkgs.writeShellScript "openclaw-container-stop" ''
          #!/usr/bin/env bash
          set -euo pipefail

          ${pkgs.docker}/bin/docker stop openclaw-declarative 2>/dev/null || true
          ${pkgs.docker}/bin/docker rm openclaw-declarative 2>/dev/null || true
        '';

        # Security settings
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [cfg.stateDir cfg.dataDir cfg.configDir "/tmp"];
        ReadOnlyPaths = ["/etc/passwd" "/etc/group"];
      };
    };

    # Add OpenClaw package to system environment for CLI tools
    environment.systemPackages = with pkgs; [
      cfg.package
      (pkgs.openclaw-tools or cfg.package)
    ];

    # Health monitoring - using docker only
    systemd.services.openclaw-container-declarative-health = {
      description = "Health check for declarative OpenClaw container";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "openclaw-health-check" ''
          #!/usr/bin/env bash
          set -euo pipefail

          # Check if container is running
          if ! ${pkgs.docker}/bin/docker ps --format "table {{.Names}}" | grep -q "^openclaw-declarative$"; then
            echo "OpenClaw container is not running, restarting..."
            ${pkgs.systemd}/bin/systemctl restart openclaw-container-declarative
            exit 0
          fi

          # Check if container is healthy
          HEALTH_STATUS=$(${pkgs.docker}/bin/docker inspect --format='{{json .State.Health}}' openclaw-declarative 2>/dev/null || echo "{}")
          if echo "$HEALTH_STATUS" | grep -q '"status":"unhealthy"'; then
            echo "OpenClaw container is unhealthy, restarting..."
            ${pkgs.systemd}/bin/systemctl restart openclaw-container-declarative
            exit 0
          fi

          # Try to access the gateway
          if ! ${pkgs.curl}/bin/curl -sf "http://127.0.0.1:${toString cfg.port}/health" >/dev/null 2>&1; then
            echo "OpenClaw gateway not responding, restarting..."
            ${pkgs.systemd}/bin/systemctl restart openclaw-container-declarative
            exit 0
          fi

          echo "OpenClaw container is healthy"
          exit 0
        '';
      };
    };

    systemd.timers.openclaw-container-declarative-health = {
      description = "Periodic health check for OpenClaw container";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*:0/30";  # Every 30 seconds
        Persistent = true;
      };
    };
  };
}