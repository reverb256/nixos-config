# Spacebot AI Agent - Podman Deployment
# Multi-agent AI system for teams with Discord, Slack, Telegram integration
# Integrates with existing AI Gateway at http://127.0.0.1:8080
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.spacebot;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    literalExpression
    ;
in
{
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
      after = [
        "network-online.target"
        "podman.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";

        # Use podman to run the container
        ExecStartPre = pkgs.writeShellScript "spacebot-prep" ''
                                        # Create data directory
                                        mkdir -p ${cfg.dataDir}/{data,ingest,skills}
                                        chmod 700 ${cfg.dataDir}

                                        # Create Podman container storage directory (required for ReadWritePaths)
                                        mkdir -p /var/lib/containers
                                        chmod 700 /var/lib/containers

                                        # Pull latest image
                                        ${pkgs.podman}/bin/podman pull ${cfg.image}

          # Generate config.toml if it doesn't exist
                                         if [ ! -f ${cfg.dataDir}/config.toml ]; then
                                           # Build config using Nix string interpolation
                                           cat > ${cfg.dataDir}/config.toml <<EOF
          # Spacebot Configuration - Auto-generated by NixOS
          # Modify this file to customize your agent
          ${
            if cfg.useGateway then
              "# ============================================================================\n# LLM PROVIDER - Using AI Gateway\n# ============================================================================\n[llm.provider.ai-gateway]\napi_type = \"openai_completions\"\nbase_url = \"${cfg.gatewayUrl}\"  # Spacebot appends /v1 automatically\napi_key = \"${
                if cfg.apiKey != null then
                  cfg.apiKey
                else if cfg.apiKeyFile != null then
                  "file:${cfg.apiKeyFile}"
                else
                  "dummy-key-for-gateway"
              }\"\nname = \"AI Gateway\"\n\n# ============================================================================\n# MODEL ROUTING - Using gateway model names\n# ============================================================================\n[defaults.routing]\nchannel = \"magnum-opus-35b-a3b-i1\"\nworker = \"magnum-opus-35b-a3b-i1\"\n\n[defaults.routing.task_overrides]\ncoding = \"magnum-opus-35b-a3b-i1\"\n"
            else
              ""
          }
          ${
            if (!cfg.useGateway && (cfg.apiKey != null || cfg.apiKeyFile != null)) then
              "[llm]\n"
              + (if cfg.apiKey != null then "openrouter_key = \"${cfg.apiKey}\"\n" else "")
              + (if cfg.apiKeyFile != null then "openrouter_key = \"file:${cfg.apiKeyFile}\"\n" else "")
              + "\n[defaults.routing]\nchannel = \"anthropic/claude-sonnet-4\"\nworker = \"anthropic/claude-haiku-4.5\"\n\n[defaults.routing.task_overrides]\ncoding = \"anthropic/claude-sonnet-4\"\n"
            else
              ""
          }
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
          ${
            if cfg.discord.enable then
              "[messaging.discord]\n"
              + (if cfg.discord.token != null then "token = \"${cfg.discord.token}\"\n" else "")
              + (if cfg.discord.tokenFile != null then "token = \"file:${cfg.discord.tokenFile}\"\n" else "")
              + "\n[[bindings]]\nagent_id = \"default\"\nchannel = \"discord\"\n"
              + (if cfg.discord.guildId != null then "guild_id = \"${cfg.discord.guildId}\"\n" else "")
            else
              ""
          }
          ${
            if cfg.slack.enable then
              "[messaging.slack]\n"
              + (if cfg.slack.token != null then "token = \"${cfg.slack.token}\"\n" else "")
              + (if cfg.slack.tokenFile != null then "token = \"file:${cfg.slack.tokenFile}\"\n" else "")
              + "\n[[bindings]]\nagent_id = \"default\"\nchannel = \"slack\"\n"
            else
              ""
          }
          ${
            if cfg.telegram.enable then
              "[messaging.telegram]\n"
              + (if cfg.telegram.token != null then "token = \"${cfg.telegram.token}\"\n" else "")
              + (if cfg.telegram.tokenFile != null then "token = \"file:${cfg.telegram.tokenFile}\"\n" else "")
              + "\n[[bindings]]\nagent_id = \"default\"\nchannel = \"telegram\"\n"
            else
              ""
          }
          # ============================================================================
          # API SERVER
          # ============================================================================
          [api]
          bind = "0.0.0.0"
          port = 19898

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
          # Use Podman CLI options to set storage paths within Spacebot's data directory
          export PATH="${pkgs.podman}/bin:${pkgs.slirp4netns}/bin:$PATH"

          exec ${pkgs.podman}/bin/podman run \
            --root ${cfg.dataDir}/podman-storage \
            --runroot ${cfg.dataDir}/podman-run \
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
        CPUQuota = "${cfg.cpu}00%"; # Format: percentage (e.g., "2" = 200%)

        # Security
        NoNewPrivileges = true;
        PrivateTmp = true;
        # ProtectSystem disabled - incompatible with Podman's dynamic storage needs
        # ProtectHome = true;
        ReadWritePaths = [
          cfg.dataDir
          "/var/lib/containers"
          "/run/containers"
          "/etc/containers"
        ];

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
    # Note: environment.systemPackages causes conflicts when defined in modules
    # These packages should be added to the main configuration instead
    # environment.systemPackages = with pkgs; [
    #   slirp4netns  # Required for Podman networking
    #   (pkgs.writeShellScriptBin "spacebot" '' ... '')
    # ];

    # ============================================================================
    # DATA DIRECTORY
    # ============================================================================
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root - -"
      "d ${cfg.dataDir}/data 0700 root root - -"
      "d ${cfg.dataDir}/ingest 0700 root root - -"
      "d ${cfg.dataDir}/skills 0700 root root - -"
      "d ${cfg.dataDir}/podman-storage 0700 root root - -"
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
