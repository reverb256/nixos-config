# OpenClaw AI Agent Gateway via Docker
# Uses official OpenClaw sandbox image to avoid hasown/pnpm issues

{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.openclaw-docker;
in {
  options.services.openclaw-docker = {
    enable = mkEnableOption "OpenClaw AI Agent Gateway (Docker)";

    image = mkOption {
      type = types.str;
      default = "openclaw/openclaw-sandbox:bookworm";
      description = "OpenClaw Docker image to use";
    };

    port = mkOption {
      type = types.port;
      default = 18789;
      description = "Port for OpenClaw gateway";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw";
      description = "Directory for OpenClaw state";
    };

    configDir = mkOption {
      type = types.str;
      default = "/etc/openclaw";
      description = "Directory for OpenClaw configuration";
    };

    gatewayToken = mkOption {
      type = types.str;
      default = "";
      description = "Gateway authentication token";
    };

    environmentFile = mkOption {
      type = types.path;
      default = "/run/agenix/openclaw-env";
      description = "File containing environment variables";
    };
  };

  config = mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker.enable = true;

    # Create directories
    systemd.tmpfiles.settings.openclaw-docker = {
      "${cfg.stateDir}" = {
        d = {
          user = config.users.users.lobster.name;
          group = config.users.users.lobster.group;
          mode = "0755";
        };
      };
      "${cfg.configDir}" = {
        d = {
          user = config.users.users.lobster.name;
          group = config.users.users.lobster.group;
          mode = "0755";
        };
      };
    };

    # Copy default config if none exists
    systemd.services.openclaw-docker-config = {
      description = "Setup OpenClaw config directory";
      after = ["docker.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "openclaw-config-setup" ''
          if [ ! -f "${cfg.configDir}/config.json" ]; then
            mkdir -p "${cfg.configDir}"
            cat > "${cfg.configDir}/config.json" << 'EOF'
{
  "version": "1.0.0",
  "gateway": {
    "mode": "local",
    "auth": {
      "mode": "token"
    },
    "server": {
      "host": "0.0.0.0",
      "port": 18789
    }
  },
  "channels": {
    "local": {
      "enabled": true
    }
  },
  "providers": {},
  "skills": {
    "directories": []
  }
}
EOF
            chown -R lobster:lobster "${cfg.configDir}"
          fi
        '';
      };
    };

    # OpenClaw Docker container service
    systemd.services.openclaw-docker = {
      description = "OpenClaw AI Agent Gateway (Docker)";
      after = ["docker.service" "network-online.target" "openclaw-docker-config.service"];
      wants = ["docker.service" "network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "5s";
        ExecStart = pkgs.writeShellScript "openclaw-start" ''
          # Remove old container if exists
          docker rm -f openclaw 2>/dev/null || true

          # Build OpenClaw container from local source
          cd /data/@projects/infra/nixos
          
          # Check if we have local source to build
          if [ -d "/data/@projects/infra/nixos/../openclaw" ]; then
            echo "Building OpenClaw from local source..."
            docker build -t openclaw-local /data/@projects/infra/nixos/../openclaw
            IMAGE="openclaw-local"
          else
            IMAGE="${cfg.image}"
            echo "Using pre-built image: $IMAGE"
          fi

          # Run OpenClaw container
          docker run -d \
            --name openclaw \
            --restart unless-stopped \
            --network host \
            -v ${cfg.stateDir}:/var/lib/openclaw \
            -v ${cfg.configDir}:/etc/openclaw \
            -e OPENCLAW_STATE_DIR=/var/lib/openclaw \
            -e OPENCLAW_CONFIG_DIR=/etc/openclaw \
            -e OPENCLAW_GATEWAY_HOST=0.0.0.0 \
            -e OPENCLAW_GATEWAY_PORT=${toString cfg.port} \
            -e OPENCLAW_GATEWAY_TOKEN=${cfg.gatewayToken} \
            -e HOME=/var/lib/openclaw \
            --user 1000:1000 \
            --cap-drop ALL \
            --security-opt no-new-privileges \
            $IMAGE \
            gateway --port ${toString cfg.port}
        '';

        ExecStop = pkgs.writeShellScript "openclaw-stop" ''
          docker stop openclaw 2>/dev/null || true
          docker rm openclaw 2>/dev/null || true
        '';

        # Environment file support
        EnvironmentFile = cfg.environmentFile;
      };
    };

    # Health check timer
    systemd.timers.openclaw-docker-health = {
      description = "Health check for OpenClaw Docker";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*:*:0/30";
        Persistent = false;
      };
    };

    systemd.services.openclaw-docker-health = {
      description = "Health check for OpenClaw Docker";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "openclaw-health-check" ''
          if ! curl -sf "http://127.0.0.1:${toString cfg.port}/health" >/dev/null 2>&1; then
            echo "OpenClaw not responding, restarting..."
            systemctl restart openclaw-docker.service
          fi
        '';
      };
    };

    # Firewall: only localhost access
    networking.firewall.interfaces.lo.allowedTCPPorts = [cfg.port];
  };
}
