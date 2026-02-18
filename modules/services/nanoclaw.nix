# NanoClaw - Lightweight Personal Claude Assistant
# Runs securely with container isolation for agents
#
# Uses Zhipu AI (GLM) via Anthropic-compatible endpoint
#
{ config, lib, pkgs, ... }:
with lib; let
  cfg = config.services.nanoclaw;
in {
  options.services.nanoclaw = {
    enable = mkEnableOption "NanoClaw - Lightweight personal Claude assistant";

    user = mkOption {
      type = types.str;
      default = "nanoclaw";
      description = "User to run NanoClaw as";
    };

    group = mkOption {
      type = types.str;
      default = "nanoclaw";
      description = "Group for NanoClaw";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/nanoclaw";
      description = "Directory for NanoClaw data";
    };

    assistantName = mkOption {
      type = types.str;
      default = "Claw";
      description = "Name your assistant responds to";
    };

    apiTokenFile = mkOption {
      type = types.nullOr types.path;
      default = "/run/agenix/zhipu-api-key";
      description = "Path to ANTHROPIC_AUTH_TOKEN file (for Zhipu AI)";
    };

    containerRuntime = mkOption {
      type = types.enum ["podman" "docker"];
      default = "podman";
      description = "Container runtime for agent isolation";
    };
  };

  config = mkIf cfg.enable {
    # Require container runtime
    virtualisation.podman.enable = mkIf (cfg.containerRuntime == "podman") true;

    # Create user and group with subuid/subgid for rootless podman
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      description = "NanoClaw service user";
      extraGroups = [ "podman" ];
      subGidRanges = [{ startGid = 100000; count = 65536; }];
      subUidRanges = [{ startUid = 100000; count = 65536; }];
    };
    users.groups.${cfg.group} = {};

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/groups 0750 ${cfg.user} ${cfg.group} -"
    ];

    # Build container image service
    systemd.services.nanoclaw-image = {
      description = "Build NanoClaw agent container image";
      wantedBy = [ "multi-user.target" ];
      after = [ "${cfg.containerRuntime}.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      before = [ "nanoclaw.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Run as root for container build (simpler than rootless podman)
        User = "root";
        Group = "root";
        WorkingDirectory = cfg.dataDir;
      };

      path = [
        pkgs.git
        pkgs.nodejs_22
        pkgs.bash
        pkgs.coreutils
      ] ++ lib.optional (cfg.containerRuntime == "podman") pkgs.podman
        ++ lib.optional (cfg.containerRuntime == "docker") pkgs.docker;

      # Environment for npm scripts
      environment = {
        HOME = cfg.dataDir;
      };

      script = ''
        set -e

        cd ${cfg.dataDir}
        
        # Ensure git is happy with the directory
        git config --global --add safe.directory ${cfg.dataDir} 2>/dev/null || true

        # Clone/update repo
        if [ ! -d ".git" ]; then
          echo "Cloning NanoClaw..."
          git clone --depth 1 https://github.com/qwibitai/nanoclaw.git .
        else
          echo "Updating NanoClaw..."
          git fetch origin
          git reset --hard origin/main
        fi

        # Install dependencies
        echo "Installing dependencies..."
        npm ci

        # Build TypeScript
        echo "Building..."
        npm run build

        # Build container image
        echo "Building container image..."
        cd container
        
        # Fix Dockerfile to use docker.io explicitly
        sed -i 's|FROM node:|FROM docker.io/library/node:|g' Dockerfile
        
        ${cfg.containerRuntime} build -t nanoclaw-agent:latest .

        # Fix ownership for nanoclaw user
        chown -R ${cfg.user}:${cfg.group} ${cfg.dataDir}

        echo "NanoClaw ready"
      '';
    };

    # Main NanoClaw service
    systemd.services.nanoclaw = {
      description = "NanoClaw - Personal Claude Assistant";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "nanoclaw-image.service" ];
      wants = [ "network-online.target" ];
      requires = [ "nanoclaw-image.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.dataDir}/dist/index.js";
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        RestartSec = 5;

        User = cfg.user;
        Group = cfg.group;

        # Systemd hardening (from openclaw-nix)
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = false;  # Node.js needs JIT
        ReadWritePaths = [ cfg.dataDir ];
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" ];
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        UMask = "0077";
      };

      environment = {
        NODE_ENV = "production";
        ASSISTANT_NAME = cfg.assistantName;
        # Zhipu AI Anthropic-compatible endpoint
        ANTHROPIC_BASE_URL = "https://api.z.ai/api/anthropic";
      };
    };

    # Load API key from file
    systemd.services.nanoclaw.serviceConfig.EnvironmentFile = cfg.apiTokenFile;

    # Helper scripts
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "nanoclaw-auth" ''
        cd ${cfg.dataDir}
        sudo -u ${cfg.user} ${pkgs.nodejs_22}/bin/npm run auth
      '')

      (pkgs.writeShellScriptBin "nanoclaw-logs" ''
        journalctl -u nanoclaw -u nanoclaw-image -f
      '')

      (pkgs.writeShellScriptBin "nanoclaw-status" ''
        echo "=== NanoClaw Status ==="
        systemctl status nanoclaw --no-pager -l
        echo ""
        echo "=== Container Image ==="
        ${cfg.containerRuntime} images | grep nanoclaw || echo "No image"
        echo ""
        echo "=== Data Directory ==="
        ls -la ${cfg.dataDir}/ 2>/dev/null | head -10
      '')

      (pkgs.writeShellScriptBin "nanoclaw-restart" ''
        sudo systemctl restart nanoclaw-image nanoclaw
      '')

      (pkgs.writeShellScriptBin "nanoclaw-register" ''
        echo "Register your main WhatsApp channel:"
        echo "1. Send a message to yourself on WhatsApp"
        echo "2. Find your JID: sqlite3 ${cfg.dataDir}/nanoclaw.db 'SELECT * FROM groups'"
        echo "3. Or add manually:"
        echo "   sqlite3 ${cfg.dataDir}/nanoclaw.db \"INSERT INTO groups (jid, folder, is_main) VALUES ('YOUR_JID@s.whatsapp.net', 'main', 1)\""
      '')
    ];

    # Documentation
    environment.etc."nanoclaw/README.md".text = ''
      # NanoClaw Setup

      ## Commands

      | Command | Description |
      |---------|-------------|
      | nanoclaw-auth | Authenticate WhatsApp |
      | nanoclaw-logs | View live logs |
      | nanoclaw-status | Check status |
      | nanoclaw-restart | Restart service |
      | nanoclaw-register | Register main channel |

      ## Setup Steps

      1. `nanoclaw-auth` - Scan QR or use pairing code
      2. Send a message to yourself on WhatsApp
      3. `nanoclaw-register` - Register your JID
      4. Test: Send "${cfg.assistantName}, hello" to yourself

      ## Configuration

      Uses Zhipu AI (GLM) via Anthropic-compatible endpoint:
      - ANTHROPIC_BASE_URL = https://api.z.ai/api/anthropic
      - ANTHROPIC_AUTH_TOKEN from ${cfg.apiTokenFile}
    '';
  };
}
