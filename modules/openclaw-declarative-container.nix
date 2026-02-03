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

    # NixOS built-in container
    virtualisation.containers.openclaw = mkIf false {  # Disabled for testing - use Docker service instead
      enable = true;
      image = cfg.image;
      binds = [
        "${cfg.stateDir}:${cfg.stateDir}"
        "${cfg.dataDir}:${cfg.dataDir}"
        "${cfg.configDir}:${cfg.configDir}"
      ];
      
      environment = {
        "OPENCLAW_MODE" = cfg.gatewayMode;
        "OPENCLAW_BIND" = cfg.gatewayBind;
        "OPENCLAW_PORT" = toString cfg.port;
        "OPENCLAW_API_PORT" = toString cfg.apiPort;
        "OPENCLAW_STATE_DIR" = cfg.stateDir;
        "OPENCLAW_DATA_DIR" = cfg.dataDir;
        "OPENCLAW_CONFIG_DIR" = cfg.configDir;
        "OPENCLAW_GATEWAY_TOKEN" = "dev-token-12345";  # Placeholder, should come from secrets
      } // (if cfg.enableLegacyEnv
        then {
          "MOLTBOT_NIX_MODE" = "1";
          "CLAWDBOT_NIX_MODE" = "1";
        }
        else {});

      autoStart = true;
      ephemeral = false;
    };

    # Docker service configuration (better for production)
    virtualisation.docker = mkIf (!config.virtualisation.podman.enable) {
      enable = true;
      enableOnBoot = true;
    };

    # Podman service configuration (alternative to Docker)
    virtualisation.podman = mkIf (!config.virtualisation.docker.enable) {
      enable = true;
      enableNftables = false;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    # Systemd service to manage the container
    systemd.services.openclaw-container-declarative = {
      description = "OpenClaw AI Agent Gateway (Declarative Container)";
      after = ["network.target"]
        ++ (if config.virtualisation.docker.enable then ["docker.service"] else [])
        ++ (if config.virtualisation.podman.enable then ["podman.service"] else []);
      wants = ["network.target"]
        ++ (if config.virtualisation.docker.enable then ["docker.service"] else [])
        ++ (if config.virtualisation.podman.enable then ["podman.service"] else []);
      wantedBy = ["multi-user.target"];

      preStart = let
        setupScript = pkgs.writeShellScript "openclaw-container-setup" ''
          #!/usr/bin/env bash
          set -euo pipefail

          # Determine container runtime
          if command -v podman >/dev/null 2>&1; then
            CONTAINER_RUNTIME=podman
          elif command -v docker >/dev/null 2>&1; then
            CONTAINER_RUNTIME=docker
          else
            echo "ERROR: Neither podman nor docker found"
            exit 1
          fi

          # Stop and remove existing container if it exists
          $CONTAINER_RUNTIME rm -f openclaw-declarative 2>/dev/null || true

          # Pull the latest image
          echo "Pulling OpenClaw image: ${cfg.image}"
          $CONTAINER_RUNTIME pull "${cfg.image}"
        '';
      in "${setupScript}";

      serviceConfig = {
        Type = "exec";
        Restart = "always";
        RestartSec = "5s";
        TimeoutStartSec = "5m";
        TimeoutStopSec = "30s";
        RemainAfterExit = true;
        
        ExecStart = let
          runtimeDetector = pkgs.writeShellScript "openclaw-runtime-detector" ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Determine which runtime to use based on system configuration
            if systemctl is-active --quiet podman && command -v podman >/dev/null 2>&1; then
              echo "podman"
            elif systemctl is-active --quiet docker && command -v docker >/dev/null 2>&1; then
              echo "docker"
            else
              # Default to docker if neither service is running
              if command -v podman >/dev/null 2>&1; then
                echo "podman"
              elif command -v docker >/dev/null 2>&1; then
                echo "docker"
              else
                echo "ERROR: Neither podman nor docker found" >&2
                exit 1
              fi
            fi
          '';
          
          containerStartScript = pkgs.writeShellScript "openclaw-container-start" ''
            #!/usr/bin/env bash
            set -euo pipefail

            CONTAINER_RUNTIME=$(${runtimeDetector})
            echo "Using container runtime: $CONTAINER_RUNTIME"

            # Build environment file path if provided
            ENV_FILE_ARG=""
            if [ -n "${lib.optionalString (cfg.environmentFile != null) (toString cfg.environmentFile)}" ]; then
              ENV_FILE_ARG="--env-file=${cfg.environmentFile}"
            fi

            # Start the container with all the right parameters
            exec $CONTAINER_RUNTIME run \
              --name openclaw-declarative \
              --network host \
              --restart unless-stopped \
              -v "${cfg.stateDir}:${cfg.stateDir}" \
              -v "${cfg.dataDir}:${cfg.dataDir}" \
              -v "${cfg.configDir}:${cfg.configDir}" \
              -e "OPENCLAW_MODE=${cfg.gatewayMode}" \
              -e "OPENCLAW_BIND=${cfg.gatewayBind}" \
              -e "OPENCLAW_PORT=${toString cfg.port}" \
              -e "OPENCLAW_API_PORT=${toString cfg.apiPort}" \
              -e "OPENCLAW_STATE_DIR=${cfg.stateDir}" \
              -e "OPENCLAW_DATA_DIR=${cfg.dataDir}" \
              -e "OPENCLAW_CONFIG_DIR=${cfg.configDir}" \
              -e "OPENCLAW_GATEWAY_TOKEN=dev-token-12345" \
              -e "OPENCLAW_NIX_MODE=1" \
              ${lib.optionalString cfg.enableLegacyEnv ''
                -e "MOLTBOT_NIX_MODE=1" \
                -e "MOLTBOT_STATE_DIR=${cfg.stateDir}" \
                -e "CLAWDBOT_NIX_MODE=1" \
                -e "CLAWDBOT_STATE_DIR=${cfg.stateDir}" \
              ''} \
              --memory=${cfg.memory} \
              --cpu-shares=${toString cfg.cpuShares} \
              --user "982:979" \
              --cap-drop ALL \
              --security-opt "no-new-privileges=true" \
              --health-cmd "curl -sf http://localhost:${toString cfg.port}/health || exit 1" \
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

        ExecStop = let
          runtimeDetector = pkgs.writeShellScript "openclaw-runtime-detector-stop" ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Determine which runtime to use based on system configuration
            if systemctl is-active --quiet podman && command -v podman >/dev/null 2>&1; then
              echo "podman"
            elif systemctl is-active --quiet docker && command -v docker >/dev/null 2>&1; then
              echo "docker"
            else
              # Default to docker if neither service is running
              if command -v podman >/dev/null 2>&1; then
                echo "podman"
              elif command -v docker >/dev/null 2>&1; then
                echo "docker"
              else
                echo "docker"  # Default fallback
              fi
            fi
          '';
          
          containerStopScript = pkgs.writeShellScript "openclaw-container-stop" ''
            #!/usr/bin/env bash
            set -euo pipefail

            CONTAINER_RUNTIME=$(${runtimeDetector})
            echo "Stopping OpenClaw container with $CONTAINER_RUNTIME..."

            $CONTAINER_RUNTIME stop openclaw-declarative 2>/dev/null || true
            $CONTAINER_RUNTIME rm openclaw-declarative 2>/dev/null || true
          '';
        in "${containerStopScript}";

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

    # Health monitoring
    systemd.services.openclaw-container-declarative-health = {
      description = "Health check for declarative OpenClaw container";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "openclaw-health-check" ''
          #!/usr/bin/env bash
          set -euo pipefail

          # Determine container runtime
          if command -v podman >/dev/null 2>&1 && systemctl is-active --quiet podman; then
            CONTAINER_RUNTIME=podman
          elif command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
            CONTAINER_RUNTIME=docker
          else
            echo "ERROR: Neither podman nor docker service is running"
            exit 1
          fi

          # Check if container is running
          if ! $CONTAINER_RUNTIME ps --format "table {{.Names}}" | grep -q "^openclaw-declarative$"; then
            echo "OpenClaw container is not running, restarting..."
            systemctl restart openclaw-container-declarative
            exit 0
          fi

          # Check if container is healthy
          HEALTH_STATUS=$($CONTAINER_RUNTIME inspect --format='{{json .State.Health}}' openclaw-declarative 2>/dev/null || echo "{}")
          if echo "$HEALTH_STATUS" | grep -q '"status":"unhealthy"'; then
            echo "OpenClaw container is unhealthy, restarting..."
            systemctl restart openclaw-container-declarative
            exit 0
          fi

          # Try to access the gateway
          if ! curl -sf "http://127.0.0.1:${toString cfg.port}/health" >/dev/null 2>&1; then
            echo "OpenClaw gateway not responding, restarting..."
            systemctl restart openclaw-container-declarative
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