{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.services.hermes-agent;
  hermesPackage = import ./package.nix { inherit pkgs lib config; };
in
{
  imports = [
    ./health-check.nix
    ./monitor.nix
    ./mcp-integration.nix
  ];
  options.services.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent - self-improving AI agent";

    packageSrc = lib.mkOption {
      type = lib.types.path;
      default = inputs.hermes-agent;
      defaultText = "inputs.hermes-agent";
      description = "Hermes agent source";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "User account for Hermes Agent";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "Group for Hermes Agent";
    };

    sharedStorage = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable NFS shared storage for skills/memory";
      };

      mountPoint = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/hermes";
        description = "Mount point for shared Hermes data";
      };

      nfsServer = lib.mkOption {
        type = lib.types.str;
        example = "10.1.1.120";
        description = "NFS server address";
      };

      nfsPath = lib.mkOption {
        type = lib.types.str;
        example = "/mnt/garage/hermes";
        description = "NFS export path";
      };
    };

    aiGateway = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Connect to local AI Inference Gateway";
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:8080/v1";
        description = "AI Gateway URL (OpenAI-compatible)";
      };
    };

    terminal = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable terminal tool access";
      };

      requireApproval = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Require user approval for terminal commands";
      };

      allowedCommands = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = "Allow-list of commands (null = allow all)";
      };
    };

    customSkills = lib.mkOption {
      type = lib.types.path;
      default = ./skills;
      defaultText = "./skills";
      description = "Path to custom NixOS-specific skills";
    };

    activeSkillsCount = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Number of active skills loaded (for metrics)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = lib.mkIf (cfg.user == "hermes") {
      isNormalUser = true;
      createHome = true;
      home = cfg.sharedStorage.mountPoint;
      group = cfg.group;
      extraGroups = [
        "wheel"
        "video"
        "render"
      ];
      shell = pkgs.fish;
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "hermes") { };

    # System packages - direct list assignment merges with host config by default
    # Note: Using direct assignment instead of mkOptionDefault because we want
    # these packages to merge with, not be overridden by, host packages
    environment.systemPackages = [
      hermesPackage
      pkgs.ripgrep # For file search
      pkgs.ffmpeg # For TTS
    ];

    # NFS mount for shared storage
    systemd.mounts = lib.mkIf cfg.sharedStorage.enable [
      {
        where = cfg.sharedStorage.mountPoint;
        what = "${cfg.sharedStorage.nfsServer}:${cfg.sharedStorage.nfsPath}";
        type = "nfs";
        options = "nofail,_netdev,hard,intr,timeo=600";
        wantedBy = [ "multi-user.target" ];
      }
    ];

    # Environment variables
    environment.sessionVariables = lib.mkIf cfg.aiGateway.enable {
      HERMES_AI_GATEWAY_URL = cfg.aiGateway.url;
      OPENAI_API_KEY = "not-needed";
      OPENAI_BASE_URL = cfg.aiGateway.url;
    };

    # Systemd service for Hermes Agent
    systemd.services.hermes-agent = {
      description = "Hermes Agent - Self-improving AI Agent";
      after = lib.mkMerge [
        [
          "network-online.target"
          "multi-user.target"
        ]
        (lib.mkIf cfg.aiGateway.enable [ "ai-inference-gateway.service" ])
      ];
      wants = [
        "network-online.target"
      ]
      ++ lib.optionals cfg.aiGateway.enable [ "ai-inference-gateway.service" ];
      requires = lib.optionals cfg.aiGateway.enable [ "ai-inference-gateway.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HERMES_AI_GATEWAY_URL = lib.mkIf cfg.aiGateway.enable cfg.aiGateway.url;
        OPENAI_API_KEY = "not-needed";
        OPENAI_BASE_URL = lib.mkIf cfg.aiGateway.enable cfg.aiGateway.url;
        HERMES_CUSTOM_SKILLS = cfg.customSkills;
        HERMES_SHARED_STORAGE = lib.mkIf cfg.sharedStorage.enable cfg.sharedStorage.mountPoint;
      };

      serviceConfig = {
        ExecStart = "${hermesPackage}/bin/hermes gateway run";
        Restart = "on-failure";
        RestartSec = "10s";
        User = cfg.user;
        Group = cfg.group;

        # Allow hermes to run terminal commands
        PrivateDevices = false;
        PrivateNetwork = false; # Needs network for AI Gateway

        # Allow access to user's X11 session for GUI apps
        Display = ":0";

        # Security settings
        NoNewPrivileges = false; # Hermes needs elevated privileges for some tasks
        ProtectSystem = "strict";
        ProtectHome = false; # Needs access to home directory

        # Resource limits
        MemoryMax = "4G";
        CPUWeight = 100;

        # Allow access to temp directories
        ReadWritePaths = [
          "/tmp"
          "/var/tmp"
        ];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "hermes-agent";
      };
    };
  };
}
