# Quadlet OpenClaw - Simple Autonomous Orchestration - Clean Module
# Single gateway on zephyr, accessible from all 4 cluster nodes
# No teams, no RBAC, no multi-team, just straightforward automation
#
# This setup enables you to orchestrate AI agents across your entire NixOS cluster
# with minimal configuration - no teams, no RBAC, just straightforward automation
#
{
  config,
  pkgs,
  lib,
  ...
}:
with pkgs.lib; let
  cfg = config.services.openclaw-quadlet;
  workspacePath = "/home/j_kro/workspace";
in {
  options.services.openclaw-quadlet = {
    enable = lib.mkEnableOption "OpenClaw quadlet orchestration for cluster";
    
    # Master node configuration
    masterNode = lib.mkOption {
      type = lib.types.str;
      default = "zephyr";
      description = "Hostname of master node running OpenClaw quadlet";
    };

    # Which nodes run OpenClaw agents
    agentNodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of node hostnames that run OpenClaw agents (e.g., ['nexus', 'forge', 'sentry'])";
    };

    # Workspace configuration per node
    workspaces = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Workspace path for each node (default: same path for all)";
        };
      default = {
        zephyr = "${workspacePath}";
        nexus = "/home/nexus/workspace";
        forge = "/home/forge/workspace";
        sentry = "/home/sentry/workspace";
      };
      description = "Workspace path for each node (default: same path for all, can customize)";
    };

    # Resource allocation per node (use per-node config)
    nodeResources = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        memoryReservation = lib.mkOption {
          type = lib.types.str;
          default = "2G";
          description = "Memory reservation for host (prevents resource exhaustion)";
        };
        memoryLimit = lib.mkOption {
          type = lib.types.str;
          default = "4G";
          description = "Memory hard limit for container";
        };
        pidsLimit = lib.mkOption {
          type = lib.types.int;
          default = 500;
          description = "PID limit to prevent fork bombs";
        };
        cpuQuota = lib.mkOption {
          type = lib.types.int;
          default = 200;
          description = "CPU quota percentage (200% of available cores)";
        };
      };
      description = "Resource allocation per node (can override per-node)";
    };

    # Network configuration
    networking = {
      bindToLocalhost = lib.mkEnableOption "Bind OpenClaw to localhost (127.0.0.1)";
      
      # Tailscale support - disabled by default
      enableTailscale = lib.mkEnableOption "Enable Tailscale for remote access to all nodes";
      tailscalePort = lib.mkOption {
        type = lib.types.port;
        default = 18090;
        description = "Tailscale port for cluster access (default: 18090)";
      };
      };

    # Token configuration
    authToken = lib.mkOption {
      type = lib.types.str;
      description = "OpenClaw gateway authentication token (stores via environment variable or agenix)";
    };

    # Security mode
    securityMode = lib.mkOption {
      type = lib.types.enum ["strict" "balanced" "development"];
      default = "balanced";
      description = "Security mode (balanced = good for production, development = more permissive)";
    };

    # Podman configuration
    virtualisation.podman = {
      enable = true;
      autoUpdate = true;
    };
  };
};
