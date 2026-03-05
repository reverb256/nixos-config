# Spacebot AI Agent - Podman Deployment
# Multi-agent AI system for teams with Discord, Slack, Telegram integration
# Integrates with existing AI Gateway at http://127.0.0.1:8080
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.spacebot;
  inherit (lib) mkEnableOption mkIf mkOption types literalExpression;
in {
  options.services.spacebot = {
    enable = mkEnableOption "Spacebot AI agent service";

    # Container configuration
    image = mkOption {
      type = types.str;
      default = "ghcr.io/spacedriveapp/spacebot:latest";
      description = "Container image to use";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/spacebot";
      description = "Directory for persistent data";
    };

    # Web UI configuration
    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host to bind the web UI to";
    };

    port = mkOption {
      type = types.int;
      default = 19898;
      description = "Port for the web UI";
    };

    # AI Gateway integration
    gatewayUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:8080";
      description = "URL of your AI inference gateway";
    };

    useGateway = mkOption {
      type = types.bool;
      default = true;
      description = "Route LLM requests through AI Gateway (enables routing, caching, metrics)";
    };

    # API Keys (can be set via environment or agenix)
    apiKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "OpenRouter/OpenAI API key (if not using gateway)";
    };

    apiKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = literalExpression ''"/run/agenix/spacebot-api-key"'';
      description = "File containing API key (if not using gateway)";
    };

    # Discord configuration
    discord = {
      enable = mkEnableOption "Discord integration";

      token = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Discord bot token";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExpression ''"/run/agenix/discord-token"'';
        description = "File containing Discord bot token";
      };

      guildId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Discord guild/server ID";
      };
    };

    # Slack configuration
    slack = {
      enable = mkEnableOption "Slack integration";

      token = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Slack bot token";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExpression ''"/run/agenix/slack-token"'';
        description = "File containing Slack bot token";
      };
    };

    # Telegram configuration
    telegram = {
      enable = mkEnableOption "Telegram integration";

      token = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Telegram bot token";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExpression ''"/run/agenix/telegram-token"'';
        description = "File containing Telegram bot token";
      };
    };

    # Resource limits
    memory = mkOption {
      type = types.str;
      default = "4G";
      description = "Memory limit for the container";
    };

    cpu = mkOption {
      type = types.str;
      default = "2";
      description = "CPU quota for the container (e.g., '2' for 2 cores)";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # ASSERTIONS
    # ============================================================================
    assertions = [
      {
        assertion = cfg.useGateway || cfg.apiKey != null || cfg.apiKeyFile != null;
        message = "Spacebot requires either: useGateway=true, apiKey, or apiKeyFile";
      }
      {
        assertion = !cfg.discord.enable || (cfg.discord.token != null || cfg.discord.tokenFile != null);
        message = "Discord integration requires token or tokenFile";
      }
    ];

    # ============================================================================
    # SYSTEMD SERVICE
    # ============================================================================
    systemd.services.spacebot = {
      description = "Spacebot AI Agent";
      after = ["network-online.target" "podman.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";

        # Use podman to run the container
        ExecStartPre = pkgs.writeShellScript "spacebot-prep" ''
          # Create data directory
          mkdir -p ${cfg.dataDir}/{data,ingest,skills}
          chmod 700 ${cfg.dataDir}

          # Pull latest image
          ${pkgs.podman}/bin/podman pull ${cfg.image}

          # Generate config.toml if it doesn't exist
          if [ ! -f ${cfg.dataDir}/config.toml ]; then
            cat > ${cfg.dataDir}/config.toml <<'EOF'
          # Spacebot Configuration - Auto-generated by NixOS
          # Modify this file to customize your agent

          # ============================================================================
          # LLM PROVIDER - Using AI Gateway
          # ============================================================================
          ${lib.optionalString cfg.useGateway ''
          [llm.provider.ai-gateway]
          api_type = "openai_completions"
          base_url = "${cfg.gatewayUrl}/v1"
          # API key is optional when using gateway
          ${lib.optionalString (cfg.apiKey != null) "api_key = \"${cfg.apiKey}\""}
          ${lib.optionalString (cfg.apiKeyFile != null) "api_key = \"file:${cfg.apiKeyFile}\""}

          [defaults.routing]
          # Use AI Gateway model names
          channel = "magnum-opus-35b-a3b-i1"
          worker = "magnum-opus-35b-a3b-i1"

          [defaults.routing.task_overrides]
          coding = "magnum-opus-35b-a3b-i1"
          ''}

          ${lib.optionalString (!cfg.useGateway && (cfg.apiKey != null || cfg.apiKeyFile != null)) ''
          [llm]
          ${lib.optionalString (cfg.apiKey != null) "openrouter_key = \"${cfg.apiKey}\""}
          ${lib.optionalString (cfg.apiKeyFile != null) "openrouter_key = \"file:${cfg.apiKeyFile}\""}

          [defaults.routing]
          channel = "anthropic/claude-sonnet-4"
          worker = "anthropic/claude-haiku-4.5"

          [defaults.routing.task_overrides]
          coding = "anthropic/claude-sonnet-4"
          ''}

          # ============================================================================
          # AGENTS
          # ============================================================================
          [[agents]]
          id = "default"
          name = "Spacebot"
          description = "AI agent for teams and communities"

          # ============================================================================
          # MESSAGING PLATFORMS
          # ============================================================================
          ${lib.optionalString cfg.discord.enable ''
          [messaging.discord]
          ${lib.optionalString (cfg.discord.token != null) "token = \"${cfg.discord.token}\""}
          ${lib.optionalString (cfg.discord.tokenFile != null) "token = \"file:${cfg.discord.tokenFile}\""}

          [[bindings]]
          agent_id = "default"
          channel = "discord"
          ${lib.optionalString (cfg.discord.guildId != null) "guild_id = \"${cfg.discord.guildId}\""}
          ''}

          ${lib.optionalString cfg.slack.enable ''
          [messaging.slack]
          ${lib.optionalString (cfg.slack.token != null) "token = \"${cfg.slack.token}\""}
          ${lib.optionalString (cfg.slack.tokenFile != null) "token = \"file:${cfg.slack.tokenFile}\""}

          [[bindings]]
          agent_id = "default"
          channel = "slack"
          ''}

          ${lib.optionalString cfg.telegram.enable ''
          [messaging.telegram]
          ${lib.optionalString (cfg.telegram.token != null) "token = \"${cfg.telegram.token}\""}
          ${lib.optionalString (cfg.telegram.tokenFile != null) "token = \"file:${cfg.telegram.tokenFile}\""}

          [[bindings]]
          agent_id = "default"
          channel = "telegram"
          ''}

          # ============================================================================
          # ADVANCED CONFIGURATION
          # ============================================================================
          [database]
          path = "/data/spacebot.db"

          [secrets]
          path = "/data/secrets.redb"

          [memory.lance]
          path = "/data/lance"

          [ingestion]
          path = "/data/ingest"

          [skills]
          path = "/data/skills"
          EOF
          fi
        '';

        ExecStart = pkgs.writeShellScript "spacebot-run" ''
          # Run Spacebot container with Podman
          exec ${pkgs.podman}/bin/podman run \
            --name spacebot \
            --rm \
            --replace \
            --cgroup-manager=systemd \
            --sdnotify=conmon \
            --security-opt label=disable \
            --network slirp4netns:allow_host_loopback=true \
            -p ${cfg.host}:${toString cfg.port}:19898 \
            -v ${cfg.dataDir}:/data:Z \
            -v ${cfg.dataDir}/config.toml:/data/config.toml:ro,Z \
            -e SPACEBOT_DATA_DIR=/data \
            ${lib.optionalString (cfg.discord.token != null) "-e DISCORD_BOT_TOKEN=${cfg.discord.token}"} \
            ${lib.optionalString (cfg.slack.token != null) "-e SLACK_BOT_TOKEN=${cfg.slack.token}"} \
            ${lib.optionalString (cfg.telegram.token != null) "-e TELEGRAM_BOT_TOKEN=${cfg.telegram.token}"} \
            --memory=${cfg.memory} \
            --cpus=${cfg.cpu} \
            --hostname spacebot \
            ${cfg.image}
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop spacebot";

        # Resource management
        MemoryMax = cfg.memory;
        CPUQuota = "${cfg.cpu}"; # Multiplied by 100% (e.g., "2" = 200%)

        # Security
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.dataDir];

        # Restart policy
        Restart = "on-failure";
        RestartSec = "10s";

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "spacebot";
      };
    };

    # ============================================================================
    # FIREWALL
    # ============================================================================
    networking.firewall.allowedTCPPorts = [
      cfg.port
    ];

    # ============================================================================
    # SPACEBOT CLI WRAPPER
    # ============================================================================
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "spacebot" ''
        # Spacebot CLI wrapper - executes commands inside the running container
        set -euo pipefail

        CONTAINER_NAME="spacebot"

        # Check if container is running
        if ! ${pkgs.podman}/bin/podman ps --format "{{.Names}}" | grep -q "^''${CONTAINER_NAME}$"; then
          echo "Error: Spacebot container is not running"
          echo "Start it with: sudo systemctl start spacebot"
          exit 1
        fi

        # If no arguments, show help
        if [ $# -eq 0 ]; then
          echo "Spacebot CLI - Interface to running Spacebot container"
          echo ""
          echo "Usage: spacebot <command> [args...]"
          echo ""
          echo "Common commands:"
          echo "  spacebot status              Show container and agent status"
          echo "  spacebot logs                Show container logs"
          echo "  spacebot restart             Restart the container"
          echo "  spacebot stop                Stop the container"
          echo "  spacebot config              Show/edit configuration"
          echo "  spacebot skill list          List installed skills"
          echo "  spacebot skill add <repo>    Install a skill from skills.sh"
          echo "  spacebot shell               Open shell in container"
          echo ""
          echo "Advanced (executed in container):"
          echo "  spacebot <any-spacebot-cmd>  Pass command to spacebot binary"
          exit 0
        fi

        # Special commands handled locally
        case "$1" in
          status)
            echo "=== Spacebot Container Status ==="
            ${pkgs.podman}/bin/podman ps --filter "name=spacebot" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            echo ""
            echo "=== Service Status ==="
            ${pkgs.systemd}/bin/systemctl is-active spacebot && echo "✓ Service is active" || echo "✗ Service is inactive"
            echo ""
            echo "=== Web UI ==="
            echo "http://localhost:19898"
            ;;
          logs)
            ${pkgs.podman}/bin/podman logs -f spacebot
            ;;
          restart)
            echo "Restarting Spacebot..."
            ${pkgs.systemd}/bin/systemctl restart spacebot
            echo "Done. Check status with: spacebot status"
            ;;
          stop)
            echo "Stopping Spacebot..."
            ${pkgs.systemd}/bin/systemctl stop spacebot
            echo "Done. Start with: sudo systemctl start spacebot"
            ;;
          config)
            echo "Spacebot configuration: /var/lib/spacebot/config.toml"
            echo ""
            echo "To edit:"
            echo "  1. Stop Spacebot: sudo systemctl stop spacebot"
            echo "  2. Edit config: sudo nano /var/lib/spacebot/config.toml"
            echo "  3. Start Spacebot: sudo systemctl start spacebot"
            echo ""
            echo "View current config (first 50 lines):"
            ${pkgs.coreutils}/bin/head -n 50 /var/lib/spacebot/config.toml 2>/dev/null || echo "Config not found - will be auto-generated on first start"
            ;;
          shell)
            echo "Opening shell in Spacebot container..."
            exec ${pkgs.podman}/bin/podman exec -it spacebot /bin/sh
            ;;
          *)
            # Pass all other commands to spacebot binary in container
            exec ${pkgs.podman}/bin/podman exec -it spacebot spacebot "$@"
            ;;
        esac
      '')
    ];

    # ============================================================================
    # DATA DIRECTORY
    # ============================================================================
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root - -"
      "d ${cfg.dataDir}/data 0700 root root - -"
      "d ${cfg.dataDir}/ingest 0700 root root - -"
      "d ${cfg.dataDir}/skills 0700 root root - -"
    ];

    # ============================================================================
    # MONITORING INTEGRATION
    # ============================================================================
    # Note: Spacebot exposes metrics at /metrics on port 19898
    # Add to your Prometheus scrapeConfigs manually if needed:
    # services.monitoring.prometheus.scrapeConfigs = [
    #   {
    #     job_name = "spacebot";
    #     static_configs = [{
    #       targets = ["${cfg.host}:${toString cfg.port}"];
    #     }];
    #     metrics_path = "/metrics";
    #   }
    # ];
  };
}
