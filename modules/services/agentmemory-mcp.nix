{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.agentmemory-mcp;
in {
  options.services.agentmemory-mcp = {
    enable = mkEnableOption "Agentmemory MCP server - persistent coding memory";

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall port";
    };

    port = mkOption {
      type = types.port;
      default = 3111;
      description = "Port for the Agentmemory server (default 3111)";
    };

    nodejsPackage = mkOption {
      type = types.package;
      default = pkgs.nodejs_22;
      defaultText = "pkgs.nodejs_22";
      description = "Node.js package to use for npx";
    };
  };

  config = mkIf cfg.enable {
    # Ensure bridge script exists with correct permissions
    systemd.tmpfiles.rules = [
      "d /data/agents/mcp-bridges 0755 j_kro users -"
      "C+ /data/agents/mcp-bridges/agentmemory-mcp.sh 0755 j_kro users - ${pkgs.writeText "agentmemory-mcp.sh" ''
#!/usr/bin/env bash
# Agentmemory MCP server bridge
# Auto-captures coding sessions via hooks, compresses with AI
# 53 MCP tools for persistent coding memory
set -euo pipefail

${pkgs.nodejs_22}/bin/npx -y @agentmemory/mcp
      ''}"
    ];

    # Systemd service for Agentmemory (optional - mostly managed by MCP bridge)
    systemd.services.agentmemory-mcp = {
      description = "Agentmemory MCP Server - Persistent Coding Memory";
      after = [ "network.target" ];
      wantedBy = mkDefault [ ]; # Don't auto-start by default (started on-demand by Hermes)
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nodejs_22}/bin/npx -y @agentmemory/mcp";
        Restart = "on-failure";
        RestartSec = "10";
        User = "j_kro";
        Group = "users";
        WorkingDirectory = "/home/j_kro";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}