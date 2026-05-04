# Hermes Workspace — Web UI for Hermes Agent
#
# Complete workspace: chat, sessions, memory, skills, config, terminal.
# Connects to hermes dashboard (port 9119) for full enhanced features.
# Fetches dashboard session token at startup for Bearer auth.
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
  hermesHome = config.users.users.j_kro.home;

  startScript = pkgs.writeShellScript "hermes-workspace-start" ''
    set -euo pipefail

    # Wait for dashboard to be ready (up to 30s)
    for i in $(seq 1 30); do
      if curl -sf http://127.0.0.1:9119/ > /dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    # Extra sleep — dashboard HTTP needs a moment after socket is bound
    sleep 2

    # Extract session token from dashboard HTML
    TOKEN=$(curl -sf http://127.0.0.1:9119/ 2>/dev/null \
      | grep -oP 'window.__HERMES_SESSION_TOKEN__="\K[^"]+' \
      || true)

    if [ -n "$TOKEN" ]; then
      export HERMES_API_TOKEN="$TOKEN"
      echo "Dashboard token acquired"
    else
      echo "WARNING: Could not extract dashboard token"
    fi

    exec ${pkgs.nodejs_22}/bin/node ${workspaceDir}/server-entry.js
  '';
in {
  options.services.hermes-workspace = {
    enable = lib.mkEnableOption "Hermes Workspace web UI";
    port = lib.mkOption {
      type = lib.types.port;
      default = 3002;
    };
    gatewayUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:9119";
    };
  };

  config = lib.mkIf cfg.enable {
    # Hermes Dashboard — provides the gateway API with sessions/skills/memory
    systemd.services.hermes-dashboard = {
      description = "Hermes Agent Dashboard (gateway API)";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "/run/current-system/sw/bin/hermes dashboard --port 9119 --host 127.0.0.1 --no-open --insecure";
        User = "j_kro";
        Group = "users";
        WorkingDirectory = hermesHome;
        Restart = "on-failure";
        RestartSec = 5;
        Environment = [
          "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/j_kro/bin:${pkgs.nodejs_22}/bin:/usr/bin:/bin"
          "HOME=${hermesHome}"
        ];
      };
    };

    # Hermes Workspace — the web UI
    systemd.services.hermes-workspace = {
      description = "Hermes Workspace Web UI";
      after = ["network.target" "hermes-dashboard.service"];
      wants = ["hermes-dashboard.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        HERMES_API_URL = cfg.gatewayUrl;
        HOST = "127.0.0.1";
        PORT = toString cfg.port;
        NODE_ENV = "production";
        HOME = hermesHome;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = startScript;
        User = "j_kro";
        Group = "users";
        WorkingDirectory = workspaceDir;
        Restart = "on-failure";
        RestartSec = 5;
        LimitNOFILE = 65536;
      };
    };
  };
}
