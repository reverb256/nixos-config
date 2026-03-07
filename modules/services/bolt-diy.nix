# bolt.diy - AI-Powered Full-Stack Web Development
# Open source version of Bolt.new with provider selection
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    literalExpression
    mkPackageOption
    ;

  cfg = config.services.bolt-diy;

  # Domain for bolt.diy (accessible from Tailscale/network)
  domain = "bolt-diy.local";

  # State directory for persistent data
  stateDir = "/var/lib/bolt-diy";
in {
  options.services.bolt-diy = {
    enable = mkEnableOption "bolt.diy - AI-powered full-stack web development IDE";

    package = mkPackageOption pkgs "bolt-diy" {
      default = [];
      # We'll build the container image from source
    };

    # Container configuration
    container = {
      image = mkOption {
        type = types.str;
        default = "ghcr.io/stackblitz-labs/bolt.diy:latest";
        description = "Container image to use for bolt.diy";
      };

      port = mkOption {
        type = types.port;
        default = 5173;
        description = "Port for bolt.diy web interface";
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
        description = "CPU quota for the container";
      };
    };

    # AI Provider Configuration
    # bolt.diy supports 19+ providers - we configure for local gateway
    provider = {
      type = mkOption {
        type = types.enum [
          "openai"
          "anthropic"
          "openai-compatible"
          "ollama"
          "lm-studio"
          "custom"
        ];
        default = "openai-compatible";
        description = "AI provider type (use openai-compatible for local gateway)";
      };

      # For OpenAI-compatible backends (vLLM, LM Studio, AI Gateway)
      openaiCompatible = {
        baseUrl = mkOption {
          type = types.str;
          default = "http://127.0.0.1:8080/v1";
          description = "Base URL for OpenAI-compatible API (your AI Gateway)";
        };

        apiKey = mkOption {
          type = types.str;
          default = "bolt-diy-local";
          description = "API key for the backend (local backends often don't require real keys)";
        };

        modelName = mkOption {
          type = types.str;
          default = "qwen3.5-35b-a3b";
          description = "Default model to use";
        };
      };

      # Anthropic-style API (for CC Router at port 3456)
      anthropic = {
        baseUrl = mkOption {
          type = types.str;
          default = "http://127.0.0.1:3456/v1";
          description = "Base URL for Anthropic-compatible API (CC Router)";
        };

        apiKey = mkOption {
          type = types.str;
          default = "cc-router";
          description = "API key for Anthropic-compatible backend";
        };

        modelName = mkOption {
          type = types.str;
          default = "claude-sonnet-4.6";
          description = "Default model name";
        };
      };

      # Ollama configuration
      ollama = {
        baseUrl = mkOption {
          type = types.str;
          default = "http://127.0.0.1:11434";
          description = "Ollama API endpoint";
        };
      };
    };

    # Storage configuration
    storage = {
      projectsDir = mkOption {
        type = types.path;
        default = "${stateDir}/projects";
        description = "Directory to store bolt.diy projects";
      };

      persistWorkDir = mkOption {
        type = types.bool;
        default = true;
        description = "Persist working directory between container restarts";
      };
    };

    # Networking
    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Host address to bind to";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall for the configured port";
    };

    # Tailscale integration
    tailscale = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable access via Tailscale";
      };

      hostname = mkOption {
        type = types.str;
        default = "bolt-diy";
        description = "Hostname for Tailscale access";
      };
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # SYSTEMD SERVICE (for non-quadlet fallback)
    # ============================================================================
    # Note: Primary method is Podman Quadlet (see below)
    # This service only exists for quadlet-generated container management

    # ============================================================================
    # PODMAN QUADLET CONFIGURATION
    # ============================================================================
    # Generate quadlet files for proper systemd integration
    environment.etc."containers/systemd/bolt-diy.container".text = lib.generators.toKeyValue {} {
      Unit = {
        Description = "bolt.diy - AI-powered full-stack web development IDE";
        Documentation = "https://github.com/stackblitz-labs/bolt.diy";
        After = ["network-online.target" "ai-inference-gateway.service"];
        Wants = ["network-online.target"];
      };

      Container = {
        Image = cfg.container.image;
        ContainerName = "bolt-diy";
        PublishPort = "${toString cfg.container.port}:5173";
        Environment = builtins.concatStringsSep " " [
          "NODE_ENV=production"
          "PORT=5173"
          # Provider configuration
          "PROVIDER_TYPE=${cfg.provider.type}"
          "OPENAI_COMPATIBLE_BASE_URL=${cfg.provider.openaiCompatible.baseUrl}"
          "OPENAI_COMPATIBLE_API_KEY=${cfg.provider.openaiCompatible.apiKey}"
          "OPENAI_COMPATIBLE_MODEL_NAME=${cfg.provider.openaiCompatible.modelName}"
          "ANTHROPIC_BASE_URL=${cfg.provider.anthropic.baseUrl}"
          "ANTHROPIC_API_KEY=${cfg.provider.anthropic.apiKey}"
          "ANTHROPIC_MODEL_NAME=${cfg.provider.anthropic.modelName}"
          "OLLAMA_BASE_URL=${cfg.provider.ollama.baseUrl}"
        ];
        Volume = lib.optionalString cfg.storage.persistWorkDir
          "${cfg.storage.projectsDir}:/app/workdir:Z";
        Memory = cfg.container.memory;
        CPUQuota = cfg.container.cpu;
        # Auto-restart policy
        AutoUpdate = "registry";
        # Health check
        HealthCmd = "curl -f http://localhost:5173/ || exit 1";
        HealthInterval = "30s";
        HealthTimeout = "10s";
        HealthRetries = 3;
        # Security
        NoNewPrivileges = "true";
        ReadOnly = "false";
        # DNS for cluster integration
        DNS = lib.optionalString config.services.unbound-cluster.enable "127.0.0.1";
      };

      Service = {
        Restart = "on-failure";
        RestartSec = "10s";
      };

      Install = {
        WantedBy = ["default.target"];
      };
    };

    # ============================================================================
    # FIREWALL
    # ============================================================================
    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.container.port;

    # ============================================================================
    # TAILSCALE INTEGRATION
    # ============================================================================
    services.nginx.virtualHosts.${cfg.tailscale.hostname} = lib.mkIf cfg.tailscale.enable {
      listen = [
        {
          addr = "100.100.100.100"; # Tailscale IP
          port = 80;
        }
      ];
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.container.port}";
        proxyWebsockets = true;
      };
    };

    # ============================================================================
    # STATE DIRECTORY
    # ============================================================================
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 root root -"
      "d ${cfg.storage.projectsDir} 0755 root root -"
    ];

    # ============================================================================
    # HELPER SCRIPTS
    # ============================================================================
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "bolt-diy-logs" ''
        #!/bin/bash
        podman logs -f bolt-diy
      '')
      (writeShellScriptBin "bolt-diy-shell" ''
        #!/bin/bash
        podman exec -it bolt-diy /bin/sh
      '')
      (writeShellScriptBin "bolt-diy-restart" ''
        #!/bin/bash
        echo "Restarting bolt.diy..."
        systemctl --user restart bolt-diy.container || sudo systemctl restart bolt-diy.container
        echo "Done! Check status with: bolt-diy-logs"
      '')
      (writeShellScriptBin "bolt-diy-update" ''
        #!/bin/bash
        echo "Updating bolt.diy to latest image..."
        podman pull ${cfg.container.image}
        bolt-diy-restart
      '')
      (writeShellScriptBin "bolt-diy-backup" ''
        #!/bin/bash
        BACKUP_DIR="/var/backups/bolt-diy"
        mkdir -p "$BACKUP_DIR"
        DATE=$(date +%Y%m%d-%H%M%S)
        echo "Backing up bolt.diy projects to $BACKUP_DIR/bolt-diy-$DATE.tar.gz..."
        tar -czf "$BACKUP_DIR/bolt-diy-$DATE.tar.gz" ${cfg.storage.projectsDir}
        echo "Backup complete: $BACKUP_DIR/bolt-diy-$DATE.tar.gz"
      '')
    ];

    # ============================================================================
    # PROMETHEUS SCRAPE CONFIG (if monitoring enabled)
    # ============================================================================
    services.prometheus.scrapeConfigs = lib.optionalAttrs config.services.prometheus.enable [
      {
        job_name = "bolt-diy";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString cfg.container.port}"];
            labels = {
              instance = config.networking.hostName;
              service = "bolt-diy";
            };
          }
        ];
      }
    ];
  };
}
