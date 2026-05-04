# Hermes Workspace — Web UI for Hermes Agent
#
# A complete workspace UI: chat, files, memory, skills, and terminal.
# Connects to the local hermes-agent gateway at 127.0.0.1:8642.
#
# Usage:
#   services.hermes-workspace.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-workspace;
  workspaceDir = "/data/projects/own/hermes-workspace";
in {
  options.services.hermes-workspace = {
    enable = lib.mkEnableOption "Hermes Workspace web UI";
    port = lib.mkOption {
      type = lib.types.port;
      default = 3002;
      description = "Port to serve the workspace on.";
    };
    gatewayUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8642";
      description = "Hermes agent gateway URL.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.hermes-workspace = {
      description = "Hermes Workspace Web UI";
      after = ["network.target" "hermes-agent.service"];
      wants = ["hermes-agent.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        HERMES_API_URL = cfg.gatewayUrl;
        HOST = "127.0.0.1";
        PORT = toString cfg.port;
        NODE_ENV = "production";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nodejs_22}/bin/node ${workspaceDir}/server-entry.js";
        WorkingDirectory = workspaceDir;
        Restart = "on-failure";
        RestartSec = 5;

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = ["${workspaceDir}/.env" "/tmp"];
        PrivateTmp = true;

        # Resource limits
        LimitNOFILE = 65536;
      };
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];
  };
}
