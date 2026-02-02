# OpenClaw AI Agent Gateway via Container (Docker/Podman)
# Uses official OpenClaw image - avoids pnpm/hasown issues entirely
# Declarative container configuration for learning containers → Kubernetes

{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.openclaw-container;
in {
  options.services.openclaw-container = {
    enable = mkEnableOption "OpenClaw AI Agent Gateway (Container)";

    image = mkOption {
      type = types.str;
      default = "docker.io/1panel/openclaw";
      description = "OpenClaw container image (use 'ghcr.io/openclaw/openclaw' for latest)";
    };

    tag = mkOption {
      type = types.str;
      default = "latest";
      description = "Image tag version";
    };

    port = mkOption {
      type = types.port;
      default = 18789;
      description = "Port for OpenClaw gateway web interface";
    };

    apiPort = mkOption {
      type = types.port;
      default = 18790;
      description = "Port for OpenClaw API";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw";
      description = "Host directory for OpenClaw state (persists across restarts)";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/data";
      description = "Directory for agent data, memory, sessions";
    };

    configDir = mkOption {
      type = types.str;
      default = "/etc/openclaw";
      description = "Directory for configuration files";
    };

    # Container runtime selection
    runtime = mkOption {
      type = types.enum ["docker" "podman"];
      default = "podman";
      description = "Container runtime to use";
    };

    # Resource limits
    memory = mkOption {
      type = types.str;
      default = "2g";
      description = "Memory limit (e.g., '2g', '512m')";
    };

    cpuShares = mkOption {
      type = types.int;
      default = 512;
      description = "CPU shares (1024 = 1 core)";
    };

    # Health check settings
    healthCheckInterval = mkOption {
      type = types.int;
      default = 30;
      description = "Health check interval in seconds";
    };

    # Environment variables
    gatewayMode = mkOption {
      type = types.str;
      default = "local";
      description = "Gateway mode: local, cloud, hybrid";
    };

    gatewayBind = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Bind address for gateway";
    };

    # Secrets (use agenix for production)
    environmentFile = mkOption {
      type = types.path;
      default = "/run/agenix/openclaw-env";
      description = "File with environment variables (API keys, tokens)";
    };

    # Nginx integration
    nginxProxy = mkOption {
      type = types.bool;
      default = true;
      description = "Create nginx reverse proxy configuration";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # CONTAINER RUNTIME
    # ============================================================================
    # Docker/Podman should already be enabled by host config or other modules
    # We just configure the daemon settings
    virtualisation.${cfg.runtime}.daemon.settings = {
      # Storage driver for overlayfs (works on most systems)
      storage-driver = "overlay2";
      # Log settings
      log-driver = "json-file";
      log-opts = {
        "max-size" = "10m";
        "max-file" = "3";
      };
    };

    # ============================================================================
    # DIRECTORY STRUCTURE
    # ============================================================================
    systemd.tmpfiles.settings.openclaw-container = {
      "${cfg.stateDir}" = {
        d = {
          user = "lobster";
          group = "lobster";
          mode = "0755";
        };
      };
      "${cfg.dataDir}" = {
        d = {
          user = "lobster";
          group = "lobster";
          mode = "0755";
        };
      };
      "${cfg.configDir}" = {
        d = {
          user = "lobster";
          group = "lobster";
          mode = "0755";
        };
      };
      # Agent-specific directories
      "${cfg.dataDir}/agents" = {
        d = {
          user = "lobster";
          group = "lobster";
          mode = "0755";
        };
      };
      "${cfg.dataDir}/memory" = {
        d = {
          user = "lobster";
          group = "lobster";
          mode = "0755";
        };
      };
      "${cfg.dataDir}/sessions" = {
        d = {
          user = "lobster";
          group = "lobster";
          mode = "0755";
        };
      };
      "${cfg.dataDir}/logs" = {
        d = {
          user = "lobster";
          group = "lobster";
          mode = "0755";
        };
      };
    };

    # ============================================================================
    # INITIAL CONFIGURATION
    # ============================================================================
    systemd.services.openclaw-container-config = {
      description = "Setup OpenClaw container configuration";
      after = ["${cfg.runtime}.service" "network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "openclaw-container-config" ''
          set -euo pipefail

          CONTAINER_RUNTIME="${cfg.runtime}"
          STATE_DIR="${cfg.stateDir}"
          DATA_DIR="${cfg.dataDir}"
          CONFIG_DIR="${cfg.configDir}"

          # Generate a random token for gateway auth
          GATEWAY_TOKEN=$(cat /proc/sys/kernel/random/uuid | tr -d '-')

          # Create default configuration if none exists
          if [ ! -f "$CONFIG_DIR/openclaw.json" ]; then
            echo "Creating default OpenClaw configuration..."
            mkdir -p "$CONFIG_DIR"

            cat > "$CONFIG_DIR/openclaw.json" << EOF
{
  "version": "1.0.0",
  "gateway": {
    "mode": "${cfg.gatewayMode}",
    "bind": "${cfg.gatewayBind}",
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    },
    "server": {
      "host": "0.0.0.0",
      "port": ${toString cfg.port}
    }
  },
  "channels": {
    "local": {
      "enabled": true,
      "type": "cli"
    },
    "http": {
      "enabled": true,
      "host": "0.0.0.0",
      "port": ${toString cfg.apiPort}
    }
  },
  "providers": {
    # Add your API providers here (anthropic, openai, etc.)
    # Loaded from environment variables or secrets
  },
  "skills": {
    "directories": [
      "/var/lib/openclaw/skills"
    ]
  },
  "memory": {
    "type": "local",
    "path": "/var/lib/openclaw/memory"
  },
  "logging": {
    "level": "info",
    "format": "json"
  }
}
EOF
            chown -R lobster:lobster "$CONFIG_DIR"
            echo "Configuration created at $CONFIG_DIR/openclaw.json"
            echo "Generated gateway token: $GATEWAY_TOKEN"
          else
            echo "Configuration already exists at $CONFIG_DIR/openclaw.json"
          fi

          # Create skills directory if it doesn't exist
          mkdir -p "$STATE_DIR/skills"
          chown -R lobster:lobster "$STATE_DIR"

          echo "OpenClaw configuration complete"
        '';
      };
    };

    # ============================================================================
    # CONTAINER MANAGEMENT SERVICE
    # ============================================================================
    systemd.services.openclaw-container = {
      description = "OpenClaw AI Agent Gateway (Container)";
      after = [
        "${cfg.runtime}.service"
        "network-online.target"
        "openclaw-container-config.service"
      ];
      wants = [
        "${cfg.runtime}.service"
        "network-online.target"
      ];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "5m";
        TimeoutStopSec = "30s";

        # Dynamic service execution
        ExecStart = "${pkgs.writeShellScriptBin "openclaw-container-start" ''
          #!/usr/bin/env bash
          set -euo pipefail

          DOCKER="/run/current-system/sw/bin/docker"
          FULL_IMAGE="${cfg.image}:${cfg.tag}"
          CONTAINER_NAME="openclaw"
          STATE_DIR="${cfg.stateDir}"
          DATA_DIR="${cfg.dataDir}"
          CONFIG_DIR="${cfg.configDir}"
          PORT="${toString cfg.port}"
          API_PORT="${toString cfg.apiPort}"

          echo "Starting OpenClaw container..."
          echo "Image: $FULL_IMAGE"

          # Stop and remove existing container
          $DOCKER rm -f "$CONTAINER_NAME" 2>/dev/null || true

          # Pull latest image
          echo "Pulling OpenClaw image..."
          $DOCKER pull "$FULL_IMAGE" || echo "Using cached version"

          # Run container
          echo "Starting container..."
          $DOCKER run -d \
            --name "$CONTAINER_NAME" \
            --restart unless-stopped \
            --network host \
            -v "$STATE_DIR:/var/lib/openclaw" \
            -v "$DATA_DIR:/var/lib/openclaw/data" \
            -v "$CONFIG_DIR:/etc/openclaw" \
            -p "127.0.0.1:$PORT:$PORT" \
            -p "127.0.0.1:$API_PORT:$API_PORT" \
            -e "OPENCLAW_MODE=${cfg.gatewayMode}" \
            -e "OPENCLAW_BIND=${cfg.gatewayBind}" \
            -e "OPENCLAW_PORT=$PORT" \
            -e "OPENCLAW_API_PORT=$API_PORT" \
            -e "OPENCLAW_DATA_DIR=/var/lib/openclaw/data" \
            -e "OPENCLAW_CONFIG_DIR=/etc/openclaw" \
            -e "OPENCLAW_LOG_DIR=/var/lib/openclaw/data/logs" \
            --memory=2147483648 \
            --cpu-shares=512 \
            --user "1000:1000" \
            --cap-drop ALL \
            --security-opt "no-new-privileges=true" \
            --health-cmd "curl -sf http://localhost:$PORT/health || exit 1" \
            --health-interval="${toString cfg.healthCheckInterval}s" \
            --health-timeout="10s" \
            --health-retries="3" \
            --health-start-period="30s" \
            --label "managed-by=nixos" \
            "$FULL_IMAGE" \
            gateway

          echo "Container started: $CONTAINER_NAME"
          echo "Gateway: http://localhost:$PORT"
        ''}/bin/openclaw-container-start";

        ExecStop = "${pkgs.writeShellScriptBin "openclaw-container-stop" ''
          #!/usr/bin/env bash
          /run/current-system/sw/bin/docker stop openclaw 2>/dev/null || true
          /run/current-system/sw/bin/docker rm openclaw 2>/dev/null || true
        ''}/bin/openclaw-container-stop";

        # Environment file for secrets
        EnvironmentFile = cfg.environmentFile;
      };
    };

    # ============================================================================
    # HEALTH MONITORING
    # ============================================================================
    systemd.timers.openclaw-container-health = {
      description = "Health check for OpenClaw container";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* *:00/1";
        Persistent = true;
        RandomizedDelaySec = "5s";
      };
    };

    systemd.services.openclaw-container-health = {
      description = "Health check for OpenClaw container";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScriptBin "openclaw-container-health" ''
          #!/usr/bin/env bash
          PORT="${toString cfg.port}"
          DOCKER="/run/current-system/sw/bin/docker"

          # Check container status
          if ! $DOCKER ps --format '{{.Names}}' | grep -q "^openclaw$"; then
            echo "OpenClaw container not running, restarting..."
            systemctl restart openclaw-container.service
            exit 0
          fi

          # Check container health
          HEALTH=$($DOCKER inspect --format='{{.State.Health.Status}}' openclaw 2>/dev/null || echo "unknown")

          case "$HEALTH" in
            healthy)
              echo "OpenClaw is healthy"
              exit 0
              ;;
            unhealthy)
              echo "OpenClaw is unhealthy, restarting..."
              systemctl restart openclaw-container.service
              exit 0
              ;;
            starting)
              echo "OpenClaw is starting, waiting..."
              exit 0
              ;;
            *)
              echo "OpenClaw health unknown: $HEALTH"
              # Try HTTP check as fallback
              if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
                echo "OpenClaw responding to HTTP"
                exit 0
              else
                echo "OpenClaw not responding, restarting..."
                systemctl restart openclaw-container.service
              fi
              ;;
          esac
        ''}/bin/openclaw-container-health";
      };
    };

    # ============================================================================
    # NGINX REVERSE PROXY (Optional)
    # ============================================================================
    services.nginx.virtualHosts."openclaw.local" = mkIf cfg.nginxProxy {
      enable = true;
      listen = [{
        addr = "127.0.0.1";
        port = 80;
      }];
      serverName = "openclaw.local";

      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          proxyWebsockets = true;
          proxySetHeader = {
            Host = "$host";
            X-Real-IP = "$remote_addr";
            X-Forwarded-For = "$proxy_add_x_forwarded_for";
            X-Forwarded-Proto = "http";
          };
        };
        "/api/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.apiPort}";
          proxyWebsockets = true;
          proxySetHeader = {
            Host = "$host";
            X-Real-IP = "$remote_addr";
            X-Forwarded-For = "$proxy_add_x_forwarded_for";
            X-Forwarded-Proto = "http";
          };
        };
      };

      extraConfig = ''
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        # Rate limiting
        limit_req_zone $binary_remote_addr zone=openclaw:10m rate=10r/s;
        limit_req zone=openclaw burst=20 nodelay;
      '';
    };

    # ============================================================================
    # FIREWALL RULES
    # ============================================================================
    networking.firewall = {
      # Allow localhost only (containers bind to host network)
      interfaces.lo.allowedTCPPorts = [
        cfg.port
        cfg.apiPort
        80
      ];

      # Reject external access
      allowedUDPPorts = [];
      trustedInterfaces = ["lo"];
    };

    # ============================================================================
    # USER PERMISSIONS
    # ============================================================================
    users.users.lobster = {
      isSystemUser = true;
      group = "lobster";
      home = cfg.stateDir;
      createHome = false; # We create directories manually
    };

    users.groups.lobster = {};

    # ============================================================================
    # PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [
      # Container management tools
      docker-client
      ctop
      dive # Container image analyzer

      # For debugging
      curl
      jq
    ];

    # ============================================================================
    # DOCUMENTATION
    # ============================================================================
    environment.etc."openclaw-container/README.md" = {
      text = ''
        # OpenClaw Container Configuration

        ## Quick Start
        ```bash
        # Start the container
        sudo systemctl start openclaw-container

        # Check status
        sudo systemctl status openclaw-container

        # View logs
        sudo journalctl -u openclaw-container -f

        # Access the UI
        curl http://localhost:${toString cfg.port}/health
        ```

        ## Container Management
        ```bash
        # Pull latest image
        ${cfg.runtime} pull ${cfg.image}:${cfg.tag}

        # View running containers
        ${cfg.runtime} ps

        # View container logs
        ${cfg.runtime} logs openclaw

        # Execute into container
        ${cfg.runtime} exec -it openclaw /bin/sh

        # Restart container
        sudo systemctl restart openclaw-container
        ```

        ## Resource Monitoring
        ```bash
        # View container stats
        ${cfg.runtime} stats openclaw

        # Check disk usage
        du -sh ${cfg.stateDir}

        # View memory limit
        cat /sys/fs/cgroup/memory/${cfg.runtime}.scope/memory.limit_in_bytes
        ```

        ## Troubleshooting
        ```bash
        # Check if container is running
        ${cfg.runtime} ps | grep openclaw

        # Check container health
        ${cfg.runtime} inspect --format='{{.State.Health.Status}}' openclaw

        # View detailed logs
        sudo journalctl -u openclaw-container.service -n 100
        ```
      '';
      mode = "0644";
    };
  };
}
