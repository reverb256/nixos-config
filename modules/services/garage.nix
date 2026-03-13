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
      description = "Shared RPC secret for cluster authentication (must be 32 hex chars)";
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

    # Generate Garage config file
    environment.etc."garage.toml".text = ''
      metadata_dir = "/var/lib/garage/meta"
      data_dir = "/var/lib/garage/data"

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
    '';

    systemd.services.garage = {
      description = "Garage S3-compatible object storage";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = "garage";
        Group = "garage";

        # StateDirectory for data management
        StateDirectory = "garage";
        StateDirectoryMode = "0750";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";  # Strict with StateDirectory
        ProtectHome = true;
        # ReadWritePaths not needed when using StateDirectory

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

    # Firewall - use mkOptionDefault to preserve existing ports
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      cfg.rpcPort    # RPC for cluster communication
      cfg.s3ApiPort  # S3 API
    ];
  };
}
