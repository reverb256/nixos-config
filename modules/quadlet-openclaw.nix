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
          OPENCLAW_TOKEN = cfg.authToken;
          OPENCLAW_AUTH_MODE = "token";
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
