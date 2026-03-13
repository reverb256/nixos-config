# Garage S3-compatible object storage
# Distributed object storage for cluster
{config, lib, pkgs, ...}: let
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
      description = "Web interface port";
    };

    rpcSecret = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Shared RPC secret for cluster authentication (deprecated: use rpcSecretFile)";
    };

    rpcSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing RPC secret";
    };

    replicationFactor = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Replication factor for stored objects";
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

    # Create data directory via tmpfiles
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 garage garage -"
      "d ${cfg.dataDir}/meta 0750 garage garage -"
      "d ${cfg.dataDir}/data 0750 garage garage -"
    ];

    systemd.services.garage = {
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
        ReadWritePaths = "${cfg.dataDir}";

        # Generate config file
        ExecStartPre = pkgs.writeShellScript "garage-config" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          # Generate config file
          cat > "${cfg.dataDir}/garage.toml" <<'EOF'
        metadata_dir = "${cfg.dataDir}/meta"
        data_dir = "${cfg.dataDir}/data"

        db_engine = "lmdb"

        # RPC configuration
        rpc_bind_addr = "[::]:${toString cfg.rpcPort}"
        rpc_public_addr = "${hostIp}:${toString cfg.rpcPort}"
        EOF

          # Add RPC secret from file or use direct value (deprecated)
          ${lib.optionalString (cfg.rpcSecretFile != null) ''
            if [ -f "${cfg.rpcSecretFile}" ]; then
              RPC_SECRET=$(${pkgs.coreutils}/bin/cat "${cfg.rpcSecretFile}")
              echo "rpc_secret = \"''${RPC_SECRET}\"" >> "${cfg.dataDir}/garage.toml"
            else
              echo "ERROR: RPC secret file not found: ${cfg.rpcSecretFile}"
              exit 1
            fi
          ''} ${lib.optionalString (cfg.rpcSecretFile == null && cfg.rpcSecret != "") ''
            echo "rpc_secret = \"${cfg.rpcSecret}\"" >> "${cfg.dataDir}/garage.toml"
          ''}

          # Add remaining config
          cat >> "${cfg.dataDir}/garage.toml" <<'EOF'

        # S3 API
        [s3_api]
        s3_region = "garage"
        api_bind_addr = "[::]:${toString cfg.s3ApiPort}"
        s3_root_domain = ".s3.garage.cluster"

        # Web interface
        [admin]
        api_bind_addr = "127.0.0.1:${toString cfg.webPort}"

        # Replication
        replication_factor = ${toString cfg.replicationFactor}
        EOF
        '';

        ExecStart = "${pkgs.garage}/bin/garage -c ${cfg.dataDir}/garage.toml server";

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

    # Firewall - use mkOptionDefault to preserve existing ports
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      cfg.rpcPort    # RPC for cluster communication
      cfg.s3ApiPort  # S3 API
    ];
  };
}
