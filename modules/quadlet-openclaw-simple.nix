# Quadlet OpenClaw - Simple Autonomous Orchestration (Cleaned)
# Single gateway on zephyr, accessible from all 4 cluster nodes
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
  # ============================================================================
  # OPENCLAW - CLUSTER ORCHESTRATION
  # ============================================================================
  
  services.openclaw-quadlet = {
    enable = true;
    
    # Master node configuration
    masterNode = "zephyr";
  
    # This node runs OpenClaw agents
    agentNodes = [];  # nexus doesn't run its own agents yet
  
    # Workspace configuration
    workspaces.zephyr = "/home/j_kro/workspace";
  
    # Token authentication
    authToken = "your-token-here";
  
    # Security mode
    securityMode = "balanced";
    
    # Resource allocation for autonomous agents
    resources = {
      pidsLimit = 500;
      memoryLimit = "8G";      # More memory for multiple agents
      cpuQuota = "400";           # More CPU for parallel tasks
    };
    
    # Network configuration
    networking = {
      bindToLocalhost = true;
      tailscalePort = 18090;
      enableTailscale = false;
    };
  };
}
