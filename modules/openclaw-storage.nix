{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.services.openclaw-storage;
in {
  options.services.openclaw-storage = {
    enable = lib.mkEnableOption "OpenClaw Storage MCP - AI data management with natural language";

    port = lib.mkOption {
      type = lib.types.port;
      default = 18800;
      description = "Port for OpenClaw Storage MCP server";
    };

    aistorEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://10.1.1.120:9000";
      description = "AIStor S3 endpoint";
    };

    aistorCredentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to AIStor credentials file";
    };

    rcloneConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to rclone config for cloud backups";
    };

    buckets = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        models = "ai-models";
        datasets = "training-data";
        experiments = "experiments";
        logs = "ai-logs";
        cache = "nix-cache";
      };
      description = "Bucket names for different data types";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "lobster";
      description = "User to run the service (default: lobster - the OpenClaw bot user)";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.aistorCredentialsFile != null;
        message = "OpenClaw Storage: aistorCredentialsFile must be set (use agenix secrets)";
      }
    ];

    # Create lobster user if needed (shared with openclaw.nix)
    users.users = lib.mkIf (cfg.user == "lobster") {
      lobster = {
        isSystemUser = true;
        group = "lobster";
        description = "OpenClaw AI Agent Bot User (lobster)";
        home = "/var/lib/lobster";
        createHome = true;
        shell = pkgs.bash;
        extraGroups = [ "rclone" ];  # Access to rclone config
      };
    };

    users.groups = lib.mkIf (cfg.user == "lobster") {
      lobster = {};
    };

    # Create state directory (scoped under lobster home)
    systemd.tmpfiles.settings.openclaw-storage = {
      "/var/lib/lobster/storage" = {
        d = {
          user = cfg.user;
          group = cfg.user;
          mode = "0750";
        };
      };
      "/var/lib/lobster/storage/metrics" = {
        d = {
          user = cfg.user;
          group = cfg.user;
          mode = "0750";
        };
      };
      "/var/lib/lobster/storage/artifacts" = {
        d = {
          user = cfg.user;
          group = cfg.user;
          mode = "0750";
        };
      };
      "/var/lib/lobster/storage/cache" = {
        d = {
          user = cfg.user;
          group = cfg.user;
          mode = "0750";
        };
      };
    };

    # OpenClaw Storage MCP Server
    systemd.services.openclaw-storage = {
      description = "OpenClaw Storage MCP - AI Data Management";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.user;
        Restart = "on-failure";
        RestartSec = "5s";
        WorkingDirectory = "/var/lib/openclaw-storage";

        Environment = [
          "AISTOR_ENDPOINT=${cfg.aistorEndpoint}"
          "STORAGE_PORT=${toString cfg.port}"
          "BUCKET_MODELS=${cfg.buckets.models}"
          "BUCKET_DATASETS=${cfg.buckets.datasets}"
          "BUCKET_EXPERIMENTS=${cfg.buckets.experiments}"
          "BUCKET_LOGS=${cfg.buckets.logs}"
          "BUCKET_CACHE=${cfg.buckets.cache}"
        ];

        EnvironmentFile = lib.mkIf (cfg.aistorCredentialsFile != null) [
          cfg.aistorCredentialsFile
        ];

        ExecStart = "${pkgs.python3}/bin/python3 ${./openclaw-storage-mcp.py} --port ${toString cfg.port}";
      };
    };

    # Firewall
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
