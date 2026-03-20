# OpenCode Configuration Module
# Provides dynamic model synchronization from AI Gateway
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.opencode;
  inherit
    (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    optional
    optionalString
    ;

  # Update script wrapper
  updateScript = pkgs.writeShellApplication {
    name = "opencode-model-update";
    runtimeInputs = with pkgs; [
      python3
      curl
      jq
      openssh
    ];
    text = ''
      set -euo pipefail

      # Configuration
      GATEWAY_URL="${cfg.gatewayUrl}"
      UPDATE_SCRIPT="${cfg.updateScriptPath}"
      USER="${cfg.user}"

      echo "=== OpenCode Model Update ==="
      echo "Gateway: $GATEWAY_URL"
      echo "Started at: $(date)"

      # Wait for gateway to be ready
      echo "Waiting for gateway..."
      for i in {1..30}; do
        if curl -sf "$GATEWAY_URL/health" >/dev/null 2>&1; then
          echo "  ✓ Gateway is ready"
          break
        fi
        if [ "$i" -eq 30 ]; then
          echo "  ✗ Gateway not ready after 30 seconds"
          exit 0
        fi
        sleep 1
      done

      # Run the Python update script
      echo "Fetching models from gateway..."
      if [ -f "$UPDATE_SCRIPT" ]; then
        if python3 "$UPDATE_SCRIPT" "$@" 2>&1; then
          echo "  ✓ Model update complete"
        else
          echo "  ⚠️  Update script failed (gateway may have no models configured)"
          echo "  This is non-critical - OpenCode will use fallback provider"
          exit 0
        fi
      else
        echo "  ✗ Update script not found: $UPDATE_SCRIPT"
        exit 0
      fi
    '';
  };
in {
  options.services.opencode = {
    enable = mkEnableOption "OpenCode with dynamic model synchronization from AI Gateway";

    # User configuration
    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User to run OpenCode as";
    };

    # Gateway configuration
    gatewayUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:8080";
      description = "AI Inference Gateway URL for model discovery";
    };

    gatewayHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Gateway host for OpenCode provider config";
    };

    gatewayPort = mkOption {
      type = types.port;
      default = 8080;
      description = "Gateway port for OpenCode provider config";
    };

    # Model sync configuration
    autoSync = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic model synchronization";
      };

      interval = mkOption {
        type = types.str;
        default = "5min";
        description = "Systemd timer interval for model sync (e.g., '5min', '1h')";
      };

      onGatewayStart = mkOption {
        type = types.bool;
        default = true;
        description = "Trigger sync when AI gateway starts";
      };
    };

    # Update script path
    updateScriptPath = mkOption {
      type = types.str;
      default = "/etc/nixos/scripts/update-opencode-models.py";
      description = "Path to the model update Python script";
    };

    # Cluster sync configuration
    clusterSync = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Sync configuration to cluster nodes (forge, nexus, sentry)";
      };

      nodes = mkOption {
        type = types.listOf types.str;
        default = ["forge" "nexus" "sentry"];
        description = "Cluster nodes to sync configuration to";
      };

      sshUser = mkOption {
        type = types.str;
        default = "j_kro";
        description = "SSH user for cluster sync";
      };
    };

    # Fallback ZAI provider (when gateway is unavailable)
    zai = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable ZAI as fallback provider";
      };

      baseUrl = mkOption {
        type = types.str;
        default = "https://api.z.ai/api/coding/paas/v4";
        description = "ZAI API base URL";
      };

      models = mkOption {
        type = types.listOf types.str;
        default = ["glm-5" "glm-4.7" "glm-4.6"];
        description = "ZAI models to configure";
      };
    };

    # Pollinations provider (free alternative)
    pollinations = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Pollinations AI provider";
      };

      baseUrl = mkOption {
        type = types.str;
        default = "https://text.pollinations.ai";
        description = "Pollinations API base URL";
      };
    };

    # Static category overrides (when dynamic sync isn't enough)
    categoryOverrides = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {
        "visual-engineering" = "gateway/qwen2-vl-7b";
        artistry = "gateway/qwen3.5-14b";
      };
      description = "Static model overrides for specific categories (overrides dynamic discovery)";
    };

    # oh-my-opencode plugin configuration
    ohMyOpencode = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable oh-my-opencode plugin for category-based model selection";
      };

      # Default model selection priorities
      defaultPriorities = mkOption {
        type = types.attrsOf types.int;
        default = {
          # 35B A3B Opus - highest priority
          "35b-a3b-opus" = 100;
          # 27B Opus
          "27b-opus" = 95;
          # 35B A3B
          "35b-a3b" = 90;
          # 18B Reap/Coding
          "18b-reap" = 85;
          "18b-coding" = 84;
          # 14B Opus
          "14b-opus" = 80;
          # 9B Opus
          "9b-opus" = 75;
          # 9B general
          "9b" = 60;
          # 4B
          "4b" = 40;
          # 0.8B - fastest
          "0.8b" = 30;
          # 2B
          "2b" = 20;
        };
        description = "Priority scores for automatic default model selection";
      };

      smallModelPriorities = mkOption {
        type = types.attrsOf types.int;
        default = {
          "0.8b" = 100;
          "2b" = 90;
          "4b" = 80;
        };
        description = "Priority scores for small/fast model selection";
      };
    };
  };

  config = mkIf cfg.enable {
    # Environment variables for OpenCode
    environment.sessionVariables = {
      OPENCODE_MCP_SCHEMA_FIX = "1";
      OPENCODE_TOOL_STRUCTURED_OUTPUT = "1";
      OPENCODE_PATH_FIX = "1";
      # Gateway URL for OpenCode provider
      OPENCODE_GATEWAY_URL = "${cfg.gatewayUrl}";
    };

    # System packages for OpenCode management
    environment.systemPackages = with pkgs; [
      updateScript
      (pkgs.writeShellScriptBin "opencode-sync" ''
        #!/bin/bash
        # Manual trigger for OpenCode model sync
        echo "=== OpenCode Model Sync ==="
        systemctl start opencode-model-update.service
        journalctl -u opencode-model-update.service -n 50 --no-pager
      '')
      (pkgs.writeShellScriptBin "opencode-status" ''
        #!/bin/bash
        # Show OpenCode configuration status
        echo "=== OpenCode Status ==="
        echo ""
        echo "Gateway:"
        curl -sf "${cfg.gatewayUrl}/health" && echo "  ✓ Gateway is healthy" || echo "  ✗ Gateway is down"
        echo ""
        echo "Models from gateway:"
        curl -sf "${cfg.gatewayUrl}/v1/models" | ${pkgs.jq}/bin/jq -r '.data[].id' 2>/dev/null | sed 's/^/  /' || echo "  ✗ Could not fetch models"
        echo ""
        echo "OpenCode config:"
        [ -f "/home/${cfg.user}/.config/opencode/opencode.json" ] && echo "  ✓ User config exists" || echo "  ✗ User config missing"
        [ -f "/root/.config/opencode/opencode.json" ] && echo "  ✓ Root config exists" || echo "  ✗ Root config missing"
        echo ""
        echo "Last sync:"
        journalctl -u opencode-model-update.service -n 1 --no-pager -o short | grep -oP 'Started at.*' || echo "  No sync logs found"
        echo ""
        echo "Available commands:"
        echo "  opencode-sync        - Trigger model sync now"
        echo "  opencode-status      - Show this status"
        echo "  systemctl status opencode-model-update.timer"
      '')
    ];

    # Create config directories
    systemd.tmpfiles.rules = [
      "d /home/${cfg.user}/.config 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/opencode 0755 ${cfg.user} users -"
      "d /root/.config 0755 root root -"
      "d /root/.config/opencode 0755 root root -"
    ];

    # Systemd service for one-time model update
    systemd.services.opencode-model-update = {
      description = "OpenCode Model Synchronization Service";
      after = ["network.target" "ai-inference-gateway.service"];
      wants = optional cfg.autoSync.onGatewayStart "ai-inference-gateway.service";

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${updateScript}/bin/opencode-model-update";
        User = "root";
        Group = "root";

        # Security
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "yes"; # Allow read from /etc, /usr, /boot but not write
        ProtectHome = "read-write";
        ReadWritePaths = [
          "/home/${cfg.user}/.config/opencode"
          "/root/.config/opencode"
        ];
        # Allow reading the update script and agenix secrets
        ReadOnlyPaths = [
          "/etc/nixos/scripts"
          "/run/agenix"
        ];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";

        # Timeouts
        TimeoutStartSec = "120"; # 2 minutes for gateway + model fetch
      };
    };

    # Systemd timer for periodic updates
    systemd.timers.opencode-model-update = mkIf cfg.autoSync.enable {
      description = "OpenCode Model Synchronization Timer";
      wantedBy = ["timers.target"];
      partOf = ["opencode-model-update.service"];
      timerConfig = {
        OnBootSec = "30s"; # Run 30s after boot
        OnUnitActiveSec = cfg.autoSync.interval;
        AccuracySec = "1s";
        Persistent = true;
      };
    };

    # Initial config generation (fallback if service fails)
    system.activationScripts.opencodeConfig = ''
      # Ensure directories exist
      mkdir -p /home/${cfg.user}/.config/opencode
      mkdir -p /root/.config/opencode

      # Check if config exists, if not create minimal fallback
      if [ ! -f /home/${cfg.user}/.config/opencode/opencode.json ]; then
        echo "Creating minimal OpenCode configuration..."
        cat > /home/${cfg.user}/.config/opencode/opencode.json <<EOF
      {
        "$schema": "https://opencode.ai/config.json",
        "provider": {
          ${optionalString cfg.zai.enable ''
        "zai-coding-plan": {
          "options": {
            "apiKey": "{env:ZAI_API_KEY}"
          }
        },
      ''}
          "gateway": {
            "npm": "@ai-sdk/openai-compatible",
            "name": "AI Gateway v2 (Local)",
            "options": {
              "baseURL": "http://${cfg.gatewayHost}:${toString cfg.gatewayPort}/v1",
              "apiKey": "{env:LM_STUDIO_API_KEY}",
              "timeout": 300000,
              "maxRetries": 3
            }
          }
        },
        "model": "gateway/qwen3.5-9b",
        "plugin": ["oh-my-opencode"]
      }
      EOF

        # Copy to root
        cp /home/${cfg.user}/.config/opencode/opencode.json /root/.config/opencode/opencode.json

        # Set permissions
        chown -R ${cfg.user}:users /home/${cfg.user}/.config/opencode
        chmod 644 /home/${cfg.user}/.config/opencode/*.json
        chmod 644 /root/.config/opencode/*.json

        echo "  ✓ Minimal OpenCode configuration created"
        echo "  ! Run 'systemctl start opencode-model-update' for full model sync"
      fi
    '';

    # Cluster sync (only on zephyr)
    system.activationScripts.opencodeSync = lib.mkAfter (
      optionalString cfg.clusterSync.enable ''
        # Only run on zephyr (main node)
        if [ "$(/run/current-system/sw/bin/hostname)" = "zephyr" ]; then
          echo "Checking opencode configuration sync to cluster nodes..."

          # Only sync if we have a valid config
          if [ -f /home/${cfg.user}/.config/opencode/opencode.json ]; then
            for node in ${lib.concatStringsSep " " cfg.clusterSync.nodes}; do
              if /run/current-system/sw/bin/ssh -o ConnectTimeout=5 ${cfg.clusterSync.sshUser}@$node "test -d /home/${cfg.clusterSync.sshUser}/.config" 2>/dev/null; then
                /run/current-system/sw/bin/scp -o ConnectTimeout=5 -q \
                  /home/${cfg.user}/.config/opencode/*.json \
                  ${cfg.clusterSync.sshUser}@$node:/home/${cfg.clusterSync.sshUser}/.config/opencode/ 2>/dev/null || true
                /run/current-system/sw/bin/ssh -o ConnectTimeout=5 ${cfg.clusterSync.sshUser}@$node \
                  "sudo -n cp /home/${cfg.clusterSync.sshUser}/.config/opencode/*.json /root/.config/opencode/" 2>/dev/null || true
                echo "  ✓ $node synced"
              fi
            done
          fi
        fi
      ''
    );
  };
}
