# SpaceBot NixOS Module
# Runs SpaceBot in a Podman container with Z.ai (GLM) configuration
# https://github.com/spacedriveapp/spacebot
#
# Uses containerized deployment for:
# - Official container image (ghcr.io/spacedriveapp/spacebot:latest)
# - Proper secret handling via agenix
# - Z.ai Coding Plan integration with optimized model routing
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.spacebot-podman;

  # Wrapper script to read secret and start container
  spacebotStartScript = pkgs.writeShellScript "spacebot-start" ''
    set -e

    # Read API key from agenix path
    API_KEY=$(cat "${cfg.llm.apiKey}")

    # Extract just the key value if the file contains "KEY=value" format
    if [[ "$API_KEY" == *"="* ]]; then
      API_KEY=$(echo "$API_KEY" | cut -d= -f2)
    fi

    # Ensure podman is ready
    ${pkgs.podman}/bin/podman system prune -f 2>/dev/null || true

    # Start the container with all environment variables
    # SpaceBot reads zai_coding_plan_key from ZAI_CODING_PLAN_KEY env var
    exec ${pkgs.podman}/bin/podman run \
      --name spacebot \
      --log-driver=journald \
      --cgroups=enabled \
      --sdnotify=conmon \
      -d \
      --replace \
      -p ${cfg.host}:${toString cfg.port}:19898 \
      -v ${cfg.dataDir}:/data:Z \
      -v /etc/spacebot-config.toml:/config.toml:ro,Z \
      ${lib.concatStringsSep " " (map (path: "-v ${path}:${path}:Z") cfg.projectPaths)} \
      -e RUST_LOG=spacebot=info \
      -e SPACEBOT_HOSTNAME=${lib.escapeShellArg (cfg.extraEnvironment.SPACEBOT_HOSTNAME or "zephyr.local")} \
      -e ZAI_CODING_PLAN_KEY="$API_KEY" \
      ${lib.optionalString (cfg.discordToken != null) "-e DISCORD_BOT_TOKEN=${lib.escapeShellArg cfg.discordToken}"} \
      ${lib.optionalString (cfg.slackToken != null) "-e SLACK_TOKEN=${lib.escapeShellArg cfg.slackToken}"} \
      ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "-e ${lib.escapeShellArg k}=${lib.escapeShellArg v}") cfg.extraEnvironment)} \
      ${cfg.image}
  '';

  spacebotStopScript = pkgs.writeShellScript "spacebot-stop" ''
    ${pkgs.podman}/bin/podman stop -t 10 spacebot || true
    ${pkgs.podman}/bin/podman rm spacebot || true
  '';
in {
  options.services.spacebot-podman = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SpaceBot using Podman.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/spacedriveapp/spacebot:latest";
      description = "Container image to use for SpaceBot.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Host address to bind SpaceBot to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 19898;
      description = "Port for SpaceBot web interface.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall for SpaceBot port.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/spacebot";
      description = "Directory for SpaceBot data.";
    };

    # LLM Configuration
    llm = {
      provider = lib.mkOption {
        type = lib.types.enum ["anthropic" "openai" "openrouter" "z-ai"];
        default = "anthropic";
        description = "LLM provider. For Z.ai, use 'anthropic' with baseURL='https://api.z.ai/api/anthropic'.";
      };

      apiKey = lib.mkOption {
        type = lib.types.str;
        description = "LLM API key (use agenix for secrets). For Z.ai, use zhipu-api-key secret.";
      };

      baseURL = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "https://api.z.ai/api/anthropic";
        description = "Custom base URL. Z.ai international: https://api.z.ai/api/anthropic";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "glm-4.7"; # Z.ai GLM Coding Plan Max
        description = "Model to use. Z.ai models: glm-5, glm-4.7, glm-4.7-flash, glm-4.6v, glm-4.5-air";
      };
    };

    # Discord (optional)
    discordToken = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Discord bot token.";
    };

    # Slack (optional)
    slackToken = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Slack bot token.";
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Extra environment variables.";
    };

    projectPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of paths to mount into the container for agent access (e.g., projects, nixos config).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable Podman with full configuration
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
      # Create required directories
      extraPackages = [pkgs.crun];
    };

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root - -"
      "d ${cfg.dataDir}/agents 0755 root root - -"
      "d ${cfg.dataDir}/agents/* 0755 j_kro users - -"
      "z ${cfg.dataDir}/agents/*/* 0644 j_kro users - -"
      # Podman runtime directories
      "d /var/lib/containers 0755 root root - -"
      "d /run/containers 0755 root root - -"
      "d /run/libpod 0755 root root - -"
    ];

    # Generate SpaceBot config.toml with Z.ai native configuration
    # Optimized routing:
    # - glm-4.5-air for speed (channel, worker, compactor) - real-time interactions
    # - glm-4.7 for quality (branch) - complex reasoning
    # - glm-5 for async background work (cortex) - memory & thinking
    environment.etc."spacebot-config.toml".text = ''
      [api]
      bind = "::"

      [llm]
      zai_coding_plan_key = "env:ZAI_CODING_PLAN_KEY"

      [[agents]]
      id = "main"
      default = true

      [agents.routing]
      channel = "zai-coding-plan/glm-4.5-air"
      branch = "zai-coding-plan/glm-4.7"
      worker = "zai-coding-plan/glm-4.5-air"
      compactor = "zai-coding-plan/glm-4.5-air"
      cortex = "zai-coding-plan/glm-5"

      [defaults.routing]
      channel = "zai-coding-plan/glm-4.5-air"
      branch = "zai-coding-plan/glm-4.7"
      worker = "zai-coding-plan/glm-4.5-air"
      compactor = "zai-coding-plan/glm-4.5-air"
      cortex = "zai-coding-plan/glm-5"
    '';

    # Firewall
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

    # Custom systemd service for SpaceBot
    systemd.services.spacebot-podman = {
      description = "SpaceBot AI Operating System";
      after = ["network-online.target" "podman.service" "agenix.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      requires = ["podman.service"];

      path = [pkgs.podman pkgs.crun];

      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";

        ExecStart = spacebotStartScript;
        ExecStop = spacebotStopScript;

        Restart = "on-failure";
        RestartSec = "10s";

        # Less restrictive sandboxing for container runtime
        PrivateTmp = true;
        ProtectSystem = "no"; # Allow writing to /var/lib/containers
        ProtectHome = false; # Allow reading from home for project paths

        # Runtime directory
        RuntimeDirectory = "spacebot";
        RuntimeDirectoryMode = "0750";
      };
    };
  };
}
