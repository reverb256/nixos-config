{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.garage-cluster;
  hostIp = config.networking.cluster.hosts.${config.networking.hostName}.ip or "127.0.0.1";

  # Template with placeholders that sed will replace at runtime
  garageConfigTemplate = pkgs.writeText "garage.toml.tpl" ''
    replication_factor = ${toString cfg.replicationFactor}
    consistency_mode = "${cfg.consistencyMode}"

    metadata_dir = "${cfg.dataDir}/meta"
    data_dir = "${cfg.dataDir}/data"

    db_engine = "lmdb"

    rpc_bind_addr = "[::]:${toString cfg.rpcPort}"
    rpc_public_addr = "${hostIp}:${toString cfg.rpcPort}"
    rpc_secret = "@RPC_SECRET@"

    [s3_api]
    s3_region = "garage"
    api_bind_addr = "[::]:${toString cfg.s3ApiPort}"
    root_domain = ".s3.garage.cluster"

    [admin]
    api_bind_addr = "127.0.0.1:${toString cfg.webPort}"
    metrics_token = "@METRICS_TOKEN@"
  '';

  # Script that generates the actual config by reading secrets
  generateConfig = pkgs.writeShellScriptBin "garage-generate-config" ''
    set -euo pipefail
    rpc_secret="$(cat ${"/run/secrets/garage-rpc-secret"})"
    metrics_token="$(cat ${"/run/secrets/garage-metrics-token"})"
    sed \
      -e "s|@RPC_SECRET@|$rpc_secret|g" \
      -e "s|@METRICS_TOKEN@|$metrics_token|g" \
      ${garageConfigTemplate} > /run/garage/garage.toml
    chmod 600 /run/garage/garage.toml
  '';

  # Idempotent S3 key + bucket provisioning (2026-08-14): imports the sops
  # access key into garage if absent, then allows provisionBuckets on it.
  # Written as a script derivation to avoid ''-string nesting; the bucket
  # allow list is interpolated at build time.
  provisionScript = pkgs.writeShellScript "garage-provision-keys" ''
    set -euo pipefail
    GARAGE=${lib.getExe pkgs.garage}
    CONF=-c /run/garage/garage.toml
    ID="$(cat ${toString cfg.s3AccessKeyFile})"
    SECRET="$(cat ${toString cfg.s3SecretKeyFile})"
    if ! $GARAGE $CONF key info "$ID" >/dev/null 2>&1; then
      $GARAGE $CONF key import --name sops-s3-key "$ID" "$SECRET"
    fi
    ${builtins.concatStringsSep "\n" (map (b: "$GARAGE $CONF bucket allow --read --write --owner ${b} --key \"$ID\" || true") cfg.provisionBuckets)}
  '';
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
      type = lib.types.enum [
        "consistent"
        "degraded"
        "dangerous"
      ];
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
      description = "Directory for metadata backups (on shared storage)";
    };

    backupInterval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Systemd timer calendar format for backup interval (default: daily)";
    };

    # S3 access key provisioning (2026-08-14): the sops-nix storage secrets
    # (garage-s3-access-key-id / garage-s3-secret-key) are used by
    # backup-to-garage + rclone, but garage must have them imported as a key
    # with bucket permissions BEFORE those clients can authenticate. A oneshot
    # after garage.service imports the key idempotently (skip if present) and
    # allows each provisionBuckets entry.
    s3AccessKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "File containing the garage S3 access key id to import";
    };

    s3SecretKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "File containing the garage S3 secret key to import";
    };

    provisionBuckets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["backups"];
      description = "Buckets to allow the provisioned S3 key on";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.garage];

    users.users.garage = {
      group = "garage";
      description = "Garage S3 storage service";
      isSystemUser = true;
    };

    users.groups.garage = {};

    systemd = {
      tmpfiles.rules =
        [
          "d ${cfg.dataDir} 0750 garage garage -"
          "d ${cfg.dataDir}/meta 0750 garage garage -"
          "d ${cfg.dataDir}/data 0750 garage garage -"
        ]
        ++ lib.optional cfg.enableBackup ''
          d ${cfg.backupDir} 0755 garage garage - -
        '';

      services = {
        garage = {
          description = "Garage S3-compatible object storage";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          wantedBy = ["multi-user.target"];

          # Generate config from template + sops-nix secrets before starting Garage.
          # Secrets are read at service start, never stored in /etc.
          preStart = "${lib.getExe generateConfig}";

          serviceConfig = {
            Type = "simple";
            User = "garage";
            Group = "garage";

            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;

            ReadWritePaths =
              [
                "${cfg.dataDir}"
                "/run/garage"
              ]
              ++ lib.optional cfg.enableBackup cfg.backupDir;

            ExecStart = "${lib.getExe pkgs.garage} -c /run/garage/garage.toml server";

            # Access sops-nix secret files for config generation in preStart
            ReadOnlyPaths = [
              "/run/secrets/garage-rpc-secret"
              "/run/secrets/garage-metrics-token"
              "${garageConfigTemplate}"
            ];

            RuntimeDirectory = "garage";
            CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
            AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictRealtime = true;
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
            ];
            MemoryDenyWriteExecute = true;

            Restart = "always";
            RestartSec = "5s";
          };
        };

        garage-backup = lib.mkIf cfg.enableBackup {
          description = "Garage metadata backup";
          after = ["garage.service"];
          requires = ["garage.service"];

          serviceConfig = {
            Type = "oneshot";
            User = "garage";
            Group = "garage";
            ExecStart = "${lib.getExe' pkgs.bash "bash"} -c '${lib.getExe pkgs.garage} -c /run/garage/garage.toml meta snapshot ${cfg.backupDir}/meta-$(date +%%Y-%%m-%%d_%%H-%%M-%%S).db && cp ${cfg.dataDir}/meta/db.lmdb ${cfg.backupDir}/db.lmdb-$(date +%%Y-%%m-%%d_%%H-%%M-%%S)'";
            IOSchedulingClass = "idle";
            IOSchedulingPriority = "7";
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [
              cfg.backupDir
              cfg.dataDir
            ];
          };
        };

        # Idempotent S3 key + bucket provisioning. Runs after garage starts;
        # imports the sops S3 access key if not already present and allows the
        # configured buckets on it. backup-to-garage / rclone clients fail auth
        # until this has run (verified 2026-08-14: garage healthy but key not
        # imported). Safe to re-run: `key info` exit != 0 -> import.
        garage-provision-keys = lib.mkIf (cfg.s3AccessKeyFile != null && cfg.s3SecretKeyFile != null) {
          description = "Import garage S3 access key and allow buckets";
          after = ["garage.service"];
          requires = ["garage.service"];
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "oneshot";
            User = "garage";
            Group = "garage";
            RemainAfterExit = true;
            ExecStart = provisionScript;
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

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      cfg.rpcPort
      cfg.s3ApiPort
    ];
  };
}
