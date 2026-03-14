# Garage S3-compatible object storage
# Distributed object storage for cluster
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.garage-cluster;
  hostIp = config.networking.cluster.hosts.${config.networking.hostName}.ip or "127.0.0.1";
in {
  options.services.garage-cluster = {
    enable = lib.mkEnableOption "Garage S3-compatible object storage";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/garage";
      description = "Directory for Garage data";
    };

    replicationFactor = lib.mkOption {
      type = lib.types.ints.between 1 10;
      default = 2;
      description = "Replication factor for data redundancy (1-10, must be same on all nodes)";
    };

    consistencyMode = lib.mkOption {
      type = lib.types.enum ["consistent" "degraded" "dangerous"];
      default = "consistent";
      description = "Consistency mode: consistent, degraded, or dangerous";
    };

    rpcPort = lib.mkOption {
      type = lib.types.port;
      default = 3901;
      description = "RPC port for cluster communication";
    };

    s3ApiPort = lib.mkOption {
      type = lib.types.port;
      default = 3900;
      description = "S3 API port";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 3902;
      description = "Web interface port (also serves metrics)";
    };

    rpcSecret = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Shared RPC secret for cluster authentication (must be 32 hex chars)";
    };

    enableMetrics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Prometheus metrics export";
    };

    enableBackup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automated metadata backups";
    };

    backupDir = lib.mkOption {
      type = lib.types.path;
      default = "/data/shared/garage-backups";
      description = "Directory for metadata backups (should be on NFS/shared storage)";
    };

    backupInterval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Systemd timer calendar format for backup interval (default: daily)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Garage package and service
    environment.systemPackages = [pkgs.garage];

    users.users.garage = {
      group = "garage";
      description = "Garage S3 storage service";
      isSystemUser = true;
    };

    users.groups.garage = {};

    # Generate Garage config file - uses dataDir option
    environment.etc."garage.toml".text = ''
      replication_factor = ${toString cfg.replicationFactor}
      consistency_mode = "${cfg.consistencyMode}"

      metadata_dir = "${cfg.dataDir}/meta"
      data_dir = "${cfg.dataDir}/data"

      db_engine = "lmdb"

      rpc_bind_addr = "[::]:${toString cfg.rpcPort}"
      rpc_public_addr = "${hostIp}:${toString cfg.rpcPort}"
      rpc_secret = "${cfg.rpcSecret}"

      [s3_api]
      s3_region = "garage"
      api_bind_addr = "[::]:${toString cfg.s3ApiPort}"
      root_domain = ".s3.garage.cluster"

      [admin]
      api_bind_addr = "127.0.0.1:${toString cfg.webPort}"
      metrics_token = ${lib.optionalString cfg.enableMetrics "\"garage_metrics_token\""}
    '';

    # Systemd services and timers
    systemd = {
      tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 garage garage -"
        "d ${cfg.dataDir}/meta 0750 garage garage -"
        "d ${cfg.dataDir}/data 0750 garage garage -"
      ] ++ lib.optional cfg.enableBackup ''
        d ${cfg.backupDir} 0755 garage garage - -
      '';

      services = {
        garage = {
          description = "Garage S3-compatible object storage";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "simple";
            User = "garage";
            Group = "garage";

            # Security hardening
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;

            # Allow write access to custom data directory
            ReadWritePaths = ["${cfg.dataDir}"] ++ lib.optional cfg.enableBackup cfg.backupDir;

            ExecStart = "${pkgs.garage}/bin/garage -c /etc/garage.toml server";

            # Hardening
            CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
            AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
            RestrictRealtime = true;
            SystemCallFilter = ["@system-service" "~@privileged"];
            MemoryDenyWriteExecute = true;

            Restart = "always";
            RestartSec = "5s";
          };
        };

        # Automated backup service
        garage-backup = lib.mkIf cfg.enableBackup {
          description = "Garage metadata backup";
          after = ["garage.service"];
          requires = ["garage.service"];

          serviceConfig = {
            Type = "oneshot";
            User = "garage";
            Group = "garage";
            ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.garage}/bin/garage -c /etc/garage.toml meta snapshot ${cfg.backupDir}/meta-$(date +%%Y-%%m-%%d_%%H-%%M-%%S).db && cp ${cfg.dataDir}/meta/db.lmdb ${cfg.backupDir}/db.lmdb-$(date +%%Y-%%m-%%d_%%H-%%M-%%S)'";
            IOSchedulingClass = "idle";
            IOSchedulingPriority = "7";
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [cfg.backupDir cfg.dataDir];
          };
        };
      };

      timers.garage-backup = lib.mkIf cfg.enableBackup {
        description = "Daily Garage metadata backup";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = cfg.backupInterval;
          Persistent = true;
          Unit = "garage-backup.service";
        };
      };
    };

    # Firewall - use mkOptionDefault to preserve existing ports
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      cfg.rpcPort # RPC for cluster communication
      cfg.s3ApiPort # S3 API
    ];
  };
}
