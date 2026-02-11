# Quadlet OpenClaw - Simple Autonomous Orchestration
# Single gateway on zephyr, accessible from all 4 cluster nodes
#
# This module provides:
# - OpenClaw gateway on master node (zephyr)
# - Workspace binding for autonomous agents
# - Token-based authentication
# - Security hardening (resource limits)
#
{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.openclaw-quadlet;
in {
  # ============================================================================
  # OPTIONS
  # ============================================================================
  
  options.services.openclaw-quadlet = {
    enable = mkEnableOption "OpenClaw quadlet orchestration for cluster";
    
    # Workspace path
    workspacePath = mkOption {
      type = types.str;
      default = "/home/j_kro/workspace";
      description = "Path to workspace directory (will be bind-mounted into container)";
    };
    
    # Authentication token
    authToken = mkOption {
      type = types.str;
      default = "";
      description = "OpenClaw gateway authentication token (use agenix for secrets)";
    };
    
    # Network port
    port = mkOption {
      type = types.port;
      default = 18090;
      description = "Port for OpenClaw gateway";
    };
    
    # Bind to localhost only
    bindToLocalhost = mkOption {
      type = types.bool;
      default = true;
      description = "Bind to 127.0.0.1 only (recommended for security)";
    };
    
    # Resource limits
    memoryLimit = mkOption {
      type = types.str;
      default = "8G";
      description = "Memory limit for container";
    };
    
    pidsLimit = mkOption {
      type = types.int;
      default = 500;
      description = "PID limit to prevent fork bombs";
    };
    
    cpuQuota = mkOption {
      type = types.int;
      default = 400;
      description = "CPU quota percentage (400% = 4 cores)";
    };
  };
  
  # ============================================================================
  # CONFIG
  # ============================================================================
  
  config = mkIf cfg.enable {
    # Enable Podman
    virtualisation.podman.enable = true;
    
    # Create workspace directory if it doesn't exist
    systemd.tmpfiles.rules = [
      "d ${cfg.workspacePath} 0755 j_kro users -"
    ];
    
    # Add OpenClaw CLI wrapper to system packages
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "openclaw" ''
        # OpenClaw CLI wrapper - runs commands inside the container
        CONTAINER_NAME="openclaw-gateway"
        PODMAN="sudo podman"
        
        check_container() {
          if ! $PODMAN ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
            echo "Error: Container '$CONTAINER_NAME' is not running"
            echo "Start it with: sudo systemctl start openclaw-gateway"
            exit 1
          fi
        }
        
        case "$1" in
          shell|sh)
            check_container
            $PODMAN exec -it "$CONTAINER_NAME" /bin/bash || $PODMAN exec -it "$CONTAINER_NAME" /bin/sh
            ;;
          logs)
            $PODMAN logs -f "$CONTAINER_NAME"
            ;;
          status)
            echo "=== Container ==="
            $PODMAN ps -a --filter "name=$CONTAINER_NAME"
            echo
            echo "=== Service ==="
            systemctl status openclaw-gateway --no-pager 2>/dev/null || true
            ;;
          restart)
            sudo systemctl restart openclaw-gateway
            ;;
          exec)
            shift
            check_container
            $PODMAN exec -it "$CONTAINER_NAME" "$@"
            ;;
          --help|-h|help)
            echo "OpenClaw CLI Wrapper"
            echo ""
            echo "Usage: openclaw <command>"
            echo ""
            echo "Commands:"
            echo "  shell      Get a shell inside the container"
            echo "  logs       Show container logs"
            echo "  status     Show container status"
            echo "  restart    Restart the container"
            echo "  exec <cmd> Run command in container"
            echo "  <cmd>      Run OpenClaw CLI command (gateway, onboard, etc.)"
            echo ""
            echo "Examples:"
            echo "  openclaw gateway --help"
            echo "  openclaw onboard"
            echo "  openclaw doctor"
            echo "  openclaw security audit"
            ;;
          *)
            check_container
            if [ $# -eq 0 ]; then
              $PODMAN exec -it "$CONTAINER_NAME" openclaw --help
            else
              $PODMAN exec -it "$CONTAINER_NAME" openclaw "$@"
            fi
            ;;
        esac
      '')
    ];
    
    # OpenClaw Gateway Container
    virtualisation.quadlet.containers.openclaw-gateway = {
      # Auto-start on boot
      autoStart = true;
      
      # Container configuration
      containerConfig = {
        image = "docker.io/alpine/openclaw:latest";
        name = "openclaw-gateway";
        
        # Workspace binding
        volumes = [
          "${cfg.workspacePath}:/workspace"
        ];
        
        # Network binding
        publishPorts = mkIf cfg.bindToLocalhost [
          "127.0.0.1:${toString cfg.port}:${toString cfg.port}"
        ];
        
        # Resource limits
        memory = cfg.memoryLimit;
        pidsLimit = cfg.pidsLimit;
        
        # Security options
        securityLabelDisable = true;
        
        # Environment variables
        environments = mkIf (cfg.authToken != "") {
          OPENCLAW_GATEWAY_TOKEN = cfg.authToken;
        };
        
        # Labels
        labels = {
          app = "openclaw";
          role = "gateway";
          managed-by = "quadlet";
        };
        
        # Log driver
        logDriver = "journald";
      };
      
      # Systemd service config
      serviceConfig = {
        Restart = "always";
        RestartSec = "10";
        TimeoutStartSec = "120";
        TimeoutStopSec = "30";
        OOMScoreAdjust = -500;
      };
    };
  };
}
