{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.services.openclaw;
in {
  options.services.openclaw = {
    enable = mkEnableOption "OpenClaw AI agent gateway service";

    package = mkOption {
      type = types.package;
      default = inputs.nix-openclaw.packages.x86_64-linux.openclaw-gateway;
      defaultText = "inputs.nix-openclaw.packages.x86_64-linux.openclaw-gateway";
      description = "OpenClaw gateway package to use";
    };

    user = mkOption {
      type = types.str;
      default = "lobster";
      description = "User to run OpenClaw service as (default: lobster)";
    };

    group = mkOption {
      type = types.str;
      default = "lobster";
      description = "Group to run OpenClaw service as (default: lobster)";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw";
      description = "Directory for OpenClaw state data";
    };

    configDir = mkOption {
      type = types.str;
      default = "/etc/openclaw";
      description = "Directory for OpenClaw configuration";
    };

    port = mkOption {
      type = types.int;
      default = 18789;
      description = "Port to run OpenClaw gateway on";
    };

    restartAlways = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to restart the service always (instead of just on-failure)";
    };

    logDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Directory for OpenClaw log files (null for journald)";
      example = "/tmp/openclaw";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra arguments to pass to OpenClaw gateway";
      example = ["--debug" "--port 8080"];
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing environment variables for OpenClaw";
      example = "/run/agenix/openclaw-env";
    };

    enableLegacyEnv = mkOption {
      type = types.bool;
      default = false;
      description = "Enable legacy MOLTBOT_* and CLAWDBOT_* environment variables for backwards compatibility";
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = "OpenClaw configuration settings";
      example = {
        telegram = {
          botTokenFile = "/run/agenix/telegram-bot-token";
          allowFrom = [123456789];
        };
        anthropic = {
          apiKeyFile = "/run/agenix/anthropic-api-key";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Create user and group with low priority (allows override from users.nix)
    users.users = mkIf (cfg.user == "lobster") {
      lobster = mkDefault {
        isSystemUser = true;
        group = cfg.group;
        description = "OpenClaw AI agent bot user (lobster)";
        home = cfg.stateDir;
        createHome = true;
        shell = pkgs.bash;
      };
    };

    users.groups = mkIf (cfg.group == "lobster") {
      lobster = {};
    };

    # Create directories
    systemd.tmpfiles.rules =
      [
        "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
        "d ${cfg.configDir} 0750 root ${cfg.group} -"
        "d ${cfg.stateDir}/workspace 0750 ${cfg.user} ${cfg.group} -"
        "d ${cfg.stateDir}/workspace/skills 0750 ${cfg.user} ${cfg.group} -"
      ]
      ++ (
        if cfg.logDir != null
        then [
          "d ${cfg.logDir} 0755 ${cfg.user} ${cfg.group} -"
        ]
        else []
      );

    # Generate configuration file
    environment.etc."openclaw/openclaw.json".source =
      pkgs.writeText "openclaw.json" (builtins.toJSON cfg.settings);

    # Systemd service
    systemd.services.openclaw = {
      description = "OpenClaw AI Agent Gateway";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        Restart =
          if cfg.restartAlways
          then "always"
          else "on-failure";
        RestartSec = "1s";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths =
          [cfg.stateDir]
          ++ (
            if cfg.logDir != null
            then [cfg.logDir]
            else []
          );
        ReadOnlyPaths = [cfg.configDir];

        # Logging (file-based or journald)
        StandardOutput =
          if cfg.logDir != null
          then "append:${cfg.logDir}/openclaw-gateway.log"
          else "journal";
        StandardError =
          if cfg.logDir != null
          then "append:${cfg.logDir}/openclaw-gateway.log"
          else "journal";

        # Environment
        Environment =
          [
            "OPENCLAW_NIX_MODE=1"
            "OPENCLAW_STATE_DIR=${cfg.stateDir}"
            "OPENCLAW_CONFIG_PATH=${cfg.configDir}/openclaw.json"
            "HOME=${cfg.stateDir}"
            # Add NODE_PATH for pnpm dependencies
            "NODE_PATH=${cfg.package}/lib/openclaw/node_modules:${cfg.package}/lib/openclaw/node_modules/.pnpm/node_modules"
          ]
          ++ (
            if cfg.enableLegacyEnv
            then [
              # Legacy environment variables for backwards compatibility
              "MOLTBOT_NIX_MODE=1"
              "MOLTBOT_STATE_DIR=${cfg.stateDir}"
              "MOLTBOT_CONFIG_PATH=${cfg.configDir}/openclaw.json"
              "CLAWDBOT_NIX_MODE=1"
              "CLAWDBOT_STATE_DIR=${cfg.stateDir}"
              "CLAWDBOT_CONFIG_PATH=${cfg.configDir}/openclaw.json"
            ]
            else []
          );

        # Command with port
        ExecStart = escapeShellArgs (
          ["${cfg.package}/bin/openclaw" "gateway" "--port" (toString cfg.port)] ++ cfg.extraArgs
        );

        # Load environment file if provided (for secrets)
        EnvironmentFile = mkIf (cfg.environmentFile != null) [cfg.environmentFile];
      };

      # Write the configuration file before starting
      preStart = ''
        # Ensure state directory exists with correct permissions
        # Note: Directories are created by systemd.tmpfiles.rules with correct ownership
        mkdir -p ${cfg.stateDir}
        mkdir -p ${cfg.stateDir}/workspace
        mkdir -p ${cfg.stateDir}/workspace/skills

        ${
          if cfg.logDir != null
          then ''
            # Ensure log directory exists
            mkdir -p ${cfg.logDir}
          ''
          else "# Using journald for logging (no log directory needed)"
        }
      '';
    };

    # Add OpenClaw packages to system profile (for CLI tools)
    environment.systemPackages = with pkgs; [
      cfg.package
      inputs.nix-openclaw.packages.x86_64-linux.openclaw-tools or cfg.package
    ];

    # Health monitoring timer
    systemd.services.openclaw-health = {
      description = "OpenClaw Gateway Health Check";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "openclaw-health-check" ''
          set -e
          # Check if OpenClaw gateway is responding
          if ! ${pkgs.curl}/bin/curl -sf "http://127.0.0.1:${toString cfg.port}/health" >/dev/null 2>&1; then
            echo "OpenClaw gateway health check failed"
            # Try to restart the service if it's not responding
            ${pkgs.systemd}/bin/systemctl restart openclaw.service || true
            exit 1
          fi
          exit 0
        '';
      };
    };

    systemd.timers.openclaw-health = {
      description = "Periodic health check for OpenClaw gateway";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*:*:0/30"; # Every 30 seconds
        Persistent = false;
      };
    };
  };
}
