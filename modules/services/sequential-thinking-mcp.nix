{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.sequential-thinking-mcp;
in {
  options.services.sequential-thinking-mcp = {
    enable = mkEnableOption "Sequential Thinking MCP server - chain reasoning steps";

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall port";
    };

    port = mkOption {
      type = types.port;
      default = 3114;
      description = "Port for the Sequential Thinking server";
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
      "C+ /data/agents/mcp-bridges/sequential-thinking-mcp.sh 0755 j_kro users - ${pkgs.writeText "sequential-thinking-mcp.sh" ''
#!/usr/bin/env bash
# Sequential Thinking MCP server bridge
# Chain sequential reasoning steps with cross-session continuity
set -euo pipefail

${pkgs.nodejs_22}/bin/npx -y @modelcontextprotocol/server-sequential-thinking
      ''}"
    ];

    # Systemd service for Sequential Thinking (optional - mostly managed by MCP bridge)
    systemd.services.sequential-thinking-mcp = {
      description = "Sequential Thinking MCP Server - Chain Reasoning Steps";
      after = [ "network.target" ];
      wantedBy = mkDefault [ ]; # Don't auto-start by default (started on-demand by Hermes)
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nodejs_22}/bin/npx -y @modelcontextprotocol/server-sequential-thinking";
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