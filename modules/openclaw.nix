{ config, lib, pkgs, inputs, ... }:

with lib;

let
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
      default = "openclaw";
      description = "User to run OpenClaw service as";
    };

    group = mkOption {
      type = types.str;
      default = "openclaw";
      description = "Group to run OpenClaw service as";
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

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra arguments to pass to OpenClaw gateway";
      example = [ "--debug" "--port 8080" ];
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing environment variables for OpenClaw";
      example = "/run/agenix/openclaw-env";
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = "OpenClaw configuration settings";
      example = {
        telegram = {
          botTokenFile = "/run/agenix/telegram-bot-token";
          allowFrom = [ 123456789 ];
        };
        anthropic = {
          apiKeyFile = "/run/agenix/anthropic-api-key";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users = mkIf (cfg.user == "openclaw") {
      openclaw = {
        isSystemUser = true;
        group = cfg.group;
        description = "OpenClaw AI agent service user";
        home = cfg.stateDir;
        createHome = true;
      };
    };

    users.groups = mkIf (cfg.group == "openclaw") {
      openclaw = {};
    };

    # Create directories
    systemd.tmpfiles.settings.openclaw = {
      "${cfg.stateDir}" = {
        d = {
          user = cfg.user;
          group = cfg.group;
          mode = "0750";
        };
      };
      "${cfg.configDir}" = {
        d = {
          user = "root";
          group = cfg.group;
          mode = "0750";
        };
      };
    };

    # Generate configuration file
    environment.etc."openclaw/openclaw.json".source = 
      pkgs.writeText "openclaw.json" (builtins.toJSON cfg.settings);

    # Systemd service
    systemd.services.openclaw = {
      description = "OpenClaw AI Agent Gateway";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        RestartSec = "5s";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.stateDir ];
        ReadOnlyPaths = [ cfg.configDir ];

        # Environment
        Environment = [
          "OPENCLAW_NIX_MODE=1"
          "OPENCLAW_STATE_DIR=${cfg.stateDir}"
          "OPENCLAW_CONFIG_PATH=${cfg.configDir}/openclaw.json"
        ];

        # Command
        ExecStart = escapeShellArgs (
          [ "${cfg.package}/bin/openclaw-gateway" ] ++ cfg.extraArgs
        );

        # Load environment file if provided (for secrets)
        EnvironmentFile = mkIf (cfg.environmentFile != null) [ cfg.environmentFile ];
      };

      # Write the configuration file before starting
      preStart = ''
        # Ensure state directory exists with correct permissions
        mkdir -p ${cfg.stateDir}
        chown ${cfg.user}:${cfg.group} ${cfg.stateDir}
        chmod 0750 ${cfg.stateDir}

        # Create workspace directory structure
        mkdir -p ${cfg.stateDir}/workspace
        mkdir -p ${cfg.stateDir}/workspace/skills
        chown -R ${cfg.user}:${cfg.group} ${cfg.stateDir}/workspace
      '';
    };

    # Add OpenClaw packages to system profile (for CLI tools)
    environment.systemPackages = with pkgs; [
      cfg.package
      inputs.nix-openclaw.packages.x86_64-linux.openclaw-tools or cfg.package
    ];
  };

}